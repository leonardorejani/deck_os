import XCTest
@testable import Nucleo

/// Executor que responde por trecho do comando e guarda o que rodou. Dados todos inventados.
private final class ExecutorDoMail: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var _comandos: [String] = []
    var aberto = true
    var leitura = SaidaShell(status: 0, saida: "")
    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }
    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); _comandos.append(comando); trava.unlock()
        if comando.hasPrefix("pgrep") { return SaidaShell(status: aberto ? 0 : 1, saida: "") }
        return leitura
    }
}

private let F = AppleScript.campoMail, R = AppleScript.registroMail
private func linha(_ campos: [String]) -> String { campos.joined(separator: F) + R }
private let fuso = TimeZone(identifier: "America/Sao_Paulo")!

private func saidaDeExemplo() -> String {
    linha(["C", "ID-1", "iCloud", "pessoa@exemplo.com"]) + linha(["C", "ID-2", "Trabalho", ""])
        + linha(["A", "ID-1"])
        + linha(["M", "<a1@exemplo.com>", "\"Ana Souza\" <ana@exemplo.com>", "Reuniao\tde terca", "2026-11-12 9:5:3", "0", "Oi,\n\n  segue   o resumo\tda semana."])
        + linha(["M", "b2@exemplo.com", "loja@exemplo.com", "", "2026-11-12 18:30:00", "1", ""])
        + linha(["M", "c3@exemplo.com", "Bia <bia@exemplo.com>", "Mais antiga", "2026-11-10 8:00:00", "1", "texto"])
}

final class MailTestes: XCTestCase {
    // MARK: Leitura da saída do script

    func testInterpretaContasMensagensELimpaOsCampos() throws {
        let l = LeitorDeMail.interpretar(saidaDeExemplo(), fuso: fuso)
        XCTAssertEqual(l.contas, [ContaMail(id: "ID-1", nome: "iCloud", email: "pessoa@exemplo.com"), ContaMail(id: "ID-2", nome: "Trabalho", email: nil)])
        XCTAssertEqual(l.conta, "ID-1")
        XCTAssertEqual(l.mensagens.map(\.id), ["b2@exemplo.com", "a1@exemplo.com", "c3@exemplo.com"], "as mais novas primeiro, e o id sem < >")
        let nova = try XCTUnwrap(l.mensagens.first { $0.id == "a1@exemplo.com" })
        XCTAssertEqual(nova.remetente, "Ana Souza")
        XCTAssertEqual(nova.assunto, "Reuniao de terca")
        XCTAssertEqual(nova.previa, "Oi, segue o resumo da semana.")
        XCTAssertEqual(nova.data, "2026-11-12T09:05:03-03:00")
        XCTAssertFalse(nova.lida)
        XCTAssertTrue(try XCTUnwrap(l.mensagens.first { $0.id == "c3@exemplo.com" }).lida)
    }

    func testRemetenteAssuntoEPreviaSemNada() {
        XCTAssertEqual(LeitorDeMail.remetente("loja@exemplo.com"), "loja@exemplo.com")
        XCTAssertEqual(LeitorDeMail.remetente("<loja@exemplo.com>"), "loja@exemplo.com")
        XCTAssertEqual(LeitorDeMail.remetente(""), "Sem remetente")
        XCTAssertEqual(LeitorDeMail.assunto("  \n"), "(sem assunto)")
        let longa = String(repeating: "palavra ", count: 60)
        let p = LeitorDeMail.previa(longa)
        XCTAssertLessThanOrEqual(p.count, 143)
        XCTAssertTrue(p.hasSuffix("..."))
    }

    func testMensagemSemIdOuComDataRuimEDescartada() throws {
        let s = linha(["A", "ID-1"]) + linha(["M", "", "a@x.com", "s", "2026-11-12 9:5:3", "0", ""])
            + linha(["M", "ok@x.com", "a@x.com", "s", "data ruim", "0", ""]) + linha(["M", "so quebra", "a@x.com", "s", "2026-11-12 9:5:3", "0", ""])
        XCTAssertEqual(LeitorDeMail.interpretar(s, fuso: fuso).mensagens, [])
    }

    // MARK: A leitura inteira

    func testMailFechadoNaoAbreOMailENaoLeNada() {
        let f = ExecutorDoMail(); f.aberto = false
        let c = LeitorDeMail(executor: f).caixa(conta: nil)
        XCTAssertEqual(c.estado, "fechado")
        XCTAssertEqual(c.aviso, "Abra o Mail no Mac para ver as mensagens aqui.")
        XCTAssertEqual(f.comandos.count, 1, "só olhou se o Mail está aberto")
        XCTAssertFalse(f.comandos.contains { $0.contains("open ") || $0.contains("osascript") })
    }

