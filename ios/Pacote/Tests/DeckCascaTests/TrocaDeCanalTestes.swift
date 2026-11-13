import XCTest
@testable import DeckCasca

#if canImport(CryptoKit)

// Cabo e Bluetooth ao mesmo tempo: o cabo é o canal em uso quando está plugado, o Bluetooth assume quando ele
// sai, e a tela não percebe. O cabo é o de verdade (loopback, como o usbmuxd), o Bluetooth é o fio em memória.

@MainActor
final class TrocaDeCanalTestes: XCTestCase {
    private func gerenteDoCabo(segredo: String) -> (GerenteDoCabo, UInt16) {
        for _ in 0..<50 {
            let porta = UInt16.random(in: 30000..<40000)
            let g = GerenteDoCabo(porta: porta, prazoDoPedido: 10, segredo: { segredo })
            if g.iniciar() == nil {
                addTeardownBlock { g.parar() }
                return (g, porta)
            }
        }
        XCTFail("nenhuma porta livre")
        return (GerenteDoCabo(porta: 1), 1)
    }

    private struct Cenario {
        let casca: Casca
        let quadro: Quadro
        let porta: UInt16
        let macBt: MacDeTeste
        let cabo: GerenteDoCabo
        let bt: GerenteBluetooth
        let radio: RadioFalso
    }

    private func cenario(codigo: String = "ABCDEFGHIJKLMNOPQRST") -> Cenario {
        let (cabo, porta) = gerenteDoCabo(segredo: codigo)
        let macBt = MacDeTeste(codigoAcesso: codigo)
        let cofre = CofreEmMemoria(Pareado(codigoAcesso: codigo, nomeMac: macBt.nome, idBluetooth: "mac-1"))
        let radio = RadioFalso(macBt)
        let bt = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone", esperaEntreTentativas: { _ in 0.05 })
        addTeardownBlock { bt.parar() }
        let quadro = Quadro()
        let casca = Casca(pareador: PareadorCompleto(cabo: cabo, bluetooth: bt), cofre: cofre, vibrar: {}, permanenciaNoCabo: 0, cabo: cabo, bluetooth: bt)
        casca.executarJS = { quadro.js.append($0) }
        return Cenario(casca: casca, quadro: quadro, porta: porta, macBt: macBt, cabo: cabo, bt: bt, radio: radio)
    }

    private func requisitar(_ c: Casca, _ metodo: String = "GET", _ caminho: String = "/api/estado") async -> String {
        await c.tratar(Data(#"{"op":"requisitar","metodo":"\#(metodo)","caminho":"\#(caminho)","cabecalhos":{"x-deck-codigo":"ABCDEFGHIJKLMNOPQRST"}}"#.utf8))
    }

    func testComOsDoisConectadosOCaboEhOCanalEmUso() async throws {
        let c = cenario()
        c.casca.iniciar()
        await esperar { c.bt.mac != nil }
        _ = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        XCTAssertEqual(c.casca.canais.obter()?.tipo, .cabo)
        XCTAssertNotNil(c.bt.mac, "o Bluetooth continua conectado, pronto para assumir")
    }

    func testPuxarOCaboTrocaParaOBluetoothComOAvisoEATelaNaoCai() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        let antes = await requisitar(c.casca)
        XCTAssertTrue(antes.contains("\"status\":200"), antes)

        c.quadro.js = []
        mac.cair()
        await esperar { c.casca.canais.obter()?.tipo == .bluetooth }
        XCTAssertEqual(c.casca.canais.obter()?.tipo, .bluetooth, "troca direto, sem passar por 'sem canal'")
        XCTAssertEqual(c.quadro.js, ["DeckNativo.canal(\"bluetooth\")"], "um aviso só, de 3 s, dizendo Pelo Bluetooth")
        let r = await requisitar(c.casca)
        XCTAssertTrue(r.contains("\"status\":200"), r)
        XCTAssertEqual(c.macBt.vistos.last?.caminho, "/api/estado")
    }

    func testPlugarDeNovoVoltaParaOCaboComAviso() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        mac.cair()
        await esperar { c.casca.canais.obter()?.tipo == .bluetooth }
        c.quadro.js = []
        _ = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        XCTAssertEqual(c.casca.canais.obter()?.tipo, .cabo)
        XCTAssertEqual(c.quadro.js, ["DeckNativo.canal(\"cabo\")"])
    }

