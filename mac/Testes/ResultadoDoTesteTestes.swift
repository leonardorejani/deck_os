import XCTest
@testable import Nucleo

/// O "Testar" do editor de tecla: ok ou o erro em uma linha, e na tecla liga e desliga com comando que confere, como ela ficou.
final class ResultadoDoTesteTestes: XCTestCase {
    func testErroDoNucleoPassaIntacto() {
        XCTAssertEqual(ResultadoDoTeste.texto(erro: "Não achei o app Foo neste Mac", ms: 5, ligada: nil), "Não achei o app Foo neste Mac")
        XCTAssertEqual(ResultadoDoTeste.texto(erro: "O comando falhou", ms: 5, ligada: true), "O comando falhou")
    }

    func testOkMostraOTempo() {
        XCTAssertEqual(ResultadoDoTeste.texto(erro: nil, ms: 12, ligada: nil), "Ok, rodou em 12 ms")
    }

    func testLigaEDesligaDizComoFicou() {
        XCTAssertEqual(ResultadoDoTeste.texto(erro: nil, ms: 3, ligada: true), "Ok, rodou em 3 ms. Agora está ligada")
        XCTAssertEqual(ResultadoDoTeste.texto(erro: nil, ms: 3, ligada: false), "Ok, rodou em 3 ms. Agora está desligada")
    }

    func testTodoTipoDeTeclaDevolveErroEmUmaLinhaSemAcao() {
        let ex = ExecutorAcoes(shell: ExecutorFalso([]), limiteSegundos: 10, shellDoUsuario: { "/bin/zsh" }, memoria: MemoriaLigaDesliga())
        for tipo in ["app", "comando", "atalho", "tecla"] {
            let erro = ex.executar(Tecla(id: "x", nome: "X", tipo: tipo, valor: "", estado: nil, icone: nil))
            XCTAssertEqual(erro, "A tecla \"X\" está sem ação configurada", tipo)
        }
    }

    func testLigaEDesligaComConfereRodaOComandoEConfere() {
        let f = ExecutorFalso([("ligar", SaidaShell(status: 0, saida: "")), ("conferir", SaidaShell(status: 0, saida: ""))])
        let ex = ExecutorAcoes(shell: f, limiteSegundos: 10, shellDoUsuario: { "/bin/zsh" }, memoria: MemoriaLigaDesliga(), graca: 2)
        let t = Tecla(id: "l", nome: "L", tipo: "comando", valor: "ligar", estado: "conferir", icone: nil, desligar: "desligar")
        XCTAssertTrue(t.ligaEDesliga)
        XCTAssertNil(ex.executar(t))
        XCTAssertTrue(ex.conferir(t.comandoQueConfere!))
    }
}
