import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import Nucleo

// O cabo inteiro sem iPhone: um usbmuxd falso num soquete unix, o app do iPhone falso do outro lado
// do fio e o roteador de verdade (com as peças falsas de RotasFalsos) no meio.

/// Um par de soquetes ligados entre si: o que um escreve o outro lê.
func parDeSoquetes() -> (Soquete, Soquete) {
    var fds: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, Soquete.tipoStream, 0, &fds), 0)
    return (Soquete(fd: fds[0]), Soquete(fd: fds[1]))
}

/// Escuta num soquete unix (fora da classe de teste, que tem um `bind` próprio).
func ouvirUnix(_ caminho: String) -> Int32 {
    let fd = socket(AF_UNIX, Soquete.tipoStream, 0)
    var fim = sockaddr_un()
    fim.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: fim.sun_path)
    withUnsafeMutablePointer(to: &fim.sun_path) { p in
        p.withMemoryRebound(to: UInt8.self, capacity: cap) { d in
            for (i, b) in Array(caminho.utf8).enumerated() { d[i] = b }
            d[caminho.utf8.count] = 0
        }
    }
    let ok = withUnsafePointer(to: &fim) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard ok == 0, listen(fd, 8) == 0 else { return -1 }
    return fd
}

/// O "iPhone" do teste: fala os quadros do cabo do outro lado do fio.
final class IPhoneFalso: @unchecked Sendable {
    let fio: FluxoBytes
    private var proximo = 1
    init(_ fio: FluxoBytes) { self.fio = fio }

    func pedir(_ metodo: String, _ caminho: String, query: [String: String] = [:], cabecalhos: [String: String] = [:], corpo: String = "") -> Int {
        let id = proximo
        proximo += 1
        let p = PedidoCabo(metodo: metodo, caminho: caminho, query: query, cabecalhos: cabecalhos, corpo: Data(corpo.utf8))
        _ = fio.escrever(Quadros.codificar(MensagemCabo(tipo: "pedido", id: id, pedido: p))!)
        return id
    }

    /// Lê quadros até achar a resposta desse id (ping e ola passam).
    func resposta(_ id: Int) -> RespostaCabo? {
        while let m = Quadros.ler(de: fio) {
            if m.tipo == "resposta", m.id == id { return m.resposta }
        }
        return nil
    }
}

extension RespostaCabo {
    var texto: String { String(decoding: corpo, as: UTF8.self) }
}

final class CaboTestes: XCTestCase {
    // MARK: Quadros

