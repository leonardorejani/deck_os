import XCTest
import CoreImage
@testable import Deck

final class ParearIphoneTestes: XCTestCase {
    func testNomeNaRedeTiraAcentoEEspaco() {
        XCTAssertEqual(ParearIphone.nomeNaRede("MacBook Pro de Exemplo"), "macbook-pro-de-exemplo")
        XCTAssertEqual(ParearIphone.nomeNaRede("  Mac do João!  "), "mac-do-joao")
        XCTAssertEqual(ParearIphone.nomeNaRede("???"), "mac")
    }

    func testEnderecoUsaONomeDoServidorQuandoHa() {
        XCTAssertEqual(ParearIphone.endereco(nomeMac: "MacBook Pro de Exemplo", porta: 4777), "https://macbook-pro-de-exemplo.local:4777")
        XCTAssertEqual(ParearIphone.endereco(nomeMac: "x", porta: 4780, nomeDoServidor: "Leo-Mac.local"), "https://Leo-Mac.local:4780")
        XCTAssertEqual(ParearIphone.endereco(nomeMac: "x", porta: 4777, nomeDoServidor: "Leo-Mac"), "https://Leo-Mac.local:4777")
    }

    func testCodigoEmGrupos() {
        XCTAssertEqual(ParearIphone.codigoEmGrupos("482913"), "482 913")
        XCTAssertEqual(ParearIphone.codigoEmGrupos(""), "")
    }

    /// O QR tem que ser lido de volta com o mesmo texto: é o que a câmera do iPhone faz.
    func testQrLeDeVoltaOEndereco() throws {
        let texto = "https://macbook-pro-de-exemplo.local:4777"
        let img = try XCTUnwrap(ParearIphone.qr(texto))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let achados = detector.features(in: CIImage(cgImage: img)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(achados, [texto])
    }

    @MainActor func testDesconectarTrocaOCodigoDeAcesso() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), iphone: IphonePareado(nome: "iPhone"))
        let antes = m.config.codigoAcesso
        m.desconectarIphone()
        XCTAssertNil(m.iphone)
        XCTAssertNotEqual(m.config.codigoAcesso, antes)
        XCTAssertEqual(m.config.codigoAcesso.count, Config.tamanhoCodigo)
    }

    @MainActor func testCodigoDePareamentoPedeUmNovoAoNucleo() async throws {
        let pareamento = Pareamento(sorteio: { "111111" })
        let c = CodigoDePareamento()
        c.iniciar(pareamento)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(c.codigo, "111111")
        XCTAssertEqual(pareamento.codigoAtivo, "111111")
        c.parar()
        XCTAssertEqual(pareamento.tentar("111111"), .vencido, "fechou a tela: o código deixa de valer")
    }

    func testTextoDaConexao() {
        XCTAssertEqual(TextosDeAjuste.conexao(IphonePareado(nome: "i")), "Safari, pelo Wi-Fi")
        let nove = Calendar.current.date(bySettingHour: 9, minute: 12, second: 0, of: Date())
        XCTAssertEqual(TextosDeAjuste.conexao(IphonePareado(nome: "i", canal: .cabo, desde: nove)), "App nativo, pelo cabo desde 09:12")
    }
}

private struct VerificadorFalso: VerificadorDeAcessos {
    var lista: [AcessoMac]
    func acessos() -> [AcessoLido] {
        OrdemDosAcessos.painel.map { AcessoLido(acesso: $0, situacao: lista.contains($0) ? .recusado : .liberado) }
    }
}

/// O macOS de mentira: cada leitura devolve o que o teste combinou, sem abrir janela nenhuma.
private struct DetectoresFalsos: DetectoresDeAcesso {
    var agenda: SituacaoDoAcesso = .naoPedido
    var bt: SituacaoDoAcesso = .naoPedido
    var acess = false
    var disco = false
    var apps: [String: RespostaDeAutomacao] = [:]
    var instalados: Set<String> = [VerificadorVivo.spotify, "com.apple.Safari", "com.google.Chrome"]
    func calendario() -> SituacaoDoAcesso { agenda }
    func bluetooth() -> SituacaoDoAcesso { bt }
    func acessibilidade() -> Bool { acess }
    func discoTotal() -> Bool { disco }
    func automacao(bundle: String) -> RespostaDeAutomacao { apps[bundle] ?? .fechado }
    func instalado(bundle: String) -> Bool { instalados.contains(bundle) }
}

