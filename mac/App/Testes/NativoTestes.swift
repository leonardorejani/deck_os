import XCTest
@testable import Deck

/// Anota o que chega de outra thread.
private final class Registro: @unchecked Sendable {
    private let trava = NSLock()
    private var itens: [String] = []
    func anotar(_ s: String) { trava.lock(); itens.append(s); trava.unlock() }
    var todos: [String] { trava.lock(); defer { trava.unlock() }; return itens }
}

/// O app nativo do iPhone no Mac: pedido de pareamento por Bluetooth, canal em uso, renovação e log.
final class RenovacaoTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func dias(_ n: Double) -> TimeInterval { n * 86_400 }

    func testSemRegistroQuandoOMacNaoSabeDaUltimaRenovacao() {
        XCTAssertEqual(RenovacaoDoApp().estado(agora: t0), .semRegistro)
    }

    func testEmDiaAteOQuintoDiaComAProximaMarcada() {
        let r = RenovacaoDoApp(renovadoEm: t0)
        XCTAssertEqual(r.estado(agora: t0.addingTimeInterval(dias(4.9))), .emDia(proxima: t0.addingTimeInterval(dias(5))))
    }

    func testPassouDaHoraDeRenovarMasAindaTemPrazoTentaDeNovoSozinho() {
        let r = RenovacaoDoApp(renovadoEm: t0)
        XCTAssertEqual(r.estado(agora: t0.addingTimeInterval(dias(5.2))), .tentandoDeNovo(venceEm: t0.addingTimeInterval(dias(7))))
    }

    func testMeioDiaDepoisDaHoraDeRenovarSemTerRenovadoOPrazoAperta() {
        let r = RenovacaoDoApp(renovadoEm: t0)
        XCTAssertEqual(r.estado(agora: t0.addingTimeInterval(dias(6.2))), .apertando(venceEm: t0.addingTimeInterval(dias(7))))
        XCTAssertEqual(r.estado(agora: t0.addingTimeInterval(dias(8))), .apertando(venceEm: t0.addingTimeInterval(dias(7))), "vencido também é apertando")
    }

    func testRegistroSobreviveAoFecharOApp() {
        let defaults = UserDefaults(suiteName: "deck.teste.renovacao.\(UUID().uuidString)")!
        XCTAssertEqual(RenovacaoDoApp.ler(defaults), RenovacaoDoApp())
        let r = RenovacaoDoApp(instaladoEm: t0, versao: "0.1 (1)", renovadoEm: t0.addingTimeInterval(100))
        r.gravar(defaults)
        XCTAssertEqual(RenovacaoDoApp.ler(defaults), r)
        RenovacaoDoApp().gravar(defaults)
        XCTAssertEqual(RenovacaoDoApp.ler(defaults), RenovacaoDoApp(), "gravar vazio apaga")
    }
}

final class TextosDoNativoTestes: XCTestCase {
    private func data(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ mi: Int = 0) -> Date {
        DateComponents(calendar: .current, year: y, month: m, day: d, hour: h, minute: mi).date!
    }

    func testPrazoEmDiasInteirosContandoMeioDiaComoUm() {
        let agora = data(2026, 11, 10, 12)
        XCTAssertEqual(TextosDoNativo.venceEm(data(2026, 11, 12, 12), agora: agora), "O app vence em 2 dias")
        XCTAssertEqual(TextosDoNativo.venceEm(data(2026, 11, 11, 6), agora: agora), "O app vence em 1 dia")
        XCTAssertEqual(TextosDoNativo.venceEm(data(2026, 11, 9), agora: agora), "O app vence hoje", "vencido não conta dia negativo")
    }

    func testLinhaDeRenovacaoPorEstado() {
        let agora = data(2026, 11, 10, 12)
        XCTAssertEqual(TextosDoNativo.renovacao(.semRegistro, agora: agora), "Ainda não renovou")
        XCTAssertEqual(TextosDoNativo.renovacao(.tentandoDeNovo(venceEm: data(2026, 11, 13)), agora: agora), "Tenta de novo sozinha")
        XCTAssertEqual(TextosDoNativo.renovacao(.apertando(venceEm: data(2026, 11, 12, 12)), agora: agora), "Vence em 2 dias")
        let proxima = TextosDoNativo.renovacao(.emDia(proxima: data(2026, 11, 13, 10)), agora: agora)
        XCTAssertEqual(proxima, "próxima em 3 dias, sex 10h")
        XCTAssertEqual(TextosDoNativo.renovacao(.emDia(proxima: data(2026, 11, 13, 10, 30)), agora: agora), "próxima em 3 dias, sex 10h30")
    }

