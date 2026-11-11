import XCTest
@testable import Deck

/// A agenda da renovação no modelo, com relógio e renovador de mentira (nada de Xcode nem de iPhone).
@MainActor
final class RenovacaoAgendaTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var agora = Date(timeIntervalSince1970: 1_800_000_000)
    private var tentativas = 0
    private var situacao = SituacaoDoIphone.semIphone
    private var resposta: ResultadoDaRenovacao = .falhou(.iphoneForaDoCabo)
    private let semArquivo = URL(fileURLWithPath: "/nao/existe/renovacao.plist")

    private func modelo(renovadoEm: Date?) -> ModeloApp {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), renovacao: RenovacaoDoApp(renovadoEm: renovadoEm),
                          defaults: UserDefaults(suiteName: "deck.teste.agenda.\(UUID().uuidString)")!)
        m.relogio = { [unowned self] in self.agora }
        m.renovador = { [unowned self] in self.tentativas += 1; return self.resposta }
        m.sondarIphone = { [unowned self] in self.situacao }
        return m
    }
    private func apos(_ dias: Double) { agora = t0.addingTimeInterval(dias * 86_400) }

    func testAntesDeCincoDiasNaoMexeEmNada() async {
        let m = modelo(renovadoEm: t0)
        apos(4.9)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 0)
    }

    func testFalhaGuardaOMotivoEmPortuguesEOAvisoDaTelaFicaQuieto() async {
        let m = modelo(renovadoEm: t0)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1)
        XCTAssertEqual(m.renovacao.motivo, "O iPhone não está ao alcance do Mac (nem no cabo, nem no mesmo Wi-Fi)")
        XCTAssertEqual(m.renovacao.tentouEm, agora)
        XCTAssertNil(m.aviso, "a agenda não pisca aviso na janela")
        XCTAssertEqual(m.renovacao.renovadoEm, t0, "falhar não finge que renovou")
    }

    func testRenovacaoDaAgendaQueDaCertoNaoPiscaAvisoNemAbreAJanela() async {
        let m = modelo(renovadoEm: t0)
        resposta = .renovado(em: t0.addingTimeInterval(5.1 * 86_400), venceEm: nil)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1)
        XCTAssertNil(m.aviso, "renovou sozinho: ninguém precisa saber")
        XCTAssertFalse(m.renovacaoApertando)
    }

    func testSoAvisaQuandoOPrazoApertaEAExplicacaoDasCondicoesCitaOWifi() async {
        let m = modelo(renovadoEm: t0)
        m.nativo = AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0)
        apos(5.3)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertNil(m.aviso)
        XCTAssertFalse(m.renovacaoApertando, "falhou, mas ainda dentro das 12 h: só tenta de novo")
        apos(5.6)
        XCTAssertTrue(m.renovacaoApertando, "passou das 12 h sem renovar: agora sim")
        let t = TextosDoNativo.renovacaoCondicoes
        XCTAssertTrue(t.contains("Wi-Fi") && t.contains("Xcode") && t.contains("bloqueado"))
        XCTAssertFalse(t.contains("—") || t.contains(";"))
    }

    func testSoTentaDeNovoQuandoOIphoneVoltaAoCaboEDesbloqueia() async {
        let m = modelo(renovadoEm: t0)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1)
        for s in [SituacaoDoIphone.semIphone, .bloqueado] {
            situacao = s
            apos(5.2)
            await m.conferirRenovacao(arquivo: semArquivo)
        }
        XCTAssertEqual(tentativas, 1, "fora do cabo ou bloqueado: só olha, não compila")
        situacao = .liberado
        resposta = .renovado(em: t0.addingTimeInterval(5.3 * 86_400), venceEm: nil)
        apos(5.3)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 2)
        XCTAssertEqual(m.renovacao.renovadoEm, agora)
        XCTAssertNil(m.renovacao.motivo, "deu certo: o motivo antigo some")
        XCTAssertNil(m.falhaDaRenovacao)
    }

    func testAposRenovarOProximoPrazoContaDeNovoDoZero() async {
        let m = modelo(renovadoEm: t0)
        resposta = .renovado(em: t0.addingTimeInterval(5.1 * 86_400), venceEm: nil)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        apos(9)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1)
        XCTAssertEqual(m.estadoDaRenovacao, .emDia(proxima: m.renovacao.renovadoEm!.addingTimeInterval(5 * 86_400)))
    }

    func testPrazoApertaSoDozeHorasDepoisDaHoraDeRenovar() async {
        let m = modelo(renovadoEm: t0)
        m.nativo = AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0)
        apos(5.4)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertFalse(m.renovacaoApertando, "5,4 dias: ainda dentro das 12 h")
        apos(5.6)
        XCTAssertTrue(m.renovacaoApertando, "passou de 12 h sem renovar: cartão amarelo, selo e linha no menu")
    }

    func testBotaoEAgendaNaoRodamJuntos() async {
        let m = modelo(renovadoEm: t0)
        m.renovando = true
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 0)
    }

    func testBotaoComFalhaMostraOMotivoNoAviso() async {
        let m = modelo(renovadoEm: t0)
        resposta = .falhou(.iphoneBloqueado)
        await m.executarRenovacao(manual: true)
        XCTAssertEqual(m.aviso?.texto, "Não consegui renovar: O iPhone está bloqueado. Tento de novo sozinho")
        XCTAssertTrue(m.aviso?.falha == true)
    }

    func testInstalacaoFeitaPeloScriptEEntradaComoUltimaRenovacao() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("renovacao-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let feita = t0.addingTimeInterval(-3 * 86_400)
        try PropertyListSerialization.data(fromPropertyList: ["pasta": "/Users/x/deck", "instaladoEm": feita], format: .xml, options: 0).write(to: url)
        let m = modelo(renovadoEm: nil)
        m.lerInstalacao(url)
        XCTAssertEqual(m.pastaDoProjeto, "/Users/x/deck")
        XCTAssertEqual(m.renovacao.renovadoEm, feita)
        let velha = t0.addingTimeInterval(-9 * 86_400)
        try PropertyListSerialization.data(fromPropertyList: ["pasta": "/Users/x/deck", "instaladoEm": velha], format: .xml, options: 0).write(to: url)
        m.lerInstalacao(url)
        XCTAssertEqual(m.renovacao.renovadoEm, feita, "arquivo mais velho não volta o relógio")
    }
}