    func testQuadroTemTamanhoBigEndianEJson() throws {
        let q = Quadros.codificar(MensagemCabo(tipo: "ola", nome: "Mac", versao: 1))!
        let n = q.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        XCTAssertEqual(n, q.count - 4)
        XCTAssertEqual(String(decoding: q.dropFirst(4), as: UTF8.self), #"{"nome":"Mac","tipo":"ola","versao":1}"#)
    }

    func testPedidoIdaEVoltaPeloFio() throws {
        let (a, b) = parDeSoquetes()
        let p = PedidoCabo(metodo: "POST", caminho: "/api/botao/x", query: ["a": "b"], cabecalhos: ["x-deck-codigo": "abc"], corpo: Data([0, 1, 255]))
        XCTAssertTrue(a.escrever(Quadros.codificar(MensagemCabo(tipo: "pedido", id: 7, pedido: p))!))
        let m = try XCTUnwrap(Quadros.ler(de: b))
        XCTAssertEqual(m.id, 7)
        XCTAssertEqual(m.pedido, p)
    }

    func testQuadroGigantePedidoNoCabecalhoDerrubaALeitura() {
        let (a, b) = parDeSoquetes()
        _ = a.escrever(Data([0x7F, 0xFF, 0xFF, 0xFF]))
        XCTAssertNil(Quadros.ler(de: b))
    }

    func testQuadroComLixoNoJsonDerrubaALeitura() {
        let (a, b) = parDeSoquetes()
        _ = a.escrever(Data([0, 0, 0, 3]) + Data("abc".utf8))
        XCTAssertNil(Quadros.ler(de: b))
    }

    /// O mesmo quadro de ouro existe em ios/Pacote/Tests: os dois lados têm que concordar byte a byte.
    func testQuadroDeOuroIgualAoDoIPhone() {
        let p = PedidoCabo(metodo: "GET", caminho: "/api/estado", query: [:], cabecalhos: ["x-deck-codigo": "abc"], corpo: Data())
        let q = Quadros.codificar(MensagemCabo(tipo: "pedido", id: 1, pedido: p))!
        XCTAssertEqual(String(decoding: q.dropFirst(4), as: UTF8.self),
                       #"{"id":1,"pedido":{"cabecalhos":{"x-deck-codigo":"abc"},"caminho":"/api/estado","corpo":"","metodo":"GET","query":{}},"tipo":"pedido"}"#)
    }

    // MARK: Sessão (o Mac atendendo o iPhone)

    private func sessao(_ c: Cenario, intervaloDoPing: TimeInterval = 60) -> (IPhoneFalso, SessaoCabo, Soquete, Registro) {
        let (mac, iphone) = parDeSoquetes()
        let log = Registro()
        let s = SessaoCabo(fluxo: mac, roteador: c.roteador, nomeMac: "Mac do Leo", rotulo: "teste", intervaloDoPing: intervaloDoPing,
                           log: { log.anotar($0) })
        Thread { s.rodar() }.start()
        return (IPhoneFalso(iphone), s, mac, log)
    }

    func testMacSeApresentaComONomeAoAbrir() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let m = try XCTUnwrap(Quadros.ler(de: ip.fio))
        XCTAssertEqual(m.tipo, "ola")
        XCTAssertEqual(m.nome, "Mac do Leo")
        XCTAssertEqual(m.versao, Quadros.versao)
    }

    func testEstadoVemDoMesmoRoteadorDoHttps() throws {
        let c = try Cenario()
        let (ip, s, _, log) = sessao(c)
        defer { s.encerrar() }
        let id = ip.pedir("GET", "/api/estado", cabecalhos: ["x-deck-codigo": Cenario.codigo])
        let r = try XCTUnwrap(ip.resposta(id))
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.texto.contains("\"nomeMac\":\"Mac\""), r.texto)
        let direto = c.pedir("GET", "/api/estado")
        XCTAssertEqual(r.corpo, direto.corpo, "o cabo devolve os mesmos bytes que o roteador")
        XCTAssertTrue(log.todos.contains { $0.contains("GET /api/estado 200") }, "\(log.todos)")
    }

    /// O app do Mac descobre por aqui por onde o iPhone fala: cada pedido respondido avisa rótulo, caminho e status.
    func testAoAtenderAvisaORotuloOCaminhoEOStatus() throws {
        let c = try Cenario()
        let (mac, iphone) = parDeSoquetes()
        let vistos = Registro()
        let s = SessaoCabo(fluxo: mac, roteador: c.roteador, nomeMac: "Mac", rotulo: "usbmux/7", intervaloDoPing: 60, log: { _ in },
                           aoAtender: { rotulo, caminho, status in vistos.anotar("\(rotulo) \(caminho) \(status)") })
        Thread { s.rodar() }.start()
        defer { s.encerrar() }
        let ip = IPhoneFalso(iphone)
        _ = try XCTUnwrap(ip.resposta(ip.pedir("GET", "/api/estado", cabecalhos: ["x-deck-codigo": Cenario.codigo])))
        _ = try XCTUnwrap(ip.resposta(ip.pedir("GET", "/api/estado")))
        // O aviso sai logo depois da resposta: dá um instante para a outra thread terminar.
        for _ in 0..<100 where vistos.todos.count < 2 { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(vistos.todos, ["usbmux/7 /api/estado 200", "usbmux/7 /api/estado 401"])
    }

    func testSemCodigoDa401EEscolhaNaoExecutaNada() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let r = try XCTUnwrap(ip.resposta(ip.pedir("POST", "/api/botao/acordado")))
        XCTAssertEqual(r.status, 401)
        XCTAssertTrue(c.registro.todos.isEmpty)
    }

