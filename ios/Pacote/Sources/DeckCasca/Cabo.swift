import Foundation

// O canal pelo cabo (fase 6). O app escuta numa porta fixa do loopback do iPhone e o Mac, que enxerga
// o aparelho pelo usbmuxd, abre a conexão e se apresenta. Dali em diante é só pedido e resposta, o mesmo
// HTTP do Wi-Fi em quadros (Quadros.swift). Tirou o cabo, o fio cai e o Mac abre outro ao plugar de novo.

/// Uma conexão com o Mac. Lê numa thread, entrega cada resposta a quem pediu e avisa quando acaba.
final class ConexaoCabo: @unchecked Sendable {
    /// Sem ouvir o Mac por este tempo, o fio é dado como morto (o Mac manda um ping a cada 5 s).
    static let silencioMaximo: TimeInterval = 15
    static let prazoDoPedidoPadrao: TimeInterval = 10
    /// Quem conecta e não se apresenta (ou não prova quem é) nesse tempo é largado.
    static let prazoDaApresentacao: TimeInterval = 5
    static let prazoDaProva: TimeInterval = 3

    private let fluxo: FluxoBytes
    private let prazoDoPedido: TimeInterval
    private let trava = NSLock()
    private let escrita = NSLock()
    private var pendentes: [Int: CheckedContinuation<RespostaCanal, Error>] = [:]
    private var proximo = 1
    private var ultimoSinal = Date()
    private var acabou = false
    private var _nomeMac: String?
    /// Só vale depois de o Mac provar quem é (o código de acesso ou os dígitos do pareamento).
    private var _autenticada = false
    /// O último desafio que mandei: só a prova que o repete (mesmo nonce e modo) conta.
    private var desafio: (nonce: String, modo: String, chave: String?)?
    private var esperaProva: CheckedContinuation<Bool, Never>?
    private let segredo: @Sendable () -> String?
    /// Como o erro chama este fio ("O cabo", "O Bluetooth").
    private let nomeDoCanal: String
    var nomeMac: String? { trava.withLock { _nomeMac } }
    var autenticada: Bool { trava.withLock { _autenticada } }

    /// `segredo` devolve o código de acesso quando o iPhone já está pareado. Pareado, só entra o Mac que o prova.
    /// `confiavel`: o fio já provou quem é o Mac (o Bluetooth faz isso no aperto de mão cifrado), então não há desafio.
    init(fluxo: FluxoBytes, prazoDoPedido: TimeInterval = ConexaoCabo.prazoDoPedidoPadrao,
         segredo: @escaping @Sendable () -> String? = { nil }, confiavel: Bool = false, nomeDoCanal: String = "O cabo") {
        self.fluxo = fluxo
        self.prazoDoPedido = prazoDoPedido
        self.segredo = segredo
        self.nomeDoCanal = nomeDoCanal
        _autenticada = confiavel
    }

