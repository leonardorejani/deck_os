import Foundation

/// Atende a chamada do gancho PermissionRequest: lê o pedido, abre um pedido de aprovação e espera o iPhone responder.
/// Só a regra, sem rede, para testar sem porta.
struct TratadorDoGancho: Sendable {
    let aprovacoes: Aprovacoes
    let segredo: String
    var prazo: TimeInterval = Aprovacoes.prazoPadrao

    /// Abre o pedido. Nil quando o gancho não deve esperar: método ou caminho errado, segredo errado, entrada que o iPhone não
    /// responde, sem iPhone recente ou fila cheia. Em todos esses casos a resposta é vazia e o terminal pergunta como sempre.
    func abrir(_ r: HttpRequisicao) -> Aprovacoes.Pendente? {
        guard r.metodo == "POST", r.caminho == GanchoInstalador.caminho,
              let recebido = r.cabecalhos[SegredoDoGancho.cabecalho.lowercased()], Autenticacao.igual(recebido, segredo),
              let e = GanchoDoClaude.ler(r.corpo) else { return nil }
        return aprovacoes.abrir(projeto: e.projeto, ferramenta: e.ferramenta, titulo: e.titulo, resumo: e.resumo, prazo: prazo)
    }

    /// Decisão: o JSON que o Claude Code espera. Sem decisão: 204 sem corpo, o gancho não imprime nada.
    static func resposta(_ d: DecisaoDeAprovacao?) -> RespostaRota {
        guard let d else { return RespostaRota(status: 204, tipo: "text/plain", corpo: Data()) }
        return RespostaRota.json(200, GanchoDoClaude.saida(d))
    }
}

#if canImport(Network)
import Network

/// O servidor do gancho: só no loopback (nenhum outro aparelho da rede chega nele), HTTP puro e uma porta só dele, separada
/// da do painel. A chamada fica aberta até o iPhone responder ou o prazo acabar. Se quem chamou desistir (o terminal respondeu
/// antes e o Claude Code encerrou o gancho), a conexão cai e o pedido some do iPhone.
final class ServidorDoGancho: @unchecked Sendable {
    private let tratador: TratadorDoGancho
    let porta: UInt16
    private var listener: NWListener?
    private let fila = DispatchQueue(label: "deck.gancho")

    init(tratador: TratadorDoGancho, porta: UInt16) {
        self.tratador = tratador
        self.porta = porta
    }

    func iniciar() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let p = NWEndpoint.Port(rawValue: porta) else { throw ErroServidor(description: "Porta inválida: \(porta).") }
        let l = try NWListener(using: params, on: p)
        let tratador = self.tratador
        l.newConnectionHandler = { conexao in AtendimentoDoGancho(conexao: conexao, tratador: tratador).iniciar() }
        let sinal = DispatchSemaphore(value: 0)
        let caixa = CaixaDeFalha()
        l.stateUpdateHandler = { estado in
            switch estado {
            case .ready: if caixa.fechar(nil) { sinal.signal() }
            case .failed(let e): if caixa.fechar("Não consegui abrir a porta do gancho (\(self.porta)): \(e)") { sinal.signal() }
            default: break
            }
        }
        l.start(queue: fila)
        if sinal.wait(timeout: .now() + 5) == .timedOut { l.cancel(); throw ErroServidor(description: "O gancho demorou demais para abrir a porta \(porta).") }
        if let erro = caixa.erro { l.cancel(); throw ErroServidor(description: erro) }
        listener = l
    }

    func parar() { listener?.cancel(); listener = nil }
}

private final class CaixaDeFalha: @unchecked Sendable {
    private let trava = NSLock()
    private var fechado = false
    private(set) var erro: String?
    func fechar(_ e: String?) -> Bool {
        trava.lock(); defer { trava.unlock() }
        if fechado { return false }
        fechado = true; erro = e
        return true
    }
}

private final class AtendimentoDoGancho: @unchecked Sendable {
    private let conexao: NWConnection
    private let tratador: TratadorDoGancho
    private let fila = DispatchQueue(label: "deck.gancho.conexao")
    private var buffer = Data()
    private var respondeu = false

    init(conexao: NWConnection, tratador: TratadorDoGancho) {
        self.conexao = conexao
        self.tratador = tratador
    }

    func iniciar() {
        conexao.start(queue: fila)
        // Quem abre e não manda o pedido não prende a porta. Depois de lido, quem manda é o prazo do pedido.
        fila.asyncAfter(deadline: .now() + 10) { [self] in if buffer.isEmpty || !lido { conexao.cancel() } }
        ler()
    }

    private var lido = false

    private func ler() {
        conexao.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] dados, _, fim, erro in
            if let dados { buffer.append(dados) }
            switch Http.ler(buffer) {
            case .ok(let req): lido = true; atender(req)
            case .invalido: enviar(TratadorDoGancho.resposta(nil))
            case .incompleto: if erro != nil || fim { conexao.cancel() } else { ler() }
            }
        }
    }

    private func atender(_ req: HttpRequisicao) {
        guard let pendente = tratador.abrir(req) else { return enviar(TratadorDoGancho.resposta(nil)) }
        let aprovacoes = tratador.aprovacoes
        vigiar(pendente.id, aprovacoes)
        DispatchQueue.global().async { [self] in
            enviar(TratadorDoGancho.resposta(aprovacoes.esperar(pendente)))
        }
    }

    /// Quando a conexão cai (o terminal respondeu e o gancho foi encerrado), o pedido deixa de existir.
    private func vigiar(_ id: String, _ aprovacoes: Aprovacoes) {
        conexao.receive(minimumIncompleteLength: 1, maximumLength: 1) { [self] _, _, fim, erro in
            if fim || erro != nil { aprovacoes.cancelar(id) } else { vigiar(id, aprovacoes) }
        }
    }

    private func enviar(_ r: RespostaRota) {
        fila.async { [self] in
            guard !respondeu else { return }
            respondeu = true
            conexao.send(content: r.serializar(), contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { [conexao] _ in conexao.cancel() })
        }
    }
}
#endif
