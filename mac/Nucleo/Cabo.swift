import Foundation

// Segunda porta de entrada do Deck: o cabo USB. Igual ao HTTPS, só traduz o canal em HttpRequisicao e
// de volta, e quem responde é o mesmo Roteador. Aqui o Mac abre a conexão (pelo usbmuxd) até o app do
// iPhone, que escuta numa porta fixa do próprio aparelho, e depois atende os pedidos que o iPhone manda
// pelo mesmo fio.

/// Uma conexão viva com um iPhone. `rodar` só volta quando o fio acaba.
final class SessaoCabo: @unchecked Sendable {
    static let intervaloDoPing: TimeInterval = 5
    /// Pedidos andando ao mesmo tempo. O painel faz poucos por segundo: passou disso, algo está errado.
    static let limiteSimultaneo = 32

    private let fluxo: FluxoBytes
    private let roteador: Roteador
    private let nomeMac: String
    private let rotulo: String
    private let log: @Sendable (String) -> Void
    private let intervaloDoPing: TimeInterval
    /// Deixa o canal mexer na resposta antes de ir pelo fio (o Bluetooth troca a capa grande por uma pequena).
    private let ajustar: (@Sendable (PedidoCabo, RespostaRota) -> RespostaRota)?
    /// Avisa quem ligou a sessão que um pedido foi respondido (o app do Mac usa para saber o canal em uso).
    private let aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)?
    private let trava = NSLock()
    private let escrita = NSLock()
    private var emAndamento = 0
    private var acabou = false

    init(fluxo: FluxoBytes, roteador: Roteador, nomeMac: String, rotulo: String, intervaloDoPing: TimeInterval = SessaoCabo.intervaloDoPing,
         log: @escaping @Sendable (String) -> Void, ajustar: (@Sendable (PedidoCabo, RespostaRota) -> RespostaRota)? = nil,
         aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)? = nil) {
        self.ajustar = ajustar
        self.aoAtender = aoAtender
        self.intervaloDoPing = intervaloDoPing
        self.fluxo = fluxo
        self.roteador = roteador
        self.nomeMac = nomeMac
        self.rotulo = rotulo
        self.log = log
    }

    func rodar() {
        defer { encerrar() }
        guard enviar(MensagemCabo(tipo: "ola", nome: nomeMac, versao: Quadros.versao)) else { return }
        agendarPing()
        while let m = Quadros.ler(de: fluxo) {
            if m.tipo == "desafio" { responderDesafio(m); continue }
            guard m.tipo == "pedido", let id = m.id, let pedido = m.pedido else { continue }
            if reservar() {
                DispatchQueue.global().async { [self] in
                    atender(id, pedido)
                    liberar()
                }
            } else {
                _ = enviar(MensagemCabo(tipo: "resposta", id: id, resposta: Self.resposta(.erro(429, "Pedidos demais ao mesmo tempo."))))
            }
        }
    }

    func encerrar() {
        trava.lock(); acabou = true; trava.unlock()
        fluxo.fechar()
    }

    // MARK: Desafio

    /// O iPhone só confia em quem prova que conhece o código de acesso (ou os 6 dígitos do pareamento em
    /// curso), porque qualquer app do aparelho consegue conectar na porta dele. Sem segredo para o modo
    /// pedido, responde sem prova: o iPhone entende que não há o que provar e não manda nada sensível.
    private func responderDesafio(_ d: MensagemCabo) {
        guard let nonce = d.nonce, !nonce.isEmpty, nonce.count <= 128, let modo = d.modo else { return }
        let chave: String?
        switch modo {
        case ProvaCabo.modoAcesso: chave = roteador.config.ler().codigoAcesso
        case ProvaCabo.modoCodigo: chave = roteador.pareamento.vigente()
        default: return
        }
        let prova = chave.map { ProvaCabo.prova(chave: $0, modo: modo, nonce: nonce, nomeMac: nomeMac) }
        _ = enviar(MensagemCabo(tipo: "ola", nome: nomeMac, versao: Quadros.versao, nonce: nonce, modo: modo, prova: prova))
    }

    // MARK: Pedidos

    private func atender(_ id: Int, _ pedido: PedidoCabo) {
        let inicio = Date()
        var resposta = responder(pedido)
        if let ajustar { resposta = ajustar(pedido, resposta) }
        _ = enviar(MensagemCabo(tipo: "resposta", id: id, resposta: Self.resposta(resposta)))
        // Só o caminho vai para o log: a query pode levar o código de acesso (a capa).
        log("cabo \(rotulo) \(pedido.metodo) \(pedido.caminho) \(resposta.status) \(Int(Date().timeIntervalSince(inicio) * 1000)) ms")
        aoAtender?(rotulo, pedido.caminho, resposta.status)
    }

    private func responder(_ p: PedidoCabo) -> RespostaRota {
        guard p.caminho.hasPrefix("/"), !p.metodo.isEmpty else { return .erro(400, "Pedido inválido.") }
        guard p.corpo.count <= 1024 * 1024 else { return .erro(400, "Pedido grande demais.") }
        var cabecalhos: [String: String] = [:]
        for (k, v) in p.cabecalhos { cabecalhos[k.lowercased()] = v }
        return roteador.responder(HttpRequisicao(metodo: p.metodo.uppercased(), caminho: p.caminho, query: p.query,
                                                 cabecalhos: cabecalhos, corpo: p.corpo))
    }

    static func resposta(_ r: RespostaRota) -> RespostaCabo {
        RespostaCabo(status: r.status, tipo: r.tipo, corpo: r.corpo, cabecalhos: r.extras)
    }

    // MARK: Fio

    private func enviar(_ m: MensagemCabo) -> Bool {
        guard let quadro = Quadros.codificar(m) else { return false }
        escrita.lock(); defer { escrita.unlock() }
        return fluxo.escrever(quadro)
    }

    /// O iPhone fecha o fio se ficar 15 s sem ouvir o Mac. Escrever também revela fio morto aqui.
    private func agendarPing() {
        DispatchQueue.global().asyncAfter(deadline: .now() + intervaloDoPing) { [self] in
            trava.lock(); let fim = acabou; trava.unlock()
            if fim { return }
            if enviar(MensagemCabo(tipo: "ping")) { agendarPing() } else { encerrar() }
        }
    }

    private func reservar() -> Bool {
        trava.lock(); defer { trava.unlock() }
        if emAndamento >= Self.limiteSimultaneo { return false }
        emAndamento += 1
        return true
    }

    private func liberar() { trava.lock(); emAndamento -= 1; trava.unlock() }
}

