import XCTest
#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif
@testable import Nucleo

// O Bluetooth sem rádio: o fio de bytes do LE é trocado por um par de FluxoEnlace ligados entre si, e o "iPhone"
// do teste fala o mesmo aperto de mão cifrado e os mesmos quadros do cabo. O que depende de CoreBluetooth
// de verdade (anúncio, MTU, fila do rádio) foi provado no aparelho: docs/provas/fase-7-bluetooth.md.

final class EnlaceTestes: XCTestCase {
    // MARK: Fila e fio

    func testFilaEntregaNaOrdemEPartePeloMaximo() {
        let f = FilaDeBytes()
        f.empurrar(Data([1, 2, 3, 4, 5]))
        f.empurrar(Data([6]))
        XCTAssertEqual(f.ler(maximo: 2), Data([1, 2]))
        XCTAssertEqual(f.ler(maximo: 10), Data([3, 4, 5]))
        XCTAssertEqual(f.ler(maximo: 10), Data([6]))
    }

    func testFilaFechadaEsvaziaDepoisDevolveNilEAcordaQuemEspera() {
        let f = FilaDeBytes()
        let espera = expectation(description: "leitura acordou")
        nonisolated(unsafe) var lido: Data? = Data([9])
        Thread {
            lido = f.ler(maximo: 4)
            espera.fulfill()
        }.start()
        Thread.sleep(forTimeInterval: 0.1)
        f.fechar()
        wait(for: [espera], timeout: 2)
        XCTAssertNil(lido)
        f.empurrar(Data([1]))
        XCTAssertNil(f.ler(maximo: 4), "depois de fechada a fila não aceita mais nada")
    }

    func testParDeFluxosLevaOsBytesNosDoisSentidosELeExato() {
        let (a, b) = FluxoEnlace.par()
        XCTAssertTrue(a.escrever(Data("ida".utf8)))
        XCTAssertTrue(b.escrever(Data("volta".utf8)))
        XCTAssertEqual(b.lerExato(3), Data("ida".utf8))
        XCTAssertEqual(a.lerExato(5), Data("volta".utf8))
    }

    func testFecharUmLadoAcabaALeituraDoOutroEBloqueiaEscrita() {
        let (a, b) = FluxoEnlace.par()
        a.fechar()
        XCTAssertNil(b.ler(maximo: 4))
        XCTAssertFalse(a.escrever(Data([1])))
    }

    // MARK: Código de 6 dígitos

    /// O mesmo vetor existe em ios/Pacote/Tests: o Mac e o iPhone têm que sortear os mesmos 6 dígitos.
    func testCodigoDeOuroIgualAoDoIPhone() {
        let t = Sas.transcricao(modo: "parear", chaveIphone: Data(repeating: 1, count: 32), nonceIphone: Data(repeating: 2, count: 16),
                                chaveMac: Data(repeating: 3, count: 32), nonceMac: Data(repeating: 4, count: 16), nomeMac: "MacBook Pro de Exemplo")
        XCTAssertEqual(ProvaCabo.hex([UInt8](t)), "d927e3550a83a65850b5c0512354b78a70b0661b0c563b85aaa348d84753a0ca")
        XCTAssertEqual(Sas.digitos(t), "532820")
        XCTAssertEqual(Sas.digitos(t).count, 6)
    }

    func testCodigoMudaSeQualquerPedacoDaConversaMuda() {
        func d(_ k: UInt8 = 1, _ n: String = "Mac") -> String {
            Sas.digitos(Sas.transcricao(modo: "parear", chaveIphone: Data(repeating: k, count: 32), nonceIphone: Data(repeating: 2, count: 16),
                                        chaveMac: Data(repeating: 3, count: 32), nonceMac: Data(repeating: 4, count: 16), nomeMac: n))
        }
        XCTAssertEqual(d(), d())
        XCTAssertNotEqual(d(), d(9), "chave trocada no meio muda o código")
        XCTAssertNotEqual(d(), d(1, "Outro"))
    }

