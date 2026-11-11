import XCTest
@testable import Nucleo

/// Executor que responde por padrão de comando: o que contém o trecho recebe a saída combinada.
private final class ExecutorPorTrecho: Executor, @unchecked Sendable {
    var comandos: [String] = []
    var respostas: [(trecho: String, saida: SaidaShell)] = []
    var padrao = SaidaShell(status: 0, saida: "")
    func rodar(_ comando: String) -> SaidaShell {
        comandos.append(comando)
        return respostas.first { comando.contains($0.trecho) }?.saida ?? padrao
    }
}

final class CatalogoDeAcoesTestes: XCTestCase {
    private func app(_ bundle: String, navegador: Bool = false, arquivos: Bool = false) -> AppAchado {
        AppAchado(app: AppInstalado(nome: "X", valor: "X", bundle: bundle, navegador: navegador), caminho: "/x", abreArquivos: arquivos)
    }

    private func ids(_ l: [AcaoDisponivel]) -> [String] { l.map(\.id) }

    func testMailListaAsContasConfiguradasNoMail() {
        let f = ExecutorPorTrecho()
        f.padrao = SaidaShell(status: 0, saida: "AAA-1\tiCloud\tpessoa@icloud.com\nBBB-2\tTrabalho\t\n\nlixo sem tab\n")
        let acoes = CatalogoDeAcoes(executor: f).acoes(para: app("com.apple.mail"))

        XCTAssertEqual(ids(acoes), ["mail-caixa", "mail-novo"])
        XCTAssertEqual(acoes[0].entrada, "lista")
        XCTAssertEqual(acoes[0].opcoes, [OpcaoDeAcao(valor: "AAA-1", nome: "iCloud", detalhe: "pessoa@icloud.com"),
                                         OpcaoDeAcao(valor: "BBB-2", nome: "Trabalho", detalhe: nil)])
        XCTAssertNil(acoes[0].aviso)
        XCTAssertEqual(acoes[1].entrada, "nenhuma")
        // Mail fechado abre escondido antes de perguntar, e o script é fixo.
        XCTAssertEqual(f.comandos.count, 1)
        XCTAssertTrue(f.comandos[0].hasPrefix("pgrep -x 'Mail' >/dev/null || open -g -j -b 'com.apple.mail'; "))
        XCTAssertTrue(f.comandos[0].contains("email addresses of c"))
    }

    func testMailSemPermissaoSemContaOuDemoradoViraAviso() {
        let f = ExecutorPorTrecho()
        let c = CatalogoDeAcoes(executor: f)

        f.padrao = SaidaShell(status: 1, saida: "execution error: Not authorized to send Apple events to Mail. (-1743)")
        var a = c.acoes(para: app("com.apple.mail"))[0]
        XCTAssertEqual(a.opcoes, [])
        XCTAssertEqual(a.aviso, "O Deck não tem permissão para controlar o Mail. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação.")

        f.padrao = SaidaShell(status: ExecutorAcoes.statusTempoEsgotado, saida: "")
        a = c.acoes(para: app("com.apple.mail"))[0]
        XCTAssertEqual(a.aviso, "O macOS está esperando você permitir o Deck controlar o Mail. Toque em Permitir na janela do Mac e tente de novo.")

        f.padrao = SaidaShell(status: 0, saida: "")
        a = c.acoes(para: app("com.apple.mail"))[0]
        XCTAssertEqual(a.aviso, "Nenhuma conta configurada no Mail. Adicione uma conta no app Mail.")

        f.padrao = SaidaShell(status: 1, saida: "coisa estranha")
        XCTAssertEqual(c.acoes(para: app("com.apple.mail"))[0].aviso, "Não consegui ler as opções do Mail.")
    }

