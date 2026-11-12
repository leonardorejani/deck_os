import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import DeckCasca

// O canal do cabo sem Mac nem cabo: um "Mac" de teste abre conexão TCP no loopback, como o usbmuxd
// faz com o iPhone de verdade, e fala os quadros do protocolo.

func conectarLocal(_ porta: UInt16) -> Soquete? {
    let fd = socket(AF_INET, Soquete.tipoStream, 0)
    var fim = sockaddr_in()
    fim.sin_family = sa_family_t(AF_INET)
    fim.sin_port = porta.bigEndian
    fim.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
    let ok = withUnsafePointer(to: &fim) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard ok == 0 else { _ = close(fd); return nil }
    return Soquete(fd: fd)
}

/// O Mac do teste: se apresenta e responde pedido por pedido com o que a closure mandar.
final class MacFalso: @unchecked Sendable {
    let fio: Soquete
    private let trava = NSLock()
    private var _vistos: [PedidoCanal] = []
    var vistos: [PedidoCanal] { trava.withLock { _vistos } }
    var extras: [String: String] = [:]
    var responder: @Sendable (PedidoCanal) -> RespostaCanal? = { _ in
        RespostaCanal(status: 200, tipo: "application/json", corpo: Data("{\"ok\":true}".utf8))
    }

    /// `segredo` e `digitos` são o que este Mac sabe: o código de acesso e os 6 dígitos do pareamento em curso.
    /// Quem não os sabe (um app qualquer do iPhone) responde o desafio sem prova ou nem responde.
    init(porta: UInt16, nome: String = "MacBook do Leo", seApresenta: Bool = true, segredo: String? = nil, digitos: String? = nil) throws {
        guard let f = conectarLocal(porta) else { throw NSError(domain: "MacFalso", code: 1, userInfo: [NSLocalizedDescriptionKey: "não conectou na porta \(porta)"]) }
        fio = f
        if seApresenta { _ = fio.escrever(Quadros.codificar(MensagemCabo(tipo: "ola", nome: nome, versao: 1))!) }
        let t = Thread { [self] in
            while let m = Quadros.ler(de: fio) {
                if m.tipo == "desafio", let nonce = m.nonce, let modo = m.modo {
                    let chave = modo == ProvaCabo.modoAcesso ? segredo : digitos
                    let prova = chave.map { ProvaCabo.prova(chave: $0, modo: modo, nonce: nonce, nomeMac: nome) }
                    _ = fio.escrever(Quadros.codificar(MensagemCabo(tipo: "ola", nome: nome, versao: 1, nonce: nonce, modo: modo, prova: prova))!)
                    continue
                }
                guard m.tipo == "pedido", let id = m.id, let p = m.pedido else { continue }
                trava.withLock { _vistos.append(p) }
                guard var r = responder(p) else { continue }
                for (k, v) in extras { r.cabecalhos[k] = v }
                _ = fio.escrever(Quadros.codificar(MensagemCabo(tipo: "resposta", id: id, resposta: r))!)
            }
        }
        t.start()
    }

    func cair() { fio.fechar() }
}

func pedido(_ caminho: String = "/api/estado") -> PedidoCanal {
    PedidoCanal(metodo: "GET", caminho: caminho, cabecalhos: ["x-deck-codigo": "ABC"])
}

final class CaboTestes: XCTestCase {
    /// Sorteia uma porta alta e tenta até uma abrir: a máquina de quem testa pode ter qualquer coisa escutando.
    private func gerente(prazo: TimeInterval = 10, segredo: String? = nil) -> (GerenteDoCabo, UInt16, Linhas) {
        let linhas = Linhas()
        for _ in 0..<50 {
            let porta = UInt16.random(in: 20000..<30000)
            let g = GerenteDoCabo(porta: porta, prazoDoPedido: prazo, segredo: { segredo }, log: { linhas.anotar($0) })
            if g.iniciar() == nil {
                addTeardownBlock { g.parar() }
                return (g, porta, linhas)
            }
        }
        XCTFail("nenhuma porta livre")
        return (GerenteDoCabo(porta: 1), 1, linhas)
    }

