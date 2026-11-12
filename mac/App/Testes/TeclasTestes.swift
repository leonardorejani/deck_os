import XCTest
@testable import Deck

private func t(_ id: String, _ nome: String = "", tipo: String = "app", valor: String = "") -> Tecla {
    Tecla(id: id, nome: nome.isEmpty ? id : nome, tipo: tipo, valor: valor, estado: nil, icone: nil)
}

final class LogicaTeclasTestes: XCTestCase {
    func testPorPaginaCincoNaAENoveNaB() {
        XCTAssertEqual(LogicaTeclas.porPagina(comp: "a"), 5)
        XCTAssertEqual(LogicaTeclas.porPagina(comp: "b"), 9)
    }

    func testPaginasSempreTemUmaEAbasSoComMaisDeUma() {
        XCTAssertEqual(LogicaTeclas.paginas([], porPagina: 5).count, 1)
        let sete = (1...7).map { t("t\($0)") }
        let p = LogicaTeclas.paginas(sete, porPagina: 5)
        XCTAssertEqual(p.map(\.count), [5, 2])
        XCTAssertEqual(LogicaTeclas.paginas(Array(sete.prefix(5)), porPagina: 5).count, 1)
    }

    func testMoverPoeAArrastadaNoLugarDaOutra() {
        let l = [t("a"), t("b"), t("c"), t("d")]
        XCTAssertEqual(LogicaTeclas.mover(l, id: "a", para: "c").map(\.id), ["b", "c", "a", "d"])
        XCTAssertEqual(LogicaTeclas.mover(l, id: "d", para: "b").map(\.id), ["a", "d", "b", "c"])
        XCTAssertEqual(LogicaTeclas.mover(l, id: "a", para: "a"), l)
        XCTAssertEqual(LogicaTeclas.mover(l, id: "x", para: "a"), l)
    }

    func testSoltarNaAbaLevaParaOFimDaquelaPagina() {
        let l = (1...7).map { t("t\($0)") }
        // t1 vai para a página 2 (índice 1): depois de remover, entra na posição 9 limitada ao fim
        XCTAssertEqual(LogicaTeclas.soltarNaPagina(l, id: "t1", pagina: 1, porPagina: 5).map(\.id), ["t2", "t3", "t4", "t5", "t6", "t7", "t1"])
        // t7 vai para a página 1: fica no fim da primeira (posição 4)
        XCTAssertEqual(LogicaTeclas.soltarNaPagina(l, id: "t7", pagina: 0, porPagina: 5).map(\.id), ["t1", "t2", "t3", "t4", "t7", "t5", "t6"])
        XCTAssertEqual(LogicaTeclas.paginaDe(indice: 6, porPagina: 5), 1)
    }

    func testBuscaSemAcentoNemMaiuscula() {
        let apps = ["Música", "Calculadora", "Prévia"]
        XCTAssertEqual(LogicaTeclas.filtrar(apps, busca: "musica") { $0 }, ["Música"])
        XCTAssertEqual(LogicaTeclas.filtrar(apps, busca: "PREVIA") { $0 }, ["Prévia"])
        XCTAssertEqual(LogicaTeclas.filtrar(apps, busca: "  ") { $0 }, apps)
        XCTAssertEqual(LogicaTeclas.filtrar(apps, busca: "zzz") { $0 }, [])
    }

    func testNomeAcompanhaAEscolhaAteOUsuarioDarOProprio() {
        XCTAssertEqual(LogicaTeclas.nomeAposEscolher(atual: "Nova tecla", escolhido: "Safari"), "Safari")
        XCTAssertEqual(LogicaTeclas.nomeAposEscolher(atual: "", escolhido: "Safari"), "Safari")
        XCTAssertEqual(LogicaTeclas.nomeAposEscolher(atual: "Meu navegador", escolhido: "Safari"), "Meu navegador")
        XCTAssertEqual(LogicaTeclas.nomeAposEscolher(atual: "Mail", escolhido: "Safari", nomesDeApps: ["Mail"]), "Safari")
    }

    func testEscolhidaAposExcluir() {
        let l = [t("a"), t("b")]
        XCTAssertEqual(LogicaTeclas.escolhidaApos(excluir: 0, restantes: l), "a")
        XCTAssertEqual(LogicaTeclas.escolhidaApos(excluir: 5, restantes: l), "b")
        XCTAssertNil(LogicaTeclas.escolhidaApos(excluir: 0, restantes: []))
    }

