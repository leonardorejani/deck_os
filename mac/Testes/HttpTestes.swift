import XCTest
@testable import Nucleo

final class HttpTestes: XCTestCase {
    func testLeGetComQuery() throws {
        let bruto = Data("GET /api/estado?codigo=ab%20c&x=1+2 HTTP/1.1\r\nHost: mac.local\r\n\r\n".utf8)
        guard case .ok(let r) = Http.ler(bruto) else { return XCTFail("esperava requisição completa") }
        XCTAssertEqual(r.metodo, "GET")
        XCTAssertEqual(r.caminho, "/api/estado")
        XCTAssertEqual(r.query, ["codigo": "ab c", "x": "1 2"])
        XCTAssertEqual(r.cabecalhos["host"], "mac.local")
    }

    func testEsperaOCorpoInteiro() {
        let cabecalho = "POST /api/botao/a HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
        guard case .incompleto = Http.ler(Data((cabecalho + "ab").utf8)) else { return XCTFail("esperava incompleto") }
        guard case .ok(let r) = Http.ler(Data((cabecalho + "abcde").utf8)) else { return XCTFail("esperava ok") }
        XCTAssertEqual(r.corpo, Data("abcde".utf8))
    }

    func testRecusaTamanhoInvalido() {
        let bruto = Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        guard case .invalido = Http.ler(bruto) else { return XCTFail("esperava inválido") }
    }

    func testRespostaETipo() {
        let saida = String(decoding: Http.resposta(status: 404, tipo: "text/plain", corpo: Data("x".utf8)), as: UTF8.self)
        XCTAssertTrue(saida.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(saida.contains("Content-Length: 1\r\n"))
        XCTAssertTrue(saida.hasSuffix("\r\n\r\nx"))
        XCTAssertEqual(Http.tipoConteudo("/painel/deck.css"), "text/css; charset=utf-8")
        XCTAssertEqual(Http.tipoConteudo("/x.bin"), "application/octet-stream")
    }
}
