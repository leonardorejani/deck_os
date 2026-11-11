import XCTest
@testable import Nucleo

final class SeloTestes: XCTestCase {
    func testLeNumeroDoSelo() {
        XCTAssertEqual(Selo.ler(#""StatusLabel"={ "label"="3" }"#), "3")
    }

    func testSemSeloDevolveNil() {
        XCTAssertNil(Selo.ler(#""StatusLabel"={ "label"="" }"#))
        XCTAssertNil(Selo.ler(""))
    }
}
