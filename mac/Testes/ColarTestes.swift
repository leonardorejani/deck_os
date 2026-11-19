import XCTest
@testable import Nucleo

/// "Escrever no Mac": o texto do iPhone vira Cmd+V no app em foco, e a prancheta do dono volta como estava.
final class ColarTestes: XCTestCase {
    final class Diario: @unchecked Sendable {
        private let trava = NSLock()
        private var linhas: [String] = []
        func anotar(_ s: String) { trava.lock(); linhas.append(s); trava.unlock() }
        var todas: [String] { trava.lock(); defer { trava.unlock() }; return linhas }
    }

    final class PranchetaFalsa: PranchetaDoMac, @unchecked Sendable {
        let diario: Diario
        var conteudo: PranchetaGuardada
        var mudancas = 0
        /// Roda no meio da espera, simulando alguém copiando outra coisa.
        var aoEsperar: (() -> Void)?
        init(_ diario: Diario, conteudo: PranchetaGuardada = PranchetaGuardada(itens: [["public.utf8-plain-text": Data("original".utf8), "public.png": Data([1, 2, 3])]])) {
            self.diario = diario; self.conteudo = conteudo
        }
        func contagem() -> Int { mudancas }
        func guardar() -> PranchetaGuardada { diario.anotar("guardar"); return conteudo }
        func colocar(texto: String) -> Int {
            diario.anotar("colocar \(texto)")
            conteudo = PranchetaGuardada(itens: [["public.utf8-plain-text": Data(texto.utf8)]]); mudancas += 1; return mudancas
        }
        func devolver(_ g: PranchetaGuardada) { diario.anotar("devolver"); conteudo = g; mudancas += 1 }
    }

    struct Montagem {
        let colador: ColadorReal
        let prancheta: PranchetaFalsa
        let diario: Diario
    }

    func montar(foco: AppEmFoco? = AppEmFoco(bundle: "com.apple.Notes", nome: "Notas"), acessibilidade: Bool = true,
                aoEsperar: (() -> Void)? = nil) -> Montagem {
        let diario = Diario()
        let prancheta = PranchetaFalsa(diario)
        prancheta.aoEsperar = aoEsperar
        let colador = ColadorReal(prancheta: prancheta, emFoco: { foco }, temAcessibilidade: { acessibilidade },
                                  enviarTecla: { c in diario.anotar("tecla \(c.codigo) cmd=\(c.modificadores.contains(.comando))") },
                                  pausar: { _ in diario.anotar("espera"); prancheta.aoEsperar?() }, espera: 0.5)
        return Montagem(colador: colador, prancheta: prancheta, diario: diario)
    }

    func testColaGuardaPoeOTextoTeclaCmdVEDevolve() {
        let m = montar()
        XCTAssertNil(m.colador.colar("olá mundo"))
        // v é o código 9; a ordem importa: só devolve depois de esperar o app ler a prancheta
        XCTAssertEqual(m.diario.todas, ["guardar", "colocar olá mundo", "tecla 9 cmd=true", "espera", "devolver"])
        XCTAssertEqual(m.prancheta.conteudo.itens.first?["public.png"], Data([1, 2, 3]), "a imagem que estava lá volta junto")
    }

    func testSemAppEmFocoNaoMexeEmNada() {
        for foco in [nil, AppEmFoco(bundle: "", nome: "")] as [AppEmFoco?] {
            let m = montar(foco: foco)
            XCTAssertEqual(m.colador.colar("oi")?.status, 409)
            XCTAssertEqual(m.diario.todas, [], "sem app aceitável, nem a prancheta é tocada")
        }
    }

    func testAppsQueNaoAceitamTextoSaoRecusados() {
        for bundle in ["com.leonardorejani.deck", "com.leonardorejani.deck.bancada", "com.apple.loginwindow", "com.apple.finder", "com.apple.dock"] {
            let m = montar(foco: AppEmFoco(bundle: bundle, nome: "x"))
            XCTAssertEqual(m.colador.colar("oi")?.status, 409, bundle)
            XCTAssertEqual(m.diario.todas, [], bundle)
        }
        XCTAssertTrue(ColadorReal.aceitavel(AppEmFoco(bundle: "com.apple.Safari", nome: "Safari")))
        XCTAssertTrue(ColadorReal.aceitavel(AppEmFoco(bundle: "com.leonardorejani.deckfalso", nome: "Outro")), "só o Deck e o que mora debaixo do id dele")
    }

    func testSemAcessibilidadeNaoCola() {
        let m = montar(acessibilidade: false)
        let e = m.colador.colar("oi")
        XCTAssertEqual(e?.status, 422)
        XCTAssertEqual(e?.texto, ExecutorAcoes.erroAcessibilidade)
        XCTAssertEqual(m.diario.todas, [])
    }

