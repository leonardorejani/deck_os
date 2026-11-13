import Foundation

/// O que uma tecla de comando está fazendo agora, para o painel do iPhone mostrar "Ligando...", "Desligando..." ou
/// "Rodando..." em vez de esperar o comando acabar dentro do pedido. `fase` é "ligando", "desligando", "rodando" ou
/// "falhou" (só por um tempo, com o motivo em `erro`, para o iPhone avisar uma vez).
struct AndamentoDeTecla: Codable, Equatable, Sendable {
    var fase: String
    var erro: String? = nil
    /// Hora em que o comando falhou (ISO 8601). Só em "falhou": o painel usa para avisar uma vez só.
    var fim: String? = nil
}

/// As teclas de comando que estão rodando soltas (sem prazo de pedido) e a última falha de cada uma.
final class ComandosEmAndamento: @unchecked Sendable {
    /// A do Deck: o `ExecutorAcoes` que atende o iPhone e o Agregador que monta o estado enxergam a mesma.
    static let compartilhado = ComandosEmAndamento()
    /// Quanto tempo a falha de um comando solto fica no estado.
    static let validadeDaFalha: TimeInterval = 30

    private let trava = NSLock()
    private var itens: [String: AndamentoDeTecla] = [:]
    private var falhouEm: [String: Date] = [:]

    func fase(de id: String) -> String? {
        trava.lock(); defer { trava.unlock() }
        guard let f = itens[id]?.fase, f != "falhou" else { return nil }
        return f
    }

    /// Marca o começo. Falso se a tecla já tem um comando rodando.
    func comecar(_ id: String, fase: String) -> Bool {
        trava.lock(); defer { trava.unlock() }
        if let f = itens[id]?.fase, f != "falhou" { return false }
        itens[id] = AndamentoDeTecla(fase: fase)
        falhouEm[id] = nil
        return true
    }

    /// Terminou. `lembrarFalha`: o pedido já respondeu sem esperar, então o erro só chega ao iPhone pelo estado.
    func terminar(_ id: String, erro: String?, lembrarFalha: Bool, agora: Date = Date()) {
        trava.lock(); defer { trava.unlock() }
        if let erro, lembrarFalha {
            itens[id] = AndamentoDeTecla(fase: "falhou", erro: erro, fim: Datas.iso(agora))
            falhouEm[id] = agora
        } else {
            itens[id] = nil
            falhouEm[id] = nil
        }
    }

    func foto(agora: Date = Date()) -> [String: AndamentoDeTecla] {
        trava.lock(); defer { trava.unlock() }
        for (id, quando) in falhouEm where agora.timeIntervalSince(quando) > Self.validadeDaFalha {
            itens[id] = nil; falhouEm[id] = nil
        }
        return itens
    }
}

/// Entre o pedido que espera um pouco e o comando que segue rodando: quem chega primeiro decide quem entrega o resultado.
private final class Corrida: @unchecked Sendable {
    private let trava = NSLock()
    private var soltou = false
    private var erro: String??
    /// O comando acabou. Devolve verdadeiro se o pedido já tinha ido embora (o erro vai pelo estado).
    func terminou(_ e: String?) -> Bool {
        trava.lock(); defer { trava.unlock() }
        if soltou { return true }
        erro = .some(e)
        return false
    }
    /// O pedido cansou de esperar. Devolve o resultado se o comando acabou nesse meio tempo.
    func soltar() -> String?? {
        trava.lock(); defer { trava.unlock() }
        if let e = erro { return e }
        soltou = true
        return nil
    }
}

extension ExecutorAcoes {
    /// Tecla de comando. O comando roda solto, sem prazo de pedido e sem ser derrubado aos 10 s: o pedido do iPhone espera
    /// só `graca` segundos. Acabou nesse tempo, responde como sempre (erro em texto ou nil). Não acabou, responde nil na
    /// hora e o comando segue até o fim: o estado da tecla mostra "ligando", "desligando" ou "rodando", vira ligado ou
    /// desligado pelo código de saída e a falha chega pelo estado (`ComandosEmAndamento`).
    func rodarSolto(_ tecla: Tecla, ligar: String) -> String? {
        let ligadaAgora = tecla.ligaEDesliga ? (tecla.comandoQueConfere.map { conferir($0) } ?? memoria.ligada(tecla.id)) : false
        let comando = ligadaAgora ? (tecla.desligar ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ligar
        let fase = !tecla.ligaEDesliga ? "rodando" : ligadaAgora ? "desligando" : "ligando"
        guard andamento.comecar(tecla.id, fase: fase) else {
            return "\(tecla.nome) ainda está \(andamento.fase(de: tecla.id) ?? fase). Espere terminar."
        }
        let corrida = Corrida()
        let pronto = DispatchSemaphore(value: 0)
        let guardaEstado = tecla.ligaEDesliga && tecla.comandoQueConfere == nil
        DispatchQueue.global(qos: .userInitiated).async {
            let erro = self.rodarComando(comando, segundos: self.tetoSegundos)
            // O estado guardado muda antes de o "ligando" sair, para o painel nunca ver o meio do caminho.
            if erro == nil, guardaEstado { self.memoria.definir(tecla.id, ligada: !ligadaAgora) }
            let foiEmbora = corrida.terminou(erro)
            self.andamento.terminar(tecla.id, erro: erro, lembrarFalha: foiEmbora)
            pronto.signal()
        }
        _ = pronto.wait(timeout: .now() + graca)
        // Acabou: devolve o resultado. Não acabou: o pedido responde nil e o comando segue solto.
        return corrida.soltar().flatMap { $0 }
    }
}
