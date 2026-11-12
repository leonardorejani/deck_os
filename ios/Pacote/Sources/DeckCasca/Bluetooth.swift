import Foundation

#if canImport(CryptoKit)

// O canal pelo Bluetooth (fase 7). Igual ao cabo, só leva pedido e resposta, e o roteador do Mac não sabe a
// diferença. O que muda: o fio é aberto ao ar, então só vale depois do aperto de mão cifrado (EnlaceSeguro), e é
// lento (a vazão medida em docs/provas/fase-7-bluetooth.md), então o Mac manda a capa pequena. Duas entradas:
// pareamento (iPhone novo, com o código de 6 dígitos nas duas telas) e reconexão (iPhone já pareado, prova o
// código de acesso). Depois de pareado, o iPhone mantém o Bluetooth conectado mesmo com o cabo plugado, para a
// troca de canal ser instantânea quando o cabo sai.

/// Mantém a conexão Bluetooth com o Mac e conduz o pareamento principal.
public final class GerenteBluetooth: @unchecked Sendable {
    /// Espera entre tentativas de reconectar. Cresce até o teto e volta ao mínimo quando conecta.
    static let esperaMinima: TimeInterval = 1
    static let esperaMaxima: TimeInterval = 15
    /// Rejeitado pelo Mac (código de acesso que ele não reconhece): não adianta insistir a cada segundo.
    static let esperaSeNaoPareado: TimeInterval = 30
    /// Quantas vezes seguidas o Mac já conhecido pode recusar este iPhone antes de o pareamento valer como acabado.
    /// Uma só poderia ser um instante da troca do código de acesso: a segunda, logo em seguida, confirma.
    static let recusasParaEsquecer = 2

    private struct Pendente {
        var pareando: EnlaceSeguro.Pareando
        var mac: MacEncontrado
    }

    private let radio: RadioBle
    private let cofre: Cofre
    private let nomeDoIphone: String
    private let esperaEntreTentativas: (TimeInterval) -> TimeInterval
    private let log: @Sendable (String) -> Void
    private let trava = NSLock()
    private var conexao: ConexaoCabo?
    private var macAtual: MacEncontrado?
    private var laco: Task<Void, Never>?
    private var pendente: Pendente?
    private var aoMudarBt: (@Sendable (MacEncontrado?) -> Void)?
    private var aoNaoReconhecidoBt: (@Sendable () -> Void)?
    /// Sobe a cada parar(): um laço antigo que ainda está terminando não mexe no novo.
    private var geracao = 0

    #if canImport(CoreBluetooth)
    public convenience init(cofre: Cofre, nomeDoIphone: String, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(radio: RadioCentral(log: log), cofre: cofre, nomeDoIphone: nomeDoIphone, log: log)
    }
    #endif

    init(radio: RadioBle, cofre: Cofre, nomeDoIphone: String, esperaEntreTentativas: @escaping (TimeInterval) -> TimeInterval = { $0 },
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.radio = radio
        self.cofre = cofre
        self.nomeDoIphone = nomeDoIphone
        self.esperaEntreTentativas = esperaEntreTentativas
        self.log = log
    }

    /// Chamado quando o Mac se apresenta pelo Bluetooth (com ele) e quando o fio cai (com nil).
    public func aoMudar(_ f: @escaping @Sendable (MacEncontrado?) -> Void) {
        trava.withLock { aoMudarBt = f }
    }

    public func aoNaoReconhecido(_ f: @escaping @Sendable () -> Void) {
        trava.withLock { aoNaoReconhecidoBt = f }
    }

    public var mac: MacEncontrado? { trava.withLock { macAtual } }

    /// Por que o Bluetooth não pode ser usado agora (desligado, sem permissão), ou nil.
    var indisponivel: String? { radio.indisponivel }
    var radioPronto: Bool { radio.pronto }

    // MARK: Reconexão (iPhone já pareado)

