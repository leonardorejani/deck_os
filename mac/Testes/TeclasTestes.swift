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

    // MARK: Texto da combinação

    func testEscreveNaOrdemDoGravador() {
        XCTAssertEqual(Teclas.escrever(modificadores: [.comando, .controle, .opcao], tecla: "k"), "ctrl+opt+cmd+k")
        XCTAssertEqual(Teclas.escrever(modificadores: [.shift, .comando], tecla: "4"), "cmd+shift+4")
        XCTAssertEqual(Teclas.escrever(modificadores: [.fn, .comando], tecla: "f5"), "fn+cmd+f5")
    }

    func testEscreverRecusaSemModificadorOuTeclaDesconhecida() {
        XCTAssertNil(Teclas.escrever(modificadores: [], tecla: "k"))
        XCTAssertNil(Teclas.escrever(modificadores: [.comando], tecla: "zz"))
    }

    // MARK: Envio da combinação

    func testPassosDescemESobemComOsModificadores() {
        let c = Combinacao(codigo: 21, modificadores: [.comando, .shift])
        XCTAssertEqual(Teclas.passos(c), [
            PassoDeTecla(codigo: 21, descendo: true, modificadores: [.comando, .shift]),
            PassoDeTecla(codigo: 21, descendo: false, modificadores: [.comando, .shift]),
        ])
    }
}