private func defaultsNovos() -> UserDefaults { UserDefaults(suiteName: "deck-testes-\(UUID().uuidString)")! }

final class AcessosTestes: XCTestCase {
    @MainActor func testAtualizarTrocaAListaESomeQuandoLibera() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        m.atualizarAcessos(VerificadorFalso(lista: [.automacao, .discoTotal]))
        XCTAssertEqual(m.acessosRecusados, [.automacao, .discoTotal])
        XCTAssertEqual(m.acessos.count, OrdemDosAcessos.painel.count)
        m.atualizarAcessos(VerificadorFalso(lista: []))
        XCTAssertTrue(m.acessosRecusados.isEmpty)
        // Sem nada recusado a seção continua na lista, mostrando tudo liberado.
        XCTAssertEqual(m.acessos.filter { $0.situacao == .liberado }.count, OrdemDosAcessos.painel.count)
    }

    func testCadaAcessoAbreAPaginaCerta() {
        XCTAssertEqual(AcessoMac.automacao.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        XCTAssertEqual(AcessoMac.navegadores.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        XCTAssertEqual(AcessoMac.discoTotal.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        XCTAssertEqual(AcessoMac.acessibilidade.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertEqual(AcessoMac.calendarios.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        XCTAssertEqual(AcessoMac.bluetooth.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        XCTAssertEqual(AcessoMac.redeLocal.enderecoDosAjustes.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    }

    func testAcessoNuncaPedidoNaoContaComoRecusado() {
        let defaults = defaultsNovos()
        // Detectores falsos e não liberados: com os de verdade o resultado dependeria do Mac em que o teste roda.
        let v = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos())
        XCTAssertFalse(v.recusado(.acessibilidade))
        XCTAssertFalse(v.recusado(.discoTotal))
        defaults.set(true, forKey: VerificadorVivo.chaveRecusado(.discoTotal))
        XCTAssertTrue(v.recusado(.discoTotal))
    }

    // MARK: Acessos do Mac mostra o estado real de cada acesso (a lista antiga só tinha o que foi recusado)

    private func situacoes(_ v: VerificadorVivo) -> [AcessoMac: SituacaoDoAcesso] {
        Dictionary(uniqueKeysWithValues: v.acessos().map { ($0.acesso, $0.situacao) })
    }

    func testMacRecemInstaladoMostraTudoComoNaoPerguntado() {
        // Antes: nada recusado, então a lista ficava vazia e a seção sumia, mesmo sem nenhum acesso liberado.
        let v = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(apps: [
            VerificadorVivo.spotify: .naoPerguntado, "com.apple.Safari": .naoPerguntado, "com.google.Chrome": .fechado]))
        let s = situacoes(v)
        XCTAssertEqual(s[.calendarios], .naoPedido)
        XCTAssertEqual(s[.automacao], .naoPedido)
        XCTAssertEqual(s[.navegadores], .naoPedido)
        XCTAssertEqual(s[.acessibilidade], .naoPedido)
        XCTAssertEqual(s[.discoTotal], .naoPedido)
        XCTAssertEqual(s[.bluetooth], .naoPedido)
        if case .semComoSaber = s[.redeLocal] {} else { XCTFail("Rede Local sem leitura devia ser semComoSaber, veio \(String(describing: s[.redeLocal]))") }
        XCTAssertTrue(v.recusados().isEmpty)
    }

    func testCalendarioRecusadoEOutrosLiberados() {
        let d = DetectoresFalsos(agenda: .recusado, bt: .liberado, acess: true, disco: true, apps: [VerificadorVivo.spotify: .liberado])
        let v = VerificadorVivo(defaults: defaultsNovos(), detectores: d)
        let s = situacoes(v)
        XCTAssertEqual(s[.calendarios], .recusado)
        XCTAssertEqual(s[.acessibilidade], .liberado)
        XCTAssertEqual(s[.discoTotal], .liberado)
        XCTAssertEqual(s[.automacao], .liberado)
        XCTAssertEqual(s[.bluetooth], .liberado)
        XCTAssertEqual(v.recusados(), [.calendarios])
    }

    func testAcessibilidadeEDiscoViramRecusadosDepoisQueODeckPede() {
        let defaults = defaultsNovos()
        let v = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos())
        XCTAssertEqual(situacoes(v)[.acessibilidade], .naoPedido)
        defaults.set(true, forKey: VerificadorVivo.chavePedido(.acessibilidade))
        defaults.set(true, forKey: VerificadorVivo.chavePedido(.discoTotal))
        XCTAssertEqual(situacoes(v)[.acessibilidade], .recusado)
        XCTAssertEqual(situacoes(v)[.discoTotal], .recusado)
        // Ligou nos Ajustes do Sistema: vira liberado sem perguntar nada.
        let ligado = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos(acess: true, disco: true))
        XCTAssertEqual(situacoes(ligado)[.acessibilidade], .liberado)
        XCTAssertEqual(situacoes(ligado)[.discoTotal], .liberado)
    }

    /// Recusado com o interruptor ligado nos Ajustes do Sistema = lista com a versão velha do app: a linha ensina a tirar e pôr de novo.
    func testRecusadoDeAcessibilidadeEDiscoExplicaOBotaoMenos() {
        let defaults = defaultsNovos()
        let v = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos())
        XCTAssertNil(v.ler(.acessibilidade)?.detalhe, "não perguntado ainda não precisa do aviso")
        defaults.set(true, forKey: VerificadorVivo.chavePedido(.acessibilidade))
        defaults.set(true, forKey: VerificadorVivo.chavePedido(.discoTotal))
        for acesso in [AcessoMac.acessibilidade, .discoTotal] {
            let lido = v.ler(acesso)
            XCTAssertEqual(lido?.situacao, .recusado)
            XCTAssertTrue(lido?.detalhe?.contains("botão menos") ?? false)
            XCTAssertTrue(lido?.detalhe?.contains("adicione de novo") ?? false)
        }
        let ligado = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos(acess: true, disco: true))
        XCTAssertNil(ligado.ler(.acessibilidade)?.detalhe)
        XCTAssertFalse(VerificadorVivo.textoDaListaVelha.contains("—") || VerificadorVivo.textoDaListaVelha.contains(";"))
    }

    func testAutomacaoComOAppFechadoUsaAUltimaLeituraOuAvisa() {
        let defaults = defaultsNovos()
        let aberto = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos(apps: [VerificadorVivo.spotify: .recusado]))
        XCTAssertEqual(situacoes(aberto)[.automacao], .recusado)
        let fechado = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos(apps: [VerificadorVivo.spotify: .fechado]))
        let lido = fechado.ler(.automacao)
        XCTAssertEqual(lido?.situacao, .recusado)
        XCTAssertEqual(lido?.detalhe, "Última leitura, com o Spotify aberto")
        // Nunca foi lido e está fechado: o Deck diz que não dá para conferir, em vez de inventar.
        let virgem = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(apps: [VerificadorVivo.spotify: .fechado]))
        if case .semComoSaber(let texto) = virgem.ler(.automacao)?.situacao { XCTAssertTrue(texto.contains("Abra o Spotify")) } else { XCTFail("devia ser semComoSaber") }
    }

    func testSpotifyNaoInstaladoNaoApareceNaLista() {
        let v = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(instalados: ["com.apple.Safari"]))
        XCTAssertNil(v.ler(.automacao))
        XCTAssertFalse(v.acessos().contains { $0.acesso == .automacao })
    }

    func testNavegadoresJuntamOsInstaladosEDizemQuaisFaltam() {
        let apps = [VerificadorVivo.spotify: RespostaDeAutomacao.liberado, "com.apple.Safari": .liberado, "com.google.Chrome": .recusado]
        let v = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(apps: apps))
        let nav = v.ler(.navegadores)
        XCTAssertEqual(nav?.situacao, .recusado)
        XCTAssertEqual(nav?.detalhe, "Recusado em Google Chrome")
        // Com o Chrome fixado na config, o Safari não conta.
        var fixado = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(apps: ["com.apple.Safari": .recusado, "com.google.Chrome": .liberado]))
        fixado.navegadorFixado = "Google Chrome"
        XCTAssertEqual(fixado.ler(.navegadores)?.situacao, .liberado)
        // Com o WhatsApp lido só pelo app, a linha dos navegadores some.
        var soApp = v
        soApp.origemDoWhatsApp = "app"
        XCTAssertNil(soApp.ler(.navegadores))
    }

    func testNavegadoresFechadosNaoInventamEstado() {
        let v = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos())
        if case .semComoSaber = v.ler(.navegadores)?.situacao {} else { XCTFail("navegadores fechados e nunca lidos devia ser semComoSaber") }
        let metade = VerificadorVivo(defaults: defaultsNovos(), detectores: DetectoresFalsos(apps: ["com.apple.Safari": .liberado]))
        XCTAssertEqual(metade.ler(.navegadores)?.situacao, .liberado)
        XCTAssertEqual(metade.ler(.navegadores)?.detalhe, "Sem como conferir agora: Google Chrome")
    }

    func testRedeLocalLiberadaQuandoOIphoneFalaPeloWifiOuQuandoOPedidoDeuCerto() {
        let defaults = defaultsNovos()
        var v = VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos())
        v.iphonePeloWifi = true
        XCTAssertEqual(v.ler(.redeLocal)?.situacao, .liberado)
        defaults.set("recusado", forKey: VerificadorVivo.chaveUltima("redeLocal"))
        XCTAssertEqual(VerificadorVivo(defaults: defaults, detectores: DetectoresFalsos()).ler(.redeLocal)?.situacao, .recusado)
    }

    func testListaEmPortugues() {
        XCTAssertEqual(VerificadorVivo.lista(["Safari"]), "Safari")
        XCTAssertEqual(VerificadorVivo.lista(["Safari", "Arc"]), "Safari e Arc")
        XCTAssertEqual(VerificadorVivo.lista(["Safari", "Arc", "Brave Browser"]), "Safari, Arc e Brave Browser")
    }

    func testPermitirSoApareceQuandoOMacOSAindaNaoPerguntou() {
        XCTAssertTrue(AcessoLido(acesso: .calendarios, situacao: .naoPedido).podePermitir)
        XCTAssertFalse(AcessoLido(acesso: .calendarios, situacao: .recusado).podePermitir)
        XCTAssertFalse(AcessoLido(acesso: .calendarios, situacao: .liberado).podePermitir)
        XCTAssertFalse(AcessoLido(acesso: .automacao, situacao: .semComoSaber("Abra o Spotify")).podePermitir)
        XCTAssertTrue(AcessoLido(acesso: .redeLocal, situacao: .semComoSaber("Toque em Permitir")).podePermitir)
        // A Rede Local recusada guardada pode ter sido liberada depois nos Ajustes do Sistema: só perguntando de novo se sabe.
        XCTAssertTrue(AcessoLido(acesso: .redeLocal, situacao: .recusado).podePermitir)
    }

    @MainActor func testPermitirPedeAoMacOSERelAsLinhas() async {
        final class Pedidos: PedidosDeAcesso {
            var pedidos: [AcessoMac] = []
            func estado(_ a: AcessoMac) -> EstadoDoAcesso? { nil }
            func pedir(_ a: AcessoMac) async -> EstadoDoAcesso { pedidos.append(a); return .liberado }
            func abrirAjustes(_ a: AcessoMac) {}
        }
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        let pedidos = Pedidos()
        await m.permitirAcesso(.calendarios, pedidos: pedidos, verificador: VerificadorFalso(lista: [.bluetooth]))
        XCTAssertEqual(pedidos.pedidos, [.calendarios])
        XCTAssertEqual(m.acessosRecusados, [.bluetooth])
    }
}