    func testLimiteEControles() {
        let m = montar()
        XCTAssertEqual(m.colador.colar("")?.status, 400)
        XCTAssertEqual(m.colador.colar(String(repeating: "a", count: ColadorReal.limite + 1))?.status, 400)
        XCTAssertEqual(m.colador.colar("a\u{0}b")?.status, 400, "caractere de controle não passa")
        XCTAssertEqual(m.diario.todas, [])
        XCTAssertNil(m.colador.colar(String(repeating: "a", count: ColadorReal.limite)), "no limite exato passa")
        XCTAssertNil(m.colador.colar("linha 1\n\tlinha 2\r\n"), "quebra de linha e tabulação passam")
    }

    func testNaoDevolveSeAlguemCopiouNoMeioDaEspera() {
        var m = montar()
        let p = m.prancheta
        p.aoEsperar = { p.mudancas += 1; p.conteudo = PranchetaGuardada(itens: [["public.utf8-plain-text": Data("copiado agora".utf8)]]) }
        m = Montagem(colador: m.colador, prancheta: p, diario: m.diario)
        XCTAssertNil(m.colador.colar("oi"))
        XCTAssertFalse(m.diario.todas.contains("devolver"), "o que o dono copiou durante a espera não pode ser apagado")
        XCTAssertEqual(String(decoding: p.conteudo.itens[0]["public.utf8-plain-text"] ?? Data(), as: UTF8.self), "copiado agora")
    }

    func testPranchetaVaziaTambemVolta() {
        let diario = Diario()
        let p = PranchetaFalsa(diario, conteudo: PranchetaGuardada())
        let c = ColadorReal(prancheta: p, emFoco: { AppEmFoco(bundle: "com.apple.Notes", nome: "Notas") }, temAcessibilidade: { true },
                            enviarTecla: { _ in }, pausar: { _ in }, espera: 0)
        XCTAssertNil(c.colar("oi"))
        XCTAssertEqual(p.conteudo, PranchetaGuardada(), "prancheta que estava vazia fica vazia")
    }

    func testSegundoPedidoNoMeioDoPrimeiroEhRecusado() {
        final class Caixa: @unchecked Sendable { var erro: ErroColar? }
        let segundo = Caixa()
        let diario = Diario()
        let p = PranchetaFalsa(diario)
        nonisolated(unsafe) var colador: ColadorReal!
        colador = ColadorReal(prancheta: p, emFoco: { AppEmFoco(bundle: "com.apple.Notes", nome: "Notas") }, temAcessibilidade: { true },
                              enviarTecla: { _ in }, pausar: { _ in segundo.erro = colador.colar("outro") }, espera: 0)
        XCTAssertNil(colador.colar("primeiro"))
        XCTAssertEqual(segundo.erro?.status, 409)
        XCTAssertEqual(diario.todas.filter { $0.hasPrefix("colocar") }, ["colocar primeiro"])
    }

    // MARK: rota

    final class ColadorFalso: ColadorDeTexto, @unchecked Sendable {
        var recebidos: [String] = []
        var erro: ErroColar?
        func colar(_ texto: String) -> ErroColar? { recebidos.append(texto); return erro }
    }

    func testRota() throws {
        var c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/colar", corpo: "{\"texto\":\"oi\"}").status, 404, "sem colador o Mac responde 404 (Mac antigo)")
        let f = ColadorFalso()
        c.roteador.colador = f
        XCTAssertEqual(c.pedir("POST", "/api/colar", corpo: "{\"texto\":\"oi\"}", codigo: nil).status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/colar").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/colar", corpo: "nao e json").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/colar", corpo: "{\"texto\":5}").status, 400)
        XCTAssertEqual(f.recebidos, [])
        let ok = c.pedir("POST", "/api/colar", corpo: "{\"texto\":\"olá\\nmundo\"}")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual((ok.json as? [String: Any])?["ok"] as? Bool, true)
        XCTAssertEqual(f.recebidos, ["olá\nmundo"])
        f.erro = ErroColar(status: 409, texto: ColadorReal.erroSemApp)
        let sem = c.pedir("POST", "/api/colar", corpo: "{\"texto\":\"oi\"}")
        XCTAssertEqual(sem.status, 409)
        XCTAssertEqual(sem.erroTexto, ColadorReal.erroSemApp)
    }

    func testRotaGrandeCabeNoLimiteDoHttp() throws {
        var c = try Cenario()
        let f = ColadorFalso()
        c.roteador.colador = f
        let texto = String(repeating: "ã", count: ColadorReal.limite)
        let corpo = String(decoding: try JSONSerialization.data(withJSONObject: ["texto": texto]), as: UTF8.self)
        XCTAssertLessThan(corpo.utf8.count, 1024 * 1024)
        XCTAssertEqual(c.pedir("POST", "/api/colar", corpo: corpo).status, 200)
        XCTAssertEqual(f.recebidos.first?.count, ColadorReal.limite)
    }
}