    func testCompromissoDependeDaChaveEDoNonce() {
        let a = Sas.compromisso(chavePublica: Data(repeating: 1, count: 32), nonce: Data(repeating: 2, count: 16))
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, Sas.compromisso(chavePublica: Data(repeating: 9, count: 32), nonce: Data(repeating: 2, count: 16)))
        XCTAssertNotEqual(a, Sas.compromisso(chavePublica: Data(repeating: 1, count: 32), nonce: Data(repeating: 9, count: 16)))
    }

    // MARK: Vazão

    func testMedidaDeVazaoPercorreOsTresPassosPeloFio() throws {
        let (mac, iphone) = FluxoEnlace.par()
        Thread { VazaoBluetooth.servir(mac) }.start()
        let r = try XCTUnwrap(VazaoBluetooth.medir(iphone, bytes: 20000, pings: 3))
        XCTAssertEqual(r.pings.count, 3)
        XCTAssertEqual(r.descidaBytes, 20000)
        XCTAssertEqual(r.subidaBytes, 20000)
        XCTAssertGreaterThan(r.descidaKBs, 0)
        iphone.fechar()
    }

    func testMedidaDeVazaoSemRespostaDevolveNil() {
        let (_, iphone) = FluxoEnlace.par()
        iphone.fechar()
        XCTAssertNil(VazaoBluetooth.medir(iphone, bytes: 100, pings: 1))
    }

    // MARK: Capa pequena

    func testSoACapaEhAjustadaEORestoPassaComoVeio() {
        let p = PedidoCabo(metodo: "GET", caminho: "/api/estado", query: [:], cabecalhos: [:], corpo: Data())
        let r = RespostaRota.json(200, Data("{}".utf8))
        XCTAssertEqual(CapaPequena.ajustar(p, r), r)
        let erro = RespostaRota.erro(404, "Nenhuma capa tocando agora.")
        let pc = PedidoCabo(metodo: "GET", caminho: "/api/capa", query: [:], cabecalhos: [:], corpo: Data())
        XCTAssertEqual(CapaPequena.ajustar(pc, erro), erro, "capa que o Mac não tem segue como erro de verdade")
    }

    func testCapaQueNaoEhImagemVira404EmVezDeMandarLixoPeloAr() {
        let pc = PedidoCabo(metodo: "GET", caminho: "/api/capa", query: [:], cabecalhos: [:], corpo: Data())
        let r = CapaPequena.ajustar(pc, RespostaRota(status: 200, tipo: "image/png", corpo: Data([1, 2, 3])))
        XCTAssertEqual(r.status, 404)
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    func testCapaGrandeSaiPequenaEEmJpeg() throws {
        let png = try XCTUnwrap(Self.imagem(640))
        let pc = PedidoCabo(metodo: "GET", caminho: "/api/capa", query: [:], cabecalhos: [:], corpo: Data())
        let r = CapaPequena.ajustar(pc, RespostaRota(status: 200, tipo: "image/png", corpo: png, extras: ["Cache-Control": "no-store"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.tipo, "image/jpeg")
        XCTAssertEqual(r.extras["Cache-Control"], "no-store")
        XCTAssertLessThan(r.corpo.count, 20 * 1024, "uma capa pelo Bluetooth cabe em menos de um segundo")
        XCTAssertLessThan(r.corpo.count, png.count)
        XCTAssertEqual([UInt8](r.corpo.prefix(2)), [0xFF, 0xD8], "JPEG")
    }

    /// Um degradê de 640 x 640, parecido com uma capa do Spotify.
    static func imagem(_ lado: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let cores = [CGColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 1), CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1)]
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cores as CFArray, locations: [0, 1]) else { return nil }
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: lado, y: lado), options: [])
        guard let img = ctx.makeImage() else { return nil }
        let saida = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(saida, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return saida as Data
    }
    #endif
}

#if canImport(CryptoKit)
import CryptoKit

final class EnlaceSeguroTestes: XCTestCase {
    private let codigo = "abcdefghjkmnpqrstuvw"

    private func servidor(_ fluxo: FluxoBytes, aceitar: Bool = true, chaves: [String]? = nil, vistos: Vistos? = nil) -> Thread {
        let cod = codigo
        let cfg = EnlaceSeguro.ConfigServidor(
            nomeMac: "Mac do Leo", chaves: { chaves ?? [cod] }, codigoAcesso: { cod },
            decidir: { iphone, cod in vistos?.anotar("\(iphone)|\(cod)"); return aceitar },
            prazoDoAperto: 5, prazoDoIphone: 5)
        let t = Thread {
            do {
                let seguro = try EnlaceSeguro.servir(fluxo, cfg)
                vistos?.guardar(seguro)
            } catch { vistos?.falhou(error) }
        }
        t.start()
        return t
    }