    /// O cabo sai no meio de uma leitura que já tinha ido: a leitura é repetida no Bluetooth e a página recebe a resposta.
    func testLeituraNoMeioDaTrocaEhRepetidaNoBluetooth() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        mac.responder = { _ in nil }   // o Mac pelo cabo não responde: o pedido fica pendente
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        let casca = c.casca
        let pendente = Task { @MainActor in await casca.tratar(Data(#"{"op":"requisitar","metodo":"GET","caminho":"/api/estado","cabecalhos":{"x-deck-codigo":"ABCDEFGHIJKLMNOPQRST"}}"#.utf8)) }
        try await Task.sleep(nanoseconds: 200_000_000)
        mac.cair()
        let r = await pendente.value
        XCTAssertTrue(r.contains("\"status\":200"), r)
        XCTAssertEqual(c.macBt.vistos.last?.caminho, "/api/estado")
    }

    /// Tecla não se repete: se a resposta se perdeu, o Mac pode ter executado, e repetir apertaria duas vezes.
    func testTeclaNoMeioDaTrocaNaoEhRepetida() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        mac.responder = { _ in nil }
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        let casca = c.casca
        let pendente = Task { @MainActor in await casca.tratar(Data(#"{"op":"requisitar","metodo":"POST","caminho":"/api/botao/teste","cabecalhos":{"x-deck-codigo":"ABCDEFGHIJKLMNOPQRST"}}"#.utf8)) }
        try await Task.sleep(nanoseconds: 200_000_000)
        mac.cair()
        let r = await pendente.value
        XCTAssertTrue(r.contains("\"erro\":\"canal\""), r)
        XCTAssertFalse(c.macBt.vistos.contains { $0.caminho == "/api/botao/teste" })
    }

    func testBluetoothSaindoComOCaboPlugadoNaoMudaOCanalNemAvisa() async throws {
        let c = cenario()
        c.casca.iniciar()
        _ = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        await esperar { c.bt.mac != nil }
        c.quadro.js = []
        c.macBt.sairDoAlcance()
        await esperar { c.bt.mac == nil }
        XCTAssertEqual(c.casca.canais.obter()?.tipo, .cabo)
        XCTAssertTrue(c.quadro.js.isEmpty)
    }

    /// 13/11/2026: o Bluetooth cai com o cabo plugado (o Mac fechou o enlace) e depois o cabo sai. Sem religar nada, o
    /// Bluetooth tem que voltar sozinho e virar o canal.
    func testBluetoothQueCaiuComOCaboPlugadoVoltaSozinhoQuandoOCaboSai() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        await esperar { c.bt.mac != nil }
        c.macBt.sairDoAlcance()
        await esperar { c.bt.mac == nil }
        mac.cair()
        await esperar { c.casca.canais.obter()?.tipo == .bluetooth }
        XCTAssertEqual(c.casca.canais.obter()?.tipo, .bluetooth)
        let r = await requisitar(c.casca)
        XCTAssertTrue(r.contains("\"status\":200"), r)
    }

    func testSemNenhumDosDoisAPaginaVeSemCanal() async throws {
        let c = cenario()
        c.casca.iniciar()
        let mac = try MacFalso(porta: c.porta, segredo: "ABCDEFGHIJKLMNOPQRST")
        await esperar { c.casca.canais.obter()?.tipo == .cabo }
        c.radio.recusaConectar = true
        c.macBt.sairDoAlcance()
        mac.cair()
        await esperar { c.casca.canais.obter() == nil }
        let r = await requisitar(c.casca)
        XCTAssertTrue(r.contains("semCanal"), r)
    }
}
#endif
