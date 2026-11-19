import Foundation

// Aprovar pedidos de permissão do Claude Code pelo iPhone (SPEC 13, item de 19/11/2026).
// O molde é o PhoneBox (MIT, github.com/ersinkoc/phonebox, Ersin KOÇ, agent/PhoneBox.Agent: ClaudeHook.cs e ApprovalStore.cs):
// um gancho PermissionRequest no settings.json do Claude Code manda cada pedido para o Mac, o Mac mostra Permitir e
// Negar no iPhone e devolve a resposta como saída do gancho. Aqui o código é próprio, só a ideia vem de lá.

/// O que o iPhone mostra de um pedido de permissão: o projeto, o que o Claude quer fazer e quanto tempo resta.
struct PedidoDeAprovacao: Codable, Equatable, Sendable {
    var id: String
    /// A pasta do projeto (o nome só, sem caminho).
    var projeto: String
    /// O nome da ferramenta do Claude Code ("Bash", "Edit", "WebFetch", "mcp__...").
    var ferramenta: String
    /// O que ele quer fazer, em português ("Rodar um comando").
    var titulo: String
    /// O comando, o arquivo ou o endereço, curto e sem segredos.
    var resumo: String
    /// Segundos até o pedido vencer e o terminal voltar a perguntar.
    var restante: Int
}

enum DecisaoDeAprovacao: String, Sendable {
    case permitir = "allow"
    case negar = "deny"
}

/// Os pedidos esperando resposta. O gancho abre um, o iPhone responde, o gancho recebe a decisão. Sem iPhone recente, sem
/// resposta no prazo ou com o terminal respondendo antes, não há decisão: o gancho não imprime nada e o Claude Code
/// pergunta no terminal, como sempre (falha aberta).
final class Aprovacoes: @unchecked Sendable {
    /// Prazo padrão de um pedido, em segundos.
    static let prazoPadrao: TimeInterval = 90
    /// O iPhone conta como "ali" se falou com o Mac nesse tempo (ele pede o estado a cada segundo).
    static let janelaDoIphone: TimeInterval = 12
    /// Nunca mais que isso esperando: o resto cai no terminal.
    static let limiteDePedidos = 8

    /// Um pedido aberto. Quem abriu espera por `esperar` e pode `cancelar` se o gancho foi embora.
    final class Pendente: @unchecked Sendable {
        let id: String
        fileprivate let projeto: String, ferramenta: String, titulo: String, resumo: String
        fileprivate let vence: Date
        fileprivate let sinal = DispatchSemaphore(value: 0)
        fileprivate var decisao: DecisaoDeAprovacao?
        fileprivate var fechado = false
        fileprivate init(id: String, projeto: String, ferramenta: String, titulo: String, resumo: String, vence: Date) {
            self.id = id; self.projeto = projeto; self.ferramenta = ferramenta; self.titulo = titulo; self.resumo = resumo; self.vence = vence
        }
    }

    private let trava = NSLock()
    private let relogio: @Sendable () -> Date
    private var abertos: [String: Pendente] = [:]
    private var ordem: [String] = []
    private var iphoneVisto: Date?

    init(relogio: @escaping @Sendable () -> Date = { Date() }) { self.relogio = relogio }

    /// O iPhone pediu o estado agora. Quem chama é o roteador, a cada GET /api/estado autenticado.
    func iphoneApareceu() {
        trava.lock(); defer { trava.unlock() }
        iphoneVisto = relogio()
    }

    var iphoneRecente: Bool {
        trava.lock(); defer { trava.unlock() }
        guard let visto = iphoneVisto else { return false }
        return relogio().timeIntervalSince(visto) <= Self.janelaDoIphone
    }

    /// Abre um pedido. Nil: não há iPhone recente ou a fila está cheia, e o terminal pergunta como sempre.
    func abrir(projeto: String, ferramenta: String, titulo: String, resumo: String, prazo: TimeInterval = Aprovacoes.prazoPadrao) -> Pendente? {
        trava.lock(); defer { trava.unlock() }
        guard let visto = iphoneVisto, relogio().timeIntervalSince(visto) <= Self.janelaDoIphone,
              abertos.count < Self.limiteDePedidos, prazo > 0 else { return nil }
        let p = Pendente(id: Self.novoId(), projeto: projeto, ferramenta: ferramenta, titulo: titulo, resumo: resumo,
                         vence: relogio().addingTimeInterval(prazo))
        abertos[p.id] = p
        ordem.append(p.id)
        return p
    }

    /// Espera a decisão (ou o prazo, ou o cancelamento) e tira o pedido da lista. Bloqueia: roda fora da tela e fora da fila de rede.
    func esperar(_ p: Pendente) -> DecisaoDeAprovacao? {
        let restante = max(0, p.vence.timeIntervalSince(relogio()))
        _ = p.sinal.wait(timeout: .now() + restante)
        trava.lock(); defer { trava.unlock() }
        // A decisão que chegou antes de o relógio acabar vale, mesmo que a espera tenha estourado no mesmo instante.
        p.fechado = true
        abertos[p.id] = nil
        ordem.removeAll { $0 == p.id }
        return p.decisao
    }