    final class Vistos: @unchecked Sendable {
        private let trava = NSLock()
        private var _itens: [String] = []
        private var _seguro: FluxoCifrado?
        private var _erro: Error?
        private let pronto = DispatchSemaphore(value: 0)
        func anotar(_ s: String) { trava.lock(); _itens.append(s); trava.unlock() }
        func guardar(_ s: FluxoCifrado) { trava.lock(); _seguro = s; trava.unlock(); pronto.signal() }
        func falhou(_ e: Error) { trava.lock(); _erro = e; trava.unlock(); pronto.signal() }
        var itens: [String] { trava.lock(); defer { trava.unlock() }; return _itens }
        func esperar() -> (FluxoCifrado?, Error?) {
            _ = pronto.wait(timeout: .now() + 10)
            trava.lock(); defer { trava.unlock() }
            return (_seguro, _erro)
        }
    }

    // MARK: Pareamento (iPhone novo)

    func testPareamentoMostraOMesmoCodigoNosDoisLadosEEntregaOCodigoDeAcesso() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let p = try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone Exemplo")
        let codigoNoIphone = p.codigo
        XCTAssertEqual(p.nomeMac, "Mac do Leo")
        XCTAssertEqual(codigoNoIphone.count, 6)
        // o Mac mostra o código na tela e a pessoa permite: só então o iPhone recebe o código de acesso
        let recebido = try EnlaceSeguro.concluir(p, aceito: true)
        XCTAssertEqual(recebido, codigo)
        let (seguro, erro) = v.esperar()
        XCTAssertNil(erro)
        XCTAssertNotNil(seguro)
        XCTAssertEqual(v.itens, ["iPhone Exemplo|\(codigoNoIphone)"], "o Mac mostrou os mesmos 6 dígitos do iPhone")
    }

    func testDepoisDoPareamentoOFioContinuaCifradoNosDoisSentidos() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let p = try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone")
        _ = try EnlaceSeguro.concluir(p, aceito: true)
        let seguroMac = try XCTUnwrap(v.esperar().0)
        XCTAssertTrue(p.fluxo.escrever(Data("pedido secreto".utf8)))
        XCTAssertEqual(seguroMac.lerExato(14), Data("pedido secreto".utf8))
        XCTAssertTrue(seguroMac.escrever(Data("resposta".utf8)))
        XCTAssertEqual(p.fluxo.lerExato(8), Data("resposta".utf8))
    }

    func testMacRecusandoOIphoneNaoRecebeOCodigoDeAcesso() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, aceitar: false, vistos: v)
        let p = try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone")
        XCTAssertThrowsError(try EnlaceSeguro.concluir(p, aceito: true)) { XCTAssertEqual($0 as? ErroEnlace, .recusado("O pareamento foi recusado no Mac.")) }
        XCTAssertNotNil(v.esperar().1)
    }

    func testIphoneRecusandoONaoDeixaOMacEntregarNada() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let p = try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone")
        XCTAssertThrowsError(try EnlaceSeguro.concluir(p, aceito: false))
        let (seguro, erro) = v.esperar()
        XCTAssertNil(seguro)
        XCTAssertNotNil(erro)
    }

    func testIphoneNovoNaoVeOCodigoDeAcessoSemOMacPermitir() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let liberar = DispatchSemaphore(value: 0)
        let cod = codigo
        let cfg = EnlaceSeguro.ConfigServidor(nomeMac: "Mac", chaves: { [] }, codigoAcesso: { cod },
                                              decidir: { _, _ in _ = liberar.wait(timeout: .now() + 5); return false }, prazoDoAperto: 5, prazoDoIphone: 5)
        Thread { _ = try? EnlaceSeguro.servir(mac, cfg) }.start()
        let p = try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone")
        // o iPhone confirma, mas o Mac ainda espera a pessoa: nada de código de acesso no fio
        XCTAssertTrue(p.fluxo.escrever(Data("ok-fantasma".utf8)))
        nonisolated(unsafe) var chegou = false
        let lido = expectation(description: "leu")
        lido.isInverted = true
        Thread { if p.fluxo.ler(maximo: 8) != nil { chegou = true; lido.fulfill() } }.start()
        wait(for: [lido], timeout: 0.5)
        XCTAssertFalse(chegou)
        liberar.signal()
    }

    /// Alguém no meio troca a chave do Mac pela dele: o Mac se comprometeu antes de ver a do iPhone, então a troca é pega.
    func testChaveTrocadaDepoisDoCompromissoDerrubaOPareamento() throws {
        let (mac, iphone) = FluxoEnlace.par()
        Thread {
            guard QuadroEnlace.ler(mac) != nil else { return }
            let legitima = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            let nonce = Data(repeating: 7, count: 16)
            _ = QuadroEnlace.escrever(mac, MsgEnlace(t: "c", a: Sas.compromisso(chavePublica: legitima, nonce: nonce), n: "Mac do Leo"))
            guard QuadroEnlace.ler(mac) != nil else { return }
            let falsa = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            _ = QuadroEnlace.escrever(mac, MsgEnlace(t: "m", a: falsa, b: nonce))
        }.start()
        XCTAssertThrowsError(try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone")) {
            XCTAssertEqual($0 as? ErroEnlace, .protocolo("o Mac mudou a chave depois de se comprometer"))
        }
    }

    func testPareamentoSemRespostaFechaOFioNoPrazo() {
        let (_, iphone) = FluxoEnlace.par()
        let t0 = Date()
        XCTAssertThrowsError(try EnlaceSeguro.iniciarPareamento(iphone, nomeDoIphone: "iPhone", prazo: 0.3))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3)
    }

    // MARK: Reconexão (iPhone já pareado)

    func testIphoneParedoEntraProvandoOCodigoDeAcessoENosDoisLadosOFioFicaCifrado() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let entrada = try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)
        XCTAssertEqual(entrada.nomeMac, "Mac do Leo")
        let seguroMac = try XCTUnwrap(v.esperar().0)
        XCTAssertTrue(entrada.fluxo.escrever(Data("X-Deck-Codigo".utf8)))
        XCTAssertEqual(seguroMac.lerExato(13), Data("X-Deck-Codigo".utf8))
        XCTAssertTrue(v.itens.isEmpty, "reconectar não pede confirmação na tela do Mac")
    }

    func testCodigoDeAcessoErradoNaoEntraENenhumLadoRecebeNada() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        XCTAssertThrowsError(try EnlaceSeguro.entrar(iphone, codigoAcesso: "outrocodigooutrocodi")) { XCTAssertEqual($0 as? ErroEnlace, .naoPareado) }
        let (seguro, erro) = v.esperar()
        XCTAssertNil(seguro)
        XCTAssertEqual(erro as? ErroEnlace, .naoPareado)
    }

    /// Rodízio: durante a folga o Mac aceita o código anterior (e o atual), e prova com o que o iPhone usou.
    func testMacAceitaOCodigoAnteriorNaFolgaDoRodizio() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, chaves: ["codigonovocodigonovo", codigo], vistos: v)
        let entrada = try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)
        XCTAssertNotNil(v.esperar().0)
        XCTAssertEqual(entrada.nomeMac, "Mac do Leo")
    }

    func testMacFalsoQueNaoSabeOCodigoNaoEngana() throws {
        let (mac, iphone) = FluxoEnlace.par()
        Thread {
            guard let m1 = QuadroEnlace.ler(mac), m1.t == "i" else { return }
            let chave = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
            _ = QuadroEnlace.escrever(mac, MsgEnlace(t: "m", a: chave, b: Data(repeating: 1, count: 16), n: "Mac do Leo"))
            guard QuadroEnlace.ler(mac) != nil else { return }
            _ = QuadroEnlace.escrever(mac, MsgEnlace(t: "q", a: Data(repeating: 0, count: 32)))
        }.start()
        XCTAssertThrowsError(try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)) {
            XCTAssertEqual($0 as? ErroEnlace, .protocolo("o Mac não provou que conhece o código"))
        }
    }

    // MARK: Fio cifrado

    private func parCifrado() throws -> (FluxoCifrado, FluxoCifrado, FluxoEnlace, FluxoEnlace) {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let entrada = try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)
        return (entrada.fluxo, try XCTUnwrap(v.esperar().0), mac, iphone)
    }

    func testNadaDoQueVaiPeloArEstaEmTextoPuro() throws {
        // o par de fluxos cru deixa espiar o que o rádio levaria
        let (mac, iphone) = FluxoEnlace.par()
        let espiao = Espiao(iphone)
        let v = Vistos()
        _ = servidor(mac, vistos: v)
        let entrada = try EnlaceSeguro.entrar(espiao, codigoAcesso: codigo)
        _ = v.esperar()
        _ = entrada.fluxo.escrever(Data("GET /api/estado X-Deck-Codigo: \(codigo)".utf8))
        let visto = espiao.escrito
        XCTAssertFalse(visto.range(of: Data(codigo.utf8)) != nil, "o código de acesso nunca passa aberto")
        XCTAssertFalse(visto.range(of: Data("/api/estado".utf8)) != nil)
    }

    /// Um fio que guarda tudo que escreve, para provar que o que vai pelo ar não é texto puro.
    final class Espiao: FluxoBytes, @unchecked Sendable {
        let interno: FluxoBytes
        private let trava = NSLock()
        private var _escrito = Data()
        init(_ f: FluxoBytes) { interno = f }
        var escrito: Data { trava.lock(); defer { trava.unlock() }; return _escrito }
        func ler(maximo: Int) -> Data? { interno.ler(maximo: maximo) }
        func escrever(_ d: Data) -> Bool { trava.lock(); _escrito.append(d); trava.unlock(); return interno.escrever(d) }
        func fechar() { interno.fechar() }
    }

    func testRegistroAdulteradoDerrubaAConexao() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        let adulterador = Adulterador(mac)
        _ = servidor(adulterador, vistos: v)
        let entrada = try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)
        let seguroMac = try XCTUnwrap(v.esperar().0)
        adulterador.adulterar = true
        XCTAssertTrue(entrada.fluxo.escrever(Data("manda abrir o terminal".utf8)))
        XCTAssertNil(seguroMac.ler(maximo: 64), "etiqueta não confere: a conexão cai em vez de entregar texto trocado")
    }

    /// Troca um byte de tudo que o iPhone escreve depois de ligado.
    final class Adulterador: FluxoBytes, @unchecked Sendable {
        let interno: FluxoBytes
        var adulterar = false
        init(_ f: FluxoBytes) { interno = f }
        func ler(maximo: Int) -> Data? {
            guard var d = interno.ler(maximo: maximo) else { return nil }
            if adulterar, d.count > 4 { d[d.count - 1] ^= 0x01 }
            return d
        }
        func escrever(_ d: Data) -> Bool { interno.escrever(d) }
        func fechar() { interno.fechar() }
    }

    func testRegistroRepetidoNaoAbre() throws {
        let (mac, iphone) = FluxoEnlace.par()
        let v = Vistos()
        let gravador = Gravador(mac)
        _ = servidor(gravador, vistos: v)
        let entrada = try EnlaceSeguro.entrar(iphone, codigoAcesso: codigo)
        let seguroMac = try XCTUnwrap(v.esperar().0)
        gravador.gravando = true
        XCTAssertTrue(entrada.fluxo.escrever(Data("pedido".utf8)))
        XCTAssertEqual(seguroMac.lerExato(6), Data("pedido".utf8))
        // quem escuta o ar repete o mesmo registro: o contador de cada direção não deixa passar
        gravador.repetir()
        XCTAssertNil(seguroMac.ler(maximo: 64))
    }

    /// Guarda o que chega do iPhone para depois repeti-lo.
    final class Gravador: FluxoBytes, @unchecked Sendable {
        let interno: FluxoBytes
        var gravando = false
        private var gravado = Data()
        init(_ f: FluxoBytes) { interno = f }
        func ler(maximo: Int) -> Data? {
            guard let d = interno.ler(maximo: maximo) else { return nil }
            if gravando { gravado.append(d) }
            return d
        }
        func repetir() { (interno as? FluxoEnlace)?.fila.empurrar(gravado) }
        func escrever(_ d: Data) -> Bool { interno.escrever(d) }
        func fechar() { interno.fechar() }
    }

    func testRegistroGrandeVaiPartidoEVoltaInteiro() throws {
        let (iphone, mac, _, _) = try parCifrado()
        let grande = Data((0..<20_000).map { UInt8($0 % 251) })
        Thread { _ = iphone.escrever(grande) }.start()
        XCTAssertEqual(mac.lerExato(grande.count), grande)
    }
}

