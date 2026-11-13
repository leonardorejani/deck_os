import Foundation

// WhatsApp pelo navegador. Quem usa o WhatsApp Web não tem o banco do app do Mac em dia, então o Deck
// olha as abas abertas (AppleScript, sempre via Executor e com tempo limite) e lê o total de não lidas
// do título da aba, "(23) WhatsApp". O navegador não entrega a lista por conversa: só o total.

/// Navegador que o Deck sabe consultar por AppleScript.
struct NavegadorWeb: Equatable, Sendable {
    enum Estilo: Sendable { case safari, chromium }
    /// Nome do app, como o usuário vê e como o `open -a` entende.
    var nome: String
    /// Nome do processo, para saber se está aberto sem acordar o app.
    var processo: String
    var idBundle: String
    var estilo: Estilo

    static let todos = [
        NavegadorWeb(nome: "Safari", processo: "Safari", idBundle: "com.apple.Safari", estilo: .safari),
        NavegadorWeb(nome: "Google Chrome", processo: "Google Chrome", idBundle: "com.google.Chrome", estilo: .chromium),
        NavegadorWeb(nome: "Arc", processo: "Arc", idBundle: "company.thebrowser.Browser", estilo: .chromium),
        NavegadorWeb(nome: "Brave Browser", processo: "Brave Browser", idBundle: "com.brave.Browser", estilo: .chromium),
        NavegadorWeb(nome: "Microsoft Edge", processo: "Microsoft Edge", idBundle: "com.microsoft.edgemac", estilo: .chromium),
    ]

    static func chamado(_ nome: String?) -> NavegadorWeb? { todos.first { $0.nome == nome } }

    /// O Safari chama o título da aba de `name`, os de base Chromium de `title`.
    var rotuloTitulo: String { estilo == .safari ? "name" : "title" }
}

/// Uma aba do WhatsApp Web achada num navegador (janela e aba contam a partir de 1).
struct AbaWeb: Equatable, Sendable {
    var navegador: NavegadorWeb
    var janela: Int
    var aba: Int
    var titulo: String

    /// O WhatsApp Web põe o número de conversas com mensagem nova na frente do título: "(23) WhatsApp".
    var naoLidas: Int { WhatsAppWeb.naoLidas(titulo: titulo) }
}

enum WhatsAppWeb {
    static let endereco = "https://web.whatsapp.com"
    /// Quanto uma consulta a um navegador espera. Passou disso (ou o macOS está esperando o "Permitir"
    /// da Automação), a consulta cai e o estado segue com o último valor.
    static let limiteSegundos = 4

