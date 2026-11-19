import XCTest
@testable import Nucleo

/// Quem instalou o app do iPhone (Deck ou outro app) e quando o cartão de renovação aparece.
final class InstalacaoDoAppTestes: XCTestCase {
    private let pacote = MotorDeRenovacao.idDoAppDoIphone
    private let equipe = "EQUIPE0001"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func detectar(_ i: InstalacaoDoApp?, instaladoEm: Date? = nil, equipeDoDeck: String? = "EQUIPE0001") -> OrigemDaInstalacao {
        DeteccaoDaInstalacao.detectar(informada: i, pacoteDoDeck: pacote, equipeDoDeck: equipeDoDeck, instaladoEm: instaladoEm ?? t0)
    }

    // MARK: Detecção

    func testSemInformacaoDoIphoneSegueComoSempre() {
        XCTAssertEqual(detectar(nil), .desconhecida)
        XCTAssertEqual(detectar(InstalacaoDoApp()), .desconhecida)
    }

    func testInstalacaoDoDeckTemMesmoPacoteEquipeEVencimentoDeSeteDias() {
        let i = InstalacaoDoApp(versao: "1.2 (1)", bundleId: pacote, equipe: equipe, venceEm: t0.addingTimeInterval(7 * 86_400 - 600))
        XCTAssertEqual(detectar(i), .deck)
    }

