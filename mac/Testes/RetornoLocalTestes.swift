import XCTest
@testable import Nucleo
#if canImport(Network)
import Network

/// O redirecionamento local de verdade: abre a porta no loopback e o "navegador" é um pedido HTTP comum.
final class RetornoLocalTestes: XCTestCase {
    func testInterpretaOCodigoEOEstadoDoRetorno() {
        func req(_ alvo: String, _ m: String = "GET") -> HttpRequisicao {
            let (c, q) = Http.separarAlvo(alvo)
            return HttpRequisicao(metodo: m, caminho: c, query: q, cabecalhos: [:], corpo: Data())
        }
        XCTAssertEqual(RetornoLocal.interpretar(req("/retorno?code=ABC&state=XYZ")), RetornoLogin(codigo: "ABC", estado: "XYZ", erro: nil))
        XCTAssertEqual(RetornoLocal.interpretar(req("/retorno?error=access_denied&state=XYZ")), RetornoLogin(codigo: nil, estado: "XYZ", erro: "access_denied"))
        XCTAssertNil(RetornoLocal.interpretar(req("/favicon.ico")))
        XCTAssertNil(RetornoLocal.interpretar(req("/retorno?code=A", "POST")))
    }

    func testEnderecoDoRedirecionamentoUsaIpDeLoopbackNaoLocalhost() {
        XCTAssertEqual(RetornoLocal.endereco(porta: 4778), "http://127.0.0.1:4778/retorno")
        XCTAssertEqual(RetornoLocal.portaPadrao, 4778)
    }

    private func buscar(_ url: String) -> (Int, String)? {
        let sem = DispatchSemaphore(value: 0)
        final class Caixa: @unchecked Sendable { var r: (Int, String)? }
        let caixa = Caixa()
        URLSession.shared.dataTask(with: URLRequest(url: URL(string: url)!, timeoutInterval: 5)) { d, resp, _ in
            if let h = resp as? HTTPURLResponse { caixa.r = (h.statusCode, String(decoding: d ?? Data(), as: UTF8.self)) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 6)
        return caixa.r
    }

    final class Recebidos: @unchecked Sendable {
        private let t = NSLock(); private var l: [RetornoLogin] = []
        func somar(_ r: RetornoLogin) { t.lock(); l.append(r); t.unlock() }
        var todos: [RetornoLogin] { t.lock(); defer { t.unlock() }; return l }
    }

    func testPortaRealRecebeORetornoEIgnoraOResto() throws {
        let recebidos = Recebidos()
        let servidor = RetornoLocal(porta: 0)
        let porta = try servidor.iniciar { recebidos.somar($0) }
        defer { servidor.parar() }
        XCTAssertGreaterThan(porta, 0)

        let favicon = try XCTUnwrap(buscar("http://127.0.0.1:\(porta)/favicon.ico"))
        XCTAssertEqual(favicon.0, 404)
        XCTAssertEqual(recebidos.todos.count, 0)

        let ok = try XCTUnwrap(buscar("http://127.0.0.1:\(porta)/retorno?code=COD%2B1&state=EST"))
        XCTAssertEqual(ok.0, 200)
        XCTAssertTrue(ok.1.contains("Pode fechar esta aba"))
        XCTAssertEqual(recebidos.todos, [RetornoLogin(codigo: "COD+1", estado: "EST", erro: nil)])
    }

    func testPortaOcupadaDaErroComTextoUtil() throws {
        let a = RetornoLocal(porta: 0)
        let porta = try a.iniciar { _ in }
        defer { a.parar() }
        let b = RetornoLocal(porta: porta)
        XCTAssertThrowsError(try b.iniciar { _ in }) { e in
            XCTAssertTrue((e as? ErroServidor)?.description.contains("porta") ?? false)
        }
    }

    func testDepoisDeFecharAPortaNaoAtendeMais() throws {
        let s = RetornoLocal(porta: 0)
        let porta = try s.iniciar { _ in }
        s.parar()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertNil(buscar("http://127.0.0.1:\(porta)/retorno?code=A&state=B"))
    }
}
#endif
