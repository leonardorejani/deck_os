import Foundation

/// As seções da janela de Ajustes, na ordem e nos grupos da barra lateral do protótipo
/// (mac.js, SECOES): o que mais se usa em cima.
enum SecaoAjustes: String, CaseIterable, Identifiable {
    case teclas, uso, iphone, permissoes, geral, sobre

    var id: String { rawValue }

    /// `--ajustes=iphone` na linha de comando abre os Ajustes já nessa seção (para conferir uma tela sem clicar).
    static func daLinhaDeComando(_ argumentos: [String]) -> SecaoAjustes? {
        guard let valor = argumentos.first(where: { $0.hasPrefix("--ajustes=") })?.dropFirst("--ajustes=".count) else { return nil }
        return SecaoAjustes(rawValue: String(valor))
    }

    var nome: String {
        switch self {
        case .teclas: return "Suas teclas"
        case .uso: return "Uso das IAs"
        case .iphone: return "Conexões"
        case .permissoes: return "Acessos do Mac"
        case .geral: return "Este Mac"
        case .sobre: return "Sobre o Deck"
        }
    }

    /// Ícone na barra lateral (chave de mac.js, IC).
    var icone: String {
        switch self {
        case .teclas: return Icone.teclas
        case .uso: return Icone.uso
        case .iphone: return Icone.iphone
        case .permissoes: return Icone.permissoes
        case .geral: return Icone.geral
        case .sobre: return Icone.sobre
        }
    }

    /// Grupos separados por um espaço na barra lateral.
    static let grupos: [[SecaoAjustes]] = [[.teclas, .uso], [.iphone, .permissoes], [.geral, .sobre]]

}

/// Os acessos do macOS que o Deck usa. A seção "Acessos do Mac" lista todos, cada um com o estado real.
enum AcessoMac: String, CaseIterable, Identifiable {
    case acessibilidade, calendarios, automacao, discoTotal
    /// Automação dos navegadores onde o WhatsApp Web abre (a do Spotify é `automacao`).
    case navegadores, bluetooth, redeLocal

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .acessibilidade: return "Acessibilidade"
        case .calendarios: return "Calendários"
        case .automacao: return "Automação"
        case .discoTotal: return "Acesso Total ao Disco"
        case .navegadores: return "Automação"
        case .bluetooth: return "Bluetooth"
        case .redeLocal: return "Rede Local"
        }
    }

    /// O nome na lista dos Ajustes: o macOS junta o Spotify e os navegadores sob "Automação", então aqui diz de quem é.
    var nomeNaLista: String {
        switch self {
        case .automacao: return "Automação do Spotify"
        case .navegadores: return "Automação dos navegadores"
        default: return nome
        }
    }

    /// Para que o Deck usa (a linha de baixo da lista de acessos).
    var para: String {
        switch self {
        case .acessibilidade: return "Para as teclas do tipo Teclado apertarem atalhos no Mac."
        case .calendarios: return "Para mostrar seus eventos na Agenda do iPhone."
        case .automacao: return "Para o player do iPhone mostrar a música e controlar o Spotify."
        case .discoTotal: return "Para mostrar quem mandou mensagem no WhatsApp. Só leitura, nada sai do Mac."
        case .navegadores: return "Para contar as não lidas do WhatsApp Web aberto no navegador."
        case .bluetooth: return "Para o app do iPhone falar com o Mac por Bluetooth, sem Wi-Fi."
        case .redeLocal: return "Para o iPhone achar o Mac na rede de casa."
        }
    }
}

enum TextosDoMenu {
    static func acessosRecusados(_ n: Int) -> String { "\(n) \(n > 1 ? "acessos recusados" : "acesso recusado")" }

    static func portaOcupada(preferida: Int, usada: Int) -> String { "A porta \(preferida) está ocupada. O Deck usa a \(usada)" }

    static let servidorFalhou = "O iPhone não consegue achar o Mac"

    static func estadoIphone(_ iphone: IphonePareado?, agora: Date = Date()) -> String {
        guard let iphone else { return "Nenhum iPhone pareado" }
        return iphone.aoVivo(agora: agora) ? "\(iphone.nome), \(iphone.canal.texto)" : "\(iphone.nome), fora de alcance"
    }

    static func sincronia(_ iphone: IphonePareado?, salvoAgora: Bool = false, agora: Date = Date()) -> String {
        guard let iphone else { return salvoAgora ? "Salvo" : "Nenhum iPhone pareado" }
        if !iphone.aoVivo(agora: agora) { return salvoAgora ? "Salvo. Vai para o iPhone quando ele voltar" : "\(iphone.nome) fora de alcance" }
        return salvoAgora ? "Salvo. Já está no iPhone" : "Sincronizado com o \(iphone.nome)"
    }

    static func composicao(_ c: String) -> String { c == "a" ? "Relógio em cima" : "Deck 3 x 3" }
}

/// Primeira vez do app: quem já tinha config.json (usa o Deck há tempo) não passa pela configuração
/// inicial de novo. Quem nunca teve, passa. Depois de feita, vale o que ficou guardado.
enum EstadoInicial {
    static func jaFeita(guardado: Bool?, configExistia: Bool) -> Bool { guardado ?? configExistia }
}
