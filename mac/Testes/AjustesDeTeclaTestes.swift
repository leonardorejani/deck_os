import XCTest
@testable import Nucleo

private final class ShellGravador: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var _comandos: [String] = []
    var respostas: [(trecho: String, saida: SaidaShell)] = []
    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }
    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); _comandos.append(comando); trava.unlock()
        return respostas.first { comando.contains($0.trecho) }?.saida ?? SaidaShell(status: 0, saida: "")
    }
}

/// Tecla de comando com liga e desliga ("mudar foco": entra no modo jogo, clica de novo e volta ao de trabalho).
final class LigaDesligaTestes: XCTestCase {
    private func tecla(estado: String? = nil, desligar: String? = "foco trabalho") -> Tecla {
        Tecla(id: "foco", nome: "Foco", tipo: "comando", valor: "foco jogo", estado: estado, icone: nil, desligar: desligar)
    }

    private func executor(_ f: Executor, _ m: MemoriaLigaDesliga) -> ExecutorAcoes {
        ExecutorAcoes(shell: f, limiteSegundos: 5, shellDoUsuario: { "/bin/zsh" }, memoria: m)
    }

    func testSemComandoDeConferirODeckGuardaOEstadoEAlternaALigarEDesligar() {
        let f = ShellGravador(), m = MemoriaLigaDesliga()
        let ex = executor(f, m)
        XCTAssertNil(ex.executar(tecla()))
        XCTAssertTrue(f.comandos.last!.contains("foco jogo"))
        XCTAssertTrue(m.ligada("foco"))
        XCTAssertNil(ex.executar(tecla()))
        XCTAssertTrue(f.comandos.last!.contains("foco trabalho"))
        XCTAssertFalse(m.ligada("foco"))
        XCTAssertNil(ex.executar(tecla()))
        XCTAssertTrue(f.comandos.last!.contains("foco jogo"))
    }

    func testComandoQueFalhaNaoMudaOEstado() {
        let f = ShellGravador(), m = MemoriaLigaDesliga()
        f.respostas = [("foco jogo", SaidaShell(status: 1, saida: "deu ruim"))]
        XCTAssertNotNil(executor(f, m).executar(tecla()))
        XCTAssertFalse(m.ligada("foco"), "ligar falhou: a tecla não pode ficar como ligada")
    }

    func testComComandoDeConferirOSistemaManda() {
        let f = ShellGravador(), m = MemoriaLigaDesliga()
        let t = tecla(estado: "checar-foco")
        f.respostas = [("checar-foco", SaidaShell(status: 0, saida: ""))]
        XCTAssertNil(executor(f, m).executar(t))
        XCTAssertTrue(f.comandos.last!.contains("foco trabalho"), "conferir saiu 0: está ligado, então desliga")
        f.respostas = [("checar-foco", SaidaShell(status: 1, saida: ""))]
        XCTAssertNil(executor(f, m).executar(t))
        XCTAssertTrue(f.comandos.last!.contains("foco jogo"))
        XCTAssertFalse(m.ligada("foco"), "com comando de conferir o Deck não guarda estado nenhum")
    }

    /// O que confere roda no mesmo shell de perfil que o comando (aliases e PATH do .zshrc): conferir "cru" dava sempre
    /// "desligado" para quem usa alias, e todo toque rodava o comando de ligar.
    func testComandoDeConferirRodaNoShellDePerfilComoOsOutros() {
        let f = ShellGravador(), m = MemoriaLigaDesliga()
        f.respostas = [(" -l ", SaidaShell(status: 0, saida: "")), ("checar-foco", SaidaShell(status: 1, saida: "alias não existe aqui"))]
        let t = tecla(estado: "checar-foco")
        XCTAssertNil(executor(f, m).executar(t))
        XCTAssertTrue(f.comandos.last!.contains("foco trabalho"), "conferir saiu 0 no shell de perfil: está ligado, então desliga")
        XCTAssertEqual(TeclasAcesas.ler([t], executor: f, memoria: m), ["foco"], "a tecla acende pelo mesmo conferir")
    }

    func testTeclaDeComandoSemDesligarContinuaRodandoSoOComando() {
        let f = ShellGravador(), m = MemoriaLigaDesliga()
        var t = tecla(); t.desligar = nil
        XCTAssertNil(executor(f, m).executar(t))
        XCTAssertNil(executor(f, m).executar(t))
        XCTAssertEqual(f.comandos.filter { $0.contains("foco jogo") }.count, 2)
        XCTAssertFalse(m.ligada("foco"))
    }

