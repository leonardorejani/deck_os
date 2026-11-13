import XCTest
@testable import Nucleo

/// A central do Google Meet (SPEC 13, 13/11/2026): estado e ações pela Acessibilidade, sem a opção de JavaScript do navegador.

private final class ArvoreFalsa: AcessibilidadeDoNavegador, @unchecked Sendable {
    var porPid: [Int32: [JanelaDoNavegador]] = [:]
    var apertados: [String] = []
    var apertaCom = true
    func janelas(pid: Int32) -> [JanelaDoNavegador]? { porPid[pid] }
    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool { apertados.append("\(pid)/\(janela)/\(rotulo)"); return apertaCom }
}

/// Chrome aberto com o pid 4242. O `osascript` responde o que o teste mandar (nada, por padrão).
private final class ShellDoMeet: Executor, @unchecked Sendable {
    var comandos: [String] = []
    var chromeAberto = true
    var osascript: [(trecho: String, saida: SaidaShell)] = []
    func rodar(_ comando: String) -> SaidaShell {
        comandos.append(comando)
        if comando == "pgrep -x 'Google Chrome'" { return chromeAberto ? SaidaShell(status: 0, saida: "4242\n") : SaidaShell(status: 1, saida: "") }
        if comando.hasPrefix("pgrep -x ") { return SaidaShell(status: 1, saida: "") }
        // A busca é "if pgrep -x '<navegador>' ...; then osascript ...; else echo fechado; fi" (dentro do vigia de tempo):
        // só o Chrome está aberto.
        if comando.contains("if pgrep -x"), !comando.contains("pgrep -x '\\''Google Chrome'\\''") || !chromeAberto { return SaidaShell(status: 0, saida: "fechado\n") }
        return osascript.first { comando.contains($0.trecho) }?.saida ?? SaidaShell(status: 0, saida: "")
    }
    var rodouOsascript: Bool { comandos.contains { $0.contains("osascript") } }
}

private final class Teclou: @unchecked Sendable { var lista: [Combinacao] = [] }

private func janela(_ rotulos: String...) -> JanelaDoNavegador {
    JanelaDoNavegador(titulo: "Meet", botoes: rotulos.map { BotaoWeb(rotulos: [$0]) })
}

final class MeetTestes: XCTestCase {
    let chrome = NavegadorWeb.todos[1]
    let sala = "https://meet.google.com/abc-defg-hij"

    // MARK: - O nome do botão diz o estado

    func testRotulosEmPortuguesInglesEEspanhol() {
        func c(_ texto: String) -> BotaoDoMeet? { BotaoDoMeet.classificar(texto) }
        XCTAssertEqual(c("Desativar microfone (ctrl + d)"), .microfone(ligado: true))
        XCTAssertEqual(c("Ativar microfone (⌘ + d)"), .microfone(ligado: false))
        XCTAssertEqual(c("Desativar câmera (ctrl + e)"), .camera(ligado: true))
        XCTAssertEqual(c("Ativar câmera"), .camera(ligado: false))
        XCTAssertEqual(c("Turn off microphone (ctrl + d)"), .microfone(ligado: true))
        XCTAssertEqual(c("Turn on camera (ctrl + e)"), .camera(ligado: false))
        XCTAssertEqual(c("Desactivar micrófono"), .microfone(ligado: true))
        XCTAssertEqual(c("Activar cámara"), .camera(ligado: false))
        XCTAssertEqual(c("Sair da chamada"), .sair)
        XCTAssertEqual(c("Leave call"), .sair)
        XCTAssertEqual(c("Salir de la llamada"), .sair)
    }

    func testBotaoDeOutroParticipanteOuDeOutraCoisaNaoEntra() {
        for r in ["Silenciar o microfone de Ana", "Mute everyone", "Desativar legendas", "Turn off captions", "Ativar câmera de Bia",
                  "Apresentar agora", "Mais opções", "", "Microfone"] {
            XCTAssertNil(BotaoDoMeet.classificar(r), r)
        }
    }

    // MARK: - Leitura

