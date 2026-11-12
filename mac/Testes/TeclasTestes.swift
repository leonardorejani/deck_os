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

    // MARK: Montagem na tela (atalho de outro app que o gravador não alcança)

    func testEscreveNaOrdemDoGravador() {
        XCTAssertEqual(Teclas.escrever(modificadores: [.comando, .controle, .opcao], tecla: "k"), "ctrl+opt+cmd+k")
        XCTAssertEqual(Teclas.escrever(modificadores: [.shift, .comando], tecla: "4"), "cmd+shift+4")
        XCTAssertEqual(Teclas.escrever(modificadores: [.fn, .comando], tecla: "f5"), "fn+cmd+f5")
    }

    func testEscreverRecusaSemModificadorOuTeclaDesconhecida() {
        XCTAssertNil(Teclas.escrever(modificadores: [], tecla: "k"))
        XCTAssertNil(Teclas.escrever(modificadores: [.comando], tecla: "zz"))
    }

    func testTextoEscritoVoltaIgualPeloNucleo() {
        for t in Teclas.grupos.flatMap(\.teclas) {
            let texto = Teclas.escrever(modificadores: [.controle, .comando, .shift], tecla: t.nome)
            XCTAssertNotNil(texto, "a tecla \(t.nome) do seletor tem que ser entendida pelo núcleo")
            let c = Teclas.ler(texto ?? "")
            XCTAssertEqual(c?.codigo, Teclas.codigos[t.nome])
            XCTAssertEqual(c?.modificadores, [.controle, .comando, .shift])
        }
    }

    func testSeletorNaoRepeteTeclaNemRotulo() {
        let todas = Teclas.grupos.flatMap(\.teclas)
        XCTAssertEqual(Set(todas.map(\.nome)).count, todas.count)
        XCTAssertTrue(todas.allSatisfy { !$0.rotulo.isEmpty })
    }

    func testMontagemSoTemValorQuandoCompleta() {
        var m = MontagemDeCombinacao()
        XCTAssertNil(m.valor)
        XCTAssertEqual(m.faltaDizer, "Ligue pelo menos um modificador e escolha a tecla.")
        m.tecla = "4"
        XCTAssertNil(m.valor)
        XCTAssertEqual(m.faltaDizer, "Ligue pelo menos um modificador.")
        m.alternar(.comando); m.alternar(.shift)
        XCTAssertEqual(m.valor, "cmd+shift+4")
        XCTAssertNil(m.faltaDizer)
        m.alternar(.comando); m.alternar(.shift)
        XCTAssertNil(m.valor, "desligar os modificadores tira o valor")
    }

    func testMontagemParteDoTextoJaGravado() {
        let m = MontagemDeCombinacao(valor: "ctrl+opt+cmd+k")
        XCTAssertEqual(m.modificadores, [.controle, .opcao, .comando])
        XCTAssertEqual(m.tecla, "k")
        XCTAssertEqual(m.valor, "ctrl+opt+cmd+k")
        XCTAssertEqual(MontagemDeCombinacao(valor: "isso nao e combinacao"), MontagemDeCombinacao())
        XCTAssertEqual(MontagemDeCombinacao(valor: "alt+esquerda").tecla, "left", "apelido vira o nome do seletor")
    }

    func testMontagemSerializaComoOGravadorEscreveria() {
        // cmd+shift+4 é a captura de parte da tela do macOS, o mesmo que o CleanShot pede
        var m = MontagemDeCombinacao()
        m.alternar(.shift); m.alternar(.comando); m.tecla = "4"
        XCTAssertEqual(m.valor, "cmd+shift+4")
        XCTAssertEqual(Teclas.ler(m.valor ?? ""), Combinacao(codigo: 21, modificadores: [.comando, .shift]))
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