    func testTeclaAcendePeloEstadoGuardadoEPeloComandoDeConferir() {
        let m = MemoriaLigaDesliga()
        let f = ShellGravador()
        XCTAssertEqual(TeclasAcesas.ler([tecla()], executor: f, memoria: m), [])
        m.definir("foco", ligada: true)
        XCTAssertEqual(TeclasAcesas.ler([tecla()], executor: f, memoria: m), ["foco"])
        // com comando de conferir, vale o comando e não a memória
        f.respostas = [("checar-foco", SaidaShell(status: 1, saida: ""))]
        XCTAssertEqual(TeclasAcesas.ler([tecla(estado: "checar-foco")], executor: f, memoria: m), [])
        f.respostas = [("checar-foco", SaidaShell(status: 0, saida: ""))]
        XCTAssertEqual(TeclasAcesas.ler([tecla(estado: "checar-foco")], executor: f, memoria: MemoriaLigaDesliga()), ["foco"])
    }

    func testEstadoGuardadoSobreviveAFecharEAbrir() throws {
        let arquivo = try pastaTemporaria().appendingPathComponent("liga.json")
        MemoriaLigaDesliga(arquivo: arquivo).definir("foco", ligada: true)
        XCTAssertTrue(MemoriaLigaDesliga(arquivo: arquivo).ligada("foco"))
        MemoriaLigaDesliga(arquivo: arquivo).definir("foco", ligada: false)
        XCTAssertFalse(MemoriaLigaDesliga(arquivo: arquivo).ligada("foco"))
    }

    func testConfigGravaLeEValidaOComandoDeDesligar() throws {
        let c = config(perfil: [tecla(estado: "checar-foco")])
        XCTAssertNil(Config.validar(c))
        let volta = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(volta.perfis[0].teclas[0].desligar, "foco trabalho")
        XCTAssertEqual(volta.perfis[0].teclas[0].estado, "checar-foco")
        var errada = c
        errada.perfis[0].teclas[0].tipo = "app"
        XCTAssertNotNil(Config.validar(errada), "só comando pode ter comando para desligar")
        let semChave = Tecla(id: "t", nome: "N", tipo: "comando", valor: "x", estado: nil, icone: nil)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(semChave), as: UTF8.self).contains("desligar"))
    }

    func testDesligarApagadoNoMacNaoVoltaDoArquivoAntigo() throws {
        let antigo = try JSONEncoder().encode(config(perfil: [tecla()]))
        var nova = config(perfil: [tecla()])
        nova.perfis[0].teclas[0].desligar = nil
        let novo = try JSONEncoder().encode(nova)
        XCTAssertNil(ArmazemConfig.preservandoDesconhecidos(novo: novo, antigo: antigo), "desligar é chave conhecida da tecla")
    }
}

/// Ajustes que saíram do Este Mac e foram para a tecla.
final class AjustesDeTeclaTestes: XCTestCase {
    func testControlesDeFabricaMostramOsTresEFaltaDeChaveNaoApagaEscolha() throws {
        XCTAssertEqual(ConfigControles(), ConfigControles(volume: true, brilho: true, teclado: true))
        let c = config(perfil: [])
        XCTAssertEqual(c.controles, ConfigControles())
        var escolhida = c
        escolhida.controles.brilho = false
        let volta = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(escolhida))
        XCTAssertFalse(volta.controles.brilho)
        XCTAssertTrue(volta.controles.volume)
        // config velha, sem a chave: todos ligados
        let velha = try JSONDecoder().decode(Config.self, from: Data(
            #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","nomeMac":"M","codigoAcesso":"abcdefghjkmnpqrstuvw"}"#.utf8))
        XCTAssertEqual(velha.controles, ConfigControles())
        // painel velho manda PUT sem "controles": a escolha fica
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(escolhida.publica)) as! [String: Any]
        json.removeValue(forKey: "controles")
        let nova = try Config.receber(corpo: JSONSerialization.data(withJSONObject: json), sobre: escolhida).get()
        XCTAssertFalse(nova.controles.brilho)
        XCTAssertEqual(escolhida.publica.controles, escolhida.controles)
    }

    func testMeetNoNavegadorOferecePenasMicrofoneECamera() {
        let apps = AppsDoMac(descobridor: DescobridorDeApps(pastas: [], extras: [], nomeExibido: { $0 }), executor: ShellGravador())
        XCTAssertEqual(apps.acoes(bundle: ControleDeReuniao.idDoMeet)?.map(\.id), ["reuniao-microfone", "reuniao-camera"])
        XCTAssertNil(apps.acoes(bundle: "nao.existe"))
    }

