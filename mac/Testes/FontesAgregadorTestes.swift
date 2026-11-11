import XCTest
@testable import Nucleo

final class FontesAgregadorTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)

    func tecla(_ id: String, tipo: String = "app", valor: String = "x", estado: String? = nil) -> Tecla {
        Tecla(id: id, nome: id, tipo: tipo, valor: valor, estado: estado, icone: nil)
    }

    /// Fontes de exemplo que contam quantas vezes foram chamadas.
    func fontes(whats: Leitura<WhatsAppDados?>? = nil, selo: Int? = nil, agenda: ResumoAgenda? = ResumoAgenda(permissao: true, proximo: nil),
                chamadas: Contador = Contador()) -> Fontes {
        let w = whats ?? Leitura(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 5, conversas: 2), conversas: []), aviso: nil)
        return Fontes(
            sessoes: { Leitura(valor: [Sessao(id: "s", nome: "n", projeto: "p", pergunta: "?", desde: "2026-11-10T10:00:00Z")], aviso: nil) },
            uso: { contas, _ in Leitura(valor: contas.map { UsoConta(id: $0.id, nome: $0.nome, conta: $0.conta, semana: 40, renova: nil) }, aviso: nil) },
            whatsapp: { chamadas.somar(); return w },
            seloWhatsApp: { selo },
            spotify: { _ in Leitura(valor: EstadoSpotify(tocando: true, faixa: "f", artista: "a", posicao: 1, duracao: 2, capaId: "c", cores: []), aviso: nil) },
            capa: { nil },
            agenda: { _ in Leitura(valor: agenda, aviso: nil) },
            acesas: { teclas in teclas.filter { $0.estado == "sim" }.map(\.id) }
        )
    }

    func testMontaOEstadoComTudoLigado() {
        let cfg = config(perfil: [tecla("whats", valor: "WhatsApp"), tecla("luz", tipo: "tecla", valor: "cmd+k", estado: "sim"), tecla("lamp", tipo: "tecla", valor: "cmd+j", estado: "nao")],
                         contas: [ContaIA(id: "codex", nome: "Codex", conta: "pro")])
        let e = Agregador(fontes: fontes()).estado(config: cfg, agora: agora)
        XCTAssertEqual(e.perfilAtivo, "p")
        XCTAssertEqual(e.nomeMac, "Mac de teste")
        XCTAssertEqual(e.agora, Datas.iso(agora))
        XCTAssertEqual(e.spotify?.faixa, "f")
        XCTAssertEqual(e.sessoes.count, 1)
        XCTAssertEqual(e.uso.map(\.semana), [40])
        XCTAssertEqual(e.whatsapp, ResumoWhatsApp(total: 5, conversas: 2))
        XCTAssertEqual(e.acesas, ["luz"])
        XCTAssertEqual(e.selos, ["whats": "5"])
        XCTAssertEqual(e.avisos, [])
    }

    func testBlocosDesligadosEscondemOCampoENemLeemAFonte() {
        let chamadas = Contador()
        var blocos = Blocos()
        blocos.spotify = false; blocos.whatsapp = false; blocos.sessoes = false; blocos.uso = false; blocos.agenda = false
        let cfg = config(perfil: [tecla("whats", valor: "WhatsApp")], blocos: blocos, contas: [ContaIA(id: "c", nome: "Codex", conta: "p")])
        let e = Agregador(fontes: fontes(chamadas: chamadas)).estado(config: cfg, agora: agora)
        XCTAssertNil(e.spotify); XCTAssertNil(e.whatsapp); XCTAssertNil(e.agenda)
        XCTAssertEqual(e.sessoes, []); XCTAssertEqual(e.uso, [])
        XCTAssertEqual(e.selos, [:])
        XCTAssertEqual(chamadas.valor, 0)
        XCTAssertEqual(e.blocos, blocos)
    }

    func testAgendaSemPermissaoPoeExclamacaoNaTeclaDoCalendario() {
        let cfg = config(perfil: [tecla("cal", valor: "Calendar"), tecla("outra", valor: "Notes")])
        let e = Agregador(fontes: fontes(agenda: ResumoAgenda(permissao: false, proximo: nil))).estado(config: cfg, agora: agora)
        XCTAssertEqual(e.selos, ["cal": "!"])
        XCTAssertEqual(e.agenda?.permissao, false)
    }

    func testBancoDoWhatsAppFechadoUsaOSeloDoDockEJuntaOAviso() {
        let aviso = Aviso(fonte: "whatsapp", texto: "Libere o Acesso Total ao Disco.")
        let cfg = config(perfil: [tecla("whats", valor: "whatsapp")])
        let e = Agregador(fontes: fontes(whats: Leitura(valor: nil, aviso: aviso), selo: 7)).estado(config: cfg, agora: agora)
        XCTAssertEqual(e.whatsapp?.total, 7)
        XCTAssertEqual(e.selos, ["whats": "7"])
        XCTAssertEqual(e.avisos, [aviso])
    }

    func testSemBancoNemSeloOWhatsAppFicaNilComAviso() {
        let aviso = Aviso(fonte: "whatsapp", texto: "x")
        let e = Agregador(fontes: fontes(whats: Leitura(valor: nil, aviso: aviso), selo: nil)).estado(config: config(perfil: [tecla("whats", valor: "WhatsApp")]), agora: agora)
        XCTAssertNil(e.whatsapp)
        XCTAssertEqual(e.selos, [:])
        XCTAssertEqual(e.avisos, [aviso])
    }

    func testUmaFonteQueFalhaNaoDerrubaAsOutras() {
        var f = fontes()
        f.spotify = { _ in Leitura(valor: nil, aviso: Aviso(fonte: "spotify", texto: "falhou")) }
        let e = Agregador(fontes: f).estado(config: config(perfil: []), agora: agora)
        XCTAssertNil(e.spotify)
        XCTAssertEqual(e.avisos, [Aviso(fonte: "spotify", texto: "falhou")])
        XCTAssertEqual(e.sessoes.count, 1)
        XCTAssertEqual(e.whatsapp?.total, 5)
    }

    func testSeloAcimaDe99() {
        let w = Leitura<WhatsAppDados?>(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 258, conversas: 31), conversas: []), aviso: nil)
        let e = Agregador(fontes: fontes(whats: w)).estado(config: config(perfil: [tecla("whats", valor: "WhatsApp")]), agora: agora)
        XCTAssertEqual(e.selos["whats"], "99+")
    }

    func testPerfilAtivoInexistenteViraAvisoEOrestoSegue() {
        var cfg = config(perfil: [tecla("a")])
        cfg.perfilAtivo = "sumiu"
        let e = Agregador(fontes: fontes()).estado(config: cfg, agora: agora)
        XCTAssertEqual(e.acesas, [])
        XCTAssertEqual(e.avisos.map(\.fonte), ["teclas"])
        XCTAssertEqual(e.spotify?.faixa, "f")
    }

    func testFontesLentasFicamEmCacheEVencem() {
        let chamadas = Contador()
        let ag = Agregador(fontes: fontes(chamadas: chamadas))
        let cfg = config(perfil: [])
        for i in 0..<4 { _ = ag.estado(config: cfg, agora: agora.addingTimeInterval(Double(i))) }
        XCTAssertEqual(chamadas.valor, 1)
        _ = ag.estado(config: cfg, agora: agora.addingTimeInterval(6))
        XCTAssertEqual(chamadas.valor, 2)
    }

    func testRotasDeListaUsamAsMesmasFontes() {
        let conversa = ConversaWhatsApp(id: "1", nome: "Ana", grupo: false, naoLidas: 1, ultima: "", mensagens: [])
        let w = Leitura<WhatsAppDados?>(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 1, conversas: 1), conversas: [conversa]), aviso: nil)
        let ag = Agregador(fontes: fontes(whats: w))
        XCTAssertEqual(ag.conversasWhatsApp(agora: agora), [conversa])
        XCTAssertEqual(ag.sessoes(agora: agora).count, 1)
    }

    // MARK: fonte lenta não segura a conexão

    /// Fontes em que `lenta` demora `segundos` a partir da segunda leitura (a primeira, a fria, é rápida).
    private func fontesComLentidao(segundos: TimeInterval, em campo: String, selo: Int? = nil) -> (Fontes, Contador) {
        let chamadas = Contador()
        var f = fontes(whats: campo == "selo" ? Leitura(valor: nil, aviso: nil) : nil, selo: selo)
        let w = Leitura<WhatsAppDados?>(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 5, conversas: 2), conversas: []), aviso: nil)
        switch campo {
        case "whatsapp":
            f.whatsapp = { chamadas.somar(); if chamadas.valor > 1 { Thread.sleep(forTimeInterval: segundos) }; return w }
        case "spotify":
            let sp = Leitura<EstadoSpotify?>(valor: EstadoSpotify(tocando: true, faixa: "f", artista: "a", posicao: 1, duracao: 2, capaId: "c", cores: []), aviso: nil)
            f.spotify = { _ in chamadas.somar(); if chamadas.valor > 1 { Thread.sleep(forTimeInterval: segundos) }; return sp }
        default:
            f.seloWhatsApp = { chamadas.somar(); Thread.sleep(forTimeInterval: segundos); return selo }
        }
        return (f, chamadas)
    }

    /// Defeito: o WhatsApp venceu e a leitura nova leva 1,5 s. O estado esperava a leitura inteira (até o limite de 2 s) e o
    /// painel, com tempo limite curto, contava isso como queda. Agora devolve o valor guardado em meio segundo.
    func testFonteLentaComValorGuardadoNaoSeguraOEstado() {
        let (f, chamadas) = fontesComLentidao(segundos: 1.5, em: "whatsapp")
        let ag = Agregador(fontes: f)
        let cfg = config(perfil: [])
        let frio = ag.estado(config: cfg, agora: agora)
        XCTAssertEqual(frio.whatsapp?.total, 5)
        let t0 = Date()
        let vencido = ag.estado(config: cfg, agora: agora.addingTimeInterval(6))
        let gasto = Date().timeIntervalSince(t0)
        XCTAssertLessThan(gasto, 1.0, "o estado esperou a fonte lenta (\(gasto) s)")
        XCTAssertEqual(vencido.whatsapp?.total, 5, "sem a leitura nova, vale o último valor bom")
        XCTAssertEqual(chamadas.valor, 2, "a leitura nova foi pedida")
    }

    /// A leitura que ficou para trás termina sozinha e o pedido seguinte já vê o valor novo.
    func testLeituraEmSegundoPlanoTerminaEOProximoPedidoVeOValorNovo() {
        let chamadas = Contador()
        var f = fontes()
        f.whatsapp = {
            chamadas.somar()
            let n = chamadas.valor
            if n > 1 { Thread.sleep(forTimeInterval: 0.9) }
            return Leitura(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: n * 10, conversas: 1), conversas: []), aviso: nil)
        }
        let ag = Agregador(fontes: f)
        let cfg = config(perfil: [])
        XCTAssertEqual(ag.estado(config: cfg, agora: agora).whatsapp?.total, 10)
        XCTAssertEqual(ag.estado(config: cfg, agora: agora.addingTimeInterval(6)).whatsapp?.total, 10, "a leitura nova ainda anda")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(ag.estado(config: cfg, agora: agora.addingTimeInterval(7)).whatsapp?.total, 20, "terminou em segundo plano")
        XCTAssertEqual(chamadas.valor, 2, "nenhuma leitura empilhada")
    }

    /// O Spotify é lido a cada pedido. Se o osascript trava, o painel segue com a última faixa em vez de esperar.
    func testSpotifyLentoNaoSeguraOEstado() {
        let (f, _) = fontesComLentidao(segundos: 1.5, em: "spotify")
        let ag = Agregador(fontes: f)
        let cfg = config(perfil: [])
        XCTAssertEqual(ag.estado(config: cfg, agora: agora).spotify?.faixa, "f")
        let t0 = Date()
        let e = ag.estado(config: cfg, agora: agora.addingTimeInterval(1))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
        XCTAssertEqual(e.spotify?.faixa, "f")
    }

    /// Defeito: com o banco do WhatsApp fechado, o selo do Dock era lido depois do prazo das fontes, sem limite nenhum.
    /// Um lsappinfo lento (o Mac acordando) somava segundos ao estado.
    func testSeloDoDockLentoNaoPassaDoPrazoDasFontes() {
        let (f, _) = fontesComLentidao(segundos: 3, em: "selo", selo: 7)
        let ag = Agregador(fontes: f, limite: 0.5)
        let t0 = Date()
        let e = ag.estado(config: config(perfil: []), agora: agora)
        let gasto = Date().timeIntervalSince(t0)
        XCTAssertLessThan(gasto, 1.5, "o estado esperou o selo do Dock (\(gasto) s)")
        XCTAssertNil(e.whatsapp, "sem o selo a tempo, não há total para mostrar")
    }

    /// O selo que chegou a tempo continua valendo (o comportamento de antes, agora dentro do prazo).
    func testSeloDoDockRapidoContinuaDandoOTotal() {
        let (f, _) = fontesComLentidao(segundos: 0, em: "selo", selo: 7)
        let e = Agregador(fontes: f).estado(config: config(perfil: []), agora: agora)
        XCTAssertEqual(e.whatsapp?.total, 7)
    }

    // MARK: tecla acesa

    func testTeclaAcesaRodaPeloExecutorEAcendeComStatusZero() {
        let ex = ExecutorFalso([("acordado", SaidaShell(status: 0, saida: "")), ("apagado", SaidaShell(status: 1, saida: ""))])
        let teclas = [tecla("a", estado: "echo acordado"), tecla("b", estado: "echo apagado"), tecla("c"), tecla("d", estado: "  ")]
        XCTAssertEqual(TeclasAcesas.ler(teclas, executor: ex), ["a"])
        XCTAssertEqual(ex.comandos.sorted(), ["echo acordado", "echo apagado"])
    }

    func testTeclaAcesaRodaEmParaleloEComTempoLimite() {
        let ex = ExecutorFalso([("rapido", SaidaShell(status: 0, saida: "")), ("lento", SaidaShell(status: 0, saida: ""))],
                               atraso: { $0.contains("lento") ? 3 : 0.5 })
        let teclas = [tecla("r1", estado: "rapido 1"), tecla("r2", estado: "rapido 2"), tecla("r3", estado: "rapido 3"), tecla("l", estado: "lento")]
        let t0 = Date()
        let acesas = TeclasAcesas.ler(teclas, executor: ex, limite: 1.5)
        let gasto = Date().timeIntervalSince(t0)
        // Os três rápidos (0,5 s cada) rodam juntos: se fosse em série daria 1,5 s só neles.
        XCTAssertEqual(acesas, ["r1", "r2", "r3"])
        XCTAssertLessThan(gasto, 2.5)
        XCTAssertGreaterThanOrEqual(gasto, 1.4)
    }

    func testSemNenhumEstadoNemRodaComando() {
        let ex = ExecutorFalso([])
        XCTAssertEqual(TeclasAcesas.ler([tecla("a")], executor: ex), [])
        XCTAssertEqual(ex.comandos, [])
    }
}