    /// `aoOla` roda quando o Mac se apresenta (e, pareado, só depois de provar quem é). `aoFechar` roda uma vez, quando o fio acaba.
    func iniciar(aoOla: @escaping @Sendable (ConexaoCabo) -> Void, aoFechar: @escaping @Sendable (ConexaoCabo) -> Void) {
        let t = Thread { [self] in
            while let m = Quadros.ler(de: fluxo) {
                sinal()
                switch m.tipo {
                case "ola":
                    if !receberOla(m) { break }
                    aoOla(self)
                case "resposta":
                    if let id = m.id, let r = m.resposta { terminar(id, .success(r)) }
                default: break
                }
                if rejeitada() { break }
            }
            fechar()
            aoFechar(self)
        }
        t.name = "deck.cabo.leitura"
        t.start()
        // Pareado, quem conecta recebe o desafio já: o "ola" sem prova não serve.
        if let chave = segredo() { _ = desafiar(modo: ProvaCabo.modoAcesso, chave: chave) }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.prazoDaApresentacao) { [self] in
            if nomeMac == nil { fechar() }
        }
        vigiar()
    }

    private var _rejeitada = false
    private func rejeitada() -> Bool { trava.withLock { _rejeitada } }
    /// O Mac do outro lado não provou o código de acesso deste iPhone (não o conhece ou conhece outro).
    var rejeitadaPeloMac: Bool { rejeitada() }

    /// Decide se este "ola" vale como apresentação. Devolve true quando é a primeira apresentação aceita.
    private func receberOla(_ m: MensagemCabo) -> Bool {
        guard let nome = m.nome, !nome.isEmpty else { return false }
        let (esperado, jaTinha): ((nonce: String, modo: String, chave: String?)?, Bool) = trava.withLock { (desafio, _nomeMac != nil) }
        if let prova = m.prova, let d = esperado, m.nonce == d.nonce, m.modo == d.modo, let chave = d.chave {
            let certa = ProvaCabo.prova(chave: chave, modo: d.modo, nonce: d.nonce, nomeMac: nome)
            if ProvaCabo.igual(prova, certa) {
                let cont: CheckedContinuation<Bool, Never>? = trava.withLock {
                    _autenticada = true
                    desafio = nil
                    let c = esperaProva
                    esperaProva = nil
                    if _nomeMac == nil { _nomeMac = nome }
                    return c
                }
                cont?.resume(returning: true)
                return !jaTinha
            }
            // Prova errada. Pareado é um impostor: derruba. Sem pareamento só o desafio falha.
            if d.modo == ProvaCabo.modoAcesso { trava.withLock { _rejeitada = true } }
            soltarEspera(false)
            return false
        }
        if m.prova == nil, let d = esperado, m.nonce == d.nonce, m.modo == d.modo {
            // O Mac respondeu "não tenho esse segredo" (modo codigo sem pareamento em curso).
            if d.modo == ProvaCabo.modoAcesso { trava.withLock { _rejeitada = true } }
            soltarEspera(false)
            return false
        }
        // "Ola" solto, sem prova. Pareado não confia. Sem pareamento é só o nome para a lista de Macs.
        if segredo() != nil { return false }
        return trava.withLock {
            guard _nomeMac == nil else { return false }
            _nomeMac = nome
            return true
        }
    }

    private func soltarEspera(_ ok: Bool) {
        let c: CheckedContinuation<Bool, Never>? = trava.withLock {
            let c = esperaProva
            esperaProva = nil
            return c
        }
        c?.resume(returning: ok)
    }

    @discardableResult
    private func desafiar(modo: String, chave: String) -> Bool {
        let nonce = ProvaCabo.nonce()
        trava.withLock { desafio = (nonce, modo, chave) }
        guard let quadro = Quadros.codificar(MensagemCabo(tipo: "desafio", nonce: nonce, modo: modo)) else { return false }
        return escrita.withLock { fluxo.escrever(quadro) }
    }

    /// Pede ao Mac que prove que conhece os dígitos digitados. true só se a prova bater: só então os dígitos
    /// podem seguir pelo fio, porque quem não os conhece não vê nada que sirva para descobri-los.
    func provarCodigo(_ digitos: String) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            trava.withLock { esperaProva = c }
            guard desafiar(modo: ProvaCabo.modoCodigo, chave: digitos) else { return soltarEspera(false) }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.prazoDaProva) { [self] in soltarEspera(false) }
        }
    }

    func fechar() {
        soltarEspera(false)
        let soltar: [CheckedContinuation<RespostaCanal, Error>] = trava.withLock {
            acabou = true
            let todos = Array(pendentes.values)
            pendentes = [:]
            return todos
        }
        fluxo.fechar()
        for c in soltar { c.resume(throwing: ErroCanal.falhou("\(nomeDoCanal) foi desconectado.")) }
    }

    func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<RespostaCanal, Error>) in
            let id: Int? = trava.withLock {
                if acabou { return nil }
                let id = proximo
                proximo += 1
                pendentes[id] = c
                return id
            }
            guard let id else { return c.resume(throwing: ErroCanal.semCanal) }
            guard let quadro = Quadros.codificar(MensagemCabo(tipo: "pedido", id: id, pedido: pedido)) else {
                return terminar(id, .failure(ErroCanal.falhou("O pedido é grande demais para \(nomeDoCanal.lowercased()).")))
            }
            let escreveu = escrita.withLock { fluxo.escrever(quadro) }
            if !escreveu { fechar(); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + prazoDoPedido) { [self] in
                terminar(id, .failure(ErroCanal.falhou("O Mac não respondeu a tempo.")))
            }
        }
    }

    /// Resolve o pedido uma só vez: resposta, prazo e queda do fio disputam e só o primeiro vale.
    private func terminar(_ id: Int, _ resultado: Result<RespostaCanal, Error>) {
        let c = trava.withLock { pendentes.removeValue(forKey: id) }
        c?.resume(with: resultado)
    }

    private func sinal() { trava.withLock { ultimoSinal = Date() } }

    private func vigiar() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            let (fim, parado) = trava.withLock { (acabou, Date().timeIntervalSince(ultimoSinal)) }
            if fim { return }
            if parado > Self.silencioMaximo { fechar() } else { vigiar() }
        }
    }
}