    func testLeSalaDentroDaChamada() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Início"), janela("Mais opções", "Desativar microfone (ctrl + d)", "Ativar câmera (ctrl + e)", "Sair da chamada")]
        let r = LeitorDeMeetAX.ler(chrome, executor: sh, ax: ax, confiavel: true)
        XCTAssertEqual(r, .sala(SalaMeet(navegador: chrome, janela: 1, microfone: .ligado, camera: .desligado, naChamada: true)))
    }

    func testTelaDeEntradaNaoTemSair() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Ativar microfone", "Desativar câmera", "Participar agora")]
        guard case .sala(let s) = LeitorDeMeetAX.ler(chrome, executor: sh, ax: ax, confiavel: true) else { return XCTFail("achou") }
        XCTAssertEqual(s.microfone, .desligado)
        XCTAssertEqual(s.camera, .ligado)
        XCTAssertFalse(s.naChamada)
    }

    func testSemSalaFechadoESemAcesso() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Pesquisar", "Mais opções")]
        XCTAssertEqual(LeitorDeMeetAX.ler(chrome, executor: sh, ax: ax, confiavel: true), .semSala)
        XCTAssertEqual(LeitorDeMeetAX.ler(chrome, executor: sh, ax: ax, confiavel: false), .semAcesso)
        sh.chromeAberto = false
        XCTAssertEqual(LeitorDeMeetAX.ler(chrome, executor: sh, ax: ax, confiavel: true), .fechado)
    }

    func testAsTeclasLemOEstadoSemJavaScriptNemAutomacao() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Ativar microfone", "Desativar câmera", "Sair da chamada")]
        let mic = Tecla(id: "mic", nome: "Mutar", tipo: "app", valor: "Google Meet", estado: nil, icone: nil, acao: AcaoDeApp(id: "reuniao-microfone", valor: nil))
        let cam = Tecla(id: "cam", nome: "Câmera", tipo: "app", valor: "Google Meet", estado: nil, icone: nil, acao: AcaoDeApp(id: "reuniao-camera", valor: nil))
        let l = LeitorDeReuniao(executor: sh, acessibilidade: ax, temAcessibilidade: { true }).ler([mic, cam])
        XCTAssertEqual(l.valor, ["mic": .desligado, "cam": .ligado])
        XCTAssertNil(l.aviso)
        XCTAssertFalse(sh.rodouOsascript, "nenhum AppleScript: nem JavaScript do navegador nem Automação")
    }

    func testSemLeituraPelaAcessibilidadeOJavaScriptAindaServe() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Pesquisar")] // a aba da reunião está atrás de outra
        sh.osascript = [("execute t javascript", SaidaShell(status: 0, saida: "\(sala)\tmic=false;cam=true\n"))]
        let l = LeitorDeReuniao(executor: sh, acessibilidade: ax, temAcessibilidade: { true }).lerMeet([chrome])
        XCTAssertEqual(l, LeituraDeReuniao(microfone: .ligado, camera: .desligado))
    }

    // MARK: - Ação

    private func acoes(_ sh: Executor, _ ax: ArvoreFalsa, _ teclou: Teclou = Teclou()) -> ExecutorAcoes {
        ExecutorAcoes(shell: sh, temAcessibilidade: { true }, enviarTecla: { teclou.lista.append($0) }, ax: ax)
    }

    func testMicrofoneApertaOBotaoSemTrazerONavegadorNemTeclar() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa(), t = Teclou()
        ax.porPid[4242] = [janela("Desativar microfone (ctrl + d)", "Sair da chamada")]
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax, t)).agir(.microfone))
        XCTAssertEqual(ax.apertados, ["4242/0/Desativar microfone (ctrl + d)"])
        XCTAssertTrue(t.lista.isEmpty)
        XCTAssertFalse(sh.rodouOsascript)
    }

    func testCameraApertaOBotaoDaCamera() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Ativar microfone", "Ativar câmera (ctrl + e)")]
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax)).agir(.camera))
        XCTAssertEqual(ax.apertados, ["4242/0/Ativar câmera (ctrl + e)"])
    }

    func testSemLeituraDaPaginaMicrofoneCaiNoAtalhoDoMeet() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa(), t = Teclou()
        sh.osascript = [("starts with \"https://meet.google.com/\"", SaidaShell(status: 0, saida: "1\t2\t\(sala)\n"))]
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax, t)).agir(.microfone))
        XCTAssertTrue(ax.apertados.isEmpty)
        XCTAssertEqual(t.lista, [Teclas.ler("cmd+d")!], "Cmd+D com a aba da reunião na frente")
    }

    func testSairApertaSairDaChamada() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Desativar microfone", "Sair da chamada")]
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax)).agir(.sair))
        XCTAssertEqual(ax.apertados, ["4242/0/Sair da chamada"])
    }

    func testSairSemChamadaDizOQueFazer() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Ativar microfone", "Participar agora")] // tela de entrada, sem "Sair da chamada"
        XCTAssertEqual(MeetReal(executor: sh, acoes: acoes(sh, ax)).agir(.sair), MeetReal.naoAchouAChamada)
        XCTAssertTrue(ax.apertados.isEmpty)
    }

    func testSairSemAcessibilidadeDizPorque() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        let sem = ExecutorAcoes(shell: sh, temAcessibilidade: { false }, enviarTecla: { _ in }, ax: ax)
        XCTAssertEqual(MeetReal(executor: sh, acoes: sem).agir(.sair), MeetReal.semAcessibilidade)
    }

    func testEntrarSemReuniaoAbreOMeetNoNavegador() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax)).agir(.entrar))
        XCTAssertTrue(sh.comandos.contains("open 'https://meet.google.com'"))
    }

    func testEntrarComReuniaoAbertaTrazAAbaEmVezDeAbrirOutra() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        sh.osascript = [("starts with \"https://meet.google.com/\"", SaidaShell(status: 0, saida: "1\t2\t\(sala)\n"))]
        XCTAssertNil(MeetReal(executor: sh, acoes: acoes(sh, ax)).agir(.entrar))
        XCTAssertTrue(sh.comandos.contains { $0.contains("set active tab index of window 1 to 2") }, sh.comandos.joined(separator: "\n---\n"))
        XCTAssertFalse(sh.comandos.contains("open 'https://meet.google.com'"))
    }

    // MARK: - Estado

    func testEstadoSemReuniaoNaoFingeEstado() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Pesquisar")]
        let e = MeetReal(executor: sh, acoes: acoes(sh, ax)).estado()
        XCTAssertEqual(e, .semReuniao)
    }

    func testEstadoNaChamada() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Desativar microfone", "Ativar câmera", "Sair da chamada")]
        let e = MeetReal(executor: sh, acoes: acoes(sh, ax)).estado()
        XCTAssertEqual(e, EstadoMeet(aberta: true, naChamada: true, microfone: .ligado, camera: .desligado))
    }

    func testEstadoComSalaAtrasDeOutraAbaDizQueHaReuniaoMasNaoLe() {
        let sh = ShellDoMeet(), ax = ArvoreFalsa()
        ax.porPid[4242] = [janela("Pesquisar")]
        sh.osascript = [("execute t javascript", SaidaShell(status: 0, saida: "\(sala)\terro:JavaScript from Apple Events is disabled\n"))]
        let e = MeetReal(executor: sh, acoes: acoes(sh, ax)).estado()
        XCTAssertTrue(e.aberta)
        XCTAssertEqual(e.microfone, .desconhecido)
        XCTAssertEqual(e.aviso, LeituraDeMeet.avisoJavascript.texto)
    }

    // MARK: - Rotas

    private final class MeetFalso: MeetDoMac, @unchecked Sendable {
        var feitas: [AcaoMeet] = []
        var erro: String?
        func estado() -> EstadoMeet { EstadoMeet(aberta: true, naChamada: true, microfone: .ligado, camera: .desligado) }
        func agir(_ acao: AcaoMeet) -> String? { feitas.append(acao); return erro }
    }

    func testRotaDeEstado() throws {
        var c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/meet").status, 404, "sem a central o Mac responde 404 (Mac antigo)")
        c.roteador.meet = MeetFalso()
        XCTAssertEqual(c.pedir("GET", "/api/meet", codigo: nil).status, 401)
        let r = c.pedir("GET", "/api/meet")
        XCTAssertEqual(r.status, 200)
        let j = r.json as? [String: Any]
        XCTAssertEqual(j?["aberta"] as? Bool, true)
        XCTAssertEqual(j?["microfone"] as? String, "ligado")
        XCTAssertEqual(j?["camera"] as? String, "desligado")
        XCTAssertEqual(c.pedir("POST", "/api/meet").status, 405)
    }

    func testRotaDeAcao() throws {
        var c = try Cenario()
        let f = MeetFalso()
        c.roteador.meet = f
        for a in ["entrar", "microfone", "camera", "sair"] { XCTAssertEqual(c.pedir("POST", "/api/meet/\(a)").status, 200, a) }
        XCTAssertEqual(f.feitas, [.entrar, .microfone, .camera, .sair])
        XCTAssertEqual(c.pedir("POST", "/api/meet/apagar-tudo").status, 404)
        XCTAssertEqual(c.pedir("GET", "/api/meet/sair").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/meet/sair", codigo: nil).status, 401)
        f.erro = "Não achei a chamada"
        XCTAssertEqual(c.pedir("POST", "/api/meet/sair").status, 422)
    }
}
