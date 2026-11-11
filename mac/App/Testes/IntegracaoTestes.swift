import XCTest
import CoreImage
@testable import Deck

private final class RelogioDoTeste: @unchecked Sendable {
    private let trava = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var agora: Date { trava.lock(); defer { trava.unlock() }; return t }
    func avancar(_ s: TimeInterval) { trava.lock(); t = t.addingTimeInterval(s); trava.unlock() }
}

private final class SorteioDoTeste: @unchecked Sendable {
    private let trava = NSLock()
    private var n = 0
    func proximo() -> String { trava.lock(); defer { trava.unlock() }; n += 1; return String(format: "%06d", n * 111_111 % 1_000_000) }
}

private func espera(_ condicao: @MainActor () -> Bool, ate segundos: TimeInterval = 3) async {
    let limite = Date().addingTimeInterval(segundos)
    while !(await condicao()), Date() < limite { try? await Task.sleep(nanoseconds: 20_000_000) }
}

/// Os buracos entre as partes do app (certificado no QR, pareamento aceito, código que se renova,
/// rodízio, porta e barra de menus).
@MainActor
final class IntegracaoTestes: XCTestCase {
    private func pastaTemp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("deck-int-\(UUID().uuidString)") }
    private func defaultsNovos() -> UserDefaults { UserDefaults(suiteName: "deck-int-\(UUID().uuidString)")! }

    private func modelo(config: Config? = nil, nomeDoMac: String = "Mac de teste") throws -> (ModeloApp, URL) {
        let arquivo = pastaTemp().appendingPathComponent("config.json")
        if let config {
            try FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ArmazemConfig(url: arquivo).gravar(config)
        }
        return (ModeloApp(arquivo: arquivo, defaults: defaultsNovos(), nomeDoMac: nomeDoMac), arquivo)
    }

    // MARK: a) QR com código e certificado

    func testQrLevaEnderecoCodigoELinkDoCertificado() throws {
        let texto = ParearIphone.textoDoQr(endereco: "https://mac.local:4777", codigo: "482913")
        XCTAssertEqual(texto, "https://mac.local:4777/#parear=482913&certificado=https://mac.local:4777/ca.crt")
        XCTAssertEqual(ParearIphone.textoDoQr(endereco: "https://mac.local:4777", codigo: ""),
                       "https://mac.local:4777/#certificado=https://mac.local:4777/ca.crt")
        let img = try XCTUnwrap(ParearIphone.qr(texto))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        XCTAssertEqual(detector.features(in: CIImage(cgImage: img)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }, [texto])
    }

    // MARK: b) pareamento aceito chega no modelo

    func testPareamentoAceitoNoNucleoMostraOIphoneNoModelo() async throws {
        let (m, _) = try modelo()
        XCTAssertNil(m.iphone)
        let codigo = m.pareamento.gerar()
        XCTAssertEqual(m.pareamento.tentar(codigo), .aceito)
        await espera { m.iphone != nil }
        XCTAssertEqual(m.iphone?.nome, "iPhone")
        XCTAssertEqual(m.aviso?.texto, "iPhone pareado")
    }

    // MARK: c) o código se renova sozinho e some ao fechar

    func testCodigoRenovaQuandoUsado() async throws {
        let sorteio = SorteioDoTeste()
        let pareamento = Pareamento(sorteio: { sorteio.proximo() })
        let c = CodigoDePareamento()
        c.iniciar(pareamento, intervalo: 0.02)
        await espera { !c.codigo.isEmpty }
        let primeiro = c.codigo
        XCTAssertEqual(pareamento.tentar(primeiro), .aceito)
        await espera { c.codigo != primeiro }
        XCTAssertNotEqual(c.codigo, primeiro, "o código usado não pode continuar na tela")
        XCTAssertEqual(pareamento.codigoAtivo, c.codigo)
        c.parar()
    }

    func testCodigoRenovaQuandoVence() async throws {
        let relogio = RelogioDoTeste()
        let sorteio = SorteioDoTeste()
        let pareamento = Pareamento(agora: { relogio.agora }, sorteio: { sorteio.proximo() })
        let c = CodigoDePareamento()
        c.iniciar(pareamento, intervalo: 0.02)
        await espera { !c.codigo.isEmpty }
        let primeiro = c.codigo
        relogio.avancar(Pareamento.validade + 1)
        await espera { c.codigo != primeiro }
        XCTAssertNotEqual(c.codigo, primeiro)
        XCTAssertEqual(pareamento.tentar(c.codigo), .aceito)
        c.parar()
    }

    func testFecharATelaNaoDeixaCodigoAtivo() async throws {
        let sorteio = SorteioDoTeste()
        let pareamento = Pareamento(sorteio: { sorteio.proximo() })
        let c = CodigoDePareamento()
        c.iniciar(pareamento, intervalo: 0.02)
        await espera { !c.codigo.isEmpty }
        let mostrado = c.codigo
        c.parar()
        XCTAssertNil(pareamento.codigoAtivo)
        XCTAssertEqual(pareamento.tentar(mostrado), .vencido)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(pareamento.codigoAtivo, "parou: o cronômetro não gera outro")
    }

    func testConfiguracaoInicialSoTemCodigoNoPassoDoIphone() async throws {
        let (m, _) = try modelo()
        let a = AssistenteInicial(modelo: m, achadas: [], sugestoes: [], pedidos: nil, intervaloDoCodigo: 0.02)
        XCTAssertNil(m.pareamento.codigoAtivo, "abrir a janela não gera código")
        a.irPara(.layout)
        XCTAssertNil(m.pareamento.codigoAtivo)
        a.irPara(.iphone)
        await espera { m.pareamento.codigoAtivo != nil }
        XCTAssertEqual(m.pareamento.codigoAtivo, a.codigo)
        let usado = a.codigo
        XCTAssertEqual(m.pareamento.tentar(usado), .aceito)
        await espera { a.codigo != usado }
        XCTAssertNotEqual(a.codigo, usado)
        a.irPara(.contas)
        XCTAssertNil(m.pareamento.codigoAtivo, "saiu do passo: sem código")
        a.irPara(.iphone)
        await espera { m.pareamento.codigoAtivo != nil }
        a.fechou()
        XCTAssertNil(m.pareamento.codigoAtivo, "fechou a janela: sem código")
    }

    // MARK: d) rodízio e Desconectar iPhones

    private func configVelha() -> Config {
        var c = Config.padrao(nomeMac: "Mac")
        c.codigoCriadoEm = Int(Date().timeIntervalSince1970) - Int(Rodizio.validade) - 60
        return c
    }

    func testRodizioTrocaOCodigoVencidoSemPedido() throws {
        let c = configVelha()
        let (m, _) = try modelo(config: c)
        m.iphone = IphonePareado(nome: "iPhone")
        IphoneLembrado.gravar(m.iphone!, codigo: c.codigoAcesso, m.defaults)
        XCTAssertEqual(m.config.codigoAcesso, c.codigoAcesso)
        XCTAssertTrue(m.verificarRodizio())
        XCTAssertEqual(IphoneLembrado.ler(m.defaults, codigoAtual: m.config.codigoAcesso)?.nome, "iPhone",
                       "o rodízio não faz o Mac esquecer o iPhone")
        XCTAssertNotEqual(m.config.codigoAcesso, c.codigoAcesso)
        XCTAssertEqual(m.config.codigoAnterior, c.codigoAcesso, "o anterior vale na folga")
        XCTAssertFalse(m.verificarRodizio(), "ainda dentro das 24 h")
    }

    func testCronometroDoRodizioTrocaSozinho() async throws {
        let c = configVelha()
        let (m, _) = try modelo(config: c)
        m.iniciar(comServidor: false, intervaloDoRodizio: 0.03)
        defer { m.encerrar() }
        await espera { m.config.codigoAcesso != c.codigoAcesso }
        XCTAssertNotEqual(m.config.codigoAcesso, c.codigoAcesso)
        XCTAssertEqual(Rodizio.checagem, 300, "no app de verdade: a cada 5 minutos")
    }

    func testDesconectarIphonesRevogaOAtualEOAnterior() throws {
        var c = configVelha()
        c.codigoAnterior = "zzzzzzzzzzzzzzzzzzzz"
        c.anteriorValeAte = Int(Date().timeIntervalSince1970) + 600
        let (m, _) = try modelo(config: c)
        m.iphone = IphonePareado(nome: "iPhone")
        m.desconectarIphones()
        XCTAssertNil(m.iphone)
        XCTAssertNotEqual(m.config.codigoAcesso, c.codigoAcesso)
        XCTAssertNil(m.config.codigoAnterior, "o código anterior também deixa de valer")
        XCTAssertNil(m.config.anteriorValeAte)
        XCTAssertEqual(m.aviso?.texto, "iPhones desconectados. Todos voltam a pedir pareamento")
    }

    // MARK: e) porta ocupada

    func testPortaOcupadaAvisaENaoGravaOutra() throws {
        var c = Config.padrao(nomeMac: "Mac")
        c.porta = 4777
        let (m, arquivo) = try modelo(config: c)
        m.registrarPorta(4779)
        XCTAssertEqual(m.servidor, .ligado(porta: 4779))
        XCTAssertEqual(m.config.porta, 4777, "a porta da config continua a que a pessoa escolheu")
        XCTAssertEqual(try ArmazemConfig(url: arquivo).ler().porta, 4777, "e o disco também")
        XCTAssertEqual(m.avisoDePorta, TextosDoMenu.portaOcupada(preferida: 4777, usada: 4779))
        XCTAssertEqual(TextosDoMenu.portaOcupada(preferida: 4777, usada: 4779), "A porta 4777 está ocupada. O Deck usa a 4779")
        m.registrarPorta(4777)
        XCTAssertNil(m.avisoDePorta)
    }

    // MARK: f) nome do Mac

    func testConfigPadraoUsaONomeDoMacDoSistema() throws {
        let (m, arquivo) = try modelo(nomeDoMac: "Mac da Igreja")
        XCTAssertEqual(m.config.nomeMac, "Mac da Igreja")
        XCTAssertEqual(try ArmazemConfig(url: arquivo).ler().nomeMac, "Mac da Igreja")
        let ex = ExecutorDeTeste(saida: "MacBook Pro de Fulano\n")
        XCTAssertEqual(Ligacao.nomeDoMac(executor: ex), "MacBook Pro de Fulano")
        XCTAssertEqual(ex.comandos, ["scutil --get ComputerName"])
    }

    func testSecaoPelaLinhaDeComando() {
        XCTAssertEqual(SecaoAjustes.daLinhaDeComando(["Deck", "--ajustes=iphone"]), .iphone)
        XCTAssertNil(SecaoAjustes.daLinhaDeComando(["Deck", "--ajustes=nada"]))
        XCTAssertNil(SecaoAjustes.daLinhaDeComando(["Deck"]))
    }

    // MARK: g) barra de menus escondida

    func testItemDaBarraEscondido() {
        typealias J = ItemDaBarra.Janela
        XCTAssertFalse(ItemDaBarra.escondido(janelas: [J(classe: "NSStatusBarWindow", visivel: true, naTela: true)]))
        XCTAssertTrue(ItemDaBarra.escondido(janelas: [J(classe: "NSStatusBarWindow", visivel: true, naTela: false)]),
                      "o macOS tira o item da tela quando a pessoa o desliga")
        XCTAssertTrue(ItemDaBarra.escondido(janelas: [J(classe: "NSStatusBarWindow", visivel: false, naTela: true)]))
        XCTAssertTrue(ItemDaBarra.escondido(janelas: []), "nenhum item: escondido")
        XCTAssertFalse(ItemDaBarra.escondido(janelas: [J(classe: "NSWindow", visivel: true, naTela: true), J(classe: "NSStatusBarWindow", visivel: true, naTela: true)]))
        XCTAssertTrue(ItemDaBarra.escondido(janelas: [J(classe: "NSWindow", visivel: true, naTela: true)]), "janela comum não é o item")
        XCTAssertEqual(ItemDaBarra.urlDosAjustes.scheme, "x-apple.systempreferences")
    }

    func testAppDeBarraNaoEncerraSozinho() {
        XCTAssertFalse(SaidaDoApp.permitir(pedida: false, vemDeEventoDoSistema: false, vemDeAcaoDaPessoa: false),
                       "terminate vindo do SwiftUI porque o macOS escondeu o item: cancela")
        XCTAssertTrue(SaidaDoApp.permitir(pedida: true, vemDeEventoDoSistema: false, vemDeAcaoDaPessoa: false), "Sair do Deck")
        XCTAssertTrue(SaidaDoApp.permitir(pedida: false, vemDeEventoDoSistema: true, vemDeAcaoDaPessoa: false), "desligar, reiniciar, sair da conta")
        XCTAssertTrue(SaidaDoApp.permitir(pedida: false, vemDeEventoDoSistema: false, vemDeAcaoDaPessoa: true), "⌘Q")
    }

    func testReaberturaAbreAJanelaCerta() {
        XCTAssertEqual(Reabertura.destino(configuracaoInicialFeita: true, temJanelaVisivel: false), .ajustes)
        XCTAssertEqual(Reabertura.destino(configuracaoInicialFeita: false, temJanelaVisivel: false), .configuracaoInicial,
                       "primeira vez, sem config: continua indo para a configuração inicial")
        XCTAssertEqual(Reabertura.destino(configuracaoInicialFeita: true, temJanelaVisivel: true), .nenhum, "já tem janela: só traz para a frente")
    }

    /// Ícone escondido: nenhum label da barra aparece, só o delegado recebe o evento do `open -a`.
    @MainActor func testReaberturaChegaSemOLabelDaBarra() async throws {
        var recebido: Bool?
        DeckDelegado.aoReabrir = { recebido = $0 }
        defer { DeckDelegado.aoReabrir = nil }
        let retorno = DeckDelegado().applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(recebido, false, "o delegado repassa a reabertura sem passar pela cena do label")
        XCTAssertFalse(retorno, "o app trata sozinho, o padrão do sistema não faz nada")
    }

    func testAvisoDoIconeEscondidoTemOCaminhoCerto() {
        XCTAssertTrue(ItemDaBarra.tituloDoAviso.contains("escondido"))
        XCTAssertTrue(ItemDaBarra.caminhoDoAviso.contains("Barra de Menus > Permitir na barra de menus"))
        XCTAssertEqual(ItemDaBarra.urlDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
    }

    @MainActor func testModeloNasceComIconeVisivel() throws {
        let (m, _) = try modelo()
        XCTAssertFalse(m.iconeEscondido)
    }

    @MainActor func testAvisoDaBarraSoNaPrimeiraVez() {
        let d = defaultsNovos()
        XCTAssertTrue(ItemDaBarra.deveAvisar(escondido: true, defaults: d))
        XCTAssertFalse(ItemDaBarra.deveAvisar(escondido: true, defaults: d), "já avisou")
        XCTAssertFalse(ItemDaBarra.deveAvisar(escondido: false, defaults: defaultsNovos()))
    }
}

