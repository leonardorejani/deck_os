import XCTest
@testable import DeckCasca

final class InstalacaoTestes: XCTestCase {
    /// Um embedded.mobileprovision de mentira: bytes de envelope CMS em volta do plist, como o de verdade.
    private func perfil(venceEm: String = "2026-11-26T18:00:00Z", equipe: String = "EQUIPE0001", app: String = "EQUIPE0001.com.exemplo.deck") -> Data {
        var d = Data([0x30, 0x82, 0x0a, 0xff, 0x06, 0x09, 0x2a])
        d.append(Data("""
            <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>ExpirationDate</key><date>\(venceEm)</date>
            <key>TeamIdentifier</key><array><string>\(equipe)</string></array>
            <key>Entitlements</key><dict><key>application-identifier</key><string>\(app)</string></dict></dict></plist>
            """.utf8))
        d.append(Data([0xa0, 0x03, 0x02, 0x01, 0x00, 0xff]))
        return d
    }

    func testLeVencimentoEquipeEPacoteDoPerfil() {
        let lido = PerfilDeProvisionamento.ler(perfil())
        XCTAssertEqual(lido?.venceEm, ISO8601DateFormatter().date(from: "2026-11-26T18:00:00Z"))
        XCTAssertEqual(lido?.equipe, "EQUIPE0001")
        XCTAssertEqual(lido?.pacote, "com.exemplo.deck")
    }

    func testArquivoSemPlistNaoViraNada() {
        XCTAssertNil(PerfilDeProvisionamento.ler(Data([1, 2, 3, 4])))
        XCTAssertNil(PerfilDeProvisionamento.ler(Data()))
    }

    func testInformaOPacoteDoProprioAppEOVencimentoDoPerfil() {
        // o SideStore re-assina com o pacote mudado: o que vale é o pacote que o app tem de verdade
        let i = PerfilDeProvisionamento.instalacao(perfil: perfil(), versao: "1.2 (1)", bundleId: "com.exemplo.deck.EQUIPE0001")
        XCTAssertEqual(i.bundleId, "com.exemplo.deck.EQUIPE0001")
        XCTAssertEqual(i.equipe, "EQUIPE0001")
        XCTAssertEqual(i.versao, "1.2 (1)")
        XCTAssertEqual(i.venceEm, ISO8601DateFormatter().date(from: "2026-11-26T18:00:00Z"))
    }

    func testSemPerfilVaiSoOQueOAppSabeDeSi() {
        let i = PerfilDeProvisionamento.instalacao(perfil: nil, versao: "1.2 (1)", bundleId: "a.b")
        XCTAssertEqual(i, InstalacaoDoApp(versao: "1.2 (1)", bundleId: "a.b"))
    }

    func testCorpoUsaDataIsoQueOMacLe() throws {
        let i = InstalacaoDoApp(versao: "1.2 (1)", bundleId: "a.b", equipe: "T", venceEm: ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z"))
        let json = try XCTUnwrap(String(data: i.corpo(), encoding: .utf8))
        XCTAssertEqual(json, #"{"bundleId":"a.b","equipe":"T","venceEm":"2027-01-10T12:00:00Z","versao":"1.2 (1)"}"#)
    }

    @MainActor
    func testPonteMandaOPostComOCodigoEAceitaORodizio() async {
        let canais = CanalAtual()
        let canal = CanalFalso(.cabo)
        canais.definir(canal)
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let ponte = Ponte(canais: canais, cofre: cofre, vibrar: {})
        let ok = await ponte.informar(InstalacaoDoApp(versao: "1.2 (1)", bundleId: "a.b"))
        XCTAssertTrue(ok)
        let pedido = canal.pedidos.last
        XCTAssertEqual(pedido?.metodo, "POST")
        XCTAssertEqual(pedido?.caminho, "/api/app/instalacao")
        XCTAssertEqual(pedido?.cabecalhos["x-deck-codigo"], "CODIGOATUAL")
    }

    func testSemCanalOuSemPareamentoNaoInforma() async {
        let ponte = Ponte(canais: CanalAtual(), cofre: CofreEmMemoria(Pareado(codigoAcesso: "X", nomeMac: "Mac")), vibrar: {})
        let a = await ponte.informar(InstalacaoDoApp())
        XCTAssertFalse(a)
        let canais = CanalAtual(); canais.definir(CanalFalso(.cabo))
        let b = await Ponte(canais: canais, cofre: CofreEmMemoria(), vibrar: {}).informar(InstalacaoDoApp())
        XCTAssertFalse(b)
    }
}