    final class Linhas: @unchecked Sendable {
        private let trava = NSLock()
        private var l: [String] = []
        func anotar(_ s: String) { trava.withLock { l.append(s) } }
        var todas: [String] { trava.withLock { l } }
    }

    final class Aviso: @unchecked Sendable {
        private let trava = NSLock()
        private var _macs: [String?] = []
        func anotar(_ m: MacEncontrado?) { trava.withLock { _macs.append(m?.nome) } }
        var macs: [String?] { trava.withLock { _macs } }
    }

    private func esperarSync(_ ok: () -> Bool, _ texto: String) {
        for _ in 0..<200 where !ok() { Thread.sleep(forTimeInterval: 0.025) }
        XCTAssertTrue(ok(), texto)
    }

    // MARK: Quadros

    /// O mesmo quadro de ouro existe em mac/Testes: os dois lados têm que concordar byte a byte.
    func testQuadroDeOuroIgualAoDoMac() {
        let p = PedidoCanal(metodo: "GET", caminho: "/api/estado", query: [:], cabecalhos: ["x-deck-codigo": "abc"], corpo: Data())
        let q = Quadros.codificar(MensagemCabo(tipo: "pedido", id: 1, pedido: p))!
        XCTAssertEqual(String(decoding: q.dropFirst(4), as: UTF8.self),
                       #"{"id":1,"pedido":{"cabecalhos":{"x-deck-codigo":"abc"},"caminho":"/api/estado","corpo":"","metodo":"GET","query":{}},"tipo":"pedido"}"#)
        XCTAssertEqual(q.prefix(4).reduce(0) { $0 << 8 | Int($1) }, q.count - 4)
    }

    func testRespostaDoMacDecodificaCompleta() throws {
        let json = #"{"id":2,"resposta":{"cabecalhos":{"X-Deck-Codigo-Novo":"novo"},"corpo":"e30=","status":200,"tipo":"application/json"},"tipo":"resposta"}"#
        let m = try JSONDecoder().decode(MensagemCabo.self, from: Data(json.utf8))
        XCTAssertEqual(m.resposta?.status, 200)
        XCTAssertEqual(m.resposta?.corpo, Data("{}".utf8))
        XCTAssertEqual(m.resposta?.cabecalho("x-deck-codigo-novo"), "novo")
    }

    // MARK: Gerente

    func testMacQueSeApresentaViraOCanalEOPedidoVolta() async throws {
        let (g, porta, _) = gerente()
        let aviso = Aviso()
        g.aoMudar { aviso.anotar($0) }
        let mac = try MacFalso(porta: porta)
        esperarSync({ aviso.macs == ["MacBook do Leo"] }, "avisou que o Mac chegou")
        let r = try await g.enviar(pedido())
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(String(decoding: r.corpo, as: UTF8.self), "{\"ok\":true}")
        XCTAssertEqual(mac.vistos.first?.caminho, "/api/estado")
        XCTAssertEqual(mac.vistos.first?.cabecalhos["x-deck-codigo"], "ABC")
    }

    func testSemMacOPedidoFalhaComSemCanal() async {
        let (g, _, _) = gerente()
        do { _ = try await g.enviar(pedido()); XCTFail("devia falhar") } catch { XCTAssertEqual(error as? ErroCanal, .semCanal) }
    }

    func testCaboSaindoDerrubaOCanalEAvisa() async throws {
        let (g, porta, _) = gerente()
        let aviso = Aviso()
        g.aoMudar { aviso.anotar($0) }
        let mac = try MacFalso(porta: porta)
        esperarSync({ g.mac != nil }, "Mac chegou")
        mac.cair()
        esperarSync({ aviso.macs == ["MacBook do Leo", nil] }, "avisou que caiu: \(aviso.macs)")
        XCTAssertNil(g.mac)
        do { _ = try await g.enviar(pedido()); XCTFail() } catch { XCTAssertEqual(error as? ErroCanal, .semCanal) }
    }

    func testPlugarDeNovoVoltaSozinho() async throws {
        let (g, porta, _) = gerente()
        let aviso = Aviso()
        g.aoMudar { aviso.anotar($0) }
        let primeiro = try MacFalso(porta: porta)
        esperarSync({ g.mac != nil }, "primeira conexão")
        primeiro.cair()
        esperarSync({ g.mac == nil }, "caiu")
        _ = try MacFalso(porta: porta)
        esperarSync({ aviso.macs == ["MacBook do Leo", nil, "MacBook do Leo"] }, "voltou: \(aviso.macs)")
        let r = try await g.enviar(pedido())
        XCTAssertEqual(r.status, 200)
    }

    func testConexaoNovaSubstituiAAntigaSemAvisarQueCaiu() async throws {
        let (g, porta, _) = gerente()
        let aviso = Aviso()
        g.aoMudar { aviso.anotar($0) }
        let velho = try MacFalso(porta: porta, nome: "Velho")
        esperarSync({ g.mac?.nome == "Velho" }, "velho")
        _ = try MacFalso(porta: porta, nome: "Novo")
        esperarSync({ g.mac?.nome == "Novo" }, "novo")
        try await Task.sleep(nanoseconds: 200000000)
        XCTAssertEqual(aviso.macs, ["Velho", "Novo"], "a troca não passa por nil")
        velho.cair()
    }

    func testPedidoSemRespostaFalhaNoPrazo() async throws {
        let (g, porta, _) = gerente(prazo: 0.2)
        let mac = try MacFalso(porta: porta)
        mac.responder = { _ in nil }
        esperarSync({ g.mac != nil }, "Mac chegou")
        do { _ = try await g.enviar(pedido()); XCTFail() } catch {
            XCTAssertEqual(error as? ErroCanal, .falhou("O Mac não respondeu a tempo."))
        }
    }

    func testPedidoPendenteFalhaQuandoOCaboSai() async throws {
        let (g, porta, _) = gerente()
        let mac = try MacFalso(porta: porta)
        mac.responder = { _ in nil }
        esperarSync({ g.mac != nil }, "Mac chegou")
        async let r = g.enviar(pedido())
        esperarSync({ mac.vistos.count == 1 }, "o Mac recebeu")
        mac.cair()
        do { _ = try await r; XCTFail() } catch { XCTAssertEqual(error as? ErroCanal, .falhou("O cabo foi desconectado.")) }
    }

    func testPedidosJuntosVoltamCadaUmNoSeuId() async throws {
        let (g, porta, _) = gerente()
        let mac = try MacFalso(porta: porta)
        mac.responder = { p in RespostaCanal(status: 200, tipo: "text/plain", corpo: Data(p.caminho.utf8)) }
        esperarSync({ g.mac != nil }, "Mac chegou")
        let caminhos = (0..<12).map { "/api/n\($0)" }
        let respostas = try await withThrowingTaskGroup(of: (String, String).self) { grupo -> [(String, String)] in
            for c in caminhos { grupo.addTask { (c, String(decoding: try await g.enviar(pedido(c)).corpo, as: UTF8.self)) } }
            var tudo: [(String, String)] = []
            for try await r in grupo { tudo.append(r) }
            return tudo
        }
        XCTAssertEqual(respostas.count, 12)
        for (pedido, resposta) in respostas { XCTAssertEqual(pedido, resposta) }
    }

    func testLixoNoFioDerrubaSoAquelaConexao() async throws {
        let (g, porta, _) = gerente()
        let ruim = try MacFalso(porta: porta, seApresenta: false)
        _ = ruim.fio.escrever(Data([0x7F, 0xFF, 0xFF, 0xFF, 1, 2, 3]))
        try await Task.sleep(nanoseconds: 200000000)
        XCTAssertNil(g.mac)
        _ = try MacFalso(porta: porta)
        esperarSync({ g.mac != nil }, "o próximo Mac entra normal")
    }

    func testMacsEntregaOQueJaEstaPlugadoEOQueChegarDepois() async throws {
        let (g, porta, _) = gerente()
        _ = try MacFalso(porta: porta, nome: "Primeiro")
        esperarSync({ g.mac != nil }, "primeiro")
        var it = g.macs().makeAsyncIterator()
        let agora = await it.next()
        XCTAssertEqual(agora?.nome, "Primeiro")
    }

    func testPortaOcupadaDaErroEmPortugues() {
        let (_, porta, _) = gerente()
        let outro = GerenteDoCabo(porta: porta)
        // SO_REUSEADDR não deixa dois ouvintes na mesma porta com o primeiro ainda aceitando.
        XCTAssertNotNil(outro.iniciar())
    }

    func testRetomarAbreAPortaDeNovoSemDerrubarOMacConectado() async throws {
        let (g, porta, _) = gerente()
        _ = try MacFalso(porta: porta)
        esperarSync({ g.mac != nil }, "Mac chegou")
        g.retomar()
        try await Task.sleep(nanoseconds: 100000000)
        XCTAssertNotNil(g.mac)
        let r = try await g.enviar(pedido())
        XCTAssertEqual(r.status, 200)
        // e a porta nova aceita outro Mac
        _ = try MacFalso(porta: porta, nome: "Depois")
        esperarSync({ g.mac?.nome == "Depois" }, "porta nova aceitou")
    }

    // MARK: Rodízio do código (X-Deck-Codigo-Novo)

    func testCodigoNovoDoMacChegaAteOCofrePelaPonte() async throws {
        let (g, porta, _) = gerente(segredo: "ANTIGO")
        let mac = try MacFalso(porta: porta, segredo: "ANTIGO")
        mac.extras = ["X-Deck-Codigo-Novo": "NOVOCODIGOSEGURO1234"]
        esperarSync({ g.mac != nil }, "Mac chegou")
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "ANTIGO", nomeMac: "Mac"))
        let canais = CanalAtual()
        canais.definir(CanalCabo(g))
        let ponte = Ponte(canais: canais, cofre: cofre, vibrar: {})
        let r = await ponte.requisitar(MensagemPonte(op: "requisitar", metodo: "GET", caminho: "/api/estado", cabecalhos: ["X-Deck-Codigo": "ANTIGO"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.codigoNovo, "NOVOCODIGOSEGURO1234")
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "NOVOCODIGOSEGURO1234")
        XCTAssertEqual(mac.vistos.first?.cabecalhos["x-deck-codigo"], "ANTIGO", "a página manda o código no cabeçalho em minúsculas")
    }

