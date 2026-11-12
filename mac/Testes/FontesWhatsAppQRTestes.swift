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
