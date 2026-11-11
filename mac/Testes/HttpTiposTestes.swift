import XCTest
@testable import Nucleo

final class HttpTiposTestes: XCTestCase {
    func testTiposDaPagina() {
        XCTAssertEqual(Http.tipoConteudo("/app.webmanifest"), "application/json; charset=utf-8")
        XCTAssertEqual(Http.tipoConteudo("/favicon.ico"), "image/x-icon")
        XCTAssertEqual(Http.tipoConteudo("/f.woff2"), "font/woff2")
        XCTAssertEqual(Http.tipoConteudo("/capa.jpg"), "image/jpeg")
        XCTAssertEqual(Http.tipoConteudo("/capa.JPEG"), "image/jpeg")
        XCTAssertEqual(Http.tipoConteudo("/x.bin"), "application/octet-stream")
    }

    func testTextosDeStatusNovos() {
        XCTAssertEqual(Http.textoStatus(422), "Unprocessable Entity")
        XCTAssertEqual(Http.textoStatus(429), "Too Many Requests")
        XCTAssertEqual(Http.textoStatus(500), "Internal Server Error")
    }
}
