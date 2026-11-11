import XCTest
@testable import DeckCasca

@MainActor
final class FluxoTestes: XCTestCase {
    private func fluxo(_ pareador: Pareador = PareadorFalso(), cofre: Cofre = CofreEmMemoria()) -> FluxoPareamento {
        FluxoPareamento(pareador: pareador, cofre: cofre, permanenciaNoCabo: 0)
    }

    func testPrimeiraAberturaSemMacComecaVazia() {
        let f = fluxo()
        f.iniciar()
        XCTAssertEqual(f.estado.etapa, .vazio)
        XCTAssertTrue(f.estado.macs.isEmpty)
    }

    func testComMacPareadoAbreNoPainel() {
        let f = fluxo(cofre: CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "MacBook Pro de Exemplo")))
        f.iniciar()
        XCTAssertEqual(f.estado.etapa, .painel)
        XCTAssertEqual(f.estado.nomeMac, "MacBook Pro de Exemplo")
    }

    // MARK: Bluetooth, o caminho principal

    func testProcurarListaOsMacsPorPerto() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        XCTAssertEqual(f.estado.etapa, .procurando)
        XCTAssertEqual(f.estado.macs.map(\.nome), ["MacBook Pro de Exemplo", "Mac mini do estúdio"])
    }

    func testEscolherUmMacMostraOCodigoParaConferir() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        let erro = await f.tratar(.escolher("mac-1"))
        XCTAssertNil(erro)
        XCTAssertEqual(f.estado.etapa, .confirmar)
        XCTAssertEqual(f.estado.codigo, "483 291")
        XCTAssertEqual(f.estado.nomeMac, "MacBook Pro de Exemplo")
    }

    func testMacLongeNaoPareia() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        _ = await f.tratar(.escolher("mac-2"))
        XCTAssertEqual(f.estado.etapa, .procurando)
    }

    func testConfirmarGravaOCodigoENaPronto() async {
        let cofre = CofreEmMemoria()
        let f = fluxo(cofre: cofre)
        var pareados: [PareamentoFeito] = []
        f.aoPareado = { pareados.append($0) }
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        _ = await f.tratar(.escolher("mac-1"))
        let erro = await f.tratar(.confirmar(true))
        XCTAssertNil(erro)
        XCTAssertEqual(f.estado.etapa, .pronto)
        XCTAssertEqual(f.estado.via, .bluetooth)
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "ABCDEFGHIJKLMNOPQRST")
        XCTAssertEqual(pareados.count, 1)
        XCTAssertEqual(pareados.first?.canal.tipo, .bluetooth)
    }

    func testNaoSaoIguaisRecusaEVoltaAoComeco() async {
        let p = PareadorFalso()
        let cofre = CofreEmMemoria()
        let f = fluxo(p, cofre: cofre)
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        _ = await f.tratar(.escolher("mac-1"))
        _ = await f.tratar(.confirmar(false))
        XCTAssertEqual(f.estado.etapa, .vazio)
        XCTAssertEqual(p.concluidos, [false])
        XCTAssertNil(cofre.ler())
    }

    func testFalhaAoEscolherVoltaParaALista() async {
        let p = PareadorFalso()
        p.falhaAoIniciar = .recusado("Não consegui falar com esse Mac. Tente de novo.")
        let f = fluxo(p)
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        let erro = await f.tratar(.escolher("mac-1"))
        XCTAssertEqual(erro, "Não consegui falar com esse Mac. Tente de novo.")
        XCTAssertEqual(f.estado.etapa, .procurando)
    }

    func testAbrirOPainelDepoisDoPronto() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        _ = await f.tratar(.escolher("mac-1"))
        _ = await f.tratar(.confirmar(true))
        _ = await f.tratar(.abrirPainel)
        XCTAssertEqual(f.estado.etapa, .painel)
    }

    // MARK: Cabo com código, a segunda via

    func testSegundaViaPeloCaboChegaNoCodigoDigitado() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        XCTAssertEqual(f.estado.etapa, .codigo)
        XCTAssertEqual(f.estado.nomeMac, "MacBook Pro de Exemplo")
    }

    func testCodigoCertoPareiaPeloCabo() async {
        let cofre = CofreEmMemoria()
        let f = fluxo(cofre: cofre)
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        let erro = await f.tratar(.digitos("483291"))
        XCTAssertNil(erro)
        XCTAssertEqual(f.estado.etapa, .pronto)
        XCTAssertEqual(f.estado.via, .cabo)
        XCTAssertEqual(cofre.ler()?.nomeMac, "MacBook Pro de Exemplo")
    }

    func testCodigoErradoAvisaEContinuaNaTela() async {
        let cofre = CofreEmMemoria()
        let f = fluxo(cofre: cofre)
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        let erro = await f.tratar(.digitos("000000"))
        XCTAssertEqual(erro, "Código errado. Confira o que aparece no Mac.")
        XCTAssertEqual(f.estado.etapa, .codigo)
        XCTAssertNil(cofre.ler())
    }

    func testCodigoComTamanhoErradoNemChegaNoPareador() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        let erro = await f.tratar(.digitos("48329"))
        XCTAssertEqual(erro, "O código tem 6 dígitos.")
        XCTAssertEqual(f.estado.etapa, .codigo)
    }

    func testVoltarParaOBluetoothDaProcuraNoCabo() async {
        let f = fluxo(PareadorSemMac())
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        XCTAssertEqual(f.estado.etapa, .cabo)
        _ = await f.tratar(.voltarParaBluetooth)
        XCTAssertEqual(f.estado.etapa, .procurando)
    }

    func testVoltarDoCodigoVaiParaAProcuraNoCabo() async {
        let f = fluxo()
        f.iniciar()
        _ = await f.tratar(.procurar)
        _ = await f.tratar(.cabo)
        await esperar { f.estado.etapa == .codigo }
        _ = await f.tratar(.voltar)
        XCTAssertTrue([.cabo, .codigo].contains(f.estado.etapa))
    }

    // MARK: Sem canal nenhum (esta fase)

    func testSemCanalNenhumOAppFicaProcurandoSemMacs() async {
        let f = fluxo(PareadorSemMac())
        f.iniciar()
        _ = await f.tratar(.procurar)
        XCTAssertEqual(f.estado.etapa, .procurando)
        XCTAssertTrue(f.estado.macs.isEmpty)
        _ = await f.tratar(.cabo)
        XCTAssertEqual(f.estado.etapa, .cabo)
    }

    // MARK: Esquecer o Mac (código recusado pelo Mac)

    func testEsquecerApagaOCofreEVoltaAoComeco() async {
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: "CODIGOATUAL", nomeMac: "Mac"))
        let f = fluxo(cofre: cofre)
        f.iniciar()
        _ = await f.tratar(.esquecer)
        XCTAssertNil(cofre.ler())
        XCTAssertEqual(f.estado.etapa, .vazio)
    }

    func testMudancaDeEtapaAvisaQuemEstaOuvindo() async {
        let f = fluxo()
        var etapas: [Etapa] = []
        f.aoMudar = { etapas.append($0.etapa) }
        f.iniciar()
        _ = await f.tratar(.procurar)
        XCTAssertEqual(etapas.first, .vazio)
        XCTAssertTrue(etapas.contains(.procurando))
    }
}

