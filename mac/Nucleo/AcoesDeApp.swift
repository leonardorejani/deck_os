import Foundation

// Abrir o app numa coisa específica: a caixa de entrada de uma conta do Mail, um endereço no navegador,
// uma pasta das Notas, um dia do Calendário. O catálogo (o que cada app oferece e as escolhas, como a lista
// de contas) é descoberto no Mac de quem usa e sai por GET /api/apps/<bundle>/acoes. A tecla guarda só o id
// da ação e a escolha (`Tecla.acao`). Nada vindo da config ou do iPhone vira texto de script: os scripts são
// fixos e a escolha entra como argumento separado (`on run argv`), com aspas do shell.

/// Uma escolha dentro de uma ação (uma conta, uma pasta).
struct OpcaoDeAcao: Codable, Equatable, Sendable {
    var valor: String
    var nome: String
    /// Texto de apoio (o e-mail da conta, o serviço da pasta).
    var detalhe: String? = nil
}

/// Uma ação que o app oferece, como o editor de tecla mostra.
struct AcaoDisponivel: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    /// O que a pessoa informa: "nenhuma", "lista" (escolhe entre `opcoes`) ou "texto" (digita).
    var entrada: String
    var rotulo: String? = nil
    var exemplo: String? = nil
    var opcoes: [OpcaoDeAcao]? = nil
    /// Quando a lista não pôde ser lida (app negou a permissão, demorou), o motivo em português.
    var aviso: String? = nil
}

enum IdsDeAcao {
    static let mailCaixa = "mail-caixa"
    static let mailNovo = "mail-novo"
    static let link = "link"
    static let gmail = "gmail"
    static let notasPasta = "notas-pasta"
    static let calendarioHoje = "calendario-hoje"
    static let calendarioDia = "calendario-dia"
    static let abrirArquivo = "abrir-arquivo"
    static let reuniaoMicrofone = "reuniao-microfone"
    static let reuniaoCamera = "reuniao-camera"

    static let todos: Set<String> = [mailCaixa, mailNovo, link, gmail, notasPasta, calendarioHoje, calendarioDia, abrirArquivo,
                                     reuniaoMicrofone, reuniaoCamera]
}

// MARK: - AppleScript

enum AppleScript {
    /// Linha de shell que roda o script (linhas fixas) com `argumentos` separados, dentro do vigia de tempo.
    /// Argumento começando com "-" poderia ser lido como opção do osascript: não passa.
    static func comando(_ linhas: [String], argumentos: [String] = [], segundos: Int) -> String? {
        guard !argumentos.contains(where: { $0.hasPrefix("-") }) else { return nil }
        let osa = "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
            + argumentos.map { " " + Shell.aspas($0) }.joined()
        return Shell.limitado(osa, segundos: segundos)
    }

    /// Cada linha de uma lista é "valor<TAB>nome<TAB>detalhe".
    static func lerLista(_ saida: String) -> [OpcaoDeAcao] {
        saida.split(whereSeparator: \.isNewline).compactMap { linha in
            let c = linha.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 2, !c[0].isEmpty, !c[1].isEmpty else { return nil }
            let detalhe = c.count > 2 ? c[2].trimmingCharacters(in: .whitespaces) : ""
            return OpcaoDeAcao(valor: c[0], nome: c[1], detalhe: detalhe.isEmpty ? nil : detalhe)
        }
    }

    // O TAB nasce fora do `tell`: dentro dele, `tab` pode ser uma classe do app.
    static let contasDoMail = [
        "set t to (ASCII character 9)",
        #"tell application id "com.apple.mail""#,
        #"set saida to """#,
        "repeat with c in accounts",
        #"set e to """#,
        "try",
        "set e to item 1 of (email addresses of c)",
        "end try",
        "set saida to saida & (id of c) & t & (name of c) & t & e & linefeed",
        "end repeat",
        "return saida",
        "end tell",
    ]

    /// A caixa de entrada da conta: "INBOX" (IMAP) ou "Inbox" (Exchange), a que existir.
    static let caixaDoMail = [
        "on run argv",
        #"tell application id "com.apple.mail""#,
        "set conta to account id (item 1 of argv)",
        "set caixa to missing value",
        "try",
        #"set caixa to mailbox "INBOX" of conta"#,
        "on error",
        #"set caixa to mailbox "Inbox" of conta"#,
        "end try",
        "if (count of message viewers) is 0 then make new message viewer",
        "set selected mailboxes of front message viewer to {caixa}",
        "activate",
        "end tell",
        "end run",
    ]

