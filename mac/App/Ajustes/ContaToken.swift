import Foundation

/// O que a conferência do token devolve: o uso da semana da conta (o mesmo que o cartão mostra).
struct UsoDoToken: Equatable {
    var semana: Int
    var renova: Date?
}

enum ResultadoDoToken: Equatable {
    case ok(UsoDoToken)
    case recusado
    case semRede
    case inesperado
}

/// Pede ao Claude o uso da semana de uma conta, com o token dela. Serve para conferir o token ao
/// adicionar e para manter o cartão em dia. O token só sai no cabeçalho de autorização, nunca em
/// texto de erro, log ou arquivo.
protocol LeitorDeUsoPorToken: Sendable {
    func ler(token: String) async -> ResultadoDoToken
}

/// O token de "claude setup-token" só tem o escopo user:inference. O endereço de uso
/// (/api/oauth/usage) pede user:profile e responde 403 para ele, então não serve. O que serve é o
/// que o próprio Claude Code usa: qualquer resposta de /v1/messages traz o uso da conta nos
/// cabeçalhos anthropic-ratelimit-unified-7d-utilization (fração de 0 a 1) e -7d-reset (epoch).
/// Por isso a leitura é um pedido de 1 token ao modelo mais barato.
struct ClaudeUsoPorToken: LeitorDeUsoPorToken {
    static let endereco = URL(string: "https://api.anthropic.com/v1/messages")!
    static let modelo = "claude-haiku-4-5"

    func ler(token: String) async -> ResultadoDoToken {
        var req = URLRequest(url: Self.endereco, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let corpo: [String: Any] = [
            "model": Self.modelo, "max_tokens": 1,
            "system": "You are Claude Code, Anthropic's official CLI for Claude.",
            "messages": [["role": "user", "content": "oi"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        do {
            let (_, resposta) = try await URLSession.shared.data(for: req)
            guard let http = resposta as? HTTPURLResponse else { return .semRede }
            var cab: [String: String] = [:]
            for (k, v) in http.allHeaderFields { if let k = k as? String, let v = v as? String { cab[k.lowercased()] = v } }
            return Self.interpretar(status: http.statusCode, cabecalhos: cab)
        } catch {
            return .semRede
        }
    }

    /// Com o cabeçalho do uso, vale qualquer status (até o 429 de quem estourou o limite traz o uso).
    /// Sem ele: 401 e 403 são token recusado, 5xx e 429 sem cabeçalho são o Claude fora do ar
    /// (tenta depois) e o resto é resposta que o Deck não entende.
    static func interpretar(status: Int, cabecalhos: [String: String]) -> ResultadoDoToken {
        if let bruto = cabecalhos["anthropic-ratelimit-unified-7d-utilization"], let fracao = Double(bruto) {
            let reset = cabecalhos["anthropic-ratelimit-unified-7d-reset"].flatMap(Double.init).flatMap(Numero.epoch)
            return .ok(UsoDoToken(semana: Numero.percentual(fracao * 100), renova: reset))
        }
        if status == 401 || status == 403 { return .recusado }
        if status == 429 || status >= 500 { return .semRede }
        return .inesperado
    }
}

/// Guarda a última leitura de cada token por alguns minutos. A tela chama a cada 30 s, e cada leitura
/// gasta um pedido de verdade: sem isso seriam quase 3 mil por dia por conta.
final class LeitorComCache: LeitorDeUsoPorToken, @unchecked Sendable {
    private let base: LeitorDeUsoPorToken
    private let validade: TimeInterval
    private let agora: @Sendable () -> Date
    private let trava = NSLock()
    private var guardado: [String: (quando: Date, uso: UsoDoToken)] = [:]

    init(_ base: LeitorDeUsoPorToken = ClaudeUsoPorToken(), validade: TimeInterval = 300, agora: @escaping @Sendable () -> Date = Date.init) {
        self.base = base
        self.validade = validade
        self.agora = agora
    }

    func ler(token: String) async -> ResultadoDoToken {
        let t = agora()
        trava.lock()
        let achado = guardado[token]
        trava.unlock()
        if let achado, t.timeIntervalSince(achado.quando) < validade { return .ok(achado.uso) }
        let r = await base.ler(token: token)
        trava.lock()
        if case .ok(let uso) = r { guardado[token] = (t, uso) } else { guardado[token] = nil }
        trava.unlock()
        return r
    }
}

/// O token de uma conta da troca de contas (`~/.config/claude-account/profiles/<perfil>.json`), quando
/// ela foi criada com "claude setup-token" (type oauth_token). O token mora no Chaveiro, num item
/// que o próprio arquivo aponta. Quem lê é o /usr/bin/security, que o item já aceita sem pedir senha.
enum TokenDoPerfil {
    static func ler(perfil: String, casa: URL) -> String? {
        guard ContasAchadas.perfilValido(perfil) else { return nil }
        let arquivo = casa.appendingPathComponent(".config/claude-account/profiles/\(perfil).json")
        guard let dados = try? Data(contentsOf: arquivo),
              let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              obj["type"] as? String == "oauth_token",
              let servico = obj["keychainService"] as? String, !servico.isEmpty else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", servico, "-w"]
        let saida = Pipe()
        p.standardOutput = saida
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let dadosToken = saida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let t = String(data: dadosToken, encoding: .utf8) else { return nil }
        let limpo = TokenClaude.limpar(t)
        return limpo.hasPrefix(TokenClaude.prefixo) ? limpo : nil
    }
}