final class EsteMacESobreTestes: XCTestCase {
    func testPreferencias() {
        let defaults = UserDefaults(suiteName: "deck-testes-\(UUID().uuidString)")!
        XCTAssertTrue(PreferenciasDoMac.procurarAtualizacoes(defaults))
        PreferenciasDoMac.definirProcurarAtualizacoes(false, defaults)
        XCTAssertFalse(PreferenciasDoMac.procurarAtualizacoes(defaults))
        XCTAssertEqual(PreferenciasDoMac.nomeLimpo("  Meu Mac "), "Meu Mac")
        XCTAssertEqual(PreferenciasDoMac.nomeLimpo("   "), "Mac")
    }

    func testInformacoesDoApp() {
        let data = DateComponents(calendar: .current, year: 2026, month: 11, day: 10).date!
        let i = InformacoesDoApp(versao: "0.1", compilacao: "1", atualizadoEm: data, macOS: "macOS 26")
        XCTAssertEqual(i.versaoComCompilacao, "0.1 (1)")
        XCTAssertEqual(i.dataPorExtenso, "10 de novembro de 2026")
    }
}

final class LinksDoProjetoTestes: XCTestCase {
    func testEnderecosDoProjetoAberto() {
        XCTAssertEqual(LinksDoProjeto.estrela.absoluteString, "https://github.com/leonardorejani/deck_os", "a estrela é dada na página do repositório")
        XCTAssertEqual(LinksDoProjeto.problema.absoluteString, "https://github.com/leonardorejani/deck_os/issues/new")
        for u in [LinksDoProjeto.estrela, LinksDoProjeto.problema] {
            XCTAssertEqual(u.scheme, "https")
            XCTAssertEqual(u.host, "github.com")
        }
    }

