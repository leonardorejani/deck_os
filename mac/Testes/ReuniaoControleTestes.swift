import XCTest
@testable import Nucleo

private final class ShellDeReuniao: Executor, @unchecked Sendable {
    var comandos: [String] = []
    var respostas: [(trecho: String, saida: SaidaShell)] = []
    func rodar(_ comando: String) -> SaidaShell {
        comandos.append(comando)
        return respostas.first { comando.contains($0.trecho) }?.saida ?? SaidaShell(status: 0, saida: "")
    }
}

private final class Teclou: @unchecked Sendable { var lista: [Combinacao] = [] }

final class ControleDeReuniaoTestes: XCTestCase {
    private func tecla(_ app: String, _ acao: String) -> Tecla {
        Tecla(id: "t", nome: "Mutar", tipo: "app", valor: app, estado: nil, icone: nil, acao: AcaoDeApp(id: acao, valor: nil))
    }

    private func executor(_ f: Executor, acesso: Bool = true, _ enviadas: Teclou = Teclou()) -> ExecutorAcoes {
        ExecutorAcoes(shell: f, temAcessibilidade: { acesso }, enviarTecla: { enviadas.lista.append($0) })
    }

    private func app(_ valor: String, _ bundle: String, navegador: Bool = false) -> AppAchado {
        AppAchado(app: AppInstalado(nome: valor, valor: valor, bundle: bundle, navegador: navegador), caminho: "/x", abreArquivos: false)
    }

    // MARK: - Catálogo

    func testZoomTeamsENavegadoresOferecemMutarECamera() {
        let c = CatalogoDeAcoes(executor: ShellDeReuniao())
        let ids: (AppAchado) -> [String] = { c.acoes(para: $0).map(\.id) }
        XCTAssertEqual(ids(app("zoom.us", "us.zoom.xos")), ["reuniao-microfone", "reuniao-camera"])
        XCTAssertEqual(ids(app("Microsoft Teams", "com.microsoft.teams2")), ["reuniao-microfone", "reuniao-camera"])
        XCTAssertEqual(ids(app("Google Chrome", "com.google.Chrome", navegador: true)), ["link", "gmail", "reuniao-microfone", "reuniao-camera"])
        XCTAssertEqual(ids(app("Safari", "com.apple.Safari", navegador: true)), ["link", "gmail", "reuniao-microfone", "reuniao-camera"])
    }

    func testAppSemReuniaoNaoGanhaAsAcoes() {
        let c = CatalogoDeAcoes(executor: ShellDeReuniao())
        XCTAssertEqual(c.acoes(para: app("Calculator", "com.apple.calculator")).map(\.id), [])
        // Navegador que o Deck não sabe consultar por AppleScript não acha a aba do Meet.
        XCTAssertEqual(c.acoes(para: app("Firefox", "org.mozilla.firefox", navegador: true)).map(\.id), ["link", "gmail"])
    }

    func testConfigAceitaAAcaoSemEscolha() {
        var cfg = config(perfil: [tecla("zoom.us", "reuniao-microfone")])
        XCTAssertNil(Config.validar(cfg))
        cfg.perfis[0].teclas[0].acao = AcaoDeApp(id: "reuniao-camera", valor: nil)
        XCTAssertNil(Config.validar(cfg))
    }

    // MARK: - Atalhos

    func testAtalhosDosTresApps() {
        XCTAssertEqual(ControleDeReuniao.atalho(.meet(NavegadorWeb.todos[1]), .microfone), "cmd+d")
        XCTAssertEqual(ControleDeReuniao.atalho(.meet(NavegadorWeb.todos[1]), .camera), "cmd+e")
        XCTAssertEqual(ControleDeReuniao.atalho(.zoom, .microfone), "cmd+shift+a")
        XCTAssertEqual(ControleDeReuniao.atalho(.zoom, .camera), "cmd+shift+v")
        XCTAssertEqual(ControleDeReuniao.atalho(.teams, .microfone), "cmd+shift+m")
        XCTAssertEqual(ControleDeReuniao.atalho(.teams, .camera), "cmd+shift+o")
        for a: ControleDeReuniao.Alvo in [.meet(NavegadorWeb.todos[0]), .zoom, .teams] {
            for i: ControleDeReuniao.Item in [.microfone, .camera] { XCTAssertNotNil(Teclas.ler(ControleDeReuniao.atalho(a, i))) }
        }
    }

    func testSoSalaDeVerdadeContaComoReuniaoDoMeet() {
        XCTAssertTrue(ControleDeReuniao.ehSalaDoMeet("https://meet.google.com/abc-defg-hij"))
        XCTAssertTrue(ControleDeReuniao.ehSalaDoMeet("https://meet.google.com/abc-defg-hij?authuser=1"))
        XCTAssertFalse(ControleDeReuniao.ehSalaDoMeet("https://meet.google.com/landing"))
        XCTAssertFalse(ControleDeReuniao.ehSalaDoMeet("https://meet.google.com/"))
        XCTAssertFalse(ControleDeReuniao.ehSalaDoMeet("https://exemplo.com/abc-defg-hij"))
    }

    // MARK: - Execução

