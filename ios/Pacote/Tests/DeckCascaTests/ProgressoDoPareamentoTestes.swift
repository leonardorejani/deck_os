import XCTest
@testable import DeckCasca

/// O toque em Parear tem resposta na hora: cada passo real do núcleo aparece no estado, com erro claro e "Tentar de novo".
@MainActor
final class ProgressoDoPareamentoTestes: XCTestCase {
    private func fluxo(_ p: PareadorFalso, cofre: Cofre = CofreEmMemoria(), achar: TimeInterval = 5, permitir: TimeInterval = 5) -> FluxoPareamento {
        FluxoPareamento(pareador: p, cofre: cofre, permanenciaNoCabo: 0, prazoParaAcharOMac: achar, prazoParaOMacPermitir: permitir)
    }

    private func naLista(_ f: FluxoPareamento) async {
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
    }

    func testTocarEmPareaMostraProcurandoOMacNaHoraEDepoisOCodigo() async {
        let p = PareadorFalso()
        p.atrasoAoIniciar = 0.3
        let f = fluxo(p)
        var vistos: [Progresso?] = []
        f.aoMudar = { vistos.append($0.progresso) }
        await naLista(f)
        XCTAssertNil(f.estado.progresso, "antes do toque não há progresso")
        let tocou = Task { await f.tratar(.escolher("mac-1")) }
        await esperar { f.estado.progresso == .procurandoMac }
        XCTAssertEqual(f.estado.progresso, .procurandoMac)
        XCTAssertEqual(f.estado.alvoId, "mac-1")
        XCTAssertEqual(f.estado.etapa, .procurando)
        _ = await tocou.value
        XCTAssertEqual(f.estado.etapa, .confirmar)
        XCTAssertNil(f.estado.progresso, "o código apareceu: o passo acabou")
        XCTAssertTrue(vistos.contains(.procurandoMac))
    }

    func testToqueDuploNaMesmaLinhaNaoPareiaDuasVezes() async {
        let p = PareadorFalso()
        p.atrasoAoIniciar = 0.3
        let f = fluxo(p)
        await naLista(f)
        let primeiro = Task { await f.tratar(.escolher("mac-1")) }
        await esperar { f.estado.progresso == .procurandoMac }
        let segundo = await f.tratar(.escolher("mac-1"))
        XCTAssertNil(segundo)
        _ = await primeiro.value
        XCTAssertEqual(p.iniciados, 1)
    }

    func testSaoIguaisMostraPareandoEDepoisPareado() async {
        let p = PareadorFalso()
        p.atrasoAoConcluir = 0.3
        let cofre = CofreEmMemoria()
        let f = fluxo(p, cofre: cofre)
        await naLista(f)
        _ = await f.tratar(.escolher("mac-1"))
        XCTAssertEqual(f.estado.etapa, .confirmar)
        let confirmou = Task { await f.tratar(.confirmar(true)) }
        await esperar { f.estado.progresso == .pareando }
        XCTAssertEqual(f.estado.progresso, .pareando)
        XCTAssertEqual(f.estado.etapa, .confirmar)
        let outroToque = await f.tratar(.confirmar(true))
        XCTAssertNil(outroToque)
        _ = await confirmou.value
        XCTAssertEqual(f.estado.etapa, .pronto)
        XCTAssertNil(f.estado.progresso)
        XCTAssertNil(f.estado.falha)
        XCTAssertNotNil(cofre.ler())
        XCTAssertEqual(p.concluidos, [true], "um toque só concluiu")
    }

    func testFalhaAoAcharOMacFicaNaTelaComOMotivoEOAlvo() async {
        let p = PareadorFalso()
        p.falhaAoIniciar = .recusado("O Mac não respondeu.")
        let f = fluxo(p)
        await naLista(f)
        let erro = await f.tratar(.escolher("mac-1"))
        XCTAssertEqual(erro, "O Mac não respondeu.")
        XCTAssertEqual(f.estado.etapa, .procurando)
        XCTAssertNil(f.estado.progresso)
        XCTAssertEqual(f.estado.falha, "O Mac não respondeu.")
        XCTAssertEqual(f.estado.alvoId, "mac-1")
    }

