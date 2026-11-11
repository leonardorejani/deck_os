import Foundation
import AppKit
import ApplicationServices
import EventKit

/// Como está cada acesso do macOS que o Deck usa, lido na hora e sem abrir janela do macOS. A seção
/// Acessos do Mac mostra todos (SPEC 9a), e o aviso do menu e o selo da barra lateral contam só os recusados.
protocol VerificadorDeAcessos {
    func acessos() -> [AcessoLido]
}

extension VerificadorDeAcessos {
    func recusados() -> [AcessoMac] { acessos().filter { $0.situacao == .recusado }.map(\.acesso) }
}

/// A leitura de verdade. Os detectores só consultam, e o que o macOS não diz sozinho (Acessibilidade e Acesso
/// Total ao Disco não separam "nunca pedi" de "recusei") o Deck lembra pelo pedido que ele mesmo fez.
struct VerificadorVivo: VerificadorDeAcessos {
    var defaults: UserDefaults = .standard
    var detectores: DetectoresDeAcesso = DetectoresDoMac()
    /// De onde o WhatsApp é lido (config `whatsapp.origem`): com `app` os navegadores não entram na lista.
    var origemDoWhatsApp = "auto"
    /// O navegador fixado em `whatsapp.navegador`. Sem ele, valem todos os instalados.
    var navegadorFixado: String?
    /// Um iPhone falou com o Mac pelo Wi-Fi: a Rede Local está liberada (o macOS não deixa conferir de outro jeito).
    var iphonePeloWifi = false

    /// O Spotify, alvo da Automação.
    static let spotify = "com.spotify.client"
    /// Quem pede o acesso grava esta chave na hora do pedido, e só depois disso "não liberado" conta como recusado.
    static func chavePedido(_ acesso: AcessoMac) -> String { "acessoPedido.\(acesso.rawValue)" }

    static func chaveRecusado(_ acesso: AcessoMac) -> String { "acessoRecusado.\(acesso.rawValue)" }

    /// A última resposta do macOS que não dá para reler sempre: a Automação (só com o app aberto) e a Rede
    /// Local (só perguntando). Vale "liberado" ou "recusado".
    static func chaveUltima(_ alvo: String) -> String { "acessoUltimo.\(alvo)" }

    func acessos() -> [AcessoLido] { OrdemDosAcessos.painel.compactMap { ler($0) } }

    func recusado(_ acesso: AcessoMac) -> Bool { ler(acesso)?.situacao == .recusado }

    /// nil = o acesso não se aplica a este Mac (Spotify não instalado, WhatsApp lido só pelo app).
    func ler(_ acesso: AcessoMac) -> AcessoLido? {
        switch acesso {
        case .calendarios: return AcessoLido(acesso: acesso, situacao: detectores.calendario())
        case .bluetooth: return AcessoLido(acesso: acesso, situacao: detectores.bluetooth())
        case .acessibilidade: return AcessoLido(acesso: acesso, situacao: porPedido(acesso, liberado: detectores.acessibilidade()))
        case .discoTotal: return AcessoLido(acesso: acesso, situacao: porPedido(acesso, liberado: detectores.discoTotal()))
        case .automacao:
            guard detectores.instalado(bundle: Self.spotify) else { return nil }
            let (situacao, detalhe) = automacao(bundle: Self.spotify, app: "o Spotify")
            return AcessoLido(acesso: acesso, situacao: situacao, detalhe: detalhe)
        case .navegadores: return navegadores()
        case .redeLocal: return AcessoLido(acesso: acesso, situacao: redeLocal())
        }
    }

    private func porPedido(_ acesso: AcessoMac, liberado: Bool) -> SituacaoDoAcesso {
        if liberado { return .liberado }
        let pediu = defaults.bool(forKey: Self.chavePedido(acesso)) || defaults.bool(forKey: Self.chaveRecusado(acesso))
        return pediu ? .recusado : .naoPedido
    }

    private func automacao(bundle: String, app: String) -> (SituacaoDoAcesso, String?) {
        let chave = Self.chaveUltima(bundle)
        switch detectores.automacao(bundle: bundle) {
        case .liberado: defaults.set("liberado", forKey: chave); return (.liberado, nil)
        case .recusado: defaults.set("recusado", forKey: chave); return (.recusado, nil)
        case .naoPerguntado: defaults.removeObject(forKey: chave); return (.naoPedido, nil)
        case .naoInstalado: return (.semComoSaber("Não está instalado neste Mac."), nil)
        case .fechado:
            switch defaults.string(forKey: chave) {
            case "liberado": return (.liberado, "Última leitura, com \(app) aberto")
            case "recusado": return (.recusado, "Última leitura, com \(app) aberto")
            default: return (.semComoSaber("Abra \(app) e o macOS deixa conferir."), nil)
            }
        }
    }

    /// Os navegadores que o Deck consulta: o fixado na config ou, sem fixo, todos os instalados.
    func navegadoresRelevantes() -> [NavegadorWeb] {
        NavegadorWeb.todos.filter { n in
            detectores.instalado(bundle: n.idBundle) && (navegadorFixado == nil || navegadorFixado == n.nome)
        }
    }