    static let pastasDasNotas = [
        "set t to (ASCII character 9)",
        #"tell application id "com.apple.Notes""#,
        #"set saida to """#,
        "repeat with a in accounts",
        "repeat with f in folders of a",
        "set saida to saida & (id of f) & t & (name of f) & t & (name of a) & linefeed",
        "end repeat",
        "end repeat",
        "return saida",
        "end tell",
    ]

    static let abrirPastaDasNotas = [
        "on run argv",
        #"tell application id "com.apple.Notes""#,
        "activate",
        "show folder id (item 1 of argv)",
        "end tell",
        "end run",
    ]

    static let calendarioHoje = [
        #"tell application id "com.apple.iCal""#,
        "activate",
        "switch view to day view",
        "view calendar at (current date)",
        "end tell",
    ]

    /// A data chega como "AAAA-MM-DD" já validada. O dia vai para 1 antes de mudar o mês, para "31" não estourar.
    static let diaDoCalendario = [
        "on run argv",
        "set p to item 1 of argv",
        "set d to (current date)",
        "set day of d to 1",
        "set year of d to ((text 1 thru 4 of p) as integer)",
        "set month of d to ((text 6 thru 7 of p) as integer)",
        "set day of d to ((text 9 thru 10 of p) as integer)",
        "set time of d to 0",
        #"tell application id "com.apple.iCal""#,
        "activate",
        "switch view to day view",
        "view calendar at d",
        "end tell",
        "end run",
    ]
}

// MARK: - Endereços

enum Enderecos {
    /// Só http e https. Sem esquema ("google.com"), entra https. Qualquer outro (javascript:, file:) é recusado.
    static func link(_ texto: String) -> String? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        if !t.contains("://") {
            // "mailto:x" e "tel:1" têm esquema, só que não o de uma página: não ganham https:// na frente.
            // "localhost:3000" (porta) é endereço e passa.
            if t.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:(?!//|\d)"#, options: .regularExpression) != nil { return nil }
            // servidor local de desenvolvimento não tem https: localhost e loopback entram como http
            let local = t.range(of: #"^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(/|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
            t = (local ? "http://" : "https://") + t
        }
        let minusculo = t.lowercased()
        guard minusculo.hasPrefix("https://") || minusculo.hasPrefix("http://"),
              let url = URL(string: t), let host = url.host, host.contains(".") || host.contains(":") || host == "localhost" else { return nil }
        return t
    }

    /// A conta do Gmail: o número do `authuser` (0, 1, 2...) ou o e-mail dela.
    static func gmail(_ texto: String) -> String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if (1...2).contains(t.count), t.allSatisfy({ ("0"..."9").contains($0) }) {
            return "https://mail.google.com/mail/u/\(Int(t)!)/#inbox"
        }
        let partes = t.split(separator: "@", omittingEmptySubsequences: false)
        let proibidos = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?#&%\"'<>\\"))
        guard partes.count == 2, !partes[0].isEmpty, partes[1].contains("."), !partes[1].hasPrefix("."), !partes[1].hasSuffix("."),
              t.unicodeScalars.allSatisfy({ !proibidos.contains($0) }) else { return nil }
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "._-")
        guard let codificado = t.addingPercentEncoding(withAllowedCharacters: permitidos) else { return nil }
        return "https://mail.google.com/mail/?authuser=\(codificado)#inbox"
    }

    /// Caminho absoluto ou começando em "~". Sem isso o `open` leria "-algo" como opção.
    static func caminho(_ texto: String) -> String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/") || t == "~" || t.hasPrefix("~/") else { return nil }
        return (t as NSString).expandingTildeInPath
    }
}

// MARK: - O que cada app oferece

struct CatalogoDeAcoes: Sendable {
    let executor: any Executor

    /// Pseudo id de pacote para "o navegador padrão do Mac", que não é um app da lista.
    static let navegadorPadrao = "navegador-padrao"
    /// Quanto a leitura de uma lista espera. Passou disso (o macOS está esperando o "Permitir" da Automação), vira aviso.
    static let limiteSegundos = 8

    /// `nil` é o navegador padrão.
    func acoes(para app: AppAchado?) -> [AcaoDisponivel] {
        guard let app else { return [Self.link, Self.gmail] }
        var lista: [AcaoDisponivel] = []
        switch app.app.bundle {
        case "com.apple.mail": lista = [mailCaixa(), Self.mailNovo]
        case "com.apple.Notes": lista = [notasPasta()]
        case "com.apple.iCal": lista = [Self.calendarioHoje, Self.calendarioDia]
        default: break
        }
        if app.app.navegador { lista += [Self.link, Self.gmail] }
        // Mutar e câmera: o Zoom, o Teams e os navegadores que o Deck sabe consultar (para a aba do Meet).
        if Self.temControleDeReuniao(app.app) { lista += [Self.reuniaoMicrofone, Self.reuniaoCamera] }
        if lista.isEmpty, app.abreArquivos { lista = [Self.abrirArquivo] }
        return lista
    }