    /// Liga a reconexão automática se já tem pareamento. Sem pareamento não faz nada (nem pede permissão de Bluetooth).
    public func iniciar() {
        guard cofre.ler() != nil else { return }
        let ja: Bool = trava.withLock {
            if laco != nil { return true }
            geracao += 1
            let g = geracao
            laco = Task { [self] in await manter(g) }
            return false
        }
        if ja { return }
        log("bluetooth: procurando o Mac pareado")
    }

    /// Pareou (ou esqueceu) agora: liga ou desliga a reconexão conforme o cofre.
    public func reavaliar() {
        if cofre.ler() != nil { iniciar() } else { parar() }
    }

    public func parar() {
        let (l, c): (Task<Void, Never>?, ConexaoCabo?) = trava.withLock {
            let r = (laco, conexao)
            laco = nil
            geracao += 1
            return r
        }
        l?.cancel()
        c?.fechar()
    }

    /// O app voltou ao primeiro plano: o iOS pode ter derrubado a conexão em segundo plano.
    public func retomar() { iniciar() }

    private func manter(_ g: Int) async {
        var espera = Self.esperaMinima
        /// Macs que já disseram não conhecer este iPhone nesta rodada de procura (quando o id ainda não foi guardado).
        var recusados = Set<String>()
        var recusasSeguidas = 0
        defer { trava.withLock { if geracao == g { laco = nil } } }
        while !Task.isCancelled, trava.withLock({ geracao == g }) {
            guard let pareado = cofre.ler() else { break }
            if trava.withLock({ conexao != nil }) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            var alvoAtual: String?
            do {
                let (id, fluxo) = try await conectarNoMac(pareado, excluindo: recusados)
                alvoAtual = id
                let entrada: (fluxo: FluxoCifrado, nomeMac: String)
                do {
                    entrada = try await Task.detached { try EnlaceSeguro.entrar(fluxo, codigoAcesso: pareado.codigoAcesso) }.value
                } catch {
                    fluxo.fechar()
                    throw error
                }
                recusados = []
                recusasSeguidas = 0
                cofre.guardarBluetooth(id)
                log("bluetooth: Mac \"\(entrada.nomeMac)\" conectado (cifrado)")
                ativar(ConexaoCabo(fluxo: entrada.fluxo, segredo: { nil }, confiavel: true, nomeDoCanal: "O Bluetooth"), id: id, nome: entrada.nomeMac)
                espera = Self.esperaMinima
            } catch ErroEnlace.naoPareado {
                // Os dois lados não concordam no código de acesso (o Mac refez o pareamento, por exemplo).
                log("bluetooth: o Mac não reconhece este iPhone")
                if pareado.idBluetooth == nil, let id = alvoAtual {
                    // Pareou pelo cabo e ainda não sabe qual é o Mac: pode ser outro com o Deck por perto. Tenta o próximo já.
                    recusados.insert(id)
                    espera = Self.esperaMinima
                } else {
                    // Mac já conhecido que não reconhece o código: o Mac desconectou este iPhone. Sem canal nenhum, a
                    // página nunca leva um 401 e ficaria em "Mac desconectado" para sempre. Confirma uma vez e avisa.
                    recusasSeguidas += 1
                    if recusasSeguidas >= Self.recusasParaEsquecer {
                        log("bluetooth: o Mac recusou este iPhone \(recusasSeguidas) vezes, o pareamento acabou")
                        let aviso = trava.withLock { aoNaoReconhecidoBt }
                        aviso?()
                        return
                    }
                    espera = Self.esperaMinima
                }
            } catch ErroSemCandidato.todosRecusaram {
                // Pareado só pelo cabo (id do Bluetooth ainda desconhecido): cada Mac por perto já recusou este iPhone nesta
                // rodada. Duas rodadas seguidas assim e o pareamento acabou, senão a tela fica presa em "Mac desconectado".
                recusasSeguidas += 1
                if recusasSeguidas >= Self.recusasParaEsquecer {
                    log("bluetooth: todos os Macs por perto recusaram este iPhone \(recusasSeguidas) vezes, o pareamento acabou")
                    let aviso = trava.withLock { aoNaoReconhecidoBt }
                    aviso?()
                    return
                }
                recusados = []
                espera = Self.esperaSeNaoPareado
            } catch {
                espera = min(espera * 2, Self.esperaMaxima)
            }
            try? await Task.sleep(nanoseconds: UInt64(esperaEntreTentativas(espera) * 1_000_000_000))
        }
    }

