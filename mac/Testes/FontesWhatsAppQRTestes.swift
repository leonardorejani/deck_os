import XCTest
@testable import Nucleo

/// O ajudante de verdade (Go) não roda aqui: um script de shell faz o papel dele e imprime as mesmas
/// linhas de JSON, com dados inventados.
final class FontesWhatsAppQRTestes: XCTestCase {
    var pasta: URL!

    override func setUpWithError() throws {
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-qr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: pasta) }

    /// Cria o "ajudante": o script recebe `--pasta <dir>` como o de verdade.
    func ajudante(_ corpo: String) throws -> URL {
        let url = pasta.appendingPathComponent("ajudante.sh")
        try ("#!/bin/sh\n" + corpo + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func ponte(_ corpo: String) throws -> PonteWhatsAppQR {
        PonteWhatsAppQR(executavel: try ajudante(corpo), pasta: pasta.appendingPathComponent("sessao", isDirectory: true))
    }

    func esperar(_ motivo: String, _ cond: () -> Bool) {
        let limite = Date().addingTimeInterval(6)
        while !cond(), Date() < limite { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertTrue(cond(), motivo)
    }

    static let conversas = #"{"t":"conversas","lista":[{"id":"a","nome":"Louvor","grupo":true,"naoLidas":2,"ultima":"2026-11-12T13:00:00Z","mensagens":[{"de":"Ana","texto":"Ensaio às 19h","hora":"2026-11-12T12:59:00Z"},{"de":"Beto","texto":"Foto","hora":"2026-11-12T13:00:00Z"}]},{"id":"b","nome":"Carla","grupo":false,"naoLidas":1,"ultima":"2026-11-12T12:00:00Z","mensagens":[{"de":"","texto":"Oi","hora":"2026-11-12T12:00:00Z"}]}]}"#

    // MARK: Linhas do ajudante

    func testInterpretaAsLinhasDoAjudante() {
        XCTAssertEqual(LinhaDoAjudante.interpretar(#"{"t":"fase","fase":"aguardando_qr","detalhe":""}"#), .fase(.aguardandoQR, ""))
        XCTAssertEqual(LinhaDoAjudante.interpretar(#"{"t":"fase","fase":"erro","detalhe":"caiu"}"#), .fase(.erro, "caiu"))
        XCTAssertEqual(LinhaDoAjudante.interpretar(#"{"t":"qr","codigo":"2@abc"}"#), .qr("2@abc"))
        guard case .conversas(let c)? = LinhaDoAjudante.interpretar(Self.conversas) else { return XCTFail("não leu as conversas") }
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0], ConversaWhatsApp(id: "a", nome: "Louvor", grupo: true, naoLidas: 2, ultima: "2026-11-12T13:00:00Z",
                                              mensagens: [MensagemWhatsApp(de: "Ana", texto: "Ensaio às 19h", hora: "2026-11-12T12:59:00Z"),
                                                          MensagemWhatsApp(de: "Beto", texto: "Foto", hora: "2026-11-12T13:00:00Z")]))
    }

    func testLinhaEstranhaOuFaseDesconhecidaEIgnorada() {
        XCTAssertNil(LinhaDoAjudante.interpretar("não é json"))
        XCTAssertNil(LinhaDoAjudante.interpretar(#"{"t":"coisa-nova"}"#))
        XCTAssertNil(LinhaDoAjudante.interpretar(#"{"t":"fase","fase":"inventada"}"#))
        XCTAssertNil(LinhaDoAjudante.interpretar(#"{"t":"qr"}"#))
    }

    func testLeitorJuntaPedacosEmLinhasInteiras() {
        let lista = Lista()
        let l = LeitorDeLinhas { lista.add($0) }
        l.alimentar(Data(#"{"t":"qr","co"#.utf8))
        XCTAssertEqual(lista.itens, [])
        l.alimentar(Data("digo\":\"x\"}\n{\"t\":\"fase\"".utf8))
        l.alimentar(Data(",\"fase\":\"conectado\"}\n".utf8))
        XCTAssertEqual(lista.itens, [#"{"t":"qr","codigo":"x"}"#, #"{"t":"fase","fase":"conectado"}"#])
    }

    // MARK: Ponte

    func testMostraOQrEAvisaEnquantoNaoConectou() throws {
        let p = try ponte(#"echo '{"t":"fase","fase":"aguardando_qr","detalhe":""}'; echo '{"t":"qr","codigo":"2@falso"}'; cat >/dev/null"#)
        defer { p.desligar() }
        p.garantirLigada()
        esperar("QR chegou") { p.atual.qr == "2@falso" }
        XCTAssertEqual(p.atual.fase, .aguardandoQR)
        let l = p.ler()
        XCTAssertEqual(l.valor?.resumo.origem, "qr")
        XCTAssertEqual(l.valor?.resumo.aberto, false)
        XCTAssertEqual(l.valor?.conversas, [])
        XCTAssertEqual(l.aviso?.fonte, "whatsapp")
        XCTAssertTrue(l.aviso?.texto.contains("Leia o QR") == true)
    }

    func testConectadoEntregaConversasNoFormatoDoApiWhatsapp() throws {
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; cat >/dev/null")
        defer { p.desligar() }
        p.garantirLigada()
        esperar("conversas chegaram") { p.atual.conversas.count == 2 }
        let l = p.ler()
        XCTAssertNil(l.aviso)
        XCTAssertEqual(l.valor?.resumo, ResumoWhatsApp(total: 3, conversas: 2, origem: "qr", navegador: nil, aberto: true))
        XCTAssertEqual(l.valor?.conversas.map(\.nome), ["Louvor", "Carla"])
        XCTAssertNil(p.atual.qr)
    }

    func testQrVencidoNaoRelancaOAjudanteSozinho() throws {
        let marca = pasta.appendingPathComponent("lancamentos")
        let p = try ponte("echo x >> '\(marca.path)'; echo '{\"t\":\"fase\",\"fase\":\"qr_expirou\",\"detalhe\":\"\"}'")
        p.garantirLigada()
        esperar("QR expirou") { p.atual.fase == .qrExpirou }
        esperar("processo saiu") { !p.ligada }
        for _ in 0..<5 { _ = p.ler() }
        Thread.sleep(forTimeInterval: 0.3)
        let lancamentos = (try? String(contentsOf: marca))?.split(separator: "\n").count
        XCTAssertEqual(lancamentos, 1, "a leitura a cada segundo não pode relançar o ajudante")
        XCTAssertTrue(p.ler().aviso?.texto.contains("expirou") == true)
        // Quem pede outro QR é a pessoa.
        p.reiniciar()
        esperar("lançou de novo") { ((try? String(contentsOf: marca))?.split(separator: "\n").count ?? 0) == 2 }
    }

    func testAjudanteQueCaiViraErroSemRelancar() throws {
        let p = try ponte(#"echo '{"t":"fase","fase":"conectado","detalhe":""}'"#)
        p.garantirLigada()
        esperar("virou erro") { p.atual.fase == .erro }
        XCTAssertNotNil(p.ler().aviso)
    }

    func testSemAjudanteNoAppDizQueNaoEstaDisponivel() {
        let p = PonteWhatsAppQR(executavel: nil, pasta: pasta)
        XCTAssertFalse(p.disponivel)
        let l = p.ler()
        XCTAssertEqual(p.atual.fase, .erro)
        XCTAssertTrue(l.aviso?.texto.contains("sem o WhatsApp por QR") == true)
    }

    func testDesligarLimpaConversasEFechaOAjudante() throws {
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; cat >/dev/null")
        p.garantirLigada()
        esperar("conversas") { p.atual.conversas.count == 2 }
        p.desligar()
        XCTAssertEqual(p.atual, EstadoQR())
        XCTAssertFalse(p.ligada)
    }

    func testApagarSessaoMandaOComandoEApagaAPasta() throws {
        let recebido = pasta.appendingPathComponent("recebido")
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        let p = try ponte("mkdir -p \"$2\"; echo segredo > \"$2/sessao.db\"; : > \"$2/pareado\"; echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; read l; echo \"$l\" > '\(recebido.path)'")
        p.garantirLigada()
        esperar("sessão criada") { p.temSessao }
        p.apagarSessao()
        XCTAssertEqual((try? String(contentsOf: recebido))?.trimmingCharacters(in: .whitespacesAndNewlines), #"{"c":"apagar"}"#)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessao.path))
        XCTAssertEqual(p.atual.fase, .desligado)
    }

    func testSoContaComoSessaoDepoisDePareado() throws {
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try FileManager.default.createDirectory(at: sessao, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sessao.appendingPathComponent("sessao.db"))
        let p = PonteWhatsAppQR(executavel: nil, pasta: sessao)
        XCTAssertFalse(p.temSessao, "o sessao.db existe desde a primeira tentativa de QR e não prova que pareou")
        try Data().write(to: sessao.appendingPathComponent("pareado"))
        XCTAssertTrue(p.temSessao)
    }

    func testAjudanteEmbutidoPelaVariavelDeAmbiente() throws {
        let sh = try ajudante("exit 0")
        XCTAssertEqual(PonteWhatsAppQR.ajudanteEmbutido(ambiente: [PonteWhatsAppQR.variavelDoAjudante: sh.path], pacote: pasta), sh)
        XCTAssertNil(PonteWhatsAppQR.ajudanteEmbutido(ambiente: [:], pacote: pasta))
    }

    // MARK: Origem na config e na escolha da fonte

    func testOrigemQrNaConfigEDesligadaPorPadrao() throws {
        XCTAssertEqual(ConfigWhatsApp().origem, "auto")
        let c = try JSONDecoder().decode(ConfigWhatsApp.self, from: Data(#"{"origem":"qr"}"#.utf8))
        XCTAssertEqual(c.origem, "qr")
        XCTAssertTrue(ConfigWhatsApp.origens.contains("qr"))
        let desconhecida = try JSONDecoder().decode(ConfigWhatsApp.self, from: Data(#"{"origem":"zap"}"#.utf8))
        XCTAssertEqual(desconhecida.origem, "auto")
    }

    func testAutomaticoNuncaEscolheQr() {
        let ex = ExecutorFalso([("stat -f %m", SaidaShell(status: 1, saida: ""))])
        let o = OrigemWhatsApp(executor: ex, banco: "/x/ChatStorage.sqlite", config: { ConfigWhatsApp() })
        XCTAssertNotEqual(o.decidir().origem, "qr")
    }

    func testFonteEscolhidaLeDaPonteSoNaOrigemQrEDesligaQuandoSai() throws {
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; cat >/dev/null")
        defer { p.desligar() }
        let cfg = Caixa(ConfigWhatsApp(origem: "qr", navegador: nil))
        let ex = ExecutorFalso([])
        let origem = OrigemWhatsApp(executor: ex, banco: "/x/ChatStorage.sqlite", config: { cfg.valor })
        let fonte = FonteWhatsAppEscolhida(origem: origem, app: FonteWhatsApp(executor: ex, banco: "/x/ChatStorage.sqlite"), qr: p)
        _ = fonte.ler()
        esperar("conversas") { p.atual.conversas.count == 2 }
        XCTAssertEqual(fonte.ler().valor?.resumo.origem, "qr")
        XCTAssertTrue(p.ligada)
        // A pessoa volta para "app": a conexão é fechada e o app é lido de novo.
        cfg.valor = ConfigWhatsApp(origem: "app", navegador: nil)
        _ = fonte.ler()
        XCTAssertFalse(p.ligada, "fora da origem QR a conexão não pode ficar ocupando um aparelho")
    }

    func testConfigAceitaOrigemQrERecusaOutraCoisa() {
        var c = config(perfil: [])
        c.whatsapp.origem = "qr"
        XCTAssertNil(Config.validar(c))
        c.whatsapp.origem = "zap"
        XCTAssertNotNil(Config.validar(c))
    }

    /// De ponta a ponta no núcleo, com dados inventados: o Estado e a lista de /api/whatsapp saem do ajudante falso.
    func testEstadoEListaDoPainelSaemDoAjudanteFalso() throws {
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; cat >/dev/null")
        defer { p.desligar() }
        var cfg = config(perfil: [Tecla(id: "whats", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: nil)])
        cfg.whatsapp.origem = "qr"
        let ex = ExecutorFalso([])
        let cfgW = cfg.whatsapp
        let escolhida = FonteWhatsAppEscolhida(origem: OrigemWhatsApp(executor: ex, banco: "/x/c.sqlite", config: { cfgW }),
                                               app: FonteWhatsApp(executor: ex, banco: "/x/c.sqlite"), qr: p)
        let fontes = Fontes(sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
                            whatsapp: { escolhida.ler() }, seloWhatsApp: { nil }, spotify: { _ in Leitura(valor: nil, aviso: nil) },
                            capa: { nil }, agenda: { _ in Leitura(valor: nil, aviso: nil) }, acesas: { _ in [] })
        let ag = Agregador(fontes: fontes)
        _ = ag.estado(config: cfg)
        esperar("conversas") { p.atual.conversas.count == 2 }
        let agora = Date().addingTimeInterval(30)  // passa do cache de 5 s da leitura anterior
        let e = ag.estado(config: cfg, agora: agora)
        XCTAssertEqual(e.whatsapp, ResumoWhatsApp(total: 3, conversas: 2, origem: "qr", navegador: nil, aberto: true))
        XCTAssertEqual(e.selos["whats"], "3")
        XCTAssertEqual(ag.conversasWhatsApp(agora: agora).map(\.nome), ["Louvor", "Carla"])
        XCTAssertEqual(ag.conversasWhatsApp(agora: agora).first?.mensagens.first?.texto, "Ensaio às 19h")
    }

    func testOrigemQrSemPonteAvisaEmVezDeQuebrar() {
        let ex = ExecutorFalso([])
        let origem = OrigemWhatsApp(executor: ex, banco: "/x/c.sqlite", config: { ConfigWhatsApp(origem: "qr", navegador: nil) })
        let l = FonteWhatsAppEscolhida(origem: origem, app: FonteWhatsApp(executor: ex, banco: "/x/c.sqlite")).ler()
        XCTAssertNil(l.valor)
        XCTAssertNotNil(l.aviso)
    }

    // MARK: Correções da verificação (12/11/2026)

    private func pareada(_ sessao: URL) throws {
        try FileManager.default.createDirectory(at: sessao, withIntermediateDirectories: true)
        try Data().write(to: sessao.appendingPathComponent("pareado"))
    }

    /// Ajudante parado com sessão guardada: o Apagar sobe o ajudante só para sair do aparelho no WhatsApp.
    func testApagarComAjudanteParadoSobeOAjudanteParaSair() throws {
        let recebido = pasta.appendingPathComponent("recebido")
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try pareada(sessao)
        let p = try ponte("read l; echo \"$l\" > '\(recebido.path)'")
        XCTAssertFalse(p.ligada)
        XCTAssertTrue(p.apagarSessao())
        XCTAssertEqual((try? String(contentsOf: recebido))?.trimmingCharacters(in: .whitespacesAndNewlines), #"{"c":"apagar"}"#,
                       "sem processo vivo o comando de sair do aparelho nem era enviado")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessao.path))
    }

    /// O ajudante não conseguiu sair (sem rede): a sessão fica, o motivo aparece e dá para tentar de novo.
    func testApagarQueNaoSaiDoAparelhoMantemASessaoEAvisa() throws {
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try pareada(sessao)
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; read l; echo '{\"t\":\"fase\",\"fase\":\"erro\",\"detalhe\":\"sem rede\"}'; cat >/dev/null")
        p.garantirLigada()
        esperar("conectou") { p.atual.fase == .conectado }
        XCTAssertFalse(p.apagarSessao())
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessao.path), "sem sair do aparelho a sessão não pode ser apagada")
        XCTAssertTrue(p.temSessao)
        XCTAssertEqual(p.atual.fase, .erro)
        XCTAssertEqual(p.atual.detalhe, TextosWhatsAppQR.naoSaiu)
    }

    func testApagarSemSessaoGuardadaSoLimpaAPasta() throws {
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try FileManager.default.createDirectory(at: sessao, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sessao.appendingPathComponent("sessao.db"))
        let p = try ponte("exit 1")
        XCTAssertTrue(p.apagarSessao())
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessao.path))
    }

    /// Subindo ou reconectando não manda ler o QR: não há QR a ler.
    func testSubindoOuReconectandoNaoMandaLerOQr() throws {
        for f in [FaseQR.iniciando, .desconectado] {
            XCTAssertNil(EstadoQR(fase: f).aviso, "\(f) é transitória")
            XCTAssertTrue(EstadoQR(fase: f).reconectando)
        }
        for f in [FaseQR.aguardandoQR, .qrExpirou, .erro, .conectado] { XCTAssertFalse(EstadoQR(fase: f).reconectando) }
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; echo '{\"t\":\"fase\",\"fase\":\"desconectado\",\"detalhe\":\"\"}'; cat >/dev/null")
        defer { p.desligar() }
        p.garantirLigada()
        esperar("caiu") { p.atual.fase == .desconectado && p.atual.conversas.count == 2 }
        let l = p.ler()
        XCTAssertNil(l.aviso)
        XCTAssertEqual(l.valor?.resumo.aberto, false)
        XCTAssertEqual(l.valor?.resumo.reconectando, true)
        XCTAssertEqual(l.valor?.conversas.count, 2, "a lista de antes continua à vista durante a queda curta")
    }

    // MARK: Chave "Conectar pelo QR"

    func testDesligarOQrVoltaParaAOrigemDeAntes() {
        var c = ConfigWhatsApp(origem: "app", navegador: nil)
        XCTAssertTrue(c.ligarQR(disponivel: true))
        XCTAssertEqual(c.origem, "qr")
        c.desligarQR()
        XCTAssertEqual(c.origem, "app")
        XCTAssertNil(c.origemAntes)
        var web = ConfigWhatsApp(origem: "web", navegador: "Arc")
        web.ligarQR(disponivel: true); web.ligarQR(disponivel: true)
        web.desligarQR()
        XCTAssertEqual(web.origem, "web", "ligar duas vezes não pode perder a origem de antes")
        var auto = ConfigWhatsApp(origem: "qr", navegador: nil)
        auto.desligarQR()
        XCTAssertEqual(auto.origem, "auto", "sem origem de antes (config antiga), volta para auto")
    }

    func testSemAjudanteALigarNaoMudaAOrigem() {
        var c = ConfigWhatsApp(origem: "app", navegador: nil)
        XCTAssertFalse(c.ligarQR(disponivel: false))
        XCTAssertEqual(c.origem, "app", "o Deck sem o ajudante perderia a leitura pelo app")
        XCTAssertNil(c.origemAntes)
    }

    func testOrigemAntesSobreviveAoDiscoELeituraTolerante() throws {
        var c = ConfigWhatsApp(origem: "app", navegador: nil)
        c.ligarQR(disponivel: true)
        let volta = try JSONDecoder().decode(ConfigWhatsApp.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(volta.origemAntes, "app")
        let ruim = try JSONDecoder().decode(ConfigWhatsApp.self, from: Data(#"{"origem":"qr","origemAntes":"zap"}"#.utf8))
        XCTAssertNil(ruim.origemAntes)
    }
    // MARK: Conexões e WhatsApp (12/11/2026): arquivadas, nome em branco, foto, mídia e velocidade

    func testLeNomeNumeroFotoArquivadaEMidiaDaConversa() throws {
        let linha = #"{"t":"conversas","lista":[{"id":"5@s.whatsapp.net","nome":"Ana","grupo":false,"naoLidas":1,"ultima":"2026-11-12T13:00:00Z","arquivada":true,"numero":"5544999990000","foto":"0123456789abcdef.jpg","mensagens":[{"de":"","texto":"Foto","hora":"2026-11-12T13:00:00Z","id":"M1","tipo":"foto","midia":true},{"de":"","texto":"Áudio único","hora":"2026-11-12T13:01:00Z","id":"M2","tipo":"audio","unica":true}]}]}"#
        guard case .conversas(let c)? = LinhaDoAjudante.interpretar(linha) else { return XCTFail("não leu") }
        XCTAssertEqual(c[0].arquivada, true)
        XCTAssertEqual(c[0].numero, "5544999990000")
        XCTAssertEqual(c[0].foto, "0123456789abcdef.jpg")
        XCTAssertEqual(c[0].mensagens[0].tipo, "foto")
        XCTAssertEqual(c[0].mensagens[0].midia, true)
        XCTAssertEqual(c[0].mensagens[1].unica, true)
        XCTAssertNil(c[0].mensagens[1].midia)
    }

    func testArquivadaNaoContaNoTotalMasContinuaNaLista() throws {
        let linha = #"{"t":"conversas","lista":[{"id":"a","nome":"Ana","grupo":false,"naoLidas":2,"ultima":"2026-11-12T13:00:00Z","mensagens":[]},{"id":"b","nome":"Bia","grupo":false,"naoLidas":5,"ultima":"2026-11-12T13:00:00Z","arquivada":true,"mensagens":[]}]}"#
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(linha)'; cat >/dev/null")
        defer { p.desligar() }
        p.garantirLigada()
        esperar("conversas") { p.atual.conversas.count == 2 }
        let l = p.ler()
        XCTAssertEqual(l.valor?.resumo.total, 2, "arquivada não entra na conta nem no selo")
        XCTAssertEqual(l.valor?.resumo.conversas, 1)
        XCTAssertEqual(l.valor?.conversas.count, 2, "mas a arquivada tem de chegar ao painel, que a mostra no filtro Arquivadas")
    }

    func testConversaSemNomeNuncaVaiEmBranco() throws {
        let linha = #"{"t":"conversas","lista":[{"id":"1@lid","nome":"","grupo":false,"naoLidas":1,"ultima":"2026-11-12T13:00:00Z","mensagens":[]},{"id":"g","nome":" ","grupo":true,"naoLidas":1,"ultima":"2026-11-12T13:00:00Z","mensagens":[]}]}"#
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(linha)'; cat >/dev/null")
        defer { p.desligar() }
        p.garantirLigada()
        esperar("conversas") { p.atual.conversas.count == 2 }
        XCTAssertEqual(p.ler().valor?.conversas.map(\.nome), ["Contato", "Grupo"])
    }

    func testVersaoSobeQuandoOAjudanteEmpurraLista() throws {
        let p = try ponte("echo '{\"t\":\"fase\",\"fase\":\"conectado\",\"detalhe\":\"\"}'; echo '\(Self.conversas)'; cat >/dev/null")
        defer { p.desligar() }
        let antes = p.versao
        p.garantirLigada()
        esperar("conversas") { p.atual.conversas.count == 2 }
        XCTAssertGreaterThan(p.versao, antes)
    }

    func testAgregadorNaoEsperaOPrazoDoCacheQuandoChegaMensagemNova() {
        let versao = ContadorQr(0)
        let lidas = ContadorQr(0)
        let fontes = Fontes(
            sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
            whatsapp: { lidas.valor += 1; return Leitura(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 0, conversas: 0), conversas: []), aviso: nil) },
            seloWhatsApp: { nil }, versaoWhatsApp: { versao.valor },
            spotify: { _ in Leitura(valor: nil, aviso: nil) }, capa: { nil }, agenda: { _ in Leitura(valor: nil, aviso: nil) }, acesas: { _ in [] })
        let a = Agregador(fontes: fontes)
        let agora = Date()
        _ = a.conversasWhatsApp(agora: agora)
        _ = a.conversasWhatsApp(agora: agora.addingTimeInterval(1))
        XCTAssertEqual(lidas.valor, 1, "sem novidade, vale o cache")
        versao.valor = 1
        _ = a.conversasWhatsApp(agora: agora.addingTimeInterval(1))
        XCTAssertEqual(lidas.valor, 2, "lista nova do ajudante não espera os 5 s do cache")
    }

    func testFotoSoDeArquivoComNomeDeHash() throws {
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try FileManager.default.createDirectory(at: sessao.appendingPathComponent("fotos"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: sessao.appendingPathComponent("fotos/0123456789abcdef.jpg"))
        try Data([9]).write(to: sessao.appendingPathComponent("segredo.jpg"))
        let p = PonteWhatsAppQR(executavel: nil, pasta: sessao)
        XCTAssertEqual(p.foto(arquivo: "0123456789abcdef.jpg"), MidiaBaixada(tipo: "image/jpeg", dados: Data([1, 2, 3])))
        for ruim in ["../segredo.jpg", "..%2Fsegredo.jpg", "fotos/0123456789abcdef.jpg", "0123456789abcdef.png", "ABCDEF.jpg", "", "0123456789abcdef.jpg/../../x"] {
            XCTAssertNil(p.foto(arquivo: ruim), ruim)
        }
    }

    func testPedeAMidiaAoAjudanteELeOArquivoBaixado() throws {
        // O ajudante de mentira lê o pedido, grava o arquivo em <pasta>/midia e responde com a linha.
        let p = try ponte(#"""
        mkdir -p "$2/midia"; echo '{"t":"fase","fase":"conectado","detalhe":""}'
        while read l; do
          req=$(echo "$l" | sed 's/.*"req":"\([^"]*\)".*/\1/')
          printf 'oi' > "$2/midia/0123456789abcdef.ogg"
          echo "{\"t\":\"midia\",\"req\":\"$req\",\"arquivo\":\"0123456789abcdef.ogg\",\"tipo\":\"audio/ogg; codecs=opus\"}"
        done
        """#)
        defer { p.desligar() }
        p.garantirLigada()
        esperar("conectou") { p.atual.fase == .conectado }
        XCTAssertEqual(p.midia(chat: "a@s.whatsapp.net", id: "M1", limite: 5), .pronta(MidiaBaixada(tipo: "audio/ogg; codecs=opus", dados: Data("oi".utf8))))
    }

    func testMidiaQueOAjudanteRecusaVoltaComOMotivo() throws {
        let p = try ponte(#"""
        echo '{"t":"fase","fase":"conectado","detalhe":""}'
        while read l; do
          req=$(echo "$l" | sed 's/.*"req":"\([^"]*\)".*/\1/')
          echo "{\"t\":\"midia\",\"req\":\"$req\",\"erro\":\"Arquivo grande demais para abrir aqui.\"}"
        done
        """#)
        defer { p.desligar() }
        p.garantirLigada()
        esperar("conectou") { p.atual.fase == .conectado }
        XCTAssertEqual(p.midia(chat: "a", id: "M1", limite: 5), .erro("Arquivo grande demais para abrir aqui."))
    }

    func testMidiaSemConexaoNaoEspera() {
        let p = PonteWhatsAppQR(executavel: nil, pasta: pasta)
        XCTAssertEqual(p.midia(chat: "a", id: "M1", limite: 5), .erro("O WhatsApp por QR não está conectado agora."))
    }

    func testMidiaComArquivoOuTipoForaDoPadraoEMaterialRecusado() throws {
        let sessao = pasta.appendingPathComponent("sessao", isDirectory: true)
        try FileManager.default.createDirectory(at: sessao.appendingPathComponent("midia"), withIntermediateDirectories: true)
        try Data([1]).write(to: sessao.appendingPathComponent("midia/0123456789abcdef.jpg"))
        XCTAssertEqual(PonteWhatsAppQR.lerMidia(pasta: sessao, arquivo: "0123456789abcdef.jpg", tipo: "image/jpeg", erro: nil), .pronta(MidiaBaixada(tipo: "image/jpeg", dados: Data([1]))))
        for (arq, tipo) in [("../x.jpg", "image/jpeg"), ("0123456789abcdef.jpg", "text/html"), ("0123456789abcdef.jpg", "image/jpeg\r\nX: y")] {
            guard case .erro = PonteWhatsAppQR.lerMidia(pasta: sessao, arquivo: arq, tipo: tipo, erro: nil) else { return XCTFail("aceitou \(arq) \(tipo)") }
        }
    }
}

private final class Lista: @unchecked Sendable {
    private let t = NSLock()
    private var v: [String] = []
    func add(_ s: String) { t.lock(); v.append(s); t.unlock() }
    var itens: [String] { t.lock(); defer { t.unlock() }; return v }
}

private final class Caixa: @unchecked Sendable {
    var valor: ConfigWhatsApp
    init(_ v: ConfigWhatsApp) { valor = v }
}

private final class ContadorQr: @unchecked Sendable {
    private let trava = NSLock()
    private var v: Int
    init(_ v: Int) { self.v = v }
    var valor: Int {
        get { trava.lock(); defer { trava.unlock() }; return v }
        set { trava.lock(); v = newValue; trava.unlock() }
    }
}