    func testIdNovoNaoRepete() {
        let agora = Date(timeIntervalSince1970: 1)
        XCTAssertEqual(LogicaTeclas.idNovo(prefixo: "t", existentes: ["t1000"], agora: agora), "t1001")
    }
}

final class CombinacaoTestes: XCTestCase {
    func testGravaCombinacaoNaOrdemDoNucleo() {
        // código 40 = k
        XCTAssertEqual(CombinacaoEmTexto.interpretar(codigo: 40, controle: true, opcao: true, comando: true, shift: false), .gravou("ctrl+opt+cmd+k"))
        XCTAssertEqual(CombinacaoEmTexto.interpretar(codigo: 21, controle: false, opcao: false, comando: true, shift: true), .gravou("cmd+shift+4"))
        // o texto gravado volta como a mesma combinação no núcleo
        XCTAssertNotNil(Teclas.ler("ctrl+opt+cmd+k"))
    }

    func testEscCancelaESoModificadorEspera() {
        XCTAssertEqual(CombinacaoEmTexto.interpretar(codigo: 53, controle: true, opcao: false, comando: false, shift: false), .cancelou)
        XCTAssertEqual(CombinacaoEmTexto.interpretar(codigo: 55, controle: false, opcao: false, comando: true, shift: false), .ignorar)
    }

    func testExigeTeclaDeControle() {
        XCTAssertEqual(CombinacaoEmTexto.interpretar(codigo: 40, controle: false, opcao: false, comando: false, shift: false), .faltaControle)
    }

    func testNomesEspeciaisSaemEmIngles() {
        XCTAssertEqual(CombinacaoEmTexto.nome(doCodigo: 36), "return")
        XCTAssertEqual(CombinacaoEmTexto.nome(doCodigo: 123), "left")
        XCTAssertEqual(CombinacaoEmTexto.nome(doCodigo: 49), "space")
        // todo código que o núcleo conhece volta para um nome que o próprio núcleo entende
        for (_, codigo) in Teclas.codigos {
            let n = CombinacaoEmTexto.nome(doCodigo: codigo)
            XCTAssertNotNil(n.flatMap { Teclas.ler("cmd+" + $0) }, "código \(codigo)")
        }
    }

    func testPecasDoGravador() {
        XCTAssertEqual(CombinacaoEmTexto.pecas("ctrl+opt+cmd+k"), ["⌃ control", "⌥ option", "⌘ command", "K"])
    }
}

final class LeitorDeAppsTestes: XCTestCase {
    func testLeAppsDasPastasDeA_aZ() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        for n in ["Zoom.app", "Arc.app", "leia-me.txt"] {
            try FileManager.default.createDirectory(at: raiz.appendingPathComponent(n), withIntermediateDirectories: true)
        }
        let apps = LeitorDeApps.ler(pastas: [raiz.path], extras: [])
        XCTAssertEqual(apps.map(\.valor), ["Arc", "Zoom"])
        XCTAssertEqual(apps.first?.caminhoDoIcone, raiz.appendingPathComponent("Arc.app").path)
    }

    func testMaisUsadosCompletaComOsDeSempre() {
        let apps = ["Safari", "Notes", "Zoom"].map { AppDoMac(nome: $0, valor: $0, caminhoDoIcone: nil) }
        let r = LeitorDeApps.maisUsados(apps) { $0.valor == "Zoom" ? 9 : 0 }
        XCTAssertEqual(r.map(\.valor), ["Zoom", "Safari", "Notes"])
    }

    func testListaDeAtalhosIgnoraLinhaVazia() {
        XCTAssertEqual(LeitorDeApps.atalhos(daSaida: "Hora do Dia\n\n Modo Ensaio \n"), ["Hora do Dia", "Modo Ensaio"])
    }
}

@MainActor
final class ModeloTeclasTestes: XCTestCase {
    private func modelo(comp: String = "a") -> ModeloApp {
        var c = Config.padrao(nomeMac: "Mac")
        c.comp = comp
        c.perfis = [Perfil(id: "trabalho", nome: "Trabalho", teclas: [t("a", valor: "Safari"), t("b", valor: "Notes"), t("c", tipo: "comando", valor: "ls")]),
                    Perfil(id: "ensaio", nome: "Ensaio", teclas: [t("e1")])]
        c.perfilAtivo = "trabalho"
        return ModeloApp(config: c)
    }