    // MARK: Mac que desconectou o iPhone (código de acesso mudou)

    final class Contagem: @unchecked Sendable {
        private let trava = NSLock()
        private var n = 0
        func somar() { trava.withLock { n += 1 } }
        var valor: Int { trava.withLock { n } }
    }

    /// Defeito de 11/11/2026: sem Bluetooth, o cabo conectava e caía a cada 2 s com o código velho e o iPhone nunca
    /// esquecia o pareamento. Duas conexões seguidas sem prova (uma só pode ser a troca do código) é o sinal.
    func testCaboSoQueNaoProvaOCodigoDuasVezesAvisaQueOPareamentoAcabou() throws {
        let (g, porta, _) = gerente(segredo: "CODIGOVELHOCODIGOVEL")
        let avisos = Contagem()
        g.aoNaoReconhecido { avisos.somar() }
        _ = try MacFalso(porta: porta, segredo: "OUTROCODIGOOUTROCODI")
        esperarSync({ avisos.valor == 0 && g.mac == nil }, "a primeira recusa derruba, sem avisar ainda")
        XCTAssertEqual(avisos.valor, 0, "uma recusa só não basta")
        _ = try MacFalso(porta: porta, segredo: "OUTROCODIGOOUTROCODI")
        esperarSync({ avisos.valor == 1 }, "a segunda recusa seguida avisa")
        XCTAssertNil(g.mac)
    }

