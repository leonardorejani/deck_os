import XCTest
@testable import Nucleo

/// Pasta de apps de mentira: cada .app tem só o Info.plist, que é o que o Deck lê.
private struct PastaDeApps {
    let raiz: URL

    init() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("deck-apps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    }

    @discardableResult
    func app(_ caminho: String, info: [String: Any]?) throws -> String {
        let pacote = raiz.appendingPathComponent(caminho)
        try FileManager.default.createDirectory(at: pacote.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        if let info {
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: pacote.appendingPathComponent("Contents/Info.plist"))
        }
        return pacote.path
    }

    var descobridor: DescobridorDeApps {
        DescobridorDeApps(pastas: [raiz.appendingPathComponent("Apps").path, raiz.appendingPathComponent("Casa").path],
                          extras: [raiz.appendingPathComponent("Sistema/Finder.app").path],
                          nomeExibido: { DescobridorDeApps.semExtensao($0) })
    }
}

final class AppsTestes: XCTestCase {
    func testListaOsAppsDasPastasENiveisAbaixo() throws {
        let p = try PastaDeApps()
        try p.app("Apps/Calculator.app", info: ["CFBundleIdentifier": "com.apple.calculator"])
        try p.app("Apps/Utilities/Terminal.app", info: ["CFBundleIdentifier": "com.apple.Terminal",
                                                       "CFBundleDocumentTypes": [["CFBundleTypeName": "Shell"]]])
        try p.app("Casa/Google Chrome.app", info: ["CFBundleIdentifier": "com.google.Chrome",
                                                  "CFBundleURLTypes": [["CFBundleURLSchemes": ["HTTP", "https"]]]])
        try p.app("Sistema/Finder.app", info: ["CFBundleIdentifier": "com.apple.finder"])
        let lista = p.descobridor.listar()

        XCTAssertEqual(lista.map(\.app.valor), ["Calculator", "Finder", "Google Chrome", "Terminal"])
        let chrome = try XCTUnwrap(lista.first { $0.app.bundle == "com.google.Chrome" })
        XCTAssertTrue(chrome.app.navegador)
        XCTAssertEqual(chrome.caminho, p.raiz.path + "/Casa/Google Chrome.app")
        XCTAssertFalse(try XCTUnwrap(lista.first { $0.app.valor == "Calculator" }).app.navegador)
        XCTAssertTrue(try XCTUnwrap(lista.first { $0.app.valor == "Terminal" }).abreArquivos)
        XCTAssertFalse(try XCTUnwrap(lista.first { $0.app.valor == "Calculator" }).abreArquivos)
        // O Finder abre pasta mesmo sem declarar documentos.
        XCTAssertTrue(try XCTUnwrap(lista.first { $0.app.valor == "Finder" }).abreArquivos)
    }

    func testIgnoraAppSemPlistEmSegundoPlanoOcultoERepetido() throws {
        let p = try PastaDeApps()
        try p.app("Apps/SemPlist.app", info: nil)
        try p.app("Apps/SemId.app", info: ["CFBundleName": "x"])
        try p.app("Apps/Servico.app", info: ["CFBundleIdentifier": "com.x.servico", "LSBackgroundOnly": true])
        try p.app("Apps/.Escondido.app", info: ["CFBundleIdentifier": "com.x.escondido"])
        try p.app("Apps/Barra.app", info: ["CFBundleIdentifier": "com.x.barra", "LSUIElement": true])
        try p.app("Apps/Igual.app", info: ["CFBundleIdentifier": "com.x.igual"])
        try p.app("Casa/Igual copia.app", info: ["CFBundleIdentifier": "com.x.igual"])
        XCTAssertEqual(p.descobridor.listar().map(\.app.bundle), ["com.x.barra", "com.x.igual"])
    }

    func testPastaQueNaoExisteNaoQuebra() {
        let d = DescobridorDeApps(pastas: ["/nao/existe/mesmo"], extras: ["/nao/existe.app"], nomeExibido: { $0 })
        XCTAssertEqual(d.listar(), [])
    }

    func testNomeExibidoVemDoSistemaEOValorEODoArquivo() throws {
        let p = try PastaDeApps()
        try p.app("Apps/Calculator.app", info: ["CFBundleIdentifier": "com.apple.calculator"])
        let d = DescobridorDeApps(pastas: [p.raiz.appendingPathComponent("Apps").path], extras: [],
                                  nomeExibido: { _ in "Calculadora" })
        let a = try XCTUnwrap(d.listar().first)
        XCTAssertEqual(a.app, AppInstalado(nome: "Calculadora", valor: "Calculator", bundle: "com.apple.calculator", navegador: false))
    }