/// Fica de olho nos iPhones plugados e mantém uma sessão com cada um. Plugou de novo, conecta de novo:
/// a cada `intervalo` olha a lista do usbmuxd e abre conexão com quem não tem sessão.
final class PortaDoCabo: @unchecked Sendable {
    /// Porta fixa em que o app do iPhone escuta (só no loopback do aparelho, vista pelo Mac via USB).
    static let portaDoAparelho: UInt16 = 4975

    private let roteador: Roteador
    private let nomeMac: @Sendable () -> String
    private let mux: Mux
    private let porta: UInt16
    private let intervalo: TimeInterval
    private let log: @Sendable (String) -> Void
    private let aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)?
    private let trava = NSLock()
    private var ativos: [Int: SessaoCabo] = [:]
    private var rodando = false
    private var ultimoAviso = ""

    init(roteador: Roteador, nomeMac: @escaping @Sendable () -> String, mux: Mux = UsbmuxReal(),
         porta: UInt16 = PortaDoCabo.portaDoAparelho, intervalo: TimeInterval = 2,
         log: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
         aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)? = nil) {
        self.aoAtender = aoAtender
        self.roteador = roteador
        self.nomeMac = nomeMac
        self.mux = mux
        self.porta = porta
        self.intervalo = intervalo
        self.log = log
    }

    func iniciar() {
        trava.lock()
        if rodando { trava.unlock(); return }
        rodando = true
        trava.unlock()
        let t = Thread { [self] in laco() }
        t.name = "deck.cabo"
        t.start()
    }

    func parar() {
        trava.lock()
        rodando = false
        let sessoes = Array(ativos.values)
        trava.unlock()
        for s in sessoes { s.encerrar() }
    }

    var sessoesAtivas: Int { trava.lock(); defer { trava.unlock() }; return ativos.count }

    private func continua() -> Bool { trava.lock(); defer { trava.unlock() }; return rodando }

    private func laco() {
        while continua() {
            varrer()
            Thread.sleep(forTimeInterval: intervalo)
        }
    }

    /// Uma passada: conecta nos aparelhos USB que ainda não têm sessão.
    func varrer() {
        let ids: [Int]
        do { ids = try mux.aparelhosUSB() } catch {
            avisar("O serviço USB do macOS não respondeu. Tento de novo já.")
            return
        }
        if ids.isEmpty { avisar("Nenhum iPhone no cabo.") }
        for id in ids {
            trava.lock(); let ja = ativos[id] != nil; trava.unlock()
            if ja { continue }
            do {
                let fluxo = try mux.conectar(aparelho: id, porta: porta)
                abrirSessao(id, fluxo)
            } catch let e as ErroUsbmux {
                avisar("iPhone \(id) no cabo: \(e.description)")
            } catch {
                avisar("iPhone \(id) no cabo: \(error)")
            }
        }
    }

    private func abrirSessao(_ id: Int, _ fluxo: FluxoBytes) {
        let sessao = SessaoCabo(fluxo: fluxo, roteador: roteador, nomeMac: nomeMac(), rotulo: "usbmux/\(id)", log: log, aoAtender: aoAtender)
        trava.lock(); ativos[id] = sessao; ultimoAviso = ""; trava.unlock()
        log("cabo conectado ao iPhone \(id) pelo usbmux (porta \(porta) do aparelho)")
        let t = Thread { [self] in
            sessao.rodar()
            trava.lock(); ativos[id] = nil; trava.unlock()
            log("cabo do iPhone \(id) caiu. Volto a procurar.")
        }
        t.name = "deck.cabo.\(id)"
        t.start()
    }

    /// Só escreve quando o motivo muda, senão o log enche a cada 2 s.
    private func avisar(_ texto: String) {
        trava.lock()
        let repetido = texto == ultimoAviso
        ultimoAviso = texto
        trava.unlock()
        if !repetido { log("cabo: \(texto)") }
    }
}
