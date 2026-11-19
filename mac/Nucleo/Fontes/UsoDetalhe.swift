import Foundation

/// Uma janela de limite de uma conta, com o ritmo dela.
struct JanelaDeLimite: Codable, Equatable, Sendable {
    /// "Semana" ou "5 horas".
    var rotulo: String
    var percentual: Int
    var renova: String?
    /// Quando o Mac mediu isso. Sem o campo, a fonte não diz.
    var medidoEm: String?
    var ritmo: RitmoDeUso?
}

struct ContaDetalhada: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var conta: String
    var janelas: [JanelaDeLimite]
    /// Os tokens da conta. Só o Codex traz: o log do Claude não diz de qual conta cada resposta saiu.
    var gasto: GastoPeriodo?
}

/// O corpo de GET /api/uso/detalhe. Enxuto de propósito (o Bluetooth é estreito): campo vazio não vai, e o gráfico é só uma lista de números.
struct DetalheUso: Codable, Equatable, Sendable {
    var periodo: String
    /// Quando a varredura dos logs terminou pela última vez, ISO 8601.
    var atualizadoEm: String?
    /// true: ainda não há nenhuma varredura pronta (primeira vez neste Mac).
    var calculando: Bool?
    /// Dia (AAAA-MM-DD, no relógio do Mac) da última barra do gráfico.
    var ate: String
    var contas: [ContaDetalhada]
    /// O Claude somado neste Mac. Só existe se alguma conta Claude está visível no iPhone.
    var claudeMac: GastoPeriodo?
    var aviso: String?
}

enum UsoDetalhe {
    /// 7 dias da semana de limite do Claude e do Codex.
    static let duracaoDaSemana: TimeInterval = 7 * 86_400

    static func rotuloDaJanela(minutos: Int) -> String {
        if minutos == 10080 { return "Semana" }
        if minutos % 1440 == 0 { return "\(minutos / 1440) dias" }
        if minutos % 60 == 0 { return "\(minutos / 60) horas" }
        return "\(minutos) min"
    }

    /// Junta o uso que o estado já mostra (a semana de cada conta) com a janela curta do Codex e o gasto de tokens.
    static func montar(periodo: PeriodoUso, uso: [UsoConta], medicaoClaude: [String: Date], janelasCodex: [UsoCodex.JanelaCodex],
                       contas: [ContaIA], gasto: GastoTokens?, agora: Date, calendario: Calendar = .current) -> DetalheUso {
        let visiveis = contas.filter { $0.mostrar != false }
        var primeiroCodex = true
        let linhas = visiveis.map { c -> ContaDetalhada in
            let u = uso.first { $0.id == c.id }
            var janelas: [JanelaDeLimite] = []
            if c.nome == "Codex" {
                // a janela curta do Codex vem antes da semana, como no app deles
                for j in janelasCodex where j.minutos != 10080 && j.renova > agora {
                    janelas.append(JanelaDeLimite(rotulo: rotuloDaJanela(minutos: j.minutos), percentual: j.percentual, renova: Datas.iso(j.renova, fuso: TimeZone(identifier: "UTC")!),
                                                  medidoEm: j.medidoEm.map { Datas.iso($0, fuso: TimeZone(identifier: "UTC")!) },
                                                  ritmo: RitmoDeUso.calcular(percentual: j.percentual, renova: j.renova, agora: agora, duracao: Double(j.minutos) * 60)))
                }
            }
            if let u, let p = u.semana {
                let renova = u.renova.flatMap(Datas.ler)
                let medido = c.nome == "Codex" ? janelasCodex.first { $0.minutos == 10080 }?.medidoEm : c.perfil.flatMap { medicaoClaude[$0] }
                janelas.append(JanelaDeLimite(rotulo: "Semana", percentual: p, renova: u.renova,
                                              medidoEm: medido.map { Datas.iso($0, fuso: TimeZone(identifier: "UTC")!) },
                                              ritmo: RitmoDeUso.calcular(percentual: p, renova: renova, agora: agora, duracao: duracaoDaSemana)))
            }
            var g: GastoPeriodo?
            if c.nome == "Codex", primeiroCodex, let gasto { g = gasto.consultar(.codex, periodo: periodo, agora: agora, calendario: calendario); primeiroCodex = false }
            return ContaDetalhada(id: c.id, nome: c.nome, conta: c.conta, janelas: janelas, gasto: g)
        }
        let temClaude = visiveis.contains { $0.nome == "Claude" }
        let claude = temClaude ? gasto?.consultar(.claude, periodo: periodo, agora: agora, calendario: calendario) : nil
        var fmt = DateFormatter()
        fmt = DateFormatter(); fmt.calendar = calendario; fmt.timeZone = calendario.timeZone; fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
        return DetalheUso(periodo: periodo.rawValue, atualizadoEm: gasto?.atualizadoEm.map { Datas.iso($0) },
                          calculando: (gasto?.calculando ?? false) ? true : nil, ate: fmt.string(from: agora),
                          contas: linhas, claudeMac: claude, aviso: nil)
    }
}
