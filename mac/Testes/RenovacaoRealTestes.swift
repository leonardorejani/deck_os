import XCTest
@testable import Nucleo

/// Prova contra este Mac, só leitura: acha o iPhone (cabo ou Wi-Fi), vê se está desbloqueado e calcula a próxima renovação
/// pela data da última instalação. Não compila, não instala e não escreve nada. Só roda com DECK_PROVA_REAL=1.
///   DECK_PROVA_REAL=1 swift test --package-path mac --filter RenovacaoRealTestes
final class RenovacaoRealTestes: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DECK_PROVA_REAL"] == "1", "prova real desligada")
    }

    func testAcheOIphoneEAProximaDataSemReinstalar() async {
        let motor = MotorDeRenovacao(executor: ExecutorDeProcesso(), relogio: { Date() }, pasta: { nil })
        let t0 = Date()
        let sonda = await motor.sondar()
        print("iphone: \(sonda.id == nil ? "nenhum ao alcance" : "achado"), caminho: \(sonda.via?.texto ?? "desconhecido"), situacao: \(sonda.situacao) (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
        let instalacao = ArquivoDeInstalacao.ler()
        if let em = instalacao.instaladoEm {
            let proxima = AgendaDeRenovacao.proxima(depoisDe: em)
            let f = ISO8601DateFormatter()
            print("ultima instalacao: \(f.string(from: em)), proxima renovacao: \(f.string(from: proxima)), devida agora: \(AgendaDeRenovacao.devida(renovadoEm: em, agora: Date()))")
        } else {
            print("arquivo de instalacao sem data")
        }
        XCTAssertNotNil(sonda.id, "iPhone fora do alcance neste momento")
    }
}
