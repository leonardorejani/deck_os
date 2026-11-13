import XCTest
@testable import Nucleo

final class AgendaCriarTestes: XCTestCase {
    private let cal = DestinoAgenda(tipo: "calendario", id: "cal-1")
    private let lista = DestinoAgenda(tipo: "lembretes", id: "lis-1")

    private func ler(_ json: String, padrao: DestinoAgenda? = nil) -> Result<NovoCompromisso, ErroAgenda> {
        NovoCompromisso.ler(corpo: Data(json.utf8), padrao: padrao)
    }

    private func erro(_ json: String, padrao: DestinoAgenda? = nil) -> String? {
        if case .failure(let e) = ler(json, padrao: padrao) { return e.texto }
        return nil
    }

    private let base = #""titulo":"Ensaio","dia":"2026-11-14","inicio":"19:00","fim":"21:00","destino":{"tipo":"calendario","id":"cal-1"}"#

    // MARK: Validação

    func testLeUmCompromissoCompleto() throws {
        let n = try ler("{\(base),\"alertaMin\":15,\"padrao\":true}").get()
        XCTAssertEqual(n, NovoCompromisso(titulo: "Ensaio", dia: "2026-11-14", inicio: "19:00", fim: "21:00", diaTodo: false,
                                          destino: cal, alertaMin: 15, definirPadrao: true))
    }