    func testUltimoCanalEAparelho() {
        let visto = data(2026, 11, 10, 9, 12)
        let n = AppNativo(nome: "iPhone Exemplo", canal: .bluetooth, desde: visto, visto: visto)
        XCTAssertEqual(TextosDoNativo.ultimoCanal(n, agora: visto.addingTimeInterval(20)), "Bluetooth, agora")
        XCTAssertEqual(TextosDoNativo.ultimoCanal(n, agora: visto.addingTimeInterval(30)), "Bluetooth, agora")
        XCTAssertEqual(TextosDoNativo.ultimoCanal(n, agora: visto.addingTimeInterval(45)), "Bluetooth, há 1 min", "passou de 30 s: o cabeçalho já diz fora de alcance")
        XCTAssertEqual(TextosDoNativo.ultimoCanal(n, agora: visto.addingTimeInterval(300)), "Bluetooth, há 5 min")
        XCTAssertEqual(TextosDoNativo.ultimoCanal(n, agora: visto.addingTimeInterval(7200)), "Bluetooth, às 09:12")
        var cabo = n; cabo.canal = .cabo
        XCTAssertEqual(TextosDoNativo.ultimoCanal(cabo, agora: visto), "Cabo, agora")
        XCTAssertEqual(TextosDoNativo.aparelhoNativo(n), "App nativo, por Bluetooth desde 09:12")
        XCTAssertEqual(TextosDeAjuste.conexao(IphonePareado(nome: "i", canal: .wifi, desde: visto)), "Safari, pelo Wi-Fi desde 09:12")
    }

    func testInstaladoSoDizADataQuandoSabe() {
        XCTAssertEqual(TextosDoNativo.instalado(RenovacaoDoApp()), "Instalado pelo Xcode")
        XCTAssertEqual(TextosDoNativo.instalado(RenovacaoDoApp(instaladoEm: data(2026, 11, 10))), "Instalado pelo Xcode em 10 de novembro de 2026")
    }
}

final class PonteDeDecisaoTestes: XCTestCase {
    func testPerguntaEsperaAPessoaEDevolveAResposta() async throws {
        let ponte = PonteDeDecisao(limite: 5)
        let vistos = Registro()
        ponte.aoPerguntar = { vistos.anotar("\($0.iphone) \($0.codigo)") }
        for resposta in [true, false] {
            let r = Task.detached { ponte.perguntar(iphone: "iPhone Exemplo", codigo: "483291") }
            try await Task.sleep(nanoseconds: 100_000_000)
            ponte.responder(resposta)
            let valor = await r.value
            XCTAssertEqual(valor, resposta)
        }
        XCTAssertEqual(vistos.todos, ["iPhone Exemplo 483291", "iPhone Exemplo 483291"])
    }

    func testSemRespostaNoPrazoVaiComoRecusar() {
        let ponte = PonteDeDecisao(limite: 0.1)
        let fim = Registro()
        ponte.aoEncerrar = { fim.anotar($0) }
        XCTAssertFalse(ponte.perguntar(iphone: "i", codigo: "111111"))
        XCTAssertEqual(fim.todos, ["111111"], "a tela tira o pedido")
    }

    func testIphoneQueSaiSoltaQuemEspera() async throws {
        let ponte = PonteDeDecisao(limite: 30)
        let r = Task.detached { ponte.perguntar(iphone: "i", codigo: "222222") }
        try await Task.sleep(nanoseconds: 100_000_000)
        ponte.desistir(codigo: "222222")
        let valor = await r.value
        XCTAssertFalse(valor)
    }
}

final class JanelaDePareamentoTestes: XCTestCase {
    private final class Relogio: @unchecked Sendable { var agora = Date(timeIntervalSince1970: 1_800_000_000) }

    func testFechadaAteATelaRenovarEFechaSozinhaDepoisDeSessentaSegundos() {
        let r = Relogio()
        let j = JanelaDePareamento(agora: { r.agora })
        XCTAssertFalse(j.aberta, "sem a tela aberta, ninguém aparece no Mac pedindo para parear")
        j.renovar()
        XCTAssertTrue(j.aberta)
        r.agora.addTimeInterval(59)
        XCTAssertTrue(j.aberta)
        r.agora.addTimeInterval(2)
        XCTAssertFalse(j.aberta, "a tela fechou e parou de renovar: a janela fecha sem aviso de saída")
        j.renovar(); j.fechar()
        XCTAssertFalse(j.aberta)
    }
}