// MARK: - A sessão inteira: aperto de mão, pedido ao roteador de verdade e capa pequena

final class PortaDoBluetoothTestes: XCTestCase {
    private func iphone(_ c: Cenario, codigo: String = Cenario.codigo, decidir: @escaping @Sendable (String, String) -> Bool = { _, _ in true })
        throws -> (iphone: FluxoCifrado, porta: PortaDoBluetooth, log: Registro, mac: FluxoEnlace) {
        let (mac, fio) = FluxoEnlace.par()
        let log = Registro()
        let porta = PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac do Leo" }, decidir: decidir, pareamentoAberto: { true }, log: { log.anotar($0) })
        Thread { porta.atender(mac, rotulo: "teste") }.start()
        let entrada = try EnlaceSeguro.entrar(fio, codigoAcesso: codigo)
        return (entrada.fluxo, porta, log, mac)
    }

    private func pedir(_ f: FluxoBytes, _ id: Int, _ metodo: String, _ caminho: String, query: [String: String] = [:], cabecalhos: [String: String] = [:]) -> RespostaCabo? {
        let p = PedidoCabo(metodo: metodo, caminho: caminho, query: query, cabecalhos: cabecalhos, corpo: Data())
        _ = f.escrever(Quadros.codificar(MensagemCabo(tipo: "pedido", id: id, pedido: p))!)
        while let m = Quadros.ler(de: f) {
            if m.tipo == "resposta", m.id == id { return m.resposta }
        }
        return nil
    }

