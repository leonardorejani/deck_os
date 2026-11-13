import Foundation

// A conexão do iPhone com o Mac vista pelo app do Mac. Uma fonte para cada conceito: quem está falando agora (`visto`),
// por onde (`CanalIphone`), qual método a tela mostra (`MetodoDeConexao`). Sem tela nem rede, para o `swift test`.

/// Por onde o iPhone está falando com o Mac.
enum CanalIphone: String {
    case wifi, cabo, bluetooth

    var texto: String {
        switch self {
        case .wifi: return "pelo Wi-Fi"
        case .cabo: return "pelo cabo"
        case .bluetooth: return "por Bluetooth"
        }
    }
}

struct IphonePareado: Equatable {
    var nome: String
    var canal: CanalIphone = .wifi
    /// Desde quando está conectado (a linha da seção Conexões) e a versão do iOS.
    var desde: Date? = nil
    var ios: String? = nil
    /// A última vez que o iPhone falou com o Mac (qualquer resposta boa da API). nil = não se sabe, vale como ao vivo.
    var visto: Date? = nil

    /// Quanto tempo sem falar ainda conta como conectado. O painel pergunta ao Mac a cada segundo, e o app nativo
    /// também: 30 s sem nada é o aparelho longe da rede, bloqueado ou com o app fechado.
    static let janelaAoVivo: TimeInterval = 30

    func aoVivo(agora: Date) -> Bool {
        guard let visto else { return true }
        return agora.timeIntervalSince(visto) <= Self.janelaAoVivo
    }
}

/// O app nativo do iPhone, visto por quem fala com ele pelo cabo ou pelo Bluetooth.
struct AppNativo: Equatable {
    var nome: String
    /// O canal do último pedido atendido: o cabo ou o Bluetooth.
    var canal: CanalIphone
    var desde: Date
    var visto: Date
}

enum Conexoes {
    /// De quanto em quanto tempo uma resposta boa atualiza o "visto" (o painel pergunta a cada segundo).
    static let intervaloDoRegistro: TimeInterval = 5

    /// O Mac respondeu a API pelo Wi-Fi. Resposta boa quer dizer que o iPhone está pareado e falando agora: sem registro
    /// ele passa a existir (o Mac reabriu, ou o pareamento foi antes de o Mac anotar), com registro o `visto` anda.
    /// Devolve o iPhone novo, ou nil quando nada muda.
    static func aposRespostaDoWifi(atual: IphonePareado?, caminho: String, status: Int, agora: Date) -> IphonePareado? {
        guard (200..<300).contains(status), caminho.hasPrefix("/api/"), caminho != "/api/parear" else { return nil }
        guard var i = atual else { return IphonePareado(nome: "iPhone", canal: .wifi, desde: agora, visto: agora) }
        guard i.canal == .wifi else { return nil }
        if let visto = i.visto, agora.timeIntervalSince(visto) < intervaloDoRegistro { return nil }
        i.visto = agora
        return i
    }
}

/// Os métodos de conectar um iPhone, na ordem do seletor no topo de Conexões.
enum MetodoDeConexao: String, CaseIterable, Identifiable {
    case cabo, pwa, whatsapp, spotify

    var id: String { rawValue }

    var rotulo: String {
        switch self {
        case .cabo: return "Cabo e Bluetooth"
        case .pwa: return "PWA"
        case .whatsapp: return "WhatsApp"
        case .spotify: return "Spotify"
        }
    }
}

/// Os avisos do menu e da barra lateral que levam a Conexões. Cada um mora em um método só, então quem leva para lá também
/// escolhe o método: sem isso o aviso abria uma tela onde ele não aparece.
enum AvisoDeConexao {
    /// "O app vence em N dias": o cartão da renovação é do app nativo (Cabo e Bluetooth).
    case renovacao
    /// O servidor não subiu ou subiu em outra porta: o cartão de erro e o endereço são do PWA (Wi-Fi).
    case servidor

    var metodo: MetodoDeConexao {
        switch self {
        case .renovacao: return .cabo
        case .servidor: return .pwa
        }
    }
}

/// O Deck some da frente quando o macOS abre outra janela por ele (Ajustes do Sistema) ou quando um pedido
/// de acesso termina. Aqui está a espera que traz o Deck de volta.
enum PrimeiroPlano {
    /// Olha `ler()` a cada `intervalo` segundos, por até `limite`. Quando o valor deixa de ser `inicial`, chama
    /// `trazer()` e devolve true. Sem mudança no prazo devolve false e não chama nada.
    @MainActor
    static func trazerQuandoMudar<T: Equatable>(inicial: T, ler: () -> T, trazer: () -> Void,
                                                intervalo: TimeInterval = 1, limite: TimeInterval = 180,
                                                dormir: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) async -> Bool {
        let voltas = max(1, Int(limite / max(intervalo, 0.001)))
        for _ in 0..<voltas {
            if Task.isCancelled { return false }
            await dormir(intervalo)
            if ler() != inicial { trazer(); return true }
        }
        return false
    }

    /// Quem pediu o acesso só traz o Deck de volta no fim do pedido se nenhuma vigia foi ligada: com a vigia, quem traz é a
    /// mudança da permissão. Trazer antes cobre os Ajustes do Sistema que o próprio pedido acabou de abrir.
    @MainActor
    static func aoTerminarPedido(vigiaLigada: Bool, trazer: () -> Void) {
        if !vigiaLigada { trazer() }
    }

    /// Só vale vigiar o que o Deck consegue reler. Sem leitura (nil), ou com uma situação que não muda sozinha (Rede Local,
    /// Automação com o app fechado), a espera de 3 min seria à toa: o Deck não voltaria nunca.
    static func deveVigiar<T>(inicial: T?, legivel: (T) -> Bool) -> Bool {
        guard let inicial else { return false }
        return legivel(inicial)
    }
}

/// O ícone de uma tecla de app não pode esperar a lista de apps carregar: sem ela, acha o .app direto nas pastas.
enum IconeDeApp {
    static func caminho(valor: String, doCatalogo: String?, pastas: [String], existe: (String) -> Bool) -> String? {
        if let doCatalogo { return doCatalogo }
        guard !valor.isEmpty else { return nil }
        return pastas.map { $0 + "/" + valor + ".app" }.first(where: existe)
    }
}

/// Quando a lista de apps do Mac (o seletor de "Abrir app" e os ícones das teclas) precisa ser lida de novo. Ela carrega ao
/// abrir o Deck, mas app instalado depois não pode esperar o Deck reiniciar: cada vez que Suas teclas abre e a leitura
/// passou de `idadeMaxima`, lê outra vez (sem apagar a lista antiga, para o ícone não piscar).
enum RecargaDoCatalogo {
    static let idadeMaxima: TimeInterval = 30

    static func precisa(ultimaLeitura: Date?, agora: Date, carregando: Bool) -> Bool {
        if carregando { return false }
        guard let ultimaLeitura else { return true }
        return agora.timeIntervalSince(ultimaLeitura) > idadeMaxima
    }
}