    // MARK: - Ícones e cache

    private final class IconesFalsos: FabricaDeIcones, @unchecked Sendable {
        var pedidos: [String] = []
        var png: Data? = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        func png(doApp caminho: String, lado: Int) -> Data? { pedidos.append("\(caminho)@\(lado)"); return png }
    }

    func testIconeVemDoSistemaUmaVezEDepoisDoCache() throws {
        let p = try PastaDeApps()
        try p.app("Apps/Calculator.app", info: ["CFBundleIdentifier": "com.apple.calculator"])
        let cache = p.raiz.appendingPathComponent("cache")
        let icones = IconesFalsos()
        let apps = AppsDoMac(descobridor: p.descobridor, icones: icones, pastaDeCache: cache, executor: ExecutorDeAcoesFalso())

        XCTAssertEqual(apps.icone(bundle: "com.apple.calculator"), icones.png)
        icones.png = nil // se pedisse de novo ao sistema, voltaria nil
        XCTAssertEqual(apps.icone(bundle: "com.apple.calculator"), Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))
        XCTAssertEqual(icones.pedidos, [p.raiz.path + "/Apps/Calculator.app@64"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).count, 1)
    }

    func testIconeDeBundleQueNaoEstaNaListaNaoChegaAoSistema() throws {
        let p = try PastaDeApps()
        try p.app("Apps/Calculator.app", info: ["CFBundleIdentifier": "com.apple.calculator"])
        let icones = IconesFalsos()
        let apps = AppsDoMac(descobridor: p.descobridor, icones: icones, pastaDeCache: nil, executor: ExecutorDeAcoesFalso())
        XCTAssertNil(apps.icone(bundle: "com.evil.app"))
        XCTAssertNil(apps.icone(bundle: "../../etc/passwd"))
        XCTAssertEqual(icones.pedidos, [])
        icones.png = nil
        XCTAssertNil(apps.icone(bundle: "com.apple.calculator"))
    }

    func testListaFicaGuardadaPorUmTempoEDepoisRele() throws {
        let p = try PastaDeApps()
        try p.app("Apps/A.app", info: ["CFBundleIdentifier": "com.x.a"])
        final class Relogio: @unchecked Sendable { var agora = Date(timeIntervalSince1970: 1000) }
        let relogio = Relogio()
        let apps = AppsDoMac(descobridor: p.descobridor, icones: IconesFalsos(), executor: ExecutorDeAcoesFalso(),
                             agora: { relogio.agora }, validade: 30)
        XCTAssertEqual(apps.apps().map(\.bundle), ["com.x.a"])
        try p.app("Apps/B.app", info: ["CFBundleIdentifier": "com.x.b"])
        relogio.agora += 10
        XCTAssertEqual(apps.apps().map(\.bundle), ["com.x.a"])
        relogio.agora += 30
        XCTAssertEqual(apps.apps().map(\.bundle), ["com.x.a", "com.x.b"])
    }

    // MARK: - Rotas

    private struct AppsFalsos: ProvedorDeApps {
        func apps() -> [AppInstalado] {
            [AppInstalado(nome: "Calculadora", valor: "Calculator", bundle: "com.apple.calculator", navegador: false),
             AppInstalado(nome: "Safari", valor: "Safari", bundle: "com.apple.Safari", navegador: true)]
        }
        func icone(bundle: String) -> Data? { bundle == "com.apple.calculator" ? Data([0x89, 0x50, 0x4E, 0x47]) : nil }
        func acoes(bundle: String) -> [AcaoDisponivel]? {
            switch bundle {
            case "com.apple.Safari": return [CatalogoDeAcoes.link, CatalogoDeAcoes.gmail]
            case CatalogoDeAcoes.navegadorPadrao: return [CatalogoDeAcoes.link]
            case "com.apple.calculator": return []
            default: return nil
            }
        }
    }

    /// O roteador do cenário padrão, com os apps de mentira (ou sem eles).
    private struct ComApps {
        let roteador: Roteador

