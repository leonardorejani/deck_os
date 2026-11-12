import XCTest
@testable import Nucleo

/// Executor falso que responde por prefixo do comando e guarda tudo que foi pedido.
final class ExecutorPorPrefixo: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var _comandos: [String] = []
    var respostas: [(prefixo: String, saida: SaidaShell)] = []
    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }
    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); _comandos.append(comando); trava.unlock()
        return respostas.first { comando.hasPrefix($0.prefixo) }?.saida ?? SaidaShell(status: 0, saida: "")
    }
}

final class ReuniaoTestes: XCTestCase {
    // MARK: Achar o link

    func testAchaOLinkDoMeetNasNotas() {
        let notas = "Pauta: x\nEntre em https://meet.google.com/abc-defg-hij. Até lá."
        XCTAssertEqual(Reuniao.achar(em: [nil, "Sala 2", notas]), "https://meet.google.com/abc-defg-hij")
    }

    func testOEnderecoDoEventoVemAntesDoLocalEDasNotas() {
        let r = Reuniao.achar(em: ["https://teams.microsoft.com/l/meetup-join/19%3a123", "https://meet.google.com/aaa-bbbb-ccc", nil])
        XCTAssertEqual(r, "https://teams.microsoft.com/l/meetup-join/19%3a123")
    }

    func testZoomDeSubdominioEOTeamsLive() {
        XCTAssertEqual(Reuniao.achar(em: ["Link: https://us02web.zoom.us/j/81234567890?pwd=abc123"]), "https://us02web.zoom.us/j/81234567890?pwd=abc123")
        XCTAssertEqual(Reuniao.achar(em: ["https://teams.live.com/meet/9300000000"]), "https://teams.live.com/meet/9300000000")
    }

    func testIgnoraEnderecoQueNaoEDeReuniaoOuQueImita() {
        XCTAssertNil(Reuniao.achar(em: ["https://exemplo.com/?r=meet.google.com", "http://meet.google.com/abc", "https://meet.google.com.golpe.com/abc"]))
        XCTAssertNil(Reuniao.achar(em: ["https://zoom.us.golpe.com/j/123456789", "https://meet.google.com@golpe.com/abc", "https://evilzoom.us/j/123456789"]))
        XCTAssertNil(Reuniao.achar(em: [nil, "", "Templo"]))
    }

    func testValidarRecusaOQueNaoEHttpsDosTresServicos() {
        XCTAssertEqual(Reuniao.validar("https://meet.google.com/abc-defg-hij")?.servico, .meet)
        XCTAssertEqual(Reuniao.validar(" https://zoom.us/j/123456789 ")?.servico, .zoom)
        XCTAssertNil(Reuniao.validar("file:///Applications/Calculator.app"))
        XCTAssertNil(Reuniao.validar("zoommtg://zoom.us/join?confno=123456789"))
        XCTAssertNil(Reuniao.validar("javascript:alert(1)"))
        XCTAssertNil(Reuniao.validar(""))
    }

    // MARK: Zoom no app

    func testEnderecoDoAppDoZoomLevaONumeroEASenha() {
        let url = URL(string: "https://us02web.zoom.us/j/81234567890?pwd=abc123")!
        XCTAssertEqual(Reuniao.enderecoDoAppZoom(url), "zoommtg://us02web.zoom.us/join?confno=81234567890&pwd=abc123")
        XCTAssertEqual(Reuniao.enderecoDoAppZoom(URL(string: "https://zoom.us/j/81234567890")!), "zoommtg://zoom.us/join?confno=81234567890")
        XCTAssertNil(Reuniao.enderecoDoAppZoom(URL(string: "https://zoom.us/my/sala-do-leo")!))
        XCTAssertNil(Reuniao.enderecoDoAppZoom(URL(string: "https://meet.google.com/abc-defg-hij")!))
    }

    func testSenhaComCaractereEstranhoNaoViajaParaOApp() {
        let url = URL(string: "https://zoom.us/j/81234567890?pwd=a%26b%3Bc")!
        XCTAssertEqual(Reuniao.enderecoDoAppZoom(url), "zoommtg://zoom.us/join?confno=81234567890")
    }

    // MARK: Abrir