    private func tela(_ m: ModeloApp, apps: [AppDoMac] = []) -> ModeloTeclas {
        ModeloTeclas(modelo: m, catalogo: CatalogoDeApps(apps: apps, maisUsados: apps, atalhos: []),
                     pedirAcessibilidade: { }, executar: { _ in nil })
    }

    func testComecaNoPerfilAtivoComAPrimeiraTecla() {
        let tl = tela(modelo())
        XCTAssertEqual(tl.editando, "trabalho")
        XCTAssertEqual(tl.sel, "a")
    }

    func testEditarOutroPerfilNaoMudaOQueOIphoneMostra() {
        let m = modelo()
        let tl = tela(m)
        tl.editarPerfil("ensaio")
        XCTAssertEqual(tl.teclas.map(\.id), ["e1"])
        XCTAssertEqual(m.config.perfilAtivo, "trabalho")
        XCTAssertFalse(tl.iphoneMostraEstePerfil)
        tl.usarNoIphone()
        XCTAssertEqual(m.config.perfilAtivo, "ensaio")
    }

    func testNovaTeclaVaiParaOFimEAbreAUltimaPagina() {
        let m = modelo()
        let tl = tela(m)
        tl.novaTecla(); tl.novaTecla(); tl.novaTecla()
        XCTAssertEqual(tl.teclas.count, 6)
        XCTAssertEqual(tl.teclas.last?.nome, "Nova tecla")
        XCTAssertEqual(tl.sel, tl.teclas.last?.id)
        XCTAssertEqual(tl.pagina, 1)
        XCTAssertEqual(m.config.perfis[0].teclas.count, 3, "sem ação, a tecla nova ainda não vai para a config")
    }

