#if canImport(Network)
import Foundation
import Network

/// O redirecionamento local do login do Spotify: o navegador volta para `http://127.0.0.1:<porta>/retorno`,
/// que é este Mac falando com ele mesmo. A porta só abre durante o login e só no loopback (o resto da
/// rede de casa não alcança). O Spotify aceita http só em endereço de loopback, e `localhost` não vale.
final class RetornoLocal: @unchecked Sendable {
    /// Fixa, para a pessoa registrar o endereço exato no site do Spotify uma vez só.
    static let portaPadrao: UInt16 = 4778
    static let caminho = "/retorno"

    static func endereco(porta: UInt16) -> String { "http://127.0.0.1:\(porta)\(caminho)" }

    private let porta: UInt16
    private var listener: NWListener?
    private let fila = DispatchQueue(label: "deck.retorno-spotify")

    /// Porta 0 deixa o sistema escolher (os testes).
    init(porta: UInt16 = RetornoLocal.portaPadrao) { self.porta = porta }

    /// Abre a porta e devolve a que ficou em uso. `aoReceber` roda uma vez por retorno válido do Spotify.
    func iniciar(aoReceber: @escaping @Sendable (RetornoLogin) -> Void) throws -> UInt16 {
        let params = NWParameters.tcp
        guard let p = NWEndpoint.Port(rawValue: porta) else { throw ErroServidor(description: "Porta inválida: \(porta).") }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: p)
        let l = try NWListener(using: params)
        let sinal = DispatchSemaphore(value: 0)
        let caixa = Caixa()
        l.stateUpdateHandler = { estado in
            switch estado {
            case .ready: if caixa.fechar(nil) { sinal.signal() }
            case .failed(let e): if caixa.fechar("\(e)") { sinal.signal() }
            default: break
            }
        }
        l.newConnectionHandler = { conexao in
            Atendimento(conexao: conexao, aoReceber: aoReceber).iniciar()
        }
        l.start(queue: fila)
        if sinal.wait(timeout: .now() + 5) == .timedOut { l.cancel(); throw ErroServidor(description: "A porta do retorno do Spotify demorou a abrir.") }
        if let falha = caixa.erro {
            l.cancel()
            throw ErroServidor(description: "Não consegui abrir a porta \(porta) para o retorno do Spotify (\(falha)). Feche o que está usando essa porta e tente de novo.")
        }
        listener = l
        return l.port?.rawValue ?? porta
    }

    func parar() {
        listener?.cancel()
        listener = nil
    }

    /// Lê o pedido do navegador. nil: não é o retorno (favicon, outra rota).
    static func interpretar(_ r: HttpRequisicao) -> RetornoLogin? {
        guard r.metodo == "GET", r.caminho == caminho else { return nil }
        return RetornoLogin(codigo: r.query["code"], estado: r.query["state"], erro: r.query["error"])
    }

    static let paginaFinal = """
        <!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\
        <meta name="referrer" content="no-referrer"><title>Deck</title>\
        <body style="font:16px -apple-system,system-ui,sans-serif;background:#0b0b0c;color:#f2f2f3;display:grid;place-items:center;height:100vh;margin:0">\
        <p>Pronto. Pode fechar esta aba e voltar ao Deck.</p></body></html>
        """

    private final class Caixa: @unchecked Sendable {
        private let trava = NSLock()
        private var feito = false
        private(set) var erro: String?
        func fechar(_ e: String?) -> Bool {
            trava.lock(); defer { trava.unlock() }
            if feito { return false }
            feito = true; erro = e
            return true
        }
    }

    private final class Atendimento: @unchecked Sendable {
        private let conexao: NWConnection
        private let aoReceber: @Sendable (RetornoLogin) -> Void
        private let fila = DispatchQueue(label: "deck.retorno-spotify.conexao")
        private var buffer = Data()

        init(conexao: NWConnection, aoReceber: @escaping @Sendable (RetornoLogin) -> Void) {
            self.conexao = conexao
            self.aoReceber = aoReceber
        }

        func iniciar() {
            conexao.start(queue: fila)
            fila.asyncAfter(deadline: .now() + 10) { [conexao] in conexao.cancel() }
            ler()
        }

        private func ler() {
            conexao.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] dados, _, fim, erro in
                if let dados { buffer.append(dados) }
                switch Http.ler(buffer) {
                case .ok(let req):
                    if let retorno = RetornoLocal.interpretar(req) {
                        enviar(200, RetornoLocal.paginaFinal)
                        aoReceber(retorno)
                    } else {
                        enviar(404, "")
                    }
                case .invalido:
                    enviar(400, "")
                case .incompleto:
                    if erro != nil || fim { conexao.cancel() } else { ler() }
                }
            }
        }

        private func enviar(_ status: Int, _ html: String) {
            let resposta = Http.resposta(status: status, tipo: "text/html; charset=utf-8", corpo: Data(html.utf8),
                                         extras: ["Cache-Control": "no-store", "Referrer-Policy": "no-referrer"])
            conexao.send(content: resposta, contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { [conexao] _ in conexao.cancel() })
        }
    }
}
#endif
