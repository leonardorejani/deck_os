import XCTest
@testable import Nucleo

/// Relógio de mentira que anda só quando o teste manda.
final class RelogioDeAprovacao: @unchecked Sendable {
    private let trava = NSLock()
    private var agora = Date(timeIntervalSince1970: 1_794_400_000)
    var data: Date { trava.lock(); defer { trava.unlock() }; return agora }
    func avancar(_ s: TimeInterval) { trava.lock(); agora = agora.addingTimeInterval(s); trava.unlock() }
}

final class AprovacoesTestes: XCTestCase {
    func nova() -> (Aprovacoes, RelogioDeAprovacao) {
        let r = RelogioDeAprovacao()
        return (Aprovacoes(relogio: { r.data }), r)
    }

    func abrir(_ a: Aprovacoes, prazo: TimeInterval = 90) -> Aprovacoes.Pendente? {
        a.abrir(projeto: "deck", ferramenta: "Bash", titulo: "Rodar um comando", resumo: "ls", prazo: prazo)
    }

    // MARK: Falha aberta

    func testSemIphoneRecenteNaoAbrePedido() {
        let (a, relogio) = nova()
        XCTAssertNil(abrir(a), "nunca falou com o iPhone")
        a.iphoneApareceu()
        XCTAssertNotNil(abrir(a))
        relogio.avancar(Aprovacoes.janelaDoIphone + 1)
        XCTAssertNil(abrir(a), "o iPhone sumiu há mais que a janela")
        XCTAssertFalse(a.iphoneRecente)
    }

