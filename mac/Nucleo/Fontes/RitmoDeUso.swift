import Foundation

/// O ritmo de uma janela de limite: onde o uso deveria estar agora, aonde ele chega até renovar
/// e se vale um aviso. Conta pura sobre o percentual, a hora de renovar e o tamanho da janela.
struct RitmoDeUso: Codable, Equatable, Sendable {
    /// Percentual que o uso teria agora se fosse parelho do começo ao fim da janela.
    var esperado: Int
    /// Percentual a que o uso chega na renovação, mantido o ritmo de agora. Sem número nos primeiros 5% da janela.
    var projecao: Int?
    /// "rapido" (vai passar de 100% antes de renovar) ou "sobra" (renova em menos de 24 h com mais da metade sem usar).
    var situacao: String?

    static func calcular(percentual: Int, renova: Date?, agora: Date, duracao: TimeInterval) -> RitmoDeUso? {
        guard let renova, duracao > 0, renova > agora else { return nil }
        let inicio = renova.addingTimeInterval(-duracao)
        let fracao = max(0, min(1, agora.timeIntervalSince(inicio) / duracao))
        let esperado = Int((fracao * 100).rounded())
        var projecao: Int?
        if fracao >= 0.05 { projecao = Int(min(999, (Double(percentual) / fracao).rounded())) }
        var situacao: String?
        if let p = projecao, p > 100 { situacao = "rapido" }
        else if percentual < 50, renova.timeIntervalSince(agora) < 86_400 { situacao = "sobra" }
        return RitmoDeUso(esperado: esperado, projecao: projecao, situacao: situacao)
    }
}