    private enum ErroSemCandidato: Error { case todosRecusaram }

    /// Onde conectar: o Mac que já foi usado, ou um dos que o rádio achar com o Deck. O macOS não anuncia o nome
    /// do Deck (o iPhone lê o do sistema), então o nome só desempata e a ordem é o sinal, do mais forte ao mais fraco.
    /// `excluindo` são os que já recusaram este iPhone, para a reconexão chegar ao Mac certo quando há mais de um.
    private func conectarNoMac(_ pareado: Pareado, excluindo recusados: Set<String>) async throws -> (String, FluxoBytes) {
        if let id = pareado.idBluetooth { return (id, try await radio.conectar(id: id)) }
        let busca = Task { () -> [AnuncioBle] in
            for await lista in radio.procurar() where !lista.isEmpty { return lista }
            return []
        }
        let prazo = Task { try? await Task.sleep(nanoseconds: 8_000_000_000); busca.cancel() }
        let achados = await busca.value
        prazo.cancel()
        guard !achados.isEmpty else { throw ErroPareamento.recusado("Nenhum Mac com o Deck por perto.") }
        let candidatos = achados.filter { !recusados.contains($0.id) }.sorted { $0.rssi > $1.rssi }
        guard let alvo = candidatos.first(where: { $0.nome == pareado.nomeMac }) ?? candidatos.first else {
            throw ErroSemCandidato.todosRecusaram
        }
        return (alvo.id, try await radio.conectar(id: alvo.id))
    }

    /// Põe a conexão em uso. O Mac só conta como conectado quando se apresenta (o "ola" dele).
    private func ativar(_ nova: ConexaoCabo, id: String, nome: String) {
        let antiga: ConexaoCabo? = trava.withLock {
            let a = conexao
            conexao = nova
            return a
        }
        antiga?.fechar()
        nova.iniciar(aoOla: { [self] c in apresentou(c, id: id, nome: nome) }, aoFechar: { [self] c in caiu(c) })
    }

    private func apresentou(_ c: ConexaoCabo, id: String, nome: String) {
        let mac = MacEncontrado(id: id, nome: nome, perto: true)
        let aviso: (@Sendable (MacEncontrado?) -> Void)?? = trava.withLock {
            guard conexao === c else { return nil }
            macAtual = mac
            return .some(aoMudarBt)
        }
        guard let aviso else { return }
        aviso?(mac)
    }

    private func caiu(_ c: ConexaoCabo) {
        let aviso: (@Sendable (MacEncontrado?) -> Void)?? = trava.withLock {
            guard conexao === c else { return nil }
            conexao = nil
            macAtual = nil
            return .some(aoMudarBt)
        }
        guard let aviso else { return }
        log("bluetooth: conexão com o Mac caiu")
        aviso?(nil)
    }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal {
        guard let c = trava.withLock({ conexao }) else { throw ErroCanal.semCanal }
        return try await c.enviar(pedido)
    }

    // MARK: Pareamento (iPhone novo)

    /// Os Macs com Deck por perto, a cada mudança. Cancelar a tarefa para a procura.
    func listar() -> AsyncStream<[MacEncontrado]> {
        let origem = radio.procurar()
        return AsyncStream { saida in
            let t = Task {
                for await lista in origem {
                    saida.yield(lista.map { MacEncontrado(id: $0.id, nome: $0.nome, perto: $0.perto) })
                }
                saida.finish()
            }
            saida.onTermination = { _ in t.cancel() }
        }
    }

