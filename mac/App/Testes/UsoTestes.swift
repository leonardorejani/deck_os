import XCTest
@testable import Deck

final class CofreFalso: CofreDeToken, @unchecked Sendable {
    private let trava = NSLock()
    private var itens: [String: String] = [:]
    var falhaAoGuardar = false
    func guardar(_ token: String, conta: String) throws {
        if falhaAoGuardar { throw ErroChaveiro(codigo: -1) }
        trava.lock(); itens[conta] = token; trava.unlock()
    }
    func ler(conta: String) -> String? { trava.lock(); defer { trava.unlock() }; return itens[conta] }
    func apagar(conta: String) { trava.lock(); itens[conta] = nil; trava.unlock() }
}

final class Contador: @unchecked Sendable { var n = 0 }
final class Relogio: @unchecked Sendable { var agora = Date(timeIntervalSince1970: 1_800_000_000) }
struct ContadorLeitor: LeitorDeUsoPorToken {
    var conta: Contador
    func ler(token: String) async -> ResultadoDoToken { conta.n += 1; return .ok(UsoDoToken(semana: 5, renova: nil)) }
}

struct LeitorFalso: LeitorDeUsoPorToken {
    var resultado: ResultadoDoToken
    func ler(token: String) async -> ResultadoDoToken { resultado }
}

private let claudeLeo = ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo", mostrar: nil)
private let claudeEquipe = ContaIA(id: "claude-equipe", nome: "Claude", conta: "equipe", perfil: "equipe", mostrar: nil)
private let codexPro = ContaIA(id: "codex", nome: "Codex", conta: "pro", perfil: nil, mostrar: nil)

private var calendario: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}

private func data(_ dia: Int, _ hora: Int, _ min: Int = 0) -> Date {
    calendario.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: min))!
}

private func tokenValido() -> String { TokenClaude.prefixo + String(repeating: "a", count: 90) }

final class UsoLogicaTestes: XCTestCase {
    func testNivelAmarelaEm70EVermelhaEm90() {
        XCTAssertEqual(UsoLogica.nivel(69), .normal)
        XCTAssertEqual(UsoLogica.nivel(70), .alto)
        XCTAssertEqual(UsoLogica.nivel(89), .alto)
        XCTAssertEqual(UsoLogica.nivel(90), .cheio)
    }

    func testRenovaEmHojeAmanhaEDias() {
        let agora = data(10, 12)
        XCTAssertEqual(UsoLogica.renovaEm(data(10, 14), agora: agora, calendario: calendario), "hoje às 14h")
        XCTAssertEqual(UsoLogica.renovaEm(data(10, 14, 30), agora: agora, calendario: calendario), "hoje às 14h30")
        XCTAssertEqual(UsoLogica.renovaEm(data(11, 22), agora: agora, calendario: calendario), "amanhã")
        XCTAssertEqual(UsoLogica.renovaEm(data(13, 14), agora: agora, calendario: calendario), "em 3 dias")
        XCTAssertEqual(UsoLogica.renovaEm(data(15, 9), agora: agora, calendario: calendario), "em 5 dias")
    }

    func testTextoRenovaTemODiaExato() throws {
        let iso = Datas.iso(data(13, 14), fuso: calendario.timeZone)
        let r = try XCTUnwrap(UsoLogica.textoRenova(iso, agora: data(10, 12), calendario: calendario))
        XCTAssertEqual(r.texto, "Renova em 3 dias")
        XCTAssertTrue(r.exata.hasSuffix("às 14h"), r.exata)
        XCTAssertNil(UsoLogica.textoRenova(nil, agora: data(10, 12)))
    }

    func testMaisPertoDoLimiteIgnoraEscondidaESemMedicao() throws {
        let a = ContaIA(id: "a", nome: "Claude", conta: "leo", perfil: nil, mostrar: nil)
        let b = ContaIA(id: "b", nome: "Claude", conta: "equipe", perfil: nil, mostrar: nil)
        let c = ContaIA(id: "c", nome: "Codex", conta: "pro", perfil: nil, mostrar: false)
        let d = ContaIA(id: "d", nome: "Codex", conta: "sem", perfil: nil, mostrar: nil)
        let uso = ["a": UsoConta(id: "a", nome: "Claude", conta: "leo", semana: 61, renova: nil),
                   "b": UsoConta(id: "b", nome: "Claude", conta: "equipe", semana: 77, renova: nil),
                   "c": UsoConta(id: "c", nome: "Codex", conta: "pro", semana: 99, renova: nil),
                   "d": UsoConta(id: "d", nome: "Codex", conta: "sem", semana: nil, renova: nil)]
        let perto = try XCTUnwrap(UsoLogica.maisPerto(contas: [a, b, c, d], uso: uso))
        XCTAssertEqual(perto.conta.id, "b")
        XCTAssertEqual(perto.semana, 77)
        XCTAssertNil(UsoLogica.maisPerto(contas: [d], uso: uso))
    }