final class LogDoDeckTestes: XCTestCase {
    func testGravaLinhasComHoraENoMaximoUmArquivoVelho() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pasta) }
        let arquivo = pasta.appendingPathComponent("deck.log")
        let log = LogDoDeck(arquivo: arquivo, limite: 200)
        log.escrever("cabo conectado ao iPhone 5")
        let texto = try String(contentsOf: arquivo)
        XCTAssertTrue(texto.hasSuffix(" cabo conectado ao iPhone 5\n"), texto)
        XCTAssertTrue(texto.hasPrefix("20"), "começa com a data ISO")
        for i in 0..<20 { log.escrever("linha \(i) com texto para passar do limite") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: arquivo.appendingPathExtension("1").path), "passou do limite: o velho vira .1")
        XCTAssertLessThan(try Data(contentsOf: arquivo).count, 1000)
        let perm = (try FileManager.default.attributesOfItem(atPath: arquivo.path))[.posixPermissions] as? Int
        XCTAssertEqual(perm, 0o600, "o log é só do dono")
    }
}

@MainActor
final class NativoNoModeloTestes: XCTestCase {
    private func modelo(iphone: IphonePareado? = nil, nativo: AppNativo? = nil, renovacao: RenovacaoDoApp = RenovacaoDoApp()) -> ModeloApp {
        // Um domínio de preferências só do teste: o hospedeiro é o Deck de verdade e `.standard` seria o registro do dono.
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), iphone: iphone, nativo: nativo, renovacao: renovacao,
                          defaults: UserDefaults(suiteName: "deck.teste.modelo.\(UUID().uuidString)")!)
        m.ligarDecisao()
        return m
    }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRotuloDaSessaoDizOCanal() {
        XCTAssertEqual(CanalIphone(rotulo: "usbmux/5"), .cabo)
        XCTAssertEqual(CanalIphone(rotulo: "bluetooth/737A3C86"), .bluetooth)
        XCTAssertNil(CanalIphone(rotulo: "teste"))
    }

    func testPrimeiraRespostaBoaPeloBluetoothMarcaOAppEOCanal() {
        let m = modelo()
        m.nativoAtendeu(rotulo: "bluetooth/AB", caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertEqual(m.nativo, AppNativo(nome: "iPhone", canal: .bluetooth, desde: t0, visto: t0))
        XCTAssertEqual(m.iphoneAtivo?.canal, .bluetooth)
    }

    func testRespostaRecusadaOuDeCanalDesconhecidoNaoMarcaNada() {
        let m = modelo()
        m.nativoAtendeu(rotulo: "bluetooth/AB", caminho: "/api/estado", status: 401, agora: t0)
        m.nativoAtendeu(rotulo: "teste", caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertNil(m.nativo, "quem não provou o código não aparece como pareado")
    }

    func testTrocaDeCanalAtualizaNaHoraEMesmoCanalSoDepoisDeCincoSegundos() {
        let m = modelo()
        m.nativoAtendeu(rotulo: "usbmux/1", caminho: "/api/estado", status: 200, agora: t0)
        m.nativoAtendeu(rotulo: "usbmux/1", caminho: "/api/estado", status: 200, agora: t0.addingTimeInterval(2))
        XCTAssertEqual(m.nativo?.visto, t0, "a tela não é redesenhada a cada pedido")
        m.nativoAtendeu(rotulo: "bluetooth/1", caminho: "/api/estado", status: 200, agora: t0.addingTimeInterval(3))
        XCTAssertEqual(m.nativo?.canal, .bluetooth)
        XCTAssertEqual(m.nativo?.desde, t0, "é o mesmo aparelho: o desde não anda")
    }

    func testPareamentoPeloCaboNaoDeixaUmIphoneDeWifiFalso() {
        let m = modelo()
        m.iphonePareou(agora: t0)
        XCTAssertEqual(m.iphone?.canal, .wifi, "o núcleo só sabe que alguém acertou o código")
        m.nativoAtendeu(rotulo: "usbmux/1", caminho: "/api/parear", status: 200, agora: t0.addingTimeInterval(1))
        XCTAssertNil(m.iphone, "foi o app nativo, pelo cabo")
        XCTAssertEqual(m.nativo?.canal, .cabo)
    }

    func testIphoneDeWifiAntigoNaoSomeQuandoOAppNativoPareia() {
        let antigo = IphonePareado(nome: "iPhone de Exemplo", canal: .wifi, desde: t0.addingTimeInterval(-3600))
        let m = modelo(iphone: antigo)
        m.nativoAtendeu(rotulo: "usbmux/1", caminho: "/api/parear", status: 200, agora: t0)
        XCTAssertEqual(m.iphone, antigo)
        XCTAssertEqual(m.iphoneAtivo?.canal, .cabo, "o app nativo tem a vez no topo do menu")
    }

    func testPedidoPorBluetoothAparecePermitirLibera() async throws {
        let m = modelo()
        let ponte = m.decisao
        let r = Task.detached { ponte.perguntar(iphone: "iPhone Exemplo", codigo: "483291") }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(m.pedidoBluetooth, PedidoDePareamento(iphone: "iPhone Exemplo", codigo: "483291"))
        m.responderPedido(permitir: true)
        let permitido = await r.value
        XCTAssertTrue(permitido)
        XCTAssertNil(m.pedidoBluetooth)
        XCTAssertEqual(m.aviso?.texto, "iPhone pareado. O app já pode abrir o painel")
        m.nativoAtendeu(rotulo: "bluetooth/AB", caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertEqual(m.nativo?.nome, "iPhone Exemplo", "o nome que o iPhone deu ao pedir")
    }

    func testRecusarDevolveFalsoETiraOPedido() async throws {
        let m = modelo()
        let ponte = m.decisao
        let r = Task.detached { ponte.perguntar(iphone: "iPhone Exemplo", codigo: "111111") }
        try await Task.sleep(nanoseconds: 300_000_000)
        m.responderPedido(permitir: false)
        let permitido = await r.value
        XCTAssertFalse(permitido)
        XCTAssertNil(m.pedidoBluetooth)
        XCTAssertEqual(m.aviso?.texto, "Pareamento recusado")
        m.nativoAtendeu(rotulo: "bluetooth/AB", caminho: "/api/estado", status: 401, agora: t0)
        XCTAssertNil(m.nativo)
    }

    func testIphoneQueSaiAntesDeResponderTiraOPedidoDaTela() async throws {
        let m = modelo()
        let ponte = m.decisao
        let r = Task.detached { ponte.perguntar(iphone: "i", codigo: "222222") }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(m.pedidoBluetooth)
        m.decisao.desistir(codigo: "222222")
        _ = await r.value
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(m.pedidoBluetooth)
    }

    func testDesconectarOAppTrocaOCodigoEEsquece() {
        let m = modelo(nativo: AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0))
        let antes = m.config.codigoAcesso
        m.desconectarNativo()
        XCTAssertNil(m.nativo)
        XCTAssertNotEqual(m.config.codigoAcesso, antes, "o app antigo para de ler e volta a pedir pareamento")
    }

    func testRenovarAgoraSemARenovacaoDaFase8DizAVerdadeENaoMarcaRenovado() {
        let m = modelo(nativo: AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0))
        m.renovarAppNativo()
        XCTAssertEqual(m.aviso?.texto, TextosDoNativo.semRenovador)
        XCTAssertTrue(m.aviso?.falha == true)
        XCTAssertNil(m.renovacao.renovadoEm, "não finge que renovou")
    }

    func testRenovarAgoraComRenovadorRegistraSoQuandoDaCerto() async throws {
        let m = modelo(nativo: AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0))
        m.renovador = { .falhou(.iphoneForaDoCabo) }
        m.renovarAppNativo()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(m.renovacao.renovadoEm)
        XCTAssertTrue(m.aviso?.falha == true)
        m.renovador = { .renovado(em: Date(), venceEm: nil) }
        m.renovarAppNativo()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(m.renovacao.renovadoEm)
        XCTAssertEqual(m.aviso?.texto, "App renovado. Vale por mais 7 dias")
    }

    func testSeloELinhaDoMenuSoComOPrazoApertandoEOAppPareado() {
        let velho = RenovacaoDoApp(renovadoEm: Date().addingTimeInterval(-6.5 * 86_400))
        let n = AppNativo(nome: "iPhone", canal: .cabo, desde: t0, visto: t0)
        XCTAssertTrue(modelo(nativo: n, renovacao: velho).renovacaoApertando)
        XCTAssertFalse(modelo(renovacao: velho).renovacaoApertando, "sem app pareado não há o que avisar")
        XCTAssertFalse(modelo(nativo: n, renovacao: RenovacaoDoApp(renovadoEm: Date())).renovacaoApertando)
        XCTAssertFalse(modelo(nativo: n).renovacaoApertando, "sem registro o Mac não inventa prazo")
    }
}