    func testMeetAbreNoNavegadorPadraoSemProcurarOZoom() {
        let f = ExecutorPorPrefixo()
        XCTAssertNil(AbridorDeReuniao(shell: f).entrar("https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(f.comandos, ["open 'https://meet.google.com/abc-defg-hij'"])
    }

    func testTeamsAbreNoNavegadorPadrao() {
        let f = ExecutorPorPrefixo()
        XCTAssertNil(AbridorDeReuniao(shell: f).entrar("https://teams.microsoft.com/l/meetup-join/19%3a123"))
        XCTAssertEqual(f.comandos, ["open 'https://teams.microsoft.com/l/meetup-join/19%3a123'"])
    }

    func testZoomInstaladoAbreNoApp() {
        let f = ExecutorPorPrefixo()
        f.respostas = [("mdfind", SaidaShell(status: 0, saida: "/Applications/zoom.us.app\n"))]
        XCTAssertNil(AbridorDeReuniao(shell: f).entrar("https://us02web.zoom.us/j/81234567890?pwd=abc123"))
        XCTAssertEqual(f.comandos.last, "open 'zoommtg://us02web.zoom.us/join?confno=81234567890&pwd=abc123'")
        XCTAssertFalse(f.comandos.contains { $0.hasPrefix("open 'https") })
    }

    func testZoomSemOAppAbreNoNavegador() {
        let f = ExecutorPorPrefixo()
        f.respostas = [("mdfind", SaidaShell(status: 0, saida: ""))]
        XCTAssertNil(AbridorDeReuniao(shell: f).entrar("https://zoom.us/j/81234567890"))
        XCTAssertEqual(f.comandos.last, "open 'https://zoom.us/j/81234567890'")
        XCTAssertFalse(f.comandos.contains { $0.contains("zoommtg") })
    }

    func testZoomQueNaoAbreNoAppCaiParaONavegador() {
        let f = ExecutorPorPrefixo()
        f.respostas = [("mdfind", SaidaShell(status: 0, saida: "/Applications/zoom.us.app")), ("open 'zoommtg", SaidaShell(status: 1, saida: "erro"))]
        XCTAssertNil(AbridorDeReuniao(shell: f).entrar("https://zoom.us/j/81234567890"))
        XCTAssertEqual(f.comandos.last, "open 'https://zoom.us/j/81234567890'")
    }

    func testLinkDeOutroLugarNaoAbreNada() {
        let f = ExecutorPorPrefixo()
        XCTAssertNotNil(AbridorDeReuniao(shell: f).entrar("https://golpe.com/meet.google.com"))
        XCTAssertEqual(f.comandos, [])
    }

    func testAbrirQueFalhaDevolveOMotivo() {
        let f = ExecutorPorPrefixo()
        f.respostas = [("open", SaidaShell(status: 1, saida: "x"))]
        XCTAssertEqual(AbridorDeReuniao(shell: f).entrar("https://meet.google.com/abc-defg-hij"), "O Mac não conseguiu abrir o link da reunião.")
    }

    // MARK: Contrato

    func testEventoAntigoSemLinkAindaLe() throws {
        let json = ##"{"titulo":"Ensaio","inicio":"2026-11-11T12:00:00Z","diaTodo":false,"calendario":"Louvor","cor":"#ff8000"}"##
        let e = try JSONDecoder().decode(Evento.self, from: Data(json.utf8))
        XCTAssertNil(e.link)
    }

    func testEventoComLinkViajaNoJson() throws {
        let e = Evento(titulo: "Reunião", inicio: "2026-11-11T12:00:00Z", diaTodo: false, calendario: "T", cor: "#000000", local: nil, link: "https://meet.google.com/abc-defg-hij")
        let dados = try JSONEncoder().encode(e)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: dados) as? [String: Any])?["link"] as? String, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(try JSONDecoder().decode(Evento.self, from: dados), e)
    }

