import XCTest
@testable import Nucleo

final class FontesWhatsAppWebTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)
    let banco = "/Users/x/Library/Group Containers/g/ChatStorage.sqlite"
    let fechado = SaidaShell(status: 0, saida: "fechado\n")

    func origem(_ cfg: ConfigWhatsApp, _ ex: ExecutorFalso) -> OrigemWhatsApp {
        let t = agora
        return OrigemWhatsApp(executor: ex, banco: banco, config: { cfg }, relogio: { t })
    }

    // O Executor falso reconhece cada navegador pelo id do pacote, que passa intacto pelas aspas do vigia.
    // Quem traz a aba para a frente também leva o id: a resposta dele vai primeiro na lista.
    /// Banco mexido há `s` segundos, como o `stat -f %m` imprime (um número por arquivo que existe).
    func stat(haSegundos s: Double) -> (String, SaidaShell) {
        ("stat -f %m", SaidaShell(status: 0, saida: "\(Int(agora.timeIntervalSince1970 - s))\n"))
    }
    let semBanco = ("stat -f %m", SaidaShell(status: 1, saida: ""))

    func chromeComAba(_ titulo: String, janela: Int = 1, aba: Int = 2) -> (String, SaidaShell) {
        ("com.google.Chrome", SaidaShell(status: 0, saida: "\(janela)\t\(aba)\t\(titulo)\n"))
    }
    let outrosFechados: [(String, SaidaShell)] = ["com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"].map { ($0, SaidaShell(status: 0, saida: "fechado\n")) }

    // MARK: Título da aba

    func testLeONumeroDeNaoLidasDoTituloDaAba() {
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: "(23) WhatsApp"), 23)
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: "(1) WhatsApp Web"), 1)
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: "(99+) WhatsApp"), 99)
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: "WhatsApp"), 0)
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: ""), 0)
        // Número no meio do título não é contagem.
        XCTAssertEqual(WhatsAppWeb.naoLidas(titulo: "WhatsApp (3)"), 0)
    }

    func testLeAsAbasDaSaidaDoAppleScriptEIgnoraLinhaEstranha() {
        let chrome = NavegadorWeb.chamado("Google Chrome")!
        let abas = WhatsAppWeb.lerAbas("1\t3\t(5) WhatsApp\nlixo\n2\t1\tWhatsApp\n0\t1\tx\n", em: chrome)
        XCTAssertEqual(abas.map(\.titulo), ["(5) WhatsApp", "WhatsApp"])
        XCTAssertEqual(abas.map(\.naoLidas), [5, 0])
        XCTAssertEqual(abas.map(\.janela), [1, 2])
    }

    func testInterpretaPermissaoTempoEsgotadoEFalha() {
        let n = NavegadorWeb.chamado("Safari")!
        XCTAssertEqual(WhatsAppWeb.interpretar(status: 0, saida: "fechado\n", navegador: n), .fechado)
        XCTAssertEqual(WhatsAppWeb.interpretar(status: 0, saida: "", navegador: n), .abas([]))
        XCTAssertEqual(WhatsAppWeb.interpretar(status: 1, saida: "execution error: Not authorized to send Apple events to Safari. (-1743)", navegador: n), .semPermissao)
        XCTAssertEqual(WhatsAppWeb.interpretar(status: ExecutorAcoes.statusTempoEsgotado, saida: "", navegador: n), .falhou)
        XCTAssertEqual(WhatsAppWeb.interpretar(status: 1, saida: "outra coisa", navegador: n), .falhou)
    }

    func testOComandoDeBuscaTemTempoLimiteEPerguntaSeOProcessoEstaAberto() {
        for n in NavegadorWeb.todos {
            let c = WhatsAppWeb.comandoBusca(n)
            XCTAssertTrue(c.hasPrefix("perl -e "), n.nome)
            // A linha inteira vai entre aspas simples para o vigia, então o nome do processo aparece escapado.
            XCTAssertTrue(c.contains("pgrep -x ") && c.contains(n.processo), n.nome)
            XCTAssertTrue(c.contains("application id \"\(n.idBundle)\""), n.nome)
            XCTAssertTrue(c.contains(n.estilo == .safari ? "(name of t)" : "(title of t)"), n.nome)
        }
    }

    /// Dentro do `tell` de um navegador `tab` é a classe da aba e sai como o texto "tab": o separador tem
    /// de nascer fora do `tell`. E só vale URL que COMEÇA no domínio (uma busca no Google por ele não).
    func testOSeparadorNaoEOTabDoNavegadorEAUrlTemQueComecarNoDominio() {
        for n in NavegadorWeb.todos {
            let c = WhatsAppWeb.comandoBusca(n)
            XCTAssertFalse(c.contains("& tab &"), n.nome)
            XCTAssertTrue(c.contains("set sep to (ASCII character 9)"), n.nome)
            XCTAssertLessThan(c.range(of: "set sep to")!.lowerBound, c.range(of: "tell application id")!.lowerBound, n.nome)
            XCTAssertTrue(c.contains("starts with \"https://web.whatsapp.com\""), n.nome)
            XCTAssertFalse(c.contains("contains \"web.whatsapp.com\""), n.nome)
        }
    }

    /// O AppleScript de verdade (sem navegador): o separador montado fora do `tell` vira TAB.
    func testOSeparadorFeitoComAsciiViraTabDeVerdade() throws {
        #if !os(macOS)
        throw XCTSkip("osascript só existe no macOS")
        #endif
        let r = ExecutorShell().rodar("osascript -e 'set sep to (ASCII character 9)' -e 'return \"1\" & sep & \"2\"'")
        XCTAssertEqual(r.saida.trimmingCharacters(in: .newlines), "1\t2")
    }

    // MARK: Decisão da origem

    func testAutoComBancoEmAtividadeFicaNoAppENaoConsultaOsNavegadores() {
        let ex = ExecutorFalso([stat(haSegundos: 60), chromeComAba("(9) WhatsApp")])
        let d = origem(ConfigWhatsApp(), ex).decidir()
        XCTAssertEqual(d.origem, "app")
        XCTAssertEqual(ex.comandos.count, 1, "só o stat do banco")
        XCTAssertFalse(ex.comandos.contains { $0.contains("pgrep") })
    }

    func testAutoComBancoParadoEAbaDoWhatsAppWebVaiParaWeb() {
        let ex = ExecutorFalso([stat(haSegundos: 3 * 24 * 3600), chromeComAba("(23) WhatsApp")] + outrosFechados)
        let d = origem(ConfigWhatsApp(), ex).decidir()
        XCTAssertEqual(d.origem, "web")
        XCTAssertEqual(d.aba?.naoLidas, 23)
        XCTAssertEqual(d.aba?.navegador.nome, "Google Chrome")
        XCTAssertNil(d.aviso)
    }

    func testAutoComBancoAusenteEAbaVaiParaWeb() {
        let ex = ExecutorFalso([semBanco, chromeComAba("(2) WhatsApp")] + outrosFechados)
        XCTAssertEqual(origem(ConfigWhatsApp(), ex).decidir().origem, "web")
    }

    func testAutoComBancoParadoESemAbaFicaNoApp() {
        let ex = ExecutorFalso([stat(haSegundos: 3 * 3600), ("com.google.Chrome", SaidaShell(status: 0, saida: ""))] + outrosFechados)
        let d = origem(ConfigWhatsApp(), ex).decidir()
        XCTAssertEqual(d.origem, "app")
        XCTAssertNil(d.aba)
    }

    /// Mac sem o app do WhatsApp (sem banco) e sem aba aberta: "Abrir no Mac" e a tecla abrem o web.
    func testAutoSemBancoESemAbaVaiParaWebEAbreOWhatsAppWeb() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: "")), semBanco, ("com.google.Chrome", SaidaShell(status: 0, saida: ""))] + outrosFechados)
        let o = origem(ConfigWhatsApp(), ex)
        let d = o.decidir()
        XCTAssertEqual(d.origem, "web")
        XCTAssertNil(d.aba)
        XCTAssertEqual(AbridorWhatsApp(origem: o, executor: ex).abrir(), .aberto)
        XCTAssertTrue(ex.comandos.contains("open 'https://web.whatsapp.com'"), ex.comandos.joined(separator: "\n"))
    }

    func testAutoOlhaOArquivoDeLogDoBancoTambem() {
        let ex = ExecutorFalso([stat(haSegundos: 10)])
        _ = origem(ConfigWhatsApp(), ex).decidir()
        XCTAssertTrue(ex.comandos[0].contains("ChatStorage.sqlite-wal"))
    }

    func testOrigemAppFixaNaoOlhaNemOBancoNemOsNavegadores() {
        let ex = ExecutorFalso([chromeComAba("(23) WhatsApp")])
        let d = origem(ConfigWhatsApp(origem: "app", navegador: nil), ex).decidir()
        XCTAssertEqual(d.origem, "app")
        XCTAssertEqual(ex.comandos, [])
    }

    func testOrigemWebFixaIgnoraOBancoMesmoEmAtividade() {
        let ex = ExecutorFalso([stat(haSegundos: 1), chromeComAba("(4) WhatsApp")] + outrosFechados)
        let d = origem(ConfigWhatsApp(origem: "web", navegador: nil), ex).decidir()
        XCTAssertEqual(d.origem, "web")
        XCTAssertEqual(d.aba?.naoLidas, 4)
        XCTAssertFalse(ex.comandos.contains { $0.contains("stat -f") })
    }

    func testNavegadorEscolhidoEConsultadoPrimeiroEVenceOutraAba() {
        let safari = ("com.apple.Safari", SaidaShell(status: 0, saida: "1\t1\t(7) WhatsApp\n"))
        let ex = ExecutorFalso([safari, chromeComAba("(30) WhatsApp")] + outrosFechados.filter { !$0.0.contains("Safari") })
        let d = origem(ConfigWhatsApp(origem: "web", navegador: "Safari"), ex).decidir()
        XCTAssertEqual(d.aba?.navegador.nome, "Safari")
        XCTAssertEqual(d.aba?.naoLidas, 7)
        XCTAssertEqual(ex.comandos.count, 1, "achou no primeiro, não consulta os outros")
    }

    func testOrigemWebSemAbaFicaEmWebMarcadaComoNaoAberta() {
        let ex = ExecutorFalso(outrosFechados + [("com.google.Chrome", SaidaShell(status: 0, saida: ""))])
        let d = origem(ConfigWhatsApp(origem: "web", navegador: nil), ex).decidir()
        XCTAssertEqual(d.origem, "web")
        XCTAssertNil(d.aba)
        XCTAssertNil(d.aviso)
    }

    func testOrigemWebSemPermissaoDaAvisoDeAutomacao() {
        let negado = SaidaShell(status: 1, saida: "execution error: Not authorized to send Apple events to Google Chrome. (-1743)")
        let ex = ExecutorFalso([("com.google.Chrome", negado)] + outrosFechados)
        let d = origem(ConfigWhatsApp(origem: "web", navegador: nil), ex).decidir()
        XCTAssertEqual(d.aviso, WhatsAppWeb.avisoPermissao)
        XCTAssertTrue(d.aviso!.texto.contains("Automação"))
    }

    func testNavegadorQueEstouraOTempoNaoDerrubaAsOutrasConsultas() {
        let lento = SaidaShell(status: ExecutorAcoes.statusTempoEsgotado, saida: "")
        let ex = ExecutorFalso([("com.apple.Safari", lento), chromeComAba("(1) WhatsApp")] + outrosFechados.filter { !$0.0.contains("Safari") })
        XCTAssertEqual(origem(ConfigWhatsApp(origem: "web", navegador: nil), ex).decidir().aba?.naoLidas, 1)
    }

    func testADecisaoFicaGuardadaPorPoucosSegundos() {
        let ex = ExecutorFalso([stat(haSegundos: 5)])
        let o = origem(ConfigWhatsApp(), ex)
        _ = o.decidir(); _ = o.decidir()
        XCTAssertEqual(ex.comandos.count, 1)
    }

    // MARK: Leitura (o que vai para o estado)

    func testLeituraWebDevolveSoOTotalDoTituloSemListaDeConversas() {
        let ex = ExecutorFalso([semBanco, chromeComAba("(23) WhatsApp")] + outrosFechados)
        let f = FonteWhatsAppEscolhida(origem: origem(ConfigWhatsApp(), ex), app: FonteWhatsApp(executor: ex, banco: banco))
        let l = f.ler()
        XCTAssertEqual(l.valor?.resumo, ResumoWhatsApp(total: 23, conversas: 0, origem: "web", navegador: "Google Chrome", aberto: true))
        XCTAssertEqual(l.valor?.conversas, [])
        XCTAssertNil(l.aviso)
        XCTAssertFalse(ex.comandos.contains { $0.contains("sqlite3") }, "web não abre o banco")
    }

    func testLeituraWebSemAbaDiaQueNaoEstaAberto() {
        let ex = ExecutorFalso(outrosFechados + [("com.google.Chrome", fechado.self)])
        let f = FonteWhatsAppEscolhida(origem: origem(ConfigWhatsApp(origem: "web", navegador: "Arc"), ex), app: FonteWhatsApp(executor: ex, banco: banco))
        let r = f.ler().valor?.resumo
        XCTAssertEqual(r?.total, 0)
        XCTAssertEqual(r?.aberto, false)
        XCTAssertEqual(r?.navegador, "Arc", "o navegador fixado, onde o WhatsApp Web vai abrir")
    }

    func testLeituraAppMarcaAOrigemEMantemALista() {
        let conversas = #"[{"id":1,"nome":"Maria","tipo":0,"nao":2,"ultima":813848582.5,"jid":"1@lid"}]"#
        let mensagens = #"[{"cid":1,"d":813848500.0,"t":"oi","ty":0,"de":null},{"cid":1,"d":813848582.0,"t":"oi de novo","ty":0,"de":null}]"#
        let ex = ExecutorFalso([stat(haSegundos: 30), ("from ZWACHATSESSION", SaidaShell(status: 0, saida: conversas)), ("from ZWAMESSAGE", SaidaShell(status: 0, saida: mensagens))])
        let f = FonteWhatsAppEscolhida(origem: origem(ConfigWhatsApp(), ex), app: FonteWhatsApp(executor: ex, banco: banco))
        let l = f.ler()
        XCTAssertEqual(l.valor?.resumo.origem, "app")
        XCTAssertEqual(l.valor?.resumo.total, 2)
        XCTAssertEqual(l.valor?.conversas.count, 1)
    }

    func testEstadoTrazOTotalDaAbaEOSeloDaTeclaDoWhatsApp() {
        let ex = ExecutorFalso([semBanco, chromeComAba("(23) WhatsApp")] + outrosFechados)
        let fontes = Fontes.vivas(executor: ex, casa: "/Users/x", origemWhatsApp: origem(ConfigWhatsApp(), ex))
        let cfg = config(perfil: [Tecla(id: "w", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: nil)],
                         blocos: Blocos(spotify: false, agenda: false, whatsapp: true, sessoes: false, uso: false))
        let e = Agregador(fontes: fontes, limite: 5).estado(config: cfg, agora: agora)
        XCTAssertEqual(e.whatsapp?.total, 23)
        XCTAssertEqual(e.whatsapp?.origem, "web")
        XCTAssertEqual(e.whatsapp?.navegador, "Google Chrome")
        XCTAssertEqual(e.selos["w"], "23")
    }

    // MARK: Abrir

    func testAbreATelaExistenteDoWhatsAppWebTrazendoONavegadorParaAFrente() {
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), semBanco, chromeComAba("(23) WhatsApp", janela: 2, aba: 3)] + outrosFechados)
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(), ex), executor: ex)
        XCTAssertEqual(abridor.abrir(), .aberto)
        let ultimo = ex.comandos.last!
        for trecho in ["set active tab index of window 2 to 3", "set index of window 2 to 1", "activate", "com.google.Chrome"] {
            XCTAssertTrue(ultimo.contains(trecho), trecho)
        }
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open ") })
    }

    func testNoSafariAtivaAAbaPeloCurrentTab() {
        let safari = ("com.apple.Safari", SaidaShell(status: 0, saida: "1\t4\t(1) WhatsApp\n"))
        let ex = ExecutorFalso([("set current tab", SaidaShell(status: 0, saida: "")), semBanco, safari] + outrosFechados.filter { !$0.0.contains("Safari") })
        XCTAssertEqual(AbridorWhatsApp(origem: origem(ConfigWhatsApp(), ex), executor: ex).abrir(), .aberto)
        XCTAssertTrue(ex.comandos.last!.contains("set current tab of window 1 to tab 4 of window 1"))
    }

    func testSemAbaAbreOWhatsAppWebNoNavegadorEscolhido() {
        let ex = ExecutorFalso(outrosFechados + [("com.google.Chrome", fechado), ("open -a", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "web", navegador: "Arc"), ex), executor: ex)
        XCTAssertEqual(abridor.abrir(), .aberto)
        XCTAssertEqual(ex.comandos.last, "open -a 'Arc' 'https://web.whatsapp.com'")
    }

    func testSemAbaENemNavegadorEscolhidoAbreNoNavegadorPadraoDoMac() {
        let ex = ExecutorFalso(outrosFechados + [("com.google.Chrome", fechado), ("open 'https", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "web", navegador: nil), ex), executor: ex)
        XCTAssertEqual(abridor.abrir(), .aberto)
        XCTAssertEqual(ex.comandos.last, "open 'https://web.whatsapp.com'")
    }

    func testSeATelaSumiuNoMeioDoCaminhoAbreUmaNova() {
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 1, saida: "erro")), ("open -a", SaidaShell(status: 0, saida: "")), semBanco, chromeComAba("(1) WhatsApp")] + outrosFechados)
        XCTAssertEqual(AbridorWhatsApp(origem: origem(ConfigWhatsApp(), ex), executor: ex).abrir(), .aberto)
        XCTAssertEqual(ex.comandos.last, "open -a 'Google Chrome' 'https://web.whatsapp.com'")
    }

    func testFalhaAoAbrirDaErroEmPortugues() {
        let ex = ExecutorFalso(outrosFechados + [("com.google.Chrome", fechado), ("open", SaidaShell(status: 1, saida: "x"))])
        XCTAssertEqual(AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "web", navegador: nil), ex), executor: ex).abrir(), .falhou(AbridorWhatsApp.erro))
    }

    func testOrigemAppNaoMexeNoNavegador() {
        let ex = ExecutorFalso([])
        XCTAssertEqual(AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "app", navegador: nil), ex), executor: ex).abrir(), .naoEWeb)
        XCTAssertEqual(ex.comandos, [])
    }

    func testATeclaDoWhatsAppAbreAWebEnaoOAppQuandoAOrigemEWeb() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: ""))])
        let acoes = ExecutorAcoes(shell: ex, whatsappWeb: { .aberto })
        let t = Tecla(id: "w", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: nil)
        XCTAssertNil(acoes.executar(t))
        XCTAssertEqual(ex.comandos, [], "nada de `open -a WhatsApp`")
    }

    func testATeclaDoWhatsAppVoltaAoAppQuandoAOrigemNaoEWeb() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: ""))])
        let acoes = ExecutorAcoes(shell: ex, whatsappWeb: { .naoEWeb })
        let t = Tecla(id: "w", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: nil)
        XCTAssertNil(acoes.executar(t))
        XCTAssertEqual(ex.comandos, ["open -a 'WhatsApp'"])
    }

    func testOutroAppNuncaPassaPeloWhatsAppWeb() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: ""))])
        let acoes = ExecutorAcoes(shell: ex, whatsappWeb: { XCTFail("não devia chamar"); return .aberto })
        XCTAssertNil(acoes.executar(Tecla(id: "n", nome: "Notas", tipo: "app", valor: "Notes", estado: nil, icone: nil)))
        XCTAssertEqual(ex.comandos, ["open -a 'Notes'"])
    }

    func testATeclaMostraOErroQuandoOWhatsAppWebNaoAbre() {
        let acoes = ExecutorAcoes(shell: ExecutorFalso([]), whatsappWeb: { .falhou(AbridorWhatsApp.erro) })
        let t = Tecla(id: "w", nome: "WhatsApp", tipo: "app", valor: "whatsapp", estado: nil, icone: nil)
        XCTAssertEqual(acoes.executar(t), AbridorWhatsApp.erro)
    }

    // MARK: Roteador de ponta a ponta

    func testBotaoDoWhatsAppPeloRoteadorAbreAAbaDoWhatsAppWeb() throws {
        let url = try pastaTemporaria().appendingPathComponent("config.json")
        let armazem = try ArmazemEmDisco(ArmazemConfig(url: url, nomeMac: "Mac de teste"))
        var cfg = armazem.ler()
        cfg.whatsapp = ConfigWhatsApp(origem: "web", navegador: nil)
        XCTAssertNil(armazem.aplicar(cfg))
        let id = cfg.perfis[0].teclas.first { $0.valor == "WhatsApp" }!.id
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("(23) WhatsApp", janela: 1, aba: 2)] + outrosFechados)
        let r = Ligacao.roteador(armazem: armazem, pareamento: Pareamento(), pagina: ArquivosPagina(raiz: try pastaTemporaria()), executor: ex)
        let resp = r.responder(HttpRequisicao(metodo: "POST", caminho: "/api/botao/\(id)", query: [:], cabecalhos: ["x-deck-codigo": cfg.codigoAcesso], corpo: Data()))
        XCTAssertEqual(resp.status, 200, String(decoding: resp.corpo, as: UTF8.self))
        XCTAssertTrue(ex.comandos.last!.contains("set active tab index of window 1 to 2"))
        XCTAssertFalse(ex.comandos.contains { $0.contains("open -a 'WhatsApp'") })
    }
    // MARK: Responder no Mac (12/11/2026): abre a conversa do contato no WhatsApp Web

    func testResponderAbreAConversaDoNumeroNoNavegadorPadrao() {
        let ex = ExecutorFalso([("open 'https", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex)
        XCTAssertEqual(abridor.abrirConversa(numero: "5511900000000", grupo: false), .aberta(aviso: nil))
        XCTAssertEqual(ex.comandos.filter { $0.hasPrefix("open") }, ["open 'https://web.whatsapp.com/send?phone=5511900000000'"])
    }

    func testResponderUsaONavegadorEscolhido() {
        let ex = ExecutorFalso([("open -a", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: "Arc"), ex), executor: ex)
        XCTAssertEqual(abridor.abrirConversa(numero: "5511900000000", grupo: false), .aberta(aviso: nil))
        XCTAssertEqual(ex.comandos.filter { $0.hasPrefix("open") }, ["open -a 'Arc' 'https://web.whatsapp.com/send?phone=5511900000000'"])
    }

    func testResponderEmGrupoAbreOWebEDizQueNaoTemLinkDireto() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex)
        XCTAssertEqual(abridor.abrirConversa(numero: nil, grupo: true), .aberta(aviso: AbridorWhatsApp.avisoDoGrupo))
        XCTAssertEqual(ex.comandos.filter { $0.hasPrefix("open") }, ["open 'https://web.whatsapp.com'"])
    }

    func testResponderSemNumeroAbreOWebEAvisa() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 0, saida: ""))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex)
        XCTAssertEqual(abridor.abrirConversa(numero: nil, grupo: false), .aberta(aviso: AbridorWhatsApp.avisoSemNumero))
    }

    func testNumeroComLixoNuncaViraParteDoComando() {
        for ruim in ["5544'; rm -rf ~; '", "55 11900000000", "123", "1234567890123456", "+5511900000000", "55１１900000000"] {
            XCTAssertNil(WhatsAppWeb.enderecoDaConversa(numero: ruim), ruim)
        }
        XCTAssertEqual(WhatsAppWeb.enderecoDaConversa(numero: "5511900000000"), "https://web.whatsapp.com/send?phone=5511900000000")
    }

    // A aba que já está aberta é reaproveitada SEM trocar o endereço dela (13/11/2026: "é pra permanecer na mesma"): ela vem
    // para a frente e a conversa abre pela busca do próprio WhatsApp Web.

    /// A busca de mentira: guarda o que lhe pediram e devolve o resultado combinado.
    final class BuscaFalsa: BuscaNaPagina, @unchecked Sendable {
        var pedidos: [(pid: Int32, texto: String, aguardar: TimeInterval)] = []
        var resultado: ResultadoBusca
        init(_ r: ResultadoBusca = .aberta) { resultado = r }
        func pesquisar(pid: Int32, texto: String, aguardar: TimeInterval) -> ResultadoBusca {
            pedidos.append((pid, texto, aguardar)); return resultado
        }
    }
    let comPid = ("pgrep -x", SaidaShell(status: 0, saida: "4321\n"))

    func abridor(_ ex: ExecutorFalso, _ busca: BuscaFalsa?, cfg: ConfigWhatsApp = ConfigWhatsApp(origem: "qr", navegador: nil)) -> AbridorWhatsApp {
        AbridorWhatsApp(origem: origem(cfg, ex), executor: ex, busca: busca, dormir: { _ in })
    }

    func testResponderComAbaAbertaNaoTrocaOEnderecoEBuscaPeloNome() {
        let busca = BuscaFalsa()
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("(3) WhatsApp", janela: 2, aba: 4)] + outrosFechados + [comPid])
        let r = abridor(ex, busca).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana Souza")
        XCTAssertEqual(r, .aberta(aviso: nil))
        XCTAssertEqual(busca.pedidos.map(\.texto), ["Ana Souza"])
        XCTAssertEqual(busca.pedidos.first?.pid, 4321)
        let trouxe = ex.comandos.last { $0.contains("set active tab index") }!
        for trecho in ["set active tab index of window 2 to 4", "set index of window 2 to 1", "activate", "com.google.Chrome"] { XCTAssertTrue(trouxe.contains(trecho), trecho) }
        XCTAssertFalse(ex.comandos.contains { $0.contains("set URL") || $0.contains("send?phone") }, "a página não recarrega: o endereço da aba não muda")
        XCTAssertFalse(ex.comandos.contains { $0.hasPrefix("open") }, "nada de aba nova")
    }

    /// Vários processos com o nome do navegador (perfil extra, instância de automação): a aba do WhatsApp está em um só.
    final class BuscaPorProcesso: BuscaNaPagina, @unchecked Sendable {
        var tentativas: [Int32] = []
        let ondeTem: Int32
        init(ondeTem: Int32) { self.ondeTem = ondeTem }
        func pesquisar(pid: Int32, texto: String, aguardar: TimeInterval) -> ResultadoBusca {
            tentativas.append(pid); return pid == ondeTem ? .aberta : .semCampo
        }
    }

    func testResponderTentaCadaProcessoDoNavegadorAteAchar() {
        let busca = BuscaPorProcesso(ondeTem: 333)
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp"), ("pgrep -x", SaidaShell(status: 0, saida: "111\n222\n333\n"))] + outrosFechados)
        let r = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex, busca: busca, dormir: { _ in })
            .abrirConversa(numero: nil, grupo: true, nome: "Louvor")
        XCTAssertEqual(r, .aberta(aviso: nil))
        XCTAssertEqual(busca.tentativas, [111, 222, 333])
    }

    func testResponderComNenhumProcessoComCampoAvisaParaProcurarNaLista() {
        let busca = BuscaPorProcesso(ondeTem: 999)
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp"), ("pgrep -x", SaidaShell(status: 0, saida: "111\n222\n"))] + outrosFechados)
        let r = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex, busca: busca, dormir: { _ in })
            .abrirConversa(numero: nil, grupo: true, nome: "Louvor")
        XCTAssertEqual(r, .aberta(aviso: AbridorWhatsApp.avisoDoGrupo))
    }

    func testResponderEmGrupoComAbaAbertaBuscaOGrupoPeloNome() {
        let busca = BuscaFalsa()
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp", janela: 1, aba: 2)] + outrosFechados + [comPid])
        XCTAssertEqual(abridor(ex, busca).abrirConversa(numero: nil, grupo: true, nome: "Louvor"), .aberta(aviso: nil))
        XCTAssertEqual(busca.pedidos.map(\.texto), ["Louvor"])
        XCTAssertFalse(ex.comandos.contains { $0.contains("set URL") })
    }

    func testResponderContatoSemNomeBuscaPeloNumero() {
        let busca = BuscaFalsa()
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp")] + outrosFechados + [comPid])
        _ = abridor(ex, busca).abrirConversa(numero: "5511900000000", grupo: false, nome: "Contato")
        XCTAssertEqual(busca.pedidos.map(\.texto), ["5511900000000"])
        _ = abridor(ex, busca).abrirConversa(numero: "5511900000000", grupo: false, nome: "+55 11 90000-0000")
        XCTAssertEqual(busca.pedidos.map(\.texto), ["5511900000000", "5511900000000"])
    }

    func testResponderComAbaNoSafariUsaAAbaAtualDele() {
        let safari = ("com.apple.Safari", SaidaShell(status: 0, saida: "1\t3\t(1) WhatsApp\n"))
        let ex = ExecutorFalso([("set current tab of window", SaidaShell(status: 0, saida: "")), safari] + outrosFechados.filter { !$0.0.contains("Safari") } + [comPid])
        XCTAssertEqual(abridor(ex, BuscaFalsa()).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: nil))
        XCTAssertTrue(ex.comandos.contains { $0.contains("set current tab of window 1 to tab 3 of window 1") })
    }

    func testResponderSemABuscaTrazAAbaEAvisaSemTrocarOEndereco() {
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp")] + outrosFechados + [comPid])
        XCTAssertEqual(abridor(ex, nil).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: AbridorWhatsApp.avisoSemNumero))
        XCTAssertEqual(abridor(ex, nil).abrirConversa(numero: nil, grupo: true, nome: "Louvor"), .aberta(aviso: AbridorWhatsApp.avisoDoGrupo))
        XCTAssertFalse(ex.comandos.contains { $0.contains("set URL") })
    }

    func testResponderQuandoABuscaFalhaAvisaECadaMotivoTemSeuTexto() {
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp")] + outrosFechados + [comPid])
        let casos: [(ResultadoBusca, String)] = [(.semAcesso, AbridorWhatsApp.avisoSemAcesso), (.semCampo, AbridorWhatsApp.avisoSemNumero),
                                                 (.ambiguo, AbridorWhatsApp.avisoSemNumero), (.naoFocou, AbridorWhatsApp.avisoSemNumero)]
        for (res, aviso) in casos {
            XCTAssertEqual(abridor(ex, BuscaFalsa(res)).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: aviso), "\(res)")
        }
    }

    func testResponderSemAbaDeContatoComNumeroAbreNovaPeloLinkDireto() {
        let busca = BuscaFalsa()
        let ex = ExecutorFalso([("open 'https", SaidaShell(status: 0, saida: ""))] + ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"].map { ($0, SaidaShell(status: 0, saida: "fechado\n")) })
        XCTAssertEqual(abridor(ex, busca).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: nil))
        XCTAssertEqual(ex.comandos.last, "open 'https://web.whatsapp.com/send?phone=5511900000000'")
        XCTAssertTrue(busca.pedidos.isEmpty, "o link direto já abre a conversa")
    }

    func testResponderGrupoSemAbaAbreOWebEBuscaDepoisDeCarregar() {
        let busca = BuscaFalsa()
        let ex = ExecutorFalso([("open -a 'Google Chrome' 'https://web.whatsapp.com'", SaidaShell(status: 0, saida: "")), comPid])
        let r = abridor(ex, busca, cfg: ConfigWhatsApp(origem: "qr", navegador: "Google Chrome")).abrirConversa(numero: nil, grupo: true, nome: "Louvor")
        XCTAssertEqual(r, .aberta(aviso: nil))
        XCTAssertEqual(busca.pedidos.map(\.texto), ["Louvor"])
        XCTAssertGreaterThanOrEqual(busca.pedidos[0].aguardar, 8, "a página nova leva um tempo para carregar")
    }

    func testResponderSeAAbaSumiuNoMeioDoCaminhoAbreUmaNova() {
        let ex = ExecutorFalso([("set active tab index", SaidaShell(status: 1, saida: "erro")), ("open 'https", SaidaShell(status: 0, saida: "")), chromeComAba("WhatsApp")] + outrosFechados)
        XCTAssertEqual(abridor(ex, BuscaFalsa()).abrirConversa(numero: "5511900000000", grupo: false, nome: "Ana"), .aberta(aviso: nil))
        XCTAssertEqual(ex.comandos.last, "open 'https://web.whatsapp.com/send?phone=5511900000000'")
    }

    // MARK: Que campo vale como a busca

    func testSoOCampoDeBuscaDaListaVale() {
        for ok in ["Pesquisar ou começar uma nova conversa", "Search or start a new chat", "Search or start new chat", "Buscar un chat o iniciar uno nuevo",
                   "Search input textbox", "Caixa de texto de pesquisa"] {
            XCTAssertTrue(CampoDoWhatsApp.ehBusca(ok), ok)
        }
        for nao in ["Digite uma mensagem", "Type a message", "Escribe un mensaje", "Pesquisar...", "Search...", "Pesquisar mensagens nesta conversa",
                    "Pesquisar ou começar uma nova mensagem", "", "Nome do grupo"] {
            XCTAssertFalse(CampoDoWhatsApp.ehBusca(nao), nao)
        }
        XCTAssertTrue(CampoDoWhatsApp.ehBusca(CampoWeb(rotulos: ["", "Pesquisar ou começar uma nova conversa"])))
    }

    func testTermoDeBuscaEONomeOuONumeroDeQuemNaoTemNome() {
        XCTAssertEqual(CampoDoWhatsApp.termo(nome: " Ana Souza ", numero: "5511900000000"), "Ana Souza")
        XCTAssertEqual(CampoDoWhatsApp.termo(nome: "Louvor", numero: nil), "Louvor")
        XCTAssertEqual(CampoDoWhatsApp.termo(nome: "Contato", numero: "5511900000000"), "5511900000000")
        XCTAssertEqual(CampoDoWhatsApp.termo(nome: "", numero: "5511900000000"), "5511900000000")
        XCTAssertEqual(CampoDoWhatsApp.termo(nome: "+55 11 90000-0000", numero: "5511900000000"), "5511900000000")
        XCTAssertNil(CampoDoWhatsApp.termo(nome: "Grupo", numero: nil))
        XCTAssertNil(CampoDoWhatsApp.termo(nome: nil, numero: "12"))
        XCTAssertNil(CampoDoWhatsApp.termo(nome: nil, numero: "55 44'; rm -rf ~; '"))
    }

    func testResponderFalhaDaErroEmPortugues() {
        let ex = ExecutorFalso([("open", SaidaShell(status: 1, saida: "x"))])
        let abridor = AbridorWhatsApp(origem: origem(ConfigWhatsApp(origem: "qr", navegador: nil), ex), executor: ex)
        XCTAssertEqual(abridor.abrirConversa(numero: "5511900000000", grupo: false), .falhou(AbridorWhatsApp.erro))
    }

}

