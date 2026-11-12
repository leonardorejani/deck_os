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
                                 pergunta: "Posso abrir o PR?", desde: "2026-11-06T20:14:02.573Z",
                                 pedido: "outro texto"))
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

    // Contexto: a última linha do timeline.jsonl (estado blocked) é o que a sessão disse antes de parar.
    private func gravarJob(_ raiz: URL, _ id: String, estado: String, linhas: [String]) throws {
        let p = raiz.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        try estado.write(to: p.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        try (linhas.joined(separator: "\n") + "\n").write(to: p.appendingPathComponent("timeline.jsonl"), atomically: true, encoding: .utf8)
    }

    private func linha(_ estado: String, _ texto: String) -> String {
        let t = try! JSONSerialization.data(withJSONObject: ["at": "2026-11-12T10:00:00.000Z", "state": estado, "detail": "d", "text": texto])
        return String(data: t, encoding: .utf8)!
    }

    func testLeOContextoSugestaoEPedidoDaSessao() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravarJob(raiz, "a", estado: #"{"state":"blocked","name":"n","detail":"Resumo","needs":"Pedido inteiro da sessão","suggestedReply":"sim, pode","updatedAt":"2026-11-12T10:00:00.000Z"}"#,
                      linhas: [linha("working", "trabalho antigo"), linha("blocked", "needs input: preciso de uma decisão.\n\nOpção A ou B?")])
        let s = try XCTUnwrap(FonteSessoes.ler(raiz: raiz).valor.first)
        XCTAssertEqual(s.pergunta, "Resumo")
        XCTAssertEqual(s.pedido, "Pedido inteiro da sessão")
        XCTAssertEqual(s.sugestao, "sim, pode")
        XCTAssertEqual(s.contexto, "preciso de uma decisão.\n\nOpção A ou B?")
    }

    func testContextoSoVemSeAUltimaLinhaForDeEspera() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravarJob(raiz, "a", estado: #"{"state":"blocked","name":"n","detail":"R","updatedAt":"2026-11-12T10:00:00.000Z"}"#,
                      linhas: [linha("blocked", "texto velho"), linha("working", "voltou a trabalhar")])
        XCTAssertNil(try XCTUnwrap(FonteSessoes.ler(raiz: raiz).valor.first).contexto)
    }

    func testContextoLongoVemCortadoELinhaGrandeNoFimDoArquivoEhLida() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let enorme = String(repeating: "palavra ", count: 20_000) // 160 KB numa linha só
        try gravarJob(raiz, "a", estado: #"{"state":"blocked","name":"n","detail":"R","updatedAt":"2026-11-12T10:00:00.000Z"}"#,
                      linhas: [linha("working", String(repeating: "x", count: 50_000)), linha("blocked", enorme)])
        let c = try XCTUnwrap(try XCTUnwrap(FonteSessoes.ler(raiz: raiz).valor.first).contexto)
        XCTAssertLessThanOrEqual(c.count, FonteSessoes.limiteContexto + 3)
        XCTAssertTrue(c.hasSuffix("..."))
    }

    func testEstadoDoPainelNaoLevaOContexto() {
        let s = Sessao(id: "a", nome: "n", projeto: "p", pergunta: "?", desde: "d", pedido: "p", contexto: "longo", sugestao: "s")
        let leve = FonteSessoes.semContexto([s])
        XCTAssertNil(leve[0].contexto)
        XCTAssertEqual(leve[0].pedido, "p")
    }

    /// Segredo de mentira montado na hora: o repo é público e o scanner do GitHub barra token de exemplo escrito inteiro.
    private func fake(_ a: String, _ b: String) -> String { a + b }

    func testMascaraSegredosNoQueVaiParaOIphone() throws {
        let segredos = [
            fake("gh" + "p_", "abcdefghijklmnopqrstuvwxyz0123456789"), fake("s" + "k-ant-", "api03-abcdefghijklmnopqrstuvwx"),
            fake("github" + "_pat_", "11ABCDEFG0abcdefghij_klmnop"), fake("xo" + "xb-", "123456789012-abcdefghij"), fake("AK" + "IA", "ABCDEFGHIJKLMNOP"),
            fake("ey" + "J", "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop"),
            "Zk3Qm9Xa7Lp2Vn8Rt5Yb1Hc4Wd6Jg0SeKfUiOyTx",
        ]
        for seg in segredos {
            let m = Mascara.segredos("use \(seg) agora", limite: 500)
            XCTAssertFalse(m.contains(seg), "vazou: \(seg)")
            XCTAssertTrue(m.contains("[oculto]"))
        }
        XCTAssertEqual(Mascara.segredos("export API_TOKEN=abc123def456 e segue", limite: 500), "export API_TOKEN=[oculto] e segue")
        XCTAssertEqual(Mascara.segredos("Authorization: Bearer abcdefghijklmnop1234567", limite: 500), "Authorization: Bearer [oculto]")
        XCTAssertEqual(Mascara.segredos("git clone https://leo:minhasenha@github.com/x/y", limite: 500), "git clone https://leo:[oculto]@github.com/x/y")
        // o que não é segredo passa intacto: commit, caminho, branch, texto comum
        let normal = "commit 66b5d06a1b2c3d4e5f60718293a4b5c6d7e8f901 em feat/sessoes-contexto, arquivo mac/Nucleo/Fontes/Sessoes.swift"
        XCTAssertEqual(Mascara.segredos(normal, limite: 500), normal)
    }

    func testSegredoNoNeedsENoContextoNaoChegaAoPainel() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let gh = fake("gh" + "p_", "abcdefghijklmnopqrstuvwxyz0123456789"), sk = fake("s" + "k-", "abcdefghijklmnopqrstuv")
        try gravarJob(raiz, "a", estado: #"{"state":"blocked","name":"n","detail":"R","needs":"cole o token \#(gh)","updatedAt":"2026-11-12T10:00:00.000Z"}"#,
                      linhas: [linha("blocked", "senha: hunter2hunter2 e depois \(sk)")])
        let s = try XCTUnwrap(FonteSessoes.ler(raiz: raiz).valor.first)
        let tudo = [s.pergunta, s.pedido, s.contexto].compactMap { $0 }.joined()
        XCTAssertFalse(tudo.contains(gh) || tudo.contains("hunter2") || tudo.contains(sk))
        XCTAssertTrue(tudo.contains("[oculto]"))
    }
}