    static let reuniaoMicrofone = AcaoDisponivel(id: IdsDeAcao.reuniaoMicrofone, nome: "Mutar ou desmutar o microfone da reunião", entrada: "nenhuma")
    static let reuniaoCamera = AcaoDisponivel(id: IdsDeAcao.reuniaoCamera, nome: "Ligar ou desligar a câmera da reunião", entrada: "nenhuma")

    static func temControleDeReuniao(_ app: AppInstalado) -> Bool {
        ControleDeReuniao.alvo(app: app.valor) != nil
            && (NavegadorWeb.todos.contains { $0.idBundle == app.bundle } || ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams"].contains(app.bundle))
    }

    static let link = AcaoDisponivel(id: IdsDeAcao.link, nome: "Abrir um endereço", entrada: "texto",
                                     rotulo: "Endereço", exemplo: "https://github.com")
    static let gmail = AcaoDisponivel(id: IdsDeAcao.gmail, nome: "Abrir o Gmail de uma conta", entrada: "texto",
                                      rotulo: "Conta (número ou e-mail)", exemplo: "1 ou nome@gmail.com")
    static let mailNovo = AcaoDisponivel(id: IdsDeAcao.mailNovo, nome: "Escrever um e-mail novo", entrada: "nenhuma")
    static let calendarioHoje = AcaoDisponivel(id: IdsDeAcao.calendarioHoje, nome: "Mostrar hoje", entrada: "nenhuma")
    static let calendarioDia = AcaoDisponivel(id: IdsDeAcao.calendarioDia, nome: "Mostrar um dia", entrada: "texto",
                                              rotulo: "Dia", exemplo: "2026-12-25")
    static let abrirArquivo = AcaoDisponivel(id: IdsDeAcao.abrirArquivo, nome: "Abrir um arquivo ou pasta", entrada: "texto",
                                             rotulo: "Arquivo ou pasta", exemplo: "~/Downloads")

    private func mailCaixa() -> AcaoDisponivel {
        lista(id: IdsDeAcao.mailCaixa, nome: "Abrir a caixa de entrada de uma conta", rotulo: "Conta", app: "Mail",
              abrirEscondido: "com.apple.mail", processo: "Mail", script: AppleScript.contasDoMail,
              vazio: "Nenhuma conta configurada no Mail. Adicione uma conta no app Mail.")
    }

    private func notasPasta() -> AcaoDisponivel {
        lista(id: IdsDeAcao.notasPasta, nome: "Abrir uma pasta", rotulo: "Pasta", app: "Notas",
              abrirEscondido: "com.apple.Notes", processo: "Notes", script: AppleScript.pastasDasNotas,
              vazio: "Nenhuma pasta nas Notas.")
    }

    /// Lê a lista de dentro do app por AppleScript. App fechado abre escondido e sem tomar o foco (o script
    /// precisa dele aberto), e a permissão de Automação é pedida pelo macOS na hora, nunca antes.
    private func lista(id: String, nome: String, rotulo: String, app: String, abrirEscondido bundle: String,
                       processo: String, script: [String], vazio: String) -> AcaoDisponivel {
        var acao = AcaoDisponivel(id: id, nome: nome, entrada: "lista", rotulo: rotulo, opcoes: [])
        guard let osa = AppleScript.comando(script, segundos: Self.limiteSegundos) else { return acao }
        let abrir = "pgrep -x \(Shell.aspas(processo)) >/dev/null || open -g -j -b \(Shell.aspas(bundle)); "
        let r = executor.rodar(abrir + osa)
        if r.status == 0 {
            acao.opcoes = AppleScript.lerLista(r.saida)
            if acao.opcoes?.isEmpty == true { acao.aviso = vazio }
        } else {
            acao.aviso = Self.motivo(r, app: app)
        }
        return acao
    }

    /// O texto do erro do osascript vem no idioma do Mac: o que vale é o número do erro.
    static func motivo(_ r: SaidaShell, app: String) -> String {
        if r.status == ExecutorAcoes.statusTempoEsgotado {
            return "O macOS está esperando você permitir o Deck controlar o \(app). Toque em Permitir na janela do Mac e tente de novo."
        }
        if r.saida.contains("-1743") {
            return "O Deck não tem permissão para controlar o \(app). Libere em Ajustes do Sistema > Privacidade e Segurança > Automação."
        }
        return "Não consegui ler as opções do \(app)."
    }
}

// MARK: - Execução

extension ExecutorAcoes {
    /// Valor da tecla que manda abrir no navegador padrão do Mac, em vez de um app.
    static let navegadorPadrao = CatalogoDeAcoes.navegadorPadrao