    func testTeclaExecutaPeloCaboComOCodigoNoCabecalhoMaiusculo() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let r = try XCTUnwrap(ip.resposta(ip.pedir("POST", "/api/botao/acordado", cabecalhos: ["X-Deck-Codigo": Cenario.codigo])))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(c.registro.todos, ["tecla acordado"])
    }

    func testCapaPeloCaboLevaOCodigoNaQuery() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let r = try XCTUnwrap(ip.resposta(ip.pedir("GET", "/api/capa", query: ["codigo": Cenario.codigo, "v": "1"])))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.tipo, "image/png")
        XCTAssertEqual(r.corpo, Data([1, 2, 3]))
    }

    func testPareamentoPeloCaboDevolveOCodigoDeAcessoEServeUmaVez() throws {
        let c = try Cenario(codigoPareamento: "482913")
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let errado = try XCTUnwrap(ip.resposta(ip.pedir("POST", "/api/parear", corpo: #"{"codigo":"000000"}"#)))
        XCTAssertEqual(errado.status, 401)
        XCTAssertTrue(errado.texto.contains("Restam 4 tentativas"), errado.texto)
        let certo = try XCTUnwrap(ip.resposta(ip.pedir("POST", "/api/parear", corpo: #"{"codigo":"482913"}"#)))
        XCTAssertEqual(certo.status, 200)
        XCTAssertTrue(certo.texto.contains(Cenario.codigo))
        let denovo = try XCTUnwrap(ip.resposta(ip.pedir("POST", "/api/parear", corpo: #"{"codigo":"482913"}"#)))
        XCTAssertEqual(denovo.status, 401, "o código de 6 dígitos vale uma vez só")
    }


    // MARK: Desafio (o iPhone só confia em quem prova o segredo)

    private func olaDoDesafio(_ ip: IPhoneFalso, modo: String, nonce: String) throws -> MensagemCabo {
        _ = ip.fio.escrever(Quadros.codificar(MensagemCabo(tipo: "desafio", nonce: nonce, modo: modo))!)
        while let m = Quadros.ler(de: ip.fio) {
            if m.tipo == "ola", m.nonce == nonce { return m }
        }
        throw XCTSkip("fio acabou sem resposta ao desafio")
    }

    func testDesafioDeAcessoRespondeComHmacDoCodigoDeAcesso() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let m = try olaDoDesafio(ip, modo: "acesso", nonce: "aabbcc")
        XCTAssertEqual(m.modo, "acesso")
        XCTAssertEqual(m.prova, ProvaCabo.prova(chave: Cenario.codigo, modo: "acesso", nonce: "aabbcc", nomeMac: "Mac do Leo"))
        XCTAssertNotEqual(m.prova, ProvaCabo.prova(chave: "outro", modo: "acesso", nonce: "aabbcc", nomeMac: "Mac do Leo"))
    }

    func testDesafioDeCodigoUsaOsDigitosVigentesESemCodigoNaoDaProva() throws {
        let c = try Cenario(codigoPareamento: "482913")
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let m = try olaDoDesafio(ip, modo: "codigo", nonce: "n1")
        XCTAssertEqual(m.prova, ProvaCabo.prova(chave: "482913", modo: "codigo", nonce: "n1", nomeMac: "Mac do Leo"))
        _ = c.pareamento.tentar("482913")
        let depois = try olaDoDesafio(ip, modo: "codigo", nonce: "n2")
        XCTAssertNil(depois.prova, "código já usado: não há o que provar")
    }

    func testPareamentoVigenteSomeQuandoVenceOuEstouraErros() {
        let relogio = RelogioFalso()
        let p = Pareamento(agora: { relogio.agora }, sorteio: { "111222" })
        XCTAssertNil(p.vigente())
        p.gerar()
        XCTAssertEqual(p.vigente(), "111222")
        relogio.avancar(Pareamento.validade + 1)
        XCTAssertNil(p.vigente())
        p.gerar()
        for _ in 0..<Pareamento.maxErros { _ = p.tentar("000000") }
        XCTAssertNil(p.vigente())
    }

    func testSha256EHmacBatemComOsVetoresPublicados() {
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.sha256(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.hmacSHA256(chave: Array("Jefe".utf8), mensagem: Array("what do ya want for nothing?".utf8))),
                       "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        XCTAssertEqual(ProvaCabo.hex(ProvaCabo.hmacSHA256(chave: [UInt8](repeating: 0xaa, count: 131),
                                                          mensagem: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))),
                       "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    func testPedidosJuntosVoltamComOIdCerto() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let cab = ["x-deck-codigo": Cenario.codigo]
        let ids = [ip.pedir("GET", "/api/sessoes", cabecalhos: cab), ip.pedir("GET", "/api/whatsapp", cabecalhos: cab),
                   ip.pedir("GET", "/api/estado", cabecalhos: cab), ip.pedir("GET", "/api/inexistente", cabecalhos: cab)]
        var vistos: [Int: RespostaCabo] = [:]
        while vistos.count < ids.count, let m = Quadros.ler(de: ip.fio) {
            if m.tipo == "resposta", let id = m.id, let r = m.resposta { vistos[id] = r }
        }
        XCTAssertTrue(vistos[ids[0]]!.texto.contains("Seguir?"))
        XCTAssertTrue(vistos[ids[1]]!.texto.contains("Louvor"))
        XCTAssertTrue(vistos[ids[2]]!.texto.contains("nomeMac"))
        XCTAssertEqual(vistos[ids[3]]!.status, 404)
    }

    func testPedidoInvalidoOuGrandeDemaisNaoDerrubaASessao() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c)
        defer { s.encerrar() }
        let sem = try XCTUnwrap(ip.resposta(ip.pedir("GET", "sem-barra")))
        XCTAssertEqual(sem.status, 400)
        let grande = try XCTUnwrap(ip.resposta(ip.pedir("PUT", "/api/config", cabecalhos: ["x-deck-codigo": Cenario.codigo], corpo: String(repeating: "a", count: 1024 * 1024 + 1))))
        XCTAssertEqual(grande.status, 400)
        let ok = try XCTUnwrap(ip.resposta(ip.pedir("GET", "/api/estado", cabecalhos: ["x-deck-codigo": Cenario.codigo])))
        XCTAssertEqual(ok.status, 200)
    }

    func testLogNaoGuardaOCodigoDaQuery() throws {
        let c = try Cenario()
        let (ip, s, _, log) = sessao(c)
        defer { s.encerrar() }
        _ = ip.resposta(ip.pedir("GET", "/api/capa", query: ["codigo": Cenario.codigo]))
        XCTAssertFalse(log.todos.joined().contains(Cenario.codigo))
        XCTAssertTrue(log.todos.contains { $0.contains("GET /api/capa 200") })
    }

    func testCodigoNovoDoRodizioSegueNoCabecalhoDaResposta() {
        let r = SessaoCabo.resposta(RespostaRota(status: 200, tipo: "application/json", corpo: Data("{}".utf8),
                                                  extras: ["X-Deck-Codigo-Novo": "novonovonovonovonovo"]))
        XCTAssertEqual(r.cabecalhos["X-Deck-Codigo-Novo"], "novonovonovonovonovo")
        XCTAssertEqual(r.status, 200)
    }

    func testPingChegaDepoisDoIntervalo() throws {
        let c = try Cenario()
        let (ip, s, _, _) = sessao(c, intervaloDoPing: 0.1)
        defer { s.encerrar() }
        XCTAssertEqual(try XCTUnwrap(Quadros.ler(de: ip.fio)).tipo, "ola")
        XCTAssertEqual(try XCTUnwrap(Quadros.ler(de: ip.fio)).tipo, "ping")
    }

    func testSessaoAcabaQuandoOIPhoneFechaOFio() throws {
        let c = try Cenario()
        let (mac, iphone) = parDeSoquetes()
        let s = SessaoCabo(fluxo: mac, roteador: c.roteador, nomeMac: "Mac", rotulo: "t", intervaloDoPing: 60, log: { _ in })
        let fim = expectation(description: "sessão acabou")
        Thread { s.rodar(); fim.fulfill() }.start()
        iphone.fechar()
        wait(for: [fim], timeout: 5)
    }

    // MARK: usbmuxd

    func testPacoteDoUsbmuxTemCabecalhoLittleEndianEPlist() throws {
        let p = try XCTUnwrap(UsbmuxReal.pacote(tag: 9, ["MessageType": "ListDevices"]))
        let l = [UInt8](p)
        XCTAssertEqual(Int(l[0]) | Int(l[1]) << 8, p.count)
        XCTAssertEqual(Array(l[4..<8]), [1, 0, 0, 0], "versão 1")
        XCTAssertEqual(Array(l[8..<12]), [8, 0, 0, 0], "tipo plist")
        XCTAssertEqual(Array(l[12..<16]), [9, 0, 0, 0], "tag")
        let (a, b) = parDeSoquetes()
        _ = a.escrever(p)
        let lido = try XCTUnwrap(UsbmuxReal.lerPacote(b))
        XCTAssertEqual(lido["MessageType"] as? String, "ListDevices")
        XCTAssertEqual(lido["ProgName"] as? String, "deck")
    }

    /// Sobe um usbmuxd de mentira num soquete unix: um iPhone no USB, um por Wi-Fi, e Connect que vira eco.
    private func usbmuxFalso(portasAceitas: Set<Int>, pedidos: Registro) throws -> String {
        let caminho = "/tmp/deck-mux-\(UUID().uuidString.prefix(8)).sock"
        let fd = ouvirUnix(caminho)
        XCTAssertGreaterThanOrEqual(fd, 0)
        addTeardownBlock { close(fd); unlink(caminho) }
        Thread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                let s = Soquete(fd: c)
                Thread {
                    guard let m = UsbmuxReal.lerPacote(s) else { return }
                    var resposta: [String: Any]
                    switch m["MessageType"] as? String {
                    case "ListDevices":
                        resposta = ["DeviceList": [
                            ["DeviceID": 3, "MessageType": "Attached", "Properties": ["ConnectionType": "USB", "SerialNumber": "AAA"]],
                            ["DeviceID": 4, "MessageType": "Attached", "Properties": ["ConnectionType": "Network", "SerialNumber": "BBB"]],
                        ]]
                    case "Connect":
                        let porta = (m["PortNumber"] as? NSNumber)?.intValue ?? -1
                        pedidos.anotar("connect \(m["DeviceID"] as? Int ?? -1) \(porta)")
                        resposta = ["MessageType": "Result", "Number": portasAceitas.contains(porta) ? 0 : 3]
                    default: return
                    }
                    _ = s.escrever(UsbmuxReal.pacote(tag: 2, resposta)!)
                    if (resposta["Number"] as? Int) == 0 {
                        // vira eco, como o fio cru depois do Connect
                        while let d = s.ler(maximo: 4096) { _ = s.escrever(d) }
                    }
                }.start()
            }
        }.start()
        return caminho
    }

    func testListaSoOsAparelhosPorUsb() throws {
        let caminho = try usbmuxFalso(portasAceitas: [], pedidos: Registro())
        XCTAssertEqual(try UsbmuxReal(caminho: caminho).aparelhosUSB(), [3])
    }

    func testConectaNaPortaEmBigEndianEViraFioCru() throws {
        let pedidos = Registro()
        // 4975 = 0x136F: em big endian dentro de 16 bits vira 0x6F13 = 28435
        let caminho = try usbmuxFalso(portasAceitas: [28435], pedidos: pedidos)
        let fio = try UsbmuxReal(caminho: caminho).conectar(aparelho: 3, porta: 4975)
        XCTAssertEqual(pedidos.todos, ["connect 3 28435"])
        XCTAssertTrue(fio.escrever(Data("oi".utf8)))
        XCTAssertEqual(fio.lerExato(2), Data("oi".utf8))
        fio.fechar()
    }

    func testPortaSemOuvinteDaErroDoUsbmuxComCodigo3() throws {
        let caminho = try usbmuxFalso(portasAceitas: [], pedidos: Registro())
        XCTAssertThrowsError(try UsbmuxReal(caminho: caminho).conectar(aparelho: 3, porta: 4975)) { e in
            XCTAssertEqual((e as? ErroUsbmux)?.codigo, 3)
            XCTAssertTrue((e as? ErroUsbmux)!.description.contains("não está aberto"))
        }
    }

    func testSemUsbmuxdDaErroEmPortugues() {
        XCTAssertThrowsError(try UsbmuxReal(caminho: "/tmp/nao-existe-\(UUID().uuidString).sock").aparelhosUSB()) { e in
            XCTAssertEqual(e as? ErroUsbmux, ErroUsbmux.indisponivel)
        }
    }

    // MARK: Porta do cabo (reconexão)

    /// Um Mux falso: cada conectar entrega um fio novo e guarda a ponta do iPhone.
    final class MuxFalso: Mux, @unchecked Sendable {
        private let trava = NSLock()
        var aparelhos: [Int] = [5]
        var recusa = false
        var pontas: [Soquete] = []
        func aparelhosUSB() throws -> [Int] { trava.withLock { aparelhos } }
        func conectar(aparelho: Int, porta: UInt16) throws -> FluxoBytes {
            if trava.withLock({ recusa }) { throw ErroUsbmux(description: "O app do Deck não está aberto no iPhone.", codigo: 3) }
            let (mac, iphone) = parDeSoquetes()
            trava.withLock { pontas.append(iphone) }
            return mac
        }
        func conexoes() -> Int { trava.withLock { pontas.count } }
        func ponta(_ i: Int) -> Soquete { trava.withLock { pontas[i] } }
    }

    private func esperar(_ condicao: @autoclosure () -> Bool, _ texto: String) {
        for _ in 0..<200 where !condicao() { Thread.sleep(forTimeInterval: 0.025) }
        XCTAssertTrue(condicao(), texto)
    }

    func testPortaConectaUmaVezPorAparelhoEReconectaDepoisDeCair() throws {
        let c = try Cenario()
        let mux = MuxFalso()
        let log = Registro()
        let porta = PortaDoCabo(roteador: c.roteador, nomeMac: { "Mac" }, mux: mux, intervalo: 0.05, log: { log.anotar($0) })
        porta.iniciar()
        defer { porta.parar() }
        esperar(mux.conexoes() == 1, "primeira conexão")
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(mux.conexoes(), 1, "aparelho com sessão viva não ganha outra")

        // a sessão funciona
        let ip = IPhoneFalso(mux.ponta(0))
        XCTAssertEqual(try XCTUnwrap(Quadros.ler(de: ip.fio)).tipo, "ola")
        let r = try XCTUnwrap(ip.resposta(ip.pedir("GET", "/api/estado", cabecalhos: ["x-deck-codigo": Cenario.codigo])))
        XCTAssertEqual(r.status, 200)

        // tirou o cabo: o fio cai, a porta percebe e conecta de novo sozinha
        mux.ponta(0).fechar()
        esperar(mux.conexoes() == 2, "reconexão")
        XCTAssertEqual(try XCTUnwrap(Quadros.ler(de: IPhoneFalso(mux.ponta(1)).fio)).tipo, "ola")
        XCTAssertTrue(log.todos.contains { $0.contains("caiu") })
    }

    func testPortaSemAppNoIPhoneEsperaESoAvisaUmaVez() throws {
        let c = try Cenario()
        let mux = MuxFalso()
        mux.recusa = true
        let log = Registro()
        let porta = PortaDoCabo(roteador: c.roteador, nomeMac: { "Mac" }, mux: mux, intervalo: 0.02, log: { log.anotar($0) })
        porta.iniciar()
        defer { porta.parar() }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(log.todos.filter { $0.contains("não está aberto") }.count, 1, "\(log.todos)")
        mux.recusa = false
        esperar(mux.conexoes() == 1, "conecta quando o app abre")
    }

    func testPortaSemNenhumIPhoneNaoConectaENemQuebra() throws {
        let c = try Cenario()
        let mux = MuxFalso()
        mux.aparelhos = []
        let porta = PortaDoCabo(roteador: c.roteador, nomeMac: { "Mac" }, mux: mux, intervalo: 0.02, log: { _ in })
        porta.varrer()
        XCTAssertEqual(mux.conexoes(), 0)
        XCTAssertEqual(porta.sessoesAtivas, 0)
    }
}