    func testMacSeApresentaEResponde() throws {
        let c = try Cenario()
        let (f, _, log, mac) = try iphone(c)
        defer { mac.fechar() }
        let ola = try XCTUnwrap(Quadros.ler(de: f))
        XCTAssertEqual(ola.tipo, "ola")
        XCTAssertEqual(ola.nome, "Mac do Leo")
        let r = try XCTUnwrap(pedir(f, 1, "GET", "/api/estado", cabecalhos: ["x-deck-codigo": Cenario.codigo]))
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(log.todos.contains { $0.contains("bluetooth/teste GET /api/estado 200") }, "\(log.todos)")
    }

    func testTeclaExecutaPeloBluetoothComOCodigoDeAcesso() throws {
        let c = try Cenario()
        let (f, _, _, mac) = try iphone(c)
        defer { mac.fechar() }
        let r = try XCTUnwrap(pedir(f, 1, "POST", "/api/botao/acordado", cabecalhos: ["x-deck-codigo": Cenario.codigo]))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(c.registro.todos, ["tecla acordado"])
    }

    func testIphoneSemOCodigoCertoNaoRecebeSessao() throws {
        let c = try Cenario()
        let (mac, fio) = FluxoEnlace.par()
        let log = Registro()
        let porta = PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac" }, decidir: { _, _ in true }, log: { log.anotar($0) })
        Thread { porta.atender(mac, rotulo: "intruso") }.start()
        XCTAssertThrowsError(try EnlaceSeguro.entrar(fio, codigoAcesso: "codigoerradocodigoerr"))
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(c.registro.todos.isEmpty)
        XCTAssertEqual(porta.sessoesAtivas, 0)
    }

