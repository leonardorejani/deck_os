import XCTest
import ServiceManagement
@testable import Deck

final class SecoesTestes: XCTestCase {
    func testSecoesNaOrdemDoPrototipo() {
        XCTAssertEqual(SecaoAjustes.grupos.flatMap { $0 }.map(\.nome),
                       ["Suas teclas", "Uso das IAs", "Conexões", "Acessos do Mac", "Este Mac", "Sobre o Deck"])
    }

    /// Palavras dele: "As permissões não aparecem no painel". A seção some do menu lateral só quando o
    /// recusado era o único motivo para mostrá-la, e isso era o defeito: sem recusa nada aparecia.
    func testAcessosDoMacApareceSempre() {
        XCTAssertTrue(SecaoAjustes.grupos.flatMap { $0 }.contains(.permissoes))
    }

    func testTextosDoMenu() {
        XCTAssertEqual(TextosDoMenu.acessosRecusados(1), "1 acesso recusado")
        XCTAssertEqual(TextosDoMenu.acessosRecusados(2), "2 acessos recusados")
        XCTAssertEqual(TextosDoMenu.estadoIphone(nil), "Nenhum iPhone pareado")
        XCTAssertEqual(TextosDoMenu.estadoIphone(IphonePareado(nome: "iPhone de Exemplo")), "iPhone de Exemplo, pelo Wi-Fi")
        XCTAssertEqual(TextosDoMenu.estadoIphone(IphonePareado(nome: "iPhone", canal: .bluetooth)), "iPhone, por Bluetooth")
    }

    func testConfiguracaoInicialNaoRepeteParaQuemJaUsava() {
        XCTAssertTrue(EstadoInicial.jaFeita(guardado: nil, configExistia: true))
        XCTAssertFalse(EstadoInicial.jaFeita(guardado: nil, configExistia: false))
        XCTAssertFalse(EstadoInicial.jaFeita(guardado: false, configExistia: true))
        XCTAssertTrue(EstadoInicial.jaFeita(guardado: true, configExistia: false))
    }
}

