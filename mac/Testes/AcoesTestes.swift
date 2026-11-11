import XCTest
@testable import Nucleo

/// Executor falso: guarda o que foi pedido e devolve a saída combinada.
final class ExecutorDeAcoesFalso: Executor, @unchecked Sendable {
    var comandos: [String] = []
    var saida = SaidaShell(status: 0, saida: "")
    func rodar(_ comando: String) -> SaidaShell {
        comandos.append(comando)
        return saida
    }
}

final class AcoesTestes: XCTestCase {
    private func tecla(_ tipo: String, _ valor: String) -> Tecla {
        Tecla(id: "t", nome: "Teste", tipo: tipo, valor: valor, estado: nil, icone: nil)
    }

    private func acoes(_ f: ExecutorDeAcoesFalso, acesso: Bool = true, enviadas: Enviadas = Enviadas()) -> ExecutorAcoes {
        ExecutorAcoes(shell: f, temAcessibilidade: { acesso }, enviarTecla: { enviadas.lista.append($0) })
    }

    final class Enviadas: @unchecked Sendable { var lista: [Combinacao] = [] }

    func testAppAbreComNomeEscapado() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("app", "Música d'Aguiar \"X\"")))
        XCTAssertEqual(f.comandos, ["open -a 'Música d'\\''Aguiar \"X\"'"])
    }

    func testAppInexistenteDaErroClaro() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: 1, saida: "Unable to find application named 'Zzz'")
        XCTAssertEqual(acoes(f).executar(tecla("app", "Zzz")), "Não achei o app Zzz neste Mac")
    }

    func testComandoOkEComFalha() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("comando", "echo oi")))
        XCTAssertTrue(f.comandos[0].contains("alarm($t)"))
        XCTAssertTrue(f.comandos[0].hasSuffix("'echo oi'"))
        f.saida = SaidaShell(status: 3, saida: "linha 1\nquebrou aqui\n\n")
        XCTAssertEqual(acoes(f).executar(tecla("comando", "x")), "O comando falhou: quebrou aqui")
    }

    func testComandoQueEstouraOTempo() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: ExecutorAcoes.statusTempoEsgotado, saida: "")
        XCTAssertEqual(acoes(f).executar(tecla("comando", "sleep 99")), "O comando demorou mais de 10 segundos e foi interrompido")
    }

    // Os três testes abaixo usam zsh e perl de verdade, que só o Mac tem (o Linux do CI não tem).
    #if os(macOS)
    /// Com o shell de verdade: o limite vale mesmo com o comando em laço, com filho vivo e com sinal.
    func testLimiteDeTempoComShellDeVerdade() {
        let real = ExecutorAcoes(shell: ExecutorShell(), temAcessibilidade: { false }, enviarTecla: { _ in }, limiteSegundos: 1)
        let msg = "O comando demorou mais de 1 segundos e foi interrompido"
        let t0 = Date()
        XCTAssertEqual(real.executar(tecla("comando", "while true; do :; done")), msg)
        XCTAssertEqual(real.executar(tecla("comando", "sleep 20; echo fim")), msg)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 8)
    }

    func testComandoRealDevolveFalhaESaida() {
        let real = ExecutorAcoes(shell: ExecutorShell(), temAcessibilidade: { false }, enviarTecla: { _ in }, limiteSegundos: 5)
        XCTAssertNil(real.executar(tecla("comando", "echo oi")))
        XCTAssertEqual(real.executar(tecla("comando", "echo ops >&2; exit 4")), "O comando falhou: ops")
    }

    /// Filho em segundo plano não pode segurar a tecla: o comando volta assim que o shell termina.
    func testFilhoEmSegundoPlanoNaoTravaATecla() {
        let real = ExecutorAcoes(shell: ExecutorShell(), temAcessibilidade: { false }, enviarTecla: { _ in }, limiteSegundos: 5)
        let t0 = Date()
        XCTAssertNil(real.executar(tecla("comando", "sleep 6 &")))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 3)
    }
    #endif

    func testAtalhoInexistenteEmPortugues() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: 1, saida: "Error: A operação não pôde ser concluída. Não foi possível encontrar o atalho")
        XCTAssertEqual(acoes(f).executar(tecla("atalho", "Nada")), "Não achei o Atalho Nada neste Mac")
    }

    func testValorComecandoComTracoNaoViraOpcao() {
        let f = ExecutorDeAcoesFalso()
        _ = acoes(f).executar(tecla("atalho", "-h"))
        XCTAssertEqual(f.comandos, ["shortcuts run -- '-h'"])
    }

    func testAtalhoOkEInexistente() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("atalho", "Modo Foco")))
        XCTAssertEqual(f.comandos, ["shortcuts run -- 'Modo Foco'"])
        f.saida = SaidaShell(status: 1, saida: "Error: Couldn't find shortcut")
        XCTAssertEqual(acoes(f).executar(tecla("atalho", "Nada")), "Não achei o Atalho Nada neste Mac")
    }

    func testTeclaEnviaQuandoTemPermissao() {
        let f = ExecutorDeAcoesFalso()
        let env = Enviadas()
        XCTAssertNil(acoes(f, enviadas: env).executar(tecla("teclado", "ctrl+opt+cmd+k")))
        XCTAssertEqual(env.lista, [Combinacao(codigo: 40, modificadores: [.controle, .opcao, .comando])])
        XCTAssertTrue(f.comandos.isEmpty)
    }

    func testTeclaSemPermissaoNaoEnvia() {
        let env = Enviadas()
        XCTAssertEqual(acoes(ExecutorDeAcoesFalso(), acesso: false, enviadas: env).executar(tecla("teclado", "cmd+k")),
                       "O Deck precisa do acesso de Acessibilidade para teclar")
        XCTAssertTrue(env.lista.isEmpty)
    }

    func testTeclaInvalida() {
        let env = Enviadas()
        XCTAssertNotNil(acoes(ExecutorDeAcoesFalso(), enviadas: env).executar(tecla("teclado", "cmd+banana")))
        XCTAssertTrue(env.lista.isEmpty)
    }

    func testTipoDesconhecidoEValorVazioNuncaExecutam() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNotNil(acoes(f).executar(tecla("foguete", "x")))
        for tipo in ["app", "comando", "atalho", "teclado"] {
            XCTAssertNotNil(acoes(f).executar(tecla(tipo, "  ")))
        }
        XCTAssertTrue(f.comandos.isEmpty)
    }

    /// O shell de verdade recebe o texto escapado e tem que devolver exatamente o mesmo texto,
    /// sem executar nada do que vem dentro.
    func testValoresMaliciososNaoExecutamNada() {
        let marca = NSTemporaryDirectory() + "deck-invasao-\(UUID().uuidString)"
        let perigosos = [
            "a'; touch \(marca); '", "$(touch \(marca))", "`touch \(marca)`",
            "x; touch \(marca)", "\"; touch \(marca); \"", "a\nb", "'", "\\",
        ]
        for v in perigosos {
            let r = ExecutorShell().rodar("printf %s \(ExecutorAcoes.escapar(v))")
            XCTAssertEqual(r.saida, v)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marca))
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