private final class ExecutorDeTeste: Executor, @unchecked Sendable {
    let saida: String
    private(set) var comandos: [String] = []
    init(saida: String) { self.saida = saida }
    func rodar(_ comando: String) -> SaidaShell { comandos.append(comando); return SaidaShell(status: 0, saida: saida) }
}

/// "O aviso de ícone escondido tem que sair quando o ícone aparece" (Leonardo, 11/11/2026, com print: o aviso ficava com o
/// ícone já visível). O app olhava o item uma vez, 3 s depois de abrir, e só de novo na reabertura.
@MainActor
final class AvisoDoIconeSomeTestes: XCTestCase {
    private typealias J = ItemDaBarra.Janela
    private let escondida = [J(classe: "NSStatusBarWindow", visivel: false, naTela: false)]
    private let aparecida = [J(classe: "NSStatusBarWindow", visivel: true, naTela: true)]

    private final class Cena: @unchecked Sendable { var janelas: [J] = []; var contagem = 0 }

    func testAvisoSaiSozinhoQuandoOIconeAparece() async throws {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac de teste"))
        let cena = Cena()
        cena.janelas = escondida
        ItemDaBarra.conferirNaAbertura(modelo: m, abrirAjustes: {}, depoisDe: 0.05, defaults: UserDefaults(suiteName: "deck-\(UUID().uuidString)")!,
                                       vigiarCada: 0.1, janelas: { cena.janelas })
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(m.iconeEscondido, "escondido na abertura: o aviso aparece")
        cena.janelas = aparecida   // a pessoa liberou o ícone em Ajustes do Sistema, sem reabrir o Deck
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(m.iconeEscondido, "o aviso tem que sair sozinho quando o ícone aparece")
    }

    func testReconferirAoAbrirOsAjustesTiraOAvisoNaHora() async throws {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac de teste"))
        m.iconeEscondido = true
        ItemDaBarra.conferir(modelo: m, janelas: { self.aparecida })
        XCTAssertFalse(m.iconeEscondido, "ícone visível ao abrir os Ajustes: o aviso não fica")
        XCTAssertNil(m.vigiaDoIcone, "visível: não precisa vigiar")
    }

    func testVigiaParaQuandoOIconeApareceENaoGiraSemMotivo() async throws {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac de teste"))
        let cena = Cena()
        cena.janelas = escondida
        ItemDaBarra.conferir(modelo: m, vigiarCada: 0.05, janelas: { cena.contagem += 1; return cena.janelas })
        XCTAssertTrue(m.iconeEscondido)
        XCTAssertNotNil(m.vigiaDoIcone)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(m.iconeEscondido, "segue escondido: o aviso fica")
        cena.janelas = aparecida
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(m.iconeEscondido)
        XCTAssertNil(m.vigiaDoIcone, "a vigia termina quando o ícone aparece")
        let depois = cena.contagem
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(cena.contagem, depois, "sem vigia rodando, ninguém olha as janelas")
    }
}