    func testSubtitulo() {
        XCTAssertEqual(UsoLogica.subtitulo(ContaIA(id: "a", nome: "Claude", conta: "x", perfil: "leo", mostrar: nil)), "Claude Code, conta leo")
        XCTAssertEqual(UsoLogica.subtitulo(ContaIA(id: "c", nome: "Codex", conta: "pro", perfil: nil, mostrar: nil)), "Codex, conta pro")
    }
}

final class TokenClaudeTestes: XCTestCase {
    func testLimparTiraEspacoEQuebraDeLinha() {
        XCTAssertEqual(TokenClaude.limpar("sk-ant-oat01-abc\n def \r\n ghi"), "sk-ant-oat01-abcdefghi")
    }

    func testErrosDeFormatoComOsTextosDoPrototipo() {
        XCTAssertEqual(TokenClaude.erroDeFormato("abc"), "Isso não é um token do Claude Code. Ele começa com sk-ant-oat01-")
        XCTAssertEqual(TokenClaude.erroDeFormato("sk-ant-oat01-curto"), "O token parece cortado. Copie de novo, ele é bem longo.")
        XCTAssertNil(TokenClaude.erroDeFormato(tokenValido()))
    }

    /// O token de setup-token toma 403 em /api/oauth/usage (falta o escopo user:profile). O uso vem nos
    /// cabeçalhos de /v1/messages, como fração de 0 a 1 e reset em epoch.
    func testInterpretaOUsoDosCabecalhosDoClaude() throws {
        let cab = ["anthropic-ratelimit-unified-7d-utilization": "0.614", "anthropic-ratelimit-unified-7d-reset": "1794474000"]
        guard case .ok(let u) = ClaudeUsoPorToken.interpretar(status: 200, cabecalhos: cab) else { return XCTFail("deveria ler o uso") }
        XCTAssertEqual(u.semana, 61)
        XCTAssertEqual(u.renova, Date(timeIntervalSince1970: 1794474000))
        guard case .ok(let cheio) = ClaudeUsoPorToken.interpretar(status: 429, cabecalhos: ["anthropic-ratelimit-unified-7d-utilization": "1.4"]) else { return XCTFail("429 com cabeçalho também mede") }
        XCTAssertEqual(cheio.semana, 100)
        XCTAssertNil(cheio.renova)
    }