    func testExcluirTeclaEDesfazer() {
        let m = modelo()
        let tl = tela(m)
        tl.escolher("b")
        tl.excluirTecla()
        XCTAssertEqual(m.config.perfis[0].teclas.map(\.id), ["a", "c"])
        XCTAssertEqual(tl.sel, "c")
        XCTAssertTrue(tl.podeDesfazer)
        tl.desfazerAgora()
        XCTAssertEqual(m.config.perfis[0].teclas.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(tl.sel, "b")
        XCTAssertFalse(tl.podeDesfazer)
    }

    func testExcluirPerfilAtivoEDesfazer() {
        let m = modelo()
        let tl = tela(m)
        tl.excluirPerfil()
        XCTAssertEqual(m.config.perfis.map(\.id), ["ensaio"])
        XCTAssertEqual(m.config.perfilAtivo, "ensaio")
        tl.desfazerAgora()
        XCTAssertEqual(m.config.perfis.map(\.id), ["trabalho", "ensaio"])
        XCTAssertEqual(m.config.perfilAtivo, "trabalho")
        XCTAssertEqual(tl.editando, "trabalho")
    }

    func testNaoExcluiOUnicoPerfil() {
        var c = Config.padrao(nomeMac: "Mac")
        c.perfis = [Perfil(id: "p", nome: "P", teclas: [])]
        c.perfilAtivo = "p"
        let tl = tela(ModeloApp(config: c))
        tl.excluirPerfil()
        XCTAssertEqual(tl.perfis.count, 1)
    }

    func testNovoPerfilFicaEmEdicaoSemMudarOIphone() {
        let m = modelo()
        let tl = tela(m)
        tl.novoPerfil()
        XCTAssertEqual(m.config.perfis.count, 3)
        XCTAssertEqual(tl.perfil.nome, "Novo perfil")
        XCTAssertEqual(m.config.perfilAtivo, "trabalho")
        XCTAssertNil(tl.sel)
    }

    func testArrastarReordenaESoltarNaAbaTrocaDePagina() {
        let m = modelo()
        let tl = tela(m)
        tl.novaTecla(); tl.novaTecla(); tl.novaTecla()   // 6 teclas, 2 páginas
        tl.arrastar("a")
        tl.moverArrastada(para: "c")
        XCTAssertEqual(m.config.perfis[0].teclas.prefix(3).map(\.id), ["b", "c", "a"])
        tl.soltarNaAba(1)
        XCTAssertEqual(m.config.perfis[0].teclas.last?.id, "a")
        XCTAssertEqual(tl.pagina, 1)
        XCTAssertEqual(tl.sel, "a")
        XCTAssertNil(tl.arrastando)
    }

    func testTrocarOTipoLimpaOValorNaTelaEEscolherAppPoeNomeEIcone() {
        let m = modelo()
        let tl = tela(m, apps: [AppDoMac(nome: "Calendário", valor: "Calendar", caminhoDoIcone: nil)])
        tl.escolherTipo(.comando)
        XCTAssertEqual(tl.tecla?.tipo, "comando")
        XCTAssertEqual(tl.tecla?.valor, "")
        XCTAssertEqual(m.config.perfis[0].teclas[0].tipo, "app", "sem comando escrito, a config segue como estava")
        tl.escolherTipo(.app)
        tl.escolherApp(AppDoMac(nome: "Calendário", valor: "Calendar", caminhoDoIcone: nil))
        let k = m.config.perfis[0].teclas[0]
        XCTAssertEqual(k.valor, "Calendar")
        XCTAssertEqual(k.icone, "Calendar")
        XCTAssertEqual(k.nome, "a", "nome próprio não é trocado")
    }

    func testTeclasDeFabricaEntramNaListaESaoDeFabrica() {
        XCTAssertEqual(TeclasDeFabrica.todas.map(\.nome), ["Controles do Mac", "Google Meet (navegador)"])
        XCTAssertEqual(AjusteDeApp.de("Calendar"), .agenda)
        XCTAssertEqual(AjusteDeApp.de("Activity Monitor"), .monitor)
        XCTAssertEqual(AjusteDeApp.de("Controles"), .controles)
        XCTAssertEqual(AjusteDeApp.de("Google Meet"), .meet)
        XCTAssertNil(AjusteDeApp.de("Safari"))
    }

    func testEscolherOMeetDaListaDaNomeCurtoIconeEAcaoLimpaAoTrocarDeApp() {
        let m = modelo()
        let tl = tela(m)
        tl.escolherApp(TeclasDeFabrica.meet)
        tl.escolherAcao(AcaoDeApp(id: "reuniao-microfone", valor: nil))
        var k = m.config.perfis[0].teclas[0]
        XCTAssertEqual(k.valor, "Google Meet")
        XCTAssertEqual(k.icone, "svg:video")
        XCTAssertEqual(k.acao?.id, "reuniao-microfone")
        XCTAssertNil(Config.validar(m.config))
        tl.escolherApp(AppDoMac(nome: "Safari", valor: "Safari", caminhoDoIcone: nil))
        k = m.config.perfis[0].teclas[0]
        XCTAssertNil(k.acao, "a ação era do Meet")
        XCTAssertEqual(k.icone, "Safari")
    }

    func testLigaEDesligaDaTeclaDeComando() {
        let m = modelo()
        let tl = tela(m)
        tl.escolherTipo(.comando)
        tl.escolherComando("foco jogo")
        tl.definirLigaEDesliga(true)
        tl.escolherDesligar("foco trabalho")
        tl.escolherConferir("checar-foco")
        var k = m.config.perfis[0].teclas[0]
        XCTAssertEqual([k.valor, k.desligar, k.estado], ["foco jogo", "foco trabalho", "checar-foco"])
        XCTAssertNil(Config.validar(m.config))
        tl.escolherConferir("  ")
        XCTAssertNil(m.config.perfis[0].teclas[0].estado, "campo vazio apaga o comando de conferir")
        tl.definirLigaEDesliga(false)
        k = m.config.perfis[0].teclas[0]
        XCTAssertNil(k.desligar)
        XCTAssertEqual(k.valor, "foco jogo", "o comando de ligar continua sendo o da tecla")
    }

    func testTrocarOTipoApagaOQueSoValiaNoTipoAntigo() {
        let m = modelo()
        let tl = tela(m)
        tl.escolherTipo(.comando)
        tl.escolherComando("x")
        tl.definirLigaEDesliga(true)
        tl.escolherDesligar("y")
        tl.escolherTipo(.app)
        XCTAssertNil(tl.tecla?.desligar)
        tl.escolherApp(TeclasDeFabrica.meet)
        tl.escolherAcao(AcaoDeApp(id: "reuniao-camera", valor: nil))
        tl.escolherTipo(.comando)
        XCTAssertNil(tl.tecla?.acao)
    }

    func testEscolherTipoTecladoPedeAcessibilidadeUmaVez() {
        var pedidos = 0
        let tl = ModeloTeclas(modelo: modelo(), pedirAcessibilidade: { pedidos += 1 }, executar: { _ in nil })
        tl.escolherTipo(.tecla)
        tl.escolherTipo(.tecla)
        XCTAssertEqual(pedidos, 1)
    }

    func testComandoProntoPreencheNomeEValor() {
        let m = modelo()
        let tl = tela(m)
        tl.novaTecla()
        tl.escolherTipo(.comando)
        tl.escolherComando("pmset displaysleepnow", nome: "Apagar tela")
        let k = m.config.perfis[0].teclas.last
        XCTAssertEqual(k?.nome, "Apagar tela")
        XCTAssertEqual(k?.valor, "pmset displaysleepnow")
    }

    func testIconeEAtalhoEGravacaoGravamNaConfig() {
        let m = modelo()
        let tl = tela(m)
        tl.escolherTipo(.atalho)
        tl.escolherAtalho("Modo Ensaio")
        tl.escolherIcone("svg:raio")
        tl.escolherCombinacao("cmd+shift+4")
        let k = m.config.perfis[0].teclas[0]
        XCTAssertEqual(k.tipo, "atalho")
        XCTAssertEqual(k.icone, "svg:raio")
        XCTAssertEqual(k.valor, "cmd+shift+4")
    }

    func testConferirVoltaParaOPerfilAtivoSeOEditadoSumiu() {
        let m = modelo()
        let tl = tela(m)
        tl.editarPerfil("ensaio")
        m.gravar { $0.perfis.removeAll { $0.id == "ensaio" } }
        tl.conferir()
        XCTAssertEqual(tl.editando, "trabalho")
        XCTAssertEqual(tl.sel, "a")
    }

    func testTesteDoComandoMostraOErroDoNucleo() async {
        let tl = ModeloTeclas(modelo: modelo(), pedirAcessibilidade: { }, executar: { _ in "O comando falhou: nada" })
        tl.escolher("c")
        tl.testarComando()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(tl.saidaDoTeste, "O comando falhou: nada")
    }
}


/// Com o armazém de verdade (a validação do núcleo recusa tecla sem ação): é o que o app faz.
@MainActor
final class ModeloTeclasComDiscoTestes: XCTestCase {
    private var pasta: URL!
    private var arquivo: URL { pasta.appendingPathComponent("config.json") }

