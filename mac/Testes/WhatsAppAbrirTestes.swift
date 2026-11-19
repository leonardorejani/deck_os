import XCTest
@testable import Nucleo

/// "Responder no Mac" e "Abrir no Mac" do WhatsApp (13/11/2026): nunca abrir aba nova sem saber se já existe uma,
/// achar a aba pela Acessibilidade quando a Automação falha, seguir o ajuste de onde abrir, e registrar cada passo.

final class ArvoreDeAbas: AcessibilidadeDoNavegador, @unchecked Sendable {
    /// nil para um pid: sem acesso.
    var porPid: [Int32: [AbasDaJanela]?] = [:]
    var escolhidas: [String] = []
    var elevadas: [String] = []
    var escolheCom = true
    func janelas(pid: Int32) -> [JanelaDoNavegador]? { nil }
    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool { false }
    func pressionarAba(pid: Int32, janela: Int, titulo: String) -> Bool { escolhidas.append("\(pid)/\(janela)/\(titulo)"); return escolheCom }
    func abasDasJanelas(pid: Int32) -> [AbasDaJanela]? { porPid[pid] ?? nil }
    func elevarJanela(pid: Int32, janela: Int) -> Bool { elevadas.append("\(pid)/\(janela)"); return true }
}

final class Linhas: @unchecked Sendable {
    private let trava = NSLock()
    private var _l: [String] = []
    func add(_ s: String) { trava.lock(); _l.append(s); trava.unlock() }
    var todas: [String] { trava.lock(); defer { trava.unlock() }; return _l }
}

