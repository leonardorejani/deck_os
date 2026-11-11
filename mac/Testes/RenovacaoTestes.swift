import XCTest
@testable import Nucleo

/// Executor de mentira: responde pelo texto do comando e guarda o que foi chamado.
final class ComandosFalsos: ExecutorDeComandos, @unchecked Sendable {
    private let trava = NSLock()
    private var chamadas_: [String] = []
    private var respostas: [(trecho: String, resultado: ResultadoDeComando)] = []
    var padrao = ResultadoDeComando(status: 0, saida: "")

    var chamadas: [String] { trava.lock(); defer { trava.unlock() }; return chamadas_ }
    func responder(_ trecho: String, status: Int32 = 0, saida: String = "") {
        trava.lock(); respostas.insert((trecho, ResultadoDeComando(status: status, saida: saida)), at: 0); trava.unlock()
    }

    func rodar(_ executavel: String, _ argumentos: [String], pasta: String?, limite: TimeInterval) async -> ResultadoDeComando {
        let linha = ([executavel] + argumentos).joined(separator: " ")
        return registrar(linha)
    }

    private func registrar(_ linha: String) -> ResultadoDeComando {
        trava.lock(); defer { trava.unlock() }
        chamadas_.append(linha)
        return respostas.first { linha.contains($0.trecho) }?.resultado ?? padrao
    }

    /// Um Mac com tudo no lugar e o iPhone liberado no cabo.
    static func tudoCerto() -> ComandosFalsos {
        let e = ComandosFalsos()
        e.responder("devicectl list devices", saida: "iPhone Exemplo   iPhone-Exemplo.coredevice.local   11111111-2222-3333-4444-555555555555   available (paired)   iPhone 15 Pro Max\n")
        e.responder("lockState", saida: "• passcodeRequired: false\n• unlockedSinceBoot: true\n")
        e.responder("xcodebuild -project", saida: "** BUILD SUCCEEDED **\n")
        e.responder("install app", saida: "App installed: bundleID com.leonardorejani.deck.iphone\n")
        e.responder("security cms", saida: """
            <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-17T18:00:00Z</date></dict></plist>
            """)
        return e
    }
}

private final class Ordem: @unchecked Sendable {
    private let trava = NSLock()
    private var lista: [String] = []
    func anotar(_ s: String) { trava.lock(); lista.append(s); trava.unlock() }
    var itens: [String] { trava.lock(); defer { trava.unlock() }; return lista }
}

