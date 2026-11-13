import XCTest
@testable import Nucleo

/// Tudo com log inventado na hora (modelo-a, sessao-1): nenhum dado de conversa, conta ou pasta de verdade.
final class UsoDetalheTestes: XCTestCase {
    var utcCal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }
    // 13/11/2026, 15:00 em UTC
    let agora = Date(timeIntervalSince1970: 1_794_582_000)

    func claude(_ id: String?, req: String = "r1", quando: String, modelo: String = "claude-opus-5-5", entrada: Int = 10, saida: Int = 20,
                leitura: Int = 100, c5: Int = 5, c1: Int = 0, sessao: String? = nil) -> String {
        let sessaoTxt = sessao.map { #""sessionId":"\#($0)","# } ?? ""
        let idTxt = id.map { #""id":"\#($0)","# } ?? ""
        return #"{"type":"assistant",\#(sessaoTxt)"timestamp":"\#(quando)","requestId":"\#(req)","message":{\#(idTxt)"model":"\#(modelo)","usage":{"input_tokens":\#(entrada),"output_tokens":\#(saida),"cache_read_input_tokens":\#(leitura),"cache_creation_input_tokens":\#(c5 + c1),"cache_creation":{"ephemeral_5m_input_tokens":\#(c5),"ephemeral_1h_input_tokens":\#(c1)}}}}"#
    }

    func gravar(_ linhas: [String], em url: URL, anexar: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let texto = linhas.joined(separator: "\n") + "\n"
        if anexar, let h = try? FileHandle(forWritingTo: url) { try h.seekToEnd(); try h.write(contentsOf: Data(texto.utf8)); try h.close() }
        else { try Data(texto.utf8).write(to: url) }
    }

    func gasto(_ raiz: URL, cache: URL? = nil) -> GastoTokens {
        GastoTokens(raizClaude: raiz.appendingPathComponent("claude"), raizCodex: raiz.appendingPathComponent("codex"), pastaDeCache: cache)
    }

    // MARK: Claude

    func testClaudeSomaPorTipoEModeloEDeduplicaAMesmaResposta() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let a = raiz.appendingPathComponent("claude/p/sessao-1.jsonl")
        try gravar([
            claude("m1", quando: "2026-11-13T10:00:00.000Z"),
            claude("m1", quando: "2026-11-13T10:00:01.000Z"),                       // linha repetida do streaming: não soma de novo
            claude("m2", req: "r2", quando: "2026-11-13T11:00:00Z", modelo: "claude-sonnet-5-5", entrada: 1, saida: 2, leitura: 3, c5: 0, c1: 4),
            #"{"type":"user","timestamp":"2026-11-13T11:00:00Z","message":{"content":"oi"}}"#,
            claude("m3", req: "r3", quando: "2026-11-13T12:00:00Z", modelo: "<synthetic>"),
        ], em: a)
        let g = gasto(raiz); g.atualizar(agora: agora)
        let r = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.entrada, 11); XCTAssertEqual(r.saida, 22); XCTAssertEqual(r.cacheLeitura, 103); XCTAssertEqual(r.cacheEscrita, 9)
        XCTAssertEqual(r.total, 145); XCTAssertEqual(r.turnos, 2); XCTAssertEqual(r.sessoes, 1)
        XCTAssertEqual(r.modelos.map(\.nome), ["Opus 5.5", "Sonnet 5.5"])
        XCTAssertEqual(r.modelos.map(\.parte).reduce(0, +), 100)
    }

    func testClaudeSemIdNaoDeduplica() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([claude(nil, quando: "2026-11-13T10:00:00Z"), claude(nil, quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 2)
    }

    func testRespostaRepetidaEmOutroArquivoContaUmaVez() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        // sessão retomada: o arquivo novo copia as respostas do antigo
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"))
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z"), claude("m2", req: "r2", quando: "2026-11-13T10:05:00Z")], em: raiz.appendingPathComponent("claude/b.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let r = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.turnos, 2); XCTAssertEqual(r.sessoes, 2)
    }

    func testSubagenteContaNaSessaoQueOChamou() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z", sessao: "sessao-1")], em: raiz.appendingPathComponent("claude/p/sessao-1.jsonl"))
        try gravar([claude("m2", req: "r2", quando: "2026-11-13T10:05:00Z", sessao: "sessao-1")], em: raiz.appendingPathComponent("claude/p/sessao-1/subagents/agente-x.jsonl"))
        try gravar([claude("m3", req: "r3", quando: "2026-11-13T10:10:00Z", sessao: "sessao-2")], em: raiz.appendingPathComponent("claude/p/sessao-2.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let r = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.turnos, 3); XCTAssertEqual(r.sessoes, 2, "o subagente não é outra sessão")
    }

    func testPrecoDoOpus46EmDianteSegueOdo45() {
        for m in ["claude-opus-4-6", "claude-opus-4-7-20260101", "claude-opus-4-8"] {
            XCTAssertEqual(PrecosModelos.preco(m)?.entrada, 5, m); XCTAssertEqual(PrecosModelos.preco(m)?.saida, 25, m)
        }
        XCTAssertEqual(PrecosModelos.preco("claude-opus-4-1")?.entrada, 15, "o 4 e o 4.1 seguem a 15 e 75")
    }

    func testPrimeiraVarreduraGravaCacheParcialSemDizerQueTerminou() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let cache = raiz.appendingPathComponent("cache")
        for i in 0..<12 { try gravar([claude("m\(i)", req: "r\(i)", quando: "2026-11-13T10:00:00Z", sessao: "s\(i)")], em: raiz.appendingPathComponent("claude/p/s\(i).jsonl")) }
        let g = gasto(raiz, cache: cache); g.intervaloDeGravacao = 0
        var visto = false
        g.aoGravarParcial = {
            guard !visto else { return }; visto = true
            let outro = self.gasto(raiz, cache: cache); outro.carregarSemVarrer()
            XCTAssertGreaterThan(outro.consultar(.claude, periodo: .dia, agora: self.agora, calendario: self.utcCal).turnos, 0, "o que já foi lido está no disco")
            XCTAssertNil(outro.atualizadoEm, "o cache parcial não diz que a varredura terminou")
        }
        g.atualizar(agora: agora)
        XCTAssertTrue(visto, "gravou um cache parcial no meio da varredura")
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 12)
    }

    func testLeituraIncrementalSoLeOTrechoNovo() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let a = raiz.appendingPathComponent("claude/a.jsonl")
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: a)
        let g = gasto(raiz); g.atualizar(agora: agora)
        g.atualizar(agora: agora) // nada mudou: o total não pode dobrar
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 1)
        try gravar([claude("m2", req: "r2", quando: "2026-11-13T11:00:00Z")], em: a, anexar: true)
        g.atualizar(agora: agora)
        let r = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.turnos, 2); XCTAssertEqual(r.total, 2 * 135)
    }

    func testLinhaPelaMetadeFicaParaAProximaLeitura() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let a = raiz.appendingPathComponent("claude/a.jsonl")
        let inteira = claude("m1", quando: "2026-11-13T10:00:00Z")
        try FileManager.default.createDirectory(at: a.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(inteira.prefix(40).utf8).write(to: a) // o Claude ainda está escrevendo a linha
        let g = gasto(raiz); g.atualizar(agora: agora)
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 0)
        try Data((inteira + "\n").utf8).write(to: a)
        g.atualizar(agora: agora)
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 1)
    }

    func testPeriodosDiaSemanaEMesComGraficoPorBarra() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([
            claude("a", req: "a", quando: "2026-11-13T09:30:00Z", entrada: 0, saida: 100, leitura: 0, c5: 0),   // hoje, 9h
            claude("b", req: "b", quando: "2026-11-12T23:30:00Z", entrada: 0, saida: 10, leitura: 0, c5: 0),   // ontem
            claude("c", req: "c", quando: "2026-11-07T10:00:00Z", entrada: 0, saida: 1, leitura: 0, c5: 0),    // 6 dias atrás: ainda na semana
            claude("d", req: "d", quando: "2026-11-06T10:00:00Z", entrada: 0, saida: 1000, leitura: 0, c5: 0), // 7 dias atrás: só no mês
            claude("e", req: "e", quando: "2026-10-15T10:00:00Z", entrada: 0, saida: 5000, leitura: 0, c5: 0), // 29 dias atrás: no mês
            claude("f", req: "f", quando: "2026-10-14T10:00:00Z", entrada: 0, saida: 99999, leitura: 0, c5: 0), // 30 dias atrás: fora
        ], em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let dia = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(dia.total, 100); XCTAssertEqual(dia.serie.count, 24); XCTAssertEqual(dia.serie[9], 100)
        let sem = g.consultar(.claude, periodo: .semana, agora: agora, calendario: utcCal)
        XCTAssertEqual(sem.total, 111); XCTAssertEqual(sem.serie, [1, 0, 0, 0, 0, 10, 100])
        let mes = g.consultar(.claude, periodo: .mes, agora: agora, calendario: utcCal)
        XCTAssertEqual(mes.total, 6111); XCTAssertEqual(mes.serie.count, 30)
        XCTAssertEqual(mes.serie[0], 5000); XCTAssertEqual(mes.serie[29], 100)
    }

    func testDiaSegueOFusoDoMacENaoOUTC() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        // 02:00 UTC de 13/11 ainda é 23:00 de 12/11 em Brasília
        try gravar([claude("a", quando: "2026-11-13T02:00:00Z", entrada: 0, saida: 7, leitura: 0, c5: 0)], em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        var br = Calendar(identifier: .gregorian); br.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: br).total, 0)
        XCTAssertEqual(g.consultar(.claude, periodo: .semana, agora: agora, calendario: br).serie[5], 7)
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).total, 7)
    }

    func testArquivoVelhoDemaisNemEAberto() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let a = raiz.appendingPathComponent("claude/velho.jsonl")
        try gravar([claude("a", quando: "2026-11-12T10:00:00Z")], em: a)
        try FileManager.default.setAttributes([.modificationDate: agora.addingTimeInterval(-40 * 86_400)], ofItemAtPath: a.path)
        let g = gasto(raiz); g.atualizar(agora: agora)
        XCTAssertEqual(g.consultar(.claude, periodo: .mes, agora: agora, calendario: utcCal).turnos, 0)
    }

    // MARK: Codex

    func testCodexSoSomaQuandoOTotalCresceEUsaOModeloDoTurno() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        func conta(_ q: String, total: Int, entrada: Int, lido: Int, saida: Int) -> String {
            #"{"timestamp":"\#(q)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(total)},"last_token_usage":{"input_tokens":\#(entrada),"cached_input_tokens":\#(lido),"output_tokens":\#(saida),"reasoning_output_tokens":5,"total_tokens":\#(entrada + saida)}},"rate_limits":null}}"#
        }
        try gravar([
            #"{"timestamp":"2026-11-13T09:00:00Z","type":"turn_context","payload":{"model":"gpt-5.5-codex"}}"#,
            conta("2026-11-13T09:01:00Z", total: 1100, entrada: 1000, lido: 600, saida: 100),
            conta("2026-11-13T09:01:01Z", total: 1100, entrada: 1000, lido: 600, saida: 100),   // repetido: o total não cresceu
            #"{"timestamp":"2026-11-13T09:02:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
            conta("2026-11-13T09:03:00Z", total: 1500, entrada: 300, lido: 0, saida: 100),
        ], em: raiz.appendingPathComponent("codex/2026/11/13/sessao-1.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let r = g.consultar(.codex, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.entrada, 700); XCTAssertEqual(r.cacheLeitura, 600); XCTAssertEqual(r.saida, 200); XCTAssertEqual(r.turnos, 2)
        XCTAssertEqual(r.modelos.first?.nome, "GPT-5.5-codex")
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).total, 0)
    }

    func testCodexLeAJanelaCurtaEASemanalDoMesmoEvento() {
        let linha = #"{"timestamp":"2026-11-13T14:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1794600000},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1795000000}}}}"#
        let j = UsoCodex.parseJanelas(linha + "\n")
        XCTAssertEqual(j.map(\.minutos), [300, 10080])
        XCTAssertEqual(j.map(\.percentual), [40, 12])
        XCTAssertEqual(j[0].medidoEm, Datas.ler("2026-11-13T14:00:00Z"))
        XCTAssertEqual(UsoCodex.parse(linha)?.percentual, 12, "a leitura da semana que já existia não muda")
        XCTAssertTrue(UsoCodex.parseJanelas("lixo").isEmpty)
    }

    // MARK: Custo, nome e ritmo

    func testCustoEstimadoEModeloSemPrecoFicaSemDolar() throws {
        let c = Contagem(entrada: 1_000_000, saida: 1_000_000, leitura: 1_000_000, escrita5m: 1_000_000, escrita1h: 1_000_000)
        // Opus 5: entrada 4, saída 20, leitura 0,4, escrita 5 min 5, escrita 1 h 8
        XCTAssertEqual(PrecosModelos.custo(modelo: "claude-opus-5-5-20261001", c)!, 37.4, accuracy: 0.0001)
        XCTAssertNil(PrecosModelos.custo(modelo: "modelo-a", c))
        XCTAssertEqual(PrecosModelos.preco("claude-opus-4-5-20251101")?.entrada, 5, "o prefixo mais longo vence")
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([claude("a", quando: "2026-11-13T10:00:00Z", modelo: "claude-opus-5-5", entrada: 1_000_000, saida: 0, leitura: 0, c5: 0),
                    claude("b", req: "b", quando: "2026-11-13T10:00:00Z", modelo: "modelo-a", entrada: 50, saida: 0, leitura: 0, c5: 0)],
                   em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let r = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal)
        XCTAssertEqual(r.custo, 4.0); XCTAssertEqual(r.custoParcial, true)
        XCTAssertNil(r.modelos.first { $0.nome == "modelo-a" }?.custo)
    }

    func testRotulosCurtosDeModelo() {
        XCTAssertEqual(PrecosModelos.rotulo("claude-opus-5-5-20261001"), "Opus 5.5")
        XCTAssertEqual(PrecosModelos.rotulo("claude-sonnet-4-5"), "Sonnet 4.5")
        XCTAssertEqual(PrecosModelos.rotulo("claude-3-5-haiku-20241022"), "Haiku 3.5")
        XCTAssertEqual(PrecosModelos.rotulo("claude-opus-4-1-20250805"), "Opus 4.1")
        XCTAssertEqual(PrecosModelos.rotulo("modelo-a"), "modelo-a")
    }

    func testSeisModelosViramCincoComOutros() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let linhas = (1...7).map { claude("m\($0)", req: "r\($0)", quando: "2026-11-13T10:00:00Z", modelo: "modelo-\($0)", entrada: $0 * 10, saida: 0, leitura: 0, c5: 0) }
        try gravar(linhas, em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let m = g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).modelos
        XCTAssertEqual(m.count, 5); XCTAssertEqual(m.last?.nome, "Outros"); XCTAssertEqual(m.first?.nome, "modelo-7")
        XCTAssertEqual(m.map(\.tokens).reduce(0, +), 280)
    }

    func testRitmoMarcaOndeDeviaEstarEAvisaDoQueAcabaAntesOuSobra() {
        let renova = agora.addingTimeInterval(3.5 * 86_400) // metade da semana
        var r = RitmoDeUso.calcular(percentual: 80, renova: renova, agora: agora, duracao: 7 * 86_400)!
        XCTAssertEqual(r.esperado, 50); XCTAssertEqual(r.projecao, 160); XCTAssertEqual(r.situacao, "rapido")
        r = RitmoDeUso.calcular(percentual: 40, renova: renova, agora: agora, duracao: 7 * 86_400)!
        XCTAssertEqual(r.projecao, 80); XCTAssertNil(r.situacao)
        r = RitmoDeUso.calcular(percentual: 30, renova: agora.addingTimeInterval(3 * 3600), agora: agora, duracao: 7 * 86_400)!
        XCTAssertEqual(r.situacao, "sobra")
        XCTAssertNil(RitmoDeUso.calcular(percentual: 5, renova: agora.addingTimeInterval(-1), agora: agora, duracao: 7 * 86_400), "janela que já renovou não tem ritmo")
        XCTAssertNil(RitmoDeUso.calcular(percentual: 5, renova: agora.addingTimeInterval(7 * 86_400 - 60), agora: agora, duracao: 7 * 86_400)?.projecao, "no começo da janela não se projeta")
    }

    // MARK: Cache em disco e privacidade

    func testCacheEmDiscoVoltaSemVarrerENaoGuardaCaminhoNemTexto() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let cache = raiz.appendingPathComponent("cache")
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/projeto-secreto/sessao-1.jsonl"))
        gasto(raiz, cache: cache).atualizar(agora: agora)
        try FileManager.default.removeItem(at: raiz.appendingPathComponent("claude"))
        let outro = gasto(raiz, cache: cache); outro.carregarSemVarrer()
        XCTAssertEqual(outro.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 1)
        XCTAssertFalse(outro.calculando)
        let bruto = try String(contentsOf: cache.appendingPathComponent("uso-gasto.json"), encoding: .utf8)
        XCTAssertFalse(bruto.contains("projeto-secreto")); XCTAssertFalse(bruto.contains(raiz.path)); XCTAssertFalse(bruto.contains("sessao-1"))
        XCTAssertFalse(bruto.contains("m1|"))
    }

    func testCacheNaoSomaDeNovoOQueJaFoiLido() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        let cache = raiz.appendingPathComponent("cache")
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"))
        gasto(raiz, cache: cache).atualizar(agora: agora)
        let outro = gasto(raiz, cache: cache); outro.atualizar(agora: agora)
        XCTAssertEqual(outro.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 1)
    }

    func testDispararNaoRodaDuasVezesEmUmMinutoENuncaTrava() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz)
        g.disparar(agora: agora)
        let t0 = Date()
        while g.atualizadoEm == nil, Date().timeIntervalSince(t0) < 5 { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertNotNil(g.atualizadoEm)
        try gravar([claude("m2", req: "r2", quando: "2026-11-13T10:10:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"), anexar: true)
        g.disparar(agora: agora.addingTimeInterval(30)) // menos de 60 s: não varre
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(g.consultar(.claude, periodo: .dia, agora: agora, calendario: utcCal).turnos, 1)
    }

    // MARK: Detalhe e rota

    func testDetalheJuntaJanelasGastoEOrdemDasContas() throws {
        let raiz = try pastaTemporaria(); defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar([claude("m1", quando: "2026-11-13T10:00:00Z")], em: raiz.appendingPathComponent("claude/a.jsonl"))
        let g = gasto(raiz); g.atualizar(agora: agora)
        let contas = [ContaIA(id: "c1", nome: "Claude", conta: "conta-a", perfil: "a"), ContaIA(id: "c2", nome: "Claude", conta: "conta-b", perfil: "b", mostrar: false),
                      ContaIA(id: "x1", nome: "Codex", conta: "conta-c")]
        let renova = agora.addingTimeInterval(3.5 * 86_400)
        let uso = [UsoConta(id: "c1", nome: "Claude", conta: "conta-a", semana: 80, renova: Datas.iso(renova, fuso: utc)),
                   UsoConta(id: "x1", nome: "Codex", conta: "conta-c", semana: nil, renova: nil)]
        let curta = UsoCodex.JanelaCodex(minutos: 300, percentual: 20, renova: agora.addingTimeInterval(3600), medidoEm: agora.addingTimeInterval(-120))
        let d = UsoDetalhe.montar(periodo: .semana, uso: uso, medicaoClaude: ["a": agora.addingTimeInterval(-300)], janelasCodex: [curta],
                                  contas: contas, gasto: g, agora: agora, calendario: utcCal)
        XCTAssertEqual(d.contas.map(\.id), ["c1", "x1"], "conta desligada no Mac não aparece")
        XCTAssertEqual(d.contas[0].janelas.first?.ritmo?.situacao, "rapido")
        XCTAssertEqual(d.contas[0].janelas.first?.medidoEm, "2026-11-13T14:55:00Z")
        XCTAssertNil(d.contas[0].gasto, "o log do Claude não diz a conta: o gasto fica no cartão do Mac")
        XCTAssertEqual(d.contas[1].janelas.map(\.rotulo), ["5 horas"], "semana sem medição não inventa número")
        XCTAssertEqual(d.claudeMac?.turnos, 1)
        XCTAssertEqual(d.ate, "2026-11-13"); XCTAssertEqual(d.periodo, "semana")
    }

    func testSemContaClaudeVisivelNaoHaCartaoDoClaudeNoMac() {
        let d = UsoDetalhe.montar(periodo: .dia, uso: [], medicaoClaude: [:], janelasCodex: [],
                                  contas: [ContaIA(id: "c1", nome: "Claude", conta: "a", mostrar: false)], gasto: nil, agora: agora, calendario: utcCal)
        XCTAssertTrue(d.contas.isEmpty); XCTAssertNil(d.claudeMac)
    }

    struct PaineisComUso: ProvedorPaineis {
        let base: PaineisFalsos
        let detalhe: @Sendable (PeriodoUso) -> DetalheUso
        func estado() -> Estado { base.estado() }
        func whatsapp() -> [ConversaWhatsApp] { [] }
        func agenda(de: String, dias: Int) -> [Evento] { [] }
        func sessoes() -> [Sessao] { [] }
        func capa() -> CapaAtual? { nil }
        func usoDetalhe(periodo: PeriodoUso) -> DetalheUso? { detalhe(periodo) }
    }

    func testRotaExigeCodigoCai_EmSemanaNoPeriodoInvalido_E404SemFonte() throws {
        var c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/uso/detalhe", codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/uso/detalhe").status, 404, "provedor sem o detalhe: a rota não existe")
        let anteriores = c.roteador
        c.roteador = Roteador(paineis: PaineisComUso(base: PaineisFalsos(registro: Registro())) { p in
            DetalheUso(periodo: p.rawValue, atualizadoEm: nil, calculando: nil, ate: "2026-11-13", contas: [], claudeMac: nil, aviso: nil)
        }, teclas: anteriores.teclas, spotify: anteriores.spotify, config: anteriores.config, pareamento: anteriores.pareamento,
           pagina: anteriores.pagina, rodizio: anteriores.rodizio)
        for (alvo, esperado) in [("?periodo=dia", "dia"), ("?periodo=mes", "mes"), ("?periodo=semana", "semana"), ("?periodo=ano", "semana"), ("", "semana")] {
            let r = c.pedir("GET", "/api/uso/detalhe" + alvo)
            XCTAssertEqual(r.status, 200); XCTAssertEqual((r.json as? [String: Any])?["periodo"] as? String, esperado)
        }
        XCTAssertEqual(c.pedir("POST", "/api/uso/detalhe").status, 405)
    }

    func testRespostaCheiaCabeNoBluetoothEnxuta() throws {
        // duas contas, mês inteiro, 5 modelos: o pior caso razoável tem que ficar pequeno
        let modelos = (1...5).map { ModeloDeUso(nome: "Modelo \($0)", tokens: 123_456_789, custo: 1234.56, parte: 20) }
        let g = GastoPeriodo(entrada: 123_456_789, saida: 123_456_789, cacheLeitura: 1_234_567_890, cacheEscrita: 123_456_789, total: 1_605_000_000, turnos: 12_345, sessoes: 321,
                             custo: 9999.99, custoParcial: true, serie: Array(repeating: 123_456_789, count: 30), modelos: modelos)
        let janelas = [JanelaDeLimite(rotulo: "Semana", percentual: 99, renova: "2026-11-13T15:00:00Z", medidoEm: "2026-11-13T15:00:00Z", ritmo: RitmoDeUso(esperado: 50, projecao: 150, situacao: "rapido")),
                       JanelaDeLimite(rotulo: "5 horas", percentual: 99, renova: "2026-11-13T15:00:00Z", medidoEm: "2026-11-13T15:00:00Z", ritmo: nil)]
        let d = DetalheUso(periodo: "mes", atualizadoEm: "2026-11-13T15:00:00Z", calculando: nil, ate: "2026-11-13",
                           contas: [ContaDetalhada(id: "a", nome: "Claude", conta: "conta-a", janelas: janelas, gasto: nil),
                                    ContaDetalhada(id: "b", nome: "Codex", conta: "conta-b", janelas: janelas, gasto: g)], claudeMac: g, aviso: nil)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let bytes = try enc.encode(d).count
        XCTAssertLessThan(bytes, 4_000, "a resposta do detalhe tem \(bytes) bytes")
        let json = String(decoding: try enc.encode(d), as: UTF8.self)
        XCTAssertFalse(json.contains("null"), "campo vazio não vai na resposta")
    }
}