    func testSemCabecalhoDecideOErroPeloStatus() {
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 401, cabecalhos: [:]), .recusado)
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 403, cabecalhos: [:]), .recusado)
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 429, cabecalhos: [:]), .inesperado)
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 503, cabecalhos: [:]), .inesperado)
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 200, cabecalhos: [:]), .inesperado)
        XCTAssertEqual(ClaudeUsoPorToken.interpretar(status: 400, cabecalhos: [:]), .inesperado)
    }

    func testCacheNaoPedeDeNovoDentroDaValidadeENaoGuardaFalha() async {
        let conta = Contador()
        let relogio = Relogio()
        let c = LeitorComCache(ContadorLeitor(conta: conta), validade: 300, agora: { relogio.agora })
        _ = await c.ler(token: "a"); _ = await c.ler(token: "a")
        XCTAssertEqual(conta.n, 1)
        relogio.agora = relogio.agora.addingTimeInterval(301)
        _ = await c.ler(token: "a")
        XCTAssertEqual(conta.n, 2)
        _ = await c.ler(token: "b")
        XCTAssertEqual(conta.n, 3)
    }

    /// A conta "leo" da troca de contas aparecia "Sem medição" sem o autoswitch: agora o Deck mede pelo token do perfil.
    func testContaDePerfilSemMedicaoUsaOTokenDoPerfil() async {
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("deck-vazio-\(UUID().uuidString)")
        let uso = await PainelUso.lerUso(contas: [claudeLeo], casa: casa, cofre: CofreFalso(),
                                         leitor: LeitorFalso(resultado: .ok(UsoDoToken(semana: 61, renova: nil))), agora: Date(),
                                         tokenDoPerfil: { perfil, _ in perfil == "leo" ? "t" : nil })
        XCTAssertEqual(uso["claude-leo"]?.semana, 61)
        let sem = await PainelUso.lerUso(contas: [claudeLeo], casa: casa, cofre: CofreFalso(),
                                         leitor: LeitorFalso(resultado: .ok(UsoDoToken(semana: 61, renova: nil))), agora: Date(),
                                         tokenDoPerfil: { _, _ in nil })
        XCTAssertNil(sem["claude-leo"]?.semana)
    }

    /// Conta de token (iacall) sem número ficava "Sem medição" sem dizer por quê. Agora cada causa tem o seu texto.
    func testContaSemNumeroDizPorQue() async {
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("deck-vazio-\(UUID().uuidString)")
        let iacall = ContaIA(id: "claude-token-1", nome: "Claude", conta: "iacall", perfil: nil, mostrar: nil)
        let semToken = await PainelUso.lerUsoComMotivos(contas: [iacall], casa: casa, cofre: CofreFalso(), leitor: LeitorFalso(resultado: .recusado), agora: Date())
        XCTAssertEqual(semToken.motivos["claude-token-1"], PainelUso.motivoSemToken)
        let cofre = CofreFalso(); try? cofre.guardar("t", conta: "claude-token-1")
        let recusado = await PainelUso.lerUsoComMotivos(contas: [iacall], casa: casa, cofre: cofre, leitor: LeitorFalso(resultado: .recusado), agora: Date())
        XCTAssertEqual(recusado.motivos["claude-token-1"], PainelUso.motivo(.recusado))
        let ok = await PainelUso.lerUsoComMotivos(contas: [iacall], casa: casa, cofre: cofre, leitor: LeitorFalso(resultado: .ok(UsoDoToken(semana: 3, renova: nil))), agora: Date())
        XCTAssertNil(ok.motivos["claude-token-1"])
        XCTAssertEqual(ok.usos["claude-token-1"]?.semana, 3)
    }

    func testServicoDoTokenSegueOTipoDoPerfil() {
        XCTAssertEqual(TokenDoPerfil.servico(perfil: ["type": "oauth_token", "keychainService": "A"]), "A")
        XCTAssertEqual(TokenDoPerfil.servico(perfil: ["type": "native_archive", "keychainService": "X-archive", "measureKeychainService": "M"]), "M")
        XCTAssertNil(TokenDoPerfil.servico(perfil: ["type": "native_archive", "keychainService": "X-archive"]))
        XCTAssertNil(TokenDoPerfil.servico(perfil: ["type": "native_archive", "measureKeychainService": ""]))
        XCTAssertNil(TokenDoPerfil.servico(perfil: ["type": "outro", "keychainService": "A"]))
    }

    func testTokenDoPerfilSoLeOAuthTokenEPerfilValido() throws {
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("deck-casa-\(UUID().uuidString)")
        let pasta = casa.appendingPathComponent(".config/claude-account/profiles")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try Data(#"{"type":"native_archive","keychainService":"deck-teste-nao-existe"}"#.utf8).write(to: pasta.appendingPathComponent("nativa.json"))
        try Data(#"{"type":"oauth_token","keychainService":"deck-teste-nao-existe-\#(UUID().uuidString)"}"#.utf8).write(to: pasta.appendingPathComponent("tok.json"))
        XCTAssertNil(TokenDoPerfil.ler(perfil: "nativa", casa: casa))
        XCTAssertNil(TokenDoPerfil.ler(perfil: "tok", casa: casa))
        XCTAssertNil(TokenDoPerfil.ler(perfil: "../x", casa: casa))
        XCTAssertNil(TokenDoPerfil.ler(perfil: "ausente", casa: casa))
    }
}

final class ContasAchadasTestes: XCTestCase {
    private func casa(perfis: [String], codex: Bool) throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("deck-casa-\(UUID().uuidString)")
        for p in perfis { try FileManager.default.createDirectory(at: raiz.appendingPathComponent(".config/claude-account/logins/\(p)"), withIntermediateDirectories: true) }
        if codex {
            try FileManager.default.createDirectory(at: raiz.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: raiz.appendingPathComponent(".codex/auth.json").path, contents: Data("{}".utf8))
        }
        return raiz
    }

    func testAchaPerfisDoClaudeECodexEIgnoraOQueJaEstaNoPainel() throws {
        let c = try casa(perfis: ["leo", "equipe", ".oculto", "../x"], codex: true)
        defer { try? FileManager.default.removeItem(at: c) }
        let todas = ContasAchadas.procurar(casa: c, jaNoPainel: [])
        XCTAssertEqual(todas.map(\.id), ["claude-equipe", "claude-leo", "codex"])
        let jaTem = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo", mostrar: nil),
                     ContaIA(id: "codex", nome: "Codex", conta: "pro", perfil: nil, mostrar: nil)]
        XCTAssertEqual(ContasAchadas.procurar(casa: c, jaNoPainel: jaTem).map(\.id), ["claude-equipe"])
    }

    func testSemNadaNoMacNaoAchaNada() throws {
        let c = try casa(perfis: [], codex: false)
        defer { try? FileManager.default.removeItem(at: c) }
        XCTAssertTrue(ContasAchadas.procurar(casa: c, jaNoPainel: []).isEmpty)
    }
}