    func testLeituraUsaOScriptFixoComTempoLimiteEArgumentosSeparados() throws {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: 0, saida: saidaDeExemplo())
        let c = LeitorDeMail(executor: f).caixa(conta: "ID-2")
        XCTAssertEqual(c.estado, "ok")
        XCTAssertEqual(c.contas.count, 2)
        let osa = try XCTUnwrap(f.comandos.last)
        XCTAssertTrue(osa.contains("perl -e"), "roda dentro do vigia de tempo")
        XCTAssertTrue(osa.contains("ID-2") && !AppleScript.caixaDeEntradaDoMail.joined().contains("ID-2"), "a conta entra como argumento, não dentro do script")
        XCTAssertTrue(osa.contains("read status"), "lê só o estado, nunca escreve")
        XCTAssertFalse(osa.contains("set read status"), "nunca marca como lida")
        XCTAssertFalse(osa.contains("delete") || osa.contains("move "), "nunca apaga nem move")
    }

    func testCacheCurtoNaoRelePeloMesmoMinutoERelePassadaAValidade() {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: 0, saida: saidaDeExemplo())
        let relogio = Relogio()
        let l = LeitorDeMail(executor: f, agora: { relogio.agora }, validade: 20)
        _ = l.caixa(conta: nil); _ = l.caixa(conta: nil)
        XCTAssertEqual(f.comandos.filter { $0.contains("perl") }.count, 1)
        _ = l.caixa(conta: "ID-2")
        XCTAssertEqual(f.comandos.filter { $0.contains("perl") }.count, 2, "outra conta não pega o cache da primeira")
        relogio.agora.addTimeInterval(21)
        _ = l.caixa(conta: nil)
        XCTAssertEqual(f.comandos.filter { $0.contains("perl") }.count, 3)
    }

    func testFalhaNaoFicaEmCache() {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: 1, saida: "execution error: (-1743)")
        let l = LeitorDeMail(executor: f)
        let c = l.caixa(conta: nil)
        XCTAssertEqual(c.estado, "sem-permissao")
        XCTAssertEqual(c.aviso, "O Deck não tem permissão para controlar o Mail. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação.")
        f.leitura = SaidaShell(status: 0, saida: saidaDeExemplo())
        XCTAssertEqual(l.caixa(conta: nil).estado, "ok", "a leitura seguinte tenta de novo")
    }

    func testTempoEsgotadoViraAviso() {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: ExecutorAcoes.statusTempoEsgotado, saida: "")
        let l = LeitorDeMail(executor: f)
        XCTAssertEqual(l.caixa(conta: nil).estado, "erro")
        XCTAssertEqual(l.caixa(conta: nil).aviso, "O Mail demorou demais para responder. Tente de novo em instantes.")
    }

    func testContaComTracoNoComecoNaoViraOpcaoDoOsascript() {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: 0, saida: saidaDeExemplo())
        let c = LeitorDeMail(executor: f).caixa(conta: "-e")
        XCTAssertEqual(c.estado, "erro")
        XCTAssertFalse(f.comandos.contains { $0.contains("osascript") })
    }

    func testSemContasNoMailDizOQueFazer() {
        let f = ExecutorDoMail(); f.leitura = SaidaShell(status: 0, saida: "")
        let c = LeitorDeMail(executor: f).caixa(conta: nil)
        XCTAssertEqual(c.estado, "ok")
        XCTAssertEqual(c.aviso, "Nenhuma conta configurada no Mail. Adicione uma conta no app Mail.")
        XCTAssertEqual(c.mensagens, [])
    }

    // MARK: Abrir no Mail

    func testAbrirMontaOEnderecoMessageComOIdCodificado() {
        XCTAssertEqual(LeitorDeMail.enderecoDaMensagem("<abc.1@exemplo.com>"), "message://%3Cabc.1%40exemplo.com%3E")
        XCTAssertNil(LeitorDeMail.enderecoDaMensagem(""))
        XCTAssertNil(LeitorDeMail.enderecoDaMensagem("com espaco"))
        XCTAssertNil(LeitorDeMail.enderecoDaMensagem("a\nb"))
        let f = ExecutorDoMail()
        XCTAssertNil(LeitorDeMail(executor: f).abrir(id: "abc.1@exemplo.com"))
        XCTAssertEqual(f.comandos, ["open -b 'com.apple.mail' 'message://%3Cabc.1%40exemplo.com%3E'"])
    }

    func testAbrirComIdEstranhoNaoRodaComando() {
        let f = ExecutorDoMail()
        XCTAssertNotNil(LeitorDeMail(executor: f).abrir(id: "x'; rm -rf ~; '"))
        XCTAssertTrue(f.comandos.isEmpty)
    }

    // MARK: Rotas

    private final class Relogio: @unchecked Sendable { var agora = Date(timeIntervalSince1970: 1_800_000_000) }

    private struct MailFalso: ProvedorDeMail {
        let registro: Registro
        func caixa(conta: String?) -> CaixaDeMail {
            registro.anotar("mail \(conta ?? "-")")
            return CaixaDeMail(estado: "ok", contas: [ContaMail(id: "A", nome: "iCloud")], conta: conta ?? "A",
                               mensagens: [MensagemMail(id: "m1@x.com", remetente: "Ana", assunto: "Oi", previa: "Tudo bem?", data: "2026-11-12T09:00:00-03:00", lida: false)])
        }
        func abrir(id: String) -> String? { registro.anotar("abrir \(id)"); return id == "falha@x.com" ? "Não consegui abrir a mensagem no Mail." : nil }
    }

    private func cenario(comMail: Bool = true) throws -> (Cenario, Roteador) {
        let c = try Cenario()
        var r = c.roteador
        r.mail = comMail ? MailFalso(registro: c.registro) : nil
        return (c, r)
    }

    private func pedir(_ r: Roteador, _ metodo: String, _ alvo: String, corpo: String = "", codigo: String? = Cenario.codigo) -> RespostaRota {
        let (caminho, query) = Http.separarAlvo(alvo)
        return r.responder(HttpRequisicao(metodo: metodo, caminho: caminho, query: query,
                                          cabecalhos: codigo.map { ["x-deck-codigo": $0] } ?? [:], corpo: Data(corpo.utf8)))
    }

    func testRotaDoMailExigeCodigoEMetodo() throws {
        let (_, r) = try cenario()
        XCTAssertEqual(pedir(r, "GET", "/api/mail", codigo: nil).status, 401)
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "{\"id\":\"m1@x.com\"}", codigo: nil).status, 401)
        let post = pedir(r, "POST", "/api/mail")
        XCTAssertEqual(post.status, 405)
        XCTAssertEqual(post.extras["Allow"], "GET")
        XCTAssertEqual(pedir(r, "GET", "/api/mail/abrir").status, 405)
    }

    func testRotaDoMailDevolveAListaEPassaAConta() throws {
        let (c, r) = try cenario()
        let sem = pedir(r, "GET", "/api/mail")
        XCTAssertEqual(sem.status, 200)
        let obj = try XCTUnwrap(sem.json as? [String: Any])
        XCTAssertEqual(obj["estado"] as? String, "ok")
        XCTAssertEqual((obj["mensagens"] as? [[String: Any]])?.first?["assunto"] as? String, "Oi")
        XCTAssertEqual((obj["mensagens"] as? [[String: Any]])?.first?["lida"] as? Bool, false)
        XCTAssertEqual(pedir(r, "GET", "/api/mail?conta=B").status, 200)
        XCTAssertEqual(c.registro.todos, ["mail -", "mail B"])
    }

    func testRotaDoMailRecusaContaComControle() throws {
        let (c, r) = try cenario()
        XCTAssertEqual(pedir(r, "GET", "/api/mail?conta=a%0Ab").status, 400)
        XCTAssertEqual(pedir(r, "GET", "/api/mail?conta=" + String(repeating: "a", count: 201)).status, 400)
        XCTAssertTrue(c.registro.todos.isEmpty)
    }

    func testAbrirMensagemPelaRota() throws {
        let (c, r) = try cenario()
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "{\"id\":\"m1@x.com\"}").status, 200)
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "{\"id\":\"falha@x.com\"}").status, 422)
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "{}").status, 400)
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "nada").status, 400)
        XCTAssertEqual(c.registro.todos, ["abrir m1@x.com", "abrir falha@x.com"])
    }

    func testSemProvedorAsRotasNaoExistem() throws {
        let (_, r) = try cenario(comMail: false)
        XCTAssertEqual(pedir(r, "GET", "/api/mail").status, 404)
        XCTAssertEqual(pedir(r, "POST", "/api/mail/abrir", corpo: "{\"id\":\"m1@x.com\"}").status, 404)
    }
}