    func testPrazoVencidoSemRespostaNaoDaDecisao() {
        let (a, _) = nova()
        a.iphoneApareceu()
        let p = abrir(a, prazo: 0.15)!
        XCTAssertEqual(a.pendentes().count, 1)
        let inicio = Date()
        XCTAssertNil(a.esperar(p), "ninguém respondeu: o terminal pergunta")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(inicio), 0.1)
        XCTAssertTrue(a.pendentes().isEmpty)
    }

    func testRespostaDepoisDoPrazoNaoValeNemCriaPedidoFantasma() {
        let (a, relogio) = nova()
        a.iphoneApareceu()
        let p = abrir(a, prazo: 30)!
        relogio.avancar(31)
        XCTAssertTrue(a.pendentes().isEmpty, "venceu: some da lista do iPhone")
        XCTAssertFalse(a.decidir(p.id, .permitir))
    }

    func testTerminalRespondeuAntesCancelaEOPedidoSome() {
        let (a, _) = nova()
        a.iphoneApareceu()
        let p = abrir(a)!
        let fim = expectation(description: "esperar volta")
        let caixa = CaixaDeTeste<DecisaoDeAprovacao?>()
        DispatchQueue.global().async { caixa.valor = a.esperar(p); fim.fulfill() }
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(a.pendentes().map(\.id), [p.id])
        a.cancelar(p.id)
        wait(for: [fim], timeout: 2)
        XCTAssertNil(caixa.valor ?? nil)
        XCTAssertTrue(a.pendentes().isEmpty)
        XCTAssertFalse(a.decidir(p.id, .permitir), "cancelado não aceita resposta")
    }

    // MARK: Decisão

    func testPermitirENegarChegamNoGancho() {
        for (quer, esperada) in [(DecisaoDeAprovacao.permitir, DecisaoDeAprovacao.permitir), (.negar, .negar)] {
            let (a, _) = nova()
            a.iphoneApareceu()
            let p = abrir(a)!
            let fim = expectation(description: "decisão")
            let caixa = CaixaDeTeste<DecisaoDeAprovacao?>()
            DispatchQueue.global().async { caixa.valor = a.esperar(p); fim.fulfill() }
            XCTAssertTrue(a.decidir(p.id, quer))
            wait(for: [fim], timeout: 2)
            XCTAssertEqual(caixa.valor ?? nil, esperada)
            XCTAssertFalse(a.decidir(p.id, .negar), "um pedido só é respondido uma vez")
        }
    }

    func testPedidoDesconhecidoNaoAceitaDecisao() {
        let (a, _) = nova()
        XCTAssertFalse(a.decidir("nao-existe", .permitir))
    }

    func testPendentesTrazOTempoRestanteEAFilaTemLimite() {
        let (a, relogio) = nova()
        a.iphoneApareceu()
        let p = abrir(a, prazo: 90)!
        relogio.avancar(30)
        a.iphoneApareceu()
        XCTAssertEqual(a.pendentes(), [PedidoDeAprovacao(id: p.id, projeto: "deck", ferramenta: "Bash", titulo: "Rodar um comando", resumo: "ls", restante: 60)])
        for _ in 1..<Aprovacoes.limiteDePedidos { XCTAssertNotNil(abrir(a)) }
        XCTAssertNil(abrir(a), "fila cheia: o resto cai no terminal")
    }

    // MARK: Rotas

    func testEstadoLevaOsPedidosESoOsPedidosDoIphoneAutenticado() throws {
        var c = try Cenario()
        let a = Aprovacoes()
        c.roteador.aprovacoes = a
        XCTAssertFalse(a.iphoneRecente)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: "errado").status, 401)
        XCTAssertFalse(a.iphoneRecente, "pedido sem código não conta como iPhone")
        var corpo = c.pedir("GET", "/api/estado")
        XCTAssertTrue(a.iphoneRecente)
        XCTAssertNil((corpo.json as? [String: Any])?["aprovacoes"], "sem pedido o campo nem aparece")
        let p = a.abrir(projeto: "deck", ferramenta: "Bash", titulo: "Rodar um comando", resumo: "ls -la")!
        corpo = c.pedir("GET", "/api/estado")
        let lista = (corpo.json as? [String: Any])?["aprovacoes"] as? [[String: Any]]
        XCTAssertEqual(lista?.count, 1)
        XCTAssertEqual(lista?.first?["id"] as? String, p.id)
        XCTAssertEqual(lista?.first?["resumo"] as? String, "ls -la")
    }

    func testPostDeAprovacaoPermiteNegaEAchaOErro() throws {
        var c = try Cenario()
        let a = Aprovacoes()
        c.roteador.aprovacoes = a
        a.iphoneApareceu()
        let p = a.abrir(projeto: "deck", ferramenta: "Bash", titulo: "t", resumo: "r")!
        XCTAssertEqual(c.pedir("POST", "/api/aprovacoes/\(p.id)", corpo: "{}").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/aprovacoes/\(p.id)", corpo: #"{"decisao":"talvez"}"#).status, 400)
        XCTAssertEqual(c.pedir("GET", "/api/aprovacoes/\(p.id)").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/aprovacoes/\(p.id)", corpo: #"{"decisao":"allow"}"#, codigo: nil).status, 401)
        let fim = expectation(description: "decisão")
        let caixa = CaixaDeTeste<DecisaoDeAprovacao?>()
        DispatchQueue.global().async { caixa.valor = a.esperar(p); fim.fulfill() }
        XCTAssertEqual(c.pedir("POST", "/api/aprovacoes/\(p.id)", corpo: #"{"decisao":"deny"}"#).status, 200)
        wait(for: [fim], timeout: 2)
        XCTAssertEqual(caixa.valor ?? nil, .negar)
        let repetido = c.pedir("POST", "/api/aprovacoes/\(p.id)", corpo: #"{"decisao":"allow"}"#)
        XCTAssertEqual(repetido.status, 404)
        XCTAssertNotNil(repetido.erroTexto)
    }

    func testSemAprovacoesLigadasARotaNaoExiste() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/aprovacoes/abc", corpo: #"{"decisao":"allow"}"#).status, 404)
    }
}

final class CaixaDeTeste<T>: @unchecked Sendable {
    private let trava = NSLock()
    private var v: T?
    var valor: T? { get { trava.lock(); defer { trava.unlock() }; return v } set { trava.lock(); v = newValue; trava.unlock() } }
}

// MARK: - O que o Claude Code manda

final class GanchoDoClaudeTestes: XCTestCase {
    func ler(_ json: String) -> GanchoDoClaude.Entrada? { GanchoDoClaude.ler(Data(json.utf8)) }

    func testComandoDoBash() {
        let e = ler(#"{"session_id":"x","cwd":"/Users/x/Projetos/app_web","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove"}}"#)
        XCTAssertEqual(e, GanchoDoClaude.Entrada(projeto: "app_web", ferramenta: "Bash", titulo: "Rodar um comando", resumo: "rm -rf node_modules"))
    }

    func testArquivoEnderecoEBuscaCadaUmNoSeuCampo() {
        XCTAssertEqual(ler(#"{"cwd":"/a/p","tool_name":"Edit","tool_input":{"file_path":"/a/p/x.swift","old_string":"a","new_string":"b"}}"#)?.resumo, "/a/p/x.swift")
        XCTAssertEqual(ler(#"{"cwd":"/a/p","tool_name":"Write","tool_input":{"file_path":"/a/p/novo.md","content":"conteudo grande"}}"#)?.resumo, "/a/p/novo.md")
        XCTAssertEqual(ler(#"{"cwd":"/a/p","tool_name":"WebFetch","tool_input":{"url":"https://exemplo.com/a"}}"#)?.resumo, "https://exemplo.com/a")
        XCTAssertEqual(ler(#"{"cwd":"/a/p","tool_name":"WebSearch","tool_input":{"query":"swift nio"}}"#)?.titulo, "Buscar na web")
    }

    func testProjetoDeWorktreeEhARaiz() {
        XCTAssertEqual(GanchoDoClaude.projeto(de: "/Users/x/Projetos/deck/.claude/worktrees/aprovacao"), "deck")
        XCTAssertEqual(GanchoDoClaude.projeto(de: "/Users/x/Projetos/deck/"), "deck")
        XCTAssertEqual(GanchoDoClaude.projeto(de: ""), "")
    }

    func testFerramentaDeMcpTemTituloLegivel() {
        XCTAssertEqual(GanchoDoClaude.titulo("mcp__supabase__list_tables"), "Usar supabase: list_tables")
        XCTAssertEqual(GanchoDoClaude.titulo("Task"), "Usar Task")
    }

    func testSegredoNoComandoNaoChegaAoIphone() {
        let e = ler(#"{"cwd":"/a/p","tool_name":"Bash","tool_input":{"command":"curl -H 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123' https://x.com"}}"#)
        XCTAssertFalse(e?.resumo.contains("abcdefghijklmnopqrstuvwxyz0123") ?? true)
        XCTAssertTrue(e?.resumo.contains(Mascara.oculto) ?? false)
        let senha = ler(#"{"cwd":"/a/p","tool_name":"Bash","tool_input":{"command":"export SENHA_BANCO=hunter2hunter2 && ./rodar"}}"#)
        XCTAssertFalse(senha?.resumo.contains("hunter2hunter2") ?? true)
    }

    func testResumoGrandeEhCortado() {
        let longo = String(repeating: "a", count: 5000)
        let e = ler(#"{"cwd":"/a/p","tool_name":"Bash","tool_input":{"command":"\#(longo)"}}"#)
        XCTAssertLessThanOrEqual(e?.resumo.count ?? 9999, GanchoDoClaude.limiteDoResumo + 3)
    }

    func testPerguntaDoClaudeEEntradaRuimNaoViramPedido() {
        XCTAssertNil(ler(#"{"cwd":"/a/p","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#), "é pergunta, não permissão")
        XCTAssertNil(ler("não é json"))
        XCTAssertNil(ler(#"{"cwd":"/a/p"}"#))
        XCTAssertNil(ler(#"[1,2]"#))
    }

    func testSaidaNoFormatoDoClaudeCode() throws {
        let permitir = try XCTUnwrap(try JSONSerialization.jsonObject(with: GanchoDoClaude.saida(.permitir)) as? [String: Any])
        let h = try XCTUnwrap(permitir["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(h["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((h["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        let negar = try XCTUnwrap(try JSONSerialization.jsonObject(with: GanchoDoClaude.saida(.negar)) as? [String: Any])
        let d = try XCTUnwrap((negar["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        XCTAssertEqual(d["behavior"] as? String, "deny")
        XCTAssertNotNil(d["message"] as? String)
    }
}

// MARK: - O tratador (sem rede)

final class TratadorDoGanchoTestes: XCTestCase {
    let segredo = String(repeating: "ab", count: 24)
    let corpo = #"{"cwd":"/a/deck","tool_name":"Bash","tool_input":{"command":"ls"}}"#

    func req(segredo s: String?, metodo: String = "POST", caminho: String = GanchoInstalador.caminho, corpo c: String? = nil) -> HttpRequisicao {
        var cab: [String: String] = [:]
        if let s { cab["x-deck-gancho"] = s }
        return HttpRequisicao(metodo: metodo, caminho: caminho, query: [:], cabecalhos: cab, corpo: Data((c ?? corpo).utf8))
    }

    func testSoComSegredoCertoEIphoneRecenteAbre() {
        let a = Aprovacoes()
        let t = TratadorDoGancho(aprovacoes: a, segredo: segredo)
        XCTAssertNil(t.abrir(req(segredo: segredo)), "sem iPhone recente")
        a.iphoneApareceu()
        XCTAssertNil(t.abrir(req(segredo: nil)))
        XCTAssertNil(t.abrir(req(segredo: "errado")))
        XCTAssertNil(t.abrir(req(segredo: segredo, metodo: "GET")))
        XCTAssertNil(t.abrir(req(segredo: segredo, caminho: "/api/estado")))
        XCTAssertNil(t.abrir(req(segredo: segredo, corpo: "lixo")))
        XCTAssertTrue(a.pendentes().isEmpty, "nada disso abriu pedido")
        let p = t.abrir(req(segredo: segredo))
        XCTAssertNotNil(p)
        XCTAssertEqual(a.pendentes().first?.projeto, "deck")
    }

    func testRespostaVaziaSemDecisaoEJsonComDecisao() {
        let vazia = TratadorDoGancho.resposta(nil)
        XCTAssertEqual(vazia.status, 204)
        XCTAssertTrue(vazia.corpo.isEmpty)
        let ok = TratadorDoGancho.resposta(.permitir)
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.corpo, GanchoDoClaude.saida(.permitir))
    }
}

// MARK: - Instalar e remover o gancho no settings.json

final class GanchoInstaladorTestes: XCTestCase {
    var pasta: URL!
    var settings: URL { pasta.appendingPathComponent("settings.json") }
    let cab = URL(fileURLWithPath: "/Users/x/Library/Application Support/Deck/gancho-cabecalho")

    override func setUpWithError() throws { pasta = try pastaTemporaria() }
    override func tearDown() { try? FileManager.default.removeItem(at: pasta) }

    func gravar(_ json: String) throws { try json.write(to: settings, atomically: true, encoding: .utf8) }
    func ler() throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]) }
    func instalar(_ sim: Bool = true) -> String? { GanchoInstalador.aplicar(instalar: sim, arquivo: settings, porta: 4792, cabecalho: cab) }

    func testInstalaEmArquivoQueNaoExisteEDiaQueEstaInstalado() throws {
        XCTAssertEqual(GanchoInstalador.situacao(arquivo: settings), .naoInstalado)
        XCTAssertNil(instalar())
        XCTAssertEqual(GanchoInstalador.situacao(arquivo: settings), .instalado)
        let grupos = try XCTUnwrap(((try ler())["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])
        let gancho = try XCTUnwrap((grupos.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(gancho["type"] as? String, "command")
        XCTAssertEqual(gancho["timeout"] as? Int, 105)
        let cmd = try XCTUnwrap(gancho["command"] as? String)
        XCTAssertTrue(cmd.contains("http://127.0.0.1:4792/deck-gancho/permissao"))
        XCTAssertTrue(cmd.contains("-H @'/Users/x/Library/Application Support/Deck/gancho-cabecalho'"), "o segredo fica no arquivo, nunca no settings.json")
        XCTAssertTrue(cmd.hasSuffix("|| true"), "falha aberta: o curl nunca sai com erro")
    }

    func testPreservaTudoQueJaEstavaLaEEhIdempotente() throws {
        try gravar(#"""
        {"env":{"X":"1"},"permissions":{"allow":["Bash(ls)"]},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo oi"}]}],
                  "PermissionRequest":[{"matcher":"Edit","hooks":[{"type":"command","command":"meu-gancho.sh"}]}]}}
        """#)
        XCTAssertNil(instalar())
        XCTAssertNil(instalar(), "instalar de novo não duplica")
        var raiz = try ler()
        XCTAssertEqual((raiz["env"] as? [String: Any])?["X"] as? String, "1")
        XCTAssertNotNil(raiz["permissions"])
        var hooks = try XCTUnwrap(raiz["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PreToolUse"])
        var grupos = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(grupos.count, 2, "o do dono mais um do Deck")
        XCTAssertEqual(((grupos[0]["hooks"] as? [[String: Any]])?.first)?["command"] as? String, "meu-gancho.sh")

        XCTAssertNil(instalar(false))
        XCTAssertEqual(GanchoInstalador.situacao(arquivo: settings), .naoInstalado)
        raiz = try ler()
        hooks = try XCTUnwrap(raiz["hooks"] as? [String: Any])
        grupos = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(grupos.count, 1, "o gancho do dono continua")
        XCTAssertNotNil(hooks["PreToolUse"])
    }

    func testRemoverNoQueSoTinhaOGanchoDoDeckLimpaOCampo() throws {
        try gravar(#"{"theme":"dark"}"#)
        XCTAssertNil(instalar())
        XCTAssertNil(instalar(false))
        let raiz = try ler()
        XCTAssertNil(raiz["hooks"])
        XCTAssertEqual(raiz["theme"] as? String, "dark")
    }

    func testGuardaCopiaDoArquivoDeAntesESoDoDono() throws {
        let antes = #"{"env":{"CHAVE":"valor"}}"#
        try gravar(antes)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        XCTAssertNil(instalar())
        let copia = pasta.appendingPathComponent("settings.json.deck-copia")
        XCTAssertEqual(try String(contentsOf: copia, encoding: .utf8), antes)
        let perm = try FileManager.default.attributesOfItem(atPath: copia.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perm?.intValue, 0o600)
        let permArquivo = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permArquivo?.intValue, 0o600, "o arquivo novo mantém a permissão do que estava lá")
    }

    func testRecusaFormatoInesperadoSemMexerEmNada() throws {
        let casos = [
            "não é json",
            "[1,2,3]",
            #"{"hooks":"texto"}"#,
            #"{"hooks":{"PermissionRequest":{"matcher":"*"}}}"#,
            #"{"hooks":{"PermissionRequest":["x"]}}"#,
            #"{"hooks":{"PermissionRequest":[{"matcher":"*","hooks":"x"}]}}"#,
        ]
        for caso in casos {
            try gravar(caso)
            if case .formatoInesperado = GanchoInstalador.situacao(arquivo: settings) {} else { XCTFail("deveria recusar: \(caso)") }
            let erro = instalar()
            XCTAssertNotNil(erro, caso)
            XCTAssertTrue(erro?.contains("Nada foi mudado") ?? false, caso)
            XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), caso, "o arquivo do dono fica como estava")
            XCTAssertNotNil(instalar(false), caso)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: pasta.appendingPathComponent("settings.json.deck-copia").path))
    }

    func testArquivoVazioContaComoSemConfig() throws {
        try gravar("  \n")
        XCTAssertEqual(GanchoInstalador.situacao(arquivo: settings), .naoInstalado)
        XCTAssertNil(instalar())
        XCTAssertEqual(GanchoInstalador.situacao(arquivo: settings), .instalado)
    }

    func testAspasNoCaminhoNaoQuebramOComando() {
        XCTAssertEqual(GanchoInstalador.aspas("/a/b c/d"), "'/a/b c/d'")
        XCTAssertEqual(GanchoInstalador.aspas("/a/o'neil"), "'/a/o'\\''neil'")
    }

    func testSegredoNasceUmaVezComPermissaoSoDoDono() throws {
        let s = try XCTUnwrap(SegredoDoGancho.garantir(pasta: pasta))
        XCTAssertGreaterThanOrEqual(s.count, 32)
        XCTAssertEqual(SegredoDoGancho.garantir(pasta: pasta), s, "o segredo não troca a cada abertura")
        let arq = SegredoDoGancho.arquivo(pasta: pasta)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: arq.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try String(contentsOf: arq, encoding: .utf8), "X-Deck-Gancho: \(s)\n", "é a linha que o curl manda com -H @arquivo")
    }

    func testPortaDoGanchoNaoEhADoPainelNemADaBancada() {
        XCTAssertEqual(Variante.deck.portaDoGancho, 4792)
        XCTAssertNotEqual(Variante.deck.portaDoGancho, Variante.bancada.portaDoGancho)
        XCTAssertNotEqual(Variante.bancada.portaDoGancho, Variante.portaDaBancada)
    }
}

#if canImport(Network)
// MARK: - Servidor de verdade, no loopback

final class ServidorDoGanchoTestes: XCTestCase {
    let segredo = String(repeating: "cd", count: 24)
    let corpo = #"{"cwd":"/a/deck","tool_name":"Bash","tool_input":{"command":"ls"}}"#

    func pedir(porta: Int, segredo s: String?, sessao: URLSession = URLSession(configuration: .ephemeral)) -> (URLSessionDataTask, XCTestExpectation, CaixaDeTeste<(Int, Data)>) {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:\(porta)\(GanchoInstalador.caminho)")!)
        r.httpMethod = "POST"
        r.httpBody = Data(corpo.utf8)
        if let s { r.setValue(s, forHTTPHeaderField: SegredoDoGancho.cabecalho) }
        let fim = expectation(description: "resposta")
        let caixa = CaixaDeTeste<(Int, Data)>()
        let t = sessao.dataTask(with: r) { d, resp, _ in
            caixa.valor = ((resp as? HTTPURLResponse)?.statusCode ?? -1, d ?? Data())
            fim.fulfill()
        }
        t.resume()
        return (t, fim, caixa)
    }

    func subir(_ a: Aprovacoes) throws -> (ServidorDoGancho, Int) {
        for porta in 47_920..<47_940 {
            let s = ServidorDoGancho(tratador: TratadorDoGancho(aprovacoes: a, segredo: segredo, prazo: 5), porta: UInt16(porta))
            if (try? s.iniciar()) != nil { return (s, porta) }
        }
        throw XCTSkip("sem porta livre no loopback")
    }

    func testPermitirDoIphoneVoltaComoSaidaDoGancho() throws {
        let a = Aprovacoes()
        let (s, porta) = try subir(a)
        defer { s.parar() }
        a.iphoneApareceu()
        let (_, fim, caixa) = pedir(porta: porta, segredo: segredo)
        let achou = (0..<100).contains { _ in Thread.sleep(forTimeInterval: 0.03); return !a.pendentes().isEmpty }
        XCTAssertTrue(achou, "o pedido chegou na lista do iPhone")
        XCTAssertTrue(a.decidir(try XCTUnwrap(a.pendentes().first).id, .permitir))
        wait(for: [fim], timeout: 3)
        let (status, dados) = try XCTUnwrap(caixa.valor)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(dados, GanchoDoClaude.saida(.permitir))
    }

    func testSemSegredoOuSemIphoneNaoImprimeNada() throws {
        let a = Aprovacoes()
        let (s, porta) = try subir(a)
        defer { s.parar() }
        let (_, f1, c1) = pedir(porta: porta, segredo: segredo)
        wait(for: [f1], timeout: 3)
        XCTAssertEqual(c1.valor?.0, 204, "sem iPhone recente")
        XCTAssertTrue(c1.valor?.1.isEmpty ?? false)
        a.iphoneApareceu()
        let (_, f2, c2) = pedir(porta: porta, segredo: "errado")
        wait(for: [f2], timeout: 3)
        XCTAssertEqual(c2.valor?.0, 204, "segredo errado")
        XCTAssertTrue(a.pendentes().isEmpty)
    }

    func testGanchoQueVaiEmboraTiraOPedidoDoIphone() throws {
        let a = Aprovacoes()
        let (s, porta) = try subir(a)
        defer { s.parar() }
        a.iphoneApareceu()
        let sessao = URLSession(configuration: .ephemeral)
        let (tarefa, fim, _) = pedir(porta: porta, segredo: segredo, sessao: sessao)
        XCTAssertTrue((0..<100).contains { _ in Thread.sleep(forTimeInterval: 0.03); return !a.pendentes().isEmpty })
        tarefa.cancel() // o terminal respondeu e o Claude Code encerrou o gancho
        wait(for: [fim], timeout: 3)
        XCTAssertTrue((0..<100).contains { _ in Thread.sleep(forTimeInterval: 0.03); return a.pendentes().isEmpty }, "o pedido some sozinho")
    }
}
#endif