    func testNotasListaAsPastasComAContaDeDetalhe() {
        let f = ExecutorPorTrecho()
        f.padrao = SaidaShell(status: 0, saida: "x-coredata://1/ICFolder/p5\tCifras\tiCloud\nx-coredata://1/ICFolder/p6\tNotas\tNo meu Mac\n")
        let a = CatalogoDeAcoes(executor: f).acoes(para: app("com.apple.Notes"))
        XCTAssertEqual(ids(a), ["notas-pasta"])
        XCTAssertEqual(a[0].opcoes?.map(\.nome), ["Cifras", "Notas"])
        XCTAssertEqual(a[0].opcoes?.map(\.detalhe), ["iCloud", "No meu Mac"])
        XCTAssertTrue(f.comandos[0].contains("open -g -j -b 'com.apple.Notes'"))
    }

    func testCalendarioNavegadorEAppComDocumentosTemAsSuas() {
        let c = CatalogoDeAcoes(executor: ExecutorPorTrecho())
        XCTAssertEqual(ids(c.acoes(para: app("com.apple.iCal"))), ["calendario-hoje", "calendario-dia"])
        XCTAssertEqual(ids(c.acoes(para: app("com.google.Chrome", navegador: true))), ["link", "gmail"])
        XCTAssertEqual(ids(c.acoes(para: app("com.apple.Terminal", arquivos: true))), ["abrir-arquivo"])
        XCTAssertEqual(ids(c.acoes(para: app("com.apple.calculator"))), [])
        XCTAssertEqual(ids(c.acoes(para: nil)), ["link", "gmail"])
    }

    func testAppsQueNaoPrecisamDoAppAbertoNaoRodamNada() {
        let f = ExecutorPorTrecho()
        let c = CatalogoDeAcoes(executor: f)
        _ = c.acoes(para: app("com.apple.iCal"))
        _ = c.acoes(para: app("com.google.Chrome", navegador: true))
        _ = c.acoes(para: nil)
        XCTAssertEqual(f.comandos, [])
    }

    func testListaDeContasComNomeEstranhoNaoQuebra() {
        let linhas = AppleScript.lerLista("1\tConta\twith spaces\n2\tNome com \"aspas\" e 'simples'\t\n3\t\tvazio\n\t\t\n")
        XCTAssertEqual(linhas.map(\.valor), ["1", "2"])
        XCTAssertEqual(linhas[1].nome, "Nome com \"aspas\" e 'simples'")
    }
}

final class ExecucaoDeAcaoDeAppTestes: XCTestCase {
    private func tecla(_ valor: String, _ id: String, _ escolha: String?) -> Tecla {
        Tecla(id: "t", nome: "Minha", tipo: "app", valor: valor, estado: nil, icone: nil, acao: AcaoDeApp(id: id, valor: escolha))
    }

    private func acoes(_ f: Executor) -> ExecutorAcoes {
        ExecutorAcoes(shell: f, temAcessibilidade: { true }, enviarTecla: { _ in })
    }