    /// O gancho foi embora (o terminal respondeu antes, ou o Claude Code desistiu): o pedido some do iPhone.
    func cancelar(_ id: String) {
        trava.lock()
        let p = abertos[id]
        if let p, !p.fechado, p.decisao == nil { p.fechado = true }
        trava.unlock()
        p?.sinal.signal()
    }

    /// Permitir ou Negar vindo do iPhone. Falso: o pedido não existe mais (venceu, foi cancelado ou já foi respondido).
    @discardableResult
    func decidir(_ id: String, _ decisao: DecisaoDeAprovacao) -> Bool {
        trava.lock()
        guard let p = abertos[id], !p.fechado, p.decisao == nil, p.vence > relogio() else { trava.unlock(); return false }
        p.decisao = decisao
        trava.unlock()
        p.sinal.signal()
        return true
    }

    /// Os pedidos que o iPhone ainda pode responder, do mais antigo ao mais novo.
    func pendentes() -> [PedidoDeAprovacao] {
        trava.lock(); defer { trava.unlock() }
        let agora = relogio()
        return ordem.compactMap { abertos[$0] }.filter { !$0.fechado && $0.decisao == nil && $0.vence > agora }.map {
            PedidoDeAprovacao(id: $0.id, projeto: $0.projeto, ferramenta: $0.ferramenta, titulo: $0.titulo, resumo: $0.resumo,
                              restante: Int($0.vence.timeIntervalSince(agora).rounded(.up)))
        }
    }

    static func novoId() -> String {
        var b = [UInt8](repeating: 0, count: 6)
        for i in b.indices { b[i] = UInt8.random(in: 0...255) }
        return b.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - O que o Claude Code manda e o que ele espera de volta

/// O formato do gancho PermissionRequest (doc oficial do Claude Code, code.claude.com/docs/en/hooks): entrada em JSON na stdin com
/// `tool_name`, `tool_input`, `cwd` e `session_id`. Saída `hookSpecificOutput.decision.behavior` = allow ou deny. Sem saída
/// (exit 0 e nada impresso), o fluxo de permissão segue como se o gancho não existisse.
enum GanchoDoClaude {
    struct Entrada: Equatable {
        var projeto: String
        var ferramenta: String
        var titulo: String
        var resumo: String
    }

    static let limiteDoResumo = 300

    /// Lê a entrada do gancho. Nil: não é um pedido que o iPhone possa responder (JSON estranho, ou AskUserQuestion, que é
    /// uma pergunta e não uma permissão: "Permitir" só abriria a mesma pergunta no terminal).
    static func ler(_ corpo: Data) -> Entrada? {
        guard let obj = (try? JSONSerialization.jsonObject(with: corpo)) as? [String: Any],
              let ferramenta = obj["tool_name"] as? String, !ferramenta.isEmpty, ferramenta != "AskUserQuestion" else { return nil }
        let entrada = obj["tool_input"] as? [String: Any] ?? [:]
        let cwd = obj["cwd"] as? String ?? ""
        return Entrada(projeto: projeto(de: cwd), ferramenta: ferramenta, titulo: titulo(ferramenta),
                       resumo: Mascara.segredos(resumo(ferramenta, entrada), limite: limiteDoResumo))
    }

    /// O nome da pasta do projeto. Numa worktree (`<raiz>/.claude/worktrees/<nome>`) vale a raiz, como em `FonteSessoes`.
    static func projeto(de cwd: String) -> String {
        let raiz = cwd.components(separatedBy: "/.claude/worktrees/").first ?? cwd
        return raiz.split(separator: "/").last.map(String.init) ?? ""
    }

    static func titulo(_ ferramenta: String) -> String {
        switch ferramenta {
        case "Bash": return "Rodar um comando"
        case "Edit", "MultiEdit": return "Editar um arquivo"
        case "Write": return "Criar um arquivo"
        case "Read": return "Ler um arquivo"
        case "NotebookEdit": return "Editar um caderno"
        case "WebFetch": return "Abrir um endereço"
        case "WebSearch": return "Buscar na web"
        default:
            if ferramenta.hasPrefix("mcp__") {
                let partes = ferramenta.dropFirst(5).components(separatedBy: "__")
                return "Usar " + partes.joined(separator: ": ")
            }
            return "Usar " + ferramenta
        }
    }

    /// Uma linha curta do que a ferramenta vai fazer: o comando, o arquivo, o endereço ou a busca.
    static func resumo(_ ferramenta: String, _ entrada: [String: Any]) -> String {
        func texto(_ k: String) -> String? { (entrada[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let achado: String?
        switch ferramenta {
        case "Bash": achado = texto("command")
        case "Edit", "MultiEdit", "Write", "Read": achado = texto("file_path")
        case "NotebookEdit": achado = texto("notebook_path") ?? texto("file_path")
        case "WebFetch": achado = texto("url")
        case "WebSearch": achado = texto("query")
        default: achado = nil
        }
        if let achado { return achado.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Ferramenta sem campo conhecido: o primeiro texto do pedido, em vez de despejar o JSON inteiro.
        let primeiro = entrada.keys.sorted().compactMap { texto($0) }.first
        return primeiro?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// O que o gancho imprime para o Claude Code.
    static func saida(_ d: DecisaoDeAprovacao) -> Data {
        var decisao: [String: Any] = ["behavior": d.rawValue]
        if d == .negar { decisao["message"] = "Negado pelo Deck, no iPhone." }
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decisao]]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }
}
