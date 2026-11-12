import XCTest
@testable import DeckCasca

// O Bluetooth do iPhone sem rádio: o RadioBle de verdade (CoreBluetooth) é trocado por um que liga o iPhone a
// um "Mac" de teste por um par de fios em memória. O Mac de teste fala o mesmo aperto de mão cifrado e os
// mesmos quadros que mac/Nucleo/Bluetooth.swift. O rádio em si foi provado no aparelho (docs/provas/fase-7-bluetooth.md).

final class EnlaceTestes: XCTestCase {
    func testFilaEntregaNaOrdemEPartePeloMaximo() {
        let f = FilaDeBytes()
        f.empurrar(Data([1, 2, 3, 4, 5]))
        f.empurrar(Data([6]))
        XCTAssertEqual(f.ler(maximo: 2), Data([1, 2]))
        XCTAssertEqual(f.ler(maximo: 10), Data([3, 4, 5]))
        XCTAssertEqual(f.ler(maximo: 10), Data([6]))
    }

    func testParDeFluxosLevaOsBytesNosDoisSentidosEFecharAcabaALeitura() {
        let (a, b) = FluxoEnlace.par()
        XCTAssertTrue(a.escrever(Data("ida".utf8)))
        XCTAssertEqual(b.lerExato(3), Data("ida".utf8))
        a.fechar()
        XCTAssertNil(b.ler(maximo: 4))
        XCTAssertFalse(a.escrever(Data([1])))
    }

    /// O mesmo vetor existe em mac/Testes: o Mac e o iPhone têm que sortear os mesmos 6 dígitos.
    func testCodigoDeOuroIgualAoDoMac() {
        let t = Sas.transcricao(modo: "parear", chaveIphone: Data(repeating: 1, count: 32), nonceIphone: Data(repeating: 2, count: 16),
                                chaveMac: Data(repeating: 3, count: 32), nonceMac: Data(repeating: 4, count: 16), nomeMac: "MacBook Pro de Exemplo")
        XCTAssertEqual(ProvaCabo.hex([UInt8](t)), "d927e3550a83a65850b5c0512354b78a70b0661b0c563b85aaa348d84753a0ca")
        XCTAssertEqual(Sas.digitos(t), "532820")
    }

    func testMedidaDeVazaoPercorreOsTresPassosPeloFio() throws {
        let (mac, iphone) = FluxoEnlace.par()
        Thread { VazaoBluetooth.servir(mac) }.start()
        let r = try XCTUnwrap(VazaoBluetooth.medir(iphone, bytes: 20000, pings: 3))
        XCTAssertEqual(r.pings.count, 3)
        XCTAssertGreaterThan(r.descidaKBs, 0)
        iphone.fechar()
    }

    func testAnuncioFracoAparecePertoSoAcimaDoLimite() {
        XCTAssertTrue(AnuncioBle(id: "a", nome: "Mac", rssi: -40).perto)
        XCTAssertTrue(AnuncioBle(id: "a", nome: "Mac", rssi: AnuncioBle.sinalDePerto).perto)
        XCTAssertFalse(AnuncioBle(id: "a", nome: "Mac", rssi: -90).perto)
    }
}

#if canImport(CryptoKit)
import CryptoKit

final class Linhas: @unchecked Sendable {
    private let trava = NSLock()
    private var l: [String] = []
    func anotar(_ s: String) { trava.withLock { l.append(s) } }
    var todas: [String] { trava.withLock { l } }
}

/// O Mac do teste: aperto de mão de verdade, depois se apresenta e responde pedido por pedido.
final class MacDeTeste: @unchecked Sendable {
    let codigoAcesso: String
    let nome = "MacBook Pro de Exemplo"
    private let trava = NSLock()
    private var _aceitar = true
    private var _mostrados: [String] = []
    private var _vistos: [PedidoCanal] = []
    private var _fios: [FluxoEnlace] = []
    private var _chaves: [String]
    var extras: [String: String] = [:]
    var responder: @Sendable (PedidoCanal) -> RespostaCanal? = { _ in
        RespostaCanal(status: 200, tipo: "application/json", corpo: Data("{\"ok\":true}".utf8))
    }

    init(codigoAcesso: String = "ABCDEFGHIJKLMNOPQRST") {
        self.codigoAcesso = codigoAcesso
        _chaves = [codigoAcesso]
    }