    // iphone-bugs (12/11/2026): sem o fim, o painel não sabe que o evento de vários dias continua no mês seguinte.
    func testConverterLevaOFimParaEventoDeVariosDias() throws {
        let b = EventoBruto(titulo: "Viagem", inicio: Date(timeIntervalSince1970: 1_794_400_000), fim: Date(timeIntervalSince1970: 1_794_400_000 + 4 * 86_400),
                            diaTodo: true, calendario: "T", cor: (r: 0, g: 0, b: 0), local: nil)
        let e = Agenda.converter(b, fuso: utc)
        XCTAssertEqual(e.fim, Datas.iso(b.fim, fuso: utc))
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(e), as: UTF8.self).contains("\"fim\""))
    }

    func testConverterLevaOLinkDoEventoBruto() {
        var b = EventoBruto(titulo: "x", inicio: Date(timeIntervalSince1970: 1_794_400_000), fim: Date(timeIntervalSince1970: 1_794_403_600),
                            diaTodo: false, calendario: "T", cor: (r: 0, g: 0, b: 0), local: "Google Meet")
        b.link = "https://meet.google.com/abc-defg-hij"
        XCTAssertEqual(Agenda.converter(b, fuso: utc).link, "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(Agenda.converter(EventoBruto(titulo: "y", inicio: b.inicio, fim: b.fim, diaTodo: false, calendario: "T", cor: (r: 0, g: 0, b: 0), local: nil), fuso: utc).link)
    }

    // MARK: Rota

    private struct ReuniaoFalsa: ProvedorDeReuniao {
        let registro: Registro
        func entrar(_ link: String) -> String? { registro.anotar("reuniao \(link)"); return nil }
    }

    func testRotaEntrarNaReuniao() throws {
        var c = try Cenario()
        c.roteador.reunioes = ReuniaoFalsa(registro: c.registro)
        let ok = c.pedir("POST", "/api/reuniao/entrar", corpo: #"{"link":"https://meet.google.com/abc-defg-hij"}"#)
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(c.registro.todos, ["reuniao https://meet.google.com/abc-defg-hij"])
    }

    func testRotaRecusaLinkQueNaoEDeReuniaoSemAbrirNada() throws {
        var c = try Cenario()
        c.roteador.reunioes = ReuniaoFalsa(registro: c.registro)
        for corpo in [#"{"link":"https://golpe.com/x"}"#, #"{"link":"file:///etc/passwd"}"#, #"{}"#, "não é json"] {
            XCTAssertEqual(c.pedir("POST", "/api/reuniao/entrar", corpo: corpo).status, 400, corpo)
        }
        XCTAssertEqual(c.registro.todos, [])
    }

    func testRotaDaReuniaoExigeCodigoEPost() throws {
        var c = try Cenario()
        c.roteador.reunioes = ReuniaoFalsa(registro: c.registro)
        XCTAssertEqual(c.pedir("POST", "/api/reuniao/entrar", corpo: #"{"link":"https://meet.google.com/a"}"#, codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/reuniao/entrar").status, 405)
        XCTAssertEqual(try Cenario().pedir("POST", "/api/reuniao/entrar", corpo: #"{"link":"https://meet.google.com/a"}"#).status, 404)
    }
}

final class AbrirSessaoTestes: XCTestCase {
    let ps = """
      101     1 ??       /Applications/Orca.app/Contents/MacOS/Orca
      230   101 ??       /Applications/Orca.app/Contents/Frameworks/Orca Helper.app/Contents/MacOS/Orca Helper
      15264   230 ttys014  -zsh
      15545 15264 ttys014  /Users/x/.nvm/versions/node/v24/bin/claude attach PROJETO_PRS
       300     1 ??       /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
       310   300 ttys020  login -pf x
       311   310 ttys020  -zsh
       312   311 ttys020  /Users/x/.nvm/versions/node/v24/bin/claude attach convite novos usuarios
       400   311 ttys021  /Users/x/.nvm/versions/node/v24/bin/claude attach OUTRA_SESSAO
    """

    func testAchaOAppDonoDoTerminalDaSessao() {
        let t = AbridorDeSessaoNoMac.terminalDe(processos: ps, chamados: ["PROJETO_PRS", "abcd1234"])
        XCTAssertEqual(t, .init(caminhoDoApp: "/Applications/Orca.app", nomeDoApp: "Orca", tty: "ttys014"))
    }

    func testNomeComEspacoEOTerminalDaApple() {
        let t = AbridorDeSessaoNoMac.terminalDe(processos: ps, chamados: ["convite novos usuarios"])
        XCTAssertEqual(t, .init(caminhoDoApp: "/System/Applications/Utilities/Terminal.app", nomeDoApp: "Terminal", tty: "ttys020"))
    }

    func testSessaoSemTerminalDevolveNil() {
        XCTAssertNil(AbridorDeSessaoNoMac.terminalDe(processos: ps, chamados: ["NINGUEM"]))
        // um nome que é só começo do outro não confunde
        XCTAssertNil(AbridorDeSessaoNoMac.terminalDe(processos: ps, chamados: ["PROJETO"]))
    }

    func testProcessoQueSoCitaAttachNaoContaComoSessao() {
        let outro = "  500     1 ??       /usr/bin/vim notas-de-attach PROJETO_PRS\n  501     1 ??       /usr/bin/grep claude attach PROJETO_PRS"
        XCTAssertNil(AbridorDeSessaoNoMac.terminalDe(processos: outro, chamados: ["PROJETO_PRS"]))
    }

    private func raizComSessao(id: String, json: String) throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("deck-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz.appendingPathComponent(id), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: raiz.appendingPathComponent(id).appendingPathComponent("state.json"))
        return raiz
    }

    func testOrcaVemParaAFrente() throws {
        let raiz = try raizComSessao(id: "3bf9890f", json: #"{"state":"blocked","name":"PROJETO_PRS","originCwd":"/tmp"}"#)
        let f = ExecutorPorPrefixo(); f.respostas = [("ps", SaidaShell(status: 0, saida: ps))]
        let r = AbridorDeSessaoNoMac(raiz: raiz, shell: f).abrir(id: "3bf9890f")
        XCTAssertEqual(try r.get(), SessaoAberta(como: "terminal", app: "Orca"))
        XCTAssertEqual(f.comandos.last, "open '/Applications/Orca.app'")
    }

    func testTerminalDaAppleEscolheAAbaPeloTty() throws {
        let raiz = try raizComSessao(id: "9a9a9a9a", json: #"{"state":"blocked","name":"convite novos usuarios"}"#)
        let f = ExecutorPorPrefixo(); f.respostas = [("ps", SaidaShell(status: 0, saida: ps))]
        let r = AbridorDeSessaoNoMac(raiz: raiz, shell: f).abrir(id: "9a9a9a9a")
        XCTAssertEqual(try r.get(), SessaoAberta(como: "terminal", app: "Terminal"))
        XCTAssertTrue(f.comandos.last?.hasPrefix("osascript -e") == true)
        XCTAssertTrue(f.comandos.last?.contains("/dev/ttys020") == true)
    }

    func testSemTerminalAbreOTerminalNaPastaDoProjeto() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("projeto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let raiz = try raizComSessao(id: "11112222", json: #"{"state":"blocked","name":"SEM_TERMINAL","originCwd":"\#(pasta.path)","cwd":"/nao/existe"}"#)
        let f = ExecutorPorPrefixo(); f.respostas = [("ps", SaidaShell(status: 0, saida: ps))]
        let r = AbridorDeSessaoNoMac(raiz: raiz, shell: f).abrir(id: "11112222")
        XCTAssertEqual(try r.get(), SessaoAberta(como: "pasta", app: "Terminal"))
        XCTAssertEqual(f.comandos.last, "open -a Terminal '\(pasta.path)'")
    }

    func testSemTerminalNemPastaDevolveErro() throws {
        let raiz = try raizComSessao(id: "33334444", json: #"{"state":"blocked","name":"SEM_TERMINAL","originCwd":"/nao/existe"}"#)
        let f = ExecutorPorPrefixo(); f.respostas = [("ps", SaidaShell(status: 0, saida: ps))]
        guard case .failure(let e) = AbridorDeSessaoNoMac(raiz: raiz, shell: f).abrir(id: "33334444") else { return XCTFail("devia falhar") }
        XCTAssertEqual(e.status, 422)
        XCTAssertFalse(f.comandos.contains { $0.hasPrefix("open") })
    }

    func testIdForaDaPastaDeJobsNaoLeNada() throws {
        let raiz = try raizComSessao(id: "55556666", json: #"{"state":"blocked"}"#)
        let f = ExecutorPorPrefixo()
        for id in ["", "..", "../55556666", "a/b", "naoexiste"] {
            guard case .failure(let e) = AbridorDeSessaoNoMac(raiz: raiz, shell: f).abrir(id: id) else { return XCTFail("devia falhar: \(id)") }
            XCTAssertEqual(e.status, 404, id)
        }
        XCTAssertEqual(f.comandos, [])
    }

    // MARK: Rota

    private struct AbridorFalso: AbridorDeSessao {
        let registro: Registro
        func abrir(id: String) -> Result<SessaoAberta, ErroAbrirSessao> {
            registro.anotar("abrir \(id)")
            return id == "some" ? .failure(ErroAbrirSessao(status: 404, texto: "Essa sessão não existe mais neste Mac.")) : .success(SessaoAberta(como: "terminal", app: "Orca"))
        }
    }

    func testRotaAbrirSessao() throws {
        var c = try Cenario()
        c.roteador.abridorDeSessao = AbridorFalso(registro: c.registro)
        let ok = c.pedir("POST", "/api/sessoes/s1/abrir")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual((ok.json as? [String: Any])?["app"] as? String, "Orca")
        XCTAssertEqual((ok.json as? [String: Any])?["como"] as? String, "terminal")
        XCTAssertEqual(c.pedir("POST", "/api/sessoes/some/abrir").status, 404)
        XCTAssertEqual(c.pedir("GET", "/api/sessoes/s1/abrir").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/sessoes/s1/abrir", codigo: nil).status, 401)
        XCTAssertEqual(c.registro.todos, ["abrir s1", "abrir some"])
        XCTAssertEqual((c.pedir("GET", "/api/sessoes").json as? [[String: Any]])?.first?["id"] as? String, "s1")
    }

    func testRotaAbrirSessaoSemAbridorNaoExiste() throws {
        XCTAssertEqual(try Cenario().pedir("POST", "/api/sessoes/s1/abrir").status, 404)
    }
}
