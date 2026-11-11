import XCTest
@testable import Deck

/// Os pedidos de acesso de mentira: nenhum abre janela do macOS.
@MainActor
private final class PedidosFalsos: PedidosDeAcesso {
    var estados: [AcessoMac: EstadoDoAcesso] = [:]
    var respostas: [AcessoMac: EstadoDoAcesso] = [:]
    var aberturas: [AcessoMac] = []
    func estado(_ a: AcessoMac) -> EstadoDoAcesso? { estados[a] }
    func pedir(_ a: AcessoMac) async -> EstadoDoAcesso { respostas[a] ?? .liberado }
    func abrirAjustes(_ a: AcessoMac) { aberturas.append(a) }
}

@MainActor
final class InicialTestes: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "deck.testes.inicial.\(UUID().uuidString)")
    }

    private func modelo(teclas: [Tecla]? = nil, iphone: Bool = false) -> ModeloApp {
        var c = Config.padrao(nomeMac: "MacBook Pro")
        if let teclas { c.perfis[0].teclas = teclas }
        return ModeloApp(config: c, iphone: iphone ? IphonePareado(nome: "iPhone") : nil, configuracaoInicialFeita: false)
    }

    private func assistente(_ m: ModeloApp, pedidos: PedidosDeAcesso? = nil, acoes: AcoesDaInicial = AcoesDaInicial()) -> AssistenteInicial {
        AssistenteInicial(modelo: m, achadas: [ContaAchada(id: "claude-leo", servico: "Claude", conta: "leo", perfil: "leo", semana: 61, renova: nil),
                                               ContaAchada(id: "codex", servico: "Codex", conta: "principal", semana: nil, renova: nil)],
                          sugestoes: SugestaoDeTecla.todas, pedidos: pedidos ?? PedidosFalsos(), acoes: acoes,
                          codigo: "123456", endereco: "https://macbook-pro.local:4777", defaults: defaults)
    }

    // MARK: refazer sem perder

    func testRefazerNaoReligaOsBlocosQueAPessoaDesligou() {
        var c = Config.padrao(nomeMac: "MacBook Pro")
        c.blocos = Blocos(spotify: false, agenda: true, whatsapp: false, sessoes: true, uso: false)
        let m = ModeloApp(config: c, configuracaoInicialFeita: true)
        m.aplicarConfiguracaoInicial(teclas: [], contas: [], comp: "a", recusados: [], defaults: defaults)
        XCTAssertEqual(m.config.blocos, Blocos(spotify: false, agenda: true, whatsapp: false, sessoes: true, uso: false))
    }

    // MARK: passos

    func testSetePassosNaOrdemDoPrototipo() {
        XCTAssertEqual(PassoInicial.allCases, [.boas, .iphone, .layout, .contas, .teclas, .acessos, .pronto])
    }

    func testBotaoDeCadaPasso() {
        let a = assistente(modelo(iphone: true))
        XCTAssertEqual(a.textoDoBotao, "Começar")
        a.avancar()
        XCTAssertEqual(a.textoDoBotao, "Continuar")
        a.irPara(.pronto)
        XCTAssertEqual(a.textoDoBotao, "Concluir")
    }

    func testSemIphoneOPassoNaoAvancaMasDaParaFazerDepois() {
        let a = assistente(modelo())
        a.irPara(.iphone)
        XCTAssertFalse(a.podeAvancar)
        XCTAssertTrue(a.podePular)
        a.avancar()
        XCTAssertEqual(a.passo, .iphone)
        a.pular()
        XCTAssertEqual(a.passo, .layout)
    }

    func testComIphoneConectadoAvancaSemPular() {
        let a = assistente(modelo(iphone: true))
        a.irPara(.iphone)
        XCTAssertTrue(a.podeAvancar)
        XCTAssertFalse(a.podePular)
        a.avancar()
        XCTAssertEqual(a.passo, .layout)
    }

    func testVoltarNaoPassaDoPrimeiro() {
        let a = assistente(modelo())
        a.voltar()
        XCTAssertEqual(a.passo, .boas)
        a.irPara(.contas)
        a.voltar()
        XCTAssertEqual(a.passo, .layout)
    }

    func testNenhumPassoAlemDoIphoneEObrigatorio() {
        let a = assistente(modelo())
        for p in PassoInicial.allCases where p != .iphone {
            a.irPara(p)
            XCTAssertTrue(a.podeAvancar, "\(p)")
        }
    }

    // MARK: escolhas

    func testPartidaMarcaAsQuatroTeclasEAsContasAchadas() {
        let a = assistente(modelo())
        XCTAssertEqual(a.teclasMarcadas, ["whatsapp", "agenda", "spotify", "apagar"])
        XCTAssertEqual(a.contasMarcadas, ["claude-leo", "codex"])
    }

    func testContaConectadaEntraMarcada() {
        let a = assistente(modelo())
        a.alternarConta("codex")
        XCTAssertFalse(a.contasMarcadas.contains("codex"))
        a.contaConectada(ContaAchada(id: "claude-igreja", servico: "Claude", conta: "igreja", perfil: "igreja", semana: nil, renova: nil))
        XCTAssertTrue(a.contasMarcadas.contains("claude-igreja"))
        XCTAssertEqual(a.achadas.count, 3)
    }

    func testCincoSugestoesPorLinhaCabemEmOitoTeclas() {
        XCTAssertEqual(SugestaoDeTecla.todas.count, 8)
        XCTAssertEqual(Set(SugestaoDeTecla.todas.map(\.id)).count, 8)
    }

    // MARK: acessos

    func testPermitirGuardaOQueOMacRespondeEOrdemDosNomesDoMacOS() async {
        let p = PedidosFalsos()
        p.respostas[.automacao] = .recusado
        let a = assistente(modelo(), pedidos: p)
        XCTAssertEqual(OrdemDosAcessos.todos.map(\.nome), ["Calendários", "Automação", "Acesso Total ao Disco", "Acessibilidade"])
        await a.permitir(.calendarios)
        await a.permitir(.automacao)
        XCTAssertEqual(a.estado(.calendarios), .liberado)
        XCTAssertEqual(a.estado(.automacao), .recusado)
        XCTAssertEqual(a.estado(.discoTotal), .naoPedido)
    }

    func testRecusadoVoltaALiberadoQuandoAPessoaLigaNosAjustesDoSistema() async {
        let p = PedidosFalsos()
        p.respostas[.acessibilidade] = .recusado
        let a = assistente(modelo(), pedidos: p)
        await a.permitir(.acessibilidade)
        XCTAssertEqual(a.estado(.acessibilidade), .recusado)
        p.estados[.acessibilidade] = .liberado
        a.reler()
        XCTAssertEqual(a.estado(.acessibilidade), .liberado)
    }

    func testAbrirAjustesDoSistemaVaiNaPaginaDoAcesso() {
        let p = PedidosFalsos()
        let a = assistente(modelo(), pedidos: p)
        a.abrirAjustesDoSistema(.discoTotal)
        XCTAssertEqual(p.aberturas, [.discoTotal])
        XCTAssertEqual(PedidosDoMac.painel(.discoTotal), "Privacy_AllFiles")
        XCTAssertEqual(PedidosDoMac.painel(.acessibilidade), "Privacy_Accessibility")
    }

    // MARK: concluir

    func testConcluirPrimeiraVezTrocaAsTeclasDeFabricaPelasEscolhidas() async {
        let m = modelo()
        var fechou = false, abriuMenu = false
        var acoes = AcoesDaInicial()
        acoes.fechar = { fechou = true }
        acoes.abrirMenuDaBarra = { abriuMenu = true }
        let p = PedidosFalsos()
        p.respostas[.automacao] = .recusado
        let a = assistente(m, pedidos: p, acoes: acoes)
        a.alternarTecla("agenda")
        a.comp = "b"
        await a.permitir(.automacao)
        a.concluir()
        let teclas = m.config.perfis[0].teclas
        XCTAssertEqual(teclas.map(\.nome), ["WhatsApp", "Spotify", "Apagar tela"])
        XCTAssertEqual(m.config.comp, "b")
        XCTAssertEqual(m.config.contas.map(\.id), ["claude-leo", "codex"])
        XCTAssertEqual(m.acessosRecusados, [.automacao])
        XCTAssertTrue(m.configuracaoInicialFeita)
        XCTAssertEqual(defaults.object(forKey: "configuracaoInicialFeita") as? Bool, true)
        XCTAssertTrue(fechou)
        XCTAssertTrue(abriuMenu)
    }

    func testRefazerNaoApagaTeclasDaPessoaESoAcrescentaAsQueFaltam() {
        let minhas = [Tecla(id: "x", nome: "Minha", tipo: "comando", valor: "say oi", estado: nil, icone: "svg:raio"),
                      Tecla(id: "whatsapp", nome: "Zap", tipo: "app", valor: "WhatsApp", estado: nil, icone: "WhatsApp")]
        let m = modelo(teclas: minhas)
        let a = assistente(m)
        a.concluir()
        let teclas = m.config.perfis[0].teclas
        XCTAssertEqual(teclas.prefix(2).map(\.id), ["x", "whatsapp"])
        XCTAssertEqual(teclas.filter { $0.valor == "WhatsApp" }.count, 1)
        XCTAssertEqual(Set(teclas.map(\.id)).count, teclas.count)
        XCTAssertTrue(teclas.contains { $0.valor == "Spotify" })
    }

    func testConcluirDeixaConfigValida() {
        let m = modelo()
        assistente(m).concluir()
        XCTAssertNil(Config.validar(m.config))
    }

    func testSemIphoneOPassoProntoFalaParaConectarDepois() {
        XCTAssertFalse(assistente(modelo()).iphoneConectado)
        XCTAssertTrue(assistente(modelo(iphone: true)).iphoneConectado)
    }

    // MARK: pareamento

    func testCodigoEmGruposEEndereco() {
        XCTAssertEqual(EnderecoDoMac.codigoEmGrupos("123456"), "123 456")
        XCTAssertEqual(EnderecoDoMac.apelido("MacBook Pro de Exemplo"), "macbook-pro-de-exemplo.local")
        XCTAssertEqual(EnderecoDoMac.apelido("Mac do João"), "mac-do-joao.local")
        XCTAssertEqual(EnderecoDoMac.url(nomeMac: "x", porta: 4780, hostLocal: "leo.local"), "https://leo.local:4780")
    }

    func testQrDeVerdade() {
        XCTAssertNotNil(DesenhoDoQr.imagem("https://macbook-pro.local:4777"))
    }

    @MainActor func testCodigoSoNasceNoPassoDoIphone() {
        let m = modelo()
        let a = AssistenteInicial(modelo: m, achadas: [], sugestoes: [], pedidos: PedidosFalsos(), endereco: "https://x.local:4777", defaults: defaults)
        XCTAssertTrue(a.codigo.isEmpty, "abrir a janela não sorteia código")
        XCTAssertNil(m.pareamento.codigoAtivo)
        a.irPara(.iphone)
        XCTAssertEqual(a.codigo.count, 6)
        XCTAssertEqual(m.pareamento.codigoAtivo, a.codigo)
        a.fechou()
        XCTAssertNil(m.pareamento.codigoAtivo)
    }

    // MARK: contas e datas

    func testRenovaEmComoNoPrototipo() {
        let cal = Calendar(identifier: .gregorian)
        let agora = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        func em(_ dias: Int, _ h: Int = 9) -> Date { cal.date(byAdding: .day, value: dias, to: cal.date(bySettingHour: h, minute: 0, second: 0, of: agora)!)! }
        XCTAssertEqual(RenovaEm.texto(em(0, 14), agora: agora, calendario: cal), "hoje às 14h")
        XCTAssertEqual(RenovaEm.texto(em(1), agora: agora, calendario: cal), "amanhã")
        XCTAssertEqual(RenovaEm.texto(em(3), agora: agora, calendario: cal), "em 3 dias")
        // 10/11/2026 é terça: "seg 10h" cai daqui a 6 dias, "ter 9h" (já passou hoje) daqui a 7.
        XCTAssertEqual(RenovaEm.texto(RenovaEm.proxima("seg 10h", agora: agora, calendario: cal)!, agora: agora, calendario: cal), "em 6 dias")
        XCTAssertEqual(RenovaEm.texto(RenovaEm.proxima("ter 9h", agora: agora, calendario: cal)!, agora: agora, calendario: cal), "em 7 dias")
    }

    func testDetalheDaConta() {
        let c = ContaAchada(id: "a", servico: "Claude", conta: "leo", semana: 61, renova: nil)
        XCTAssertEqual(c.titulo, "Claude Code, conta leo")
        XCTAssertEqual(c.detalhe(), "61% da semana usado")
        XCTAssertEqual(ContaAchada(id: "b", servico: "Codex", conta: "x", semana: nil, renova: nil).detalhe(), "Uso da semana ainda sem medição")
    }

    func testAcharContasLeOsPerfisMedidosDoClaude() throws {
        let casa = FileManager.default.temporaryDirectory.appendingPathComponent("deck-inicial-\(UUID().uuidString)")
        let pasta = casa.appendingPathComponent(".config/claude-account")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let json = #"{"measured_at":"2026-11-10T12:00:00Z","profiles":{"leo":{"util_7d":61,"reset_7d":1794500000},"igreja":{"util_7d":4,"reset_7d":1794500000}}}"#
        try json.write(to: pasta.appendingPathComponent("measure.json"), atomically: true, encoding: .utf8)
        let achadas = ContasDeste.achar(casa: casa, agora: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(achadas.map(\.id), ["claude-igreja", "claude-leo"])
        XCTAssertEqual(achadas.last?.semana, 61)
        XCTAssertEqual(achadas.last?.perfil, "leo")
        try? FileManager.default.removeItem(at: casa)
    }

    func testSemNadaNoMacNaoAchaConta() {
        let vazio = FileManager.default.temporaryDirectory.appendingPathComponent("deck-vazio-\(UUID().uuidString)")
        XCTAssertTrue(ContasDeste.achar(casa: vazio).isEmpty)
    }

    func testTextoBalanceadoNaoAumentaALargura() {
        let max: CGFloat = 400
        let w = MedirTexto.balanceada("Relógio, música, agenda, mensagens e teclas que controlam o Mac, numa tela só ao lado do teclado.",
                                      tamanho: 13, peso: .regular, kern: 0, maxima: max)
        XCTAssertLessThanOrEqual(w, max)
        XCTAssertGreaterThan(w, max / 2 - 20)
    }
}