    private func fonte(_ caminho: String) throws -> String {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: raiz.appendingPathComponent(caminho), encoding: .utf8)
    }

    /// Sobre > Projeto aberto: sem a linha Repositório, "Gostou do Deck?" em primeiro e o botão amarelo com estrela.
    func testSobreSemRepositorioEComEstrelaPrimeiro() throws {
        let t = try fonte("mac/App/Ajustes/Sobre.swift")
        XCTAssertFalse(t.contains("\"Repositório\""), "a linha Repositório saiu")
        let gostou = try XCTUnwrap(t.range(of: "titulo: \"Gostou do Deck?\""))
        XCTAssertLessThan(gostou.lowerBound, try XCTUnwrap(t.range(of: "titulo: \"Achou um erro?\"")).lowerBound, "Gostou do Deck? vem antes de Achou um erro?")
        XCTAssertTrue(t.contains("estilo: .estrela, icone: \"star.fill\""))
        XCTAssertFalse(t.contains("estilo: .primario"), "o botão azul saiu")
    }

    /// Pedido de 12/11/2026: o Sobre sem as linhas Mac, iPhone e Licença (a licença fica só no texto do rodapé do grupo) e sem
    /// o título "Sobre o Deck" em cima. "Mostra nenhum iPhone pareado mas estou conectado" vinha da linha do iPhone, que lia só o Wi-Fi.
    func testSobreSemLinhasDeMacIphoneELicencaESemTitulo() throws {
        let t = try fonte("mac/App/Ajustes/Sobre.swift")
        for linha in ["titulo: \"Mac\"", "titulo: \"iPhone\"", "titulo: \"Licença\"", "modelo.iphone"] {
            XCTAssertFalse(t.contains(linha), linha)
        }
        XCTAssertTrue(t.contains("licença MIT"), "a licença fica no texto do grupo")
        let janela = try fonte("mac/App/Ajustes/JanelaAjustes.swift")
        XCTAssertTrue(janela.contains("modelo.secao != .sobre"), "o título do topo não aparece no Sobre")
    }

    /// Pedido de 12/11/2026: WhatsApp e Spotify saíram de Este Mac e foram para Conexões, e o campo do nome ficou largo.
    func testWhatsAppESpotifyEmConexoesENomeDoMacLargo() throws {
        let esteMac = try fonte("mac/App/Ajustes/EsteMac.swift")
        XCTAssertFalse(esteMac.contains("GrupoSpotify(") || esteMac.contains("titulo: \"WhatsApp\""))
        let conexoes = try fonte("mac/App/Ajustes/ConectarIphone.swift")
        XCTAssertTrue(conexoes.contains("GrupoSpotify(") && conexoes.contains("MetodoWhatsApp("))
        XCTAssertGreaterThanOrEqual(Tema.Medida.campoNome, 260)
    }

    /// Os Ajustes do Mac não mostram mais a pasta da configuração (grupo Avançado).
    func testEsteMacSemGrupoAvancado() throws {
        let t = try fonte("mac/App/Ajustes/EsteMac.swift")
        XCTAssertFalse(t.contains("Mostrar no Finder"))
        XCTAssertFalse(t.contains("config.json\""))
        XCTAssertFalse(t.contains("titulo: \"Avançado\""))
    }

    /// O amarelo da estrela tem texto escuro: contraste alto nos dois temas.
    func testEstrelaTemContrasteBom() {
        func luz(_ c: NSColor) -> Double {
            let c = c.usingColorSpace(.sRGB)!
            func f(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(c.redComponent) + 0.7152 * f(c.greenComponent) + 0.0722 * f(c.blueComponent)
        }
        for nome in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: nome)!.performAsCurrentDrawingAppearance {
                let fundo = luz(NSColor(Tema.Cor.estrela)), texto = luz(NSColor(Tema.Cor.estrelaTexto))
                XCTAssertGreaterThan((fundo + 0.05) / (texto + 0.05), 7, "\(nome)")
            }
        }
    }

    /// A nota do Wi-Fi diz que é o PWA e o que ele tem a menos.
    func testNotaDoWifiExplicaOPwa() {
        let n = TextosDeAjuste.notaDoWifi
        for trecho in ["PWA", "Tela de Início", "mesma rede", "cabo", "Bluetooth"] { XCTAssertTrue(n.contains(trecho), trecho) }
        XCTAssertFalse(n.contains("—") || n.contains(";"))
    }

    /// O arquivo LICENSE do repositório existe e é a MIT com o autor certo (o botão "MIT" aponta para ele).
    func testLicencaMITNoRepositorio() throws {
        let raiz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let texto = try String(contentsOf: raiz.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(texto.hasPrefix("MIT License"))
        XCTAssertTrue(texto.contains("Copyright (c) 2026 Leonardo Rejani"))
    }
}