final class PastaDaPaginaTestes: XCTestCase {
    private func repo(painel: Bool) throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: raiz.appendingPathComponent("prototipo"), withIntermediateDirectories: true)
        if painel { try fm.createDirectory(at: raiz.appendingPathComponent("painel"), withIntermediateDirectories: true) }
        fm.createFile(atPath: raiz.appendingPathComponent("SPEC.md").path, contents: Data())
        try fm.createDirectory(at: raiz.appendingPathComponent("mac/App/build"), withIntermediateDirectories: true)
        return raiz
    }

    func testPrefereOPainelEDepoisOPrototipo() throws {
        let com = try repo(painel: true), sem = try repo(painel: false)
        defer { try? FileManager.default.removeItem(at: com); try? FileManager.default.removeItem(at: sem) }
        XCTAssertEqual(PastaDaPagina.achar(pacote: nil, partidas: [com.appendingPathComponent("mac/App/build")])?.lastPathComponent, "painel")
        XCTAssertEqual(PastaDaPagina.achar(pacote: nil, partidas: [sem.appendingPathComponent("mac/App/build")])?.lastPathComponent, "prototipo")
    }

    func testPainelDentroDoPacoteVenceTudo() throws {
        let sem = try repo(painel: false)
        defer { try? FileManager.default.removeItem(at: sem) }
        let pacote = sem.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: pacote.appendingPathComponent("painel"), withIntermediateDirectories: true)
        XCTAssertEqual(PastaDaPagina.achar(pacote: pacote, partidas: [sem])?.path, pacote.appendingPathComponent("painel").path)
    }

    /// O app instalado em /Applications não tem o repo por perto: a página (hoje o protótipo) vai dentro do pacote.
    func testPrototipoDentroDoPacoteServeQuandoNaoHaRepo() throws {
        let pacote = FileManager.default.temporaryDirectory.appendingPathComponent("deck-pacote-\(UUID())")
        defer { try? FileManager.default.removeItem(at: pacote) }
        try FileManager.default.createDirectory(at: pacote.appendingPathComponent("prototipo"), withIntermediateDirectories: true)
        XCTAssertEqual(PastaDaPagina.achar(pacote: pacote, partidas: []), pacote.appendingPathComponent("prototipo"))
        try FileManager.default.createDirectory(at: pacote.appendingPathComponent("painel"), withIntermediateDirectories: true)
        XCTAssertEqual(PastaDaPagina.achar(pacote: pacote, partidas: [])?.lastPathComponent, "painel", "o painel vence o protótipo")
    }

    /// O pacote de verdade (o app que esses testes hospedam) leva o painel, sem os testes dele e sem o protótipo.
    func testOPacoteDoAppLevaOPainel() throws {
        let recursos = try XCTUnwrap(Bundle.main.resourceURL)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: recursos.appendingPathComponent("painel/index.html").path))
        XCTAssertTrue(fm.fileExists(atPath: recursos.appendingPathComponent("painel/canal.js").path))
        XCTAssertFalse(fm.fileExists(atPath: recursos.appendingPathComponent("painel/teste").path), "os testes do painel ficam fora do pacote")
        XCTAssertFalse(fm.fileExists(atPath: recursos.appendingPathComponent("prototipo").path), "o protótipo não vai mais no pacote")
        XCTAssertEqual(PastaDaPagina.achar(pacote: recursos, partidas: [])?.lastPathComponent, "painel")
        let canal = try String(contentsOf: recursos.appendingPathComponent("painel/canal.js"), encoding: .utf8)
        XCTAssertTrue(canal.contains("X-Deck-Codigo-Novo"), "o painel empacotado trata o rodízio do código")
    }

    func testSemPaginaDevolveNil() {
        XCTAssertNil(PastaDaPagina.achar(pacote: nil, partidas: [FileManager.default.temporaryDirectory.appendingPathComponent("nada-\(UUID())")]))
    }

    func testPortasSeguintes() {
        XCTAssertEqual(Portas.candidatas(a: 4777).first, 4777)
        XCTAssertEqual(Portas.candidatas(a: 4777).count, Portas.tentativas)
        XCTAssertEqual(Portas.candidatas(a: 65535), [65535])
    }
}

private final class LoginFalso: ServicoDeLogin {
    var status: SMAppService.Status = .notRegistered
    var falha = false
    func register() throws { if falha { throw NSError(domain: "x", code: 1) }; status = .enabled }
    func unregister() throws { status = .notRegistered }
}

