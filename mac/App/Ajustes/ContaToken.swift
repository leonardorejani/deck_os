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
}

/// Pede ao Claude o uso da semana de uma conta, com o token dela. Serve para conferir o token ao
/// adicionar e para manter o cartão em dia. O token só sai no cabeçalho de autorização, nunca em
/// texto de erro, log ou arquivo.
protocol LeitorDeUsoPorToken: Sendable {
    func ler(token: String) async -> ResultadoDoToken
}

struct ClaudeUsoPorToken: LeitorDeUsoPorToken {
    static let endereco = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func ler(token: String) async -> ResultadoDoToken {
        var req = URLRequest(url: Self.endereco, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (dados, resposta) = try await URLSession.shared.data(for: req)
            let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            if codigo == 401 || codigo == 403 { return .recusado }
            guard (200..<300).contains(codigo) else { return .semRede }
            guard let uso = Self.interpretar(dados) else { return .recusado }
            return .ok(uso)
        } catch {
            return .semRede
        }
    }

    /// `{"seven_day": {"utilization": 61.0, "resets_at": "2026-11-13T17:00:00Z"}, ...}`.
    static func interpretar(_ dados: Data) -> UsoDoToken? {
        guard let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let sete = obj["seven_day"] as? [String: Any] else { return nil }
        let u = (sete["utilization"] as? Double) ?? (sete["utilization"] as? Int).map(Double.init)
        guard let u else { return nil }
        return UsoDoToken(semana: max(0, min(100, Int(u.rounded()))), renova: (sete["resets_at"] as? String).flatMap(Datas.ler))
    }
}
