import XCTest
@testable import Nucleo

/// A tecla de reunião mostra o estado (SPEC, seção 13, item 39): Meet por JavaScript na aba, Zoom e Teams pelo menu.
final class EstadoReuniaoTestes: XCTestCase {
    let sala = "https://meet.google.com/abc-defg-hij"
    let chrome = NavegadorWeb.todos[1]
    let safari = NavegadorWeb.todos[0]

    private func tecla(_ id: String, _ app: String, _ acao: String?) -> Tecla {
        Tecla(id: id, nome: id, tipo: "app", valor: app, estado: nil, icone: nil, acao: acao.map { AcaoDeApp(id: $0, valor: nil) })
    }

    // MARK: - Meet

    func testMeetLeOsDoisBotoesPeloDataIsMuted() {
        XCTAssertEqual(LeituraDeMeet.lerEstados("mic=true;cam=false"), LeituraDeReuniao(microfone: .desligado, camera: .ligado))
        XCTAssertEqual(LeituraDeMeet.lerEstados("mic=false;cam=true"), LeituraDeReuniao(microfone: .ligado, camera: .desligado))
        XCTAssertEqual(LeituraDeMeet.lerEstados("mic=false;cam=?"), LeituraDeReuniao(microfone: .ligado, camera: .desconhecido))
        XCTAssertEqual(LeituraDeMeet.lerEstados("lixo"), .desconhecida())
    }

    func testMeetSalaAbertaDevolveOEstado() {
        let r = LeituraDeMeet.interpretar(status: 0, saida: "https://meet.google.com/landing\t?\n\(sala)\tmic=true;cam=false\n", navegador: chrome)
        XCTAssertEqual(r, .sala(LeituraDeReuniao(microfone: .desligado, camera: .ligado)))
    }

