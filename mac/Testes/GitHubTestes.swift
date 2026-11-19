import XCTest
@testable import Nucleo

final class GitHubTestes: XCTestCase {
    let agora = Date(timeIntervalSince1970: 1_794_400_000)

    static func pr(_ n: Int, _ titulo: String, repo: String = "dono/app", url: String? = nil) -> String {
        #"{"number":\#(n),"title":"\#(titulo)","url":"\#(url ?? "https://github.com/\(repo)/pull/\(n)")","repository":{"name":"app","nameWithOwner":"\#(repo)"}}"#
    }

    func fonte(revisar: String = "[]", falhando: String = "[]", gh: Int32 = 0, login: Int32 = 0, busca: Int32 = 0) -> (FonteGitHub, ExecutorFalso) {
        let ex = ExecutorFalso([
            ("gh --version", SaidaShell(status: gh, saida: gh == 0 ? "gh version 2.60.0" : "zsh: command not found: gh")),
            ("gh auth status", SaidaShell(status: login, saida: login == 0 ? "Logged in" : "You are not logged into any GitHub hosts")),
            ("--review-requested=@me", SaidaShell(status: busca, saida: revisar)),
            ("status:failure", SaidaShell(status: busca, saida: falhando)),
            ("open ", SaidaShell(status: 0, saida: "")),
        ])
        return (FonteGitHub(executor: ex), ex)
    }

    func testLeOsDoisGruposComContagemELista() {
        let (f, _) = fonte(revisar: "[\(Self.pr(12, "Ajusta o login")), \(Self.pr(7, "Corrige a fila", repo: "dono/api"))]", falhando: "[\(Self.pr(30, "Nova tela"))]")
        let r = f.ler(agora: agora)
        XCTAssertEqual(r.estado, "ok")
        XCTAssertEqual(r.revisar.map(\.id), ["dono/app#12", "dono/api#7"])
        XCTAssertEqual(r.falhando, [ItemGitHub(id: "dono/app#30", titulo: "Nova tela", repo: "dono/app", numero: 30)])
        XCTAssertEqual(r.total, 3)
        XCTAssertNil(r.aviso)
        XCTAssertEqual(r.lidoEm, Datas.iso(agora))
    }

    func testListaVaziaEEstadoOkComZero() {
        let r = fonte().0.ler(agora: agora)
        XCTAssertEqual(r.estado, "ok")
        XCTAssertEqual(r.total, 0)
    }

    func testListaCurtaCorta() {
        let muitos = "[" + (1...9).map { Self.pr($0, "PR \($0)") }.joined(separator: ",") + "]"
        let r = fonte(revisar: muitos).0.ler(agora: agora)
        XCTAssertEqual(r.revisar.count, FonteGitHub.maxPorLista)
        XCTAssertEqual(r.revisar.first?.numero, 1)
    }

    func testSemGhEstadoClaroENenhumaBuscaFeita() {
        let (f, ex) = fonte(gh: 127)
        let r = f.ler(agora: agora)
        XCTAssertEqual(r.estado, "sem-gh")
        XCTAssertEqual(r.aviso, FonteGitHub.semGh)
        XCTAssertFalse(ex.comandos.contains { $0.contains("gh search") })
    }

    func testSemLoginEstadoClaroENenhumaBuscaFeita() {
        let (f, ex) = fonte(login: 1)
        let r = f.ler(agora: agora)
        XCTAssertEqual(r.estado, "sem-login")
        XCTAssertEqual(r.aviso, FonteGitHub.semLogin)
        XCTAssertFalse(ex.comandos.contains { $0.contains("gh search") })
    }

    func testFalhaDeRedeOuSaidaEstranhaViraErroSemListaFalsa() {
        XCTAssertEqual(fonte(busca: 1).0.ler(agora: agora).estado, "erro")
        let r = fonte(revisar: "isso nao e json").0.ler(agora: agora)
        XCTAssertEqual(r.estado, "erro")
        XCTAssertEqual(r.total, 0)
        XCTAssertNotNil(r.aviso)
    }