final class ConfigWhatsAppTestes: XCTestCase {
    private func ler(_ whatsapp: String?) throws -> Config {
        let extra = whatsapp.map { #","whatsapp":\#($0)"# } ?? ""
        let json = #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","codigoAcesso":"abcdefghjkmnpqrstuvw"\#(extra)}"#
        let d = JSONDecoder()
        d.userInfo[Config.chaveNomeMac] = "Mac"
        return try d.decode(Config.self, from: Data(json.utf8))
    }

    func testConfigAntigaSemOCampoLeComoAutomatico() throws {
        XCTAssertEqual(try ler(nil).whatsapp, ConfigWhatsApp(origem: "auto", navegador: nil))
    }

    func testLeOCampoDeVerdade() throws {
        XCTAssertEqual(try ler(#"{"origem":"web","navegador":"Arc"}"#).whatsapp, ConfigWhatsApp(origem: "web", navegador: "Arc"))
        XCTAssertEqual(try ler(#"{"origem":"app"}"#).whatsapp, ConfigWhatsApp(origem: "app", navegador: nil))
    }

    func testLeituraTolerante() throws {
        XCTAssertEqual(try ler(#"{"origem":"telepatia","navegador":"Netscape"}"#).whatsapp, ConfigWhatsApp(origem: "auto", navegador: nil))
        XCTAssertEqual(try ler(#"{"origem":42,"navegador":false}"#).whatsapp, ConfigWhatsApp())
        XCTAssertEqual(try ler("true").whatsapp, ConfigWhatsApp(), "valor que não é objeto não derruba a config")
        XCTAssertEqual(try ler("{}").whatsapp, ConfigWhatsApp())
    }

    func testFicaNoJsonGravadoENoGetDaConfig() throws {
        var c = Config.padrao(nomeMac: "M")
        c.whatsapp = ConfigWhatsApp(origem: "web", navegador: "Safari")
        let volta = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(volta.whatsapp, c.whatsapp)
        XCTAssertEqual(c.publica.whatsapp, c.whatsapp)
    }

    func testValidarRecusaOrigemENavegadorQueNaoExistem() {
        var c = Config.padrao(nomeMac: "M")
        XCTAssertNil(Config.validar(c))
        c.whatsapp.origem = "radio"
        XCTAssertNotNil(Config.validar(c))
        c.whatsapp = ConfigWhatsApp(origem: "web", navegador: "Netscape")
        XCTAssertNotNil(Config.validar(c))
        c.whatsapp = ConfigWhatsApp(origem: "web", navegador: "Microsoft Edge")
        XCTAssertNil(Config.validar(c))
    }

    func testPutDePainelVelhoSemOCampoNaoApagaAEscolhaDoUsuario() throws {
        var atual = Config.padrao(nomeMac: "M")
        atual.whatsapp = ConfigWhatsApp(origem: "web", navegador: "Arc")
        var nova = atual
        nova.perfis[0].nome = "Palco"
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(nova)) as? [String: Any])
        obj.removeValue(forKey: "whatsapp")
        guard case .success(let c) = Config.receber(corpo: try JSONSerialization.data(withJSONObject: obj), sobre: atual) else { return XCTFail("recusou") }
        XCTAssertEqual(c.perfis[0].nome, "Palco")
        XCTAssertEqual(c.whatsapp, ConfigWhatsApp(origem: "web", navegador: "Arc"))
    }

    func testPutComOCampoTrocaAOrigem() throws {
        let atual = Config.padrao(nomeMac: "M")
        var nova = atual
        nova.whatsapp = ConfigWhatsApp(origem: "web", navegador: "Google Chrome")
        guard case .success(let c) = Config.receber(corpo: try JSONEncoder().encode(nova), sobre: atual) else { return XCTFail("recusou") }
        XCTAssertEqual(c.whatsapp, ConfigWhatsApp(origem: "web", navegador: "Google Chrome"))
    }
}

/// Prova contra este Mac, só leitura. Só roda com DECK_PROVA_REAL=1 (no CI e no Linux fica pulado).
/// Imprime a origem, o navegador e o total lido do título da aba. Nunca imprime título, URL nem mensagem.
///   DECK_PROVA_REAL=1 swift test --package-path mac --filter ProvaRealWhatsAppWebTestes
final class ProvaRealWhatsAppWebTestes: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DECK_PROVA_REAL"] == "1", "prova real desligada")
    }

    func testDetectaAOrigemNesteMac() {
        let ex = ExecutorShell()
        let banco = FonteWhatsApp.caminhoPadrao(casa: NSHomeDirectory())
        let o = OrigemWhatsApp(executor: ex, banco: banco)
        let t0 = Date()
        print("banco do app em atividade (30 min): \(o.bancoAtivo(Date()))")
        let d = o.decidir()
        for n in NavegadorWeb.todos {
            let t1 = Date()
            let r = ex.rodar(WhatsAppWeb.comandoBusca(n))
            print("consulta \(n.nome): status=\(r.status) -> \(WhatsAppWeb.interpretar(status: r.status, saida: r.saida, navegador: n).resumo) em \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
        }
        print("origem detectada: \(d.origem)")
        print("aba do WhatsApp Web achada: \(d.aba != nil)")
        if let aba = d.aba { print("navegador: \(aba.navegador.nome) janela=\(aba.janela) aba=\(aba.aba) total lido do título: \(aba.naoLidas)") }
        print("aviso: \(d.aviso?.texto ?? "nenhum")")
        let l = FonteWhatsAppEscolhida(origem: o, app: FonteWhatsApp(executor: ex, banco: banco)).ler()
        print("resumo no estado: \(String(describing: l.valor?.resumo)) conversas na lista: \(l.valor?.conversas.count ?? -1) aviso: \(l.aviso?.texto ?? "nenhum")")
        print("tempo total: \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    }
}

private extension WhatsAppWeb.Busca {
    /// Resumo sem título nem URL: só o que a prova precisa mostrar.
    var resumo: String {
        switch self {
        case .fechado: return "navegador fechado"
        case .abas(let a): return "\(a.count) aba(s) do WhatsApp Web, não lidas no título: \(a.map(\.naoLidas))"
        case .semPermissao: return "sem permissão de Automação"
        case .falhou: return "falhou ou estourou o tempo"
        }
    }
}
