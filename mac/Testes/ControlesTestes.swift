import XCTest
@testable import Nucleo

/// Brilho falso: guarda o que foi pedido e deixa ligar ou desligar cada recurso.
final class BrilhoFalso: BrilhoDoMac, @unchecked Sendable {
    private let trava = NSLock()
    private var _tela: Int?
    private var _teclado: Int?
    private var _pedidos: [String] = []
    var recusa = false
    init(tela: Int?, teclado: Int?) { _tela = tela; _teclado = teclado }
    var pedidos: [String] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func lerTela() -> Int? { trava.lock(); defer { trava.unlock() }; return _tela }
    func lerTeclado() -> Int? { trava.lock(); defer { trava.unlock() }; return _teclado }
    func definirTela(_ valor: Int) -> Bool {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append("tela \(valor)"); if recusa { return false }; _tela = valor; return true
    }
    func definirTeclado(_ valor: Int) -> Bool {
        trava.lock(); defer { trava.unlock() }
        _pedidos.append("teclado \(valor)"); if recusa { return false }; _teclado = valor; return true
    }
}

final class TecladoSuprimidoTestes: XCTestCase {
    /// Luz marcada como suprimida (auto-brilho ligado) continua sendo controle que funciona: a barra tem que aparecer.
    func testeSuprimidaNaoEscondeOTeclado() {
        XCTAssertTrue(Controles.tecladoServe(interno: true, suprimida: true))
        XCTAssertTrue(Controles.tecladoServe(interno: true, suprimida: false))
    }
    func testeSemTecladoInternoNaoOferece() {
        XCTAssertFalse(Controles.tecladoServe(interno: false, suprimida: false))
        XCTAssertFalse(Controles.tecladoServe(interno: false, suprimida: true))
    }
}

/// Controles falsos para as rotas.
final class ControlesFalsos: ControlesDoMac, @unchecked Sendable {
    let registro: Registro
    var estadoAtual = EstadoControles(volume: 40, mudo: false, brilho: 70, teclado: 30)
    var erro: String?
    init(_ r: Registro) { registro = r }
    func estado() -> EstadoControles { estadoAtual }
    func definirVolume(_ v: Int) -> String? { registro.anotar("volume \(v)"); return erro }
    func definirMudo(_ m: Bool) -> String? { registro.anotar("mudo \(m)"); return erro }
    func definirBrilho(_ v: Int) -> String? { registro.anotar("brilho \(v)"); return erro }
    func definirTeclado(_ v: Int) -> String? { registro.anotar("teclado \(v)"); return erro }
}

final class ControlesTestes: XCTestCase {
    private let saidaVolume = "output volume:40, input volume:47, alert volume:57, output muted:false"

    func testLeOVolumeEOMudoDoSistema() {
        let (v, m) = Controles.lerVolume(saidaVolume)
        XCTAssertEqual(v, 40)
        XCTAssertEqual(m, false)
        let mudo = Controles.lerVolume("output volume:0, input volume:47, alert volume:57, output muted:true")
        XCTAssertEqual(mudo.volume, 0)
        XCTAssertEqual(mudo.mudo, true)
    }

    func testSaidaSemVolumeProprioNaoInventaValor() {
        let r = Controles.lerVolume("output volume:missing value, input volume:47, alert volume:57, output muted:missing value")
        XCTAssertNil(r.volume)
        XCTAssertNil(r.mudo)
        XCTAssertNil(Controles.lerVolume("lixo").volume)
    }

    func testEstadoMostraSoOQueOMacOferece() {
        let sh = ExecutorFalso([("get volume settings", SaidaShell(status: 0, saida: saidaVolume))])
        let completo = ControlesReais(executor: sh, brilho: BrilhoFalso(tela: 70, teclado: 30)).estado()
        XCTAssertEqual(completo, EstadoControles(volume: 40, mudo: false, brilho: 70, teclado: 30))
        let semBrilho = ControlesReais(executor: sh, brilho: BrilhoFalso(tela: nil, teclado: nil)).estado()
        XCTAssertEqual(semBrilho, EstadoControles(volume: 40, mudo: false, brilho: nil, teclado: nil))
        let semNada = ControlesReais(executor: ExecutorFalso([]), brilho: BrilhoIndisponivel()).estado()
        XCTAssertEqual(semNada, EstadoControles())
    }

