import XCTest
@testable import Nucleo

final class ConfigTestes: XCTestCase {
    private func ler(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    func testPadraoEhValidoComAsTeclasDaSpec() {
        let c = Config.padrao(nomeMac: "Meu Mac")
        XCTAssertNil(Config.validar(c))
        XCTAssertEqual(c.nomeMac, "Meu Mac")
        XCTAssertEqual(c.perfis.map(\.nome), ["Trabalho"])
        let t = c.perfis[0].teclas
        XCTAssertEqual(t.map(\.nome), ["Manter acordado", "WhatsApp", "Agenda", "Apagar tela"])
        XCTAssertEqual(t[0].valor, "ctrl+opt+cmd+k")
        XCTAssertEqual(t[0].icone, "Vorssaint")
        XCTAssertEqual(t[0].estado, "pmset -g assertions | grep -q 'Vorssaint: keep the Mac awake'")
        XCTAssertEqual(t[2].valor, "Calendar")
        XCTAssertEqual(t[3].icone, "svg:tela")
        XCTAssertTrue(c.contas.isEmpty)
    }

    func testCodigoDeAcessoTem20LetrasDoAlfabetoESorteiaDiferente() {
        let a = Config.novoCodigoAcesso(), b = Config.novoCodigoAcesso()
        XCTAssertEqual(a.count, 20)
        XCTAssertTrue(a.allSatisfy { Config.alfabetoCodigo.contains($0) })
        XCTAssertNotEqual(a, b)
    }

    func testDecodificacaoAceitaChavesFaltando() throws {
        let c = try ler(#"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","nomeMac":"M","codigoAcesso":"abcdefghjkmnpqrstuvw","blocos":{"agenda":false}}"#)
        XCTAssertEqual(c.versao, 1)
        XCTAssertEqual(c.comp, "a")
        XCTAssertEqual(c.porta, 4777)
        XCTAssertTrue(c.contas.isEmpty)
        XCTAssertFalse(c.blocos.agenda)
        XCTAssertTrue(c.blocos.spotify)
        XCTAssertNil(Config.validar(c))
    }

    func testMigraConfigAntigaDoPrototipo() throws {
        let c = try ler(#"""
        {"teclas":[{"id":"w","nome":"WhatsApp","tipo":"painel","valor":"whatsapp"},
                   {"id":"c","nome":"Agenda","tipo":"painel","valor":"calendario"},
                   {"id":"x","nome":"Outro","tipo":"painel","valor":"sumiu"},
                   {"id":"a","nome":"Spotify","tipo":"app","valor":"Spotify","acesa":true}],
         "comp":"b","nomeMac":"M","perfilAtivo":"fantasma"}
        """#)
        XCTAssertEqual(c.perfis.count, 1)
        XCTAssertEqual(c.perfis[0].id, "principal")
        XCTAssertEqual(c.perfis[0].nome, "Principal")
        XCTAssertEqual(c.perfilAtivo, "principal")
        let t = c.perfis[0].teclas
        XCTAssertEqual(t.map(\.id), ["w", "c", "a"])
        XCTAssertEqual(t[0].tipo, "app"); XCTAssertEqual(t[0].valor, "WhatsApp")
        XCTAssertEqual(t[1].tipo, "app"); XCTAssertEqual(t[1].valor, "Calendar")
        XCTAssertEqual(c.comp, "b")
    }

    func testPerfilAtivoInexistenteCaiNoPrimeiro() throws {
        let c = try ler(#"{"perfis":[{"id":"a","nome":"A","teclas":[]},{"id":"b","nome":"B","teclas":[]}],"perfilAtivo":"z"}"#)
        XCTAssertEqual(c.perfilAtivo, "a")
    }

    func testValidarRecusaComMensagemEmPortugues() {
        func com(_ ajuste: (inout Config) -> Void) -> String? {
            var c = Config.padrao(nomeMac: "M"); ajuste(&c); return Config.validar(c)
        }
        XCTAssertEqual(com { $0.perfis = [] }, "É preciso ter pelo menos um perfil.")
        XCTAssertNotNil(com { $0.perfis.append($0.perfis[0]) })
        XCTAssertNotNil(com { $0.perfis[0].nome = "  " })
        XCTAssertNotNil(com { $0.perfis[0].teclas.append($0.perfis[0].teclas[0]) })
        XCTAssertNotNil(com { $0.perfis[0].teclas[0].nome = "" })
        XCTAssertNotNil(com { $0.perfis[0].teclas[0].tipo = "painel" })
        XCTAssertNotNil(com { $0.perfis[0].teclas[0].valor = " " })
        XCTAssertEqual(com { $0.perfis[0].teclas[0].valor = "ctrl+zz" },
                       "A combinação da tecla \"Manter acordado\" não foi reconhecida: ctrl+zz")
        XCTAssertNotNil(com { $0.comp = "d" }) // "c" passou a valer em 12/11/2026 (composição do relógio com o mês)
        XCTAssertNotNil(com { $0.porta = 80 })
        XCTAssertNotNil(com { $0.porta = 70000 })
        XCTAssertNotNil(com { $0.codigoAcesso = "curto" })
        XCTAssertNotNil(com { $0.codigoAcesso = String(repeating: "l", count: 20) })
    }

    func testIdDeTeclaPodeRepetirEmPerfisDiferentes() {
        var c = Config.padrao(nomeMac: "M")
        c.perfis.append(Perfil(id: "ensaio", nome: "Ensaio", teclas: c.perfis[0].teclas))
        XCTAssertNil(Config.validar(c))
    }

    func testAplicarPreservaCodigoEPortaEValida() {
        let atual = Config.padrao(nomeMac: "M")
        var recebida = atual
        recebida.codigoAcesso = "zzzzzzzzzzzzzzzzzzzz"
        recebida.porta = 9999
        recebida.perfis[0].nome = "Novo"
        recebida.perfilAtivo = "sumiu"
        guard case .success(let nova) = Config.aplicar(recebida: recebida, sobre: atual) else { return XCTFail("deveria aplicar") }
        XCTAssertEqual(nova.codigoAcesso, atual.codigoAcesso)
        XCTAssertEqual(nova.porta, 4777)
        XCTAssertEqual(nova.perfis[0].nome, "Novo")
        XCTAssertEqual(nova.perfilAtivo, "trabalho")

        recebida.perfis = []
        XCTAssertEqual(Config.aplicar(recebida: recebida, sobre: atual),
                       .failure(ErroConfig(mensagem: "É preciso ter pelo menos um perfil.")))
    }

    func testPublicaNaoTemCodigoDeAcesso() throws {
        let c = Config.padrao(nomeMac: "M")
        let json = String(decoding: try JSONEncoder().encode(c.publica), as: UTF8.self)
        XCTAssertFalse(json.contains("codigoAcesso"))
        XCTAssertFalse(json.contains(c.codigoAcesso))
        XCTAssertTrue(json.contains("perfilAtivo"))
    }
}

final class ConfigArmazemTestes: XCTestCase {
    private var pasta: URL!

    override func setUpWithError() throws {
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-teste-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: pasta) }

    private var arquivo: URL { pasta.appendingPathComponent("Deck/config.json") }

    private func permissao(_ u: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func testCriaPastaEPadraoQuandoNaoExiste() throws {
        let c = try ArmazemConfig(url: arquivo, nomeMac: "M").ler()
        XCTAssertNil(Config.validar(c))
        XCTAssertTrue(FileManager.default.fileExists(atPath: arquivo.path))
        XCTAssertEqual(try permissao(arquivo), 0o600)
        // Segunda leitura devolve a mesma config, com o mesmo código.
        XCTAssertEqual(try ArmazemConfig(url: arquivo).ler(), c)
    }

    func testGravarPreservaCamposQueOAppNaoConhece() throws {
        let a = ArmazemConfig(url: arquivo, nomeMac: "M")
        var c = try a.ler()
        // Um iPhone futuro gravou campos novos na raiz, no perfil e na tecla.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: arquivo)) as! [String: Any]
        json["campoFuturo"] = ["a": 1]
        var perfis = json["perfis"] as! [[String: Any]]
        perfis[0]["corDoPerfil"] = "azul"
        var teclas = perfis[0]["teclas"] as! [[String: Any]]
        teclas[0]["haptico"] = true
        perfis[0]["teclas"] = teclas
        json["perfis"] = perfis
        try JSONSerialization.data(withJSONObject: json).write(to: arquivo)
        c.perfis[0].teclas[0].nome = "Renomeada"
        c.perfis[0].teclas[1].estado = nil
        try a.gravar(c)
        let depois = try JSONSerialization.jsonObject(with: Data(contentsOf: arquivo)) as! [String: Any]
        XCTAssertNotNil(depois["campoFuturo"])
        let p0 = (depois["perfis"] as! [[String: Any]])[0]
        XCTAssertEqual(p0["corDoPerfil"] as? String, "azul")
        let t0 = (p0["teclas"] as! [[String: Any]])[0]
        XCTAssertEqual(t0["haptico"] as? Bool, true)
        XCTAssertEqual(t0["nome"] as? String, "Renomeada")
        XCTAssertEqual(try a.ler(), c)
    }

    func testGravaELeDeVolta() throws {
        let a = ArmazemConfig(url: arquivo)
        var c = Config.padrao(nomeMac: "M")
        c.perfis[0].nome = "Palco"
        try a.gravar(c)
        try a.gravar(c)
        XCTAssertEqual(try a.ler(), c)
        XCTAssertEqual(try permissao(arquivo), 0o600)
        let sobras = try FileManager.default.contentsOfDirectory(atPath: arquivo.deletingLastPathComponent().path)
        XCTAssertEqual(sobras, ["config.json"])
    }

    func testArquivoCorrompidoNaoEhSobrescritoEGuardaCopia() throws {
        try FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lixo = Data("{ isso nao eh json".utf8)
        try lixo.write(to: arquivo)
        XCTAssertThrowsError(try ArmazemConfig(url: arquivo).ler()) { erro in
            XCTAssertTrue((erro as? ErroConfig)?.mensagem.contains("danificado") == true)
        }
        XCTAssertEqual(try Data(contentsOf: arquivo), lixo)
        let nomes = try FileManager.default.contentsOfDirectory(atPath: arquivo.deletingLastPathComponent().path)
        XCTAssertTrue(nomes.contains { $0.hasPrefix("config.json.corrompido-") })
    }

    func testConfigAntigaEhMigradaEGravadaComCodigoEstavel() throws {
        try FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"teclas":[{"id":"w","nome":"WhatsApp","tipo":"painel","valor":"whatsapp"}],"nomeMac":"M"}"#.utf8).write(to: arquivo)
        let a = ArmazemConfig(url: arquivo)
        let primeira = try a.ler()
        XCTAssertEqual(primeira.perfis[0].teclas[0].tipo, "app")
        XCTAssertEqual(try a.ler().codigoAcesso, primeira.codigoAcesso)
        XCTAssertEqual(try a.ler(), primeira)
    }
}