    func testItemComEnderecoForaDoGitHubOuRepoEstranhoEDescartado() {
        let ruins = "[\(Self.pr(1, "ok")), \(Self.pr(2, "golpe", url: "https://github.com.golpe.com/x/pull/2")), \(Self.pr(3, "http", url: "http://github.com/a/b/pull/3")), \(Self.pr(4, "arquivo", url: "file:///etc/passwd")), \(Self.pr(5, "repo ruim", repo: "a b/c")), \(Self.pr(6, "com porta", url: "https://github.com:8443/a/b/pull/6"))]"
        XCTAssertEqual(fonte(revisar: ruins).0.ler(agora: agora).revisar.map(\.numero), [1])
    }

    func testTituloLongoEncurtaESemControle() {
        let r = fonte(revisar: "[\(Self.pr(1, String(repeating: "x", count: 200))), \(Self.pr(2, "duas\\nlinhas"))]").0.ler(agora: agora)
        XCTAssertLessThanOrEqual(r.revisar[0].titulo.count, 90)
        XCTAssertTrue(r.revisar[0].titulo.hasSuffix("..."))
        XCTAssertEqual(r.revisar[1].titulo, "duaslinhas")
    }

    func testBuscaUsaOGhJaLogadoComOPathDoHomebrewENaoPedeToken() {
        let (f, ex) = fonte()
        _ = f.ler(agora: agora)
        let buscas = ex.comandos.filter { $0.contains("gh search prs") }
        XCTAssertEqual(buscas.count, 2)
        XCTAssertTrue(buscas.allSatisfy { $0.contains("/opt/homebrew/bin") })
        XCTAssertTrue(buscas.contains { $0.contains("--review-requested=@me") })
        XCTAssertTrue(buscas.contains { $0.contains("--author=@me") && $0.contains("status:failure") })
        XCTAssertFalse(ex.comandos.contains { $0.lowercased().contains("token") })
    }

    // MARK: Abrir

    func testAbrirSoAbreOPrDaUltimaLeituraNoNavegadorDoMac() {
        let (f, ex) = fonte(revisar: "[\(Self.pr(12, "Ajusta"))]")
        let abridor = AbridorDeGitHub(fonte: f, shell: ex)
        XCTAssertNotNil(abridor.abrir(id: "dono/app#12"), "antes de ler não há PR conhecido")
        _ = f.ler(agora: agora)
        XCTAssertNil(abridor.abrir(id: "dono/app#12"))
        XCTAssertTrue(ex.comandos.contains { $0.hasPrefix("open ") && $0.contains("https://github.com/dono/app/pull/12") })
        let antes = ex.comandos.count
        XCTAssertNotNil(abridor.abrir(id: "dono/app#99"))
        XCTAssertNotNil(abridor.abrir(id: "https://golpe.com"))
        XCTAssertEqual(ex.comandos.count, antes, "id que não veio da leitura não roda nada")
    }

    func testLeituraNovaEsqueceOsPrsDeAntes() {
        let ex = ExecutorMutavel2([("gh --version", .init(status: 0, saida: "")), ("gh auth status", .init(status: 0, saida: "")),
                                  ("--review-requested=@me", .init(status: 0, saida: "[\(Self.pr(12, "A"))]")), ("status:failure", .init(status: 0, saida: "[]")),
                                  ("open ", .init(status: 0, saida: ""))])
        let f = FonteGitHub(executor: ex)
        _ = f.ler(agora: agora)
        ex.trocar("--review-requested=@me", .init(status: 0, saida: "[]"))
        _ = f.ler(agora: agora)
        XCTAssertNotNil(AbridorDeGitHub(fonte: f, shell: ex).abrir(id: "dono/app#12"), "o PR some da lista, deixa de abrir")
    }

    // MARK: Rota e estado