    func testPareamentoPeloBluetoothEntregaOCodigoEAbreASessao() throws {
        let c = try Cenario()
        let (mac, fio) = FluxoEnlace.par()
        let mostrados = Registro()
        let porta = PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac do Leo" }, decidir: { iphone, codigo in mostrados.anotar("\(iphone) \(codigo)"); return true }, pareamentoAberto: { true }, log: { _ in })
        Thread { porta.atender(mac, rotulo: "novo") }.start()
        let p = try EnlaceSeguro.iniciarPareamento(fio, nomeDoIphone: "iPhone Exemplo")
        let acesso = try EnlaceSeguro.concluir(p, aceito: true)
        XCTAssertEqual(acesso, Cenario.codigo)
        XCTAssertEqual(mostrados.todos, ["iPhone Exemplo \(p.codigo)"])
        // o mesmo fio vira a sessão: o Mac se apresenta e atende
        let ola = try XCTUnwrap(Quadros.ler(de: p.fluxo))
        XCTAssertEqual(ola.tipo, "ola")
        let r = try XCTUnwrap(pedir(p.fluxo, 1, "GET", "/api/estado", cabecalhos: ["x-deck-codigo": acesso]))
        XCTAssertEqual(r.status, 200)
        mac.fechar()
    }

    func testSoUmPareamentoPorVezEOSegundoEhRecusadoSemMostrarCodigo() throws {
        let c = try Cenario()
        let segura = DispatchSemaphore(value: 0)
        let mostrados = Registro()
        let porta = PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac" }, decidir: { _, cod in mostrados.anotar(cod); _ = segura.wait(timeout: .now() + 5); return false }, pareamentoAberto: { true }, log: { _ in })
        let (mac1, fio1) = FluxoEnlace.par()
        let (mac2, fio2) = FluxoEnlace.par()
        Thread { porta.atender(mac1, rotulo: "um") }.start()
        let p1 = try EnlaceSeguro.iniciarPareamento(fio1, nomeDoIphone: "A")
        Thread.sleep(forTimeInterval: 0.2)
        Thread { porta.atender(mac2, rotulo: "dois") }.start()
        let p2 = try EnlaceSeguro.iniciarPareamento(fio2, nomeDoIphone: "B")
        XCTAssertThrowsError(try EnlaceSeguro.concluir(p2, aceito: true))
        XCTAssertEqual(mostrados.todos, [p1.codigo], "só o primeiro pareamento chegou à tela do Mac")
        segura.signal()
    }
}