    var aceitar: Bool { get { trava.withLock { _aceitar } } set { trava.withLock { _aceitar = newValue } } }
    var chaves: [String] { get { trava.withLock { _chaves } } set { trava.withLock { _chaves = newValue } } }
    var mostrados: [String] { trava.withLock { _mostrados } }
    var vistos: [PedidoCanal] { trava.withLock { _vistos } }

    /// Derruba todos os fios abertos, como se o Mac saísse do alcance.
    func sairDoAlcance() { for f in trava.withLock({ _fios }) { f.fechar() } }

    func atender(_ fio: FluxoEnlace) {
        trava.withLock { _fios.append(fio) }
        let cfg = EnlaceSeguro.ConfigServidor(
            nomeMac: nome, chaves: { [self] in chaves }, codigoAcesso: { [codigoAcesso] in codigoAcesso },
            decidir: { [self] iphone, codigo in trava.withLock { _mostrados.append(codigo) }; return aceitar },
            prazoDoAperto: 5, prazoDoIphone: 5)
        Thread { [self] in
            guard let seguro = try? EnlaceSeguro.servir(fio, cfg) else { fio.fechar(); return }
            _ = seguro.escrever(Quadros.codificar(MensagemCabo(tipo: "ola", nome: nome, versao: 1))!)
            while let m = Quadros.ler(de: seguro) {
                guard m.tipo == "pedido", let id = m.id, let p = m.pedido else { continue }
                trava.withLock { _vistos.append(p) }
                guard var r = responder(p) else { continue }
                for (k, v) in extras { r.cabecalhos[k] = v }
                _ = seguro.escrever(Quadros.codificar(MensagemCabo(tipo: "resposta", id: id, resposta: r))!)
            }
        }.start()
    }
}

final class RadioFalso: RadioBle, @unchecked Sendable {
    let mac: MacDeTeste
    private let trava = NSLock()
    private var _anuncios: [AnuncioBle]
    private var _conexoes = 0
    private var _indisponivel: String?
    private var _recusaConectar = false

    init(_ mac: MacDeTeste, anuncios: [AnuncioBle] = [AnuncioBle(id: "mac-1", nome: "MacBook Pro de Exemplo", rssi: -40)]) {
        self.mac = mac
        _anuncios = anuncios
    }

    var conexoes: Int { trava.withLock { _conexoes } }
    var recusaConectar: Bool { get { trava.withLock { _recusaConectar } } set { trava.withLock { _recusaConectar = newValue } } }
    var indisponivel: String? { get { trava.withLock { _indisponivel } } set { trava.withLock { _indisponivel = newValue } } }
    var pronto: Bool { indisponivel == nil }

    func procurar() -> AsyncStream<[AnuncioBle]> {
        let lista = trava.withLock { _anuncios }
        return AsyncStream { c in c.yield(lista) }
    }

    func conectar(id: String, prazo: TimeInterval) async throws -> FluxoBytes {
        if trava.withLock({ _recusaConectar }) { throw ErroPareamento.recusado("O Mac não respondeu.") }
        trava.withLock { _conexoes += 1 }
        let (macFio, iphoneFio) = FluxoEnlace.par()
        mac.atender(macFio)
        return iphoneFio
    }
}

/// O Mac trocou de endereço: conectar no id velho fica esperando para sempre (como o connect do iOS), e o Mac aparece na
/// procura com o id novo.
final class RadioComEnderecoNovo: RadioBle, @unchecked Sendable {
    let mac: MacDeTeste
    let velho: String
    let novo: String
    let nome: String
    private let trava = NSLock()
    private var _velho = 0
    private var _novo = 0
    init(mac: MacDeTeste, velho: String, novo: String, nome: String = "MacBook Pro de Exemplo") { self.mac = mac; self.velho = velho; self.novo = novo; self.nome = nome }
    var tentativasNoVelho: Int { trava.withLock { _velho } }
    var tentativasNoNovo: Int { trava.withLock { _novo } }
    var indisponivel: String? { nil }
    var pronto: Bool { true }
    func procurar() -> AsyncStream<[AnuncioBle]> { AsyncStream { c in c.yield([AnuncioBle(id: novo, nome: nome, rssi: -40)]) } }
    func conectar(id: String, prazo: TimeInterval) async throws -> FluxoBytes {
        if id == velho {
            trava.withLock { _velho += 1 }
            try await Task.sleep(nanoseconds: 3_600_000_000_000) // nunca completa; só sai se cancelarem
            throw ErroPareamento.recusado("O Mac não respondeu.")
        }
        trava.withLock { _novo += 1 }
        let (macFio, iphoneFio) = FluxoEnlace.par()
        mac.atender(macFio)
        return iphoneFio
    }
}