    func testTituloVazioOuGrandeDemaisERecusado() {
        XCTAssertNotNil(erro(#"{"titulo":"   ","dia":"2026-11-14","inicio":"19:00","destino":{"tipo":"calendario","id":"a"}}"#))
        let grande = String(repeating: "a", count: 201)
        XCTAssertNotNil(erro("{\"titulo\":\"\(grande)\",\"dia\":\"2026-11-14\",\"inicio\":\"19:00\",\"destino\":{\"tipo\":\"calendario\",\"id\":\"a\"}}"))
        XCTAssertNotNil(erro(#"{"dia":"2026-11-14","inicio":"19:00","destino":{"tipo":"calendario","id":"a"}}"#))
    }

    func testDiaInvalidoERecusado() {
        for dia in ["2026-02-30", "2026-13-01", "14/11/2026", "", "1999-01-01", "2101-01-01"] {
            XCTAssertNotNil(erro("{\"titulo\":\"x\",\"dia\":\"\(dia)\",\"inicio\":\"19:00\",\"destino\":{\"tipo\":\"calendario\",\"id\":\"a\"}}"), dia)
        }
    }

    func testHoraInvalidaEFimAntesDoInicio() {
        for h in ["7:00", "24:00", "19:60", "19h", "", "19:0"] {
            XCTAssertNotNil(erro("{\"titulo\":\"x\",\"dia\":\"2026-11-14\",\"inicio\":\"\(h)\",\"destino\":{\"tipo\":\"calendario\",\"id\":\"a\"}}"), h)
        }
        XCTAssertEqual(erro(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00","fim":"19:00","destino":{"tipo":"calendario","id":"a"}}"#), "O fim precisa ser depois do início.")
        XCTAssertEqual(erro(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00","fim":"18:00","destino":{"tipo":"calendario","id":"a"}}"#), "O fim precisa ser depois do início.")
        XCTAssertNotNil(erro(#"{"titulo":"x","dia":"2026-11-14","destino":{"tipo":"calendario","id":"a"}}"#), "sem início e sem dia todo")
    }

    func testDiaTodoIgnoraAsHoras() throws {
        let n = try ler(#"{"titulo":"Retiro","dia":"2026-11-14","diaTodo":true,"inicio":"lixo","destino":{"tipo":"lembretes","id":"l"}}"#).get()
        XCTAssertTrue(n.diaTodo)
        XCTAssertNil(n.inicio)
        XCTAssertNil(n.fim)
    }

    func testAlertaForaDaListaERecusado() {
        for a in ["7", "-5", "\"15\"", "99999", "1.5"] {
            XCTAssertEqual(erro("{\(base),\"alertaMin\":\(a)}"), "Esse alerta não existe.", a)
        }
        XCTAssertNil(erro("{\(base),\"alertaMin\":null}"))
    }

    func testDestinoInvalidoOuAusenteSemPadrao() {
        XCTAssertNotNil(erro(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00"}"#))
        XCTAssertNotNil(erro(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00","destino":{"tipo":"disco","id":"a"}}"#))
        XCTAssertNotNil(erro(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00","destino":{"tipo":"calendario","id":""}}"#))
    }

    func testSemDestinoVaiParaOPadraoDaConfig() throws {
        let n = try ler(#"{"titulo":"x","dia":"2026-11-14","inicio":"19:00"}"#, padrao: lista).get()
        XCTAssertEqual(n.destino, lista)
    }

    func testCorpoQueNaoEJsonERecusado() {
        XCTAssertNotNil(erro("não é json"))
        XCTAssertNotNil(erro("[]"))
    }

    // MARK: Datas

    func testDatasDoEventoNoFusoDoMac() throws {
        let saoPaulo = TimeZone(secondsFromGMT: -3 * 3600)!
        let n = try ler("{\(base)}").get()
        let d = try XCTUnwrap(n.datas(fuso: saoPaulo))
        XCTAssertEqual(Datas.iso(d.inicio, fuso: saoPaulo), "2026-11-14T19:00:00-03:00")
        XCTAssertEqual(Datas.iso(d.fim, fuso: saoPaulo), "2026-11-14T21:00:00-03:00")
    }

    func testSemFimDuraUmaHora() throws {
        let n = try ler(#"{"titulo":"x","dia":"2026-11-14","inicio":"23:30","destino":{"tipo":"calendario","id":"a"}}"#).get()
        let d = try XCTUnwrap(n.datas(fuso: utc))
        XCTAssertEqual(Datas.iso(d.fim, fuso: utc), "2026-11-15T00:30:00Z")
    }

    func testDiaTodoVaiDaMeiaNoiteAteOFimDoDia() throws {
        let n = try ler(#"{"titulo":"x","dia":"2026-11-14","diaTodo":true,"destino":{"tipo":"calendario","id":"a"}}"#).get()
        let d = try XCTUnwrap(n.datas(fuso: utc))
        XCTAssertEqual(Datas.iso(d.inicio, fuso: utc), "2026-11-14T00:00:00Z")
        XCTAssertEqual(Datas.iso(d.fim, fuso: utc), "2026-11-14T23:59:59Z")
    }

    func testHoraQueNaoExisteNoSaltoDoHorarioDeVeraoViraNil() throws {
        let ny = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // 2026-03-08 02:30 não existe em Nova York (o relógio pula de 02:00 para 03:00).
        let n = try ler(#"{"titulo":"x","dia":"2026-03-08","inicio":"02:30","destino":{"tipo":"calendario","id":"a"}}"#).get()
        XCTAssertNil(n.datas(fuso: ny))
    }

    func testAlertaEmRelacaoAoInicioEPorDiaTodoAPartirDasNove() throws {
        let n = try ler("{\(base),\"alertaMin\":30}").get()
        XCTAssertEqual(Datas.iso(try XCTUnwrap(n.dataDoAlerta(fuso: utc)), fuso: utc), "2026-11-14T18:30:00Z")
        let t = try ler(#"{"titulo":"x","dia":"2026-11-14","diaTodo":true,"alertaMin":0,"destino":{"tipo":"calendario","id":"a"}}"#).get()
        XCTAssertEqual(Datas.iso(try XCTUnwrap(t.dataDoAlerta(fuso: utc)), fuso: utc), "2026-11-14T09:00:00Z")
        let v = try ler(#"{"titulo":"x","dia":"2026-11-14","diaTodo":true,"alertaMin":1440,"destino":{"tipo":"calendario","id":"a"}}"#).get()
        XCTAssertEqual(Datas.iso(try XCTUnwrap(v.dataDoAlerta(fuso: utc)), fuso: utc), "2026-11-13T09:00:00Z")
        let sem = try ler("{\(base)}").get()
        XCTAssertNil(sem.dataDoAlerta(fuso: utc))
    }

    func testAlertaDoEventoEhRelativoAoInicio() throws {
        let n = try ler("{\(base),\"alertaMin\":15}").get()
        XCTAssertEqual(n.deslocamentoDoAlerta(fuso: utc), -900)
        let t = try ler(#"{"titulo":"x","dia":"2026-11-14","diaTodo":true,"alertaMin":1440,"destino":{"tipo":"calendario","id":"a"}}"#).get()
        XCTAssertEqual(t.deslocamentoDoAlerta(fuso: utc), 9 * 3600 - 1440 * 60)
        XCTAssertNil(try ler("{\(base)}").get().deslocamentoDoAlerta(fuso: utc))
    }

    // MARK: Config

    func testConfigGuardaOPadraoELeConfigAntigaSemEle() throws {
        var c = configDeTeste()
        XCTAssertNil(c.agendaPadrao)
        c.agendaPadrao = lista
        let volta = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(volta.agendaPadrao, lista)
        let antiga = try JSONSerialization.data(withJSONObject: ["perfis": [["id": "p", "nome": "P", "teclas": []]], "perfilAtivo": "p"])
        XCTAssertNil(try JSONDecoder().decode(Config.self, from: antiga).agendaPadrao)
    }

    func testValidacaoRecusaPadraoInvalido() {
        var c = configDeTeste()
        c.agendaPadrao = DestinoAgenda(tipo: "disco", id: "x")
        XCTAssertNotNil(Config.validar(c))
        c.agendaPadrao = DestinoAgenda(tipo: "calendario", id: " ")
        XCTAssertNotNil(Config.validar(c))
        c.agendaPadrao = cal
        XCTAssertNil(Config.validar(c))
    }

    func testPutDePainelVelhoNaoApagaOPadrao() throws {
        var atual = configDeTeste()
        atual.agendaPadrao = lista
        var enviada = atual
        enviada.agendaPadrao = nil
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(enviada)) as? [String: Any])
        obj.removeValue(forKey: "agendaPadrao")
        let corpo = try JSONSerialization.data(withJSONObject: obj)
        let nova = try Config.receber(corpo: corpo, sobre: atual).get()
        XCTAssertEqual(nova.agendaPadrao, lista)
        // Mandando null de propósito, a pessoa limpa o padrão.
        obj["agendaPadrao"] = NSNull()
        let limpa = try Config.receber(corpo: JSONSerialization.data(withJSONObject: obj), sobre: atual).get()
        XCTAssertNil(limpa.agendaPadrao)
    }
}

// MARK: - Rotas

private struct CriadorFalso: CriadorDeAgenda {
    let registro: Registro
    var destinosFixos = DestinosDaAgenda(
        calendarios: [OpcaoDeDestino(id: "cal-1", nome: "Trabalho", cor: "#ff0000", conta: "iCloud")],
        listas: [OpcaoDeDestino(id: "lis-1", nome: "Compras", cor: "#00ff00", conta: nil)],
        permissaoCalendario: "liberado", permissaoLembretes: "liberado", padrao: nil)
    var falha: ErroAgenda?

    func destinos(pedirPermissao: Bool) -> DestinosDaAgenda {
        registro.anotar("destinos pedir=\(pedirPermissao)")
        return destinosFixos
    }

    func criar(_ n: NovoCompromisso) -> Result<Void, ErroAgenda> {
        if let falha { return .failure(falha) }
        registro.anotar("criar \(n.destino.tipo):\(n.destino.id) \(n.titulo) \(n.dia) \(n.inicio ?? "dia todo")")
        return .success(())
    }
}

final class AgendaCriarRotasTestes: XCTestCase {
    private let corpo = #"{"titulo":"Ensaio","dia":"2026-11-14","inicio":"19:00","fim":"21:00","destino":{"tipo":"calendario","id":"cal-1"}}"#

    private func cenario(_ ajuste: (inout CriadorFalso) -> Void = { _ in }) throws -> Cenario {
        var c = try Cenario()
        var f = CriadorFalso(registro: c.registro)
        ajuste(&f)
        c.roteador.criadorDeAgenda = f
        return c
    }

    func testSemCriadorAsRotasNaoExistem() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: corpo).status, 404)
        XCTAssertEqual(c.pedir("GET", "/api/agenda/destinos").status, 404)
    }

    func testExigeCodigoEMetodo() throws {
        let c = try cenario()
        XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: corpo, codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/agenda/destinos", codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/agenda/criar").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/agenda/destinos").status, 405)
        XCTAssertEqual(c.registro.todos, [])
    }

    func testCriaEChamaOCriadorComODestinoCerto() throws {
        let c = try cenario()
        let r = c.pedir("POST", "/api/agenda/criar", corpo: corpo)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual((r.json as? [String: Any])?["padraoSalvo"] as? Bool, false)
        XCTAssertEqual(c.registro.todos, ["criar calendario:cal-1 Ensaio 2026-11-14 19:00"])
        XCTAssertNil(c.armazem.ler().agendaPadrao)
    }

    func testEntradaInvalidaNaoChegaNoCriador() throws {
        let c = try cenario()
        for ruim in [#"{"titulo":"","dia":"2026-11-14","inicio":"19:00","destino":{"tipo":"calendario","id":"a"}}"#,
                     #"{"titulo":"x","dia":"2026-02-31","inicio":"19:00","destino":{"tipo":"calendario","id":"a"}}"#,
                     #"{"titulo":"x","dia":"2026-11-14","inicio":"19:00"}"#, "lixo"] {
            XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: ruim).status, 400, ruim)
        }
        XCTAssertEqual(c.registro.todos, [])
    }

    func testPadraoPedidoVaiParaAConfig() throws {
        let c = try cenario()
        let com = corpo.dropLast() + #","padrao":true}"#
        let r = c.pedir("POST", "/api/agenda/criar", corpo: String(com))
        XCTAssertEqual((r.json as? [String: Any])?["padraoSalvo"] as? Bool, true)
        XCTAssertEqual(c.armazem.ler().agendaPadrao, DestinoAgenda(tipo: "calendario", id: "cal-1"))
    }

    func testSemDestinoUsaOPadraoDaConfig() throws {
        let c = try cenario()
        var cfg = c.armazem.ler()
        cfg.agendaPadrao = DestinoAgenda(tipo: "lembretes", id: "lis-1")
        XCTAssertNil(c.armazem.aplicar(cfg))
        XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: #"{"titulo":"Pão","dia":"2026-11-14","diaTodo":true}"#).status, 200)
        XCTAssertEqual(c.registro.todos, ["criar lembretes:lis-1 Pão 2026-11-14 dia todo"])
    }

    func testErroDoCriadorVoltaComOStatusEOTexto() throws {
        let c = try cenario { $0.falha = ErroAgenda(status: 409, texto: "Libere os Lembretes no Mac.") }
        let r = c.pedir("POST", "/api/agenda/criar", corpo: corpo)
        XCTAssertEqual(r.status, 409)
        XCTAssertEqual(r.erroTexto, "Libere os Lembretes no Mac.")
    }

    func testFalhaAoCriarNaoGuardaPadrao() throws {
        let c = try cenario { $0.falha = ErroAgenda(status: 422, texto: "x") }
        _ = c.pedir("POST", "/api/agenda/criar", corpo: String(corpo.dropLast() + #","padrao":true}"#))
        XCTAssertNil(c.armazem.ler().agendaPadrao)
    }

    func testDestinosTrazOPadraoELevaOPedidoDePermissao() throws {
        let c = try cenario()
        var cfg = c.armazem.ler()
        cfg.agendaPadrao = DestinoAgenda(tipo: "lembretes", id: "lis-1")
        XCTAssertNil(c.armazem.aplicar(cfg))
        let r = c.pedir("GET", "/api/agenda/destinos?pedir=1")
        XCTAssertEqual(r.status, 200)
        let d = try JSONDecoder().decode(DestinosDaAgenda.self, from: r.corpo)
        XCTAssertEqual(d.padrao, DestinoAgenda(tipo: "lembretes", id: "lis-1"))
        XCTAssertEqual(d.calendarios.map(\.nome), ["Trabalho"])
        XCTAssertEqual(d.listas.map(\.nome), ["Compras"])
        XCTAssertEqual(c.registro.todos, ["destinos pedir=true"])
        _ = c.pedir("GET", "/api/agenda/destinos")
        XCTAssertEqual(c.registro.todos.last, "destinos pedir=false")
    }

    func testPadraoQueSumiuDoMacNaoVaiParaATela() throws {
        let c = try cenario()
        var cfg = c.armazem.ler()
        cfg.agendaPadrao = DestinoAgenda(tipo: "calendario", id: "apagado")
        XCTAssertNil(c.armazem.aplicar(cfg))
        let d = try JSONDecoder().decode(DestinosDaAgenda.self, from: c.pedir("GET", "/api/agenda/destinos").corpo)
        XCTAssertNil(d.padrao)
    }

    func testPadraoNaoEApagadoSeAPermissaoAindaNaoFoiDada() throws {
        let c = try cenario { $0.destinosFixos.permissaoLembretes = "pedir"; $0.destinosFixos.listas = [] }
        var cfg = c.armazem.ler()
        cfg.agendaPadrao = DestinoAgenda(tipo: "lembretes", id: "lis-1")
        XCTAssertNil(c.armazem.aplicar(cfg))
        let d = try JSONDecoder().decode(DestinosDaAgenda.self, from: c.pedir("GET", "/api/agenda/destinos").corpo)
        XCTAssertEqual(d.padrao?.id, "lis-1")
    }
}
