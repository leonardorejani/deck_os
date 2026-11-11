import XCTest
@testable import Nucleo

final class FontesWhatsAppTestes: XCTestCase {
    // Saída real do `sqlite3 -json` (colunas conferidas neste Mac, conteúdo de exemplo).
    // Datas em segundos desde 2001 (Core Data). 813848582 = 2026-10-16.
    let conversas = """
    [{"id":401,"nome":"Maria","tipo":0,"nao":2,"ultima":813848582.5,"jid":"1111@lid"},
     {"id":402,"nome":"Louvor Domingo","tipo":1,"nao":3,"ultima":813900000.0,"jid":"2222@g.us"},
     {"id":403,"nome":null,"tipo":0,"nao":-1,"ultima":null,"jid":"3333@lid"}]
    """
    // Da mais antiga para a mais nova, como a consulta ordena. A Maria tem 3 recebidas, mas só 2 não lidas.
    let mensagens = """
    [{"cid":401,"d":813848000.0,"t":"mensagem velha, já lida","ty":0,"de":null},
     {"cid":401,"d":813848500.0,"t":"oi","ty":0,"de":null},
     {"cid":401,"d":813848582.0,"t":null,"ty":1,"de":null},
     {"cid":402,"d":813899000.0,"t":"culto às 9h","ty":0,"de":"João"},
     {"cid":402,"d":813899500.0,"t":"  ","ty":2,"de":"Ana"},
     {"cid":402,"d":813900000.0,"t":"amém","ty":0,"de":null},
     {"cid":403,"d":813700000.0,"t":"marcada como não lida","ty":0,"de":null}]
    """

    func testMontaConversasComMensagensNaoLidasENomeNoGrupo() throws {
        let c = try XCTUnwrap(FonteWhatsApp.parseConversas(conversas))
        let m = try XCTUnwrap(FonteWhatsApp.parseMensagens(mensagens))
        let d = FonteWhatsApp.montar(conversas: c, mensagens: m)
        XCTAssertEqual(d.resumo, ResumoWhatsApp(total: 2 + 3 + 1, conversas: 3))
        let maria = d.conversas[0]
        XCTAssertEqual(maria.nome, "Maria")
        XCTAssertFalse(maria.grupo)
        // Só as 2 últimas, na ordem de leitura, sem nome de quem mandou (conversa direta) e a foto pelo tipo.
        XCTAssertEqual(maria.mensagens.map(\.texto), ["oi", "Foto"])
        XCTAssertEqual(maria.mensagens.map(\.de), ["", ""])
        XCTAssertEqual(maria.ultima, "2026-10-16T13:03:02Z")
        let grupo = d.conversas[1]
        XCTAssertTrue(grupo.grupo)
        XCTAssertEqual(grupo.mensagens.map(\.de), ["João", "Ana", ""])
        XCTAssertEqual(grupo.mensagens.map(\.texto), ["culto às 9h", "Vídeo", "amém"])
        // Marcada como não lida à mão (-1) conta 1, e o nome vazio ganha um rótulo.
        XCTAssertEqual(d.conversas[2].naoLidas, 1)
        XCTAssertEqual(d.conversas[2].nome, "Contato")
        XCTAssertEqual(d.conversas[2].ultima, "")
    }

    func testListaVaziaDoSqliteNaoEErro() {
        XCTAssertEqual(FonteWhatsApp.parseConversas(""), [])
        XCTAssertEqual(FonteWhatsApp.parseConversas("[]"), [])
        XCTAssertNil(FonteWhatsApp.parseConversas("isso não é json"))
    }

    func testLerRodaSoLeituraPeloExecutorEFiltraAsConversasNaConsulta() {
        let ex = ExecutorFalso([("from ZWACHATSESSION", SaidaShell(status: 0, saida: conversas)),
                                ("from ZWAMESSAGE", SaidaShell(status: 0, saida: mensagens))])
        let r = FonteWhatsApp(executor: ex, banco: "/Users/x/Library/Group Containers/g/ChatStorage.sqlite").ler()
        XCTAssertEqual(r.valor?.resumo.total, 6)
        XCTAssertNil(r.aviso)
        XCTAssertEqual(ex.comandos.count, 2)
        XCTAssertTrue(ex.comandos.allSatisfy { $0.hasPrefix("sqlite3 -readonly -json '/Users/x/Library/Group Containers/g/ChatStorage.sqlite' ") })
        let c = ex.comandos[0]
        for filtro in ["ZARCHIVED = 0", "ZHIDDEN = 0", "ZREMOVED = 0", "ZSESSIONTYPE in (0, 1, 4)"] {
            XCTAssertTrue(c.contains(filtro), filtro)
        }
        XCTAssertTrue(ex.comandos[1].contains("in (401, 402, 403)"))
    }

    func testSemNaoLidasDevolveZeroSemAviso() {
        let ex = ExecutorFalso([("from ZWACHATSESSION", SaidaShell(status: 0, saida: ""))])
        let r = FonteWhatsApp(executor: ex, banco: "/b").ler()
        XCTAssertEqual(r.valor, WhatsAppDados(resumo: ResumoWhatsApp(total: 0, conversas: 0), conversas: []))
        XCTAssertNil(r.aviso)
        XCTAssertEqual(ex.comandos.count, 1)
    }

    func testSemAcessoTotalAoDiscoViraAvisoENuncaQuebra() {
        let ex = ExecutorFalso([("sqlite3", SaidaShell(status: 14, saida: "Error: unable to open database file"))])
        let r = FonteWhatsApp(executor: ex, banco: "/b").ler()
        XCTAssertNil(r.valor)
        XCTAssertEqual(r.aviso?.fonte, "whatsapp")
        XCTAssertTrue(r.aviso?.texto.contains("Acesso Total ao Disco") ?? false)
    }

    func testEsquemaMudadoViraAviso() {
        let ex = ExecutorFalso([("sqlite3", SaidaShell(status: 1, saida: "Error: no such column: ZUNREADCOUNT"))])
        let r = FonteWhatsApp(executor: ex, banco: "/b").ler()
        XCTAssertNil(r.valor)
        XCTAssertTrue(r.aviso?.texto.contains("atualização") ?? false)

        let lixo = ExecutorFalso([("sqlite3", SaidaShell(status: 0, saida: "<html>"))])
        XCTAssertNotNil(FonteWhatsApp(executor: lixo, banco: "/b").ler().aviso)
    }

    func testCaminhoComApostrofoVaiComAspasCertas() {
        let ex = ExecutorFalso([("sqlite3", SaidaShell(status: 0, saida: ""))])
        _ = FonteWhatsApp(executor: ex, banco: "/Users/o'neil/b.sqlite").ler()
        XCTAssertTrue(ex.comandos[0].contains(#"'/Users/o'\''neil/b.sqlite'"#))
    }

    func testSeloDoDockComoPlanoB() {
        let ok = ExecutorFalso([("lsappinfo", SaidaShell(status: 0, saida: #""StatusLabel"={ "label"="7" }"#))])
        XCTAssertEqual(Selo.total(executor: ok, app: "WhatsApp"), 7)
        let fechado = ExecutorFalso([("lsappinfo", SaidaShell(status: 0, saida: ""))])
        XCTAssertNil(Selo.total(executor: fechado, app: "WhatsApp"))
        let ponto = ExecutorFalso([("lsappinfo", SaidaShell(status: 0, saida: #""StatusLabel"={ "label"="•" }"#))])
        XCTAssertNil(Selo.total(executor: ponto, app: "WhatsApp"))
    }
}