    /// A pessoa tocou no Mac da lista: conecta, troca as chaves e devolve o código de 6 dígitos que o Mac também mostra.
    func iniciarPareamento(com mac: MacEncontrado) async throws -> String {
        descartarPendente()
        let fluxo = try await radio.conectar(id: mac.id)
        let nome = nomeDoIphone
        do {
            let p = try await Task.detached { try EnlaceSeguro.iniciarPareamento(fluxo, nomeDoIphone: nome) }.value
            trava.withLock { pendente = Pendente(pareando: p, mac: MacEncontrado(id: mac.id, nome: p.nomeMac, perto: true)) }
            return p.codigo
        } catch {
            fluxo.fechar()
            throw ErroPareamento.recusado(Self.texto(error))
        }
    }

    /// A pessoa respondeu no iPhone. Aceito: espera o Mac permitir também e recebe o código de acesso. O fio
    /// do pareamento já está cifrado e vira a conexão em uso, sem apertar a mão de novo.
    func concluirPareamento(aceito: Bool) async throws -> PareamentoFeito {
        guard let p = trava.withLock({ () -> Pendente? in let x = pendente; pendente = nil; return x }) else {
            throw ErroPareamento.recusado("Nenhum pareamento esperando. Procure o Mac de novo.")
        }
        let codigo: String
        do { codigo = try await Task.detached { try EnlaceSeguro.concluir(p.pareando, aceito: aceito) }.value } catch {
            p.pareando.fluxo.fechar()
            throw ErroPareamento.recusado(Self.texto(error))
        }
        log("bluetooth: pareado com \"\(p.mac.nome)\"")
        ativar(ConexaoCabo(fluxo: p.pareando.fluxo, segredo: { nil }, confiavel: true, nomeDoCanal: "O Bluetooth"), id: p.mac.id, nome: p.mac.nome)
        return PareamentoFeito(pareado: Pareado(codigoAcesso: codigo, nomeMac: p.mac.nome, idBluetooth: p.mac.id), canal: CanalBluetooth(self))
    }

    private func descartarPendente() {
        let p: Pendente? = trava.withLock { let x = pendente; pendente = nil; return x }
        p?.pareando.fluxo.fechar()
    }

    private static func texto(_ erro: Error) -> String {
        switch erro {
        case let e as ErroPareamento: return e.mensagem
        case ErroEnlace.recusado(let t): return t
        case ErroEnlace.naoPareado: return "O Mac não reconheceu este iPhone."
        case ErroEnlace.protocolo: return "A conversa com o Mac falhou. Tente de novo."
        default: return "Não consegui parear. Tente de novo."
        }
    }
}

extension GerenteBluetooth: ConexaoBluetooth {
    public func canal() -> any Canal { CanalBluetooth(self) }
}

/// O canal em uso quando o Mac está no Bluetooth. Sem conexão, o pedido falha com `semCanal`.
public struct CanalBluetooth: Canal {
    public let tipo: TipoCanal = .bluetooth
    let gerente: GerenteBluetooth

    public init(_ gerente: GerenteBluetooth) { self.gerente = gerente }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal { try await gerente.enviar(pedido) }
}

/// O pareador do app: o pareamento principal (Bluetooth, código igual nas duas telas) e a segunda via (cabo,
/// código digitado no iPhone).
public struct PareadorCompleto: Pareador {
    let cabo: PareadorCabo
    let bluetooth: GerenteBluetooth

    public init(cabo: GerenteDoCabo, bluetooth: GerenteBluetooth) {
        self.cabo = PareadorCabo(cabo)
        self.bluetooth = bluetooth
    }

    public func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> { bluetooth.listar() }
    public func iniciar(com mac: MacEncontrado) async throws -> String { try await bluetooth.iniciarPareamento(com: mac) }
    public func concluir(aceito: Bool) async throws -> PareamentoFeito { try await bluetooth.concluirPareamento(aceito: aceito) }
    public func procurarNoCabo() -> AsyncStream<MacEncontrado> { cabo.procurarNoCabo() }
    public func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        try await cabo.parearComCodigo(mac, codigo)
    }

    /// O rádio leva um instante para dizer se está ligado e liberado: dá 1,5 s antes de avisar.
    public func avisoDaProcura() async -> String? {
        for _ in 0..<15 {
            if let motivo = bluetooth.indisponivel { return motivo }
            if bluetooth.radioPronto { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
}

#endif
