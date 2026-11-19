import XCTest
@testable import Nucleo

// Regras automáticas "quando, então" (SPEC 13, item 40, 19/11/2026): o motor, a config e o estado.

private func calendarioUTC() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

/// 2026-11-18 é uma quarta-feira (weekday 4, dia 3 na contagem de domingo = 0).
private func em(_ hora: Int, _ minuto: Int = 0, seg: Int = 0, dia: Int = 18) -> Date {
    var c = DateComponents(); c.year = 2026; c.month = 11; c.day = dia; c.hour = hora; c.minute = minuto; c.second = seg
    c.timeZone = TimeZone(identifier: "UTC")
    return calendarioUTC().date(from: c)!
}

private let perfis = [Perfil(id: "trabalho", nome: "Trabalho", teclas: []), Perfil(id: "palco", nome: "Palco", teclas: [])]

private func regra(_ id: String = "r1", fonte: String = "sessao", limite: Int? = nil, tipo: String = "tela", alvo: String = "sessoes",
                   ligada: Bool = true, dias: [Int] = [], de: String? = nil, ate: String? = nil, durar: Bool = false,
                   descanso: Int = 5, prioridade: Int = 5) -> Regra {
    Regra(id: id, nome: "Regra \(id)", ligada: ligada, quando: Gatilho(fonte: fonte, limite: limite), entao: AcaoDeRegra(tipo: tipo, alvo: alvo),
          dias: dias, de: de, ate: ate, enquantoDurar: durar, descanso: descanso, prioridade: prioridade)
}

private func entrada(_ agora: Date, sessoes: Int = 0, meet: Bool = false, spotify: Bool = false, uso: Int? = nil, naoLidas: Int? = nil,
                     whatsappAberto: Bool = true, ids: [String]? = nil) -> EntradaDeRegras {
    EntradaDeRegras(agora: agora, sessoes: sessoes, meetEmChamada: meet, spotifyTocando: spotify, usoMaximo: uso, naoLidas: naoLidas,
                    whatsappAberto: whatsappAberto, idsDeSessoes: ids ?? (0..<sessoes).map { "s\($0)" })
}

final class MotorDeRegrasTestes: XCTestCase {
    private func motor() -> MotorDeRegras { MotorDeRegras(calendario: calendarioUTC()) }