// MARK: - Verificação adversarial: quem escuta o ar não manda no pareamento do Mac

final class PareamentoAdversarioTestes: XCTestCase {
    private func porta(_ c: Cenario, aberto: @escaping @Sendable () -> Bool = { true }, agora: @escaping @Sendable () -> Date = { Date() },
                       desistiu: @escaping @Sendable (String) -> Void = { _ in },
                       decidir: @escaping @Sendable (String, String) -> Bool, log: Registro = Registro()) -> PortaDoBluetooth {
        PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac" }, decidir: decidir, pareamentoAberto: aberto, desistiu: desistiu, agora: agora, log: { log.anotar($0) })
    }

    func testEstranhoPrendeOPareamentoDoLegitimo() throws {
        let c = try Cenario()
        let chamadas = Registro()
        let segura = DispatchSemaphore(value: 0)
        let desistidos = Registro()
        let p = porta(c, desistiu: { desistidos.anotar($0) }, decidir: { nome, cod in
            chamadas.anotar(nome)
            if nome == "estranho" { _ = segura.wait(timeout: .now() + 5); return false }
            return true
        })
        let (macA, fioA) = FluxoEnlace.par()
        Thread { p.atender(macA, rotulo: "estranho") }.start()
        _ = try EnlaceSeguro.iniciarPareamento(fioA, nomeDoIphone: "estranho")
        Thread.sleep(forTimeInterval: 0.2)
        fioA.fechar()   // o estranho some sem responder
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(desistidos.todos.count, 1, "a tela foi avisada de que o pedido saiu")

        let (macB, fioB) = FluxoEnlace.par()
        Thread { p.atender(macB, rotulo: "legitimo") }.start()
        let pb = try EnlaceSeguro.iniciarPareamento(fioB, nomeDoIphone: "legitimo")
        XCTAssertEqual(try EnlaceSeguro.concluir(pb, aceito: true), Cenario.codigo)
        XCTAssertEqual(chamadas.todos, ["estranho", "legitimo"], "o iPhone legítimo chegou à tela")
        segura.signal()
        macB.fechar()
    }

    func testEstranhoEmLacoNaoEncheATelaDoMac() throws {
        let c = try Cenario()
        let chamadas = Registro()
        let p = porta(c, decidir: { _, cod in chamadas.anotar(cod); return false })
        for i in 0..<20 {
            let (mac, fio) = FluxoEnlace.par()
            Thread { p.atender(mac, rotulo: "e\(i)") }.start()
            if let pareando = try? EnlaceSeguro.iniciarPareamento(fio, nomeDoIphone: "e\(i)") { _ = try? EnlaceSeguro.concluir(pareando, aceito: true) }
            fio.fechar()
        }
        XCTAssertLessThan(chamadas.todos.count, 5, "chegaram \(chamadas.todos.count) pedidos à tela")
    }