    func testMeetTrazAAbaDaSalaParaAFrenteEAperta() {
        let f = ShellDeReuniao()
        // Uma aba da página inicial do Meet (janela 1, aba 1) e a sala (janela 2, aba 3).
        f.respostas = [("meet.google.com", SaidaShell(status: 0, saida: "1\t1\thttps://meet.google.com/landing\n2\t3\thttps://meet.google.com/abc-defg-hij\n"))]
        let enviadas = Teclou()
        XCTAssertNil(executor(f, enviadas).executar(tecla("Google Chrome", "reuniao-microfone")))
        XCTAssertEqual(enviadas.lista, [Teclas.ler("cmd+d")!])
        let trazer = f.comandos.first { $0.contains("active tab index of window 2 to 3") }
        XCTAssertNotNil(trazer, "a aba certa vem para a frente antes do atalho")
        XCTAssertEqual(f.comandos.last, ExecutorAcoes.esperaDoFoco)
    }

    func testMeetNoSafariUsaAAbaAtualDoSafari() {
        let f = ShellDeReuniao()
        f.respostas = [("meet.google.com", SaidaShell(status: 0, saida: "1\t2\thttps://meet.google.com/abc-defg-hij\n"))]
        let enviadas = Teclou()
        XCTAssertNil(executor(f, enviadas).executar(tecla("Safari", "reuniao-camera")))
        XCTAssertEqual(enviadas.lista, [Teclas.ler("cmd+e")!])
        XCTAssertTrue(f.comandos.contains { $0.contains("set current tab of window 1 to tab 2 of window 1") })
    }

    func testMeetSemSalaAbertaNaoApertaNada() {
        let f = ShellDeReuniao()
        f.respostas = [("meet.google.com", SaidaShell(status: 0, saida: "1\t1\thttps://meet.google.com/landing\n"))]
        let enviadas = Teclou()
        XCTAssertEqual(executor(f, enviadas).executar(tecla("Google Chrome", "reuniao-microfone")), "Não achei uma reunião do Meet aberta no Google Chrome")
        XCTAssertEqual(enviadas.lista, [], "sem a sala na frente o atalho cairia em outro app")
    }

    func testMeetNavegadorFechadoSemPermissaoEFalha() {
        let f = ShellDeReuniao()
        let enviadas = Teclou()
        f.respostas = [("meet.google.com", SaidaShell(status: 0, saida: "fechado\n"))]
        XCTAssertEqual(executor(f, enviadas).executar(tecla("Google Chrome", "reuniao-microfone")), "O Google Chrome está fechado. Entre na reunião do Meet e tente de novo")
        f.respostas = [("meet.google.com", SaidaShell(status: 1, saida: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)"))]
        XCTAssertEqual(executor(f, enviadas).executar(tecla("Google Chrome", "reuniao-microfone")),
                       "O Deck não tem permissão para controlar o Google Chrome. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação.")
        f.respostas = [("meet.google.com", SaidaShell(status: 1, saida: "coisa estranha"))]
        XCTAssertEqual(executor(f, enviadas).executar(tecla("Google Chrome", "reuniao-microfone")), "Não consegui olhar as abas do Google Chrome")
        XCTAssertEqual(enviadas.lista, [])
    }

    func testZoomAbertoTrazOAppEApertaCmdShiftA() {
        let f = ShellDeReuniao()
        let enviadas = Teclou()
        XCTAssertNil(executor(f, enviadas).executar(tecla("zoom.us", "reuniao-microfone")))
        XCTAssertEqual(f.comandos, ["pgrep -x 'zoom.us' >/dev/null", "open -a 'zoom.us'", ExecutorAcoes.esperaDoFoco])
        XCTAssertEqual(enviadas.lista, [Teclas.ler("cmd+shift+a")!])
    }

    func testTeamsCameraApertaCmdShiftO() {
        let f = ShellDeReuniao()
        let enviadas = Teclou()
        XCTAssertNil(executor(f, enviadas).executar(tecla("Microsoft Teams", "reuniao-camera")))
        XCTAssertEqual(enviadas.lista, [Teclas.ler("cmd+shift+o")!])
    }

    func testZoomFechadoNaoApertaNada() {
        let f = ShellDeReuniao()
        f.respostas = [("pgrep", SaidaShell(status: 1, saida: ""))]
        let enviadas = Teclou()
        XCTAssertEqual(executor(f, enviadas).executar(tecla("zoom.us", "reuniao-camera")), "O Zoom não está aberto. Entre na reunião e tente de novo")
        XCTAssertEqual(enviadas.lista, [])
        XCTAssertFalse(f.comandos.contains { $0.hasPrefix("open") }, "não abre o Zoom só para mutar")
    }

    func testSemAcessibilidadeDaOErroDoDeckENaoAbreNada() {
        let f = ShellDeReuniao()
        XCTAssertEqual(executor(f, acesso: false).executar(tecla("zoom.us", "reuniao-microfone")), ExecutorAcoes.erroAcessibilidade)
        XCTAssertEqual(f.comandos, [])
    }

    func testTeclaDeAppQueNaoEDeReuniaoDaErroClaro() {
        let f = ShellDeReuniao()
        XCTAssertEqual(executor(f).executar(tecla("Calculator", "reuniao-microfone")), "A tecla \"Mutar\" precisa ser de um navegador, do Zoom ou do Teams")
        XCTAssertEqual(f.comandos, [])
    }
}
