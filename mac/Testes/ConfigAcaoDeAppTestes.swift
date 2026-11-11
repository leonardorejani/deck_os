import XCTest
@testable import Nucleo

/// A ação de app dentro da config: leitura tolerante, validação e ida e volta pelo PUT.
final class ConfigAcaoDeAppTestes: XCTestCase {
    private func ler(_ teclas: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(
            #"{"perfis":[{"id":"p","nome":"P","teclas":[\#(teclas)]}],"perfilAtivo":"p","nomeMac":"M","codigoAcesso":"abcdefghjkmnpqrstuvw"}"#.utf8))
    }

    private func config(_ t: Tecla) -> Config {
        Config(perfis: [Perfil(id: "p", nome: "P", teclas: [t])], perfilAtivo: "p", nomeMac: "M", codigoAcesso: "abcdefghjkmnpqrstuvw")
    }

    private func tecla(_ id: String, _ escolha: String?, tipo: String = "app") -> Tecla {
        Tecla(id: "t", nome: "Email", tipo: tipo, valor: "Mail", estado: nil, icone: nil, acao: AcaoDeApp(id: id, valor: escolha))
    }

    func testAcaoVoltaIgualDepoisDeGravarELer() throws {
        let c = config(tecla("mail-caixa", "UUID-1"))
        let volta = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(volta.perfis[0].teclas[0].acao, AcaoDeApp(id: "mail-caixa", valor: "UUID-1"))
    }

    func testTeclaSemAcaoNaoGanhaChaveNova() throws {
        let t = Tecla(id: "t", nome: "Mail", tipo: "app", valor: "Mail", estado: nil, icone: nil)
        let json = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        XCTAssertFalse(json.contains("acao"))
    }

    func testConfigAntigaSemAcaoContinuaLendoIgual() throws {
        let c = try ler(#"{"id":"t","nome":"Mail","tipo":"app","valor":"Mail"}"#)
        XCTAssertNil(c.perfis[0].teclas[0].acao)
        XCTAssertNil(Config.validar(c))
    }

    func testAcaoMalformadaViraNilEATeclaSobrevive() throws {
        for ruim in [#""acao":"texto""#, #""acao":5"#, #""acao":{"valor":"x"}"#, #""acao":{"id":7}"#, #""acao":[]"#, #""acao":null"#] {
            let c = try ler(#"{"id":"t","nome":"Mail","tipo":"app","valor":"Mail",\#(ruim)}"#)
            XCTAssertEqual(c.perfis[0].teclas.count, 1, ruim)
            XCTAssertNil(c.perfis[0].teclas[0].acao, ruim)
        }
    }

    func testAcaoDeUmIdDesconhecidoFicaNaLeituraMasNaoPassaNaValidacao() throws {
        let c = try ler(#"{"id":"t","nome":"Mail","tipo":"app","valor":"Mail","acao":{"id":"do-futuro","valor":"x"}}"#)
        XCTAssertEqual(c.perfis[0].teclas[0].acao?.id, "do-futuro")
        XCTAssertEqual(Config.validar(c), "A ação da tecla \"Email\" não existe.".replacingOccurrences(of: "Email", with: "Mail"))
    }

    func testValidacaoDasAcoes() {
        XCTAssertNil(Config.validar(config(tecla("mail-caixa", "UUID-1"))))
        XCTAssertNil(Config.validar(config(tecla("mail-novo", nil))))
        XCTAssertNil(Config.validar(config(tecla("link", "github.com"))))
        XCTAssertNil(Config.validar(config(tecla("gmail", "2"))))
        XCTAssertNil(Config.validar(config(tecla("notas-pasta", "x-coredata://1/ICFolder/p5"))))
        XCTAssertNil(Config.validar(config(tecla("calendario-hoje", nil))))
        XCTAssertNil(Config.validar(config(tecla("calendario-dia", "2026-12-25"))))
        XCTAssertNil(Config.validar(config(tecla("abrir-arquivo", "~/Downloads"))))

        XCTAssertEqual(Config.validar(config(tecla("mail-caixa", nil))), "A tecla \"Email\" está sem a escolha da ação.")
        XCTAssertEqual(Config.validar(config(tecla("notas-pasta", " "))), "A tecla \"Email\" está sem a escolha da ação.")
        XCTAssertEqual(Config.validar(config(tecla("link", "javascript:alert(1)"))), "O endereço da tecla \"Email\" não é válido.")
        XCTAssertEqual(Config.validar(config(tecla("gmail", "abc"))), "A conta do Gmail da tecla \"Email\" não é válida.")
        XCTAssertEqual(Config.validar(config(tecla("calendario-dia", "2026-02-30"))), "O dia da tecla \"Email\" não é válido.")
        XCTAssertEqual(Config.validar(config(tecla("abrir-arquivo", "Downloads"))), "O caminho da tecla \"Email\" precisa começar com / ou ~.")
        XCTAssertEqual(Config.validar(config(tecla("mail-novo", nil, tipo: "comando"))), "Só tecla de app pode ter ação (\"Email\").")
    }

    /// O iPhone grava a config inteira: a ação tem que sobreviver ao PUT e voltar no GET.
    func testAcaoSobreviveAoPutEVoltaNoGet() throws {
        let c = try Cenario()
        let corpo = String(decoding: try JSONEncoder().encode(config(tecla("gmail", "2"))), as: UTF8.self)
        let enviado = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(corpo.utf8)) as? [String: Any])
        var pub = enviado
        for k in ["codigoAcesso", "codigoCriadoEm", "codigoAnterior", "anteriorValeAte"] { pub.removeValue(forKey: k) }
        let put = c.pedir("PUT", "/api/config", corpo: String(decoding: try JSONSerialization.data(withJSONObject: pub), as: UTF8.self))
        XCTAssertEqual(put.status, 200, put.texto)
        let get = c.pedir("GET", "/api/config")
        let perfis = try XCTUnwrap((get.json as? [String: Any])?["perfis"] as? [[String: Any]])
        let teclas = try XCTUnwrap(perfis[0]["teclas"] as? [[String: Any]])
        let acao = try XCTUnwrap(teclas[0]["acao"] as? [String: Any])
        XCTAssertEqual(acao["id"] as? String, "gmail")
        XCTAssertEqual(acao["valor"] as? String, "2")
    }

    func testPutComAcaoInvalidaERecusadoENadaMuda() throws {
        let c = try Cenario()
        let antes = c.pedir("GET", "/api/config").texto
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(antes.utf8)) as? [String: Any])
        var perfis = try XCTUnwrap(obj["perfis"] as? [[String: Any]])
        var teclas = try XCTUnwrap(perfis[0]["teclas"] as? [[String: Any]])
        teclas[0]["tipo"] = "app"
        teclas[0]["valor"] = "Safari"
        teclas[0]["acao"] = ["id": "link", "valor": "javascript:alert(1)"]
        perfis[0]["teclas"] = teclas
        obj["perfis"] = perfis
        let put = c.pedir("PUT", "/api/config", corpo: String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
        XCTAssertEqual(put.status, 400)
        XCTAssertEqual(put.erroTexto, "O endereço da tecla \"Manter acordado\" não é válido.")
        XCTAssertEqual(c.pedir("GET", "/api/config").texto, antes)
    }

    /// Pelo botão: a tecla com ação roda a ação (e não só abre o app).
    func testBotaoDeTeclaComAcaoChegaAoExecutor() throws {
        let f = ExecutorDeAcoesFalso()
        let acoes = ExecutorAcoes(shell: f, temAcessibilidade: { true }, enviarTecla: { _ in })
        XCTAssertNil(acoes.executar(tecla("gmail", "1")))
        XCTAssertEqual(f.comandos, ["open -a 'Mail' 'https://mail.google.com/mail/u/1/#inbox'"])
    }
}