final class RenovacaoMotorTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func motor(_ e: ComandosFalsos, pasta: String? = "/repo", existe: Bool = true, limpar: @escaping @Sendable () -> Void = {}) -> MotorDeRenovacao {
        MotorDeRenovacao(executor: e, relogio: { [t0] in t0 }, pasta: { pasta }, existe: { _ in existe }, limparPerfil: limpar)
    }

    func testApagaOPerfilVelhoAntesDeCompilarParaOVencimentoAndar() async {
        let e = ComandosFalsos.tudoCerto()
        let ordem = Ordem()
        let m = motor(e) { ordem.anotar("limpou") }
        _ = await m.renovar()
        XCTAssertEqual(ordem.itens, ["limpou"])
        XCTAssertTrue(e.chamadas.contains { $0.contains("xcodebuild -project") })
        let f = ComandosFalsos.tudoCerto()
        f.responder("devicectl list devices", saida: "")
        let ordem2 = Ordem()
        _ = await motor(f) { ordem2.anotar("limpou") }.renovar()
        XCTAssertEqual(ordem2.itens, [], "sem iPhone no cabo nem mexe no perfil")
    }

    func testApagarPerfisMexeSoNosDoAppDoIphone() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("perfis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        try Data("xx iOS Team Provisioning Profile: com.leonardorejani.deck.iphone xx".utf8).write(to: pasta.appendingPathComponent("a.mobileprovision"))
        try Data("xx iOS Team Provisioning Profile: com.leonardorejani.deck.prova xx".utf8).write(to: pasta.appendingPathComponent("b.mobileprovision"))
        try Data("com.leonardorejani.deck.iphone".utf8).write(to: pasta.appendingPathComponent("c.txt"))
        XCTAssertEqual(MotorDeRenovacao.apagarPerfisDoApp(em: pasta), 1)
        let sobrou = try FileManager.default.contentsOfDirectory(atPath: pasta.path).sorted()
        XCTAssertEqual(sobrou, ["b.mobileprovision", "c.txt"])
    }

    func testRenovaNaMesmaSequenciaDaProvaEDevolveOVencimentoDoPerfil() async {
        let e = ComandosFalsos.tudoCerto()
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .renovado(em: t0, venceEm: ISO8601DateFormatter().date(from: "2026-11-17T18:00:00Z")))
        let c = e.chamadas.joined(separator: "\n")
        XCTAssertTrue(c.contains("xcodegen generate"))
        XCTAssertTrue(c.contains("-allowProvisioningUpdates"), "o perfil da conta grátis nasce aqui")
        XCTAssertTrue(c.contains("devicectl device install app --device 11111111-2222-3333-4444-555555555555"))
        // a ordem da prova 0.4: gerar projeto, compilar, instalar
        XCTAssertLessThan(c.range(of: "xcodegen")!.lowerBound, c.range(of: "xcodebuild -project")!.lowerBound)
        XCTAssertLessThan(c.range(of: "xcodebuild -project")!.lowerBound, c.range(of: "install app")!.lowerBound)
    }

    func testSemPastaOuSemProjetoNaoTentaNada() async {
        let e = ComandosFalsos.tudoCerto()
        let a = await motor(e, pasta: nil).renovar()
        XCTAssertEqual(a, .falhou(.semProjeto(nil)))
        let b = await motor(e, existe: false).renovar()
        XCTAssertEqual(b, .falhou(.semProjeto("/repo")))
        XCTAssertTrue(e.chamadas.isEmpty)
    }

    func testSemXcodeParaAntesDeMexerNoIphone() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("--find xcodebuild", status: 72, saida: "xcrun: error: unable to find utility \"xcodebuild\"")
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .falhou(.semXcode))
        XCTAssertFalse(e.chamadas.contains { $0.contains("devicectl") })
    }

    func testIphoneForaDoCaboNaoCompilaNada() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("devicectl list devices", saida: "iPhone Exemplo   iPhone-Exemplo.coredevice.local   11111111-2222-3333-4444-555555555555   unavailable   iPhone 15 Pro Max\n")
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .falhou(.iphoneForaDoCabo))
        XCTAssertFalse(e.chamadas.contains { $0.contains("xcodebuild -project") }, "não gasta minutos compilando sem aparelho")
    }

    func testIphoneBloqueadoNaInstalacaoViraMotivoEmPortugues() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("install app", status: 1, saida: "ERROR: kAMDMobileImageMounterDeviceLocked (0xE8000087)")
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .falhou(.iphoneBloqueado))
        XCTAssertEqual(MotivoDaRenovacao.iphoneBloqueado.texto, "O iPhone está bloqueado")
    }

    func testSessaoDaAppleVencidaPedeParaEntrarDeNovoNoXcode() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("xcodebuild -project", status: 65, saida: "error: No Accounts: Add a new account in Accounts settings.\n** BUILD FAILED **")
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .falhou(.sessaoDaApple))
        XCTAssertTrue(MotivoDaRenovacao.sessaoDaApple.texto.contains("Apple Accounts"))
    }

    func testCompilacaoQueQuebraPorOutraRazaoGuardaAUltimaLinhaDeErro() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("xcodebuild -project", status: 65, saida: "Compiling...\nCasca.swift:10:5: error: cannot find 'Foo' in scope\n** BUILD FAILED **")
        let r = await motor(e).renovar()
        guard case .falhou(.outro(let t)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(t.contains("cannot find 'Foo'"))
    }

    func testXcodegenAusenteDizComoInstalar() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("xcodegen", status: 127, saida: "env: xcodegen: No such file or directory")
        let r = await motor(e).renovar()
        guard case .falhou(.outro(let t)) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(t.contains("brew install xcodegen"))
    }

    func testSondaDistingueForaDoCaboBloqueadoELiberado() async {
        let e = ComandosFalsos.tudoCerto()
        let liberado = await motor(e).sondar()
        XCTAssertEqual(liberado.situacao, .liberado)
        XCTAssertEqual(liberado.id, "11111111-2222-3333-4444-555555555555")
        e.responder("lockState", saida: "• passcodeRequired: true\n")
        let bloqueado = await motor(e).sondar()
        XCTAssertEqual(bloqueado.situacao, .bloqueado)
        e.responder("devicectl list devices", saida: "Name  Hostname  Identifier  State  Model\n----\n")
        let fora = await motor(e).sondar()
        XCTAssertEqual(fora.situacao, .semIphone)
    }

    // MARK: Wi-Fi, vários aparelhos e nada de tela

    private let iphone = "11111111-2222-3333-4444-555555555555"
    private let ipad = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    /// O que `devicectl list devices --quiet --json-output /dev/stdout` devolve, só com os campos que o Deck lê.
    private func json(_ aparelhos: [(id: String, tipo: String, transporte: String?)]) -> String {
        let itens = aparelhos.map { a -> String in
            let conexao = a.transporte.map { "\"transportType\": \"\($0)\", \"tunnelState\": \"disconnected\"," } ?? ""
            return "{\"identifier\": \"\(a.id)\", \"connectionProperties\": {\(conexao) \"pairingState\": \"paired\"}, \"hardwareProperties\": {\"deviceType\": \"\(a.tipo)\"}}"
        }
        return "{\"info\": {\"outcome\": \"success\"}, \"result\": {\"devices\": [\(itens.joined(separator: ","))]}}"
    }

    func testIphonePeloWifiRenovaSemCaboEAnotaOCaminho() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("--json-output", saida: json([(iphone, "iPhone", "localNetwork")]))
        let notas = Ordem()
        var m = motor(e)
        m.anotar = { notas.anotar($0) }
        let sonda = await m.sondar()
        XCTAssertEqual(sonda.via, .wifi)
        XCTAssertEqual(sonda.situacao, .liberado)
        let r = await m.renovar()
        XCTAssertEqual(r, .renovado(em: t0, venceEm: ISO8601DateFormatter().date(from: "2026-11-17T18:00:00Z")))
        XCTAssertTrue(notas.itens.contains("renovacao: iPhone achado pelo Wi-Fi"), "\(notas.itens)")
        XCTAssertTrue(e.chamadas.contains { $0.contains("install app --device \(iphone)") })
    }

    func testIphoneNoCaboDizCabo() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("--json-output", saida: json([(iphone, "iPhone", "wired")]))
        let sonda = await motor(e).sondar()
        XCTAssertEqual(sonda.via, .cabo)
    }

    func testIpadOuRelogioAoAlcanceNaoViramAlvoDaInstalacao() async {
        let e = ComandosFalsos.tudoCerto()
        let tabela = "iPad  i.local  \(ipad)  available (paired)  iPad Pro\niPhone Exemplo  l.local  \(iphone)  available (paired)  iPhone 15 Pro Max\n"
        e.responder("devicectl list devices", saida: tabela)
        e.responder("--json-output", saida: json([(ipad, "iPad", "localNetwork"), (iphone, "iPhone", "localNetwork")]))
        let r = await motor(e).renovar()
        guard case .renovado = r else { return XCTFail("\(r)") }
        XCTAssertTrue(e.chamadas.contains { $0.contains("install app --device \(iphone)") })
        XCTAssertFalse(e.chamadas.contains { $0.contains(ipad) && $0.contains("--device") }, "o app do iPhone não vai para o iPad")
    }

    func testSoOIpadAoAlcanceNaoCompilaNada() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("devicectl list devices", saida: "iPad  i.local  \(ipad)  available (paired)  iPad Pro\n")
        e.responder("--json-output", saida: json([(ipad, "iPad", "localNetwork")]))
        let r = await motor(e).renovar()
        XCTAssertEqual(r, .falhou(.iphoneForaDoCabo))
        XCTAssertFalse(e.chamadas.contains { $0.contains("xcodebuild -project") })
    }

    func testJsonIlegivelCaiNoPrimeiroDaTabelaSemQuebrarARenovacao() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("--json-output", status: 1, saida: "erro qualquer")
        let sonda = await motor(e).sondar()
        XCTAssertEqual(sonda.id, iphone)
        XCTAssertNil(sonda.via, "sem JSON não se sabe o caminho, mas renova do mesmo jeito")
        let r = await motor(e).renovar()
        guard case .renovado = r else { return XCTFail("\(r)") }
    }

    func testDetalhesAchaOJsonNoMeioDeTextoSolto() {
        let saida = "11:54:00  aviso solto\n" + json([(iphone, "iPhone", "wired")]) + "\nfim\n"
        let d = MotorDeRenovacao.detalhes(saida)
        XCTAssertEqual(d[iphone]?.tipo, "iPhone")
        XCTAssertEqual(d[iphone]?.via, .cabo)
        XCTAssertTrue(MotorDeRenovacao.detalhes("lixo").isEmpty)
    }

    func testOMotivoDeIphoneAusenteFalaDeCaboEDeWifi() {
        let t = MotivoDaRenovacao.iphoneForaDoCabo.texto
        XCTAssertTrue(t.contains("cabo") && t.contains("Wi-Fi"), t)
    }

    func testRenovarSoUsaFerramentasDeLinhaDeComandoNuncaAbreAppNemTela() async {
        let e = ComandosFalsos.tudoCerto()
        e.responder("--json-output", saida: json([(iphone, "iPhone", "localNetwork")]))
        _ = await motor(e).renovar()
        let permitidos: Set<String> = ["xcrun", "bash", "xcodegen", "xcodebuild", "security"]
        for linha in e.chamadas {
            let exe = String(linha.split(separator: " ").first ?? "")
            XCTAssertTrue(permitidos.contains(exe), "ferramenta fora da lista: \(linha)")
            XCTAssertFalse(["open", "osascript", "-a"].contains { linha.contains(" \($0) ") }, linha)
        }
        let xcrun = e.chamadas.filter { $0.hasPrefix("xcrun ") }.compactMap { $0.split(separator: " ").dropFirst().first.map(String.init) }
        XCTAssertTrue(Set(xcrun).isSubset(of: ["--find", "devicectl"]), "\(xcrun)")
    }

    func testUnavailableNaoContaComoAvailable() {
        let t = "iPhone  x.local  11111111-2222-3333-4444-555555555555  unavailable  iPhone16,2\niPad  y.local  AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE  connected  iPad\n"
        XCTAssertEqual(MotorDeRenovacao.aparelhoNoCabo(t), "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }
}

final class AgendaDeRenovacaoTestes: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func depois(_ horas: Double) -> Date { t0.addingTimeInterval(horas * 3_600) }

    func testSoVenceDepoisDeCincoDias() {
        XCTAssertFalse(AgendaDeRenovacao.devida(renovadoEm: t0, agora: depois(119)))
        XCTAssertTrue(AgendaDeRenovacao.devida(renovadoEm: t0, agora: depois(120)))
        XCTAssertFalse(AgendaDeRenovacao.devida(renovadoEm: nil, agora: depois(500)), "sem registro o Deck não inventa prazo")
    }

    func testSemFalhaTentaAssimQueVence() {
        XCTAssertFalse(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: nil, situacao: .liberado, agora: depois(100)))
        XCTAssertTrue(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: nil, situacao: .liberado, agora: depois(121)))
    }

    func testIphoneForaDoCaboEsperaOCaboVoltar() {
        let falha = FalhaDaRenovacao(em: depois(121), motivo: .iphoneForaDoCabo)
        func tentar(_ s: SituacaoDoIphone, _ h: Double) -> Bool { AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: s, agora: depois(h)) }
        XCTAssertFalse(tentar(.semIphone, 125))
        XCTAssertFalse(tentar(.bloqueado, 125), "no cabo mas bloqueado ainda não adianta")
        XCTAssertTrue(tentar(.liberado, 125), "voltou ao cabo e desbloqueado")
    }

    func testIphoneBloqueadoEsperaDesbloquear() {
        let falha = FalhaDaRenovacao(em: depois(121), motivo: .iphoneBloqueado)
        XCTAssertFalse(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .bloqueado, agora: depois(122)))
        XCTAssertTrue(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .liberado, agora: depois(122)))
    }

    func testFalhaQueNaoEDoIphoneEsperaUmaHoraParaNaoCompilarAToa() {
        let falha = FalhaDaRenovacao(em: depois(121), motivo: .sessaoDaApple)
        XCTAssertFalse(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .liberado, agora: depois(121.5)))
        XCTAssertTrue(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .liberado, agora: depois(122.1)))
    }

    func testIphoneLiberadoDesdeAFalhaTambemRepeteDepoisDeUmaHora() {
        let falha = FalhaDaRenovacao(em: depois(121), motivo: .iphoneBloqueado)
        XCTAssertFalse(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .desconhecido, agora: depois(121.5)))
        XCTAssertTrue(AgendaDeRenovacao.deveTentar(renovadoEm: t0, falha: falha, situacao: .desconhecido, agora: depois(123)))
    }
}

final class ArquivoDeInstalacaoTestes: XCTestCase {
    func testLeAPastaEADataQueOsScriptsGravam() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("renovacao-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Date(timeIntervalSince1970: 1_800_000_000)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["pasta": "/Users/x/deck", "instaladoEm": data], format: .xml, options: 0)
        try plist.write(to: url)
        XCTAssertEqual(ArquivoDeInstalacao.ler(url), ArquivoDeInstalacao(pasta: "/Users/x/deck", instaladoEm: data))
    }

    func testArquivoAusenteOuEstragadoViraVazio() throws {
        XCTAssertEqual(ArquivoDeInstalacao.ler(URL(fileURLWithPath: "/nao/existe.plist")), ArquivoDeInstalacao())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ruim-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("lixo".utf8).write(to: url)
        XCTAssertEqual(ArquivoDeInstalacao.ler(url), ArquivoDeInstalacao())
    }
}
