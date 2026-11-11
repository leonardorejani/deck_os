import XCTest
@testable import DeckCasca

final class PonteTestes: XCTestCase {
    private func ponte(canal: CanalFalso?, cofre: Cofre = CofreEmMemoria(), vibracoes: Vibracoes = Vibracoes(),
                       novoCodigo: @escaping @Sendable (String) -> Void = { _ in }) -> (Ponte, CanalAtual) {
        let atual = CanalAtual()
        if let canal { atual.definir(canal) }
        return (Ponte(canais: atual, cofre: cofre, vibrar: { vibracoes.vibrou() }, aoCodigoNovo: novoCodigo), atual)
    }

    private func pedido(_ metodo: String, _ caminho: String, query: [String: String] = [:], corpo: String? = nil) -> MensagemPonte {
        MensagemPonte(op: "requisitar", metodo: metodo, caminho: caminho, query: query,
                      cabecalhos: ["x-deck-codigo": "CODIGOATUAL"], corpo: corpo)
    }

    func testPedidoChegaAoCanalComOsCabecalhosEOCorpo() async throws {
        let canal = CanalFalso()
        canal.resposta = RespostaCanal(status: 200, tipo: "application/json", corpo: Data("{\"nomeMac\":\"Mac\"}".utf8), cabecalhos: [:])
        let (p, _) = ponte(canal: canal)
        let r = await p.requisitar(pedido("PUT", "/api/config", query: ["a": "1"], corpo: "{\"comp\":\"b\"}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.corpo, "{\"nomeMac\":\"Mac\"}")
        XCTAssertNil(r.erro)
        let enviado = try XCTUnwrap(canal.pedidos.first)
        XCTAssertEqual(enviado.metodo, "PUT")
        XCTAssertEqual(enviado.caminho, "/api/config")
        XCTAssertEqual(enviado.query, ["a": "1"])
        XCTAssertEqual(enviado.cabecalhos["x-deck-codigo"], "CODIGOATUAL")
        XCTAssertEqual(String(decoding: enviado.corpo, as: UTF8.self), "{\"comp\":\"b\"}")
    }

    func testSemCanalDizQueNaoDeuParaFalarComOMac() async {
        let (p, _) = ponte(canal: nil)
        let r = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertEqual(r.erro, "semCanal")
        XCTAssertNil(r.status)
    }

    func testFalhaDoCanalVoltaComOTextoPronto() async {
        let canal = CanalFalso()
        canal.falha = .falhou("O cabo foi desplugado.")
        let (p, _) = ponte(canal: canal)
        let r = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertEqual(r.erro, "canal")
        XCTAssertEqual(r.mensagem, "O cabo foi desplugado.")
    }

    /// Rodízio do código: o Mac manda o novo em X-Deck-Codigo-Novo e a página precisa recebê-lo.
    func testCabecalhoDoCodigoNovoChegaNaPaginaEFicaNoCofre() async {
        let canal = CanalFalso()
        canal.resposta = RespostaCanal(status: 200, tipo: "application/json", corpo: Data("{}".utf8),
                                       cabecalhos: ["X-Deck-Codigo-Novo": "CODIGONOVOQQQQQQQQQQ"])
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let (p, _) = ponte(canal: canal, cofre: cofre)
        let r = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertEqual(r.codigoNovo, "CODIGONOVOQQQQQQQQQQ")
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "CODIGONOVOQQQQQQQQQQ")
        XCTAssertEqual(cofre.ler()?.nomeMac, "Mac")
    }

    func testRespostaSemOCabecalhoNaoTrazCodigoNovo() async {
        let (p, _) = ponte(canal: CanalFalso())
        let r = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertNil(r.codigoNovo)
    }

    func testCabecalhoVazioNaoApagaOCodigo() async {
        let canal = CanalFalso()
        canal.resposta = RespostaCanal(status: 200, tipo: "application/json", corpo: Data("{}".utf8), cabecalhos: ["x-deck-codigo-novo": " "])
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let (p, _) = ponte(canal: canal, cofre: cofre)
        let r = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertNil(r.codigoNovo)
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "CODIGOATUAL")
    }

    func testToqueDeTeclaVibraEEstadoNao() async {
        let v = Vibracoes()
        let (p, _) = ponte(canal: CanalFalso(), vibracoes: v)
        _ = await p.requisitar(pedido("GET", "/api/estado"))
        XCTAssertEqual(v.total, 0)
        _ = await p.requisitar(pedido("POST", "/api/botao/acordado"))
        XCTAssertEqual(v.total, 1)
    }

    func testToqueVibraMesmoSemMacParaResponderAoDedo() async {
        let v = Vibracoes()
        let (p, _) = ponte(canal: nil, vibracoes: v)
        _ = await p.requisitar(pedido("POST", "/api/botao/acordado"))
        XCTAssertEqual(v.total, 1)
    }