    func testMeetNoNavegadorProcuraASalaEmQualquerNavegadorAberto() {
        let f = ShellGravador()
        // Safari fechado, a sala está no Chrome.
        f.respostas = [
            ("pgrep -x 'Safari'", SaidaShell(status: 0, saida: "fechado\n")),
            ("com.google.Chrome", SaidaShell(status: 0, saida: "2\t3\thttps://meet.google.com/abc-defg-hij\n")),
        ]
        let apertadas = Apertadas()
        let ex = ExecutorAcoes(shell: f, temAcessibilidade: { true }, enviarTecla: { apertadas.lista.append($0) }, memoria: MemoriaLigaDesliga())
        let t = Tecla(id: "m", nome: "Mutar", tipo: "app", valor: "Google Meet", estado: nil, icone: nil, acao: AcaoDeApp(id: "reuniao-microfone", valor: nil))
        XCTAssertNil(ex.executar(t))
        XCTAssertEqual(apertadas.lista, [Teclas.ler("cmd+d")!])
        XCTAssertTrue(f.comandos.contains { $0.contains("active tab index of window 2 to 3") })
    }

    func testMeetNoNavegadorSemSalaAvisaENaoAperta() {
        let f = ShellGravador()
        f.respostas = [("pgrep", SaidaShell(status: 0, saida: "fechado\n"))]
        let apertadas = Apertadas()
        let ex = ExecutorAcoes(shell: f, temAcessibilidade: { true }, enviarTecla: { apertadas.lista.append($0) }, memoria: MemoriaLigaDesliga())
        let t = Tecla(id: "m", nome: "Câmera", tipo: "app", valor: "Google Meet", estado: nil, icone: nil, acao: AcaoDeApp(id: "reuniao-camera", valor: nil))
        XCTAssertEqual(ex.executar(t), "Não achei uma reunião do Meet aberta no navegador. Entre na sala e tente de novo")
        XCTAssertEqual(apertadas.lista, [])
    }

    func testMeetSemAcaoAbreOMeetNoNavegadorPadrao() {
        let f = ShellGravador()
        let t = Tecla(id: "m", nome: "Meet", tipo: "app", valor: "Google Meet", estado: nil, icone: nil)
        XCTAssertNil(ExecutorAcoes(shell: f, memoria: MemoriaLigaDesliga()).executar(t))
        XCTAssertEqual(f.comandos, ["open 'https://meet.google.com'"])
    }
}

private final class Apertadas: @unchecked Sendable { var lista: [Combinacao] = [] }

// MARK: - Agenda: calendário padrão do Mac

private struct CriadorComPadrao: CriadorDeAgenda {
    let registro: Registro
    var idPadrao: String? = "cal-do-mac"

    func destinos(pedirPermissao: Bool) -> DestinosDaAgenda {
        DestinosDaAgenda(calendarios: [OpcaoDeDestino(id: "cal-do-mac", nome: "Casa", cor: "#ff0000", conta: nil)], listas: [],
                         permissaoCalendario: "liberado", permissaoLembretes: "pedir", padrao: nil)
    }
    func criar(_ n: NovoCompromisso) -> Result<Void, ErroAgenda> { registro.anotar("criar \(n.destino.id)"); return .success(()) }
    func idDoCalendarioPadrao() -> String? { idPadrao }
}

final class AgendaPadraoDoMacTestes: XCTestCase {
    private let corpo = #"{"titulo":"Dentista","dia":"2026-11-14","inicio":"19:00"}"#

    private func cenario(idPadrao: String? = "cal-do-mac") throws -> Cenario {
        var c = try Cenario()
        c.roteador.criadorDeAgenda = CriadorComPadrao(registro: c.registro, idPadrao: idPadrao)
        var cfg = c.armazem.ler()
        cfg.agendaPadrao = .padraoDoMac
        _ = c.armazem.aplicar(cfg)
        return c
    }

    func testSalvarSemEscolherUsaOCalendarioPadraoDoMacDeVerdade() throws {
        let c = try cenario()
        XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: corpo).status, 200)
        XCTAssertEqual(c.registro.todos, ["criar cal-do-mac"], "o EventKit nunca vê o id de mentira")
    }

    func testSemCalendarioPadraoNaoCriaEDizOMotivo() throws {
        let c = try cenario(idPadrao: nil)
        XCTAssertEqual(c.pedir("POST", "/api/agenda/criar", corpo: corpo).status, 409)
        XCTAssertEqual(c.registro.todos, [])
    }

    func testListaDeDestinosMostraOPadraoComoOCalendarioDeVerdade() throws {
        let c = try cenario()
        let r = c.pedir("GET", "/api/agenda/destinos")
        let d = try JSONDecoder().decode(DestinosDaAgenda.self, from: r.corpo)
        XCTAssertEqual(d.padrao, DestinoAgenda(tipo: "calendario", id: "cal-do-mac"))
    }

    func testConfigAceitaOPadraoDoMac() {
        var c = config(perfil: [])
        c.agendaPadrao = .padraoDoMac
        XCTAssertNil(Config.validar(c))
    }
}
