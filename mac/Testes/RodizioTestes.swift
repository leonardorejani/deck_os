import XCTest
@testable import Nucleo

/// Relógio que os testes avançam à mão.
final class Relogio: @unchecked Sendable {
    private let trava = NSLock()
    private var t: Date
    init(_ inicio: Date = Date()) { t = inicio }
    var agora: Date { trava.lock(); defer { trava.unlock() }; return t }
    func avancar(_ s: TimeInterval) { trava.lock(); t = t.addingTimeInterval(s); trava.unlock() }
}

final class RodizioTestes: XCTestCase {
    private let hora: TimeInterval = 3600

    private func montar() throws -> (Cenario, Relogio) {
        let relogio = Relogio()
        // O código de teste nasce agora, no mesmo instante do relógio falso.
        var c = configDeTeste()
        c.codigoCriadoEm = Int(relogio.agora.timeIntervalSince1970)
        let cenario = try Cenario(agora: { relogio.agora }, rodizio: Rodizio(agora: { relogio.agora }))
        _ = cenario.armazem.aplicar(c)
        return (cenario, relogio)
    }

    func testAntesDe24hNaoTroca() throws {
        let (c, rel) = try montar()
        rel.avancar(23 * hora + 59 * 60)
        let r = c.pedir("GET", "/api/estado")
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(r.extras["X-Deck-Codigo-Novo"])
        XCTAssertEqual(c.armazem.ler().codigoAcesso, Cenario.codigo)
        XCTAssertNil(c.armazem.ler().codigoAnterior)
    }

    func testTrocaAs24hEOAntigoValeNaFolgaComOCabecalhoDoNovo() throws {
        let (c, rel) = try montar()
        rel.avancar(24 * hora)
        let r = c.pedir("GET", "/api/estado")
        XCTAssertEqual(r.status, 200, "o iPhone que ainda tem o antigo não pode cair")
        let novo = c.armazem.ler().codigoAcesso
        XCTAssertNotEqual(novo, Cenario.codigo)
        XCTAssertEqual(r.extras["X-Deck-Codigo-Novo"], novo)
        XCTAssertEqual(c.armazem.ler().codigoAnterior, Cenario.codigo)
        // O novo funciona e não repete o cabeçalho, o antigo continua valendo e continua recebendo o novo.
        let comNovo = c.pedir("GET", "/api/estado", codigo: novo)
        XCTAssertEqual(comNovo.status, 200)
        XCTAssertNil(comNovo.extras["X-Deck-Codigo-Novo"])
        rel.avancar(9 * 60)
        let ainda = c.pedir("POST", "/api/botao/acordado")
        XCTAssertEqual(ainda.status, 200)
        XCTAssertEqual(ainda.extras["X-Deck-Codigo-Novo"], novo)
        // Também em resposta de erro autenticada.
        XCTAssertEqual(c.pedir("GET", "/api/nao-existe").extras["X-Deck-Codigo-Novo"], novo)
    }