    /// Uma linha só para os navegadores: a pior situação entre eles decide, e o detalhe diz quais.
    private func navegadores() -> AcessoLido? {
        guard origemDoWhatsApp != "app" else { return nil }
        let alvos = navegadoresRelevantes()
        guard !alvos.isEmpty else { return nil }
        let lidos = alvos.map { ($0.nome, automacao(bundle: $0.idBundle, app: $0.nome)) }
        let com = { (filtro: (SituacaoDoAcesso) -> Bool) in Self.lista(lidos.filter { filtro($0.1.0) }.map(\.0)) }
        let recusados = com { $0 == .recusado }, novos = com { $0 == .naoPedido }, abertos = com { $0 == .liberado }
        if !recusados.isEmpty { return AcessoLido(acesso: .navegadores, situacao: .recusado, detalhe: "Recusado em \(recusados)") }
        if !novos.isEmpty { return AcessoLido(acesso: .navegadores, situacao: .naoPedido, detalhe: "Ainda não perguntado para \(novos)") }
        if !abertos.isEmpty {
            let fechados = lidos.filter { if case .semComoSaber = $0.1.0 { return true } else { return false } }.map(\.0)
            return AcessoLido(acesso: .navegadores, situacao: .liberado, detalhe: fechados.isEmpty ? nil : "Sem como conferir agora: \(Self.lista(fechados))")
        }
        return AcessoLido(acesso: .navegadores, situacao: .semComoSaber("Abra o navegador onde você usa o WhatsApp Web e o macOS deixa conferir."))
    }

    private func redeLocal() -> SituacaoDoAcesso {
        if iphonePeloWifi { return .liberado }
        switch defaults.string(forKey: Self.chaveUltima(AcessoMac.redeLocal.rawValue)) {
        case "liberado": return .liberado
        case "recusado": return .recusado
        default: return .semComoSaber("O macOS não deixa conferir este sem perguntar. Toque em Permitir.")
        }
    }

    /// "Safari", "Safari e Arc", "Safari, Arc e Brave Browser".
    static func lista(_ nomes: [String]) -> String {
        guard let ultimo = nomes.last else { return "" }
        return nomes.count == 1 ? ultimo : nomes.dropLast().joined(separator: ", ") + " e " + ultimo
    }
}

extension ModeloApp {
    /// O verificador de agora: usa a config de hoje (origem do WhatsApp, navegador fixado, iPhone no Wi-Fi).
    func verificadorAtual() -> VerificadorVivo {
        VerificadorVivo(defaults: defaults, origemDoWhatsApp: config.whatsapp.origem, navegadorFixado: config.whatsapp.navegador,
                        iphonePeloWifi: iphone?.canal == .wifi)
    }

    /// Relê os acessos. A seção Acessos do Mac, o selo da barra lateral e o aviso do menu leem daqui,
    /// então atualizar uma vez atualiza os três.
    func atualizarAcessos(_ verificador: VerificadorDeAcessos? = nil) {
        let lidos = (verificador ?? verificadorAtual()).acessos()
        if lidos != acessos { acessos = lidos }
        let novos = lidos.filter { $0.situacao == .recusado }.map(\.acesso)
        if novos != acessosRecusados { acessosRecusados = novos }
    }

    /// Começa a reler os acessos agora e toda vez que o Deck volta para a frente (a pessoa foi a Ajustes
    /// do Sistema liberar e voltou).
    func vigiarAcessos(_ verificador: VerificadorDeAcessos? = nil) {
        atualizarAcessos(verificador)
        vigiaDeAcessos = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizarAcessos(verificador) }
        }
    }

    /// "Permitir": o próprio Deck pede ao macOS, que mostra a janelinha dele (ou abre os Ajustes do Sistema,
    /// quando não há janelinha), e depois a lista é relida.
    func permitirAcesso(_ acesso: AcessoMac, pedidos: PedidosDeAcesso? = nil, verificador: VerificadorDeAcessos? = nil) async {
        let pedidos = pedidos ?? PedidosDoMac(defaults: defaults, navegadores: verificadorAtual().navegadoresRelevantes().map(\.idBundle))
        _ = await pedidos.pedir(acesso)
        atualizarAcessos(verificador)
    }
}

/// Para onde "Abrir Ajustes do Sistema" leva: a página de cada acesso.
extension AcessoMac {
    var enderecoDosAjustes: URL {
        let painel: String
        switch self {
        case .acessibilidade: painel = "Privacy_Accessibility"
        case .calendarios: painel = "Privacy_Calendars"
        case .automacao: painel = "Privacy_Automation"
        case .discoTotal: painel = "Privacy_AllFiles"
        case .navegadores: painel = "Privacy_Automation"
        case .bluetooth: painel = "Privacy_Bluetooth"
        case .redeLocal: painel = "Privacy_LocalNetwork"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(painel)")!
    }
}
