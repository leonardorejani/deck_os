import XCTest
@testable import Nucleo

final class FontesAgendaTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)   // 2026-11-11T12:26:40Z

    func evento(_ titulo: String, inicio: TimeInterval, duracao: TimeInterval = 3600, diaTodo: Bool = false, local: String? = nil) -> EventoBruto {
        EventoBruto(titulo: titulo, inicio: agora.addingTimeInterval(inicio), fim: agora.addingTimeInterval(inicio + duracao),
                    diaTodo: diaTodo, calendario: "Trabalho", cor: (r: 1, g: 0.5, b: 0), local: local)
    }

    func testConverteEventoComCorEmHexELocalVazioViraNil() {
        let e = Agenda.converter(evento("Ensaio", inicio: 0, local: "  "), fuso: utc)
        XCTAssertEqual(e, Evento(titulo: "Ensaio", inicio: "2026-11-11T12:26:40Z", diaTodo: false,
                                 calendario: "Trabalho", cor: "#ff8000", local: nil, fim: "2026-11-11T13:26:40Z"))
        XCTAssertEqual(Agenda.converter(evento("Culto", inicio: 0, local: " Igreja "), fuso: utc).local, "Igreja")
    }

    func testFusoDoMacApareceNoInicio() {
        let saoPaulo = TimeZone(secondsFromGMT: -3 * 3600)!
        XCTAssertEqual(Agenda.converter(evento("x", inicio: 0), fuso: saoPaulo).inicio, "2026-11-11T09:26:40-03:00")
    }

    func testProximoPulaOQueJaTerminouEPegaOMaisCedo() {
        let lista = [evento("terminou", inicio: -7200), evento("depois", inicio: 7200), evento("em andamento", inicio: -600), evento("mais tarde", inicio: 86_400)]
        XCTAssertEqual(Agenda.proximo(lista, agora: agora)?.titulo, "em andamento")
        XCTAssertNil(Agenda.proximo([evento("terminou", inicio: -7200)], agora: agora))
    }

    func testSemPermissaoVirResumoComFalse() {
        let r = Agenda.resumo(permissao: false, eventos: [evento("x", inicio: 10)], agora: agora, fuso: utc)
        XCTAssertEqual(r, ResumoAgenda(permissao: false, proximo: nil))
    }

    func testComPermissaoEAgendaVazia() {
        XCTAssertEqual(Agenda.resumo(permissao: true, eventos: [], agora: agora), ResumoAgenda(permissao: true, proximo: nil))
    }

    func testCorForaDaFaixaFicaPresa() {
        XCTAssertEqual(Cor.hex(r: 1.2, g: -0.1, b: 0), "#ff0000")
        XCTAssertEqual(Cor.hex(1, 2, 3), "#010203")
    }

    func testLembreteComPrazoViraItemDoDiaEEntraJuntoDoEvento() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let comHora = Agenda.lembrete(titulo: "Pagar boleto", prazo: DateComponents(year: 2026, month: 11, day: 12, hour: 15, minute: 30),
                                      lista: "Lembretes", cor: (r: 0, g: 0, b: 1), calendario: cal)
        XCTAssertEqual(comHora?.inicio, Date(timeIntervalSince1970: 1_794_497_400))
        XCTAssertEqual(comHora?.diaTodo, false)
        let diaTodo = Agenda.lembrete(titulo: "Ligar", prazo: DateComponents(year: 2026, month: 11, day: 12), lista: "Casa", cor: (r: 0, g: 0, b: 1), calendario: cal)
        XCTAssertEqual(diaTodo?.diaTodo, true)
        XCTAssertNil(Agenda.lembrete(titulo: "Sem dia", prazo: DateComponents(hour: 9), lista: "Casa", cor: (r: 0, g: 0, b: 1), calendario: cal))
        let junto = Agenda.juntar([evento("Reuniao", inicio: 7 * 86_400)], [comHora!, diaTodo!].compactMap { $0 })
        XCTAssertEqual(junto.map(\.titulo), ["Ligar", "Pagar boleto", "Reuniao"])
    }
}