    override func setUpWithError() throws {
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-teclas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        var c = Config.padrao(nomeMac: "Mac")
        c.perfis = [Perfil(id: "trabalho", nome: "Trabalho", teclas: [
            t("whatsapp", "WhatsApp", valor: "WhatsApp"), t("apagar", "Apagar tela", tipo: "comando", valor: "pmset displaysleepnow"),
            t("a", valor: "Safari"), t("b", valor: "Notes")])]
        c.perfilAtivo = "trabalho"
        try ArmazemConfig(url: arquivo).gravar(c)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: pasta) }

    private func abrir(mouse: @escaping () -> Bool = { false }) -> (ModeloApp, ModeloTeclas) {
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teclas-\(UUID().uuidString)")!)
        let tl = ModeloTeclas(modelo: m, catalogo: CatalogoDeApps(apps: [], maisUsados: [], atalhos: []),
                              pedirAcessibilidade: { }, executar: { _ in nil }, mouseApertado: mouse)
        return (m, tl)
    }

    private func noDisco() throws -> Config { try ArmazemConfig(url: arquivo).ler() }

    func testNovaTeclaAparecePeloTempoQueNaoTemAcaoEEntraNaConfigComOApp() throws {
        let (m, tl) = abrir()
        tl.novaTecla()
        XCTAssertEqual(tl.teclas.count, 5)
        XCTAssertNotNil(tl.tecla, "o editor segue aberto na tecla nova")
        XCTAssertEqual(tl.tecla?.nome, "Nova tecla")
        XCTAssertNil(m.erro)
        XCTAssertEqual(try noDisco().perfis[0].teclas.count, 4)
        tl.escolherApp(AppDoMac(nome: "Safari", valor: "Safari", caminhoDoIcone: nil))
        XCTAssertEqual(try noDisco().perfis[0].teclas.map(\.id).count, 5)
        XCTAssertEqual(try noDisco().perfis[0].teclas.last?.valor, "Safari")
        XCTAssertNil(m.erro)
    }

