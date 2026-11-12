#if canImport(Network)
import Foundation
import Network
import Security

struct ErroServidor: Error, CustomStringConvertible {
    var description: String
}

/// Primeira porta de entrada do Deck: HTTPS na rede local. Só traduz bytes em HttpRequisicao e
/// de volta, o que responder é do Roteador (o cabo e o Bluetooth vão reaproveitar o mesmo).
final class ServidorHttps: @unchecked Sendable {
    private let roteador: Roteador
    private let identidade: SecIdentity
    let porta: UInt16
    /// Só no loopback (a bancada): o servidor não aparece para outros aparelhos da rede.
    let somenteLocal: Bool
    private var listener: NWListener?
    private let fila = DispatchQueue(label: "deck.servidor")

    init(roteador: Roteador, identidade: SecIdentity, porta: UInt16, somenteLocal: Bool = false) {
        self.somenteLocal = somenteLocal
        self.roteador = roteador
        self.identidade = identidade
        self.porta = porta
    }

    static func parametros(tls: NWProtocolTLS.Options, somenteLocal: Bool) -> NWParameters {
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        if somenteLocal { params.requiredInterfaceType = .loopback }
        return params
    }

    /// Começa a escutar em todas as interfaces e só volta quando a porta está aberta ou falhou.
    func iniciar() throws {
        let tls = NWProtocolTLS.Options()
        guard let id = sec_identity_create(identidade) else {
            throw ErroServidor(description: "O macOS não aceitou o certificado do servidor.")
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, id)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let params = Self.parametros(tls: tls, somenteLocal: somenteLocal)
        guard let p = NWEndpoint.Port(rawValue: porta) else {
            throw ErroServidor(description: "Porta inválida: \(porta).")
        }
        let l = try NWListener(using: params, on: p)

        let sinal = DispatchSemaphore(value: 0)
        let resultado = Resultado()
        l.stateUpdateHandler = { estado in
            switch estado {
            case .ready:
                if resultado.definir(nil) { sinal.signal() }
            case .failed(let e):
                if resultado.definir("Não consegui abrir a porta \(self.porta): \(e)") { sinal.signal() }
            default: break
            }
        }
        let roteador = self.roteador
        l.newConnectionHandler = { conexao in
            Atendimento(conexao: conexao, roteador: roteador).iniciar()
        }
        l.start(queue: fila)
        if sinal.wait(timeout: .now() + 5) == .timedOut {
            l.cancel()
            throw ErroServidor(description: "O servidor demorou demais para abrir a porta \(porta).")
        }
        if let erro = resultado.erro {
            l.cancel()
            throw ErroServidor(description: erro)
        }
        listener = l
    }

    func parar() {
        listener?.cancel()
        listener = nil
    }
}

/// Guarda o primeiro resultado do listener (pronto ou falha), já que o handler pode disparar de novo.
private final class Resultado: @unchecked Sendable {
    private let trava = NSLock()
    private var definido = false
    private(set) var erro: String?

    func definir(_ e: String?) -> Bool {
        trava.lock(); defer { trava.unlock() }
        if definido { return false }
        definido = true
        erro = e
        return true
    }
}

/// Uma conexão: acumula bytes até a requisição fechar, responde e encerra (Connection: close).
private final class Atendimento: @unchecked Sendable {
    private let conexao: NWConnection
    private let roteador: Roteador
    private let fila = DispatchQueue(label: "deck.conexao")
    private var buffer = Data()

    init(conexao: NWConnection, roteador: Roteador) {
        self.conexao = conexao
        self.roteador = roteador
    }

    func iniciar() {
        conexao.start(queue: fila)
        // Conexão que abre e não manda nada (ou manda devagar demais) não prende o servidor.
        fila.asyncAfter(deadline: .now() + 10) { [conexao] in conexao.cancel() }
        ler()
    }

    private func ler() {
        conexao.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] dados, _, fim, erro in
            if let dados { buffer.append(dados) }
            switch Http.ler(buffer) {
            case .ok(let req):
                enviar(roteador.responder(req))
            case .invalido:
                enviar(.erro(400, "Pedido inválido."))
            case .incompleto:
                if erro != nil || fim { conexao.cancel() } else { ler() }
            }
        }
    }

    private func enviar(_ r: RespostaRota) {
        conexao.send(content: r.serializar(), contentContext: .finalMessage, isComplete: true,
                     completion: .contentProcessed { [conexao] _ in conexao.cancel() })
    }
}
#endif
