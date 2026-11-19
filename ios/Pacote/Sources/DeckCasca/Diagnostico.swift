import Foundation

/// Por que o iPhone não está falando com o Mac. A tela "Mac desconectado" mostra o texto em vez de um erro genérico.
/// O painel (painel/canal.js, `causaDaFalha`) diz as mesmas frases para o HTTPS. Ideia do ciclo de reconexão e do
/// diagnóstico por categoria: WinDock, docs/SECURE_CONNECTIONS.md (MIT, https://github.com/Nmdbnk/WinDock), reescrita aqui.
public enum CausaDaConexao: Equatable, Sendable {
    /// O Mac não respondeu (desligado, fora de alcance, Deck fechado).
    case macIndisponivel
    /// O Mac não reconhece mais o código deste iPhone (ele gerou outro).
    case codigoExpirou
    /// Só aparecem Macs que não conhecem este iPhone: o Mac pareado não é o que está por perto.
    case identidadeMudou

    public func texto(tentativa: Int? = nil) -> String {
        switch self {
        case .macIndisponivel: return "Mac indisponível. Tentando de novo." + (tentativa.map { " Tentativa \($0)." } ?? "")
        case .codigoExpirou: return "O código expirou. Leia o QR de novo no Mac."
        case .identidadeMudou: return "A identidade do Mac mudou. Pareie de novo."
        }
    }
}

/// O espaçamento das novas tentativas: 1, 2, 4, 8, 16 e 30 s, e fica em 30. Sem rajada de pedidos.
public enum EscalaDeEspera {
    public static let degraus: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    /// A espera depois da falha de número `falhas` (1 é a primeira): 1, 2, 4, 8, 16, 30, 30...
    public static func degrau(_ falhas: Int) -> TimeInterval {
        degraus[min(max(falhas, 1), degraus.count) - 1]
    }
}