/// Dono da porta do cabo: escuta, aceita o Mac e guarda a conexão em uso (uma só). Qualquer app do iPhone
/// alcança essa porta, então quem conecta é só candidato: pareado, vira a conexão em uso apenas depois de
/// provar que conhece o código de acesso, e uma conexão provada nunca é trocada por uma sem prova.
public final class GerenteDoCabo: @unchecked Sendable {
    /// Porta fixa do aparelho. O Mac usa a mesma (mac/Nucleo/Cabo.swift).
    public static let portaPadrao: UInt16 = 4975

    private let porta: UInt16
    private let prazoDoPedido: TimeInterval
    private let segredo: @Sendable () -> String?
    private let log: @Sendable (String) -> Void
    private let trava = NSLock()
    private var ouvinte: Ouvinte?
    private var conexao: ConexaoCabo?
    private var candidatas: [ObjectIdentifier: ConexaoCabo] = [:]
    static let maximoDeCandidatas = 8
    private var macAtual: MacEncontrado?
    private var inscritos: [UUID: AsyncStream<MacEncontrado>.Continuation] = [:]
    private var aoMudarCabo: (@Sendable (MacEncontrado?) -> Void)?
    private var aoNaoReconhecidoCabo: (@Sendable () -> Void)?
    private var recusasSeguidas = 0
    /// Quantas conexões seguidas o Mac pode deixar sem provar o código antes de o pareamento valer como acabado.
    /// Uma só poderia ser um instante da troca do código de acesso: a segunda, logo em seguida, confirma.
    static let recusasParaEsquecer = 2

    /// `segredo` devolve o código de acesso guardado (nil enquanto não pareou). Pareado, só o Mac que o prova entra.
    public convenience init(porta: UInt16 = GerenteDoCabo.portaPadrao, segredo: @escaping @Sendable () -> String? = { nil },
                            log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(porta: porta, prazoDoPedido: ConexaoCabo.prazoDoPedidoPadrao, segredo: segredo, log: log)
    }

    init(porta: UInt16, prazoDoPedido: TimeInterval, segredo: @escaping @Sendable () -> String? = { nil },
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.porta = porta
        self.prazoDoPedido = prazoDoPedido
        self.segredo = segredo
        self.log = log
    }

    /// Chamado quando o Mac se apresenta (com ele) e quando o fio cai (com nil).
    public func aoMudar(_ f: @escaping @Sendable (MacEncontrado?) -> Void) {
        trava.withLock { aoMudarCabo = f }
    }

    /// O Mac que conecta pelo cabo não prova o código deste iPhone várias vezes seguidas: o Mac desconectou o aparelho.
    public func aoNaoReconhecido(_ f: @escaping @Sendable () -> Void) {
        trava.withLock { aoNaoReconhecidoCabo = f }
    }

    /// Abre a porta. Devolve o texto do problema se não abriu.
    @discardableResult
    public func iniciar() -> String? {
        if abrir() { return nil }
        log("cabo: não consegui abrir a porta \(porta) do aparelho")
        return "Não consegui abrir a porta do cabo."
    }

