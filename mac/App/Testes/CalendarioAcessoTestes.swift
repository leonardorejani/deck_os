import XCTest
@testable import Deck

/// No macOS 14 em diante o EventKit só pergunta (e só libera a leitura) com o texto de acesso total
/// no Info.plist. Só com o texto antigo, o pedido falha em silêncio e a Agenda fica sem permissão.
final class CalendarioAcessoTestes: XCTestCase {
    func testInfoPlistTemOTextoDeAcessoTotalAoCalendario() {
        let info = Bundle(for: ModeloApp.self).infoDictionary ?? [:]
        let texto = info["NSCalendarsFullAccessUsageDescription"] as? String
        XCTAssertFalse((texto ?? "").isEmpty, "falta NSCalendarsFullAccessUsageDescription no Info.plist do Deck")
    }

    func testInfoPlistMantemOTextoAntigoParaMacOS13() {
        let info = Bundle(for: ModeloApp.self).infoDictionary ?? [:]
        XCTAssertFalse(((info["NSCalendarsUsageDescription"] as? String) ?? "").isEmpty)
    }
}