    func testRotaAbrirExigeCodigoPostEIdValido() throws {
        let c = try Cenario()
        let reg = Registro()
        var r = c.roteador
        r.github = GitHubFalso(registro: reg)
        func pedir(_ m: String, _ corpo: String, codigo: String? = Cenario.codigo) -> RespostaRota {
            r.responder(HttpRequisicao(metodo: m, caminho: "/api/github/abrir", query: [:], cabecalhos: codigo.map { ["x-deck-codigo": $0] } ?? [:], corpo: Data(corpo.utf8)))
        }
        XCTAssertEqual(pedir("POST", #"{"id":"dono/app#12"}"#, codigo: nil).status, 401)
        XCTAssertEqual(pedir("GET", "").status, 405)
        XCTAssertEqual(pedir("POST", "x").status, 400)
        XCTAssertEqual(pedir("POST", #"{"id":"dono/app#99"}"#).status, 422)
        XCTAssertEqual(pedir("POST", #"{"id":"dono/app#12"}"#).status, 200)
        XCTAssertEqual(reg.todos, ["github dono/app#99", "github dono/app#12"])
        XCTAssertEqual(c.roteador.responder(HttpRequisicao(metodo: "POST", caminho: "/api/github/abrir", query: [:], cabecalhos: ["x-deck-codigo": Cenario.codigo], corpo: Data(#"{"id":"a/b#1"}"#.utf8))).status, 404, "sem o provedor a rota não existe")
    }

    func testEstadoSoLeOGitHubComATeclaESelaComAContagem() {
        let contador = Contador()
        var f = Fontes.vivas(executor: ExecutorFalso([]), casa: "/nonexistent")
        f.github = { _ in contador.somar(); return ResumoGitHub(estado: "ok", revisar: [ItemGitHub(id: "a/b#1", titulo: "t", repo: "a/b", numero: 1)], falhando: [ItemGitHub(id: "a/b#2", titulo: "u", repo: "a/b", numero: 2)]) }
        let ag = Agregador(fontes: f)
        func cfg(_ t: [Tecla]) -> Config { Config(perfis: [Perfil(id: "p", nome: "P", teclas: t)], perfilAtivo: "p", nomeMac: "Mac", codigoAcesso: "abcdefghjkmnpqrstuvw") }
        let sem = ag.estado(config: cfg([Tecla(id: "x", nome: "X", tipo: "comando", valor: "true", estado: nil, icone: nil)]), agora: agora)
        XCTAssertNil(sem.github)
        XCTAssertEqual(contador.valor, 0, "sem a tecla GitHub o Mac nem chama o gh")
        let tecla = Tecla(id: "gh", nome: "GitHub", tipo: "app", valor: TeclasDeFora.valorDoGitHub, estado: nil, icone: nil)
        let com = ag.estado(config: cfg([tecla]), agora: agora)
        XCTAssertEqual(com.github?.total, 2)
        XCTAssertEqual(com.selos["gh"], "2")
        _ = ag.estado(config: cfg([tecla]), agora: agora.addingTimeInterval(60))
        XCTAssertEqual(contador.valor, 1, "o estado pede a cada segundo, o gh só a cada poucos minutos")
        _ = ag.estado(config: cfg([tecla]), agora: agora.addingTimeInterval(Agregador.validadeDoGitHub + 1))
        XCTAssertEqual(contador.valor, 2)
    }

    func testSemGhSemSeloEComEstadoNoResumo() {
        var f = Fontes.vivas(executor: ExecutorFalso([]), casa: "/nonexistent")
        f.github = { _ in ResumoGitHub(estado: "sem-gh", aviso: FonteGitHub.semGh) }
        let tecla = Tecla(id: "gh", nome: "GitHub", tipo: "app", valor: TeclasDeFora.valorDoGitHub, estado: nil, icone: nil)
        let e = Agregador(fontes: f).estado(config: Config(perfis: [Perfil(id: "p", nome: "P", teclas: [tecla])], perfilAtivo: "p", nomeMac: "Mac", codigoAcesso: "abcdefghjkmnpqrstuvw"), agora: agora)
        XCTAssertEqual(e.github?.estado, "sem-gh")
        XCTAssertNil(e.selos["gh"])
    }
}

struct GitHubFalso: ProvedorDeGitHub {
    let registro: Registro
    func abrir(id: String) -> String? {
        registro.anotar("github \(id)")
        return id == "dono/app#12" ? nil : "Não achei esse PR. Abra a lista de novo."
    }
}

/// Executor falso que responde por trecho do comando e deixa trocar a resposta no meio do teste.
final class ExecutorMutavel2: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var respostas: [(String, SaidaShell)]
    private var _comandos: [String] = []
    init(_ r: [(String, SaidaShell)]) { respostas = r }
    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }
    func trocar(_ trecho: String, _ nova: SaidaShell) {
        trava.lock(); defer { trava.unlock() }
        if let i = respostas.firstIndex(where: { $0.0 == trecho }) { respostas[i].1 = nova }
    }
    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); defer { trava.unlock() }
        _comandos.append(comando)
        return respostas.first { comando.contains($0.0) }?.1 ?? SaidaShell(status: 127, saida: "")
    }
}
