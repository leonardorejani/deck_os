import XCTest
#if canImport(Network)
import Network
#endif
@testable import Nucleo

final class VarianteTestes: XCTestCase {
    private func pastaTemp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("deck-variante-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testNoTesteEODeckDeVerdade() {
        XCTAssertEqual(Variante.atual, .deck)
        XCTAssertNil(Variante.deck.portaFixa)
        XCTAssertTrue(Variante.deck.ligaIphone)
        XCTAssertFalse(Variante.deck.somenteLocal)
    }

    func testBancadaTemPortaPastaELogProprios() {
        let casa = URL(fileURLWithPath: "/tmp/casa")
        XCTAssertEqual(Variante.bancada.portaFixa, 4791)
        XCTAssertNotEqual(Variante.bancada.portaFixa, 4790)
        XCTAssertEqual(Variante.bancada.pastaDeDados(casa: casa).lastPathComponent, "Deck Bancada")
        XCTAssertEqual(Variante.bancada.pastaDeLog(casa: casa).lastPathComponent, "Deck Bancada")
        XCTAssertNotEqual(Variante.bancada.pastaDeDados(casa: casa), Variante.deck.pastaDeDados(casa: casa))
        XCTAssertEqual(Variante.deck.pastaDeDados(casa: casa).path, "/tmp/casa/Library/Application Support/Deck")
        XCTAssertEqual(Variante.deck.pastaDeLog(casa: casa).path, "/tmp/casa/Library/Logs/Deck")
    }

    func testTituloDoMenuDizTesteSoNaBancada() {
        XCTAssertEqual(Variante.deck.tituloDoMenu, "Deck")
        XCTAssertEqual(Variante.bancada.tituloDoMenu, "Deck Bancada (teste)")
    }

    func testBancadaNaoTemIphoneENaoApareceNaRede() {
        XCTAssertFalse(Variante.bancada.ligaIphone)
        XCTAssertTrue(Variante.bancada.somenteLocal)
    }

    func testBancadaNaoPedeBluetoothNemRedeLocalAoMacOS() {
        XCTAssertFalse(Variante.bancada.pedeBluetoothERedeLocal)
        XCTAssertTrue(Variante.deck.pedeBluetoothERedeLocal)
    }

    func testChaveiroDaBancadaNuncaCasaComODoDeck() {
        for nome in ["spotify", "token-claude"] {
            XCTAssertEqual(Variante.deck.servicoDoChaveiro(nome), "com.leonardorejani.deck.\(nome)")
            XCTAssertNotEqual(Variante.bancada.servicoDoChaveiro(nome), Variante.deck.servicoDoChaveiro(nome))
            XCTAssertEqual(Variante.bancada.servicoDoChaveiro(nome), "com.leonardorejani.deck.bancada.\(nome)")
            XCTAssertFalse(Variante.bancada.servicoDoChaveiro(nome).hasPrefix(AmbienteDeTeste.prefixoDeServicoDeTeste))
        }
    }

#if canImport(Network)
    func testServidorDaBancadaSoEscutaNoLoopback() {
        let tls = NWProtocolTLS.Options()
        XCTAssertEqual(ServidorHttps.parametros(tls: tls, somenteLocal: true).requiredInterfaceType, .loopback)
        XCTAssertNotEqual(ServidorHttps.parametros(tls: tls, somenteLocal: false).requiredInterfaceType, .loopback)
    }
#endif

    func testPrimeiraAberturaCopiaAConfigComAPortaDaBancada() throws {
        let pasta = pastaTemp()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appendingPathComponent("real/config.json")
        let destino = pasta.appendingPathComponent("bancada/config.json")
        try ArmazemConfig(url: origem, nomeMac: "Mac").gravar(configDeTeste())
        let antes = try Data(contentsOf: origem)

        XCTAssertEqual(PrimeiraAberturaDaBancada.preparar(origem: origem, destino: destino), .copiou)
        let copia = try ArmazemConfig(url: destino, nomeMac: "Mac").ler()
        XCTAssertEqual(copia.porta, 4791)
        XCTAssertEqual(copia.perfis.first?.teclas.count, 2)
        XCTAssertEqual(try Data(contentsOf: origem), antes, "a config do Deck real não pode mudar")
        let perm = try FileManager.default.attributesOfItem(atPath: destino.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perm?.intValue, 0o600)
    }

    func testPrimeiraAberturaNaoSobrescreveEOkSemOrigem() throws {
        let pasta = pastaTemp()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appendingPathComponent("real/config.json")
        let destino = pasta.appendingPathComponent("bancada/config.json")
        XCTAssertEqual(PrimeiraAberturaDaBancada.preparar(origem: origem, destino: destino), .semOrigem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destino.path))

        try ArmazemConfig(url: origem, nomeMac: "Mac").gravar(configDeTeste())
        try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"meu\":1}".utf8).write(to: destino)
        XCTAssertEqual(PrimeiraAberturaDaBancada.preparar(origem: origem, destino: destino), .jaTinhaConfig)
        XCTAssertEqual(try Data(contentsOf: destino), Data("{\"meu\":1}".utf8))
    }

    func testOrigemPadraoEAConfigDoDeckReal() {
        XCTAssertTrue(PrimeiraAberturaDaBancada.origemPadrao.path.hasSuffix("Library/Application Support/Deck/config.json"))
    }
}