    func testLimiteDeTaxaLiberaDepoisDaJanela() throws {
        let c = try Cenario()
        let relogio = Registro()   // cada anotação avança 61 s no relógio do teste
        let chamadas = Registro()
        let p = porta(c, agora: { Date(timeIntervalSince1970: Double(relogio.todos.count) * 61) }, decidir: { _, cod in chamadas.anotar(cod); return false })
        for i in 0..<6 {
            let (mac, fio) = FluxoEnlace.par()
            Thread { p.atender(mac, rotulo: "r\(i)") }.start()
            if let pareando = try? EnlaceSeguro.iniciarPareamento(fio, nomeDoIphone: "r") { _ = try? EnlaceSeguro.concluir(pareando, aceito: true) }
            relogio.anotar("x")
        }
        XCTAssertEqual(chamadas.todos.count, 6, "com a janela passando entre um e outro, nenhum é cortado")
    }

    func testSemJanelaDePareamentoNaoAparecePedidoNaTela() throws {
        let c = try Cenario()
        let chamadas = Registro()
        let p = porta(c, aberto: { false }, decidir: { _, cod in chamadas.anotar(cod); return true })
        let (mac, fio) = FluxoEnlace.par()
        Thread { p.atender(mac, rotulo: "fora") }.start()
        let pareando = try EnlaceSeguro.iniciarPareamento(fio, nomeDoIphone: "fora")
        XCTAssertThrowsError(try EnlaceSeguro.concluir(pareando, aceito: true))
        XCTAssertTrue(chamadas.todos.isEmpty)
    }
}

final class NomeFalsoTestes: XCTestCase {
    func testNomeDoIphoneChegaLimpoNaTelaENoLog() throws {
        let c = try Cenario()
        let recebidos = Registro()
        let log = Registro()
        let p = PortaDoBluetooth(roteador: c.roteador, nomeMac: { "Mac" }, decidir: { nome, _ in recebidos.anotar(nome); return true },
                                 pareamentoAberto: { true }, log: { log.anotar($0) })
        let (mac, fio) = FluxoEnlace.par()
        Thread { p.atender(mac, rotulo: "falso") }.start()
        let falso = "iPhone Exemplo\n\u{1b}[1A\u{1b}[2KPareamento por Bluetooth: iPhone Exemplo mostra o código 000000. Confere?"
        let pareando = try EnlaceSeguro.iniciarPareamento(fio, nomeDoIphone: falso)
        _ = try EnlaceSeguro.concluir(pareando, aceito: true)
        let nome = try XCTUnwrap(recebidos.todos.first)
        for u in nome.unicodeScalars { XCTAssertFalse(u.properties.generalCategory == .control, "caractere de controle no nome: \(nome.debugDescription)") }
        XCTAssertFalse(nome.contains("\n") || nome.contains("\u{1b}"))
        XCTAssertLessThanOrEqual(nome.count, 60)
        let linha = try XCTUnwrap(log.todos.first { $0.contains("quer parear") })
        XCTAssertFalse(linha.contains("\n") || linha.contains("\u{1b}"), linha.debugDescription)
        mac.fechar()
    }

    func testNomeLimpoCasosComuns() {
        XCTAssertEqual(EnlaceSeguro.nomeLimpo("iPhone Exemplo"), "iPhone Exemplo")
        XCTAssertEqual(EnlaceSeguro.nomeLimpo("iPhone do João"), "iPhone do João")
        XCTAssertEqual(EnlaceSeguro.nomeLimpo(nil), "iPhone")
        XCTAssertEqual(EnlaceSeguro.nomeLimpo("\n\u{1b}\u{200B}"), "iPhone")
        XCTAssertEqual(EnlaceSeguro.nomeLimpo("a\u{202E}b"), "a b")
        XCTAssertEqual(EnlaceSeguro.nomeLimpo(String(repeating: "x", count: 100)).count, 60)
    }
}
#endif
