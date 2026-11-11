import XCTest
@testable import DeckCasca

@MainActor
final class CascaTestes: XCTestCase {
    private func casca(cofre: Cofre = CofreEmMemoria(), pareador: Pareador = PareadorFalso()) -> (Casca, Quadro) {
        let quadro = Quadro()
        let c = Casca(pareador: pareador, cofre: cofre, vibrar: {}, permanenciaNoCabo: 0)
        c.executarJS = { quadro.js.append($0) }
        return (c, quadro)
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testPaginaPedeOEstadoNaAbertura() async throws {
        let (c, _) = casca()
        c.iniciar()
        let r = await c.tratar(json("{\"op\":\"estado\"}"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        let estado = try XCTUnwrap(obj["estado"] as? [String: Any])
        XCTAssertEqual(estado["etapa"] as? String, "vazio")
    }

    func testAcaoDaPaginaMexeNoFluxoEDevolveOEstado() async throws {
        let (c, _) = casca()
        c.iniciar()
        let r = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"procurar\"}"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        XCTAssertEqual((obj["estado"] as? [String: Any])?["etapa"] as? String, "procurando")
        XCTAssertNil(obj["erro"] as? String)
    }

    func testErroDoFluxoVoltaNaRespostaDaAcao() async throws {
        let (c, _) = casca()
        c.iniciar()
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"procurar\"}"))
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"cabo\"}"))
        await esperar { c.fluxo.estado.etapa == .codigo }
        let r = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"digitos\",\"digitos\":\"111111\"}"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        XCTAssertEqual(obj["erro"] as? String, "Código errado. Confira o que aparece no Mac.")
    }

    func testAcaoDesconhecidaNaoDerruba() async throws {
        let (c, _) = casca()
        c.iniciar()
        let r = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"voar\"}"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        XCTAssertNotNil(obj["erro"] as? String)
    }

    func testMensagemQueNaoEJSONNaoDerruba() async throws {
        let (c, _) = casca()
        let r = await c.tratar(json("isto não é json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        XCTAssertNotNil(obj["erro"] as? String)
    }

    func testRequisicaoPassaPelaPonteAteOCanal() async throws {
        let (c, _) = casca()
        let canal = CanalFalso()
        c.usar(canal: canal)
        let r = await c.tratar(json("{\"op\":\"requisitar\",\"metodo\":\"GET\",\"caminho\":\"/api/estado\",\"cabecalhos\":{\"x-deck-codigo\":\"C\"}}"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any])
        XCTAssertEqual(obj["status"] as? Int, 200)
        XCTAssertEqual(canal.pedidos.count, 1)
    }

    func testTrocaDeCanalAvisaAPaginaParaMostrarOAviso() {
        let (c, quadro) = casca()
        c.usar(canal: CanalFalso(.cabo))
        XCTAssertEqual(quadro.js.last, "DeckNativo.canal(\"cabo\")")
        c.usar(canal: CanalFalso(.bluetooth))
        XCTAssertEqual(quadro.js.last, "DeckNativo.canal(\"bluetooth\")")
    }

    func testMesmoCanalDeNovoNaoRepeteOAviso() {
        let (c, quadro) = casca()
        let canal = CanalFalso(.cabo)
        c.usar(canal: canal)
        let antes = quadro.js.count
        c.usar(canal: canal)
        XCTAssertEqual(quadro.js.count, antes)
    }

    func testPareamentoFeitoEntregaOCodigoEOCanalParaAPagina() async {
        let (c, quadro) = casca()
        c.iniciar()
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"procurar\"}"))
        await esperar { c.fluxo.estado.macs.count == 2 }
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"escolher\",\"id\":\"mac-1\"}"))
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"confirmar\",\"ok\":true}"))
        XCTAssertTrue(quadro.js.contains("DeckCanal.codigo(\"ABCDEFGHIJKLMNOPQRST\")"))
        XCTAssertEqual(c.canais.obter()?.tipo, .bluetooth)
    }

    func testEsquecerPedeParaRecarregarAPagina() async {
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let (c, _) = casca(cofre: cofre)
        var recarregou = 0
        c.recarregarPagina = { recarregou += 1 }
        c.iniciar()
        _ = await c.tratar(json("{\"op\":\"acao\",\"acao\":\"esquecer\"}"))
        XCTAssertEqual(recarregou, 1)
        XCTAssertNil(cofre.ler())
    }

    func testCodigoGuardadoVaiParaAPaginaNaAbertura() {
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let (c, _) = casca(cofre: cofre)
        XCTAssertTrue(c.scriptDeInicio().contains("\"codigo\":\"CODIGOATUAL\""))
        let (vazia, _) = casca()
        XCTAssertTrue(vazia.scriptDeInicio().contains("\"codigo\":null"))
    }
}

@MainActor
final class Quadro {
    var js: [String] = []
}
