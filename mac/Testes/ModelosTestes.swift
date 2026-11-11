import XCTest
@testable import Nucleo

final class ModelosTestes: XCTestCase {
    /// O config.json do Mac tem que ler o mesmo formato que o protótipo grava (dados.js, configAtual).
    func testLeOFormatoDoPrototipo() throws {
        let json = """
        {"versao":1,"perfis":[{"id":"trabalho","nome":"Trabalho","teclas":[
          {"id":"acordado","nome":"Manter acordado","tipo":"tecla","valor":"ctrl+opt+cmd+k","icone":"Vorssaint"},
          {"id":"apagar","nome":"Apagar tela","tipo":"comando","valor":"pmset displaysleepnow","icone":"svg:tela"}]}],
         "perfilAtivo":"trabalho","comp":"b",
         "contas":[{"id":"codex","nome":"Codex","conta":"pro"}],
         "blocos":{"spotify":false,"agenda":true,"whatsapp":true,"sessoes":true,"uso":true},
         "nomeMac":"MacBook Pro de Exemplo","porta":4777,"codigoAcesso":"abcdefghjkmnpqrstuvw"}
        """
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.perfis[0].teclas[1].icone, "svg:tela")
        XCTAssertEqual(c.comp, "b")
        XCTAssertFalse(c.blocos.spotify)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c)), c)
    }

    func testExecutorDevolveStatusESaida() {
        let r = ExecutorShell().rodar("echo oi; exit 3")
        XCTAssertEqual(r.status, 3)
        XCTAssertEqual(r.saida, "oi\n")
    }
}