    func testMailCaixaPassaAContaComoArgumentoENuncaNoTextoDoScript() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Mail", "mail-caixa", "AAA-1")))
        XCTAssertEqual(f.comandos.count, 1)
        let c = f.comandos[0]
        XCTAssertTrue(c.hasPrefix("perl -e "), "roda dentro do vigia de tempo")
        XCTAssertTrue(c.contains("on run argv"))
        XCTAssertTrue(c.contains("account id (item 1 of argv)"))
        // A escolha vai por último, escapada como argumento do osascript, dentro da linha do zsh.
        XCTAssertTrue(c.hasSuffix(Shell.aspas("osascript " + AppleScript.caixaDoMail.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
                                              + " " + Shell.aspas("AAA-1"))))
    }

    func testTresTeclasDeEmailComTresContasDaoTresComandosDiferentes() {
        let f = ExecutorDeAcoesFalso()
        for conta in ["UUID-A", "UUID-B", "UUID-C"] { XCTAssertNil(acoes(f).executar(tecla("Mail", "mail-caixa", conta))) }
        XCTAssertEqual(Set(f.comandos).count, 3)
        for (i, conta) in ["UUID-A", "UUID-B", "UUID-C"].enumerated() { XCTAssertTrue(f.comandos[i].contains(conta)) }
    }

    func testMailSemContaEscolhidaNaoExecutaNada() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", nil)), "Escolha a conta do Mail na tecla \"Minha\"")
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "  ")), "Escolha a conta do Mail na tecla \"Minha\"")
        XCTAssertEqual(f.comandos, [])
    }

    func testMailContaQueSumiuDaErroClaro() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: 1, saida: "execution error: Mail got an error: Can't get account id \"X\". (-1728)")
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "X")),
                       "Não achei essa conta no Mail. Escolha a conta de novo na tecla \"Minha\"")
    }

    func testPermissaoNegadaETempoEsgotadoDaoMotivoEmPortugues() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: 1, saida: "Not authorized to send Apple events to Mail. (-1743)")
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "X")),
                       "O Deck não tem permissão para controlar o Mail. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação.")
        f.saida = SaidaShell(status: ExecutorAcoes.statusTempoEsgotado, saida: "")
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "X")),
                       "O macOS está esperando você permitir o Deck controlar o Mail. Toque em Permitir na janela do Mac e tente de novo.")
        f.saida = SaidaShell(status: 1, saida: "outra coisa")
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "X")), "Não consegui abrir isso no Mail")
    }

    func testMailNovoAbreOMailComMailto() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Mail", "mail-novo", nil)))
        XCTAssertEqual(f.comandos, ["open -b 'com.apple.mail' 'mailto:'"])
    }

    func testLinkAbreNoNavegadorEscolhidoOuNoPadrao() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Google Chrome", "link", "https://github.com/leo")))
        XCTAssertNil(acoes(f).executar(tecla("navegador-padrao", "link", "github.com")))
        XCTAssertEqual(f.comandos, ["open -a 'Google Chrome' 'https://github.com/leo'", "open 'https://github.com'"])
    }

    func testLinkRecusaEsquemaPerigosoEEnderecoVazio() {
        let f = ExecutorDeAcoesFalso()
        for ruim in ["javascript:alert(1)", "file:///etc/passwd", "ftp://x.com", "https://", "a b", "-a Terminal", "x; touch /tmp/y", "  ", "mailto:a@b.com", "tel:123"] {
            XCTAssertEqual(acoes(f).executar(tecla("Safari", "link", ruim)), "O endereço da tecla \"Minha\" não é válido", ruim)
        }
        XCTAssertEqual(f.comandos, [])
    }

    func testLinkComAspasESubshellVaiEscapado() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Safari", "link", "https://x.com/a'b$(id)`c`")))
        XCTAssertEqual(f.comandos, ["open -a 'Safari' 'https://x.com/a'\\''b$(id)`c`'"])
    }

    func testGmailPorNumeroEPorEmail() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Google Chrome", "gmail", "2")))
        XCTAssertNil(acoes(f).executar(tecla("Safari", "gmail", "nome+x@gmail.com")))
        XCTAssertNil(acoes(f).executar(tecla("navegador-padrao", "gmail", "0")))
        XCTAssertEqual(f.comandos, [
            "open -a 'Google Chrome' 'https://mail.google.com/mail/u/2/#inbox'",
            "open -a 'Safari' 'https://mail.google.com/mail/?authuser=nome%2Bx%40gmail.com#inbox'",
            "open 'https://mail.google.com/mail/u/0/#inbox'",
        ])
    }

    func testGmailRecusaContaInvalida() {
        let f = ExecutorDeAcoesFalso()
        for ruim in ["abc", "123", "a@b", "@gmail.com", "a@@gmail.com", "x@y.com/../z", "x y@gmail.com", "x@gmail.com&authuser=9", "-1"] {
            XCTAssertEqual(acoes(f).executar(tecla("Safari", "gmail", ruim)),
                           "A conta do Gmail da tecla \"Minha\" não é válida. Use o número (0, 1, 2) ou o e-mail", ruim)
        }
        XCTAssertEqual(f.comandos, [])
    }

    func testNavegadorQueNaoExisteMaisDaErroDoApp() {
        let f = ExecutorDeAcoesFalso()
        f.saida = SaidaShell(status: 1, saida: "Unable to find application named 'Arc'")
        XCTAssertEqual(acoes(f).executar(tecla("Arc", "link", "https://x.com")), "Não achei o app Arc neste Mac")
    }

    func testNotasPastaEhCalendarioPassamArgumento() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Notes", "notas-pasta", "x-coredata://1/ICFolder/p5")))
        XCTAssertTrue(f.comandos[0].contains("show folder id (item 1 of argv)"))
        XCTAssertTrue(f.comandos[0].contains(Shell.aspas("x-coredata://1/ICFolder/p5")))
        XCTAssertNil(acoes(f).executar(tecla("Calendar", "calendario-hoje", nil)))
        XCTAssertTrue(f.comandos[1].contains("view calendar at (current date)"))
        XCTAssertNil(acoes(f).executar(tecla("Calendar", "calendario-dia", "2026-12-25")))
        XCTAssertTrue(f.comandos[2].contains("view calendar at d"))
        XCTAssertTrue(f.comandos[2].contains(Shell.aspas("2026-12-25")))
        XCTAssertEqual(acoes(f).executar(tecla("Notes", "notas-pasta", nil)), "Escolha a pasta das Notas na tecla \"Minha\"")
        XCTAssertEqual(acoes(f).executar(tecla("Calendar", "calendario-dia", "2026-02-30")),
                       "O dia da tecla \"Minha\" não é válido. Use AAAA-MM-DD")
        XCTAssertEqual(f.comandos.count, 3)
    }

    func testEscolhaComecandoComTracoNaoViraOpcaoDoOsascript() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "mail-caixa", "-e")), "A escolha da tecla não é válida")
        XCTAssertEqual(f.comandos, [])
    }

    func testAbrirArquivoExigeCaminhoQueExiste() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("deck pasta d'teste \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let f = ExecutorDeAcoesFalso()
        XCTAssertNil(acoes(f).executar(tecla("Visual Studio Code", "abrir-arquivo", pasta.path)))
        XCTAssertEqual(f.comandos, ["open -a 'Visual Studio Code' " + ExecutorAcoes.escapar(pasta.path)])
        XCTAssertEqual(acoes(f).executar(tecla("Terminal", "abrir-arquivo", "/nao/existe/deck-xyz")), "Não achei /nao/existe/deck-xyz neste Mac")
        XCTAssertEqual(acoes(f).executar(tecla("Terminal", "abrir-arquivo", "relativo/pasta")), "O caminho da tecla \"Minha\" precisa começar com / ou ~")
        XCTAssertEqual(acoes(f).executar(tecla("Terminal", "abrir-arquivo", "-a")), "O caminho da tecla \"Minha\" precisa começar com / ou ~")
        XCTAssertEqual(f.comandos.count, 1)
    }

    func testAcaoDesconhecidaNaoViraAbrirOAppSemAvisar() {
        let f = ExecutorDeAcoesFalso()
        XCTAssertEqual(acoes(f).executar(tecla("Mail", "acao-do-futuro", "x")), "Essa ação não existe nesta versão do Deck")
        XCTAssertEqual(f.comandos, [])
    }

    func testTeclaDeAppSemAcaoContinuaAbrindoSoOApp() {
        let f = ExecutorDeAcoesFalso()
        let t = Tecla(id: "t", nome: "Mail", tipo: "app", valor: "Mail", estado: nil, icone: nil)
        XCTAssertNil(acoes(f).executar(t))
        XCTAssertEqual(f.comandos, ["open -a 'Mail'"])
    }

    // MARK: - Com o shell de verdade

    #if os(macOS)
    /// O que a tecla entrega ao osascript volta inteiro e nunca é executado, nem com aspas, `$()`, crase e quebra de linha.
    func testArgumentoMaliciosoVoltaIgualENaoExecutaNada() {
        let marca = NSTemporaryDirectory() + "deck-invasao-osa-\(UUID().uuidString)"
        let eco = ["on run argv", "return item 1 of argv", "end run"]
        let perigosos = ["a'; touch \(marca); '", "$(touch \(marca))", "`touch \(marca)`", "x; touch \(marca)",
                         "\"; do shell script \"touch \(marca)\"; \"", "a\nb", "'", "\\", "ç é ã"]
        for v in perigosos {
            let linha = try! XCTUnwrap(AppleScript.comando(eco, argumentos: [v], segundos: 10))
            let r = ExecutorShell().rodar(linha)
            XCTAssertEqual(r.status, 0, v)
            XCTAssertEqual(r.saida.trimmingCharacters(in: .newlines), v.trimmingCharacters(in: .newlines), v)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marca))
        XCTAssertNil(AppleScript.comando(eco, argumentos: ["-e"], segundos: 10))
    }

    /// A conta de data do Calendário, sem o `tell`: o dia 31 não estoura o mês e o ano bissexto fecha.
    func testDataDoCalendarioMontadaDeVerdade() {
        let conta = Array(AppleScript.diaDoCalendario[0..<8]) + [
            #"return ((year of d) as text) & "-" & ((month of d as integer) as text) & "-" & ((day of d) as text)"#, "end run"]
        for (entrada, esperado) in [("2026-11-30", "2026-11-30"), ("2024-02-29", "2024-2-29"), ("2027-01-31", "2027-1-31"), ("2026-12-25", "2026-12-25")] {
            let linha = try! XCTUnwrap(AppleScript.comando(conta, argumentos: [entrada], segundos: 10))
            let r = ExecutorShell().rodar(linha)
            XCTAssertEqual(r.saida.trimmingCharacters(in: .newlines), esperado, entrada)
        }
    }

    /// Todos os scripts compilam no Mac de verdade (termos do Mail, das Notas e do Calendário existem).
    func testTodosOsScriptsCompilam() throws {
        let scripts: [(String, [String])] = [
            ("contasDoMail", AppleScript.contasDoMail), ("caixaDoMail", AppleScript.caixaDoMail),
            ("pastasDasNotas", AppleScript.pastasDasNotas), ("abrirPastaDasNotas", AppleScript.abrirPastaDasNotas),
            ("calendarioHoje", AppleScript.calendarioHoje), ("diaDoCalendario", AppleScript.diaDoCalendario),
        ]
        let saida = NSTemporaryDirectory() + "deck-compila-\(UUID().uuidString).scpt"
        defer { try? FileManager.default.removeItem(atPath: saida) }
        for (nome, linhas) in scripts {
            let r = ExecutorShell().rodar("osacompile -o \(Shell.aspas(saida)) " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " "))
            XCTAssertEqual(r.status, 0, "\(nome): \(r.saida)")
        }
    }
    #endif
}