@MainActor
final class PainelUsoTestes: XCTestCase {
    private func modelo(_ contas: [ContaIA] = []) -> ModeloApp {
        var c = Config.padrao(nomeMac: "Mac de teste")
        c.contas = contas
        return ModeloApp(config: c)
    }

    func testAcoesDoModelo() {
        let m = modelo([claudeLeo, codexPro])
        m.renomearConta(id: "codex", para: "plus")
        m.mostrarConta(id: "codex", noIphone: false)
        XCTAssertEqual(m.config.contas[1].conta, "plus")
        XCTAssertEqual(m.config.contas[1].mostrar, false)
        let r = m.removerConta(id: "claude-leo")
        XCTAssertEqual(r?.indice, 0)
        XCTAssertEqual(m.config.contas.map(\.id), ["codex"])
        m.restaurarConta(r!.conta, em: r!.indice)
        XCTAssertEqual(m.config.contas.map(\.id), ["claude-leo", "codex"])
        XCTAssertNil(m.removerConta(id: "nao-existe"))
    }

    func testRemoverDesfazerDevolveAContaEOToken() {
        let cofre = CofreFalso()
        try? cofre.guardar("segredo", conta: "claude-token-1")
        let p = PainelUso(cofre: cofre)
        let conta = ContaIA(id: "claude-token-1", nome: "Claude", conta: "Trabalho", perfil: nil, mostrar: true)
        let m = modelo([claudeLeo, conta])
        p.remover("claude-token-1", modelo: m)
        XCTAssertEqual(m.config.contas.map(\.id), ["claude-leo"])
        XCTAssertNil(cofre.ler(conta: "claude-token-1"), "o token sai do Chaveiro ao remover")
        XCTAssertTrue(p.podeDesfazer)
        XCTAssertEqual(p.aviso?.texto, "Conta Trabalho removida")
        XCTAssertEqual(p.aviso?.comDesfazer, true)
        p.desfazerUltimo()
        XCTAssertEqual(m.config.contas.map(\.id), ["claude-leo", "claude-token-1"])
        XCTAssertEqual(cofre.ler(conta: "claude-token-1"), "segredo")
        XCTAssertFalse(p.podeDesfazer)
        XCTAssertEqual(p.aviso?.texto, "Desfeito")
    }

    func testSomarContaAchada() {
        let p = PainelUso(cofre: CofreFalso())
        let m = modelo([])
        p.conta = EstadoConta()
        p.somar(ContaEncontrada(conta: claudeEquipe), modelo: m)
        XCTAssertEqual(m.config.contas.map(\.id), ["claude-equipe"])
        XCTAssertNil(p.conta)
    }

    func testTokenComFormatoErradoNaoChamaOClaudeENaoGuarda() async {
        let cofre = CofreFalso()
        let p = PainelUso(cofre: cofre, leitorToken: LeitorFalso(resultado: .ok(UsoDoToken(semana: 1, renova: nil))))
        let m = modelo([])
        p.conta = EstadoConta(token: "sk-ant-oat01-curto")
        await p.adicionarToken(modelo: m)
        XCTAssertEqual(p.conta?.erro, "O token parece cortado. Copie de novo, ele é bem longo.")
        XCTAssertTrue(m.config.contas.isEmpty)
    }

    func testTokenRecusadoMostraErroENaoGuarda() async {
        let cofre = CofreFalso()
        let p = PainelUso(cofre: cofre, leitorToken: LeitorFalso(resultado: .recusado))
        let m = modelo([])
        p.conta = EstadoConta(token: tokenValido(), nome: "Trabalho")
        await p.adicionarToken(modelo: m)
        XCTAssertEqual(p.conta?.erro, TokenClaude.recusado)
        XCTAssertEqual(p.conta?.conferindo, false)
        XCTAssertTrue(m.config.contas.isEmpty)
    }