final class AvisosEIphoneTestes: XCTestCase {
    private func defaultsNovos() -> UserDefaults { UserDefaults(suiteName: "deck-testes-\(UUID().uuidString)")! }

    /// "Mostra nenhum iPhone pareado mas estou conectado": o PWA falando pelo Wi-Fi, sem o Mac ter anotado o pareamento, já conta.
    @MainActor func testRespostaDoWifiFazOIphoneAparecerEmTodoLugar() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(m.iphoneAtivo)
        m.wifiAtendeu(caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertEqual(m.iphoneAtivo?.canal, .wifi)
        XCTAssertEqual(TextosDoMenu.sincronia(m.iphoneAtivo, agora: t0), "Sincronizado com o iPhone")
        XCTAssertEqual(TextosDoMenu.estadoIphone(m.iphoneAtivo, agora: t0), "iPhone, pelo Wi-Fi")
        XCTAssertEqual(TextosDoMenu.sincronia(m.iphoneAtivo, agora: t0.addingTimeInterval(120)), "iPhone fora de alcance")
    }

    @MainActor func testCaboTemAVezSobreOWifiNaFonteUnica() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), iphone: IphonePareado(nome: "iPhone", visto: t0),
                          nativo: AppNativo(nome: "iPhone do cabo", canal: .cabo, desde: t0, visto: t0))
        XCTAssertEqual(m.iphoneAtivo?.nome, "iPhone do cabo")
        XCTAssertEqual(m.iphoneAtivo?.canal, .cabo)
        XCTAssertEqual(m.iphoneAtivo?.visto, t0)
    }

    func testAparelhoForaDeAlcanceNaoFingeEstarConectado() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let i = IphonePareado(nome: "iPhone", canal: .wifi, desde: t0, visto: t0)
        XCTAssertEqual(TextosDeAjuste.conexao(i, agora: t0.addingTimeInterval(5)), "Safari, pelo Wi-Fi desde \(hora(t0))")
        XCTAssertEqual(TextosDeAjuste.conexao(i, agora: t0.addingTimeInterval(300)), "Safari, pareado e fora de alcance agora")
        XCTAssertEqual(TextosDoMenu.estadoIphone(i, agora: t0.addingTimeInterval(300)), "iPhone, fora de alcance")
    }

    private func hora(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    @MainActor func testPareouGuardaOIphoneEAvisa() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        XCTAssertNil(m.iphone)
        m.iphonePareou(agora: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(m.iphone?.nome, "iPhone")
        XCTAssertEqual(m.aviso?.texto, "iPhone pareado")
        XCTAssertEqual(TextosDoMenu.sincronia(m.iphone), "Sincronizado com o iPhone")
    }

    func testIphoneLembradoVaiEVoltaEPerdeAoTrocarOCodigo() {
        let d = defaultsNovos()
        let desde = Date(timeIntervalSince1970: 1_800_000_000)
        IphoneLembrado.gravar(IphonePareado(nome: "iPhone", desde: desde), codigo: "AAA", d)
        XCTAssertEqual(IphoneLembrado.ler(d, codigoAtual: "AAA")?.desde, desde)
        XCTAssertNil(IphoneLembrado.ler(d, codigoAtual: "BBB"), "Desconectar troca o código: o registro velho não vale")
        IphoneLembrado.esquecer(d)
        XCTAssertNil(IphoneLembrado.ler(d, codigoAtual: "AAA"))
    }

    @MainActor func testDesconectarAvisaEEsquece() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), iphone: IphonePareado(nome: "iPhone"))
        m.desconectarIphone()
        XCTAssertEqual(m.aviso?.texto, "iPhone desconectado. Ele volta a pedir pareamento")
        XCTAssertFalse(m.aviso?.falha ?? true)
    }

    @MainActor func testAvisoNovoSubstituiOAntigoEFalhaDura4s() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        m.avisar("um")
        let primeiro = m.aviso?.id
        m.avisar("dois", falha: true)
        XCTAssertEqual(m.aviso?.texto, "dois")
        XCTAssertNotEqual(m.aviso?.id, primeiro)
        XCTAssertEqual(Tema.Aviso.segundosFalha, 4)
    }

    @MainActor func testAvisoSomeSozinho() async throws {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        m.avisar("curto")
        XCTAssertNotNil(m.aviso)
        try await Task.sleep(nanoseconds: UInt64((Tema.Aviso.segundos + 0.4) * 1_000_000_000))
        XCTAssertNil(m.aviso)
    }

    @MainActor func testGravarComSucessoMostraSalvo() throws {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        m.gravar { $0.nomeMac = "Outro" }
        XCTAssertTrue(m.salvoAgora)
        XCTAssertEqual(TextosDoMenu.sincronia(nil, salvoAgora: true), "Salvo")
        XCTAssertEqual(TextosDoMenu.sincronia(IphonePareado(nome: "i"), salvoAgora: true), "Salvo. Já está no iPhone")
    }

    @MainActor func testPastaSemPermissaoDeGravacaoMostraOErro() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let arquivo = pasta.appendingPathComponent("config.json")
        let m = ModeloApp(arquivo: arquivo, defaults: defaultsNovos())
        m.gravar { $0.nomeMac = "Primeiro" }
        // Tira a permissão de escrever e tenta de novo: a gravação falha e a pessoa tem que ver.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: pasta.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path) }
        m.gravar { $0.nomeMac = "Segundo" }
        XCTAssertNotNil(m.erro)
        XCTAssertEqual(m.aviso?.texto, m.erro)
        XCTAssertTrue(m.aviso?.falha ?? false)
        XCTAssertEqual(m.config.nomeMac, "Primeiro")
    }

    @MainActor func testTentarDeNovoSoValeComServidorFalhado() {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"), servidor: .falhou("x"))
        m.tentarServidorDeNovo()
        XCTAssertEqual(m.servidor, .falhou("x"), "sem armazém (fotos e testes) não há o que religar")
    }
}
