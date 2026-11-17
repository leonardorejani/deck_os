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

    /// A partida do app não lê o Chaveiro: o modelo nasce sem tocar no armazém e só `atualizar()` o lê, fora da linha principal.
    func testModeloDoSpotifyNaPartidaNaoLeOArmazem() async {
        final class Espiao: ArmazemSpotify, @unchecked Sendable {
            let trava = NSLock(); var n = 0; var naPrincipal = 0
            func marcar() { trava.lock(); n += 1; if Thread.isMainThread { naPrincipal += 1 }; trava.unlock() }
            func ler() -> DadosSpotify { marcar(); return DadosSpotify(clientId: nil, acesso: "A", renovacao: "R", expiraEm: 1e12, nome: "Leo") }
            func gravar(_ d: DadosSpotify) -> Bool { marcar(); return true }
            func apagar() { marcar() }
        }
        let espiao = Espiao()
        let m = ModeloSpotify(conta: ContaSpotify(armazem: espiao, transporte: TransporteUrlSession()), lerNaPartida: false)
        XCTAssertEqual(espiao.n, 0, "nascer não toca no Chaveiro")
        XCTAssertFalse(m.conectado)
        m.atualizar()
        for _ in 0..<100 where !m.conectado { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(m.conectado)
        XCTAssertGreaterThan(espiao.n, 0)
        XCTAssertEqual(espiao.naPrincipal, 0, "a leitura do Chaveiro nunca roda na linha principal")
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