final class WhatsAppAbrirTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)
    let ok = SaidaShell(status: 0, saida: "")
    let negada = SaidaShell(status: 1, saida: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)")
    let fechado = SaidaShell(status: 0, saida: "fechado\n")
    var abrirOk: [(String, SaidaShell)] { [("open -a", ok), ("open 'https", ok)] }

    func origem(_ cfg: ConfigWhatsApp, _ ex: ExecutorFalso, banco: Bool = true) -> OrigemWhatsApp {
        let t = agora
        return OrigemWhatsApp(executor: ex, banco: "/x/ChatStorage.sqlite", config: { cfg }, relogio: { t })
    }

    /// Todos os navegadores fechados, menos o Chrome, que responde `chrome`.
    func shell(chrome: SaidaShell, extra: [(String, SaidaShell)] = []) -> ExecutorFalso {
        let outros = ["com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"].map { ($0, fechado) }
        return ExecutorFalso(extra + [("com.google.Chrome", chrome)] + outros + [("pgrep -x 'Google Chrome'", SaidaShell(status: 0, saida: "4321\n"))])
    }

    func abridor(_ ex: ExecutorFalso, ax: ArvoreDeAbas?, cfg: ConfigWhatsApp = ConfigWhatsApp(origem: "qr", navegador: "Google Chrome"),
                 busca: BuscaNaPagina? = nil, log: Linhas = Linhas()) -> AbridorWhatsApp {
        AbridorWhatsApp(origem: origem(cfg, ex), executor: ex, busca: busca, dormir: { _ in }, ax: ax, registrar: { log.add($0) })
    }

    func barra(_ abas: String...) -> [AbasDaJanela] { [AbasDaJanela(abas: abas, temBarraDeAbas: true)] }

    // MARK: Item 2: Automação negada

    func testAutomacaoNegadaAchaAAbaPelaAcessibilidadeENaoAbreOutra() {
        let ax = ArvoreDeAbas(); ax.porPid[4321] = barra("Gmail", "(3) WhatsApp")
        let ex = shell(chrome: negada, extra: abrirOk)
        let log = Linhas()
        let r = abridor(ex, ax: ax, log: log).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana")
        XCTAssertEqual(r, .aberta(aviso: AbridorWhatsApp.avisoSemNumero), "sem busca injetada, só traz a aba")
        XCTAssertEqual(ax.escolhidas, ["4321/0/(3) WhatsApp"])
        XCTAssertEqual(ax.elevadas, ["4321/0"])
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") }, "nada de aba nova")
        let texto = log.todas.joined(separator: "\n")
        XCTAssertTrue(texto.contains("-1743"), texto)
        XCTAssertTrue(texto.contains("caminho=acessibilidade"), texto)
        XCTAssertFalse(texto.contains("Ana") || texto.contains("5511900000000"), "o log não leva nome nem número")
    }

    func testAutomacaoSemRespostaTambemCaiNaAcessibilidade() {
        let ax = ArvoreDeAbas(); ax.porPid[4321] = barra("WhatsApp")
        let ex = shell(chrome: SaidaShell(status: 124, saida: ""))
        XCTAssertEqual(abridor(ex, ax: ax).abrir(), .aberto)
        XCTAssertEqual(ax.escolhidas, ["4321/0/WhatsApp"])
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") })
    }

    func testSemSaberSeHaAbaAvisaEmVezDeAbrirAbaNova() {
        let ex = shell(chrome: negada, extra: abrirOk)
        let log = Linhas()
        // Sem Acessibilidade (nil) e com Acessibilidade sem acesso (pid nil): os dois não sabem.
        let sem = ArvoreDeAbas(); sem.porPid[4321] = .some(nil)
        for ax in [nil, sem] {
            let r = abridor(ex, ax: ax, log: log).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana")
            XCTAssertEqual(r, .falhou("Libere a Automação do Chrome para o Deck nos Ajustes do Mac (Privacidade e Segurança, Automação)."))
            XCTAssertEqual(abridor(ex, ax: ax).abrir(), .falhou(AbridorWhatsApp.avisoSemAutomacao(NavegadorWeb.chamado("Google Chrome")!)))
        }
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") }, "nunca abre aba nova sem saber")
        XCTAssertTrue(log.todas.contains { $0.contains("não abre outra") })
    }

    func testAcessibilidadeOkSemAbaDoWhatsAppAbreUmaNova() {
        let ax = ArvoreDeAbas(); ax.porPid[4321] = barra("Gmail", "Docs")
        let ex = shell(chrome: negada, extra: abrirOk)
        XCTAssertEqual(abridor(ex, ax: ax).abrir(), .aberto)
        XCTAssertEqual(ex.comandos.last, "open -a 'Google Chrome' 'https://web.whatsapp.com'")
    }

    func testTituloQueSoCitaWhatsAppNaoEAAba() {
        XCTAssertTrue(AbridorWhatsApp.ehTituloDoWhatsApp("(12) WhatsApp"))
        XCTAssertTrue(AbridorWhatsApp.ehTituloDoWhatsApp("WhatsApp"))
        XCTAssertFalse(AbridorWhatsApp.ehTituloDoWhatsApp("Como usar o WhatsApp - Blog"))
        XCTAssertFalse(AbridorWhatsApp.ehTituloDoWhatsApp("WhatsApp Business API docs"))
        XCTAssertEqual(AbridorWhatsApp.codigoDoErro(status: 1, saida: "x. (-1743)\n"), "-1743")
        XCTAssertEqual(AbridorWhatsApp.codigoDoErro(status: 124, saida: ""), "status 124")
    }

    func testAcessibilidadeNaoEscolheAbaNaoDizQueAbriu() {
        let ax = ArvoreDeAbas(); ax.porPid[4321] = barra("WhatsApp"); ax.escolheCom = false
        let ex = shell(chrome: negada, extra: abrirOk)
        XCTAssertEqual(abridor(ex, ax: ax).abrir(), .falhou(AbridorWhatsApp.erroTrazer))
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") })
    }

    func testAutomacaoOkSemAbaAbreNovaEPassaOsPassosPeloLog() {
        let ex = shell(chrome: ok, extra: abrirOk)
        let log = Linhas()
        XCTAssertEqual(abridor(ex, ax: nil, log: log).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: nil))
        XCTAssertEqual(ex.comandos.last, "open -a 'Google Chrome' 'https://web.whatsapp.com/send?phone=5511900000000'")
        let t = log.todas.joined(separator: "\n")
        XCTAssertTrue(t.contains("Automação ok em Google Chrome, abas do WhatsApp=0"), t)
        XCTAssertTrue(t.contains("caminho=aba nova"), t)
        XCTAssertFalse(t.contains("5511900000000"))
    }

    // MARK: Item 3: Abrir no Mac segue o ajuste

    func testAbrirComAppExplicitoAbreOApp() {
        let ex = shell(chrome: ok)
        XCTAssertEqual(AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "app", navegador: nil), ex), executor: ex).abrir(), .naoEWeb)
        XCTAssertTrue(ex.comandos.isEmpty, "app: nem olha o navegador")
    }

    func testAbrirComWebExplicitoTrazAAba() {
        let ex = shell(chrome: SaidaShell(status: 0, saida: "1\t2\t(2) WhatsApp\n"), extra: [("set active tab index", ok)])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "web", navegador: "Google Chrome")).abrir(), .aberto)
        XCTAssertTrue(ex.comandos.last!.contains("set active tab index of window 1 to 2"))
    }

    func testAbrirComQRUsaOWebENaoOApp() {
        let ex = shell(chrome: SaidaShell(status: 0, saida: "1\t2\tWhatsApp\n"), extra: [("set active tab index", ok)])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "qr", navegador: nil)).abrir(), .aberto)
        XCTAssertTrue(ex.comandos.contains { $0.contains("set active tab index") })
        XCTAssertFalse(ex.comandos.contains { $0.contains("open -a 'WhatsApp'") })
    }

    func testAbrirNoAutomaticoSemOAppInstaladoUsaONavegador() {
        // Sem banco do app (stat falha): não está instalado.
        let ex = shell(chrome: ok, extra: [("stat -f %m", SaidaShell(status: 1, saida: "")), ("open -a", ok), ("open 'https", ok)])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "auto", navegador: "Google Chrome")).abrir(), .aberto)
        XCTAssertEqual(ex.comandos.last, "open -a 'Google Chrome' 'https://web.whatsapp.com'")
    }

    func testAbrirNoAutomaticoComBancoMasSemOAppUsaONavegador() {
        let antigo = Int(agora.timeIntervalSince1970 - 86_400 * 10)
        let ex = shell(chrome: ok, extra: [("stat -f %m", SaidaShell(status: 0, saida: "\(antigo)\n")), ("test -d", SaidaShell(status: 1, saida: "")), ("open -a", ok), ("open 'https", ok)])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "auto", navegador: "Google Chrome")).abrir(), .aberto)
    }

    func testAbrirNoAutomaticoComOAppInstaladoEEmUsoAbreOApp() {
        let recente = Int(agora.timeIntervalSince1970 - 60)
        let ex = shell(chrome: ok, extra: [("stat -f %m", SaidaShell(status: 0, saida: "\(recente)\n"))])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "auto", navegador: nil)).abrir(), .naoEWeb)
    }

    func testAbrirNoAutomaticoComBancoParadoEOAppInstaladoAbreOApp() {
        let antigo = Int(agora.timeIntervalSince1970 - 86_400 * 10)
        let ex = shell(chrome: ok, extra: [("stat -f %m", SaidaShell(status: 0, saida: "\(antigo)\n")), ("test -d", ok)])
        XCTAssertEqual(abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "auto", navegador: nil)).abrir(), .naoEWeb)
    }

    func testAbrirNoWebTambemNaoAbreAbaNovaSemSaber() {
        let ex = shell(chrome: negada, extra: abrirOk)
        let r = abridor(ex, ax: nil, cfg: ConfigWhatsApp(origem: "web", navegador: "Google Chrome")).abrir()
        XCTAssertEqual(r, .falhou(AbridorWhatsApp.avisoSemAutomacao(NavegadorWeb.chamado("Google Chrome")!)))
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") })
    }
}