    func testTrocarOTipoFuncionaEGravaQuandoTemAcao() throws {
        let (m, tl) = abrir()
        tl.escolher("whatsapp")
        tl.escolherTipo(.comando)
        XCTAssertEqual(tl.tecla?.tipo, "comando", "o cartão escolhido muda na hora")
        XCTAssertEqual(try noDisco().perfis[0].teclas[0].tipo, "app")
        tl.escolherComando("say oi")
        XCTAssertEqual(try noDisco().perfis[0].teclas[0].tipo, "comando")
        XCTAssertEqual(try noDisco().perfis[0].teclas[0].valor, "say oi")
        tl.escolher("apagar")
        tl.escolherTipo(.atalho)
        XCTAssertEqual(tl.tecla?.tipo, "atalho")
        tl.escolherAtalho("Modo Ensaio")
        XCTAssertEqual(try noDisco().perfis[0].teclas[1].tipo, "atalho")
        XCTAssertNil(m.erro)
    }

    func testPedeAcessibilidadeSoQuandoATrocaDeTipoAconteceu() {
        var pedidos = 0
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teclas-\(UUID().uuidString)")!)
        let tl = ModeloTeclas(modelo: m, pedirAcessibilidade: { pedidos += 1 }, executar: { _ in nil })
        tl.escolher("whatsapp")
        tl.escolherTipo(.tecla)
        XCTAssertEqual(tl.tecla?.tipo, "tecla")
        XCTAssertEqual(pedidos, 1)
    }

    func testNomeVazioNaoApagaONomeGravado() throws {
        let (_, tl) = abrir()
        tl.escolher("apagar")
        tl.renomear("")
        tl.renomear("   ")
        XCTAssertEqual(tl.tecla?.nome, "Apagar tela")
        tl.renomearPerfil("")
        XCTAssertEqual(tl.perfil.nome, "Trabalho")
        tl.renomear("Dormir tela")
        XCTAssertEqual(try noDisco().perfis[0].teclas[1].nome, "Dormir tela")
    }

    func testComandoApagadoFicaSemAcaoNaTelaEAConfigGuardaOAnterior() throws {
        let (_, tl) = abrir()
        tl.escolher("apagar")
        tl.escolherComando("")
        XCTAssertEqual(tl.tecla?.valor, "", "a caixa fica vazia enquanto a pessoa escreve")
        XCTAssertEqual(try noDisco().perfis[0].teclas[1].valor, "pmset displaysleepnow")
        tl.escolherComando("open ~/Downloads")
        XCTAssertEqual(try noDisco().perfis[0].teclas[1].valor, "open ~/Downloads")
    }

    func testGravacaoRecusadaMostraOMotivoEMantemATela() throws {
        let (m, tl) = abrir()
        tl.escolher("whatsapp")
        tl.escolherTipo(.tecla)
        tl.escolherCombinacao("isso nao e combinacao")
        XCTAssertEqual(m.erro, "A combinação da tecla \"WhatsApp\" não foi reconhecida: isso nao e combinacao")
        XCTAssertEqual(tl.tecla?.valor, "isso nao e combinacao", "a tela mostra o que a pessoa fez")
        XCTAssertEqual(try noDisco().perfis[0].teclas[0].tipo, "app")
        tl.escolherCombinacao("cmd+shift+4")
        XCTAssertNil(m.erro)
        XCTAssertEqual(try noDisco().perfis[0].teclas[0].valor, "cmd+shift+4")
    }

    func testExcluirTeclaNovaEDesfazer() throws {
        let (_, tl) = abrir()
        tl.novaTecla()
        let id = tl.sel!
        tl.excluirTecla()
        XCTAssertEqual(tl.teclas.count, 4)
        XCTAssertEqual(try noDisco().perfis[0].teclas.count, 4)
        tl.desfazerAgora()
        XCTAssertEqual(tl.teclas.count, 5)
        XCTAssertEqual(tl.sel, id)
    }

    func testArrastoCanceladoFicaLivreQuandoOMouseSobe() async {
        var apertado = true
        let (_, tl) = abrir(mouse: { apertado })
        tl.arrastar("a")
        XCTAssertEqual(tl.arrastando, "a")
        apertado = false
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertNil(tl.arrastando, "soltou fora de tudo: a tecla não fica apagada")
    }

    func testReordenarNaoGravaTeclaSemAcao() throws {
        let (m, tl) = abrir()
        tl.novaTecla()
        tl.arrastar("whatsapp")
        tl.moverArrastada(para: "b")
        XCTAssertEqual(try noDisco().perfis[0].teclas.map(\.id), ["apagar", "a", "b", "whatsapp"])
        XCTAssertNil(m.erro)
        XCTAssertEqual(tl.teclas.count, 5)
    }
}