final class EnderecosTestes: XCTestCase {
    func testLinkAceitaHttpHttpsESemEsquema() {
        XCTAssertEqual(Enderecos.link("https://github.com"), "https://github.com")
        XCTAssertEqual(Enderecos.link(" HTTP://exemplo.com.br/a?b=1 "), "HTTP://exemplo.com.br/a?b=1")
        XCTAssertEqual(Enderecos.link("youtube.com/watch?v=1"), "https://youtube.com/watch?v=1")
        XCTAssertEqual(Enderecos.link("http://localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(Enderecos.link("localhost:3000"), "http://localhost:3000")
        XCTAssertEqual(Enderecos.link("127.0.0.1:8080/x"), "http://127.0.0.1:8080/x")
        XCTAssertEqual(Enderecos.link("http://[::1]:8080"), "http://[::1]:8080")
        XCTAssertEqual(Enderecos.link("[::1]:8080"), "http://[::1]:8080")
    }

    func testLinkRecusaOResto() {
        for ruim in ["", "  ", "javascript:alert(1)", "file:///x", "mailto:a@b.com", "https://", "semponto", "a b.com", "x.com\nmais"] {
            XCTAssertNil(Enderecos.link(ruim), ruim)
        }
    }

    func testCaminho() {
        XCTAssertEqual(Enderecos.caminho("/Users/x"), "/Users/x")
        XCTAssertEqual(Enderecos.caminho("~"), NSHomeDirectory())
        XCTAssertEqual(Enderecos.caminho("~/Downloads"), NSHomeDirectory() + "/Downloads")
        XCTAssertNil(Enderecos.caminho("Downloads"))
        XCTAssertNil(Enderecos.caminho("-a"))
        XCTAssertNil(Enderecos.caminho("~outro/x"))
    }
}
