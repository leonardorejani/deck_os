import XCTest
@testable import Nucleo

final class ExecutorGravador: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var _comandos: [String] = []
    var respostas: [(String) -> SaidaShell?] = []
    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }
    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); _comandos.append(comando); trava.unlock()
        for r in respostas { if let s = r(comando) { return s } }
        return SaidaShell(status: 0, saida: "")
    }
}

final class CertificadoTestes: XCTestCase {
    private let rede = DadosRede(nome: "mac.local", ip: "192.168.0.10")
    private let agora = Date(timeIntervalSince1970: 1_800_000_000)
    private let agoraFixo: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }

    func testRefazQuandoIpOuNomeMudam() {
        let meta = MetaCertificado(nome: "mac.local", ip: "192.168.0.10", vence: agora.addingTimeInterval(300 * 86_400))
        XCTAssertFalse(CertificadoRegra.precisaRefazer(meta: meta, rede: rede, agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: meta, rede: DadosRede(nome: "mac.local", ip: "10.0.0.2"), agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: meta, rede: DadosRede(nome: "outro.local", ip: "192.168.0.10"), agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: meta, rede: DadosRede(nome: "mac.local", ip: nil), agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: nil, rede: rede, agora: agora))
    }

    func testRefazFaltando30DiasParaVencer() {
        func meta(_ dias: Double) -> MetaCertificado {
            MetaCertificado(nome: "mac.local", ip: "192.168.0.10", vence: agora.addingTimeInterval(dias * 86_400))
        }
        XCTAssertFalse(CertificadoRegra.precisaRefazer(meta: meta(31), rede: rede, agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: meta(29), rede: rede, agora: agora))
        XCTAssertTrue(CertificadoRegra.precisaRefazer(meta: meta(-1), rede: rede, agora: agora))
    }

    func testExtensoesTemSanServerAuthESemCa() {
        let t = CertificadoRegra.extensoes(rede)
        XCTAssertTrue(t.contains("subjectAltName=DNS:mac.local,IP:192.168.0.10"))
        XCTAssertTrue(t.contains("extendedKeyUsage=serverAuth"))
        XCTAssertTrue(t.contains("basicConstraints=CA:FALSE"))
        XCTAssertFalse(CertificadoRegra.extensoes(DadosRede(nome: "mac.local", ip: nil)).contains("IP:"))
    }

    func testAspasProtegeCaminhoComEspacoEAspa() {
        XCTAssertEqual(CertificadoRegra.aspas("/a b/c"), "'/a b/c'")
        XCTAssertEqual(CertificadoRegra.aspas("o'neil"), "'o'\\''neil'")
    }

    private func pastaTemp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("deck-cert-\(UUID().uuidString)")
    }

    private func executorDeRede(_ ex: ExecutorGravador, nome: String = "mac", ip: String = "192.168.0.10") {
        ex.respostas = [{ $0.hasPrefix("scutil") ? SaidaShell(status: 0, saida: nome + "\n") : nil },
                        { $0.hasPrefix("ipconfig") ? SaidaShell(status: 0, saida: ip + "\n") : nil }]
    }

    func testLeNomeEIpPeloExecutor() throws {
        let ex = ExecutorGravador()
        executorDeRede(ex)
        let g = GeradorCertificado(pasta: pastaTemp(), executor: ex)
        XCTAssertEqual(try g.lerRede(), rede.with(nome: "mac.local"))
        ex.respostas = [{ _ in SaidaShell(status: 1, saida: "") }]
        XCTAssertThrowsError(try g.lerRede())
    }

    func testPrimeiraVezCriaCaEServidorComPermissaoRestrita() throws {
        let ex = ExecutorGravador()
        executorDeRede(ex)
        let pasta = pastaTemp()
        let g = GeradorCertificado(pasta: pasta, executor: ex, agora: agoraFixo)
        // O falso não roda openssl: cria os arquivos que o openssl criaria.
        ex.respostas.append({ cmd in
            guard cmd.hasPrefix("openssl") else { return nil }
            for m in ["-keyout '", "-out '"] {
                if let r = cmd.range(of: m) {
                    let resto = cmd[r.upperBound...]
                    if let fim = resto.firstIndex(of: "'") {
                        FileManager.default.createFile(atPath: String(resto[..<fim]), contents: Data("x".utf8))
                    }
                }
            }
            return SaidaShell(status: 0, saida: "")
        })
        let a = try g.garantir()
        let ossl = ex.comandos.filter { $0.hasPrefix("openssl") }
        XCTAssertEqual(ossl.count, 3, "CA, chave+pedido do servidor, assinatura")
        XCTAssertTrue(ossl[0].contains("-days 3650"))
        XCTAssertTrue(ossl[2].contains("-days 397"))
        XCTAssertTrue(ossl[2].contains("-extfile"))
        let perm = { (u: URL) in (try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }
        XCTAssertEqual(try perm(a.caChave), 0o600)
        XCTAssertEqual(try perm(a.servidorChave), 0o600)
        XCTAssertEqual(try perm(pasta), 0o700)
        XCTAssertTrue(try String(contentsOf: a.extensoes, encoding: .utf8).contains("DNS:mac.local,IP:192.168.0.10"))

        // Segunda chamada com tudo igual não gera nada.
        let antes = ex.comandos.count
        try g.garantir()
        XCTAssertEqual(ex.comandos.filter { $0.hasPrefix("openssl") }.count, 3)
        XCTAssertEqual(ex.comandos.count, antes + 2, "só relê nome e IP")

        // IP mudou: refaz só o servidor, o CA continua o mesmo.
        executorDeRede(ex, ip: "10.0.0.7")
        ex.respostas.append({ cmd in cmd.hasPrefix("openssl") ? SaidaShell(status: 0, saida: "") : nil })
        try g.garantir()
        let novos = ex.comandos.filter { $0.hasPrefix("openssl") }
        XCTAssertEqual(novos.count, 5)
        XCTAssertFalse(novos[3].contains("-x509"), "o CA não é refeito")
        XCTAssertTrue(try String(contentsOf: a.extensoes, encoding: .utf8).contains("IP:10.0.0.7"))
    }

    func testFalhaDoOpensslViraErroEmTexto() throws {
        let ex = ExecutorGravador()
        executorDeRede(ex)
        ex.respostas.append({ $0.hasPrefix("openssl") ? SaidaShell(status: 1, saida: "boom") : nil })
        let g = GeradorCertificado(pasta: pastaTemp(), executor: ex)
        XCTAssertThrowsError(try g.garantir()) { XCTAssertTrue("\($0)".contains("boom")) }
    }

    /// Prova de verdade com o openssl do sistema, quando ele existe (Mac e imagens com openssl).
    func testComOpensslDeVerdade() throws {
        guard ExecutorShell().rodar("command -v openssl").status == 0 else { throw XCTSkip("sem openssl nesta máquina") }
        let ex = ExecutorGravador()
        executorDeRede(ex, nome: "deck-teste")
        ex.respostas.append({ _ in nil })
        let real = ExecutorShell()
        struct Misto: Executor {
            let falso: ExecutorGravador, real: ExecutorShell
            func rodar(_ c: String) -> SaidaShell { c.hasPrefix("openssl") ? real.rodar(c) : falso.rodar(c) }
        }
        let g = GeradorCertificado(pasta: pastaTemp(), executor: Misto(falso: ex, real: real))
        let a = try g.garantir()
        let verificar = real.rodar("openssl verify -CAfile '\(a.ca.path)' '\(a.servidor.path)'")
        XCTAssertEqual(verificar.status, 0, verificar.saida)
        let san = real.rodar("openssl x509 -in '\(a.servidor.path)' -noout -text")
        XCTAssertTrue(san.saida.contains("DNS:deck-teste.local"), san.saida)
        XCTAssertTrue(san.saida.contains("IP Address:192.168.0.10"), san.saida)
        XCTAssertTrue(san.saida.contains("TLS Web Server Authentication"), san.saida)
    }
}

private extension DadosRede {
    func with(nome: String) -> DadosRede { DadosRede(nome: nome, ip: ip) }
}