    func testRespostaInesperadaTemMensagemPropria() async {
        let p = PainelUso(cofre: CofreFalso(), leitorToken: LeitorFalso(resultado: .inesperado))
        p.conta = EstadoConta(token: tokenValido())
        await p.adicionarToken(modelo: modelo([]))
        XCTAssertEqual(p.conta?.erro, TokenClaude.inesperado)
    }

    func testTokenSemRedeNaoViraRecusado() async {
        let p = PainelUso(cofre: CofreFalso(), leitorToken: LeitorFalso(resultado: .semRede))
        p.conta = EstadoConta(token: tokenValido())
        await p.adicionarToken(modelo: modelo([]))
        XCTAssertEqual(p.conta?.erro, TokenClaude.semRede)
    }

    func testTokenBomGuardaNoChaveiroEAdicionaAConta() async throws {
        let cofre = CofreFalso()
        let p = PainelUso(cofre: cofre, leitorToken: LeitorFalso(resultado: .ok(UsoDoToken(semana: 8, renova: nil))))
        let m = modelo([])
        p.conta = EstadoConta(token: tokenValido(), nome: "  Trabalho ")
        await p.adicionarToken(modelo: m)
        let nova = try XCTUnwrap(m.config.contas.first)
        XCTAssertEqual(nova.conta, "Trabalho")
        XCTAssertNil(nova.perfil)
        XCTAssertEqual(cofre.ler(conta: nova.id), tokenValido())
        XCTAssertEqual(p.usos[nova.id]?.semana, 8)
        XCTAssertNil(p.conta)
        // o token nunca entra na config que vai para o disco e para o iPhone
        let json = String(data: try JSONEncoder().encode(m.config), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains(TokenClaude.prefixo))
    }

    func testNomeVazioViraNovaConta() async throws {
        let p = PainelUso(cofre: CofreFalso(), leitorToken: LeitorFalso(resultado: .ok(UsoDoToken(semana: 8, renova: nil))))
        let m = modelo([])
        p.conta = EstadoConta(token: tokenValido())
        await p.adicionarToken(modelo: m)
        XCTAssertEqual(m.config.contas.first?.conta, "nova conta")
    }

    func testFalhaNoChaveiroNaoAdicionaConta() async {
        let cofre = CofreFalso()
        cofre.falhaAoGuardar = true
        let p = PainelUso(cofre: cofre, leitorToken: LeitorFalso(resultado: .ok(UsoDoToken(semana: 8, renova: nil))))
        let m = modelo([])
        p.conta = EstadoConta(token: tokenValido())
        await p.adicionarToken(modelo: m)
        XCTAssertEqual(p.conta?.erro, TokenClaude.semGuardar)
        XCTAssertTrue(m.config.contas.isEmpty)
    }

    func testLerUsoDeContaComTokenUsaOLeitorEAsOcultasTambemAparecem() async {
        let cofre = CofreFalso()
        try? cofre.guardar("t", conta: "claude-token-1")
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("deck-vazio-\(UUID().uuidString)")
        var oculta = ContaIA(id: "claude-token-1", nome: "Claude", conta: "Trabalho", perfil: nil, mostrar: false)
        oculta.mostrar = false
        let uso = await PainelUso.lerUso(contas: [oculta], casa: casa, cofre: cofre,
                                         leitor: LeitorFalso(resultado: .ok(UsoDoToken(semana: 42, renova: nil))), agora: Date())
        XCTAssertEqual(uso["claude-token-1"]?.semana, 42)
    }
}

final class ChaveiroTestes: XCTestCase {
    /// O Chaveiro de verdade do Mac, num serviço só deste teste, apagado no fim.
    func testGuardaLeEApaga() throws {
        let c = Chaveiro(servico: "com.leonardorejani.deck.teste-\(UUID().uuidString)")
        defer { c.apagar(conta: "conta-a") }
        XCTAssertNil(c.ler(conta: "conta-a"))
        try c.guardar("um", conta: "conta-a")
        try c.guardar("dois", conta: "conta-a")
        XCTAssertEqual(c.ler(conta: "conta-a"), "dois")
        c.apagar(conta: "conta-a")
        XCTAssertNil(c.ler(conta: "conta-a"))
    }
}