    func testPacoteDiferenteEExterna() {
        // o SideStore costuma acrescentar o id da equipe ao pacote
        let i = InstalacaoDoApp(bundleId: pacote + ".EQUIPE0001", equipe: equipe, venceEm: t0.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(detectar(i), .externa(.outroPacote))
    }

    func testEquipeDiferenteEExterna() {
        let i = InstalacaoDoApp(bundleId: pacote, equipe: "OUTRAEQUIPE", venceEm: t0.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(detectar(i), .externa(.outraEquipe))
    }

    func testEquipeDoDeckDesconhecidaNaoAcusaEquipe() {
        let i = InstalacaoDoApp(bundleId: pacote, equipe: "QUALQUER", venceEm: t0.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(detectar(i, equipeDoDeck: nil), .deck)
    }

    func testVencimentoBemDepoisDoQueAInstalacaoDoDeckDariaEExterna() {
        let i = InstalacaoDoApp(bundleId: pacote, equipe: equipe, venceEm: t0.addingTimeInterval(11 * 86_400))
        XCTAssertEqual(detectar(i), .externa(.vencimentoNaoBate))
    }

    func testVencimentoMaisCedoQueOEsperadoContinuaSendoDoDeck() {
        // perfil velho reaproveitado numa instalação do Deck: o Deck é quem precisa renovar
        let i = InstalacaoDoApp(bundleId: pacote, equipe: equipe, venceEm: t0.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(detectar(i), .deck)
    }

    func testSoOVencimentoSemInstalacaoDoDeckConhecidaNaoDecide() {
        let i = InstalacaoDoApp(venceEm: t0.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(DeteccaoDaInstalacao.detectar(informada: i, pacoteDoDeck: pacote, equipeDoDeck: nil, instaladoEm: nil), .deck)
    }

    func testLeEquipeDoProjectYml() {
        XCTAssertEqual(DeteccaoDaInstalacao.equipe(doProjeto: "settings:\n  base:\n    DEVELOPMENT_TEAM: ABC123XYZ\n    X: 1\n"), "ABC123XYZ")
        XCTAssertEqual(DeteccaoDaInstalacao.equipe(doProjeto: "    DEVELOPMENT_TEAM: \"ABC123XYZ\"\n"), "ABC123XYZ")
        XCTAssertNil(DeteccaoDaInstalacao.equipe(doProjeto: "name: Deck\n"))
        XCTAssertNil(DeteccaoDaInstalacao.equipe(doProjeto: "DEVELOPMENT_TEAM:\n"))
    }

    // MARK: Corpo da rota

    func testDecodificaOCorpoComDataIso() {
        let corpo = Data(#"{"versao":"1.2 (1)","bundleId":"a.b","equipe":"T","venceEm":"2027-01-10T12:00:00Z"}"#.utf8)
        let i = InstalacaoDoApp.decodificar(corpo)
        XCTAssertEqual(i?.versao, "1.2 (1)")
        XCTAssertEqual(i?.venceEm, ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z"))
        XCTAssertNil(InstalacaoDoApp.decodificar(Data("lixo".utf8)))
        XCTAssertNil(InstalacaoDoApp.decodificar(Data(#"{"bundleId":"\#(String(repeating: "x", count: 101))"}"#.utf8)))
    }

    // MARK: O cartão

    func testDeckComRenovacaoApertandoMostraOCartaoDeFalha() {
        let vence = t0.addingTimeInterval(86_400)
        XCTAssertEqual(CartaoDaRenovacao.para(origem: .deck, venceEmDoDeck: vence, venceReal: nil, agora: t0), .falhou(venceEm: vence))
        XCTAssertEqual(CartaoDaRenovacao.para(origem: .desconhecida, venceEmDoDeck: vence, venceReal: nil, agora: t0), .falhou(venceEm: vence))
        XCTAssertNil(CartaoDaRenovacao.para(origem: .deck, venceEmDoDeck: nil, venceReal: vence, agora: t0), "renovação em dia: nenhum cartão, mesmo com o vencimento perto")
    }

    func testExternaNuncaMostraOCartaoDeRenovacaoFalha() {
        let origem = OrigemDaInstalacao.externa(.outroPacote)
        let longe = t0.addingTimeInterval(5 * 86_400)
        XCTAssertNil(CartaoDaRenovacao.para(origem: origem, venceEmDoDeck: t0.addingTimeInterval(86_400), venceReal: longe, agora: t0),
                     "a conta do Deck dizia que apertava, mas o vencimento real está longe e quem renova é o outro app")
    }

    func testExternaComVencimentoPertoViraAvisoDoOutroApp() {
        let origem = OrigemDaInstalacao.externa(.outroPacote)
        let perto = t0.addingTimeInterval(86_400)
        XCTAssertEqual(CartaoDaRenovacao.para(origem: origem, venceEmDoDeck: nil, venceReal: perto, agora: t0), .externa(venceEm: perto))
        let limite = t0.addingTimeInterval(CartaoDaRenovacao.antecedenciaDaExterna)
        XCTAssertNil(CartaoDaRenovacao.para(origem: origem, venceEmDoDeck: nil, venceReal: limite, agora: t0), "2 dias cravados ainda não avisa")
        XCTAssertEqual(CartaoDaRenovacao.para(origem: origem, venceEmDoDeck: nil, venceReal: t0.addingTimeInterval(-60), agora: t0),
                       .externa(venceEm: t0.addingTimeInterval(-60)), "já venceu: continua avisando")
        XCTAssertNil(CartaoDaRenovacao.para(origem: origem, venceEmDoDeck: nil, venceReal: nil, agora: t0))
    }

    // MARK: A rota

    func testRotaGuardaAInstalacaoEExigeOCodigo() throws {
        let url = try pastaTemporaria().appendingPathComponent("config.json")
        let armazem = try ArmazemEmDisco(ArmazemConfig(url: url, nomeMac: "Mac de teste"))
        let codigo = armazem.ler().codigoAcesso
        let guardado = Guardado()
        var r = Ligacao.roteador(armazem: armazem, pareamento: Pareamento(), pagina: ArquivosPagina(raiz: try pastaTemporaria()), executor: ExecutorFalso([]))
        func pedir(_ m: String, corpo: String, codigo: String? = codigo) -> RespostaRota {
            r.responder(HttpRequisicao(metodo: m, caminho: "/api/app/instalacao", query: [:], cabecalhos: codigo.map { ["x-deck-codigo": $0] } ?? [:], corpo: Data(corpo.utf8)))
        }
        let json = #"{"versao":"1.2 (1)","bundleId":"a.b","venceEm":"2027-01-10T12:00:00Z"}"#
        XCTAssertEqual(pedir("POST", corpo: json).status, 404, "sem o ouvinte a rota não existe")
        r.aoInformarInstalacao = { guardado.valor = $0 }
        XCTAssertEqual(pedir("POST", corpo: json, codigo: nil).status, 401)
        XCTAssertNil(guardado.valor)
        XCTAssertEqual(pedir("GET", corpo: "").status, 405)
        XCTAssertEqual(pedir("POST", corpo: "lixo").status, 400)
        XCTAssertEqual(pedir("POST", corpo: json).status, 200)
        XCTAssertEqual(guardado.valor?.bundleId, "a.b")
        XCTAssertEqual(guardado.valor?.versao, "1.2 (1)")
    }

    private final class Guardado: @unchecked Sendable { var valor: InstalacaoDoApp? }
}
