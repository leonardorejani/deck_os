import XCTest
@testable import DeckCasca

/// Item 9 (conexão com diagnóstico): a tela diz a causa em vez de erro genérico, e as novas tentativas se espaçam em
/// 1, 2, 4, 8, 16 e 30 s. A ordem dos degraus e o texto de cada causa são os mesmos do painel (painel/canal.js).
@MainActor
final class DiagnosticoTestes: XCTestCase {
    func testEscalaDeEsperaSobeEFicaEmTrintaSegundos() {
        XCTAssertEqual((1...8).map { EscalaDeEspera.degrau($0) }, [1, 2, 4, 8, 16, 30, 30, 30])
        XCTAssertEqual(EscalaDeEspera.degrau(0), 1, "antes da primeira falha vale o degrau mínimo")
    }

    func testTextosDasCausas() {
        XCTAssertEqual(CausaDaConexao.macIndisponivel.texto(tentativa: 3), "Mac indisponível. Tentando de novo. Tentativa 3.")
        XCTAssertEqual(CausaDaConexao.codigoExpirou.texto(), "O código expirou. Leia o QR de novo no Mac.")
        XCTAssertEqual(CausaDaConexao.identidadeMudou.texto(), "A identidade do Mac mudou. Pareie de novo.")
    }

    func testMacAusenteEspacaAsTentativasEmDegraus() async throws {
        let radio = RadioFalso(MacDeTeste(), anuncios: [])
        radio.recusaConectar = true
        let esperas = Linhas()
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "ABCDEFGHIJKLMNOPQRST", nomeMac: "MacBook Pro de Exemplo", idBluetooth: "mac-1"))
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo",
                                 esperaEntreTentativas: { esperas.anotar("\($0)"); return 0.01 },
                                 prazoDaConexaoDireta: 0.1, prazoDaProcura: 0.05)
        addTeardownBlock { g.parar() }
        g.iniciar()
        await esperar({ esperas.todas.count >= 7 }, segundos: 10)
        let vistas = esperas.todas.prefix(7).compactMap { Double($0) }
        XCTAssertEqual(vistas, [1, 2, 4, 8, 16, 30, 30], "\(esperas.todas)")
        XCTAssertTrue(g.situacao?.hasPrefix("Mac indisponível") == true, "a tela não disse a causa: \(String(describing: g.situacao))")
    }

    func testMacQueRecusaOCodigoDizQueOCodigoExpirou() async throws {
        let mac = MacDeTeste(codigoAcesso: "OUTROCODIGOOUTROCODI")
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOVELHOCODIGOVEL", nomeMac: "MacBook Pro de Exemplo", idBluetooth: "mac-1"))
        let g = GerenteBluetooth(radio: RadioFalso(mac), cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 })
        let vistas = Linhas()
        g.aoMudarSituacao { if let s = $0 { vistas.anotar(s) } }
        addTeardownBlock { g.parar() }
        g.iniciar()
        await esperar({ vistas.todas.contains(CausaDaConexao.codigoExpirou.texto()) }, segundos: 5)
        XCTAssertTrue(vistas.todas.contains("O código expirou. Leia o QR de novo no Mac."), "\(vistas.todas)")
    }

    func testSoHaOutroMacPorPertoDizQueAIdentidadeMudou() async throws {
        // O id guardado não responde e o único Mac achado pela procura não conhece este iPhone.
        let outro = MacDeTeste(codigoAcesso: "OUTROCODIGOOUTROCODI")
        let radio = RadioComEnderecoNovo(mac: outro, velho: "mac-1", novo: "mac-2")
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOVELHOCODIGOVEL", nomeMac: "MacBook Pro de Exemplo", idBluetooth: "mac-1"))
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 },
                                 prazoDaConexaoDireta: 0.1, prazoDaProcura: 0.05)
        let vistas = Linhas()
        g.aoMudarSituacao { if let s = $0 { vistas.anotar(s) } }
        addTeardownBlock { g.parar() }
        g.iniciar()
        await esperar({ vistas.todas.contains(CausaDaConexao.identidadeMudou.texto()) }, segundos: 6)
        XCTAssertTrue(vistas.todas.contains("A identidade do Mac mudou. Pareie de novo."), "\(vistas.todas)")
    }
}