    func testSessaoPedindoDisparaComAFraseDoCartao() {
        var m = motor()
        XCTAssertEqual(m.avaliar(entrada(em(10)), regras: [regra()], perfis: perfis, pausada: false), [])
        let a = m.avaliar(entrada(em(10, 0, seg: 1), sessoes: 1), regras: [regra()], perfis: perfis, pausada: false)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].id, "r1")
        XCTAssertEqual(a[0].texto, "Indo para Sessões")
        XCTAssertEqual(a[0].tipo, "tela")
        XCTAssertEqual(a[0].alvo, "sessoes")
        XCTAssertEqual(a[0].segundos, 3)
        XCTAssertFalse(a[0].durar)
    }

    func testRegraDesligadaNuncaDispara() {
        var m = motor()
        XCTAssertEqual(m.avaliar(entrada(em(10), sessoes: 2), regras: [regra(ligada: false)], perfis: perfis, pausada: false), [])
    }

    func testPausaGeralSegura() {
        var m = motor()
        XCTAssertEqual(m.avaliar(entrada(em(10), sessoes: 2), regras: [regra()], perfis: perfis, pausada: true), [])
        // tirou a pausa com a condição ainda valendo: dispara como borda nova
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 5), sessoes: 2), regras: [regra()], perfis: perfis, pausada: false).count, 1)
    }

    func testHistereseDeQuatroSegundosAntesDeDesfazer() {
        var m = motor()
        let r = [regra(durar: true)]
        let primeiro = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(primeiro.count, 1)
        XCTAssertTrue(primeiro[0].durar)
        // a condição some: ainda vale por 4 s
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 1)), regras: r, perfis: perfis, pausada: false).map(\.id), ["r1"])
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 4)), regras: r, perfis: perfis, pausada: false).map(\.id), ["r1"])
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 5)), regras: r, perfis: perfis, pausada: false), [])
    }

    func testCondicaoQueVoltaDentroDaHistereseNaoDisparaDeNovo() {
        var m = motor()
        let r = [regra()]
        let seq = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)[0].seq
        _ = m.avaliar(entrada(em(10, 0, seg: 1)), regras: r, perfis: perfis, pausada: false)
        let volta = m.avaliar(entrada(em(10, 0, seg: 2), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(volta.map(\.seq), [seq], "o mesmo disparo segue, o iPhone não repete a contagem")
    }

    func testDescansoSegueDisparoNovo() {
        var m = motor()
        let r = [regra(descanso: 5)]
        let s1 = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)[0].seq
        // a condição acaba e, passada a folga, a regra sai
        _ = m.avaliar(entrada(em(10, 1)), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(m.avaliar(entrada(em(10, 1, seg: 5)), regras: r, perfis: perfis, pausada: false), [])
        // sobe de novo 2 min depois do primeiro disparo: em descanso, não vale
        XCTAssertEqual(m.avaliar(entrada(em(10, 2), sessoes: 1), regras: r, perfis: perfis, pausada: false), [])
        _ = m.avaliar(entrada(em(10, 3)), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(m.avaliar(entrada(em(10, 3, seg: 5)), regras: r, perfis: perfis, pausada: false), [])
        // passou o descanso: dispara com disparo novo
        let s2 = m.avaliar(entrada(em(10, 8), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(s2.count, 1)
        XCTAssertNotEqual(s2[0].seq, s1)
    }

    func testDescansoZeroDisparaSempre() {
        var m = motor()
        let r = [regra(descanso: 0)]
        _ = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        _ = m.avaliar(entrada(em(10, 0, seg: 10)), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 11), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1)
    }

    func testPrioridadeMaiorVenceEEmpateSegueAOrdemDaLista() {
        var m = motor()
        let r = [regra("a", prioridade: 3), regra("b", prioridade: 8), regra("c", prioridade: 8)]
        let a = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(a.map(\.id), ["b", "c", "a"])
    }

    func testDiasEHorarioFecham() {
        var m = motor()
        // quarta (3 na contagem de domingo = 0), das 9h às 18h
        let r = [regra(dias: [1, 2, 3, 4, 5], de: "09:00", ate: "18:00")]
        XCTAssertEqual(m.avaliar(entrada(em(8, 59), sessoes: 1), regras: r, perfis: perfis, pausada: false), [], "antes do horário")
        XCTAssertEqual(m.avaliar(entrada(em(9, 0, seg: 10), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1, "dentro")
        XCTAssertEqual(m.avaliar(entrada(em(17, 59, seg: 59), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1, "ainda dentro")
        // às 18:00 a janela fecha: segue valendo só pela folga de 4 s, e sai
        XCTAssertEqual(m.avaliar(entrada(em(18, 0, seg: 1), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1)
        XCTAssertEqual(m.avaliar(entrada(em(18, 0, seg: 6), sessoes: 1), regras: r, perfis: perfis, pausada: false), [], "o fim é exclusivo")
        var fds = motor()
        XCTAssertEqual(fds.avaliar(entrada(em(10, dia: 21), sessoes: 1), regras: r, perfis: perfis, pausada: false), [], "sábado fica de fora")
    }

    func testJanelaQueVirouAMeiaNoite() {
        var m = motor()
        let r = [regra(de: "22:00", ate: "06:00")]
        XCTAssertEqual(m.avaliar(entrada(em(23), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1)
        var m2 = motor()
        XCTAssertEqual(m2.avaliar(entrada(em(5, 30), sessoes: 1), regras: r, perfis: perfis, pausada: false).count, 1)
        var m3 = motor()
        XCTAssertEqual(m3.avaliar(entrada(em(12), sessoes: 1), regras: r, perfis: perfis, pausada: false), [])
    }

    func testFonteHorarioValeSoDentroDaJanela() {
        var m = motor()
        let r = [regra(fonte: "horario", tipo: "composicao", alvo: "c", dias: [3], de: "12:00", ate: "13:00")]
        XCTAssertEqual(m.avaliar(entrada(em(11, 59)), regras: r, perfis: perfis, pausada: false), [])
        let a = m.avaliar(entrada(em(12, 0, seg: 1)), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(a.map(\.texto), ["Trocando para Relógio e mês"])
    }

    func testUsoAcimaDoLimite() {
        var m = motor()
        let r = [regra(fonte: "uso", limite: 80)]
        XCTAssertEqual(m.avaliar(entrada(em(10), uso: 79), regras: r, perfis: perfis, pausada: false), [])
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 1), uso: 80), regras: r, perfis: perfis, pausada: false).count, 1)
        var m2 = motor()
        XCTAssertEqual(m2.avaliar(entrada(em(10), uso: nil), regras: r, perfis: perfis, pausada: false), [], "sem medição não dispara")
    }

    func testSpotifyEMeet() {
        var m = motor()
        let r = [regra("sp", fonte: "spotify", tipo: "tela", alvo: "player"), regra("mt", fonte: "meet", tipo: "tela", alvo: "meet")]
        XCTAssertEqual(m.avaliar(entrada(em(10), meet: true, spotify: true), regras: r, perfis: perfis, pausada: false).map(\.id), ["sp", "mt"])
    }

    func testAvisoRecebidoQuandoONumeroDeNaoLidasSobe() {
        var m = motor()
        let r = [regra(fonte: "aviso", tipo: "aviso", alvo: "Mensagem nova")]
        XCTAssertEqual(m.avaliar(entrada(em(10), naoLidas: 3), regras: r, perfis: perfis, pausada: false), [], "o total que já existia não é aviso")
        let a = m.avaliar(entrada(em(10, 0, seg: 5), naoLidas: 4), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(a.map(\.texto), ["Mensagem nova"])
        XCTAssertEqual(a[0].tipo, "aviso")
        // 30 s depois a condição acaba e, com a folga, a regra sai
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 40), naoLidas: 4), regras: r, perfis: perfis, pausada: false).count, 1)
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 45), naoLidas: 4), regras: r, perfis: perfis, pausada: false), [])
    }

    func testPerfilQueNaoExisteMaisFicaParado() {
        var m = motor()
        XCTAssertEqual(m.avaliar(entrada(em(10), sessoes: 1), regras: [regra(tipo: "perfil", alvo: "sumiu")], perfis: perfis, pausada: false), [])
        var m2 = motor()
        let a = m2.avaliar(entrada(em(10), sessoes: 1), regras: [regra(tipo: "perfil", alvo: "palco")], perfis: perfis, pausada: false)
        XCTAssertEqual(a.map(\.texto), ["Trocando para o perfil Palco"])
    }

    func testRegraRemovidaDaListaSaiDoMotor() {
        var m = motor()
        _ = m.avaliar(entrada(em(10), sessoes: 1), regras: [regra()], perfis: perfis, pausada: false)
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 1), sessoes: 1), regras: [], perfis: perfis, pausada: false), [])
    }

    func testTestarDisparaSemCondicaoPausaNemRegraLigadaEExpiraEm15s() {
        var m = motor()
        let r = [regra(ligada: false)]
        m.testar("r1", agora: em(10))
        let a = m.avaliar(entrada(em(10, 0, seg: 1)), regras: r, perfis: perfis, pausada: true)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 14)), regras: r, perfis: perfis, pausada: true).count, 1)
        // o teste acabou aos 15 s e a folga de 4 s desfaz
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 16)), regras: r, perfis: perfis, pausada: true).count, 1)
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 21)), regras: r, perfis: perfis, pausada: true), [])
    }

    func testTesteIgnoraODescanso() {
        var m = motor()
        let r = [regra(descanso: 60)]
        _ = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        _ = m.avaliar(entrada(em(10, 0, seg: 10)), regras: r, perfis: perfis, pausada: false)
        m.testar("r1", agora: em(10, 1))
        XCTAssertEqual(m.avaliar(entrada(em(10, 1, seg: 1)), regras: r, perfis: perfis, pausada: false).count, 1)
    }

    func testAbaDoWhatsAppFechadaQueReabreNaoViraMensagemNova() {
        var m = motor()
        let r = [regra(fonte: "aviso", tipo: "aviso", alvo: "Mensagem nova")]
        XCTAssertEqual(m.avaliar(entrada(em(10), naoLidas: 5), regras: r, perfis: perfis, pausada: false), [])
        // aba fechada: o total 0 não é medição
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 5), naoLidas: 0, whatsappAberto: false), regras: r, perfis: perfis, pausada: false), [])
        // reabre com as mesmas 5 não lidas: nada chegou
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 10), naoLidas: 5), regras: r, perfis: perfis, pausada: false), [])
        // e uma mensagem de verdade ainda dispara
        XCTAssertEqual(m.avaliar(entrada(em(10, 0, seg: 15), naoLidas: 6), regras: r, perfis: perfis, pausada: false).count, 1)
    }

    func testTestarDeNovoComARegraAindaAtivaGeraSeqNovo() {
        var m = motor()
        let r = [regra(fonte: "meet", durar: true, descanso: 60)]
        let a = m.avaliar(entrada(em(10), meet: true), regras: r, perfis: perfis, pausada: false)
        m.testar("r1", agora: em(10, 0, seg: 2))
        let b = m.avaliar(entrada(em(10, 0, seg: 3), meet: true), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(b.count, 1)
        XCTAssertNotEqual(a[0].seq, b[0].seq, "Testar com a regra já ativa precisa de seq novo, senão o iPhone descarta")
        // e um teste a mais dentro da histerese do teste anterior também
        var n = motor()
        let t = [regra(ligada: false)]
        n.testar("r1", agora: em(10))
        let c = n.avaliar(entrada(em(10, 0, seg: 1)), regras: t, perfis: perfis, pausada: false)
        _ = n.avaliar(entrada(em(10, 0, seg: 17)), regras: t, perfis: perfis, pausada: false)
        n.testar("r1", agora: em(10, 0, seg: 18))
        let d = n.avaliar(entrada(em(10, 0, seg: 19)), regras: t, perfis: perfis, pausada: false)
        XCTAssertEqual(d.count, 1)
        XCTAssertNotEqual(c[0].seq, d[0].seq)
    }

    func testSessaoNovaComOutraPendenteDisparaDeNovoDepoisDoDescanso() {
        var m = motor()
        let r = [regra(descanso: 1)]
        let a = m.avaliar(entrada(em(10), sessoes: 1, ids: ["s1"]), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(a.count, 1)
        // chega a segunda dentro do descanso: segue o mesmo seq
        let b = m.avaliar(entrada(em(10, 0, seg: 20), sessoes: 2, ids: ["s1", "s2"]), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(b[0].seq, a[0].seq)
        // passado o descanso, a terceira dispara de novo
        let c = m.avaliar(entrada(em(10, 2), sessoes: 3, ids: ["s1", "s2", "s3"]), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(c.count, 1)
        XCTAssertNotEqual(c[0].seq, a[0].seq)
        // sem sessão nova o seq não muda
        let d = m.avaliar(entrada(em(10, 2, seg: 5), sessoes: 3, ids: ["s1", "s2", "s3"]), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(d[0].seq, c[0].seq)
    }

    func testSessaoNovaSemDescansoDisparaNaHora() {
        var m = motor()
        let r = [regra(descanso: 0)]
        let a = m.avaliar(entrada(em(10), sessoes: 1, ids: ["s1"]), regras: r, perfis: perfis, pausada: false)
        let b = m.avaliar(entrada(em(10, 0, seg: 2), sessoes: 2, ids: ["s1", "s2"]), regras: r, perfis: perfis, pausada: false)
        XCTAssertNotEqual(a[0].seq, b[0].seq)
    }

    func testDisparosNovosTemSeqDiferenteMesmoNoMesmoInstante() {
        var m = motor()
        let r = [regra("a", descanso: 0), regra("b", descanso: 0)]
        let a = m.avaliar(entrada(em(10), sessoes: 1), regras: r, perfis: perfis, pausada: false)
        XCTAssertEqual(Set(a.map(\.seq)).count, 2)
    }
}

final class RegrasConfigTestes: XCTestCase {
    func testConfigNovaTraz_AsDuasRegrasDeExemploDesligadas() {
        let c = Config.padrao(nomeMac: "Mac")
        XCTAssertEqual(c.regras.map(\.nome), ["Sessão pede você: ir para Sessões", "Meet em chamada: ir para o Meet"])
        XCTAssertTrue(c.regras.allSatisfy { !$0.ligada })
        XCTAssertEqual(c.regras[0].entao, AcaoDeRegra(tipo: "tela", alvo: "sessoes"))
        XCTAssertEqual(c.regras[1].entao, AcaoDeRegra(tipo: "tela", alvo: "meet"))
        XCTAssertNil(Config.validar(c))
    }

    func testConfigAntigaSemARegraComecaComOsExemplos() throws {
        let json = #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"a","contas":[],"blocos":{},"nomeMac":"M"}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.regras, Regra.exemplos)
        XCTAssertFalse(c.regrasPausadas)
    }

    func testListaVaziaFicaVazia() throws {
        let json = #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"a","contas":[],"blocos":{},"nomeMac":"M","regras":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).regras, [])
    }

    func testRegraQuebradaSaiDaListaESemDerrubarAConfig() throws {
        let json = #"""
        {"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"a","contas":[],"blocos":{},"nomeMac":"M",
         "regras":[{"id":"x"},{"id":"ok","nome":"Ok","quando":{"fonte":"spotify"},"entao":{"tipo":"tela","alvo":"player"}}],"regrasPausadas":true}
        """#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.regras.map(\.id), ["ok"])
        XCTAssertFalse(c.regras[0].ligada, "o que falta volta ao padrão: desligada")
        XCTAssertEqual(c.regras[0].descanso, 5)
        XCTAssertEqual(c.regras[0].prioridade, 5)
        XCTAssertTrue(c.regrasPausadas)
    }

    func testIdaEVoltaPeloJson() throws {
        var c = Config.padrao(nomeMac: "Mac")
        c.regras.append(regra("nova", fonte: "uso", limite: 85, tipo: "aviso", alvo: "Uso alto", dias: [1, 2], de: "08:00", ate: "20:00", durar: true, descanso: 30, prioridade: 7))
        c.regrasPausadas = true
        let volta = try JSONDecoder().decode(Config.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(volta.regras, c.regras)
        XCTAssertTrue(volta.regrasPausadas)
    }

    func testConfigPublicaLevaAsRegras() {
        var c = Config.padrao(nomeMac: "Mac")
        c.regrasPausadas = true
        XCTAssertEqual(c.publica.regras, c.regras)
        XCTAssertTrue(c.publica.regrasPausadas)
    }

    func testValidarRecusaRegraRuim() {
        func erro(_ r: Regra) -> String? { var c = Config.padrao(nomeMac: "Mac"); c.regras = [r]; return Config.validar(c) }
        XCTAssertNil(erro(regra()))
        XCTAssertNotNil(erro(Regra(id: "", nome: "A", quando: Gatilho(fonte: "sessao"), entao: AcaoDeRegra(tipo: "tela", alvo: "meet"))))
        XCTAssertNotNil(erro(Regra(id: "a", nome: "  ", quando: Gatilho(fonte: "sessao"), entao: AcaoDeRegra(tipo: "tela", alvo: "meet"))))
        XCTAssertNotNil(erro(regra(fonte: "lua")))
        XCTAssertNotNil(erro(regra(fonte: "uso", limite: nil)))
        XCTAssertNotNil(erro(regra(fonte: "uso", limite: 101)))
        XCTAssertNil(erro(regra(fonte: "uso", limite: 100)))
        XCTAssertNotNil(erro(regra(tipo: "tela", alvo: "nada")))
        XCTAssertNotNil(erro(regra(tipo: "composicao", alvo: "z")))
        XCTAssertNotNil(erro(regra(tipo: "aviso", alvo: "   ")))
        XCTAssertNotNil(erro(regra(tipo: "aviso", alvo: String(repeating: "a", count: 121))))
        XCTAssertNotNil(erro(regra(tipo: "voar", alvo: "x")))
        XCTAssertNotNil(erro(regra(dias: [7])))
        XCTAssertNotNil(erro(regra(de: "9:00", ate: "18:00")))
        XCTAssertNotNil(erro(regra(de: "25:00", ate: "18:00")))
        XCTAssertNotNil(erro(regra(de: "09:00", ate: nil)), "uma hora só não vale")
        XCTAssertNotNil(erro(regra(fonte: "horario")), "horário sem janela não faz sentido")
        XCTAssertNil(erro(regra(fonte: "horario", de: "09:00", ate: "10:00")))
        XCTAssertNotNil(erro(regra(descanso: -1)))
        XCTAssertNotNil(erro(regra(descanso: 1441)))
        XCTAssertNotNil(erro(regra(prioridade: 0)))
        XCTAssertNotNil(erro(regra(prioridade: 10)))
    }

    func testValidarRecusaIdRepetidoMasAceitaPerfilQueSumiu() {
        var c = Config.padrao(nomeMac: "Mac")
        c.regras = [regra("a"), regra("a")]
        XCTAssertNotNil(Config.validar(c))
        c.regras = [regra("a", tipo: "perfil", alvo: "apagado")]
        XCTAssertNil(Config.validar(c), "excluir um perfil nunca pode ser barrado por uma regra")
    }

    func testPutPartialNaoApagaAsRegras() throws {
        var atual = Config.padrao(nomeMac: "Mac")
        atual.regras = [regra("minha", ligada: true)]
        atual.regrasPausadas = true
        // painel velho: devolve a config sem as chaves novas
        let corpo = #"{"perfis":[{"id":"trabalho","nome":"Trabalho","teclas":[]}],"perfilAtivo":"trabalho","comp":"b","contas":[],"blocos":{},"nomeMac":"Mac"}"#
        let nova = try Config.receber(corpo: Data(corpo.utf8), sobre: atual).get()
        XCTAssertEqual(nova.regras.map(\.id), ["minha"])
        XCTAssertTrue(nova.regrasPausadas)
        XCTAssertEqual(nova.comp, "b")
    }

    func testPutComRegrasGrava() throws {
        let atual = Config.padrao(nomeMac: "Mac")
        let corpo = #"{"perfis":[{"id":"trabalho","nome":"Trabalho","teclas":[]}],"perfilAtivo":"trabalho","comp":"a","contas":[],"blocos":{},"nomeMac":"Mac","regras":[],"regrasPausadas":true}"#
        let nova = try Config.receber(corpo: Data(corpo.utf8), sobre: atual).get()
        XCTAssertEqual(nova.regras, [])
        XCTAssertTrue(nova.regrasPausadas)
    }

    func testResumoEmFrase() {
        XCTAssertEqual(Regra.exemplos[0].resumo(), "Quando uma sessão pede você, ir para Sessões")
        let r = regra(fonte: "uso", limite: 85, tipo: "perfil", alvo: "palco", dias: [1, 3], de: "08:00", ate: "20:00")
        XCTAssertEqual(r.resumo(perfis: perfis), "Quando o uso das IAs passar de 85%, trocar para o perfil Palco (seg, qua, 08:00 às 20:00)")
        XCTAssertEqual(regra(dias: [0, 1, 2, 3, 4, 5, 6]).resumo(), "Quando uma sessão pede você, ir para Sessões", "todos os dias não precisa dizer")
    }

    func testNovaRegraTemIdQueNaoRepeteEValida() {
        var lista = Regra.exemplos
        let nova = Regra.nova(entre: lista)
        XCTAssertFalse(lista.contains { $0.id == nova.id })
        lista.append(nova)
        XCTAssertNil(Config.validarRegras(lista))
        lista.append(Regra.nova(entre: lista))
        XCTAssertEqual(Set(lista.map(\.id)).count, 4)
        XCTAssertFalse(nova.ligada, "regra nova nasce desligada")
    }

    func testAlvoPadraoDeCadaTipoValida() {
        for tipo in AcaoDeRegra.tipos {
            var r = regra()
            r.entao = AcaoDeRegra(tipo: tipo, alvo: tipo == "aviso" ? "Oi" : AcaoDeRegra.alvoPadrao(tipo: tipo, perfis: perfis))
            XCTAssertNil(Config.validarRegras([r]), "tipo \(tipo)")
        }
        XCTAssertEqual(AcaoDeRegra.alvoPadrao(tipo: "perfil", perfis: perfis), "trabalho")
    }

    func testTextosDoEditorEDoTeste() {
        XCTAssertEqual(Regra.rotuloDoDescanso(0), "Sem descanso")
        XCTAssertEqual(Regra.rotuloDoDescanso(5), "5 min")
        XCTAssertEqual(Regra.rotuloDoDescanso(120), "2 h")
        XCTAssertEqual(Regra.avisoDoTeste(iphoneAoVivo: true), "Teste enviado ao iPhone")
        XCTAssertEqual(Regra.avisoDoTeste(iphoneAoVivo: false), "Nenhum iPhone ligado agora. O teste vale por 15 segundos")
        XCTAssertEqual(Regra.diasCurtos.count, 7)
        XCTAssertEqual(Regra.diasPorExtenso.count, 7)
        XCTAssertTrue(Regra.opcoesDeDescanso.allSatisfy { (0...Regra.descansoMaximo).contains($0) })
    }

    func testHoraValida() {
        XCTAssertEqual(Regra.minutos("09:30"), 570)
        XCTAssertNil(Regra.minutos("9:30"))
        XCTAssertNil(Regra.minutos("24:00"))
        XCTAssertNil(Regra.minutos("12:60"))
        XCTAssertNil(Regra.minutos("abc"))
    }
}

/// Estado e rota: o que o iPhone recebe.
final class RegrasNoEstadoTestes: XCTestCase {
    private struct PaineisComSessao: ProvedorPaineis {
        var quantas: Int
        func estado() -> Estado {
            Estado(agora: "2026-11-18T10:00:00Z", nomeMac: "Mac", perfilAtivo: "geral", comp: "a", blocos: Blocos(), spotify: nil, uso: [],
                   sessoes: (0..<quantas).map { Sessao(id: "s\($0)", nome: "A", projeto: "deck", pergunta: "Seguir?", desde: "2026-11-18T09:00:00Z") },
                   whatsapp: nil, agenda: nil, acesas: [], selos: [:], avisos: [])
        }
        func whatsapp() -> [ConversaWhatsApp] { [] }
        func agenda(de: String, dias: Int) -> [Evento] { [] }
        func sessoes() -> [Sessao] { [] }
        func capa() -> CapaAtual? { nil }
    }

    private final class MeetContado: MeetDoMac, @unchecked Sendable {
        var leituras = 0
        var naChamada = true
        func estado() -> EstadoMeet { leituras += 1; return EstadoMeet(aberta: true, naChamada: naChamada, microfone: .ligado, camera: .ligado) }
        func agir(_ acao: AcaoMeet) -> String? { nil }
    }

    private func cenario(sessoes: Int, regras: [Regra]) throws -> Cenario {
        var c = try Cenario()
        var cfg = configDeTeste(); cfg.regras = regras
        c.roteador = Roteador(paineis: PaineisComSessao(quantas: sessoes), teclas: TeclasFalsas(registro: c.registro), spotify: SpotifyFalso(registro: c.registro),
                              config: ArmazemFalso(cfg), pareamento: c.pareamento, pagina: ArquivosPagina(raiz: c.raiz), regras: VigiaDeRegras())
        return c
    }

    func testEstadoTrazARegraQueEstaValendo() throws {
        let c = try cenario(sessoes: 1, regras: [regra(durar: true)])
        let r = c.pedir("GET", "/api/estado")
        let lista = ((r.json as? [String: Any])?["regras"] as? [[String: Any]]) ?? []
        XCTAssertEqual(lista.count, 1)
        XCTAssertEqual(lista.first?["id"] as? String, "r1")
        XCTAssertEqual(lista.first?["texto"] as? String, "Indo para Sessões")
        XCTAssertEqual(lista.first?["tipo"] as? String, "tela")
        XCTAssertEqual(lista.first?["alvo"] as? String, "sessoes")
        XCTAssertEqual(lista.first?["durar"] as? Bool, true)
        XCTAssertEqual(lista.first?["segundos"] as? Int, 3)
        XCTAssertNotNil(lista.first?["seq"] as? Int)
    }

    func testEstadoSemRegraValendoNaoTrazAChave() throws {
        let c = try cenario(sessoes: 0, regras: [regra()])
        XCTAssertNil((c.pedir("GET", "/api/estado").json as? [String: Any])?["regras"])
        let desligada = try cenario(sessoes: 3, regras: [regra(ligada: false)])
        XCTAssertNil((desligada.pedir("GET", "/api/estado").json as? [String: Any])?["regras"])
    }

    func testMeetSoELidoQuandoUmaRegraLigadaUsa() throws {
        let meet = MeetContado()
        var c = try cenario(sessoes: 0, regras: [regra(fonte: "meet", ligada: false)])
        c.roteador.meet = meet
        _ = c.pedir("GET", "/api/estado")
        XCTAssertEqual(meet.leituras, 0)

        var d = try cenario(sessoes: 0, regras: [regra(fonte: "meet", tipo: "tela", alvo: "meet")])
        d.roteador.meet = meet
        let lista = ((d.pedir("GET", "/api/estado").json as? [String: Any])?["regras"] as? [[String: Any]]) ?? []
        XCTAssertEqual(lista.count, 1)
        _ = d.pedir("GET", "/api/estado")
        XCTAssertEqual(meet.leituras, 1, "a segunda leitura dentro de 3 s vem do cache")
    }

    func testVigiaTestarAparecenoEstado() throws {
        let vigia = VigiaDeRegras()
        var c = try cenario(sessoes: 0, regras: [regra(ligada: false)])
        c.roteador.regras = vigia
        XCTAssertNil((c.pedir("GET", "/api/estado").json as? [String: Any])?["regras"])
        vigia.testar("r1")
        let lista = ((c.pedir("GET", "/api/estado").json as? [String: Any])?["regras"] as? [[String: Any]]) ?? []
        XCTAssertEqual(lista.map { $0["id"] as? String }, ["r1"])
    }

    func testConfigPublicaDaRotaTrazAsRegras() throws {
        let c = try Cenario()
        let corpo = c.pedir("GET", "/api/config").json as? [String: Any]
        XCTAssertEqual((corpo?["regras"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(corpo?["regrasPausadas"] as? Bool, false)
        XCTAssertNil(corpo?["codigoAcesso"])
    }
}