/// Dois Macs com Deck por perto: cada id fala com o seu.
final class RadioDeDoisMacs: RadioBle, @unchecked Sendable {
    let macs: [String: MacDeTeste]
    let anuncios: [AnuncioBle]
    private let trava = NSLock()
    private var _tentativas: [String: Int] = [:]
    init(macs: [String: MacDeTeste], anuncios: [AnuncioBle]) { self.macs = macs; self.anuncios = anuncios }
    func tentativas(_ id: String) -> Int { trava.withLock { _tentativas[id, default: 0] } }
    var indisponivel: String? { nil }
    var pronto: Bool { true }
    func procurar() -> AsyncStream<[AnuncioBle]> { AsyncStream { c in c.yield(anuncios) } }
    func conectar(id: String, prazo: TimeInterval) async throws -> FluxoBytes {
        trava.withLock { _tentativas[id, default: 0] += 1 }
        let (macFio, iphoneFio) = FluxoEnlace.par()
        macs[id]?.atender(macFio)
        return iphoneFio
    }
}

@MainActor
final class BluetoothTestes: XCTestCase {
    /// Verificação adversarial: iPhone pareado pelo cabo (sem id) com dois Macs por perto. O macOS não anuncia o
    /// nome do Deck, então o nome não acha o Mac certo e o mais forte pode ser o errado.
    func testReconexaoDeIphonePareadoPeloCaboAchaOMacCertoComDoisPorPerto() async throws {
        let errado = MacDeTeste(codigoAcesso: "ZZZZZZZZZZZZZZZZZZZZ")
        let certo = MacDeTeste()
        let radio = RadioDeDoisMacs(macs: ["errado": errado, "certo": certo], anuncios: [
            AnuncioBle(id: "errado", nome: "Mac mini do estudio", rssi: -30),
            AnuncioBle(id: "certo", nome: "iMac sem relacao com o nome pareado", rssi: -50),
        ])
        let cofre = CofreEmMemoria()
        cofre.gravar(Pareado(codigoAcesso: certo.codigoAcesso, nomeMac: "Mac do Leo", idBluetooth: nil))
        let linhas = Linhas()
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 }, log: { linhas.anotar($0) })
        addTeardownBlock { g.parar() }
        g.iniciar()
        await esperar({ g.mac != nil }, segundos: 6)
        XCTAssertEqual(g.mac?.id, "certo", "nunca conectou no Mac certo")
        XCTAssertEqual(cofre.ler()?.idBluetooth, "certo")
        XCTAssertLessThanOrEqual(radio.tentativas("errado"), 1)
    }

    private func gerente(_ radio: RadioFalso, cofre: Cofre = CofreEmMemoria()) -> (GerenteBluetooth, Linhas) {
        let linhas = Linhas()
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 }, log: { linhas.anotar($0) })
        addTeardownBlock { g.parar() }
        return (g, linhas)
    }

    private func casca(_ g: GerenteBluetooth, cofre: Cofre, cabo: GerenteDoCabo? = nil) -> (Casca, Quadro) {
        let quadro = Quadro()
        let c = Casca(pareador: PareadorCompleto(cabo: cabo ?? GerenteDoCabo(porta: 1), bluetooth: g), cofre: cofre, vibrar: {},
                      permanenciaNoCabo: 0, cabo: cabo, bluetooth: g)
        c.executarJS = { quadro.js.append($0) }
        return (c, quadro)
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }
    private func pareado(_ id: String? = "mac-1", codigo: String = "ABCDEFGHIJKLMNOPQRST") -> Pareado {
        Pareado(codigoAcesso: codigo, nomeMac: "MacBook Pro de Exemplo", idBluetooth: id)
    }

    // MARK: Pareamento principal

    func testPareamentoPeloBluetoothMostraOMesmoCodigoDoMacEGuardaTudo() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria()
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, quadro) = casca(g, cofre: cofre)
        c.iniciar()
        XCTAssertEqual(mac.mostrados.count, 0)

        _ = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        await esperar { c.fluxo.estado.macs.count == 1 }
        XCTAssertEqual(c.fluxo.estado.macs.first, MacEncontrado(id: "mac-1", nome: "MacBook Pro de Exemplo", perto: true))

        let r = await c.tratar(json(#"{"op":"acao","acao":"escolher","id":"mac-1"}"#))
        XCTAssertFalse(r.contains("erro"), r)
        XCTAssertEqual(c.fluxo.estado.etapa, .confirmar)
        let digitos = c.fluxo.estado.codigo.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(digitos.count, 6)
        XCTAssertEqual(mac.mostrados, [digitos], "o Mac mostra os mesmos 6 dígitos do iPhone")
        XCTAssertNil(cofre.ler(), "nada fica guardado antes de a pessoa confirmar")

        _ = await c.tratar(json(#"{"op":"acao","acao":"confirmar","ok":true}"#))
        XCTAssertEqual(c.fluxo.estado.etapa, .pronto)
        XCTAssertEqual(cofre.ler(), Pareado(codigoAcesso: mac.codigoAcesso, nomeMac: "MacBook Pro de Exemplo", idBluetooth: "mac-1"))
        XCTAssertTrue(quadro.js.contains("DeckCanal.codigo(\"\(mac.codigoAcesso)\")"))
        XCTAssertEqual(c.canais.obter()?.tipo, .bluetooth)
        XCTAssertTrue(quadro.js.contains("DeckNativo.canal(\"bluetooth\")"))

        // o pedido da página chega no Mac pelo fio cifrado e volta
        let resp = await c.tratar(json(#"{"op":"requisitar","metodo":"GET","caminho":"/api/estado","cabecalhos":{"x-deck-codigo":"\#(mac.codigoAcesso)"}}"#))
        XCTAssertTrue(resp.contains("\"status\":200"), resp)
        XCTAssertEqual(mac.vistos.first?.caminho, "/api/estado")
    }

    func testMacRecusandoVoltaParaAListaSemGuardarNada() async throws {
        let mac = MacDeTeste()
        mac.aceitar = false
        let cofre = CofreEmMemoria()
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        _ = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        await esperar { c.fluxo.estado.macs.count == 1 }
        _ = await c.tratar(json(#"{"op":"acao","acao":"escolher","id":"mac-1"}"#))
        let r = await c.tratar(json(#"{"op":"acao","acao":"confirmar","ok":true}"#))
        XCTAssertTrue(r.contains("recusado no Mac"), r)
        XCTAssertNil(cofre.ler())
        XCTAssertNil(c.canais.obter())
        XCTAssertEqual(c.fluxo.estado.etapa, .procurando)
    }

    func testIphoneRecusandoNaoGuardaNemUsaCanal() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria()
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        _ = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        await esperar { c.fluxo.estado.macs.count == 1 }
        _ = await c.tratar(json(#"{"op":"acao","acao":"escolher","id":"mac-1"}"#))
        _ = await c.tratar(json(#"{"op":"acao","acao":"confirmar","ok":false}"#))
        XCTAssertEqual(c.fluxo.estado.etapa, .vazio)
        XCTAssertNil(cofre.ler())
        XCTAssertNil(c.canais.obter())
    }

    func testMacLongeNaListaNaoPareia() async throws {
        let mac = MacDeTeste()
        let radio = RadioFalso(mac, anuncios: [AnuncioBle(id: "mac-1", nome: "Mac longe", rssi: -95)])
        let (g, _) = gerente(radio)
        let (c, _) = casca(g, cofre: CofreEmMemoria())
        c.iniciar()
        _ = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        await esperar { c.fluxo.estado.macs.count == 1 }
        XCTAssertFalse(c.fluxo.estado.macs[0].perto)
        _ = await c.tratar(json(#"{"op":"acao","acao":"escolher","id":"mac-1"}"#))
        XCTAssertEqual(c.fluxo.estado.etapa, .procurando)
        XCTAssertEqual(radio.conexoes, 0)
    }

    func testBluetoothDesligadoAvisaOMotivoAoProcurarEPronto() async throws {
        let radio = RadioFalso(MacDeTeste())
        radio.indisponivel = "O Bluetooth do iPhone está desligado. Ligue no Centro de Controle."
        let (g, _) = gerente(radio)
        let (c, _) = casca(g, cofre: CofreEmMemoria())
        c.iniciar()
        let r = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        XCTAssertTrue(r.contains("O Bluetooth do iPhone está desligado"), r)
        radio.indisponivel = nil
        let ok = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        XCTAssertFalse(ok.contains("erro"), ok)
    }

    func testBluetoothDesligadoDaMensagemClaraNoPareamento() async throws {
        let mac = MacDeTeste()
        let radio = RadioFalso(mac)
        radio.recusaConectar = true
        let (g, _) = gerente(radio)
        let (c, _) = casca(g, cofre: CofreEmMemoria())
        c.iniciar()
        _ = await c.tratar(json(#"{"op":"acao","acao":"procurar"}"#))
        await esperar { c.fluxo.estado.macs.count == 1 }
        let r = await c.tratar(json(#"{"op":"acao","acao":"escolher","id":"mac-1"}"#))
        XCTAssertTrue(r.contains("O Mac não respondeu."), r)
    }

    // MARK: Reconexão e troca de canal

    func testSemPareamentoOBluetoothNaoConectaNemPedePermissao() async throws {
        let radio = RadioFalso(MacDeTeste())
        let (g, _) = gerente(radio)
        let (c, _) = casca(g, cofre: CofreEmMemoria())
        c.iniciar()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(radio.conexoes, 0)
        XCTAssertNil(c.canais.obter())
    }

    func testPareadoConectaSozinhoAoAbrirEUsaOBluetooth() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria(pareado())
        let (g, linhas) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, quadro) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter()?.tipo == .bluetooth }
        XCTAssertEqual(c.canais.obter()?.tipo, .bluetooth, "\(linhas.todas)")
        XCTAssertTrue(quadro.js.contains("DeckNativo.canal(\"bluetooth\")"))
        let r = await c.tratar(json(#"{"op":"requisitar","metodo":"POST","caminho":"/api/botao/teste","cabecalhos":{"x-deck-codigo":"X"}}"#))
        XCTAssertTrue(r.contains("\"status\":200"), r)
        XCTAssertEqual(mac.vistos.last?.caminho, "/api/botao/teste")
    }

    func testSairDoAlcanceDerrubaOCanalEVoltarReconectaSemParearDeNovo() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria(pareado())
        let radio = RadioFalso(mac)
        let (g, _) = gerente(radio, cofre: cofre)
        let (c, quadro) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter() != nil }
        mac.sairDoAlcance()
        await esperar { c.canais.obter() == nil }
        // ao voltar o rádio conecta de novo, e o aviso de 3 segundos aparece de novo
        quadro.js = []
        await esperar({ c.canais.obter()?.tipo == .bluetooth }, segundos: 5)
        XCTAssertEqual(c.canais.obter()?.tipo, .bluetooth)
        XCTAssertEqual(radio.conexoes, 2)
        XCTAssertTrue(quadro.js.contains("DeckNativo.canal(\"bluetooth\")"))
        XCTAssertEqual(cofre.ler()?.codigoAcesso, mac.codigoAcesso, "reconectar não mexe no pareamento")
    }

    func testMacQueNaoReconheceOIphoneNaoViraCanal() async throws {
        let mac = MacDeTeste(codigoAcesso: "OUTROCODIGOOUTROCODI")
        let cofre = CofreEmMemoria(pareado(codigo: "CODIGOVELHOCODIGOVEL"))
        let (g, linhas) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNil(c.canais.obter())
        XCTAssertTrue(linhas.todas.contains { $0.contains("não reconhece este iPhone") }, "\(linhas.todas)")
    }

    /// Defeito de 11/11/2026: "Desconectar iPhone" no Mac mudou o código, nenhum canal conectava mais, a página nunca
    /// recebia 401 e o iPhone ficava em "Mac desconectado" para sempre em vez de voltar à tela de parear.
    func testMacQueDesconectouOIphoneFazOAppEsquecerEVoltarAParear() async throws {
        let mac = MacDeTeste(codigoAcesso: "OUTROCODIGOOUTROCODI")
        let cofre = CofreEmMemoria(pareado(codigo: "CODIGOVELHOCODIGOVEL"))
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        var recarregou = false
        c.recarregarPagina = { recarregou = true }
        c.iniciar()
        await esperar({ cofre.ler() == nil }, segundos: 5)
        XCTAssertNil(cofre.ler(), "o pareamento acabou")
        XCTAssertTrue(recarregou, "a página volta à tela de parear")
        XCTAssertEqual(c.fluxo.estado, EstadoPareamento())
    }

    /// Mesmo defeito, iPhone pareado só pelo cabo (sem o id do Bluetooth ainda): o ramo "tenta o próximo Mac" nunca
    /// contava recusa, então a tela ficava presa.
    func testPareadoSoPeloCaboQueOMacRecusaEsqueceOPareamento() async throws {
        let mac = MacDeTeste(codigoAcesso: "OUTROCODIGOOUTROCODI")
        let cofre = CofreEmMemoria(pareado(nil, codigo: "CODIGOVELHOCODIGOVEL"))
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        var recarregou = false
        c.recarregarPagina = { recarregou = true }
        c.iniciar()
        await esperar({ cofre.ler() == nil }, segundos: 5)
        XCTAssertNil(cofre.ler(), "o pareamento acabou")
        XCTAssertTrue(recarregou, "a página volta à tela de parear")
    }

    func testPareadoPeloCaboAchaOMacPeloRadioEGuardaOIdentificador() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria(pareado(nil))
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter()?.tipo == .bluetooth }
        XCTAssertEqual(cofre.ler()?.idBluetooth, "mac-1", "da próxima vez conecta direto, sem procurar")
    }

    func testEsquecerOMacDesligaOBluetooth() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria(pareado())
        let radio = RadioFalso(mac)
        let (g, _) = gerente(radio, cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter() != nil }
        _ = await c.tratar(json(#"{"op":"acao","acao":"esquecer"}"#))
        XCTAssertNil(c.canais.obter())
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(g.mac)
        XCTAssertEqual(radio.conexoes, 1, "esquecido, não reconecta sozinho")
    }

    func testCodigoNovoDoRodizioChegaPeloBluetoothAoCofre() async throws {
        let mac = MacDeTeste()
        mac.extras = ["X-Deck-Codigo-Novo": "NOVOCODIGONOVOCODIGO"]
        let cofre = CofreEmMemoria(pareado())
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter() != nil }
        let r = await c.tratar(json(#"{"op":"requisitar","metodo":"GET","caminho":"/api/estado","cabecalhos":{"x-deck-codigo":"X"}}"#))
        XCTAssertTrue(r.contains("\"codigoNovo\":\"NOVOCODIGONOVOCODIGO\""), r)
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "NOVOCODIGONOVOCODIGO")
    }

    func testMacAceitaOCodigoAnteriorNaFolgaDoRodizio() async throws {
        let mac = MacDeTeste(codigoAcesso: "NOVOCODIGONOVOCODIGO")
        mac.chaves = ["NOVOCODIGONOVOCODIGO", "ABCDEFGHIJKLMNOPQRST"]
        let cofre = CofreEmMemoria(pareado())
        let (g, _) = gerente(RadioFalso(mac), cofre: cofre)
        let (c, _) = casca(g, cofre: cofre)
        c.iniciar()
        await esperar { c.canais.obter()?.tipo == .bluetooth }
        XCTAssertEqual(c.canais.obter()?.tipo, .bluetooth)
    }

    // MARK: Reconexão depois de a conexão direta nunca completar (12/11/2026)

    /// O Mac trocou de endereço: o id guardado nunca conecta (o connect do iOS fica esperando, sem falhar) e o Mac
    /// aparece na procura com outro id. Antes, o app insistia no id velho para sempre e nunca olhava o ar.
    func testIdGuardadoQueNuncaConectaCaiParaAProcuraPeloServicoEConectaNoIdNovo() async throws {
        let mac = MacDeTeste()
        let radio = RadioComEnderecoNovo(mac: mac, velho: "mac-velho", novo: "mac-novo")
        let cofre = CofreEmMemoria(pareado("mac-velho"))
        let linhas = Linhas()
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 },
                                 prazoDaConexaoDireta: 0.2, prazoDaProcura: 1, log: { linhas.anotar($0) })
        addTeardownBlock { g.parar() }
        g.iniciar()
        await esperar({ g.mac != nil }, segundos: 6)
        XCTAssertEqual(g.mac?.id, "mac-novo", "ficou preso no id velho: \(linhas.todas)")
        XCTAssertEqual(cofre.ler()?.idBluetooth, "mac-novo", "o id novo precisa ser guardado para a próxima vez")
        XCTAssertEqual(cofre.ler()?.codigoAcesso, "ABCDEFGHIJKLMNOPQRST", "o pareamento não pode ser esquecido")
        XCTAssertEqual(radio.tentativasNoVelho, 1, "a conexão direta tem que ter tempo limite, não repetir sem fim")
    }

    /// A tela de conexão tem que refletir cada tentativa e limpar quando conecta.
    func testSituacaoDaBuscaMudaACadaTentativaELimpaAoConectar() async throws {
        let mac = MacDeTeste()
        let radio = RadioFalso(mac)
        radio.recusaConectar = true
        let cofre = CofreEmMemoria(pareado())
        let (g, _) = gerente(radio, cofre: cofre)
        let vistas = Linhas()
        g.aoMudarSituacao { vistas.anotar($0 ?? "nil") }
        g.iniciar()
        await esperar({ vistas.todas.contains { $0.contains("Tentativa 2") } }, segundos: 6)
        XCTAssertTrue(vistas.todas.contains { $0.contains("Procurando o Mac pelo Bluetooth. Tentativa 1") }, "\(vistas.todas)")
        XCTAssertTrue(vistas.todas.contains { $0.contains("Tentativa 2") }, "\(vistas.todas)")
        radio.recusaConectar = false
        await esperar({ g.mac != nil }, segundos: 6)
        XCTAssertNotNil(g.mac)
        await esperar({ vistas.todas.last == "nil" }, segundos: 2)
        XCTAssertEqual(vistas.todas.last, "nil", "conectou: a tela não tem mais o que dizer")
        XCTAssertNil(g.situacao)
    }

    /// Quando a conexão cai, a tela volta a dizer que procura (antes ficava parada no que dizia).
    func testQuedaDaConexaoVoltaASituacaoDeProcura() async throws {
        let mac = MacDeTeste()
        let cofre = CofreEmMemoria(pareado())
        let radio = RadioFalso(mac)
        let (g, _) = gerente(radio, cofre: cofre)
        let vistas = Linhas()
        g.aoMudarSituacao { vistas.anotar($0 ?? "nil") }
        g.iniciar()
        await esperar({ g.mac != nil }, segundos: 4)
        radio.recusaConectar = true
        mac.sairDoAlcance()
        await esperar({ g.mac == nil && g.situacao != nil }, segundos: 4)
        XCTAssertNotNil(g.situacao, "caiu e a tela continuou sem estado: \(vistas.todas)")
    }

    /// Só há outro Mac por perto (o do vizinho) e o Mac do iPhone sumiu: o vizinho não conhece este iPhone, mas isso não é
    /// o Mac dele desconectando. O pareamento fica.
    func testVizinhoQueRecusaNaProcuraNaoFazOPareamentoSerEsquecido() async throws {
        let vizinho = MacDeTeste(codigoAcesso: "ZZZZZZZZZZZZZZZZZZZZ")
        let radio = RadioComEnderecoNovo(mac: vizinho, velho: "mac-velho", novo: "vizinho", nome: "Mac do vizinho")
        let cofre = CofreEmMemoria(pareado("mac-velho"))
        let g = GerenteBluetooth(radio: radio, cofre: cofre, nomeDoIphone: "iPhone Exemplo", esperaEntreTentativas: { _ in 0.05 },
                                 prazoDaConexaoDireta: 0.1, prazoDaProcura: 0.5, log: { _ in })
        let esqueceu = Linhas()
        g.aoNaoReconhecido { esqueceu.anotar("esqueceu") }
        addTeardownBlock { g.parar() }
        g.iniciar()
        try await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertGreaterThanOrEqual(radio.tentativasNoNovo, 2, "o teste não exercitou a recusa do vizinho")
        XCTAssertTrue(esqueceu.todas.isEmpty, "esqueceu o pareamento por causa de um Mac que não é o do iPhone")
        XCTAssertNotNil(cofre.ler())
    }
}
#endif

final class DiarioBluetoothTestes: XCTestCase {
    func testAnelGuardaSoAsUltimasLinhasComHorario() {
        let d = DiarioBluetooth(arquivo: nil, capacidade: 3, relogio: { Date(timeIntervalSince1970: 0) })
        for i in 1...5 { d.anotar("passo \(i)") }
        XCTAssertEqual(d.recentes, ["1970-01-01T00:00:00.000Z passo 3", "1970-01-01T00:00:00.000Z passo 4", "1970-01-01T00:00:00.000Z passo 5"])
    }

    func testArquivoGiraSemCrescerSemLimiteESobreviveAReabrir() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bt-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let d = DiarioBluetooth(arquivo: url, capacidade: 10)
        for i in 1...35 { d.anotar("linha \(i)") }
        let linhas = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertLessThanOrEqual(linhas.count, 20)
        XCTAssertTrue(linhas.last!.hasSuffix("linha 35"))
        let reaberto = DiarioBluetooth(arquivo: url, capacidade: 10)
        XCTAssertEqual(reaberto.recentes.count, 10)
        XCTAssertTrue(reaberto.recentes.last!.hasSuffix("linha 35"))
    }

    func testQuebraDeLinhaNaoViraDuasLinhas() {
        let d = DiarioBluetooth(arquivo: nil)
        d.anotar("a\nb")
        XCTAssertEqual(d.recentes.count, 1)
    }
}

final class UltimaListaPorOuvinteTestes: XCTestCase {
    private let mac = AnuncioBle(id: "333B2CE5", nome: "MacBook Pro de Exemplo", rssi: -44)

    /// Diário do iPhone de 12/11/2026: a procura da reconexão via o Mac a cada segundo (ACEITO) e terminava com "0 Mac(s)".
    /// A procura anterior já tinha recebido [mac] e saído. A nova entrou com a lista vazia (o anúncio velho venceu) e,
    /// quando o Mac apareceu de novo, a comparação era com o que a procura ANTERIOR recebeu: igual, ninguém foi avisado.
    func testProcuraNovaRecebeOMacMesmoQueAAnteriorJaTenhaRecebidoOMesmo() {
        var u = UltimaListaPorOuvinte()
        let antiga = UUID()
        u.entrou(antiga, recebeu: [])
        XCTAssertEqual(u.quemAvisar([mac], ouvintes: [antiga]), [antiga])
        u.saiu(antiga)
        let nova = UUID()
        u.entrou(nova, recebeu: [])
        XCTAssertEqual(u.quemAvisar([mac], ouvintes: [nova]), [nova], "a procura nova nunca soube do Mac que estava no ar")
    }

    func testSinalQueSoOscilaNaoAvisaDeNovo() {
        var u = UltimaListaPorOuvinte()
        let o = UUID()
        u.entrou(o, recebeu: [])
        XCTAssertEqual(u.quemAvisar([mac], ouvintes: [o]), [o])
        var oscilou = mac
        oscilou.rssi = -40
        XCTAssertEqual(u.quemAvisar([oscilou], ouvintes: [o]), [])
    }

    /// Dois ouvintes ao mesmo tempo (lista do pareamento e reconexão): o que chegou depois recebe sem tirar do outro.
    func testCadaOuvinteComparaComOQueEleRecebeu() {
        var u = UltimaListaPorOuvinte()
        let a = UUID()
        u.entrou(a, recebeu: [])
        XCTAssertEqual(u.quemAvisar([mac], ouvintes: [a]), [a])
        let b = UUID()
        u.entrou(b, recebeu: [])
        XCTAssertEqual(u.quemAvisar([mac], ouvintes: [a, b]), [b])
    }
}

final class AvaliacaoDeAnuncioTestes: XCTestCase {
    private let deck = EnlaceBle.servico
    private func av(servicos: [String] = [], extras: [String] = [], nome: String? = nil, rssi: Int = -50, conhecidos: Set<String> = [], filtro: Bool) -> AvaliacaoDeAnuncio.Resultado {
        AvaliacaoDeAnuncio.avaliar(servicos: servicos, extras: extras, nome: nome, rssi: rssi, uuidDoDeck: deck, nomesConhecidos: conhecidos, comFiltro: filtro)
    }

    func testServicoNoPacoteOuNaAreaExtraAceita() {
        XCTAssertTrue(av(servicos: [deck.lowercased()], filtro: false).aceito)
        XCTAssertTrue(av(extras: [deck], filtro: false).aceito)
    }

    /// Sem filtro, um aparelho qualquer é descartado, mas o Mac pareado (pelo nome) passa mesmo sem o UUID à vista.
    func testSemFiltroDescartaOutrosEAceitaOMacPareadoPeloNome() {
        XCTAssertFalse(av(nome: "Fone", filtro: false).aceito)
        XCTAssertTrue(av(nome: "MacBook Pro de Leonardo Rejani", conhecidos: ["MacBook Pro de Leonardo Rejani"], filtro: false).aceito)
    }

    func testComFiltroDoIosTudoQueChegaVale() {
        XCTAssertTrue(av(filtro: true).aceito)
    }

    func testSinal127SempreDescarta() {
        XCTAssertFalse(av(servicos: [deck], rssi: 127, filtro: true).aceito)
    }
}