    func testCaboQueProvaOCodigoZeraAContagemDeRecusas() throws {
        let (g, porta, _) = gerente(segredo: "CODIGOVELHOCODIGOVEL")
        let avisos = Contagem()
        g.aoNaoReconhecido { avisos.somar() }
        _ = try MacFalso(porta: porta, segredo: "OUTROCODIGOOUTROCODI")
        Thread.sleep(forTimeInterval: 0.3)
        let bom = try MacFalso(porta: porta, segredo: "CODIGOVELHOCODIGOVEL")
        esperarSync({ g.mac != nil }, "o Mac certo conectou")
        bom.cair()
        esperarSync({ g.mac == nil }, "caiu")
        _ = try MacFalso(porta: porta, segredo: "OUTROCODIGOOUTROCODI")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(avisos.valor, 0, "recusa, prova e recusa de novo não são duas seguidas")
    }

    @MainActor
    func testCascaSemBluetoothEsqueceOPareamentoQuandoOCaboNaoProvaOCodigo() async throws {
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOVELHOCODIGOVEL", nomeMac: "Mac"))
        var achado: (GerenteDoCabo, UInt16)?
        for _ in 0..<50 {
            let p = UInt16.random(in: 20000..<30000)
            let t = GerenteDoCabo(porta: p, prazoDoPedido: 10, segredo: { cofre.ler()?.codigoAcesso })
            if t.iniciar() == nil { achado = (t, p); break }
        }
        let (cabo, porta) = try XCTUnwrap(achado)
        addTeardownBlock { cabo.parar() }
        let c = Casca(pareador: PareadorCabo(cabo), cofre: cofre, vibrar: {}, permanenciaNoCabo: 0, cabo: cabo, bluetooth: nil)
        var recarregou = false
        c.recarregarPagina = { recarregou = true }
        c.iniciar()
        for _ in 0..<2 {
            _ = try MacFalso(porta: porta, segredo: "OUTROCODIGOOUTROCODI")
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        await esperar({ cofre.ler() == nil }, segundos: 5)
        XCTAssertNil(cofre.ler(), "o pareamento acabou")
        XCTAssertTrue(recarregou, "a página volta à tela de parear")
    }

    // MARK: Pareamento pelo cabo

    static let naoConfere = "Esse código não confere com o do Mac, ou já venceu. Confira os dígitos ou gere um novo no Mac."

    func testPareamentoComCodigoCertoDevolveOCodigoDeAcessoEOCanalDoCabo() async throws {
        let (g, porta, _) = gerente()
        let mac = try MacFalso(porta: porta, digitos: "482913")
        mac.responder = { p in
            let ok = String(decoding: p.corpo, as: UTF8.self).contains("482913")
            let corpo = ok ? #"{"codigoAcesso":"ACESSOLONGOVINTELETRAS"}"# : #"{"erro":"Código incorreto. Restam 4 tentativas."}"#
            return RespostaCanal(status: ok ? 200 : 401, tipo: "application/json", corpo: Data(corpo.utf8))
        }
        esperarSync({ g.mac != nil }, "Mac chegou")
        let pareador = PareadorCabo(g)
        let achado = await pareador.procurarNoCabo().first { _ in true }
        let macAchado = try XCTUnwrap(achado)
        XCTAssertEqual(macAchado.nome, "MacBook do Leo")

        do { _ = try await pareador.parearComCodigo(macAchado, "000000"); XCTFail("devia recusar") } catch {
            XCTAssertEqual(error as? ErroPareamento, .recusado(Self.naoConfere))
        }
        XCTAssertTrue(mac.vistos.isEmpty, "dígitos errados nem chegam ao Mac: ele não os confirmou")
        let feito = try await pareador.parearComCodigo(macAchado, "482913")
        XCTAssertEqual(feito.pareado, Pareado(codigoAcesso: "ACESSOLONGOVINTELETRAS", nomeMac: "MacBook do Leo"))
        XCTAssertEqual(feito.canal.tipo, .cabo)
        let ultimo = try XCTUnwrap(mac.vistos.last)
        XCTAssertEqual(ultimo.metodo, "POST")
        XCTAssertEqual(ultimo.caminho, "/api/parear")
        XCTAssertTrue(ultimo.cabecalhos["x-deck-codigo"] == nil, "o pareamento não leva código de acesso")
    }

    func testPareamentoComCaboSoltoDaMensagemClara() async throws {
        let (g, _, _) = gerente()
        let pareador = PareadorCabo(g)
        let mac = MacEncontrado(id: "x", nome: "Mac", perto: true)
        do { _ = try await pareador.parearComCodigo(mac, "123456"); XCTFail() } catch {
            XCTAssertEqual(error as? ErroPareamento, .recusado("O cabo desconectou. Plugue de novo e tente outra vez."))
        }
    }

    func testBluetoothContinuaIndisponivelNestaFase() async {
        let (g, _, _) = gerente()
        let pareador = PareadorCabo(g)
        do { _ = try await pareador.iniciar(com: MacEncontrado(id: "x", nome: "x", perto: true)); XCTFail() } catch {
            XCTAssertEqual(error as? ErroPareamento, .indisponivel)
        }
    }

    // MARK: Casca

    @MainActor
    func testCascaPareadaUsaOCaboAoPlugarETiraAoDesplugar() async throws {
        let (g, porta, _) = gerente(segredo: "ABC")
        let quadro = Quadro()
        let casca = Casca(pareador: PareadorCabo(g), cofre: CofreEmMemoria(Pareado(codigoAcesso: "ABC", nomeMac: "Mac")), vibrar: {},
                          permanenciaNoCabo: 0, cabo: g)
        casca.executarJS = { quadro.js.append($0) }
        casca.iniciar()
        XCTAssertNil(casca.canais.obter())
        let mac = try MacFalso(porta: porta, segredo: "ABC")
        await esperar { casca.canais.obter()?.tipo == .cabo }
        XCTAssertEqual(casca.canais.obter()?.tipo, .cabo)
        XCTAssertTrue(quadro.js.contains("DeckNativo.canal(\"cabo\")"), "\(quadro.js)")

        let r = await casca.tratar(Data(#"{"op":"requisitar","metodo":"GET","caminho":"/api/estado","cabecalhos":{"x-deck-codigo":"ABC"}}"#.utf8))
        XCTAssertTrue(r.contains("\"status\":200"), r)

        mac.cair()
        await esperar { casca.canais.obter() == nil }
        XCTAssertNil(casca.canais.obter())
        let semMac = await casca.tratar(Data(#"{"op":"requisitar","metodo":"GET","caminho":"/api/estado"}"#.utf8))
        XCTAssertTrue(semMac.contains("semCanal"), semMac)

        // plugou de novo: o canal volta e o aviso de 3 segundos aparece de novo
        quadro.js = []
        _ = try MacFalso(porta: porta, segredo: "ABC")
        await esperar { casca.canais.obter()?.tipo == .cabo }
        XCTAssertTrue(quadro.js.contains("DeckNativo.canal(\"cabo\")"), "\(quadro.js)")
    }

    @MainActor
    func testCascaSemPareamentoNaoUsaOCaboComoCanal() async throws {
        let (g, porta, _) = gerente()
        let casca = Casca(pareador: PareadorCabo(g), cofre: CofreEmMemoria(), vibrar: {}, permanenciaNoCabo: 0, cabo: g)
        casca.iniciar()
        _ = try MacFalso(porta: porta)
        esperarSync({ g.mac != nil }, "Mac chegou")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(casca.canais.obter(), "sem código de acesso guardado o cabo só serve ao pareamento")
    }

    @MainActor
    func testFluxoCompletoDeParearPeloCabo() async throws {
        let (g, porta, _) = gerente()
        let mac = try MacFalso(porta: porta, digitos: "482913")
        mac.responder = { p in
            let ok = String(decoding: p.corpo, as: UTF8.self).contains("482913")
            let corpo = ok ? #"{"codigoAcesso":"ACESSOLONGOVINTELETRAS"}"# : #"{"erro":"Código incorreto."}"#
            return RespostaCanal(status: ok ? 200 : 401, tipo: "application/json", corpo: Data(corpo.utf8))
        }
        let cofre = CofreEmMemoria()
        let casca = Casca(pareador: PareadorCabo(g), cofre: cofre, vibrar: {}, permanenciaNoCabo: 0, cabo: g)
        casca.iniciar()
        _ = await casca.fluxo.tratar(.cabo)
        await esperar { casca.fluxo.estado.etapa == .codigo }
        XCTAssertEqual(casca.fluxo.estado.nomeMac, "MacBook do Leo")
        let erro = await casca.fluxo.tratar(.digitos("111111"))
        XCTAssertEqual(erro, Self.naoConfere)
        XCTAssertEqual(casca.fluxo.estado.etapa, .codigo)
        let semErro = await casca.fluxo.tratar(.digitos("482913"))
        XCTAssertNil(semErro)
        XCTAssertEqual(casca.fluxo.estado.etapa, .pronto)
        XCTAssertEqual(cofre.ler(), Pareado(codigoAcesso: "ACESSOLONGOVINTELETRAS", nomeMac: "MacBook do Leo"))
        XCTAssertEqual(casca.canais.obter()?.tipo, .cabo)
    }

    // MARK: Quem fala no cabo (qualquer app do iPhone alcança a porta)

    final class Cofres: @unchecked Sendable {
        let cofre: CofreEmMemoria
        init(_ c: String) { cofre = CofreEmMemoria(Pareado(codigoAcesso: c, nomeMac: "Mac")) }
    }

    func testIntrusoNaoTomaOLugarDoMacNemVeOCodigoNemSobrescreveOCofre() async throws {
        let (g, porta, _) = gerente(segredo: "CODIGOREALDOMAC1234")
        let legitimo = try MacFalso(porta: porta, nome: "Mac legitimo", segredo: "CODIGOREALDOMAC1234")
        esperarSync({ g.mac?.nome == "Mac legitimo" }, "o Mac de verdade entrou")
        let intruso = try MacFalso(porta: porta, nome: "Intruso")
        intruso.extras = ["X-Deck-Codigo-Novo": "LIXO"]
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(g.mac?.nome, "Mac legitimo", "o intruso não troca o Mac")

        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOREALDOMAC1234", nomeMac: "Mac"))
        let canais = CanalAtual()
        canais.definir(CanalCabo(g))
        let ponte = Ponte(canais: canais, cofre: cofre, vibrar: {})
        let r = await ponte.requisitar(MensagemPonte(op: "requisitar", metodo: "GET", caminho: "/api/estado", cabecalhos: ["X-Deck-Codigo": "CODIGOREALDOMAC1234"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(intruso.vistos.isEmpty, "o código de acesso não chegou ao intruso: \(intruso.vistos)")
        XCTAssertEqual(legitimo.vistos.count, 1)
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "CODIGOREALDOMAC1234", "o código guardado não foi sobrescrito")
    }

    func testPareadoSemMacDeVerdadeIntrusoSozinhoNaoViraMac() async throws {
        let (g, porta, _) = gerente(segredo: "CODIGOREALDOMAC1234")
        let intruso = try MacFalso(porta: porta, nome: "Intruso", segredo: "OUTROCODIGO")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(g.mac)
        do { _ = try await g.enviar(pedido()); XCTFail("devia falhar") } catch { XCTAssertEqual(error as? ErroCanal, .semCanal) }
        XCTAssertTrue(intruso.vistos.isEmpty)
    }

    func testPareadoNaoAceitaOlaSoltoSemProva() async throws {
        let (g, porta, _) = gerente(segredo: "CODIGOREALDOMAC1234")
        let falso = try MacFalso(porta: porta, nome: "SemProva")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(g.mac)
        falso.cair()
    }

    func testConexaoSemApresentacaoCaiNoPrazo() async throws {
        let (g, porta, _) = gerente()
        let mudo = try MacFalso(porta: porta, seApresenta: false)
        XCTAssertNil(g.mac)
        // o prazo é de 5 s: a conexão muda é largada e o fio fecha do lado do iPhone
        var fechou = false
        for _ in 0..<80 where !fechou {
            try await Task.sleep(nanoseconds: 100_000_000)
            fechou = mudo.fio.lerExato(1) == nil
        }
        XCTAssertTrue(fechou)
    }

    func testIntrusoNaoVeOsDigitosDoPareamentoNemDevolveCodigoFalso() async throws {
        let (g, porta, _) = gerente()
        let intruso = try MacFalso(porta: porta, nome: "Intruso")
        intruso.responder = { _ in
            RespostaCanal(status: 200, tipo: "application/json", corpo: Data(#"{"codigoAcesso":"FALSOFALSOFALSOFALSO"}"#.utf8))
        }
        esperarSync({ g.mac != nil }, "o intruso aparece na lista, como qualquer Mac sem prova")
        let pareador = PareadorCabo(g)
        do {
            _ = try await pareador.parearComCodigo(MacEncontrado(id: "Intruso", nome: "Intruso", perto: true), "123456")
            XCTFail("não devia parear com quem não prova os dígitos")
        } catch {
            XCTAssertEqual(error as? ErroPareamento, .recusado(Self.naoConfere))
        }
        XCTAssertTrue(intruso.vistos.isEmpty, "os dígitos não chegaram ao intruso: \(intruso.vistos)")
    }

    func testIntrusoNaoTomaAConexaoQueJaProvouOsDigitos() async throws {
        let (g, porta, _) = gerente()
        let mac = try MacFalso(porta: porta, nome: "Mac legitimo", digitos: "482913")
        mac.responder = { _ in RespostaCanal(status: 200, tipo: "application/json", corpo: Data(#"{"codigoAcesso":"ACESSOLONGOVINTELETRAS"}"#.utf8)) }
        esperarSync({ g.mac != nil }, "Mac chegou")
        let feito = try await PareadorCabo(g).parearComCodigo(MacEncontrado(id: "x", nome: "x", perto: true), "482913")
        XCTAssertEqual(feito.pareado.codigoAcesso, "ACESSOLONGOVINTELETRAS")
        let intruso = try MacFalso(porta: porta, nome: "Intruso")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(g.mac?.nome, "Mac legitimo")
        XCTAssertTrue(intruso.vistos.isEmpty)
    }

    func testMuitasConexoesSemProvaNaoEstouramOGerente() async throws {
        let (g, porta, _) = gerente(segredo: "CODIGOREALDOMAC1234")
        let todos = try (0..<(GerenteDoCabo.maximoDeCandidatas + 4)).map { _ in try MacFalso(porta: porta, nome: "Spam") }
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = try MacFalso(porta: porta, nome: "Real", segredo: "CODIGOREALDOMAC1234")
        _ = todos
        // as candidatas que passam do limite são recusadas, mas o Mac de verdade continua entrando quando há vaga
        for t in todos { t.cair() }
        try await Task.sleep(nanoseconds: 300_000_000)
        _ = try MacFalso(porta: porta, nome: "Real2", segredo: "CODIGOREALDOMAC1234")
        esperarSync({ g.mac != nil }, "o Mac de verdade entrou depois das candidatas caírem")
    }

    // MARK: HMAC

    func testSha256EHmacBatemComOsVetoresPublicados() {
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.sha256(Array("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.sha256([])),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // RFC 4231, caso 2
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.hmacSHA256(chave: Array("Jefe".utf8), mensagem: Array("what do ya want for nothing?".utf8))),
                       "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        // RFC 4231, caso 6: chave maior que o bloco
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.hmacSHA256(chave: [UInt8](repeating: 0xaa, count: 131),
                                                          mensagem: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))),
                       "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }
}