final class AcoesMacTestes: XCTestCase {
    func testConverteModificadoresParaCGEventFlags() {
        XCTAssertEqual(Modificadores([.comando, .shift]).flagsCG, [.maskCommand, .maskShift])
        XCTAssertEqual(Modificadores([.controle, .opcao, .fn]).flagsCG, [.maskControl, .maskAlternate, .maskSecondaryFn])
        XCTAssertEqual(Modificadores([]).flagsCG, [])
    }

    func testChecagemDePermissaoResponde() {
        // Só confirma que a chamada ao sistema funciona, sem abrir o pedido de acesso.
        _ = AcoesSistema.temAcessibilidade()
    }

    /// Prova no Mac de verdade: DECK_PROVA_REAL=1 swift test --filter prova
    func testProvaReal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DECK_PROVA_REAL"] == "1", "defina DECK_PROVA_REAL=1")
        let acoes = ExecutorAcoes(shell: ExecutorShell(), temAcessibilidade: { false }, enviarTecla: { _ in })
        func t(_ tipo: String, _ valor: String) -> Tecla { Tecla(id: "p", nome: "P", tipo: tipo, valor: valor, estado: nil, icone: nil) }

        XCTAssertNil(acoes.executar(t("app", "Calculator")))
        Thread.sleep(forTimeInterval: 2)
        print("PROVA app Calculator: aberto, checando processo")
        XCTAssertEqual(ExecutorShell().rodar("pgrep -x Calculator >/dev/null").status, 0)
        _ = ExecutorShell().rodar("osascript -e 'quit app \"Calculator\"'")

        let arq = NSTemporaryDirectory() + "deck-prova-\(UUID().uuidString).txt"
        XCTAssertNil(acoes.executar(t("comando", "echo deck-ok > '\(arq)'")))
        let conteudo = try String(contentsOfFile: arq, encoding: .utf8)
        print("PROVA comando gravou: \(conteudo.trimmingCharacters(in: .newlines))")
        XCTAssertEqual(conteudo, "deck-ok\n")
        try? FileManager.default.removeItem(atPath: arq)

        let erro = acoes.executar(t("app", "AppQueNaoExiste123"))
        print("PROVA app inexistente: \(erro ?? "nil")")
        XCTAssertEqual(erro, "Não achei o app AppQueNaoExiste123 neste Mac")

        let falha = acoes.executar(t("comando", "echo ops >&2; exit 4"))
        print("PROVA comando com falha: \(falha ?? "nil")")
        XCTAssertEqual(falha, "O comando falhou: ops")
        let sumiu = acoes.executar(t("atalho", "NaoExisteDeck123"))
        print("PROVA atalho inexistente: \(sumiu ?? "nil")")
        XCTAssertEqual(sumiu, "Não achei o Atalho NaoExisteDeck123 neste Mac")
        let traco = acoes.executar(t("atalho", "-h"))
        print("PROVA atalho -h: \(traco ?? "nil")")
        XCTAssertEqual(traco, "Não achei o Atalho -h neste Mac")
        print("PROVA acessibilidade concedida: \(AcoesSistema.temAcessibilidade())")
    }
}
#endif