/// Pareador lento: reproduz respostas que chegam depois de a pessoa já ter mexido na tela.
final class PareadorLento: Pareador, @unchecked Sendable {
    private let base = PareadorFalso()
    private let trava = NSLock()
    private var chamadasDeConcluir = 0
    var atrasoDoIniciar: UInt64 = 0
    var atrasoDoConcluir: UInt64 = 0
    var concluirFalhaDaSegunda = false

    func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> { base.procurarPorBluetooth() }
    func iniciar(com mac: MacEncontrado) async throws -> String {
        try? await Task.sleep(nanoseconds: atrasoDoIniciar)
        return try await base.iniciar(com: mac)
    }
    func concluir(aceito: Bool) async throws -> PareamentoFeito {
        let n = trava.withLock { chamadasDeConcluir += 1; return chamadasDeConcluir }
        try? await Task.sleep(nanoseconds: atrasoDoConcluir)
        if concluirFalhaDaSegunda && n > 1 { throw ErroPareamento.recusado("Não consegui parear.") }
        return try await base.concluir(aceito: aceito)
    }
    func procurarNoCabo() -> AsyncStream<MacEncontrado> { base.procurarNoCabo() }
    func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito { try await base.parearComCodigo(mac, codigo) }
}

@MainActor
final class FluxoConcorrenciaTestes: XCTestCase {
    func testToqueDuploEmSaoIguaisContinuaPareado() async {
        let p = PareadorLento()
        p.atrasoDoConcluir = 100_000_000
        p.concluirFalhaDaSegunda = true
        let cofre = CofreEmMemoria()
        let f = FluxoPareamento(pareador: p, cofre: cofre, permanenciaNoCabo: 0)
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        _ = await f.tratar(.escolher("mac-1"))
        async let a = f.tratar(.confirmar(true))
        async let b = f.tratar(.confirmar(true))
        let erros = await [a, b]
        XCTAssertEqual(f.estado.etapa, .pronto)
        XCTAssertEqual(erros.compactMap { $0 }, [])
        XCTAssertNotNil(cofre.ler())
    }

    func testCaboDuranteAEscolhaNaoEDesfeitoPelaRespostaAtrasada() async {
        let p = PareadorLento()
        p.atrasoDoIniciar = 300_000_000
        let f = FluxoPareamento(pareador: p, cofre: CofreEmMemoria(), permanenciaNoCabo: 0)
        f.iniciar()
        _ = await f.tratar(.procurar)
        await esperar { f.estado.macs.count == 2 }
        async let escolha = f.tratar(.escolher("mac-1"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        _ = await f.tratar(.cabo)
        _ = await escolha
        XCTAssertNotEqual(f.estado.etapa, .confirmar)
        XCTAssertTrue([.cabo, .codigo].contains(f.estado.etapa), "ficou em \(f.estado.etapa)")
    }
}