    func testVolumeEMudoRodamOsaScript() {
        let sh = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: ""))])
        let c = ControlesReais(executor: sh, brilho: BrilhoIndisponivel())
        XCTAssertNil(c.definirVolume(55))
        XCTAssertNil(c.definirVolume(250))
        XCTAssertNil(c.definirMudo(true))
        XCTAssertNil(c.definirMudo(false))
        XCTAssertTrue(sh.comandos[0].contains("set volume output volume 55"))
        XCTAssertTrue(sh.comandos[1].contains("set volume output volume 100"), "limita em 100")
        XCTAssertTrue(sh.comandos[2].contains("set volume output muted true"))
        XCTAssertTrue(sh.comandos[3].contains("set volume output muted false"))
        let falha = ControlesReais(executor: ExecutorFalso([("osascript", SaidaShell(status: 1, saida: ""))]), brilho: BrilhoIndisponivel())
        XCTAssertNotNil(falha.definirVolume(10))
        XCTAssertNotNil(falha.definirMudo(true))
    }

    func testBrilhoEscreveSoSeOMacTemORecurso() {
        let b = BrilhoFalso(tela: 50, teclado: 20)
        let c = ControlesReais(executor: ExecutorFalso([]), brilho: b)
        XCTAssertNil(c.definirBrilho(80))
        XCTAssertNil(c.definirTeclado(-5))
        XCTAssertEqual(b.pedidos, ["tela 80", "teclado 0"])
        let sem = BrilhoFalso(tela: nil, teclado: nil)
        let c2 = ControlesReais(executor: ExecutorFalso([]), brilho: sem)
        XCTAssertNotNil(c2.definirBrilho(80))
        XCTAssertNotNil(c2.definirTeclado(80))
        XCTAssertTrue(sem.pedidos.isEmpty, "sem o recurso nada é escrito")
        let recusa = BrilhoFalso(tela: 50, teclado: 20)
        recusa.recusa = true
        XCTAssertNotNil(ControlesReais(executor: ExecutorFalso([]), brilho: recusa).definirBrilho(10))
    }

    // MARK: Rotas

    private func cenario() throws -> (Cenario, ControlesFalsos) {
        var c = try Cenario()
        let f = ControlesFalsos(c.registro)
        c.roteador.controles = f
        return (c, f)
    }

    func testRotaDoEstadoPrecisaDoCodigoEOmiteOQueNaoExiste() throws {
        var (c, f) = try cenario()
        XCTAssertEqual(c.pedir("GET", "/api/controles", codigo: nil).status, 401)
        let r = c.pedir("GET", "/api/controles")
        XCTAssertEqual(r.status, 200)
        let j = r.json as? [String: Any]
        XCTAssertEqual(j?["volume"] as? Int, 40)
        XCTAssertEqual(j?["mudo"] as? Bool, false)
        XCTAssertEqual(j?["brilho"] as? Int, 70)
        XCTAssertEqual(j?["teclado"] as? Int, 30)
        f.estadoAtual = EstadoControles(volume: 10, mudo: true, brilho: nil, teclado: nil)
        c.roteador.controles = f
        let j2 = c.pedir("GET", "/api/controles").json as? [String: Any]
        XCTAssertNil(j2?["brilho"], "o que o Mac não oferece não vai no corpo")
        XCTAssertNil(j2?["teclado"])
        XCTAssertEqual(c.pedir("POST", "/api/controles").status, 405)
    }

    func testRotasDeControleMandamOValor() throws {
        let (c, _) = try cenario()
        XCTAssertEqual(c.pedir("POST", "/api/controles/volume?v=55").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/controles/mudo?v=1").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/controles/mudo?v=0").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/controles/brilho?v=0").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/controles/teclado?v=100").status, 200)
        XCTAssertEqual(c.registro.todos, ["volume 55", "mudo true", "mudo false", "brilho 0", "teclado 100"])
    }

    func testRotasDeControleRecusamPedidoRuim() throws {
        let (c, _) = try cenario()
        for alvo in ["/api/controles/volume", "/api/controles/volume?v=101", "/api/controles/volume?v=-1", "/api/controles/brilho?v=abc",
                     "/api/controles/mudo?v=2", "/api/controles/mudo"] {
            XCTAssertEqual(c.pedir("POST", alvo).status, 400, alvo)
        }
        XCTAssertEqual(c.pedir("POST", "/api/controles/outro?v=1").status, 404)
        XCTAssertEqual(c.pedir("GET", "/api/controles/volume?v=1").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/controles/volume?v=1", codigo: nil).status, 401)
        XCTAssertTrue(c.registro.todos.isEmpty, "pedido recusado não mexe no Mac")
    }

    func testErroDoMacVira422ComTexto() throws {
        let (c, f) = try cenario()
        f.erro = "Este Mac não deixa mexer no brilho da tela."
        let r = c.pedir("POST", "/api/controles/brilho?v=10")
        XCTAssertEqual(r.status, 422)
        XCTAssertEqual(r.erroTexto, "Este Mac não deixa mexer no brilho da tela.")
    }

    func testSemProvedorAsRotasNaoExistem() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/controles").status, 404)
        XCTAssertEqual(c.pedir("POST", "/api/controles/volume?v=1").status, 404)
    }
}

/// Prova neste Mac, só leitura (nada é alterado): cada controle ou vem com valor válido ou vem nil, nunca quebra.
final class ControlesProvaRealTestes: XCTestCase {
    func testLeituraRealNuncaQuebraNemInventa() {
        #if os(macOS)
        let e = ControlesReais().estado()
        print("DECK-CONTROLES-REAL \(e)")
        for v in [e.volume, e.brilho, e.teclado].compactMap({ $0 }) { XCTAssertTrue((0...100).contains(v)) }
        XCTAssertEqual(e.volume == nil, e.mudo == nil, "volume e mudo vêm juntos")
        #endif
    }
}