        func pedir(_ metodo: String, _ alvo: String, codigo: String? = Cenario.codigo) -> RespostaRota {
            let (caminho, query) = Http.separarAlvo(alvo)
            let cab = codigo.map { ["x-deck-codigo": $0] } ?? [:]
            return roteador.responder(HttpRequisicao(metodo: metodo, caminho: caminho, query: query, cabecalhos: cab, corpo: Data()))
        }
    }

    private func cenario(comApps: Bool = true) throws -> ComApps {
        var r = try Cenario().roteador
        r.apps = comApps ? AppsFalsos() : nil
        return ComApps(roteador: r)
    }

    func testListaDeAppsExigeCodigoEOMetodoGet() throws {
        let c = try cenario()
        XCTAssertEqual(c.pedir("GET", "/api/apps", codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.apple.Safari/acoes", codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.apple.calculator/icone", codigo: nil).status, 401)
        let post = c.pedir("POST", "/api/apps")
        XCTAssertEqual(post.status, 405)
        XCTAssertEqual(post.extras["Allow"], "GET")
        XCTAssertEqual(c.pedir("PUT", "/api/apps/com.apple.Safari/acoes").status, 405)
    }

    func testListaDeAppsDevolveNomeValorEBundle() throws {
        let r = try cenario().pedir("GET", "/api/apps")
        XCTAssertEqual(r.status, 200)
        let lista = try XCTUnwrap(r.json as? [[String: Any]])
        XCTAssertEqual(lista.count, 2)
        XCTAssertEqual(lista[0]["nome"] as? String, "Calculadora")
        XCTAssertEqual(lista[0]["valor"] as? String, "Calculator")
        XCTAssertEqual(lista[0]["bundle"] as? String, "com.apple.calculator")
        XCTAssertEqual(lista[1]["navegador"] as? Bool, true)
        XCTAssertEqual(r.extras["Cache-Control"], "no-store")
    }

    func testIconeSaiComoPngComCacheEAppQueNaoExisteDa404() throws {
        let c = try cenario()
        let ok = c.pedir("GET", "/api/apps/com.apple.calculator/icone")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.tipo, "image/png")
        XCTAssertEqual(ok.corpo, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(ok.extras["Cache-Control"], "private, max-age=86400")
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.apple.Safari/icone").status, 404)
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.nao.existe/icone").status, 404)
    }

    func testAcoesDoAppSaemNoContrato() throws {
        let c = try cenario()
        let r = c.pedir("GET", "/api/apps/com.apple.Safari/acoes")
        XCTAssertEqual(r.status, 200)
        let obj = try XCTUnwrap(r.json as? [String: Any])
        XCTAssertEqual(obj["bundle"] as? String, "com.apple.Safari")
        let acoes = try XCTUnwrap(obj["acoes"] as? [[String: Any]])
        XCTAssertEqual(acoes.map { $0["id"] as? String }, ["link", "gmail"])
        XCTAssertEqual(acoes[0]["entrada"] as? String, "texto")
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.apple.calculator/acoes").status, 200)
        XCTAssertEqual(c.pedir("GET", "/api/apps/navegador-padrao/acoes").status, 200)
        XCTAssertEqual(c.pedir("GET", "/api/apps/com.nao.existe/acoes").status, 404)
    }

    func testRotasDeAppsNaoDeixamPassarCaminhoEstranho() throws {
        let c = try cenario()
        for alvo in ["/api/apps/", "/api/apps//acoes", "/api/apps/../icone", "/api/apps/com.apple.Safari", "/api/apps/com.apple.Safari/outra",
                     "/api/apps/com.apple.Safari/acoes/extra", "/api/apps/a b/acoes", "/api/apps/%2e%2e/acoes"] {
            XCTAssertEqual(c.pedir("GET", alvo).status, 404, alvo)
        }
        XCTAssertEqual(try cenario(comApps: false).pedir("GET", "/api/apps").status, 404)
    }

    func testBundleValido() {
        XCTAssertTrue(Roteador.bundleValido("com.apple.Safari"))
        XCTAssertTrue(Roteador.bundleValido("company.thebrowser.Browser"))
        XCTAssertFalse(Roteador.bundleValido(""))
        XCTAssertFalse(Roteador.bundleValido("a/b"))
        XCTAssertFalse(Roteador.bundleValido("a b"))
        XCTAssertFalse(Roteador.bundleValido(String(repeating: "a", count: 201)))
    }
}