    private func abrir() -> Bool {
        guard let novo = Ouvinte(porta: porta) else { return false }
        let antigo: Ouvinte? = trava.withLock {
            let a = ouvinte
            ouvinte = novo
            return a
        }
        antigo?.fechar()
        log("cabo: escutando no loopback, porta \(porta)")
        let t = Thread { [self] in
            while let soquete = novo.aceitar() { receber(soquete) }
            // O laço acabou (fecharam, ou o sistema derrubou a porta): quem olhar depois sabe que não há ouvinte.
            trava.withLock { if ouvinte === novo { ouvinte = nil } }
        }
        t.name = "deck.cabo.ouvinte"
        t.start()
        return true
    }

    /// O app voltou ao primeiro plano: o iOS pode ter derrubado ou congelado o ouvinte em segundo plano, então
    /// fecha o velho e abre um novo (tenta por até 2 s, até o velho soltar a porta). A conexão viva não é tocada.
    public func retomar() {
        let antigo: Ouvinte? = trava.withLock {
            let a = ouvinte
            ouvinte = nil
            return a
        }
        antigo?.fechar()
        DispatchQueue.global().async { [self] in
            for _ in 0..<40 {
                if abrir() { return }
                Thread.sleep(forTimeInterval: 0.05)
            }
            log("cabo: não consegui reabrir a porta \(porta) do aparelho")
        }
    }

    public func parar() {
        let (o, c): (Ouvinte?, [ConexaoCabo]) = trava.withLock {
            let r = (ouvinte, [conexao].compactMap { $0 } + candidatas.values)
            ouvinte = nil
            return r
        }
        o?.fechar()
        for x in c { x.fechar() }
    }

    public var mac: MacEncontrado? { trava.withLock { macAtual } }

    /// O Mac que está no cabo agora (se estiver) e cada um que chegar depois.
    public func macs() -> AsyncStream<MacEncontrado> {
        AsyncStream { continuacao in
            let id = UUID()
            let agora: MacEncontrado? = trava.withLock {
                inscritos[id] = continuacao
                return macAtual
            }
            if let agora { continuacao.yield(agora) }
            continuacao.onTermination = { [weak self] _ in self?.trava.withLock { _ = self?.inscritos.removeValue(forKey: id) } }
        }
    }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal {
        guard let c = trava.withLock({ conexao }) else { throw ErroCanal.semCanal }
        return try await c.enviar(pedido)
    }

    // MARK: Conexões

    private func receber(_ soquete: Soquete) {
        let nova = ConexaoCabo(fluxo: soquete, prazoDoPedido: prazoDoPedido, segredo: segredo)
        let aceita: Bool = trava.withLock {
            guard candidatas.count < Self.maximoDeCandidatas else { return false }
            candidatas[ObjectIdentifier(nova)] = nova
            return true
        }
        guard aceita else { soquete.fechar(); return }
        nova.iniciar(aoOla: { [self] c in apresentou(c) }, aoFechar: { [self] c in caiu(c) })
    }

    private func apresentou(_ c: ConexaoCabo) {
        guard let nome = c.nomeMac else { return }
        let mac = MacEncontrado(id: nome, nome: nome, perto: true)
        // Uma conexão provada não sai para uma sem prova (só acontece sem pareamento, e aí o que vale é a que já provou).
        let r: (antiga: ConexaoCabo?, inscritos: [AsyncStream<MacEncontrado>.Continuation], aviso: (@Sendable (MacEncontrado?) -> Void)?, ok: Bool) = trava.withLock {
            if let atual = conexao, atual !== c, atual.autenticada, !c.autenticada { return (nil, [], nil, false) }
            let a = conexao
            conexao = c
            macAtual = mac
            if c.autenticada { recusasSeguidas = 0 }
            return (a, Array(inscritos.values), aoMudarCabo, true)
        }
        guard r.ok else { c.fechar(); return }
        if r.antiga !== c { r.antiga?.fechar() }
        log("cabo: Mac \"\(nome)\" conectado")
        for i in r.inscritos { i.yield(mac) }
        r.aviso?(mac)
    }

