import XCTest
@testable import Nucleo

// Só no Mac: é lá que existe Chaveiro, e o Linux do CI não expõe o XCTestCase por nome.
#if os(macOS)

final class AmbienteDeTesteTestes: XCTestCase {
    func testSobXCTestEstaAtivoEBloqueiaServicoReal() {
        var bloqueados: [String] = []
        let antes = AmbienteDeTeste.aoBloquear
        AmbienteDeTeste.aoBloquear = { bloqueados.append($0) }
        defer { AmbienteDeTeste.aoBloquear = antes }
        XCTAssertTrue(AmbienteDeTeste.ativo)
        XCTAssertFalse(AmbienteDeTeste.chaveiroPermitido(servico: "com.leonardorejani.deck.spotify"))
        XCTAssertTrue(AmbienteDeTeste.chaveiroPermitido(servico: "com.leonardorejani.deck.teste-abc"))
        XCTAssertEqual(bloqueados, ["com.leonardorejani.deck.spotify"])
    }
}
#endif
