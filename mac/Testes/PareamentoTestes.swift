import XCTest
@testable import Nucleo

final class RelogioFalso: @unchecked Sendable {
    private let trava = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var agora: Date { trava.lock(); defer { trava.unlock() }; return t }
    func avancar(_ s: TimeInterval) { trava.lock(); t = t.addingTimeInterval(s); trava.unlock() }
}

final class PareamentoTestes: XCTestCase {
    private func novo(_ codigos: [String] = ["111111", "222222", "333333"]) -> (Pareamento, RelogioFalso) {
        let relogio = RelogioFalso()
        let fila = Registro()
        _ = fila
        let sorteio = SorteioFalso(codigos)
        return (Pareamento(agora: { relogio.agora }, sorteio: { sorteio.proximo() }), relogio)
    }

    func testCodigoSorteadoTem6Digitos() {
        for _ in 0..<200 {
            let c = Pareamento.sortear()
            XCTAssertEqual(c.count, 6)
            XCTAssertTrue(c.allSatisfy(\.isNumber))
        }
    }

    func testAceitaOCertoUmaVezSo() {
        let (p, _) = novo()
        XCTAssertEqual(p.gerar(), "111111")
        XCTAssertEqual(p.tentar("111111"), .aceito)
        XCTAssertEqual(p.tentar("111111"), .vencido, "uso único")
    }

    func testAvisaQuandoUmIphoneAcertaOCodigo() {
        let (p, _) = novo()
        let avisos = Registro()
        p.aoAceitar { avisos.anotar("aceito") }
        p.gerar()
        _ = p.tentar("999999")
        XCTAssertTrue(avisos.todos.isEmpty, "código errado não avisa")
        XCTAssertEqual(p.tentar("111111"), .aceito)
        XCTAssertEqual(avisos.todos, ["aceito"])
        _ = p.tentar("111111")
        XCTAssertEqual(avisos.todos, ["aceito"], "uso único: não avisa de novo")
    }

    func testSemCodigoGeradoNaoAceita() {
        let (p, _) = novo()
        XCTAssertEqual(p.tentar("111111"), .vencido)
    }

    func testVenceEmDezMinutos() {
        let (p, relogio) = novo()
        p.gerar()
        relogio.advance(599)
        XCTAssertEqual(p.tentar("000000"), .errado(restantes: 4))
        relogio.advance(2)
        XCTAssertEqual(p.tentar("111111"), .vencido)
    }

    func testCincoErrosBloqueiamInclusiveOCerto() {
        let (p, _) = novo()
        p.gerar()
        XCTAssertEqual(p.tentar("0"), .errado(restantes: 4))
        XCTAssertEqual(p.tentar("0"), .errado(restantes: 3))
        XCTAssertEqual(p.tentar("0"), .errado(restantes: 2))
        XCTAssertEqual(p.tentar("0"), .errado(restantes: 1))
        XCTAssertEqual(p.tentar("0"), .errado(restantes: 0))
        XCTAssertEqual(p.tentar("111111"), .bloqueado)
        XCTAssertEqual(p.tentar("0"), .bloqueado)
    }

    func testGerarDeNovoLiberaEInvalidaOAnterior() {
        let (p, _) = novo()
        p.gerar()
        for _ in 0..<5 { _ = p.tentar("0") }
        XCTAssertEqual(p.gerar(), "222222")
        XCTAssertEqual(p.tentar("111111"), .errado(restantes: 4), "o código antigo morreu")
        XCTAssertEqual(p.tentar("222222"), .aceito)
    }
}

private final class SorteioFalso: @unchecked Sendable {
    private let trava = NSLock()
    private var fila: [String]
    init(_ f: [String]) { fila = f }
    func proximo() -> String { trava.lock(); defer { trava.unlock() }; return fila.removeFirst() }
}

private extension RelogioFalso {
    func advance(_ s: TimeInterval) { avancar(s) }
}

final class PareamentoAtivoTestes: XCTestCase {
    private func novo() -> (Pareamento, RelogioFalso) {
        let relogio = RelogioFalso()
        let sorteio = SorteioFalso(["111111", "222222"])
        return (Pareamento(agora: { relogio.agora }, sorteio: { sorteio.proximo() }), relogio)
    }

    func testCodigoAtivoSomeQuandoVenceFoiUsadoOuEstouraOsErros() {
        let (p, relogio) = novo()
        XCTAssertNil(p.codigoAtivo, "sem gerar, não há código")
        p.gerar()
        XCTAssertEqual(p.codigoAtivo, "111111")
        relogio.avancar(Pareamento.validade + 1)
        XCTAssertNil(p.codigoAtivo, "venceu")

        let (q, _) = novo()
        q.gerar()
        XCTAssertEqual(q.tentar("111111"), .aceito)
        XCTAssertNil(q.codigoAtivo, "de uso único")

        let (r, _) = novo()
        r.gerar()
        for _ in 0..<Pareamento.maxErros { _ = r.tentar("000000") }
        XCTAssertNil(r.codigoAtivo, "bloqueado")
    }

    func testEncerrarNaoDeixaCodigoAtivo() {
        let (p, _) = novo()
        p.gerar()
        p.encerrar()
        XCTAssertNil(p.codigoAtivo)
        XCTAssertEqual(p.tentar("111111"), .vencido)
    }
}