@MainActor
final class ModeloTestes: XCTestCase {
    private func pastaTemp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)")
    }

    func testCriaConfigPadraoELeNaProximaVez() throws {
        let arquivo = pastaTemp().appendingPathComponent("config.json")
        let defaults = UserDefaults(suiteName: "deck-teste-\(UUID())")!
        let m = ModeloApp(arquivo: arquivo, defaults: defaults, abrirComMac: AbrirComMac(servico: LoginFalso()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: arquivo.path))
        XCTAssertFalse(m.configuracaoInicialFeita, "config nova: configuração inicial ainda por fazer")
        m.usarComposicao("b")
        let m2 = ModeloApp(arquivo: arquivo, defaults: defaults, abrirComMac: AbrirComMac(servico: LoginFalso()))
        XCTAssertEqual(m2.config.comp, "b")
        XCTAssertTrue(m2.configuracaoInicialFeita, "config que já existia: não repete a configuração inicial")
    }

    func testReageAoConfigJsonMudarNoDisco() throws {
        let arquivo = pastaTemp().appendingPathComponent("config.json")
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teste-\(UUID())")!, abrirComMac: AbrirComMac(servico: LoginFalso()))
        m.iniciar(comServidor: false)
        defer { m.encerrar() }
        // o iPhone grava pelo PUT: o armazém do núcleo troca o arquivo por cima
        var nova = m.config
        nova.comp = "b"
        nova.perfilAtivo = nova.perfis[0].id
        try ArmazemConfig(url: arquivo).gravar(nova)
        // o runloop gira enquanto espera: é nele que o vigia da pasta avisa
        let limite = Date().addingTimeInterval(5)
        while m.config.comp != "b", Date() < limite { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(m.config.comp, "b")
    }

    func testConfigDanificadaNaoEApagadaEAvisa() throws {
        let pasta = pastaTemp()
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let arquivo = pasta.appendingPathComponent("config.json")
        try Data("{ nao e json".utf8).write(to: arquivo)
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teste-\(UUID())")!, abrirComMac: AbrirComMac(servico: LoginFalso()))
        XCTAssertNotNil(m.erro)
        XCTAssertEqual(try String(contentsOf: arquivo), "{ nao e json")
    }

    func testAbrirComMac() {
        let f = LoginFalso()
        let a = AbrirComMac(servico: f)
        XCTAssertFalse(a.ligado)
        a.definir(true)
        XCTAssertTrue(a.ligado)
        a.definir(false)
        XCTAssertFalse(a.ligado)
        f.falha = true
        a.definir(true)
        XCTAssertFalse(a.ligado)
        XCTAssertEqual(a.erro, "Não consegui ligar a abertura junto com o Mac.")
    }
}

@MainActor
final class GravarSemPerderTestes: XCTestCase {
    func testGravarParteDoQueOIphoneAcabouDeGravar() throws {
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)/config.json")
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-teste-\(UUID())")!, abrirComMac: AbrirComMac(servico: LoginFalso()))
        // o iPhone grava um perfil novo, o vigia ainda não avisou, e o Mac troca a composição
        var doIphone = m.config
        doIphone.perfis.append(Perfil(id: "ensaio", nome: "Ensaio", teclas: []))
        try ArmazemConfig(url: arquivo).gravar(doIphone)
        m.usarComposicao("b")
        XCTAssertEqual(m.config.perfis.map(\.id).sorted(), ["ensaio", "trabalho"])
        XCTAssertEqual(m.config.comp, "b")
    }

    func testSalvoAparecePorUmTempoDepoisDeGravar() async {
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac"))
        XCTAssertFalse(m.salvoAgora)
        m.usarComposicao("b")
        XCTAssertTrue(m.salvoAgora)
        XCTAssertEqual(TextosDoMenu.sincronia(nil, salvoAgora: true), "Salvo")
        XCTAssertEqual(TextosDoMenu.sincronia(IphonePareado(nome: "iPhone de Exemplo"), salvoAgora: true), "Salvo. Já está no iPhone")
        XCTAssertEqual(TextosDoMenu.sincronia(nil, salvoAgora: false), "Nenhum iPhone pareado")
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertFalse(m.salvoAgora)
    }
}

@MainActor
final class MudancaDeForaTestes: XCTestCase {
    func testConfigQueMudouNoDiscoSobeOContadorParaATelaAvisar() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck-fora-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pasta) }
        let arquivo = pasta.appendingPathComponent("config.json")
        let base = ArmazemConfig(url: arquivo)
        try base.gravar(Config.padrao(nomeMac: "Mac"))
        let m = ModeloApp(arquivo: arquivo, defaults: UserDefaults(suiteName: "deck-fora-\(UUID().uuidString)")!)
        XCTAssertEqual(m.mudancasDeFora, 0)
        m.recarregar()
        XCTAssertEqual(m.mudancasDeFora, 0, "nada mudou")
        var c = try base.ler()
        c.perfis[0].teclas.reverse()
        try base.gravar(c)
        m.recarregar()
        XCTAssertEqual(m.mudancasDeFora, 1)
        m.usarComposicao("b")
        XCTAssertEqual(m.mudancasDeFora, 1, "gravar pelo Mac não conta como mudança de fora")
    }
}