    func testTentarDeNovoDepoisDaFalhaPareiaEApagaOErro() async {
        let p = PareadorFalso()
        p.falhaAoIniciar = .recusado("O Mac não respondeu.")
        let f = fluxo(p)
        await naLista(f)
        _ = await f.tratar(.escolher("mac-1"))
        p.falhaAoIniciar = nil
        await esperar { f.estado.macs.count == 2 }
        let erro = await f.tratar(.escolher("mac-1"))
        XCTAssertNil(erro)
        XCTAssertEqual(f.estado.etapa, .confirmar)
        XCTAssertNil(f.estado.falha)
    }

    func testPassouDoPrazoDeAcharOMacViraErroClaroEDeixaTentarDeNovo() async {
        let p = PareadorFalso()
        p.atrasoAoIniciar = 0.6
        let f = fluxo(p, achar: 0.1)
        await naLista(f)
        let erro = await f.tratar(.escolher("mac-1"))
        XCTAssertEqual(erro, "O Mac não respondeu a tempo. Confira se o Deck está aberto nele e tente de novo.")
        XCTAssertEqual(f.estado.falha, erro)
        XCTAssertNil(f.estado.progresso)
        XCTAssertEqual(f.estado.etapa, .procurando)
        // a resposta que chega tarde não vira código na tela e a conversa é solta no Mac
        await esperar({ p.concluidos == [false] }, segundos: 2)
        XCTAssertEqual(p.concluidos, [false])
        XCTAssertEqual(f.estado.etapa, .procurando)
    }

    func testPassouDoPrazoDoMacPermitirVoltaParaALista() async {
        let p = PareadorFalso()
        p.atrasoAoConcluir = 0.6
        let f = fluxo(p, permitir: 0.1)
        await naLista(f)
        _ = await f.tratar(.escolher("mac-1"))
        let erro = await f.tratar(.confirmar(true))
        XCTAssertEqual(erro, "O Mac não permitiu a tempo. Toque em Permitir no Mac e tente de novo.")
        XCTAssertEqual(f.estado.etapa, .procurando)
        XCTAssertEqual(f.estado.falha, erro)
        XCTAssertEqual(f.estado.alvoId, "mac-1")
        XCTAssertNil(f.estado.progresso)
    }

    func testMacRecusouNoMacVoltaComOMotivo() async {
        let p = PareadorFalso()
        p.falhaAoConcluir = .recusado("O Mac recusou o pareamento.")
        let f = fluxo(p)
        await naLista(f)
        _ = await f.tratar(.escolher("mac-1"))
        let erro = await f.tratar(.confirmar(true))
        XCTAssertEqual(erro, "O Mac recusou o pareamento.")
        XCTAssertEqual(f.estado.falha, "O Mac recusou o pareamento.")
        XCTAssertEqual(f.estado.etapa, .procurando)
    }

    func testProcurarDeNovoLimpaAFalha() async {
        let p = PareadorFalso()
        p.falhaAoIniciar = .recusado("Nada.")
        let f = fluxo(p)
        await naLista(f)
        _ = await f.tratar(.escolher("mac-1"))
        XCTAssertNotNil(f.estado.falha)
        _ = await f.tratar(.procurar)
        XCTAssertNil(f.estado.falha)
        XCTAssertNil(f.estado.alvoId)
    }

    func testCodigoErradoPeloCaboTiraOProgressoEFicaNaTela() async {
        let f = fluxo(PareadorFalso())
        f.iniciar()
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        let erro = await f.tratar(.digitos("000000"))
        XCTAssertEqual(erro, "Código errado. Confira o que aparece no Mac.")
        XCTAssertNil(f.estado.progresso)
        XCTAssertEqual(f.estado.etapa, .codigo)
    }

    func testEstadoNovoCodificaComOsCamposDaTela() throws {
        let e = EstadoPareamento(etapa: .procurando, macs: [], progresso: .procurandoMac, alvoId: "mac-1", falha: nil)
        let json = try XCTUnwrap(Casca.json(e))
        XCTAssertTrue(json.contains("\"progresso\":\"procurandoMac\""))
        XCTAssertTrue(json.contains("\"alvoId\":\"mac-1\""))
    }
}
