#if canImport(Network)
import Foundation
import Network

/// A porta de fora: HTTP simples (sem TLS, para o curl de um script não precisar de certificado) que só abre em 127.0.0.1.
/// Quem manda é um programa neste mesmo Mac, nunca outro aparelho da rede. Quem decide o que responder é o RoteadorDeFora.
final class ServidorDeFora: @unchecked Sendable {
    private let roteador: RoteadorDeFora
    let porta: UInt16
    private var listener: NWListener?
    private let fila = DispatchQueue(label: "deck.fora")

    init(roteador: RoteadorDeFora, porta: UInt16) {
        self.roteador = roteador
        self.porta = porta
    }

    /// Primeira porta livre a partir de `preferida` (até 10 vizinhas). Devolve o servidor ligado.
    static func ligar(roteador: RoteadorDeFora, preferida: UInt16) throws -> ServidorDeFora {
        var ultimo: Error = ErroServidor(description: "Não achei uma porta livre para os avisos de fora.")
        for p in preferida..<(preferida &+ 10) {
            let s = ServidorDeFora(roteador: roteador, porta: p)
            do { try s.iniciar(); return s } catch { ultimo = error }
        }
        throw ultimo
    }

    func iniciar() throws {
        guard let p = NWEndpoint.Port(rawValue: porta) else { throw ErroServidor(description: "Porta inválida: \(porta).") }
        let params = NWParameters.tcp
        // Preso ao 127.0.0.1: nenhuma outra interface do Mac enxerga esta porta.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: p)
        params.allowLocalEndpointReuse = false
        let l = try NWListener(using: params)
        let sinal = DispatchSemaphore(value: 0)
        let falha = Caixa()
        l.stateUpdateHandler = { estado in
            switch estado {
            case .ready: if falha.definir(nil) { sinal.signal() }
            case .failed(let e): if falha.definir("Não consegui abrir a porta \(self.porta): \(e)") { sinal.signal() }
            default: break
            }
        }
        let roteador = self.roteador
        l.newConnectionHandler = { conexao in Atendimento(conexao: conexao, roteador: roteador).iniciar() }
        l.start(queue: fila)
        if sinal.wait(timeout: .now() + 5) == .timedOut { l.cancel(); throw ErroServidor(description: "A porta \(porta) demorou demais para abrir.") }
        if let erro = falha.erro { l.cancel(); throw ErroServidor(description: erro) }
        listener = l
    }

    func parar() { listener?.cancel(); listener = nil }

    private final class Caixa: @unchecked Sendable {
        private let trava = NSLock()
        private var definido = false
        private(set) var erro: String?
        func definir(_ e: String?) -> Bool {
            trava.lock(); defer { trava.unlock() }
            if definido { return false }
            definido = true; erro = e
            return true
        }
    }

    /// Uma conexão: acumula bytes até o pedido fechar, responde e encerra.
    private final class Atendimento: @unchecked Sendable {
        private let conexao: NWConnection
        private let roteador: RoteadorDeFora
        private let fila = DispatchQueue(label: "deck.fora.conexao")
        private var buffer = Data()

        init(conexao: NWConnection, roteador: RoteadorDeFora) { self.conexao = conexao; self.roteador = roteador }

        func iniciar() {
            conexao.start(queue: fila)
            // Conexão que abre e não manda nada não prende a porta.
            fila.asyncAfter(deadline: .now() + 5) { [conexao] in conexao.cancel() }
            ler()
        }

        private func ler() {
            conexao.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] dados, _, fim, erro in
                if let dados { buffer.append(dados) }
                // Pedido maior que o limite nem termina de ser lido: o corpo máximo é de 4 KB.
                if buffer.count > ArmazemDeAvisos.maxCorpo + 8 * 1024 { return enviar(.erro(413, "O pedido é grande demais.")) }
                switch Http.ler(buffer) {
                case .ok(let req): enviar(roteador.responder(req))
                case .invalido: enviar(.erro(400, "Pedido inválido."))
                case .incompleto: if erro != nil || fim { conexao.cancel() } else { ler() }
                }
            }
        }

        private func enviar(_ r: RespostaRota) {
            conexao.send(content: r.serializar(), contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { [conexao] _ in conexao.cancel() })
        }
    }
}
#endif
