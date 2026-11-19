import XCTest
@testable import Nucleo

final class AvisosDeForaTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)
    let chave = "abcdefghjkmnpqrstuvwxyz234567892"

    func roteador(_ armazem: ArmazemDeAvisos = ArmazemDeAvisos(fuso: TimeZone(identifier: "UTC")!)) -> (RoteadorDeFora, ArmazemDeAvisos) {
        let k = chave
        return (RoteadorDeFora(armazem: armazem, chave: { k }), armazem)
    }

    func pedir(_ r: RoteadorDeFora, _ caminho: String, _ corpo: String = "", metodo: String = "POST", chave: String? = "abcdefghjkmnpqrstuvwxyz234567892", em: Date? = nil) -> RespostaRota {
        var cab: [String: String] = [:]
        if let chave { cab["x-deck-chave"] = chave }
        return r.responder(HttpRequisicao(metodo: metodo, caminho: caminho, query: [:], cabecalhos: cab, corpo: Data(corpo.utf8)), agora: em ?? agora)
    }

    // MARK: Chave

    func testSemChaveOuComChaveErradaNadaEhGravado() {
        let (r, a) = roteador()
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"x"}"#, chave: nil).status, 401)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"x"}"#, chave: "errada").status, 401)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"1"}"#, chave: "abcdefghjkmnpqrstuvwxyz23456789").status, 401, "chave com um caractere a menos")
        XCTAssertTrue(a.foto(agora: agora).avisos.isEmpty && a.foto(agora: agora).valores.isEmpty)
    }

    func testOCodigoDoIphoneNaoServeDeChave() {
        let (r, _) = roteador()
        let resposta = r.responder(HttpRequisicao(metodo: "POST", caminho: "/aviso", query: [:], cabecalhos: ["x-deck-codigo": chave], corpo: Data(#"{"titulo":"x"}"#.utf8)), agora: agora)
        XCTAssertEqual(resposta.status, 401)
    }

    func testChaveVaziaNuncaAbre() {
        let r = RoteadorDeFora(armazem: ArmazemDeAvisos(), chave: { "" })
        XCTAssertEqual(r.responder(HttpRequisicao(metodo: "POST", caminho: "/aviso", query: [:], cabecalhos: ["x-deck-chave": ""], corpo: Data(#"{"titulo":"x"}"#.utf8)), agora: agora).status, 401)
    }

    // MARK: Aviso

    func testAvisoValidoEntraComIdNivelEHora() {
        let (r, a) = roteador()
        let resposta = pedir(r, "/aviso", #"{"titulo":"Build pronto","texto":"Passou em 2 min","nivel":"ok"}"#)
        XCTAssertEqual(resposta.status, 200)
        XCTAssertEqual((resposta.json as? [String: Any])?["id"] as? Int, 1)
        let avisos = a.foto(agora: agora).avisos
        XCTAssertEqual(avisos, [AvisoDeFora(id: 1, titulo: "Build pronto", texto: "Passou em 2 min", nivel: "ok", em: Datas.iso(agora, fuso: TimeZone(identifier: "UTC")!))])
    }

    func testNivelPadraoEInfoENivelDesconhecidoEhRecusado() {
        let (r, a) = roteador()
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"a"}"#).status, 200)
        XCTAssertEqual(a.foto(agora: agora).avisos.first?.nivel, "info")
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"a","nivel":"urgente"}"#).status, 400)
    }

    func testAvisoSemTituloOuComTextoGrandeOuComControleEhRecusado() {
        let (r, _) = roteador()
        XCTAssertEqual(pedir(r, "/aviso", #"{"texto":"sem título"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"   "}"#).status, 400)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"\#(String(repeating: "a", count: 61))"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"ok","texto":"\#(String(repeating: "b", count: 141))"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"duas\nlinhas"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"no limite \#(String(repeating: "c", count: 48))"}"#).status, 200)
    }

    func testAvisoVenceEAListaGuardaSoOsUltimos() {
        let (r, a) = roteador()
        for i in 1...12 { _ = pedir(r, "/aviso", #"{"titulo":"n\#(i)"}"#, em: agora.addingTimeInterval(Double(i))) }
        let vivos = a.foto(agora: agora.addingTimeInterval(13)).avisos
        XCTAssertEqual(vivos.count, ArmazemDeAvisos.maxAvisos)
        XCTAssertEqual(vivos.first?.titulo, "n3")
        XCTAssertEqual(vivos.last?.titulo, "n12")
        XCTAssertTrue(a.foto(agora: agora.addingTimeInterval(13 + ArmazemDeAvisos.validadeDoAviso)).avisos.isEmpty, "passou a validade, o aviso sai")
    }

    // MARK: Valor

    func testValorGravaComValidadePadraoETextoOuNumero() {
        let (r, a) = roteador()
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"build","valor":"ok"}"#).status, 200)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"temp","valor":23.5,"validade":60}"#).status, 200)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"fila","valor":7}"#).status, 200)
        let v = a.foto(agora: agora).valores
        XCTAssertEqual(v.map(\.chave), ["build", "fila", "temp"])
        XCTAssertEqual(v.map(\.valor), ["ok", "7", "23.5"])
        XCTAssertEqual(Datas.ler(v[0].ate), agora.addingTimeInterval(3600))
        XCTAssertEqual(Datas.ler(v[2].ate), agora.addingTimeInterval(60))
    }

    func testValorVenceENovoValorDaMesmaChaveSubstitui() {
        let (r, a) = roteador()
        _ = pedir(r, "/valor", #"{"chave":"x","valor":"1","validade":30}"#)
        _ = pedir(r, "/valor", #"{"chave":"x","valor":"2","validade":300}"#, em: agora.addingTimeInterval(10))
        XCTAssertEqual(a.foto(agora: agora.addingTimeInterval(100)).valores.map(\.valor), ["2"])
        XCTAssertTrue(a.foto(agora: agora.addingTimeInterval(400)).valores.isEmpty)
    }

    func testValorRecusaChaveValorEValidadeForaDaRegra() {
        let (r, _) = roteador()
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"com espaço","valor":"1"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"../x","valor":"1"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"\#(String(repeating: "k", count: 33))","valor":"1"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"valor":"1"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":true}"#).status, 400, "booleano não é valor")
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":{"a":1}}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"\#(String(repeating: "v", count: 41))"}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"1","validade":0}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"1","validade":86401}"#).status, 400)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"1","validade":"60"}"#).status, 400, "validade é número")
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k","valor":"1","validade":86400}"#).status, 200)
    }

    func testNaoPassaDeVinteChavesMasSubstituirUmaExistenteSempreDeixa() {
        let (r, _) = roteador()
        for i in 1...ArmazemDeAvisos.maxValores { XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k\#(i)","valor":"1"}"#, em: agora.addingTimeInterval(Double(i) / 100)).status, 200) }
        // A taxa já gastou 20 vagas: abre espaço de tempo e testa o limite de chaves.
        let depois = agora.addingTimeInterval(ArmazemDeAvisos.janela + 1)
        let cheio = pedir(r, "/valor", #"{"chave":"nova","valor":"1"}"#, em: depois)
        XCTAssertEqual(cheio.status, 409)
        XCTAssertEqual(pedir(r, "/valor", #"{"chave":"k1","valor":"2"}"#, em: depois).status, 200)
    }

    // MARK: Forma do pedido

    func testRotaMetodoCorpoEJsonInvalido() {
        let (r, _) = roteador()
        XCTAssertEqual(pedir(r, "/outra", "{}").status, 404)
        XCTAssertEqual(pedir(r, "/aviso", metodo: "GET").status, 405)
        XCTAssertEqual(pedir(r, "/aviso", "isso nao e json").status, 400)
        XCTAssertEqual(pedir(r, "/aviso", "[1,2]").status, 400)
        let grande = #"{"titulo":"x","texto":"\#(String(repeating: "a", count: 5000))"}"#
        XCTAssertEqual(pedir(r, "/aviso", grande).status, 413)
    }

    // MARK: Taxa

    func testPassouDaTaxaVira429ComEsperaEVoltaDepoisDaJanela() {
        let (r, a) = roteador()
        for i in 0..<ArmazemDeAvisos.pedidosPorJanela { XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"a\#(i)"}"#, em: agora.addingTimeInterval(Double(i) * 0.1)).status, 200) }
        let barrado = pedir(r, "/aviso", #"{"titulo":"a"}"#, em: agora.addingTimeInterval(10))
        XCTAssertEqual(barrado.status, 429)
        XCTAssertNotNil(barrado.extras["Retry-After"])
        XCTAssertNotNil(barrado.erroTexto)
        XCTAssertEqual(a.foto(agora: agora.addingTimeInterval(10)).avisos.count, ArmazemDeAvisos.maxAvisos)
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"a"}"#, em: agora.addingTimeInterval(ArmazemDeAvisos.janela + 1)).status, 200)
    }

    func testChuteDeChaveTambemGastaAVaga() {
        let (r, _) = roteador()
        for _ in 0..<ArmazemDeAvisos.pedidosPorJanela { XCTAssertEqual(pedir(r, "/aviso", "{}", chave: "x").status, 401) }
        XCTAssertEqual(pedir(r, "/aviso", #"{"titulo":"a"}"#).status, 429, "nem a chave certa passa depois do limite")
    }

    // MARK: Chave em arquivo

    func testChaveNasceComTrintaEDoisCaracteresPermissaoSoDoDonoEFicaIgual() throws {
        let pasta = try pastaTemporaria()
        let c = ChaveDeAvisos(pasta: pasta)
        let k = c.atual()
        XCTAssertTrue(ChaveDeAvisos.valida(k))
        XCTAssertEqual(ChaveDeAvisos(pasta: pasta).atual(), k, "outra instância lê o arquivo")
        let perm = try FileManager.default.attributesOfItem(atPath: pasta.appendingPathComponent("chave-avisos").path)[.posixPermissions] as? Int
        XCTAssertEqual(perm, 0o600)
        XCTAssertNotEqual(c.trocar(), k)
        XCTAssertEqual(ChaveDeAvisos(pasta: pasta).atual(), c.atual())
    }

    func testArquivoDeChaveEstragadoViraChaveNova() throws {
        let pasta = try pastaTemporaria()
        try Data("lixo".utf8).write(to: pasta.appendingPathComponent("chave-avisos"))
        XCTAssertTrue(ChaveDeAvisos.valida(ChaveDeAvisos(pasta: pasta).atual()))
    }

    func testChaveDeForaNaoEhOCodigoDoIphone() {
        XCTAssertNotEqual(ChaveDeAvisos.tamanho, Config.tamanhoCodigo)
    }

    func testExemploDeCurlLevaPortaEChave() {
        XCTAssertTrue(ExemploDeFora.curlAviso(porta: 4792, chave: "K").contains("http://127.0.0.1:4792/aviso -H 'X-Deck-Chave: K'"))
        XCTAssertTrue(ExemploDeFora.curlValor(porta: 4792, chave: "K").contains("/valor"))
    }

    // MARK: Estado

    func testEstadoLevaOsAvisosSemPrecisarDeTeclaEOsValoresSoComATeclaValores() {
        let armazem = ArmazemDeAvisos()
        _ = armazem.registrarAviso(titulo: "Deploy", texto: nil, nivel: "ok", agora: agora)
        _ = armazem.registrarValor(chave: "fila", valor: "3", validade: nil, agora: agora)
        var f = Fontes.vivas(executor: ExecutorFalso([]), casa: "/nonexistent", avisos: armazem)
        f.sessoes = { Leitura(valor: [], aviso: nil) }
        let sem = Perfil(id: "p", nome: "P", teclas: [Tecla(id: "a", nome: "A", tipo: "comando", valor: "true", estado: nil, icone: nil)])
        let com = Perfil(id: "p", nome: "P", teclas: [Tecla(id: "v", nome: "Valores", tipo: "app", valor: TeclasDeFora.valorDosValores, estado: nil, icone: nil)])
        let ag = Agregador(fontes: f)
        let e1 = ag.estado(config: Config(perfis: [sem], perfilAtivo: "p", nomeMac: "Mac", codigoAcesso: "abcdefghjkmnpqrstuvw"), agora: agora)
        XCTAssertEqual(e1.avisosDeFora?.map(\.titulo), ["Deploy"])
        XCTAssertNil(e1.valoresDeFora, "sem a tecla Valores o estado não carrega valores")
        let e2 = ag.estado(config: Config(perfis: [com], perfilAtivo: "p", nomeMac: "Mac", codigoAcesso: "abcdefghjkmnpqrstuvw"), agora: agora)
        XCTAssertEqual(e2.valoresDeFora?.map(\.valor), ["3"])
        XCTAssertEqual(e2.selos["v"], "1", "a tecla mostra quantos valores vivos há")
        let vazio = ag.estado(config: Config(perfis: [com], perfilAtivo: "p", nomeMac: "Mac", codigoAcesso: "abcdefghjkmnpqrstuvw"), agora: agora.addingTimeInterval(7200))
        XCTAssertNil(vazio.avisosDeFora)
        XCTAssertEqual(vazio.valoresDeFora, [])
        XCTAssertNil(vazio.selos["v"])
    }
}

#if canImport(Network)
/// Prova com socket de verdade: o servidor sobe numa porta livre do loopback e o pedido vai por TCP, como o curl de um script.
final class ServidorDeForaTestes: XCTestCase {
    func testPorTcpAbreSoNoLoopbackEGravaOAviso() throws {
        let armazem = ArmazemDeAvisos()
        let chave = "abcdefghjkmnpqrstuvwxyz234567892"
        let s = try ServidorDeFora.ligar(roteador: RoteadorDeFora(armazem: armazem, chave: { chave }), preferida: 47_920)
        defer { s.parar() }
        let corpo = #"{"titulo":"Pelo socket"}"#
        let ok = try pedirPorTcp(porta: s.porta, "POST /aviso HTTP/1.1\r\nHost: x\r\nX-Deck-Chave: \(chave)\r\nContent-Length: \(corpo.utf8.count)\r\n\r\n\(corpo)")
        XCTAssertTrue(ok.hasPrefix("HTTP/1.1 200"), ok)
        XCTAssertEqual(armazem.foto(agora: Date()).avisos.map(\.titulo), ["Pelo socket"])
        let negado = try pedirPorTcp(porta: s.porta, "POST /aviso HTTP/1.1\r\nHost: x\r\nContent-Length: \(corpo.utf8.count)\r\n\r\n\(corpo)")
        XCTAssertTrue(negado.hasPrefix("HTTP/1.1 401"), negado)
        XCTAssertEqual(armazem.foto(agora: Date()).avisos.count, 1)
    }

    func testPeloEnderecoDaRedeAPortaNaoAbre() throws {
        var lista: UnsafeMutablePointer<ifaddrs>?
        XCTAssertEqual(getifaddrs(&lista), 0)
        defer { freeifaddrs(lista) }
        var enderecos: [String] = []
        var p = lista
        while let i = p?.pointee {
            if let a = i.ifa_addr, a.pointee.sa_family == sa_family_t(AF_INET), (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (i.ifa_flags & UInt32(IFF_UP)) != 0 {
                var ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var nome = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &ip, &nome, socklen_t(INET_ADDRSTRLEN))
                enderecos.append(String(cString: nome))
            }
            p = i.ifa_next
        }
        guard let rede = enderecos.first else { throw XCTSkip("Este Mac não tem endereço de rede além do loopback.") }
        let s = try ServidorDeFora.ligar(roteador: RoteadorDeFora(armazem: ArmazemDeAvisos(), chave: { "k" }), preferida: 47_940)
        defer { s.parar() }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var end = sockaddr_in()
        end.sin_family = sa_family_t(AF_INET)
        end.sin_port = s.porta.bigEndian
        end.sin_addr.s_addr = inet_addr(rede)
        let r = withUnsafePointer(to: &end) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(r, -1, "pelo \(rede) a porta de fora não pode abrir")
    }

    /// Conecta no 127.0.0.1 e devolve a resposta inteira. Pelo endereço da rede (en0) a conexão tem de ser recusada.
    private func pedirPorTcp(porta: UInt16, _ pedido: String) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var fim = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &fim, socklen_t(MemoryLayout<timeval>.size))
        var end = sockaddr_in()
        end.sin_family = sa_family_t(AF_INET)
        end.sin_port = porta.bigEndian
        end.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &end) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(r, 0, "conectar no loopback")
        _ = pedido.withCString { send(fd, $0, strlen($0), 0) }
        var saida = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            saida.append(contentsOf: buf[0..<n])
        }
        return String(decoding: saida, as: UTF8.self)
    }
}
#endif
