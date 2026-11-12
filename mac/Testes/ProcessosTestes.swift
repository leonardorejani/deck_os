import XCTest
@testable import Nucleo

/// Pedaço de saída do `ps -axo pid=,pcpu=,rss=,user=,comm=` (nomes inventados).
private let saidaPs = """
    1   0.0   10240 root /sbin/launchd
  120  35.2  204800 root /usr/libexec/WindowServer
  400  12.5  512000 leo /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
  401  80.1 1048576 leo /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
  500   3.0  300000 leo /Applications/Deck.app/Contents/MacOS/Deck
  600   0.4   90000 outra /usr/bin/algo
  700   9.9  150000 leo /usr/bin/ps
  800   1.1   65536 leo kernel_task
  900   2,5   32768 leo /Applications/Notas.app/Contents/MacOS/Notas
"""

final class ProcessosTestes: XCTestCase {
    func testLeAsLinhasComCaminhoComEspacoEVirgulaDecimal() {
        let l = Processos.ler(saidaPs)
        XCTAssertEqual(l.count, 9)
        XCTAssertEqual(l.first { $0.pid == 401 }?.nome, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(l.first { $0.pid == 401 }?.cpu, 80.1)
        XCTAssertEqual(l.first { $0.pid == 900 }?.cpu, 2.5)
        XCTAssertEqual(l.first { $0.pid == 800 }?.nome, "kernel_task")
        XCTAssertTrue(Processos.ler("lixo\n\n  12 x\n").isEmpty, "linha torta não vira processo")
    }

    func testTop5PorProcessadorEPorMemoriaSemOPsNemOApp() {
        let e = Processos.maiores(Processos.ler(saidaPs), usuario: "leo", eu: 500, quantos: 3)
        XCTAssertEqual(e.cpu.map(\.pid), [401, 120, 400], "ordem de uso, sem o ps (700) nem o próprio app (500)")
        XCTAssertEqual(e.memoria.map(\.pid), [401, 400, 120])
        XCTAssertEqual(e.memoria.first?.memoria, 1048576 * 1024, "rss vem em KB e a tela recebe em bytes")
        XCTAssertEqual(Processos.maiores(Processos.ler(saidaPs), usuario: "leo", eu: 500).cpu.count, 5)
    }

    func testSoMostraEncerrarOndeDa() {
        let e = Processos.maiores(Processos.ler(saidaPs), usuario: "leo", eu: 500, quantos: 20)
        let por = Dictionary(uniqueKeysWithValues: e.cpu.map { ($0.pid, $0.podeEncerrar) })
        XCTAssertEqual(por[401], true)
        XCTAssertEqual(por[900], true)
        XCTAssertEqual(por[1], false, "launchd")
        XCTAssertEqual(por[120], false, "do sistema (root)")
        XCTAssertEqual(por[600], false, "de outro usuário")
        XCTAssertEqual(por[800], false, "kernel_task é protegido mesmo com o mesmo usuário")
    }

    func testEstadoVazioQuandoOPsFalha() {
        let p = ProcessosReais(executor: ExecutorFalso([("ps -axo", SaidaShell(status: 1, saida: ""))]), usuario: "leo", eu: 1)
        XCTAssertEqual(p.maiores(), EstadoProcessos(cpu: [], memoria: []))
    }

    // MARK: encerrar

    private func reais(_ saida: String, matou: Registro, retorno: Int32 = 0) -> ProcessosReais {
        ProcessosReais(executor: ExecutorFalso([("ps -p", SaidaShell(status: saida.isEmpty ? 1 : 0, saida: saida))]), usuario: "leo", eu: 500,
                       matar: { pid in matou.anotar("kill \(pid)"); return retorno })
    }

    func testEncerraComSigtermQuandoTudoConfere() {
        let r = Registro()
        XCTAssertNil(reais("  401  80.1 1048576 leo /x/Google Chrome Helper (Renderer)\n", matou: r).encerrar(pid: 401, nome: "Google Chrome Helper (Renderer)"))
        XCTAssertEqual(r.todos, ["kill 401"])
    }

    func testNaoEncerraOQueNaoPode() {
        let r = Registro()
        XCTAssertNotNil(reais("  1 0.0 10 root /sbin/launchd\n", matou: r).encerrar(pid: 1, nome: "launchd"), "pid 1")
        XCTAssertNotNil(reais("  500 0.0 10 leo /x/Deck\n", matou: r).encerrar(pid: 500, nome: "Deck"), "o próprio app")
        XCTAssertNotNil(reais("  120 0.0 10 root /usr/libexec/WindowServer\n", matou: r).encerrar(pid: 120, nome: "WindowServer"), "root")
        XCTAssertNotNil(reais("  600 0.0 10 outra /usr/bin/algo\n", matou: r).encerrar(pid: 600, nome: "algo"), "outro usuário")
        XCTAssertNotNil(reais("  601 0.0 10 leo /x/loginwindow\n", matou: r).encerrar(pid: 601, nome: "loginwindow"), "protegido")
        XCTAssertTrue(r.todos.isEmpty, "nenhum sinal foi mandado")
    }

    func testPidReaproveitadoPorOutroProgramaNaoEFechado() {
        let r = Registro()
        let msg = reais("  400 1.0 10 leo /x/Safari\n", matou: r).encerrar(pid: 400, nome: "Google Chrome")
        XCTAssertEqual(msg, "Esse número agora é de outro programa. Atualize a lista.")
        XCTAssertTrue(r.todos.isEmpty)
    }

    func testProcessoQueJaFechouEFalhaDoSinalViramMensagem() {
        let r = Registro()
        XCTAssertEqual(reais("", matou: r).encerrar(pid: 400, nome: "x"), "Esse processo já tinha fechado.")
        XCTAssertEqual(reais("  400 1.0 10 leo /x/Safari\n", matou: r, retorno: -1).encerrar(pid: 400, nome: "Safari"), "Não consegui encerrar o Safari.")
    }

    // MARK: rotas

    private func cenario() throws -> (Cenario, ProcessosFalsos) {
        var c = try Cenario()
        let f = ProcessosFalsos(c.registro)
        c.roteador.processos = f
        return (c, f)
    }

    func testRotaListaPrecisaDoCodigoELevaOsDoisTops() throws {
        let (c, _) = try cenario()
        XCTAssertEqual(c.pedir("GET", "/api/processos", codigo: nil).status, 401)
        let r = c.pedir("GET", "/api/processos")
        XCTAssertEqual(r.status, 200)
        let j = r.json as? [String: Any]
        XCTAssertEqual((j?["cpu"] as? [[String: Any]])?.first?["nome"] as? String, "Safari")
        XCTAssertEqual((j?["memoria"] as? [[String: Any]])?.first?["podeEncerrar"] as? Bool, true)
        XCTAssertEqual(c.pedir("POST", "/api/processos").status, 405)
    }

    func testRotaEncerrarMandaPidENome() throws {
        let (c, _) = try cenario()
        XCTAssertEqual(c.pedir("POST", "/api/processos/321/encerrar?nome=Safari").status, 200)
        XCTAssertEqual(c.registro.todos, ["encerrar 321 Safari"])
    }

    func testRotaEncerrarRecusaPedidoRuim() throws {
        let (c, f) = try cenario()
        for alvo in ["/api/processos/abc/encerrar?nome=x", "/api/processos/1/encerrar?nome=x", "/api/processos/-4/encerrar?nome=x",
                     "/api/processos/321/encerrar", "/api/processos/321/encerrar?nome="] {
            XCTAssertEqual(c.pedir("POST", alvo).status, 400, alvo)
        }
        XCTAssertEqual(c.pedir("GET", "/api/processos/321/encerrar?nome=x").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/processos/321/encerrar?nome=x", codigo: nil).status, 401)
        XCTAssertTrue(c.registro.todos.isEmpty)
        f.erro = "Esse processo é do sistema ou do Deck e não pode ser encerrado."
        let r = c.pedir("POST", "/api/processos/321/encerrar?nome=x")
        XCTAssertEqual(r.status, 422)
        XCTAssertEqual(r.erroTexto, f.erro)
    }

    func testSemProvedorAsRotasNaoExistem() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/processos").status, 404)
        XCTAssertEqual(c.pedir("POST", "/api/processos/321/encerrar?nome=x").status, 404)
    }
}

final class ProcessosFalsos: ProcessosDoMac, @unchecked Sendable {
    let registro: Registro
    var erro: String?
    init(_ r: Registro) { registro = r }
    func maiores() -> EstadoProcessos {
        let a = Processo(pid: 321, nome: "Safari", cpu: 40.5, memoria: 900 * 1024 * 1024, podeEncerrar: true)
        let b = Processo(pid: 322, nome: "Mail", cpu: 5, memoria: 1500 * 1024 * 1024, podeEncerrar: true)
        return EstadoProcessos(cpu: [a, b], memoria: [b, a])
    }
    func encerrar(pid: Int, nome: String) -> String? { registro.anotar("encerrar \(pid) \(nome)"); return erro }
}
