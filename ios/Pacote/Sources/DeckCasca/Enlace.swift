import Foundation

// Peças do Bluetooth que não dependem de rádio nem de criptografia, para compilar e testar no Linux do CI.
// O Bluetooth LE é um fio de bytes como o cabo: o Mac é o periférico (anuncia o serviço do Deck) e o iPhone
// é a central. O iPhone escreve na característica de pedido e o Mac responde por notificações na de resposta,
// e os dois lados enxergam isso como um FluxoBytes. O espelho disto no Mac é
// mac/Nucleo/Enlace.swift: mudou aqui, muda lá.

enum EnlaceBle {
    /// Serviço que o Mac anuncia. O iPhone só procura por ele.
    static let servico = "DECC0001-6D8F-4B1E-9A53-5E1A7C0D0001"
    /// O iPhone escreve aqui (sem resposta, para a vazão ser a maior possível).
    static let pedido = "DECC0002-6D8F-4B1E-9A53-5E1A7C0D0001"
    /// O Mac notifica aqui. Quem assina é quem abre a sessão.
    static let resposta = "DECC0003-6D8F-4B1E-9A53-5E1A7C0D0001"
}

/// Fila de bytes com leitura que espera. A escrita vem do rádio (callback), a leitura da thread da sessão.
final class FilaDeBytes: @unchecked Sendable {
    private let condicao = NSCondition()
    private var blocos: [Data] = []
    private var fechada = false

    func empurrar(_ dados: Data) {
        guard !dados.isEmpty else { return }
        condicao.lock()
        if !fechada { blocos.append(dados) }
        condicao.signal()
        condicao.unlock()
    }

    /// Espera chegar algo e devolve no máximo `maximo` bytes. nil quando a fila fechou e esvaziou.
    func ler(maximo: Int) -> Data? {
        condicao.lock(); defer { condicao.unlock() }
        while blocos.isEmpty {
            if fechada { return nil }
            condicao.wait()
        }
        let primeiro = blocos[0]
        if primeiro.count <= maximo {
            blocos.removeFirst()
            return primeiro
        }
        blocos[0] = primeiro.dropFirst(maximo)
        return primeiro.prefix(maximo)
    }

    var estaFechada: Bool { condicao.lock(); defer { condicao.unlock() }; return fechada }

    func fechar() {
        condicao.lock()
        fechada = true
        condicao.broadcast()
        condicao.unlock()
    }
}

/// Um fio de Bluetooth: o que o rádio recebe entra por `fila`, e o que a sessão escreve sai por `escritor`
/// (que parte em pacotes do tamanho do MTU e espera o rádio liberar).
final class FluxoEnlace: FluxoBytes, @unchecked Sendable {
    let fila = FilaDeBytes()
    private let escritor: @Sendable (Data) -> Bool
    private let aoFechar: @Sendable () -> Void
    private let trava = NSLock()
    private var fechado = false

    init(escritor: @escaping @Sendable (Data) -> Bool, aoFechar: @escaping @Sendable () -> Void = {}) {
        self.escritor = escritor
        self.aoFechar = aoFechar
    }

    func ler(maximo: Int) -> Data? { fila.ler(maximo: maximo) }

    func escrever(_ dados: Data) -> Bool {
        trava.lock(); let fim = fechado; trava.unlock()
        return !fim && escritor(dados)
    }

    func fechar() {
        trava.lock()
        let jaFechado = fechado
        fechado = true
        trava.unlock()
        fila.fechar()
        if !jaFechado { aoFechar() }
    }

    /// Dois fios ligados de ponta a ponta, sem rádio: o que um escreve o outro lê. Para os testes.
    static func par() -> (FluxoEnlace, FluxoEnlace) {
        final class Ponta: @unchecked Sendable { var fluxo: FluxoEnlace? }
        let a = Ponta(), b = Ponta()
        let fa = FluxoEnlace(escritor: { b.fluxo?.fila.empurrar($0); return true }, aoFechar: { b.fluxo?.fila.fechar() })
        let fb = FluxoEnlace(escritor: { a.fluxo?.fila.empurrar($0); return true }, aoFechar: { a.fluxo?.fila.fechar() })
        a.fluxo = fa
        b.fluxo = fb
        return (fa, fb)
    }
}

/// O código de 6 dígitos que o Mac e o iPhone mostram para a pessoa conferir (comparação numérica, como o
/// Bluetooth faz). Sai de tudo que os dois trocaram, então quem está no meio e troca uma chave pela dele
/// deixa os dois lados com códigos diferentes. O Mac se compromete com a chave dele antes de ver a do iPhone
/// (`compromisso`), senão o intruso poderia sortear chaves até os 6 dígitos baterem.
enum Sas {
    /// O que o Mac manda primeiro: um hash da chave pública e do nonce dele, que só abre depois.
    static func compromisso(chavePublica: Data, nonce: Data) -> Data {
        Data(ProvaCabo.sha256(campos([Data("deck-ble-compromisso-v1".utf8), chavePublica, nonce])))
    }

    /// Tudo que foi trocado, com o tamanho de cada pedaço na frente para dois pedaços não se confundirem.
    static func transcricao(modo: String, chaveIphone: Data, nonceIphone: Data, chaveMac: Data, nonceMac: Data, nomeMac: String) -> Data {
        Data(ProvaCabo.sha256(campos([Data("deck-ble-transcricao-v1".utf8), Data(modo.utf8), chaveIphone, nonceIphone, chaveMac, nonceMac, Data(nomeMac.utf8)])))
    }

    /// Seis dígitos da transcrição: os 4 primeiros bytes do hash, módulo um milhão.
    static func digitos(_ transcricao: Data) -> String {
        let h = ProvaCabo.sha256(campos([Data("deck-ble-sas-v1".utf8), transcricao]))
        let n = h.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return String(format: "%06d", n % 1_000_000)
    }

    private static func campos(_ partes: [Data]) -> [UInt8] {
        var saida: [UInt8] = []
        for p in partes {
            let n = UInt32(p.count)
            saida += [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)]
            saida += p
        }
        return saida
    }
}