    func testMeetSemSalaFechadoEPermissao() {
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 0, saida: "https://meet.google.com/landing\tmic=false;cam=false\n", navegador: chrome), .semSala)
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 0, saida: "", navegador: chrome), .semSala)
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 0, saida: "fechado\n", navegador: chrome), .fechado)
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 1, saida: "Not authorized to send Apple events (-1743)", navegador: chrome), .semPermissao)
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 1, saida: "coisa estranha", navegador: chrome), .falhou)
    }

    func testMeetComJavascriptDesligadoNoNavegadorDizIsso() {
        let msg = "erro:Executing JavaScript through AppleScript is turned off. To turn it on, from the menu bar, select View > Developer > Allow JavaScript from Apple Events."
        XCTAssertEqual(LeituraDeMeet.interpretar(status: 0, saida: "\(sala)\t\(msg)\n", navegador: chrome), .javascriptDesligado)
    }

    func testComandoDoMeetEPorNavegadorESemAspasDuplasNoJavascript() {
        XCTAssertFalse(LeituraDeMeet.javascript.contains("\""))
        XCTAssertFalse(LeituraDeMeet.javascript.contains("\\"))
        let c = LeituraDeMeet.comando(chrome), s = LeituraDeMeet.comando(safari)
        XCTAssertTrue(c.contains("execute t javascript"))
        XCTAssertTrue(s.contains("do JavaScript"))
        XCTAssertTrue(c.contains("pgrep -x") && c.contains("Google Chrome"), "navegador fechado não é aberto para ser consultado")
        XCTAssertTrue(c.contains("com.google.Chrome"))
    }

    func testLeitorLeAAbaDoNavegadorEscolhido() {
        let f = ExecutorFalso([("meet.google.com", SaidaShell(status: 0, saida: "\(sala)\tmic=true;cam=true\n"))])
        let l = LeitorDeReuniao(executor: f).ler(.meet(chrome))
        XCTAssertEqual(l, LeituraDeReuniao(microfone: .desligado, camera: .desligado))
        XCTAssertEqual(f.comandos.count, 1)
    }

    func testMeetNoNavegadorProcuraEmTodosEPulaOsFechados() {
        let f = ExecutorFalso([
            ("'Safari'", SaidaShell(status: 0, saida: "fechado\n")),
            ("'Google Chrome'", SaidaShell(status: 0, saida: "\(sala)\tmic=false;cam=true\n")),
            ("meet.google.com", SaidaShell(status: 0, saida: "fechado\n")),
        ])
        let l = LeitorDeReuniao(executor: f).ler(.meetNoNavegador)
        XCTAssertEqual(l, LeituraDeReuniao(microfone: .ligado, camera: .desligado))
    }

    func testSemReuniaoNoMeetApagaATecla() {
        let f = ExecutorFalso([("meet.google.com", SaidaShell(status: 0, saida: "fechado\n"))])
        XCTAssertEqual(LeitorDeReuniao(executor: f).ler(.meetNoNavegador), .nenhuma)
    }

    func testJavascriptDesligadoMostraDesconhecidoComAviso() {
        let msg = "erro:Executing JavaScript through AppleScript is turned off."
        let f = ExecutorFalso([("meet.google.com", SaidaShell(status: 0, saida: "\(sala)\t\(msg)\n"))])
        let l = LeitorDeReuniao(executor: f).ler(.meet(chrome))
        XCTAssertEqual(l.microfone, .desconhecido)
        XCTAssertEqual(l.camera, .desconhecido)
        XCTAssertEqual(l.aviso, LeituraDeMeet.avisoJavascript)
    }

    func testSemPermissaoDaAutomacaoMostraDesconhecido() {
        let f = ExecutorFalso([("meet.google.com", SaidaShell(status: 1, saida: "Not authorized (-1743)"))])
        let l = LeitorDeReuniao(executor: f).ler(.meet(chrome))
        XCTAssertEqual(l.microfone, .desconhecido)
        XCTAssertEqual(l.aviso, LeituraDeMeet.avisoPermissao("Google Chrome"))
    }

    // MARK: - Menu do Zoom e do Teams

    func testTituloDeMenuDizOEstado() {
        func c(_ t: String) -> LeituraDeMenu.Item? { LeituraDeMenu.classificar(t) }
        XCTAssertEqual(c("Mute audio"), .init(item: .microfone, ligado: true))
        XCTAssertEqual(c("Unmute Audio"), .init(item: .microfone, ligado: false))
        XCTAssertEqual(c("Start Video"), .init(item: .camera, ligado: false))
        XCTAssertEqual(c("Stop Video"), .init(item: .camera, ligado: true))
        XCTAssertEqual(c("Mute"), .init(item: .microfone, ligado: true))
        XCTAssertEqual(c("Unmute"), .init(item: .microfone, ligado: false))
        XCTAssertEqual(c("Turn camera off"), .init(item: .camera, ligado: true))
        XCTAssertEqual(c("Turn on camera"), .init(item: .camera, ligado: false))
        XCTAssertEqual(c("Desativar áudio"), .init(item: .microfone, ligado: true))
        XCTAssertEqual(c("Ativar áudio"), .init(item: .microfone, ligado: false))
        XCTAssertEqual(c("Iniciar vídeo"), .init(item: .camera, ligado: false))
        XCTAssertEqual(c("Parar vídeo"), .init(item: .camera, ligado: true))
    }

    func testTituloQueNaoEDoMicrofoneNemDaCameraEIgnorado() {
        for t in ["Mute All", "Unmute All", "Mute Participants", "Start Meeting", "Stop Share", "Start Recording", "Copy Invite Link", "Quit zoom.us", ""] {
            XCTAssertNil(LeituraDeMenu.classificar(t), t)
        }
    }

    func testZoomEmReuniaoLeOMenu() {
        let saida = "About zoom.us\nPreferences...\nMute audio\nStop video\nStart Share\n---\nZoom Meeting\n"
        XCTAssertEqual(LeituraDeMenu.interpretar(saida), LeituraDeReuniao(microfone: .ligado, camera: .ligado))
        let mutado = "Unmute audio\nStart video\n---\nZoom Meeting\n"
        XCTAssertEqual(LeituraDeMenu.interpretar(mutado), LeituraDeReuniao(microfone: .desligado, camera: .desligado))
    }

    func testMenuSemOsItensEJanelaDeReuniaoDizDesconhecido() {
        XCTAssertEqual(LeituraDeMenu.interpretar("Preferências\nSair\n---\nReunião do Zoom\n"), .desconhecida())
    }

    func testMenuSemOsItensENenhumaJanelaDeReuniaoEApagado() {
        XCTAssertEqual(LeituraDeMenu.interpretar("About zoom.us\nPreferences\n---\nZoom Workplace\n"), .nenhuma)
    }

    func testZoomFechadoApagaATecla() {
        let f = ExecutorFalso([("pgrep", SaidaShell(status: 1, saida: ""))])
        XCTAssertEqual(LeitorDeReuniao(executor: f).ler(.zoom), .nenhuma)
        XCTAssertFalse(f.comandos.contains { $0.contains("System Events") }, "app fechado nem é consultado")
    }

    func testZoomAbertoLeOMenuPeloSystemEvents() {
        let f = ExecutorFalso([("pgrep", SaidaShell(status: 0, saida: "")), ("System Events", SaidaShell(status: 0, saida: "Unmute audio\nStop video\n---\nZoom Meeting\n"))])
        XCTAssertEqual(LeitorDeReuniao(executor: f).ler(.zoom), LeituraDeReuniao(microfone: .desligado, camera: .ligado))
        XCTAssertTrue(f.comandos.contains { $0.contains(#"process "zoom.us""#) })
    }

    func testZoomSemPermissaoDeAcessibilidadeMostraDesconhecido() {
        let f = ExecutorFalso([("pgrep", SaidaShell(status: 0, saida: "")), ("System Events", SaidaShell(status: 1, saida: "osascript is not allowed assistive access. (-25211)"))])
        let l = LeitorDeReuniao(executor: f).ler(.zoom)
        XCTAssertEqual(l.microfone, .desconhecido)
        XCTAssertEqual(l.aviso, LeituraDeMenu.avisoPermissao)
    }

    func testTeamsProcuraOProcessoNovoEDepoisOClassico() {
        let f = ExecutorFalso([
            ("'MSTeams'", SaidaShell(status: 1, saida: "")),
            ("'Microsoft Teams'", SaidaShell(status: 0, saida: "")),
            ("System Events", SaidaShell(status: 0, saida: "Mute\nTurn camera on\n---\nMeeting | Microsoft Teams\n")),
        ])
        XCTAssertEqual(LeitorDeReuniao(executor: f).ler(.teams), LeituraDeReuniao(microfone: .ligado, camera: .desligado))
    }

    // MARK: - Teclas

    func testSoTeclaDeAppComAcaoDeReuniaoEntra() {
        XCTAssertEqual(LeitorDeReuniao.item(da: tecla("a", "zoom.us", "reuniao-microfone")), .microfone)
        XCTAssertEqual(LeitorDeReuniao.item(da: tecla("b", "zoom.us", "reuniao-camera")), .camera)
        XCTAssertNil(LeitorDeReuniao.item(da: tecla("c", "zoom.us", nil)))
        XCTAssertNil(LeitorDeReuniao.item(da: tecla("d", "Safari", "link")))
    }

    func testLeUmaVezPorAppEDaOEstadoDeCadaTecla() {
        let f = ExecutorFalso([("pgrep", SaidaShell(status: 0, saida: "")), ("System Events", SaidaShell(status: 0, saida: "Unmute audio\nStop video\n---\n"))])
        let l = LeitorDeReuniao(executor: f).ler([
            tecla("mic", "zoom.us", "reuniao-microfone"), tecla("cam", "zoom.us", "reuniao-camera"), tecla("outra", "Safari", "link"),
        ])
        XCTAssertEqual(l.valor, ["mic": .desligado, "cam": .ligado])
        XCTAssertEqual(f.comandos.filter { $0.contains("System Events") }.count, 1)
    }

    // MARK: - Estado

    private func fontes(_ leitura: @escaping @Sendable ([Tecla]) -> Leitura<[String: EstadoDeReuniao]>) -> Fontes {
        Fontes(
            sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
            whatsapp: { Leitura(valor: nil, aviso: nil) }, seloWhatsApp: { nil }, spotify: { _ in Leitura(valor: nil, aviso: nil) },
            capa: { nil }, agenda: { _ in Leitura(valor: nil, aviso: nil) }, acesas: { _ in [] }, reuniao: leitura)
    }

    func testEstadoTrazOEstadoDasTeclasDeReuniao() {
        let cfg = config(perfil: [tecla("mic", "Google Meet", "reuniao-microfone"), tecla("outra", "Safari", nil)])
        let e = Agregador(fontes: fontes { _ in Leitura(valor: ["mic": .desligado], aviso: LeituraDeMeet.avisoJavascript) }).estado(config: cfg)
        XCTAssertEqual(e.reuniao, ["mic": .desligado])
        XCTAssertEqual(e.avisos, [LeituraDeMeet.avisoJavascript])
    }

    func testSemTeclaDeReuniaoOMacNemLeEOCampoFicaAusente() {
        let chamadas = Contador()
        let cfg = config(perfil: [tecla("outra", "Safari", nil)])
        let e = Agregador(fontes: fontes { _ in chamadas.somar(); return Leitura(valor: [:], aviso: nil) }).estado(config: cfg)
        XCTAssertNil(e.reuniao)
        XCTAssertEqual(chamadas.valor, 0)
    }

    func testEstadoVaiNoJsonComoTexto() throws {
        let cfg = config(perfil: [tecla("mic", "zoom.us", "reuniao-microfone")])
        let e = Agregador(fontes: fontes { _ in Leitura(valor: ["mic": .semReuniao], aviso: nil) }).estado(config: cfg)
        let json = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertTrue(json.contains(#""reuniao":{"mic":"sem-reuniao"}"#), json)
    }
}
