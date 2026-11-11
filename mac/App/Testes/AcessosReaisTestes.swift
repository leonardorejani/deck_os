import XCTest
@testable import Deck

/// Lê o estado de verdade dos acessos deste Mac, com os detectores do app (nenhum abre janela do macOS).
/// Não fixa o resultado, porque ele muda de Mac para Mac: confere que cada acesso que vale para qualquer
/// Mac aparece com uma situação e imprime a tabela para quem roda os testes ver.
final class AcessosReaisTestes: XCTestCase {
    func testLeAsSituacoesReaisSemAbrirJanela() {
        let defaults = UserDefaults(suiteName: "deck-testes-\(UUID().uuidString)")!
        let lidos = VerificadorVivo(defaults: defaults).acessos()
        for l in lidos { print("ACESSO-REAL \(l.acesso.nomeNaLista): \(l.situacao)\(l.detalhe.map { " (\($0))" } ?? "")") }
        let presentes = Set(lidos.map(\.acesso))
        for sempre in [AcessoMac.calendarios, .acessibilidade, .discoTotal, .bluetooth, .redeLocal] {
            XCTAssertTrue(presentes.contains(sempre), "\(sempre.nome) devia aparecer em qualquer Mac")
        }
    }

    func testAcessoNuncaPerguntadoNaoApareceComoRecusado() {
        // Um Deck que nunca pediu nada não pode dizer que algo foi recusado só porque não está liberado.
        let defaults = UserDefaults(suiteName: "deck-testes-\(UUID().uuidString)")!
        let lidos = VerificadorVivo(defaults: defaults).acessos()
        for l in lidos where l.acesso == .acessibilidade || l.acesso == .discoTotal {
            XCTAssertNotEqual(l.situacao, .recusado, "\(l.acesso.nome) nunca foi pedido pelo Deck")
        }
    }
}
