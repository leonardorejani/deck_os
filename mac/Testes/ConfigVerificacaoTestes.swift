import XCTest
@testable import Nucleo

final class ConfigVerificacaoTestes: XCTestCase {
    private var pasta: URL!
    override func setUpWithError() throws {
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-verif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: pasta) }
    private var arquivo: URL { pasta.appendingPathComponent("config.json") }

    private let semNome = #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","codigoAcesso":"abcdefghjkmnpqrstuvw"}"#

    func testNomeDoMacPassadoAoArmazemValeQuandoFaltaNoArquivo() throws {
        try Data(semNome.utf8).write(to: arquivo)
        let c = try ArmazemConfig(url: arquivo, nomeMac: "MacBook do Leo").ler()
        XCTAssertEqual(c.nomeMac, "MacBook do Leo")
        let gravado = try JSONDecoder().decode(Config.self, from: Data(contentsOf: arquivo))
        XCTAssertEqual(gravado.nomeMac, "MacBook do Leo")
    }

    func testPutParcialEhRecusadoESemPerderNada() {
        let atual = Config.padrao(nomeMac: "M")
        for corpo in [#"{"comp":"b"}"#,
                      #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"b","contas":[],"blocos":{}}"#] {
            guard case .failure(let e) = Config.receber(corpo: Data(corpo.utf8), sobre: atual) else {
                return XCTFail("PUT parcial foi aceito: \(corpo)")
            }
            XCTAssertTrue(e.mensagem.contains("incompleta"))
        }
    }

    func testPutCompletoEhAceitoEMantemCodigoEPorta() throws {
        let atual = Config.padrao(nomeMac: "M")
        var nova = atual
        nova.perfis[0].nome = "Palco"
        nova.codigoAcesso = "zzzzzzzzzzzzzzzzzzzz"
        let json = try JSONEncoder().encode(nova)
        guard case .success(let c) = Config.receber(corpo: json, sobre: atual) else { return XCTFail("recusou") }
        XCTAssertEqual(c.perfis[0].nome, "Palco")
        XCTAssertEqual(c.codigoAcesso, atual.codigoAcesso)
        XCTAssertEqual(c.nomeMac, "M")
    }

    func testConfigInvalidaNaoGeraCopiaEmLaco() throws {
        try Data(#"{"perfis":[{"id":"p","nome":"","teclas":[]}],"perfilAtivo":"p","codigoAcesso":"abcdefghjkmnpqrstuvw"}"#.utf8).write(to: arquivo)
        for _ in 0..<3 {
            XCTAssertThrowsError(try ArmazemConfig(url: arquivo).ler())
            Thread.sleep(forTimeInterval: 1.1)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pasta.path), ["config.json"])
    }

    func testPermissaoVoltaPara600MesmoSemRegravar() throws {
        let a = ArmazemConfig(url: arquivo)
        _ = try a.ler()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: arquivo.path)
        _ = try a.ler()
        let perm = (try FileManager.default.attributesOfItem(atPath: arquivo.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perm, 0o600)
    }

    func testValidarOlhaContasENomeDoMac() {
        func com(_ ajuste: (inout Config) -> Void) -> String? {
            var c = Config.padrao(nomeMac: "M"); ajuste(&c); return Config.validar(c)
        }
        let ok = ContaIA(id: "a", nome: "Claude", conta: "leo", perfil: "leo-2", mostrar: nil)
        XCTAssertNil(com { $0.contas = [ok] })
        XCTAssertNotNil(com { $0.contas = [ok, ok] })
        XCTAssertNotNil(com { var x = ok; x.id = "b"; x.nome = ""; $0.contas = [ok, x] })
        XCTAssertNotNil(com { var x = ok; x.conta = " "; $0.contas = [x] })
        for ruim in ["../../etc", "..", ".oculto", "a/b", ""] {
            XCTAssertNotNil(com { var x = ok; x.perfil = ruim; $0.contas = [x] }, ruim)
        }
        XCTAssertNotNil(com { $0.nomeMac = "" })
        XCTAssertNotNil(com { $0.nomeMac = "  " })
        XCTAssertNotNil(com { $0.perfis[0].id = "  " })
    }
}
