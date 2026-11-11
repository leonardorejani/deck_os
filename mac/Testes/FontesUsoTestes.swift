import XCTest
@testable import Nucleo

final class FontesUsoTestes: XCTestCase {
    // Evento real de ~/.codex/sessions (formato conferido neste Mac em 10/11/2026).
    func linhaCodex(janela: String = #""primary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1794396597},"secondary":null"#) -> String {
        #"{"timestamp":"2026-11-10T16:25:08.382Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex",\#(janela),"plan_type":"pro"}}}"#
    }

    func testCodexLeAJanelaSemanal() {
        let j = UsoCodex.parse("lixo\n" + linhaCodex() + "\n")
        XCTAssertEqual(j, UsoCodex.Janela(percentual: 10, renova: Date(timeIntervalSince1970: 1794396597)))
    }

    func testCodexAchaASemanalNoSecondaryEIgnoraAJanelaDe5Horas() {
        let j = UsoCodex.parse(linhaCodex(janela: #""primary":{"used_percent":80,"window_minutes":300,"resets_at":1},"secondary":{"used_percent":33.4,"window_minutes":10080,"resets_at":1794000000}"#))
        XCTAssertEqual(j, UsoCodex.Janela(percentual: 33, renova: Date(timeIntervalSince1970: 1794000000)))
    }

    func testCodexPegaOEventoMaisNovoDoArquivo() {
        let velho = linhaCodex(janela: #""primary":{"used_percent":5,"window_minutes":10080,"resets_at":1794000000},"secondary":null"#)
        XCTAssertEqual(UsoCodex.parse(velho + "\n" + linhaCodex())?.percentual, 10)
    }

    func testCodexSemRateLimitsDevolveNil() {
        XCTAssertNil(UsoCodex.parse(#"{"payload":{"type":"message"}}"#))
        XCTAssertNil(UsoCodex.parse(""))
    }

    func testCodexLerVarreOsArquivosMaisRecentes() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let dia = raiz.appendingPathComponent("2026/11/10")
        try FileManager.default.createDirectory(at: dia, withIntermediateDirectories: true)
        // O arquivo mais novo ainda não tem medição, o anterior tem: tem que cair no anterior.
        try (linhaCodex() + "\n").write(to: dia.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        try #"{"payload":{"type":"message"}}"#.write(to: dia.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: dia.appendingPathComponent("a.jsonl").path)
        let conta = ContaIA(id: "codex", nome: "Codex", conta: "pro")
        let agora = Date(timeIntervalSince1970: 1794396597 - 86_400)
        let r = UsoCodex.ler(raiz: raiz, conta: conta, agora: agora)
        XCTAssertEqual(r.valor, UsoConta(id: "codex", nome: "Codex", conta: "pro", semana: 10, renova: "2026-11-11T11:29:57Z"))
        XCTAssertNil(r.aviso)
    }

    func testCodexSemArquivosDaAvisoSemInventarNumero() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let r = UsoCodex.ler(raiz: raiz, conta: ContaIA(id: "codex", nome: "Codex", conta: "pro"), agora: Date())
        XCTAssertNil(r.valor.semana)
        XCTAssertEqual(r.aviso?.fonte, "uso")
    }

    func testCodexJanelaQueJaRenovouNaoVale() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try (linhaCodex() + "\n").write(to: raiz.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let depois = Date(timeIntervalSince1970: 1794396597 + 60)
        let r = UsoCodex.ler(raiz: raiz, conta: ContaIA(id: "codex", nome: "Codex", conta: "pro"), agora: depois)
        XCTAssertNil(r.valor.semana)
        XCTAssertNil(r.valor.renova)
    }

    // Formato gravado pelo claude-account-autoswitch (measure.json).
    let medicao = #"{"measured_at":"2026-11-10T18:00:00Z","profiles":{"leo":{"status":"allowed","util_5h":12,"reset_5h":1,"util_7d":61,"reset_7d":1794500000},"equipe":{"util_7d":null,"reset_7d":null}},"history":{}}"#

    func testClaudeLeAMedicaoPorPerfil() throws {
        let m = try XCTUnwrap(UsoClaude.parse(Data(medicao.utf8)))
        XCTAssertEqual(m.perfis["leo"], UsoClaude.Perfil(semana: 61, renova: Date(timeIntervalSince1970: 1794500000)))
        XCTAssertEqual(m.perfis["equipe"], UsoClaude.Perfil(semana: nil, renova: nil))
    }

    func testClaudeComMedicaoRecente() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let arq = raiz.appendingPathComponent("measure.json")
        try medicao.write(to: arq, atomically: true, encoding: .utf8)
        let contas = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo"),
                      ContaIA(id: "claude-equipe", nome: "Claude", conta: "equipe", perfil: "equipe"),
                      ContaIA(id: "claude-x", nome: "Claude", conta: "x", perfil: "inexistente")]
        let agora = Datas.ler("2026-11-10T18:05:00Z")!
        let r = UsoClaude.ler(contas: contas, arquivo: arq, agora: agora)
        XCTAssertEqual(r.valor.map(\.semana), [61, nil, nil])
        XCTAssertEqual(r.valor[0].renova, Datas.iso(Date(timeIntervalSince1970: 1794500000), fuso: utc))
        XCTAssertNil(r.aviso)
    }

    func testClaudeSemArquivoDevolveNilComAviso() {
        let contas = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo")]
        let r = UsoClaude.ler(contas: contas, arquivo: URL(fileURLWithPath: "/nao/existe/measure.json"), agora: Date())
        XCTAssertEqual(r.valor.map(\.semana), [nil])
        XCTAssertEqual(r.aviso?.fonte, "uso")
    }

    func testClaudeMedicaoVelhaNaoVale() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let arq = raiz.appendingPathComponent("measure.json")
        try medicao.write(to: arq, atomically: true, encoding: .utf8)
        let contas = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo")]
        let r = UsoClaude.ler(contas: contas, arquivo: arq, agora: Datas.ler("2026-11-10T20:00:00Z")!)
        XCTAssertEqual(r.valor.map(\.semana), [nil])
        XCTAssertNotNil(r.aviso)
    }

    func testFonteUsoRespeitaMostrarEMantemAOrdem() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let arq = raiz.appendingPathComponent("measure.json")
        try medicao.write(to: arq, atomically: true, encoding: .utf8)
        let contas = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo"),
                      ContaIA(id: "claude-oculta", nome: "Claude", conta: "equipe", perfil: "equipe", mostrar: false),
                      ContaIA(id: "outra", nome: "Gemini", conta: "g")]
        let r = FonteUso.ler(contas: contas, claude: arq, codex: raiz.appendingPathComponent("sem-codex"),
                             agora: Datas.ler("2026-11-10T18:05:00Z")!)
        XCTAssertEqual(r.valor.map(\.id), ["claude-leo", "outra"])
        XCTAssertEqual(r.valor.map(\.semana), [61, nil])
    }
}
