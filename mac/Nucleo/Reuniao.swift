import Foundation

/// Link de reunião de vídeo no evento da agenda (Meet, Zoom ou Teams) e a abertura dele no Mac.
enum Reuniao {
    enum Servico: String, Sendable { case meet, zoom, teams }

    /// Só endereço seguro (https) de um desses serviços. É isso que o Mac aceita abrir a pedido do iPhone:
    /// o iPhone nunca manda o Mac abrir um endereço qualquer.
    static func servico(de url: URL) -> Servico? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil else { return nil }
        if host == "meet.google.com" { return .meet }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return .zoom }
        if host == "teams.microsoft.com" || host == "teams.live.com" { return .teams }
        return nil
    }

    static func validar(_ texto: String) -> (url: URL, servico: Servico)? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, limpo.count <= 2000, let url = URL(string: limpo), let s = servico(de: url) else { return nil }
        return (url, s)
    }

    /// O primeiro link de reunião dentre os textos do evento (endereço do evento, local, notas), na ordem dada.
    static func achar(em textos: [String?]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https://[^\s<>"'\)\]]+"#) else { return nil }
        for texto in textos.compactMap({ $0 }) {
            let tudo = NSRange(texto.startIndex..., in: texto)
            for m in regex.matches(in: texto, range: tudo) {
                guard let r = Range(m.range, in: texto) else { continue }
                let candidato = String(texto[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                if validar(candidato) != nil { return candidato }
            }
        }
        return nil
    }

    /// O endereço que abre direto no app do Zoom: zoommtg://<servidor>/join?confno=<número>&pwd=<senha>.
    /// Só vale para link de sala numerada (/j/<número>). Outro formato abre no navegador.
    static func enderecoDoAppZoom(_ url: URL) -> String? {
        guard servico(de: url) == .zoom, let host = url.host else { return nil }
        let partes = url.path.split(separator: "/").map(String.init)
        guard partes.count >= 2, partes[0] == "j", (9...12).contains(partes[1].count), partes[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var fim = "confno=\(partes[1])"
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value,
           !pwd.isEmpty, pwd.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) {
            fim += "&pwd=\(pwd)"
        }
        return "zoommtg://\(host)/join?\(fim)"
    }
}

/// Quem abre a reunião no Mac. Devolve o texto do erro para mostrar no iPhone, ou nil se deu certo.
protocol ProvedorDeReuniao: Sendable {
    func entrar(_ link: String) -> String?
}

/// Meet e Teams abrem no navegador padrão do Mac. O Zoom abre no app do Zoom se ele estiver instalado
/// neste Mac e no navegador se não (decisão do Leonardo, 11/11/2026). Nada disso é fixo: vale o que o Mac de quem usa tem.
struct AbridorDeReuniao: ProvedorDeReuniao {
    let shell: Executor

    func entrar(_ link: String) -> String? {
        guard let (url, servico) = Reuniao.validar(link) else { return "Esse link não é de uma reunião do Meet, do Zoom ou do Teams." }
        if servico == .zoom, let app = Reuniao.enderecoDoAppZoom(url), zoomInstalado(),
           shell.rodar("open \(ExecutorAcoes.escapar(app))").status == 0 {
            return nil
        }
        let r = shell.rodar("open \(ExecutorAcoes.escapar(url.absoluteString))")
        return r.status == 0 ? nil : "O Mac não conseguiu abrir o link da reunião."
    }

    func zoomInstalado() -> Bool {
        let r = shell.rodar("mdfind \"kMDItemCFBundleIdentifier == 'us.zoom.xos'\"")
        return r.status == 0 && !r.saida.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Mutar e ligar a câmera numa reunião

/// Mutar o microfone e ligar ou desligar a câmera no Meet, no Zoom e no Teams, por uma tecla do painel.
/// O Deck só ALTERNA: aperta o atalho do app e não sabe dizer se o microfone ficou mutado ou não. Nenhum dos três
/// entrega esse estado sem espiar a tela a cada segundo (Acessibilidade) ou sem o navegador liberar JavaScript por
/// Apple Events, e o macOS pede essas permissões na hora, nunca em lista de cara (invariante 12). Por isso a tecla
/// não mostra "mutado": quem confirma é o próprio app da reunião.
enum ControleDeReuniao {
    enum Item: Sendable { case microfone, camera }

    /// A tecla "Google Meet (navegador)": não é um app instalado, é a sala aberta em qualquer navegador.
    static let valorDoMeet = "Google Meet"
    static let idDoMeet = "deck-meet-navegador"

    enum Alvo: Equatable, Sendable {
        /// Meet no navegador: o atalho só vale na aba do Meet, então ela vem para a frente antes.
        case meet(NavegadorWeb)
        /// Meet no navegador sem dizer qual: o Deck procura a sala aberta em qualquer navegador que ele sabe consultar.
        case meetNoNavegador
        case zoom
        case teams
    }

    /// Qual serviço a tecla controla, pelo nome do app dela: um navegador que o Deck sabe consultar, o Zoom ou o Teams.
    static func alvo(app nome: String) -> Alvo? {
        if nome == valorDoMeet { return .meetNoNavegador }
        if let n = NavegadorWeb.chamado(nome) { return .meet(n) }
        let baixo = nome.lowercased()
        if baixo.contains("zoom") { return .zoom }
        if baixo.contains("teams") { return .teams }
        return nil
    }

    /// Atalhos de cada app: Meet (Cmd+D microfone, Cmd+E câmera), Zoom (Cmd+Shift+A e Cmd+Shift+V)
    /// e Teams (Cmd+Shift+M e Cmd+Shift+O). Valem com a janela da reunião na frente.
    static func atalho(_ alvo: Alvo, _ item: Item) -> String {
        switch (alvo, item) {
        case (.meet, .microfone), (.meetNoNavegador, .microfone): return "cmd+d"
        case (.meet, .camera), (.meetNoNavegador, .camera): return "cmd+e"
        case (.zoom, .microfone): return "cmd+shift+a"
        case (.zoom, .camera): return "cmd+shift+v"
        case (.teams, .microfone): return "cmd+shift+m"
        case (.teams, .camera): return "cmd+shift+o"
        }
    }

    /// Aba de uma reunião de verdade (meet.google.com/abc-defg-hij), não a página inicial do Meet.
    static func ehSalaDoMeet(_ url: String) -> Bool {
        url.range(of: #"^https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}([/?#]|$)"#, options: .regularExpression) != nil
    }

    /// Cada linha é "janela<TAB>aba<TAB>endereço" das abas do Meet. Só o id do pacote entra no script (fixo).
    static func comandoBusca(_ n: NavegadorWeb) -> String {
        let linhas = [
            "set sep to (ASCII character 9)",
            #"tell application id "\#(n.idBundle)""#,
            #"set r to """#,
            "repeat with i from 1 to count of windows",
            "repeat with j from 1 to count of tabs of window i",
            "try",
            "set t to tab j of window i",
            #"if (URL of t as text) starts with "https://meet.google.com/" then set r to r & i & sep & j & sep & (URL of t as text) & linefeed"#,
            "end try",
            "end repeat",
            "end repeat",
            "return r",
            "end tell",
        ]
        let osa = "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
        // `pgrep` primeiro: consultar um navegador fechado o abriria.
        return Shell.limitado("if pgrep -x \(Shell.aspas(n.processo)) >/dev/null; then \(osa); else echo fechado; fi", segundos: WhatsAppWeb.limiteSegundos)
    }

    /// O app está aberto neste Mac? (O Zoom e o Teams só têm atalho com a reunião rolando, então fechado já é erro.)
    static func comandoAberto(_ alvo: Alvo) -> String? {
        switch alvo {
        case .meet, .meetNoNavegador: return nil
        case .zoom: return "pgrep -x 'zoom.us' >/dev/null"
        case .teams: return "pgrep -x 'MSTeams' >/dev/null || pgrep -x 'Microsoft Teams' >/dev/null"
        }
    }
}

extension ExecutorAcoes {
    /// Acha a aba da sala do Meet em qualquer navegador aberto e a põe na frente. Devolve o erro, ou nil se deu certo.
    func trazerSalaDoMeet() -> String? {
        var semPermissao: NavegadorWeb?
        for navegador in NavegadorWeb.todos {
            let r = shell.rodar(ControleDeReuniao.comandoBusca(navegador))
            if r.status == Self.statusTempoEsgotado { return CatalogoDeAcoes.motivo(r, app: navegador.nome) }
            switch WhatsAppWeb.interpretar(status: r.status, saida: r.saida, navegador: navegador) {
            case .semPermissao: semPermissao = semPermissao ?? navegador
            case .fechado, .falhou: continue
            case .abas(let abas):
                guard let sala = abas.first(where: { ControleDeReuniao.ehSalaDoMeet($0.titulo) }) else { continue }
                return shell.rodar(WhatsAppWeb.comandoTrazer(sala)).status == 0 ? nil : "Não consegui trazer a aba do Meet para a frente"
            }
        }
        if let n = semPermissao { return CatalogoDeAcoes.motivo(SaidaShell(status: 1, saida: "-1743"), app: n.nome) }
        return "Não achei uma reunião do Meet aberta no navegador. Entre na sala e tente de novo"
    }

    /// Folga entre trazer o app para a frente e apertar o atalho: sem ela a tecla cai no app que estava na frente.
    static let esperaDoFoco = "sleep 0.4"

    func controlarReuniao(_ tecla: Tecla, _ item: ControleDeReuniao.Item) -> String? {
        guard let alvo = ControleDeReuniao.alvo(app: tecla.valor) else {
            return "A tecla \"\(tecla.nome)\" precisa ser de um navegador, do Zoom ou do Teams"
        }
        guard let combinacao = Teclas.ler(ControleDeReuniao.atalho(alvo, item)) else { return "Não entendi o atalho da reunião" }
        guard temAcessibilidade() else { return Self.erroAcessibilidade }
        switch alvo {
        case .meet(let navegador):
            let r = shell.rodar(ControleDeReuniao.comandoBusca(navegador))
            if r.status == Self.statusTempoEsgotado { return CatalogoDeAcoes.motivo(r, app: navegador.nome) }
            switch WhatsAppWeb.interpretar(status: r.status, saida: r.saida, navegador: navegador) {
            case .fechado: return "O \(navegador.nome) está fechado. Entre na reunião do Meet e tente de novo"
            case .semPermissao: return CatalogoDeAcoes.motivo(SaidaShell(status: 1, saida: "-1743"), app: navegador.nome)
            case .falhou: return "Não consegui olhar as abas do \(navegador.nome)"
            case .abas(let abas):
                guard let sala = abas.first(where: { ControleDeReuniao.ehSalaDoMeet($0.titulo) }) else {
                    return "Não achei uma reunião do Meet aberta no \(navegador.nome)"
                }
                guard shell.rodar(WhatsAppWeb.comandoTrazer(sala)).status == 0 else { return "Não consegui trazer a aba do Meet para a frente" }
            }
        case .meetNoNavegador:
            if let erro = trazerSalaDoMeet() { return erro }
        case .zoom, .teams:
            let nome = alvo == .zoom ? "Zoom" : "Teams"
            if let aberto = ControleDeReuniao.comandoAberto(alvo), shell.rodar(aberto).status != 0 {
                return "O \(nome) não está aberto. Entre na reunião e tente de novo"
            }
            guard shell.rodar("open -a \(Self.escapar(tecla.valor))").status == 0 else { return "Não achei o app \(tecla.valor) neste Mac" }
        }
        _ = shell.rodar(Self.esperaDoFoco)
        enviarTecla(combinacao)
        return nil
    }
}