    /// "(23) WhatsApp" -> 23. Sem número na frente (nada novo), 0.
    static func naoLidas(titulo: String) -> Int {
        guard let r = titulo.range(of: #"^[^\p{L}\p{N}(]*\((\d{1,6})\+?\)"#, options: .regularExpression) else { return 0 }
        return Int(titulo[r].filter(\.isNumber)) ?? 0
    }

    /// Cada linha do resultado é "janela<TAB>aba<TAB>título", só das abas em web.whatsapp.com.
    static func lerAbas(_ saida: String, em navegador: NavegadorWeb) -> [AbaWeb] {
        saida.split(whereSeparator: \.isNewline).compactMap { linha in
            let c = linha.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard c.count == 3, let j = Int(c[0]), let a = Int(c[1]), j > 0, a > 0 else { return nil }
            return AbaWeb(navegador: navegador, janela: j, aba: a, titulo: String(c[2]))
        }
    }

    /// O navegador entra nas linhas só pelo id do pacote e pelo `pgrep`, e janela e aba são inteiros.
    /// Nada que vem do navegador vira texto de script.
    static func comandoBusca(_ n: NavegadorWeb) -> String {
        let linhas = [
            // O TAB nasce fora do `tell`: dentro dele, `tab` é a classe "aba" do navegador e sai como texto.
            "set sep to (ASCII character 9)",
            #"tell application id "\#(n.idBundle)""#,
            #"set r to """#,
            "repeat with i from 1 to count of windows",
            "repeat with j from 1 to count of tabs of window i",
            "try",
            "set t to tab j of window i",
            #"if (URL of t as text) starts with "https://web.whatsapp.com" then set r to r & i & sep & j & sep & (\#(n.rotuloTitulo) of t) & linefeed"#,
            "end try",
            "end repeat",
            "end repeat",
            "return r",
            "end tell",
        ]
        let osa = "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
        // `pgrep` primeiro: consultar um navegador fechado o abriria.
        let linha = "if pgrep -x \(Shell.aspas(n.processo)) >/dev/null; then \(osa); else echo fechado; fi"
        return Shell.limitado(linha, segundos: limiteSegundos)
    }

    /// Traz a aba para a frente: ativa a aba, sobe a janela e ativa o navegador.
    static func comandoTrazer(_ a: AbaWeb) -> String {
        let escolher = a.navegador.estilo == .safari
            ? "set current tab of window \(a.janela) to tab \(a.aba) of window \(a.janela)"
            : "set active tab index of window \(a.janela) to \(a.aba)"
        let linhas = [
            #"tell application id "\#(a.navegador.idBundle)""#,
            escolher,
            "set index of window \(a.janela) to 1",
            "activate",
            "end tell",
        ]
        return Shell.limitado("osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " "), segundos: limiteSegundos)
    }

    /// Sem aba aberta: abre o WhatsApp Web no navegador escolhido, ou no padrão do Mac.
    static func comandoAbrir(navegador: NavegadorWeb?) -> String {
        comandoAbrir(endereco: endereco, navegador: navegador)
    }

    static func comandoAbrir(endereco: String, navegador: NavegadorWeb?) -> String {
        guard let n = navegador else { return "open \(Shell.aspas(endereco))" }
        return "open -a \(Shell.aspas(n.nome)) \(Shell.aspas(endereco))"
    }

    /// O link que abre a conversa de um número direto no WhatsApp Web. Só dígitos entram (de 8 a 15), então nada vindo
    /// de fora vira parte do endereço ou do comando.
    static func enderecoDaConversa(numero: String) -> String? {
        let d = numero.filter { $0.isASCII && $0.isNumber }
        guard d == numero, (8...15).contains(d.count) else { return nil }
        return "\(endereco)/send?phone=\(d)"
    }

    enum Busca: Equatable {
        case fechado
        case abas([AbaWeb])
        case semPermissao
        case falhou
    }

    static func interpretar(status: Int32, saida: String, navegador: NavegadorWeb) -> Busca {
        let texto = saida.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 0 { return texto == "fechado" ? .fechado : .abas(lerAbas(saida, em: navegador)) }
        let t = texto.lowercased()
        if t.contains("-1743") || t.contains("not authorized") || t.contains("not allowed") { return .semPermissao }
        return .falhou
    }

    static let avisoPermissao = Aviso(fonte: "whatsapp", texto: "Não consegui olhar o navegador. Libere o controle dele para o Deck em Ajustes do Mac, Privacidade e Segurança, Automação.")
}

/// A decisão de onde ler o WhatsApp agora.
struct DecisaoWhatsApp: Equatable, Sendable {
    /// "app" ou "web".
    var origem: String
    /// Origem web: a aba achada (e nela o navegador). nil quando o WhatsApp Web não está aberto.
    var aba: AbaWeb?
    /// Origem web: o navegador fixado na config, usado para abrir quando não há aba.
    var navegadorEscolhido: NavegadorWeb?
    var aviso: Aviso?
}

/// Descobre de onde ler o WhatsApp: da config (`app` ou `web` fixos) ou sozinho (`auto`). A leitura e a
/// abertura do WhatsApp usam a mesma decisão, guardada por poucos segundos.
final class OrigemWhatsApp: @unchecked Sendable {
    /// Banco do app parado há mais que isso conta como "sem atividade".
    static let janelaAtividade: TimeInterval = 30 * 60

    private let executor: any Executor
    private let banco: String
    private let config: @Sendable () -> ConfigWhatsApp
    private let relogio: @Sendable () -> Date
    private let cache = Cache<ConfigWhatsApp, DecisaoWhatsApp>(validade: 2)

    init(executor: any Executor, banco: String,
         config: @escaping @Sendable () -> ConfigWhatsApp = { ConfigWhatsApp() },
         relogio: @escaping @Sendable () -> Date = { Date() }) {
        self.executor = executor
        self.banco = banco
        self.config = config
        self.relogio = relogio
    }

    /// O navegador fixado na config (nil: o padrão do Mac).
    func navegadorEscolhido() -> NavegadorWeb? { NavegadorWeb.chamado(config().navegador) }

    func decidir() -> DecisaoWhatsApp {
        let cfg = config()
        let agora = relogio()
        return cache.obter(chave: cfg, agora: agora) { calcular(cfg, agora) }
    }

    private func calcular(_ cfg: ConfigWhatsApp, _ agora: Date) -> DecisaoWhatsApp {
        let escolhido = NavegadorWeb.chamado(cfg.navegador)
        switch cfg.origem {
        case "app":
            return DecisaoWhatsApp(origem: "app")
        case "qr":
            return DecisaoWhatsApp(origem: "qr")
        case "web":
            let b = procurar(preferido: escolhido)
            return DecisaoWhatsApp(origem: "web", aba: b.aba, navegadorEscolhido: escolhido,
                                   aviso: b.aba == nil && b.semPermissao ? WhatsAppWeb.avisoPermissao : nil)
        default:
            // O app com banco em atividade ganha: ele dá a lista por conversa. O navegador só é consultado
            // (e só pede a Automação) quando o app está parado ou ausente.
            let estado = estadoBanco(agora)
            if estado == .ativo { return DecisaoWhatsApp(origem: "app") }
            let b = procurar(preferido: escolhido)
            if let aba = b.aba { return DecisaoWhatsApp(origem: "web", aba: aba, navegadorEscolhido: escolhido) }
            // Sem banco nenhum o app não está instalado (ou nunca entrou): quem só usa o web abre o
            // web.whatsapp.com pelo Deck sem ter de fixar a origem.
            if estado == .ausente { return DecisaoWhatsApp(origem: "web", navegadorEscolhido: escolhido) }
            return DecisaoWhatsApp(origem: "app")
        }
    }

    /// O banco (ou o arquivo de log dele, `-wal`) mexido há pouco. Arquivo que não abre ou não existe
    /// conta como parado.
    func bancoAtivo(_ agora: Date) -> Bool { estadoBanco(agora) == .ativo }

    enum EstadoBanco { case ativo, parado, ausente }

    func estadoBanco(_ agora: Date) -> EstadoBanco {
        let r = executor.rodar("stat -f %m \(Shell.aspas(banco)) \(Shell.aspas(banco + "-wal")) 2>/dev/null")
        let mudou = r.saida.split(whereSeparator: \.isNewline).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.max()
        guard let mudou else { return .ausente }
        return agora.timeIntervalSince1970 - mudou < Self.janelaAtividade ? .ativo : .parado
    }

    /// Uma aba do WhatsApp Web que já esteja aberta (no navegador escolhido primeiro), venha a leitura de onde vier.
    /// Sem cache: "Responder no Mac" quer a aba de agora, não a de dois segundos atrás.
    func abaAberta() -> AbaWeb? { procurar(preferido: navegadorEscolhido()).aba }

    /// A primeira aba do WhatsApp Web, olhando o navegador preferido primeiro. Com várias abas no mesmo
    /// navegador (o WhatsApp Web só deixa uma ativa por perfil), vale a que tem mais não lidas.
    private func procurar(preferido: NavegadorWeb?) -> (aba: AbaWeb?, semPermissao: Bool) {
        let ordem = (preferido.map { [$0] } ?? []) + NavegadorWeb.todos.filter { $0 != preferido }
        var semPermissao = false
        for n in ordem {
            let r = executor.rodar(WhatsAppWeb.comandoBusca(n))
            switch WhatsAppWeb.interpretar(status: r.status, saida: r.saida, navegador: n) {
            case .abas(let abas):
                if let melhor = abas.max(by: { $0.naoLidas < $1.naoLidas }) { return (melhor, semPermissao) }
            case .semPermissao: semPermissao = true
            case .fechado, .falhou: break
            }
        }
        return (nil, semPermissao)
    }
}

/// A leitura do WhatsApp que escolhe a fonte: banco do app ou aba do navegador.
struct FonteWhatsAppEscolhida: Sendable {
    var origem: OrigemWhatsApp
    var app: FonteWhatsApp
    /// O WhatsApp por QR (ajudante). Nil: sem ele, a origem "qr" só avisa que não está disponível.
    var qr: PonteWhatsAppQR? = nil

    func ler() -> Leitura<WhatsAppDados?> {
        let d = origem.decidir()
        if d.origem == "qr" {
            guard let qr else {
                return Leitura(valor: nil, aviso: Aviso(fonte: "whatsapp", texto: "O WhatsApp por QR não está disponível nesta versão do Deck."))
            }
            return qr.ler()
        }
        // Saiu da origem QR: a conexão não fica ocupando um dos 4 aparelhos do WhatsApp à toa.
        if let qr, qr.ligada { qr.desligar() }
        guard d.origem == "web" else {
            var l = app.ler()
            l.valor?.resumo.origem = "app"
            return l
        }
        let resumo = ResumoWhatsApp(total: d.aba?.naoLidas ?? 0, conversas: 0, origem: "web",
                                    navegador: (d.aba?.navegador ?? d.navegadorEscolhido)?.nome, aberto: d.aba != nil)
        return Leitura(valor: WhatsAppDados(resumo: resumo, conversas: []), aviso: d.aviso)
    }
}

/// O resultado de "Responder no Mac".
enum AberturaDeConversa: Equatable, Sendable {
    /// Abriu a conversa. `aviso` diz o que a pessoa ainda precisa fazer (grupo, ou número que não se achou).
    case aberta(aviso: String?)
    case falhou(String)
}

enum AberturaWhatsApp: Equatable, Sendable {
    /// A origem é o app: quem chamou abre o app do jeito de sempre.
    case naoEWeb
    case aberto
    case falhou(String)
}

/// "Abrir no Mac", "Responder no Mac" e a tecla do WhatsApp, quando a origem é o WhatsApp Web: traz a aba
/// que já está aberta, ou abre web.whatsapp.com.
struct AbridorWhatsApp: Sendable {
    var origem: OrigemWhatsApp
    var executor: any Executor
    /// Quem escreve na busca do WhatsApp Web (Acessibilidade). Nil: sem busca, a aba só vem para a frente.
    var busca: (any BuscaNaPagina)? = nil
    var dormir: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    static let erro = "Não consegui abrir o WhatsApp Web no navegador."

    static let avisoDoGrupo = "Abri o WhatsApp Web, mas não consegui buscar o grupo sozinho. Procure o grupo na lista."
    static let avisoSemNumero = "Abri o WhatsApp Web, mas não consegui buscar a conversa sozinho. Procure ela na lista."
    static let avisoSemAcesso = "Abri o WhatsApp Web. Libere a Acessibilidade para o Deck em Ajustes do Mac, Privacidade e Segurança, e ele abre a conversa sozinho. Por enquanto, procure ela na lista."

    /// "Responder no Mac" (13/11/2026): a aba que já está aberta vem para a frente e a conversa abre pela busca do próprio
    /// WhatsApp Web (Acessibilidade), sem trocar o endereço da aba nem recarregar a página. Só sem aba aberta se abre uma
    /// nova: contato com número vai direto em /send?phone=, o resto abre o WhatsApp Web e busca depois de carregar.
    /// Sem a busca (sem acesso, ou o campo não apareceu) a aba fica na frente e o aviso diz para escolher na lista.
    func abrirConversa(numero: String?, grupo: Bool, nome: String? = nil) -> AberturaDeConversa {
        let termo = CampoDoWhatsApp.termo(nome: nome, numero: numero)
        if let aba = origem.abaAberta(), executor.rodar(WhatsAppWeb.comandoTrazer(aba)).status == 0 {
            dormir(0.3) // o navegador leva um instante para passar a aba para a frente
            return .aberta(aviso: buscar(termo, em: aba.navegador, aguardar: 2, grupo: grupo))
        }
        // Sem aba (ou ela fechou nesse meio tempo): abre uma nova.
        let link = grupo ? nil : numero.flatMap { WhatsAppWeb.enderecoDaConversa(numero: $0) }
        let r = executor.rodar(WhatsAppWeb.comandoAbrir(endereco: link ?? WhatsAppWeb.endereco, navegador: origem.navegadorEscolhido()))
        guard r.status == 0 else { return .falhou(Self.erro) }
        if link != nil { return .aberta(aviso: nil) }
        // Sem link direto: espera a página carregar e busca pelo nome.
        guard let termo else { return .aberta(aviso: grupo ? Self.avisoDoGrupo : Self.avisoSemNumero) }
        var navegador = origem.navegadorEscolhido()
        if navegador == nil {
            for _ in 0..<6 {
                dormir(1)
                if let aba = origem.abaAberta() { navegador = aba.navegador; break }
            }
        }
        guard let navegador else { return .aberta(aviso: grupo ? Self.avisoDoGrupo : Self.avisoSemNumero) }
        return .aberta(aviso: buscar(termo, em: navegador, aguardar: 10, grupo: grupo))
    }

    /// Escreve na busca do WhatsApp Web. nil: abriu. Senão, o aviso do que a pessoa ainda precisa fazer.
    private func buscar(_ termo: String?, em navegador: NavegadorWeb, aguardar: TimeInterval, grupo: Bool) -> String? {
        let procure = grupo ? Self.avisoDoGrupo : Self.avisoSemNumero
        guard let termo, let busca, let pid = LeitorDeMeetAX.pid(navegador, executor: executor) else { return procure }
        switch busca.pesquisar(pid: pid, texto: termo, aguardar: aguardar) {
        case .aberta: return nil
        case .semAcesso: return Self.avisoSemAcesso
        case .semCampo, .ambiguo, .naoFocou: return procure
        }
    }

    func abrir() -> AberturaWhatsApp {
        let d = origem.decidir()
        guard d.origem == "web" else { return .naoEWeb }
        if let aba = d.aba, executor.rodar(WhatsAppWeb.comandoTrazer(aba)).status == 0 { return .aberto }
        // Sem aba, ou a aba fechou nesse meio tempo: abre uma nova.
        let r = executor.rodar(WhatsAppWeb.comandoAbrir(navegador: d.aba?.navegador ?? d.navegadorEscolhido))
        return r.status == 0 ? .aberto : .falhou(Self.erro)
    }
}
