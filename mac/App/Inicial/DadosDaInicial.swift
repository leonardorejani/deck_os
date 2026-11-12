import Foundation

/// Os 7 passos, na ordem do protótipo (mac.js, passosIni).
enum PassoInicial: Int, CaseIterable {
    case boas, iphone, layout, contas, teclas, acessos, pronto

    var primeiro: Bool { self == .boas }
    var ultimo: Bool { self == .pronto }
}

/// Tecla sugerida no passo "Primeiras teclas" (mac.js, SUGESTOES).
struct SugestaoDeTecla: Equatable, Identifiable {
    var id: String
    var nome: String
    var tipo: String
    var valor: String
    var icone: String
    /// Nome do app que precisa existir neste Mac para a sugestão fazer sentido (nil = sempre vale).
    var app: String?

    var tecla: Tecla { Tecla(id: id, nome: nome, tipo: tipo, valor: valor, estado: nil, icone: icone) }

    static let todas: [SugestaoDeTecla] = [
        SugestaoDeTecla(id: "whatsapp", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", icone: "WhatsApp", app: "WhatsApp"),
        SugestaoDeTecla(id: "agenda", nome: "Agenda", tipo: "app", valor: "Calendar", icone: "Calendar", app: "Calendar"),
        SugestaoDeTecla(id: "spotify", nome: "Spotify", tipo: "app", valor: "Spotify", icone: "Spotify", app: "Spotify"),
        SugestaoDeTecla(id: "apagar", nome: "Apagar tela", tipo: "comando", valor: "pmset displaysleepnow", icone: "svg:tela", app: nil),
        SugestaoDeTecla(id: "safari", nome: "Safari", tipo: "app", valor: "Safari", icone: "Safari", app: "Safari"),
        SugestaoDeTecla(id: "notas", nome: "Notas", tipo: "app", valor: "Notes", icone: "Notes", app: "Notes"),
        SugestaoDeTecla(id: "terminal", nome: "Terminal", tipo: "app", valor: "Terminal", icone: "Terminal", app: "Terminal"),
        SugestaoDeTecla(id: "finder", nome: "Finder", tipo: "app", valor: "Finder", icone: "Finder", app: "Finder"),
    ]

    /// As que já vêm marcadas.
    static let marcadasDePartida: Set<String> = ["whatsapp", "agenda", "spotify", "apagar"]
}

/// Conta de IA achada neste Mac (mac.js, ACHADAS).
struct ContaAchada: Equatable, Identifiable {
    var id: String
    /// "Claude" ou "Codex".
    var servico: String
    var conta: String
    var perfil: String? = nil
    var semana: Int?
    var renova: Date?

    var nomeDoServico: String { servico == "Claude" ? "Claude Code" : "Codex" }
    var titulo: String { "\(nomeDoServico), conta \(conta)" }

    func detalhe(agora: Date = Date()) -> String {
        guard let semana else { return "Uso da semana ainda sem medição" }
        guard let renova else { return "\(semana)% da semana usado" }
        return "\(semana)% da semana usado, renova \(RenovaEm.texto(renova, agora: agora))"
    }

    var contaIA: ContaIA { ContaIA(id: id, nome: servico, conta: conta, perfil: perfil, mostrar: nil) }
}

/// "em 3 dias", "amanhã", "hoje às 14h" (dados.js, renovaEm), contando por dia do calendário.
enum RenovaEm {
    static func texto(_ quando: Date, agora: Date = Date(), calendario: Calendar = .current) -> String {
        let dias = calendario.dateComponents([.day], from: calendario.startOfDay(for: agora), to: calendario.startOfDay(for: quando)).day ?? 0
        if dias <= 0 {
            let h = calendario.component(.hour, from: quando)
            return "hoje às \(h)h"
        }
        if dias == 1 { return "amanhã" }
        return "em \(dias) dias"
    }

    private static let diasDaSemana = ["dom", "seg", "ter", "qua", "qui", "sex", "sab"]

    /// "sex 14h" vira a próxima sexta às 14h (o jeito do protótipo de dar a data de exemplo).
    static func proxima(_ diaHora: String, agora: Date = Date(), calendario: Calendar = .current) -> Date? {
        let partes = diaHora.split(separator: " ")
        guard partes.count == 2, let dia = diasDaSemana.firstIndex(of: String(partes[0])),
              let hora = Int(partes[1].dropLast()) else { return nil }
        guard let hoje = calendario.date(bySettingHour: hora, minute: 0, second: 0, of: agora) else { return nil }
        let hojeDia = calendario.component(.weekday, from: agora) - 1
        var falta = (dia - hojeDia + 7) % 7
        if falta == 0, hoje <= agora { falta = 7 }
        return calendario.date(byAdding: .day, value: falta, to: hoje)
    }
}

/// Estado de um acesso do macOS no passo "Libere os acessos".
enum EstadoDoAcesso: Equatable {
    /// Ainda não foi pedido: botão "Permitir".
    case naoPedido
    case liberado
    /// Pedido e não concedido: botão "Abrir Ajustes do Sistema".
    case recusado
}

/// Ordem do protótipo (mac.js, ORDEM_PERMS): Calendários, Automação, Acesso Total ao Disco, Acessibilidade.
enum OrdemDosAcessos {
    static let todos: [AcessoMac] = [.calendarios, .automacao, .discoTotal, .acessibilidade]
    /// A seção Acessos do Mac lista tudo o que o Deck usa, na ordem em que a pessoa mais pergunta.
    static let painel: [AcessoMac] = painel(para: Variante.atual)

    /// A bancada não tem iPhone: sem Bluetooth e sem Rede local na lista (o macOS não pode perguntar por eles).
    static func painel(para variante: Variante) -> [AcessoMac] {
        let base: [AcessoMac] = [.calendarios, .automacao, .navegadores, .acessibilidade, .discoTotal, .bluetooth, .redeLocal]
        return variante.pedeBluetoothERedeLocal ? base : base.filter { $0 != .bluetooth && $0 != .redeLocal }
    }
}
