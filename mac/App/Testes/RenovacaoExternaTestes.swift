import XCTest
@testable import Deck

/// A cópia do app que o SideStore instalou: o Deck não renova, não avisa à toa e mostra o vencimento real.
@MainActor
final class RenovacaoExternaTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var agora = Date(timeIntervalSince1970: 1_800_000_000)
    private var tentativas = 0
    private let semArquivo = URL(fileURLWithPath: "/nao/existe/renovacao.plist")

    private func modelo(renovadoEm: Date?) -> ModeloApp {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), renovacao: RenovacaoDoApp(renovadoEm: renovadoEm),
                          defaults: UserDefaults(suiteName: "deck.teste.externa.\(UUID().uuidString)")!)
        m.relogio = { [unowned self] in self.agora }
        m.renovador = { [unowned self] in self.tentativas += 1; return .renovado(em: self.agora, venceEm: nil) }
        m.sondarIphone = { .liberado }
        m.nativo = AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0)
        return m
    }
    private func apos(_ dias: Double) { agora = t0.addingTimeInterval(dias * 86_400) }
    private func externa(vence dias: Double) -> InstalacaoDoApp {
        InstalacaoDoApp(versao: "1.2 (1)", bundleId: MotorDeRenovacao.idDoAppDoIphone + ".OUTRA", equipe: "EQUIPEX", venceEm: t0.addingTimeInterval(dias * 86_400))
    }

    func testExternaNaoRenovaPeloXcodeNemNaAgendaNemNoBotao() async {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(externa(vence: 6))
        XCTAssertTrue(m.origemDaInstalacao.externa)
        apos(6)
        await m.conferirRenovacao(arquivo: semArquivo)
        await m.executarRenovacao(manual: true)
        m.renovarAppNativo()
        XCTAssertEqual(tentativas, 0, "instalar por cima trocaria a cópia do SideStore")
    }

    func testExternaComVencimentoLongeNaoMostraCartaoNemSelo() {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(externa(vence: 6))
        apos(5.8)
        XCTAssertNil(m.cartaoDaRenovacao(agora: agora), "pela conta do Deck já estaria apertando, mas o prazo real está longe")
        XCTAssertFalse(m.renovacaoApertando)
    }

    func testExternaComVencimentoPertoPedeParaAbrirOSideStore() {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(externa(vence: 6))
        apos(4.5)
        XCTAssertEqual(m.cartaoDaRenovacao(agora: agora), .externa(venceEm: t0.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(m.renovacaoApertando)
        XCTAssertEqual(TextosDoNativo.alertaDaInstalacaoExterna(t0.addingTimeInterval(6 * 86_400), agora: agora), "O app vence em 2 dias. Abra o SideStore no iPhone para renovar.")
        apos(5.2)
        XCTAssertEqual(TextosDoNativo.alertaDaInstalacaoExterna(t0.addingTimeInterval(6 * 86_400), agora: agora), "O app vence em 1 dia. Abra o SideStore no iPhone para renovar.")
        apos(6.5)
        XCTAssertEqual(TextosDoNativo.alertaDaInstalacaoExterna(t0.addingTimeInterval(6 * 86_400), agora: agora), "O app venceu. Abra o SideStore no iPhone para renovar.")
    }

    func testInstaladoPeloDeckSegueIgualDeHoje() async {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(InstalacaoDoApp(versao: "1.2 (1)", bundleId: MotorDeRenovacao.idDoAppDoIphone, equipe: nil, venceEm: t0.addingTimeInterval(7 * 86_400)))
        XCTAssertEqual(m.origemDaInstalacao, .deck)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1, "a renovação automática do Deck continua rodando")
        XCTAssertNil(m.renovacao.venceReal, "renovou: o vencimento velho sai até o iPhone informar o novo")
    }

    func testVencimentoRealMandaNoPrazoDoCartaoDoDeck() {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(InstalacaoDoApp(versao: "1.2 (1)", bundleId: MotorDeRenovacao.idDoAppDoIphone, equipe: nil, venceEm: t0.addingTimeInterval(6 * 86_400)))
        apos(5.6)
        XCTAssertEqual(m.cartaoDaRenovacao(agora: agora), .falhou(venceEm: t0.addingTimeInterval(6 * 86_400)), "vence em 1 dia pelo perfil, não em 7 dias contados da instalação")
    }

    func testSemInformacaoDoIphoneNadaMudaEMostraDeckPresumido() async {
        let m = modelo(renovadoEm: t0)
        XCTAssertEqual(m.origemDaInstalacao, .desconhecida)
        apos(5.1)
        await m.conferirRenovacao(arquivo: semArquivo)
        XCTAssertEqual(tentativas, 1)
    }

    func testTextosDaLinhaInstaladoPor() {
        XCTAssertEqual(TextosDoNativo.instaladoPor(.deck), "Deck")
        XCTAssertEqual(TextosDoNativo.instaladoPor(.externa(.outroPacote)), "outro app (SideStore)")
    }

    func testInformacaoSobreviveAoReinicioDoDeck() {
        let m = modelo(renovadoEm: t0)
        m.instalacaoInformada(externa(vence: 6))
        let lido = RenovacaoDoApp.ler(m.defaults)
        XCTAssertEqual(lido.venceReal, t0.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(lido.versao, "1.2 (1)")
        XCTAssertEqual(lido.bundleIdReal, MotorDeRenovacao.idDoAppDoIphone + ".OUTRA")
    }
}