    func testAntigoRecusadoDepoisDaFolga() throws {
        let (c, rel) = try montar()
        rel.avancar(24 * hora)
        _ = c.pedir("GET", "/api/estado")
        let novo = c.armazem.ler().codigoAcesso
        rel.avancar(10 * 60)
        let r = c.pedir("GET", "/api/estado")
        XCTAssertEqual(r.status, 401)
        XCTAssertNil(r.extras["X-Deck-Codigo-Novo"], "401 nunca entrega código")
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: novo).status, 200)
    }

    func testSegundaTrocaNaoReviveOCodigoDeDuasTrocasAtras() throws {
        let (c, rel) = try montar()
        rel.avancar(24 * hora)
        _ = c.pedir("GET", "/api/estado")
        let segundo = c.armazem.ler().codigoAcesso
        rel.avancar(24 * hora)
        _ = c.pedir("GET", "/api/estado", codigo: segundo)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: Cenario.codigo).status, 401)
        XCTAssertEqual(c.armazem.ler().codigoAnterior, segundo)
    }

    func testRevogarDerrubaOsDoisEGeraUmNovo() throws {
        let relogio = Relogio()
        let rodizio = Rodizio(agora: { relogio.agora })
        let c = try Cenario(agora: { relogio.agora }, rodizio: rodizio)
        relogio.avancar(24 * hora)
        _ = c.pedir("GET", "/api/estado")
        let atual = c.armazem.ler().codigoAcesso
        XCTAssertNil(rodizio.revogar(em: c.armazem))
        let depois = c.armazem.ler()
        XCTAssertNotEqual(depois.codigoAcesso, atual)
        XCTAssertNil(depois.codigoAnterior)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: Cenario.codigo).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: atual).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: depois.codigoAcesso).status, 200)
    }

    func testGerarSeVencidoEVencimento() throws {
        let relogio = Relogio()
        let rodizio = Rodizio(agora: { relogio.agora })
        let armazem = ArmazemFalso(configDeTeste())
        var c = armazem.ler(); c.codigoCriadoEm = Int(relogio.agora.timeIntervalSince1970); _ = armazem.aplicar(c)
        XCTAssertEqual(rodizio.vencimento(em: armazem).timeIntervalSince(relogio.agora), 24 * hora, accuracy: 1)
        XCTAssertFalse(rodizio.gerarSeVencido(em: armazem))
        relogio.avancar(24 * hora)
        XCTAssertTrue(rodizio.gerarSeVencido(em: armazem))
        XCTAssertFalse(rodizio.gerarSeVencido(em: armazem), "já trocou, não troca de novo")
        XCTAssertEqual(armazem.ler().codigoAnterior, Cenario.codigo)
        XCTAssertEqual(rodizio.vencimento(em: armazem).timeIntervalSince(relogio.agora), 24 * hora, accuracy: 1)
    }

    func testConfigAntigaMigraEFicaEstavel() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-rodizio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let arquivo = pasta.appendingPathComponent("config.json")
        try Data(#"{"versao":1,"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"a","contas":[],"blocos":{},"nomeMac":"M","porta":4777,"codigoAcesso":"abcdefghjkmnpqrstuvw"}"#.utf8).write(to: arquivo)
        let antes = Int(Date().timeIntervalSince1970)
        let a = ArmazemConfig(url: arquivo, nomeMac: "M")
        let lida = try a.ler()
        XCTAssertEqual(lida.codigoAcesso, "abcdefghjkmnpqrstuvw")
        XCTAssertGreaterThanOrEqual(lida.codigoCriadoEm, antes)
        XCTAssertNil(lida.codigoAnterior)
        let json = try String(contentsOf: arquivo, encoding: .utf8)
        XCTAssertTrue(json.contains("codigoCriadoEm"), "a data tem que ir para o disco, senão recomeça a cada leitura")
        XCTAssertEqual(try a.ler().codigoCriadoEm, lida.codigoCriadoEm)
        let perm = try FileManager.default.attributesOfItem(atPath: arquivo.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perm?.intValue, 0o600)
    }

    func testCodigoAnteriorNuncaSaiNaConfigPublicaENaoMudaPeloPut() throws {
        let (c, rel) = try montar()
        rel.avancar(24 * hora)
        _ = c.pedir("GET", "/api/estado")
        let novo = c.armazem.ler().codigoAcesso
        let g = c.pedir("GET", "/api/config", codigo: novo)
        XCTAssertFalse(g.texto.contains(Cenario.codigo))
        XCTAssertFalse(g.texto.contains("codigoAnterior"))
        var corpo = try XCTUnwrap(g.json as? [String: Any])
        corpo["nomeMac"] = "Novo nome"
        corpo["codigoAnterior"] = "zzzzzzzzzzzzzzzzzzzz"
        let envio = String(decoding: try JSONSerialization.data(withJSONObject: corpo), as: UTF8.self)
        XCTAssertEqual(c.pedir("PUT", "/api/config", corpo: envio, codigo: novo).status, 200)
        let depois = c.armazem.ler()
        XCTAssertEqual(depois.codigoAnterior, Cenario.codigo)
        XCTAssertEqual(depois.codigoAcesso, novo)
    }

    func testPutDeUmIPhoneNaFolgaNaoDesfazATroca() throws {
        let (c, rel) = try montar()
        rel.avancar(24 * hora)
        let g = c.pedir("GET", "/api/config")
        let novo = c.armazem.ler().codigoAcesso
        let envio = String(decoding: g.corpo, as: UTF8.self)
        let r = c.pedir("PUT", "/api/config", corpo: envio)
        XCTAssertEqual(r.extras["X-Deck-Codigo-Novo"], novo)
        XCTAssertEqual(c.armazem.ler().codigoAcesso, novo)
    }
}