    func abrirComAcao(_ tecla: Tecla, _ acao: AcaoDeApp) -> String? {
        let escolha = (acao.valor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch acao.id {
        case IdsDeAcao.mailCaixa:
            guard !escolha.isEmpty else { return "Escolha a conta do Mail na tecla \"\(tecla.nome)\"" }
            return rodarScript(AppleScript.caixaDoMail, [escolha], app: "Mail",
                               naoAchou: "Não achei essa conta no Mail. Escolha a conta de novo na tecla \"\(tecla.nome)\"")
        case IdsDeAcao.mailNovo:
            return rodarOpen("open -b 'com.apple.mail' 'mailto:'", app: "Mail")
        case IdsDeAcao.link:
            guard let url = Enderecos.link(escolha) else { return "O endereço da tecla \"\(tecla.nome)\" não é válido" }
            return abrirNoNavegador(url, tecla)
        case IdsDeAcao.gmail:
            guard let url = Enderecos.gmail(escolha) else {
                return "A conta do Gmail da tecla \"\(tecla.nome)\" não é válida. Use o número (0, 1, 2) ou o e-mail"
            }
            return abrirNoNavegador(url, tecla)
        case IdsDeAcao.notasPasta:
            guard !escolha.isEmpty else { return "Escolha a pasta das Notas na tecla \"\(tecla.nome)\"" }
            return rodarScript(AppleScript.abrirPastaDasNotas, [escolha], app: "Notas",
                               naoAchou: "Não achei essa pasta nas Notas. Escolha a pasta de novo na tecla \"\(tecla.nome)\"")
        case IdsDeAcao.calendarioHoje:
            return rodarScript(AppleScript.calendarioHoje, [], app: "Calendário", naoAchou: "Não consegui abrir o Calendário")
        case IdsDeAcao.calendarioDia:
            guard Roteador.dataValida(escolha) else { return "O dia da tecla \"\(tecla.nome)\" não é válido. Use AAAA-MM-DD" }
            return rodarScript(AppleScript.diaDoCalendario, [escolha], app: "Calendário", naoAchou: "Não consegui abrir o Calendário")
        case IdsDeAcao.reuniaoMicrofone:
            return controlarReuniao(tecla, .microfone)
        case IdsDeAcao.reuniaoCamera:
            return controlarReuniao(tecla, .camera)
        case IdsDeAcao.abrirArquivo:
            guard let caminho = Enderecos.caminho(escolha) else {
                return "O caminho da tecla \"\(tecla.nome)\" precisa começar com / ou ~"
            }
            guard FileManager.default.fileExists(atPath: caminho) else { return "Não achei \(escolha) neste Mac" }
            return rodarOpen("open -a \(Self.escapar(tecla.valor)) \(Self.escapar(caminho))", app: tecla.valor)
        default:
            return "Essa ação não existe nesta versão do Deck"
        }
    }

    private func abrirNoNavegador(_ url: String, _ tecla: Tecla) -> String? {
        if tecla.valor == Self.navegadorPadrao { return rodarOpen("open \(Self.escapar(url))", app: "o navegador") }
        return rodarOpen("open -a \(Self.escapar(tecla.valor)) \(Self.escapar(url))", app: tecla.valor)
    }

    private func rodarOpen(_ linha: String, app: String) -> String? {
        shell.rodar(linha).status == 0 ? nil : "Não achei o app \(app) neste Mac"
    }

    private func rodarScript(_ linhas: [String], _ argumentos: [String], app: String, naoAchou: String) -> String? {
        guard let linha = AppleScript.comando(linhas, argumentos: argumentos, segundos: limiteSegundos) else {
            return "A escolha da tecla não é válida"
        }
        let r = shell.rodar(linha)
        if r.status == 0 { return nil }
        if r.status == Self.statusTempoEsgotado || r.saida.contains("-1743") { return CatalogoDeAcoes.motivo(r, app: app) }
        if r.saida.contains("-1728") { return naoAchou }
        return "Não consegui abrir isso no \(app)"
    }
}
