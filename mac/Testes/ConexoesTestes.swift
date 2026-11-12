import XCTest
@testable import Nucleo

/// Uma fonte de verdade para "o iPhone está conectado", e a espera que traz o Deck de volta à frente.
final class ConexoesTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRespostaBoaDoWifiSemRegistroCriaOIphoneConectado() {
        let i = Conexoes.aposRespostaDoWifi(atual: nil, caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertEqual(i, IphonePareado(nome: "iPhone", canal: .wifi, desde: t0, visto: t0))
    }

    func testRespostaRuimOuForaDaApiNaoMudaNada() {
        XCTAssertNil(Conexoes.aposRespostaDoWifi(atual: nil, caminho: "/api/estado", status: 401, agora: t0))
        XCTAssertNil(Conexoes.aposRespostaDoWifi(atual: nil, caminho: "/", status: 200, agora: t0))
        XCTAssertNil(Conexoes.aposRespostaDoWifi(atual: nil, caminho: "/api/parear", status: 200, agora: t0))
    }

    func testRespostaBoaAndaOVistoSoDepoisDeCincoSegundos() {
        let i = IphonePareado(nome: "iPhone", canal: .wifi, desde: t0, visto: t0)
        XCTAssertNil(Conexoes.aposRespostaDoWifi(atual: i, caminho: "/api/estado", status: 200, agora: t0.addingTimeInterval(2)))
        let novo = Conexoes.aposRespostaDoWifi(atual: i, caminho: "/api/estado", status: 200, agora: t0.addingTimeInterval(6))
        XCTAssertEqual(novo?.visto, t0.addingTimeInterval(6))
        XCTAssertEqual(novo?.desde, t0)
    }

    func testOIphoneLembradoDeOutraVezVoltaAoVivoNaPrimeiraResposta() {
        let lembrado = IphonePareado(nome: "iPhone", canal: .wifi, desde: t0, visto: .distantPast)
        XCTAssertFalse(lembrado.aoVivo(agora: t0))
        let novo = Conexoes.aposRespostaDoWifi(atual: lembrado, caminho: "/api/estado", status: 200, agora: t0)
        XCTAssertEqual(novo?.aoVivo(agora: t0), true)
    }

    func testAoVivoSoPorTrintaSegundos() {
        let i = IphonePareado(nome: "iPhone", canal: .cabo, visto: t0)
        XCTAssertTrue(i.aoVivo(agora: t0.addingTimeInterval(30)))
        XCTAssertFalse(i.aoVivo(agora: t0.addingTimeInterval(31)))
        XCTAssertTrue(IphonePareado(nome: "iPhone").aoVivo(agora: t0), "sem informação vale como ao vivo")
    }

    func testRespostaDoWifiNaoMexeNoAparelhoDoCabo() {
        let nativo = IphonePareado(nome: "iPhone", canal: .cabo, visto: t0)
        XCTAssertNil(Conexoes.aposRespostaDoWifi(atual: nativo, caminho: "/api/estado", status: 200, agora: t0.addingTimeInterval(60)))
    }

    func testMetodosNaOrdemDoSeletor() {
        XCTAssertEqual(MetodoDeConexao.allCases.map(\.rotulo), ["Cabo e Bluetooth", "PWA", "WhatsApp", "Spotify"])
    }

    // MARK: Trazer o Deck de volta

    @MainActor func testTrazOParaFrenteQuandoAPermissaoMuda() async {
        var valor = "recusado"
        var voltas = 0, trouxe = 0
        let mudou = await PrimeiroPlano.trazerQuandoMudar(inicial: "recusado", ler: { valor }, trazer: { trouxe += 1 },
                                                         intervalo: 1, limite: 10, dormir: { _ in voltas += 1; if voltas == 3 { valor = "liberado" } })
        XCTAssertTrue(mudou)
        XCTAssertEqual(trouxe, 1)
        XCTAssertEqual(voltas, 3)
    }

    @MainActor func testNaoTrazNadaSeAPermissaoNaoMuda() async {
        var trouxe = 0, voltas = 0
        let mudou = await PrimeiroPlano.trazerQuandoMudar(inicial: 1, ler: { 1 }, trazer: { trouxe += 1 }, intervalo: 1, limite: 5, dormir: { _ in voltas += 1 })
        XCTAssertFalse(mudou)
        XCTAssertEqual(trouxe, 0)
        XCTAssertEqual(voltas, 5)
    }

    @MainActor func testPedidoSoTrazODeckSeNenhumaVigiaFoiLigada() {
        var trouxe = 0
        PrimeiroPlano.aoTerminarPedido(vigiaLigada: true) { trouxe += 1 }
        XCTAssertEqual(trouxe, 0, "com os Ajustes abertos pelo pedido, quem traz o Deck é a mudança da permissão")
        PrimeiroPlano.aoTerminarPedido(vigiaLigada: false) { trouxe += 1 }
        XCTAssertEqual(trouxe, 1)
    }

    func testSoVigiaOQueDaParaReler() {
        XCTAssertFalse(PrimeiroPlano.deveVigiar(inicial: String?.none) { _ in true })
        XCTAssertFalse(PrimeiroPlano.deveVigiar(inicial: "semComoSaber") { $0 != "semComoSaber" })
        XCTAssertTrue(PrimeiroPlano.deveVigiar(inicial: "recusado") { $0 != "semComoSaber" })
    }

    // MARK: Aviso que leva a Conexões abre o método dele

    func testCadaAvisoAbreOMetodoOndeOCartaoAparece() {
        XCTAssertEqual(AvisoDeConexao.renovacao.metodo, .cabo)
        XCTAssertEqual(AvisoDeConexao.servidor.metodo, .pwa)
    }

    // MARK: Lista de apps relida

    func testListaDeAppsRelidaQuandoVelhaEnquantoNaoEstaLendo() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(RecargaDoCatalogo.precisa(ultimaLeitura: nil, agora: t, carregando: false))
        XCTAssertFalse(RecargaDoCatalogo.precisa(ultimaLeitura: nil, agora: t, carregando: true))
        XCTAssertFalse(RecargaDoCatalogo.precisa(ultimaLeitura: t, agora: t.addingTimeInterval(10), carregando: false))
        XCTAssertTrue(RecargaDoCatalogo.precisa(ultimaLeitura: t, agora: t.addingTimeInterval(31), carregando: false), "app instalado depois de o Deck abrir")
        XCTAssertFalse(RecargaDoCatalogo.precisa(ultimaLeitura: t, agora: t.addingTimeInterval(300), carregando: true))
    }

    // MARK: Ícone da tecla sem esperar a lista de apps

    func testIconeDaTeclaAchaOAppSemOCatalogoCarregado() {
        let existe: (String) -> Bool = { $0 == "/Applications/Spotify.app" }
        let pastas = ["/System/Applications", "/Applications"]
        XCTAssertEqual(IconeDeApp.caminho(valor: "Spotify", doCatalogo: nil, pastas: pastas, existe: existe), "/Applications/Spotify.app")
        XCTAssertEqual(IconeDeApp.caminho(valor: "Spotify", doCatalogo: "/x/Spotify.app", pastas: pastas, existe: existe), "/x/Spotify.app")
        XCTAssertNil(IconeDeApp.caminho(valor: "Nada", doCatalogo: nil, pastas: pastas, existe: existe))
        XCTAssertNil(IconeDeApp.caminho(valor: "", doCatalogo: nil, pastas: pastas, existe: { _ in true }))
    }
}
