import XCTest
@testable import Nucleo

final class FontesSessoesTestes: XCTestCase {
    // Formato real de ~/.claude/jobs/<id>/state.json (campos que importam, conteúdo de exemplo).
    let bloqueada = """
    {"state":"blocked","name":"podio ranking","detail":"Posso abrir o PR?","needs":"outro texto",
     "cwd":"/Users/x/Projetos/app_web/.claude/worktrees/a","originCwd":"/Users/x/Projetos/app_web",
     "createdAt":"2026-11-05T13:15:58.856Z","updatedAt":"2026-11-06T20:14:02.573Z"}
    """

    func testMapeiaSessaoBloqueada() throws {
        let s = try XCTUnwrap(FonteSessoes.parse(Data(bloqueada.utf8), pasta: "04e4e26b"))
        XCTAssertEqual(s, Sessao(id: "04e4e26b", nome: "podio ranking", projeto: "app_web",
                                 pergunta: "Posso abrir o PR?", desde: "2026-11-06T20:14:02.573Z"))
    }

    func testSemDetailUsaNeedsESemOriginCwdUsaCwd() throws {
        let json = #"{"state":"blocked","name":"n","needs":"Quer que eu siga?","cwd":"/a/b/api_pedidos","createdAt":"2026-11-01T10:00:00.000Z"}"#
        let s = try XCTUnwrap(FonteSessoes.parse(Data(json.utf8), pasta: "x"))
        XCTAssertEqual(s.pergunta, "Quer que eu siga?")
        XCTAssertEqual(s.projeto, "api_pedidos")
        XCTAssertEqual(s.desde, "2026-11-01T10:00:00.000Z")
    }

    func testIgnoraQuemNaoEstaBloqueadoOuEstaQuebrado() {
        XCTAssertNil(FonteSessoes.parse(Data(#"{"state":"running","name":"n"}"#.utf8), pasta: "x"))
        XCTAssertNil(FonteSessoes.parse(Data("não é json".utf8), pasta: "x"))
    }

    func testLeAPastaEOrdenaDaMaisRecenteParaAMaisAntiga() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        func gravar(_ id: String, _ json: String) throws {
            let p = raiz.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
            try json.write(to: p.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        }
        try gravar("velha", #"{"state":"blocked","name":"velha","detail":"?","updatedAt":"2026-10-01T10:00:00.000Z"}"#)
        try gravar("nova", #"{"state":"blocked","name":"nova","detail":"?","updatedAt":"2026-11-09T10:00:00.000Z"}"#)
        try gravar("rodando", #"{"state":"running","name":"r"}"#)
        try gravar("estragada", "{")
        let r = FonteSessoes.ler(raiz: raiz)
        XCTAssertEqual(r.valor.map(\.id), ["nova", "velha"])
        XCTAssertNil(r.aviso)
    }

    func testPastaInexistenteDevolveVazioSemAviso() {
        let r = FonteSessoes.ler(raiz: URL(fileURLWithPath: "/nao/existe/jobs"))
        XCTAssertEqual(r.valor, [])
        XCTAssertNil(r.aviso)
    }
}