    // MARK: Capa

    func testEnderecoDaCapaViraPedidoComOCodigoNaQuery() throws {
        let url = try XCTUnwrap(URL(string: "deckcapa://capa/?codigo=CODIGOATUAL&v=abc%20123"))
        let p = try XCTUnwrap(Ponte.pedidoDaCapa(url))
        XCTAssertEqual(p.metodo, "GET")
        XCTAssertEqual(p.caminho, "/api/capa")
        XCTAssertEqual(p.query["codigo"], "CODIGOATUAL")
        XCTAssertEqual(p.query["v"], "abc 123")
        XCTAssertEqual(p.cabecalhos["x-deck-codigo"], "CODIGOATUAL")
    }

    func testEnderecoDeOutroEsquemaNaoViraPedido() throws {
        XCTAssertNil(Ponte.pedidoDaCapa(try XCTUnwrap(URL(string: "https://exemplo.com/api/capa"))))
    }

    func testCapaDevolveOsBytesEOTipo() async throws {
        let canal = CanalFalso()
        canal.resposta = RespostaCanal(status: 200, tipo: "image/png", corpo: Data([0x89, 0x50, 0x4E, 0x47]), cabecalhos: [:])
        let (p, _) = ponte(canal: canal)
        let r = await p.capa(try XCTUnwrap(URL(string: "deckcapa://capa/?codigo=X&v=1")))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.tipo, "image/png")
        XCTAssertEqual(r.corpo, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testIconeDeAppVaiParaARotaDeIcones() throws {
        let url = try XCTUnwrap(URL(string: "deckcapa://apps/com.apple.mail/icone?codigo=CODIGOATUAL"))
        let p = try XCTUnwrap(Ponte.pedidoDaCapa(url))
        XCTAssertEqual(p.caminho, "/api/apps/com.apple.mail/icone")
        XCTAssertEqual(p.metodo, "GET")
        XCTAssertEqual(p.cabecalhos["x-deck-codigo"], "CODIGOATUAL")
    }

    func testEnderecoDeIconeForaDoFormatoNaoViraPedido() throws {
        for ruim in ["deckcapa://apps/../config/icone?codigo=X", "deckcapa://apps/com.apple.mail/acoes?codigo=X", "deckcapa://apps//icone?codigo=X",
                     "deckcapa://apps/a%2Fb/icone?codigo=X", "deckcapa://apps/com.apple.mail/icone/x?codigo=X", "deckcapa://config/?codigo=X", "deckcapa://apps?codigo=X"] {
            XCTAssertNil(Ponte.pedidoDaCapa(try XCTUnwrap(URL(string: ruim))), ruim)
        }
    }

    func testCapaSemCanalDa503() async throws {
        let (p, _) = ponte(canal: nil)
        let r = await p.capa(try XCTUnwrap(URL(string: "deckcapa://capa/?codigo=X&v=1")))
        XCTAssertEqual(r.status, 503)
    }

    func testCodigoNovoVindoDaCapaAvisaAPagina() async throws {
        let canal = CanalFalso()
        canal.resposta = RespostaCanal(status: 200, tipo: "image/png", corpo: Data([1]), cabecalhos: ["x-deck-codigo-novo": "NOVONOVONOVONOVONOVO"])
        let visto = Visto()
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let (p, _) = ponte(canal: canal, cofre: cofre, novoCodigo: { visto.guardar($0) })
        _ = await p.capa(try XCTUnwrap(URL(string: "deckcapa://capa/?codigo=CODIGOATUAL&v=1")))
        XCTAssertEqual(visto.valor, "NOVONOVONOVONOVONOVO")
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "NOVONOVONOVONOVONOVO")
    }

    // MARK: Contrato de fio (as fases 6 e 7 levam isto entre o iPhone e o Mac)

    func testPedidoERespostaViajamEmJSON() throws {
        let p = PedidoCanal(metodo: "POST", caminho: "/api/botao/x", query: ["a": "b"], cabecalhos: ["x-deck-codigo": "C"], corpo: Data("{}".utf8))
        XCTAssertEqual(try JSONDecoder().decode(PedidoCanal.self, from: JSONEncoder().encode(p)), p)
        let r = RespostaCanal(status: 422, tipo: "application/json", corpo: Data("{\"erro\":\"x\"}".utf8), cabecalhos: ["X-Deck-Codigo-Novo": "N"])
        XCTAssertEqual(try JSONDecoder().decode(RespostaCanal.self, from: JSONEncoder().encode(r)), r)
        XCTAssertEqual(r.cabecalho("x-deck-codigo-novo"), "N")
    }
}

final class Visto: @unchecked Sendable {
    private let trava = NSLock()
    private var v: String?
    var valor: String? { trava.lock(); defer { trava.unlock() }; return v }
    func guardar(_ s: String) { trava.lock(); v = s; trava.unlock() }
}
