import Foundation

/// Preço de API por milhão de tokens (US$), só para estimar o gasto. Quem usa assinatura não paga isso,
/// então a tela sempre diz "estimado". Tabela de referência de 06/10/2026. Modelo que não está aqui
/// mostra os tokens e fica sem dólar, nunca com um número inventado.
enum PrecosModelos {
    struct Preco: Equatable, Sendable {
        var entrada: Double
        var saida: Double
        /// Cache lido, cache escrito por 5 minutos e por 1 hora, como parte do preço de entrada.
        var porLeitura = 0.1
        var por5m = 1.25
        var por1h = 2.0
    }

    /// O prefixo mais longo que casar com o nome do modelo vence ("claude-opus-4-5" antes de "claude-opus-4").
    static let tabela: [(prefixo: String, preco: Preco)] = [
        ("claude-fable-5", Preco(entrada: 10, saida: 50)),
        ("claude-opus-5", Preco(entrada: 4, saida: 20)),
        ("claude-sonnet-5", Preco(entrada: 2, saida: 10)),
        ("claude-haiku-5", Preco(entrada: 0.10, saida: 0.50)),
        ("claude-opus-4-5", Preco(entrada: 5, saida: 25)),
        ("claude-opus-4-6", Preco(entrada: 5, saida: 25)),
        ("claude-opus-4-7", Preco(entrada: 5, saida: 25)),
        ("claude-opus-4-8", Preco(entrada: 5, saida: 25)),
        ("claude-opus-4", Preco(entrada: 15, saida: 75)),
        ("claude-sonnet-4", Preco(entrada: 3, saida: 15)),
        ("claude-3-7-sonnet", Preco(entrada: 3, saida: 15)),
        ("claude-3-5-sonnet", Preco(entrada: 3, saida: 15)),
        ("claude-haiku-4-5", Preco(entrada: 1, saida: 5)),
        ("claude-3-5-haiku", Preco(entrada: 0.8, saida: 4)),
        ("claude-3-haiku", Preco(entrada: 0.25, saida: 1.25)),
        ("gpt-5", Preco(entrada: 1.25, saida: 10, por5m: 0, por1h: 0)),
    ]

    static func preco(_ modelo: String) -> Preco? {
        let m = modelo.lowercased()
        return tabela.filter { m.hasPrefix($0.prefixo) }.max { $0.prefixo.count < $1.prefixo.count }?.preco
    }

    /// Dólares estimados, ou nil se o modelo não está na tabela.
    static func custo(modelo: String, _ c: Contagem) -> Double? {
        guard let p = preco(modelo) else { return nil }
        let porMilhao = Double(c.entrada) * p.entrada + Double(c.saida) * p.saida
            + Double(c.leitura) * p.entrada * p.porLeitura
            + Double(c.escrita5m) * p.entrada * p.por5m + Double(c.escrita1h) * p.entrada * p.por1h
        return porMilhao / 1_000_000
    }

    /// Nome curto para a tela: "claude-opus-5-5-20261001" vira "Opus 5.5", "gpt-5.5-codex" vira "GPT-5.5-codex".
    static func rotulo(_ modelo: String) -> String {
        let partes = modelo.lowercased().split(separator: "-").map(String.init)
        if partes.first == "gpt" { return "GPT" + modelo.dropFirst(3) }
        let familias = ["opus", "sonnet", "haiku", "fable"]
        if let i = partes.firstIndex(where: familias.contains) {
            // a versão vem depois ("opus-5-5") ou antes ("3-5-sonnet") da família, e a data (8 dígitos) nunca entra
            func versao(_ p: ArraySlice<String>) -> [String] { Array(p.prefix { $0.count <= 2 && Int($0) != nil }) }
            var v = versao(partes[(i + 1)...])
            if v.isEmpty { v = Array(partes[..<i].reversed().prefix { $0.count <= 2 && Int($0) != nil }.reversed()) }
            let nome = partes[i].prefix(1).uppercased() + partes[i].dropFirst()
            return v.isEmpty ? nome : "\(nome) \(v.joined(separator: "."))"
        }
        return String(modelo.prefix(24))
    }
}
