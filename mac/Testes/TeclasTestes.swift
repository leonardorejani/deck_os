import XCTest
@testable import Nucleo

final class TeclasTestes: XCTestCase {
    func testCombinacaoComModificadores() {
        XCTAssertEqual(Teclas.ler("ctrl+opt+cmd+k"),
                       Combinacao(codigo: 40, modificadores: [.controle, .opcao, .comando]))
    }

    func testNomesAlternativosEMaiusculas() {
        XCTAssertEqual(Teclas.ler("Command + Shift + Espaco"),
                       Combinacao(codigo: 49, modificadores: [.comando, .shift]))
        XCTAssertEqual(Teclas.ler("alt+esquerda"), Combinacao(codigo: 123, modificadores: [.opcao]))
    }

    func testRecusaTeclaDesconhecidaDuasTeclasOuSoModificador() {
        XCTAssertNil(Teclas.ler("ctrl+zz"))
        XCTAssertNil(Teclas.ler("a+b"))
        XCTAssertNil(Teclas.ler("cmd+shift"))
        XCTAssertNil(Teclas.ler(""))
    }
}