    /// Confirma, na conexão em uso, que o Mac conhece os dígitos digitados. Devolve a conexão provada
    /// (o pedido de pareamento tem que ir por ela, não pela "atual", que pode trocar no meio).
    func provarCodigo(_ digitos: String) async -> ConexaoCabo? {
        guard let c = trava.withLock({ conexao }) else { return nil }
        return await c.provarCodigo(digitos) ? c : nil
    }

    private func caiu(_ c: ConexaoCabo) {
        if c.rejeitadaPeloMac { recusouOMac() }
        // Só avisa se era a conexão em uso: a antiga, trocada por uma nova, cai em silêncio.
        let era: (aviso: (@Sendable (MacEncontrado?) -> Void)?, era: Bool) = trava.withLock {
            candidatas.removeValue(forKey: ObjectIdentifier(c))
            guard conexao === c else { return (nil, false) }
            conexao = nil
            macAtual = nil
            return (aoMudarCabo, true)
        }
        guard era.era else { return }
        log("cabo: conexão com o Mac caiu")
        era.aviso?(nil)
    }
}

extension GerenteDoCabo {
    /// Sem prova do código, o cabo conecta e cai a cada 2 s e nenhum pedido sai, então a página nunca recebe um 401.
    fileprivate func recusouOMac() {
        let aviso: (@Sendable () -> Void)? = trava.withLock {
            recusasSeguidas += 1
            guard recusasSeguidas >= Self.recusasParaEsquecer else { return nil }
            recusasSeguidas = 0
            return aoNaoReconhecidoCabo
        }
        guard let aviso else { return }
        log("cabo: o Mac não provou o código deste iPhone, o pareamento acabou")
        aviso()
    }
}

/// O canal em uso quando o Mac está no cabo. Sem conexão, o pedido falha com `semCanal` e a página mostra "Mac desconectado".
public struct CanalCabo: Canal {
    public let tipo: TipoCanal = .cabo
    let gerente: GerenteDoCabo

    public init(_ gerente: GerenteDoCabo) { self.gerente = gerente }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal { try await gerente.enviar(pedido) }
}

/// Pareamento pela segunda via: o Mac mostra 6 dígitos, a pessoa digita no iPhone e o Mac devolve o
/// código de acesso. O Bluetooth é da fase 7: aqui continua indisponível.
public struct PareadorCabo: Pareador {
    let gerente: GerenteDoCabo

    public init(_ gerente: GerenteDoCabo) { self.gerente = gerente }

    public func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> { AsyncStream { $0.yield([]) } }
    public func iniciar(com mac: MacEncontrado) async throws -> String { throw ErroPareamento.indisponivel }
    public func concluir(aceito: Bool) async throws -> PareamentoFeito { throw ErroPareamento.indisponivel }
    public func procurarNoCabo() -> AsyncStream<MacEncontrado> { gerente.macs() }

    public func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        let corpo = (try? JSONSerialization.data(withJSONObject: ["codigo": codigo])) ?? Data()
        let pedido = PedidoCanal(metodo: "POST", caminho: "/api/parear",
                                 cabecalhos: ["content-type": "application/json"], corpo: corpo)
        // Os dígitos só seguem para quem prova que os conhece: um app qualquer do iPhone que conectou
        // na porta não vê os 6 dígitos nem devolve um código de acesso falso.
        guard gerente.mac != nil else { throw ErroPareamento.recusado("O cabo desconectou. Plugue de novo e tente outra vez.") }
        guard let conexao = await gerente.provarCodigo(codigo) else {
            throw ErroPareamento.recusado("Esse código não confere com o do Mac, ou já venceu. Confira os dígitos ou gere um novo no Mac.")
        }
        let r: RespostaCanal
        do { r = try await conexao.enviar(pedido) } catch {
            throw ErroPareamento.recusado("O cabo desconectou. Plugue de novo e tente outra vez.")
        }
        let json = (try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any]
        guard r.status == 200, let acesso = json?["codigoAcesso"] as? String, !acesso.isEmpty else {
            throw ErroPareamento.recusado((json?["erro"] as? String) ?? "O Mac não aceitou o código. Tente de novo.")
        }
        return PareamentoFeito(pareado: Pareado(codigoAcesso: acesso, nomeMac: mac.nome), canal: CanalCabo(gerente))
    }
}
