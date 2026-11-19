import XCTest
@testable import Nucleo

/// A tecla "Mudar foco" de ponta a ponta pelo roteador (o que o iPhone faz): toque, estado, toque, estado.
final class ToggleRotaTestes: XCTestCase {
    func testToqueLigaAcendeEOSegundoToqueDesligaEApaga() throws {
        let url = try pastaTemporaria().appendingPathComponent("config.json")
        let armazem = try ArmazemEmDisco(ArmazemConfig(url: url, nomeMac: "Mac de teste"))
        var cfg = armazem.ler()
        cfg.perfis[0].teclas = [Tecla(id: "toggle-foco", nome: "Mudar foco", tipo: "comando", valor: "foco-jogo-x", estado: nil, icone: "svg:tela", desligar: "foco-trabalho-x")]
        cfg.perfilAtivo = cfg.perfis[0].id
        XCTAssertNil(armazem.aplicar(cfg))
        let ex = ExecutorFalso([("foco-", SaidaShell(status: 0, saida: ""))])
        let r = Ligacao.roteador(armazem: armazem, pareamento: Pareamento(), pagina: ArquivosPagina(raiz: try pastaTemporaria()), executor: ex)
        func pedir(_ m: String, _ c: String) -> RespostaRota {
            r.responder(HttpRequisicao(metodo: m, caminho: c, query: [:], cabecalhos: ["x-deck-codigo": cfg.codigoAcesso], corpo: Data()))
        }
        func acesas() throws -> [String] {
            let resp = pedir("GET", "/api/estado")
            XCTAssertEqual(resp.status, 200)
            return try JSONDecoder().decode(Estado.self, from: resp.corpo).acesas
        }
        XCTAssertEqual(try acesas(), [])
        XCTAssertEqual(pedir("POST", "/api/botao/toggle-foco").status, 200)
        XCTAssertTrue(ex.comandos.last!.contains("foco-jogo-x"))
        XCTAssertEqual(try acesas(), ["toggle-foco"], "ligou: a tecla acende")
        XCTAssertEqual(pedir("POST", "/api/botao/toggle-foco").status, 200)
        XCTAssertTrue(ex.comandos.last!.contains("foco-trabalho-x"), "o segundo toque roda o comando para desligar")
        XCTAssertEqual(try acesas(), [], "desligou: a tecla apaga")
        XCTAssertEqual(pedir("POST", "/api/botao/toggle-foco").status, 200)
        XCTAssertTrue(ex.comandos.last!.contains("foco-jogo-x"))
    }
}
