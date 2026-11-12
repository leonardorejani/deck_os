import XCTest
@testable import Deck

/// O Deck de Debug é o hospedeiro destes testes. Se ele (ou um teste) tocar no Chaveiro real, o macOS
/// pergunta a senha na tela do dono. Aqui o toque é bloqueado e contado: tem que dar zero.
@MainActor
final class ChaveiroIsoladoTestes: XCTestCase {
    private var bloqueados: [String] = []
    private var antes: ((String) -> Void)!

    override func setUp() {
        antes = AmbienteDeTeste.aoBloquear
        bloqueados = []
        AmbienteDeTeste.aoBloquear = { [unowned self] in bloqueados.append($0) }
    }
    override func tearDown() { AmbienteDeTeste.aoBloquear = antes }

    func testHospedeiroSeReconheceComoTeste() {
        XCTAssertTrue(AmbienteDeTeste.ativo)
    }

    func testModeloDeVerdadeNaoTocaNoChaveiro() {
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("deck-chaveiro-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teste-\(UUID())")!)
        _ = m.spotify.conectado
        m.spotify.atualizar()
        XCTAssertEqual(bloqueados, [], "ModeloApp(arquivo:) usou o Chaveiro real no teste")
    }

    func testChaveiroRealDoSpotifyFicaBloqueadoNoTeste() {
        let a = ArmazemSpotifyChaveiro()
        _ = a.ler()
        XCTAssertFalse(a.gravar(DadosSpotify()))
        a.apagar()
        XCTAssertEqual(bloqueados.count, 3)
        XCTAssertEqual(Set(bloqueados), ["com.leonardorejani.deck.spotify"])
    }

    func testChaveiroRealDoTokenFicaBloqueadoNoTeste() {
        let c = Chaveiro()
        XCTAssertNil(c.ler(conta: "x"))
        XCTAssertThrowsError(try c.guardar("t", conta: "x"))
        c.apagar(conta: "x")
        XCTAssertEqual(bloqueados.count, 3)
    }

    func testServicoDeTesteIsoladoPassa() {
        XCTAssertTrue(AmbienteDeTeste.chaveiroPermitido(servico: "com.leonardorejani.deck.teste-\(UUID())"))
        XCTAssertEqual(bloqueados, [])
    }

    func testUsoModeloPadraoUsaMemoria() {
        let u = PainelUso()
        XCTAssertTrue(u.cofre is CofreEmMemoria)
    }
}
