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
    /// Quando o uso chega a 100% se o ritmo de agora continuar (ISO 8601). Só vem quando "rapido" e ainda abaixo de 100%.
    var enche: String?

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
        var enche: String?
        if situacao == "rapido", percentual > 0, percentual < 100 {
            // taxa = percentual / tempo decorrido, então falta (100 - percentual) / taxa para encher
            let falta = (100 - Double(percentual)) / Double(percentual) * agora.timeIntervalSince(inicio)
            enche = Datas.iso(agora.addingTimeInterval(falta), fuso: TimeZone(identifier: "UTC")!)
        }
        return RitmoDeUso(esperado: esperado, projecao: projecao, situacao: situacao, enche: enche)
    }
}
