import Foundation
import AppKit
import ApplicationServices
import EventKit
import CoreBluetooth
import Network

/// Os pedidos de acesso ao macOS do passo "Libere os acessos". Atrás de um protocolo para os testes
/// e as fotos não abrirem janela do sistema.
@MainActor
protocol PedidosDeAcesso {
    /// Como o acesso está agora, sem perguntar nada. nil = o macOS não deixa saber sem pedir.
    func estado(_ acesso: AcessoMac) -> EstadoDoAcesso?
    /// "Permitir": mostra a janelinha do macOS (ou abre os Ajustes do Sistema, quando não há janelinha).
    func pedir(_ acesso: AcessoMac) async -> EstadoDoAcesso
    /// "Abrir Ajustes do Sistema", na página certa.
    func abrirAjustes(_ acesso: AcessoMac)
}

@MainActor
struct PedidosDoMac: PedidosDeAcesso {
    var defaults: UserDefaults = .standard
    /// Os navegadores (id do app) cuja Automação o pedido "navegadores" pergunta. Vem da config de quem usa.
    var navegadores: [String] = []

    /// O gerente do Bluetooth precisa ficar vivo enquanto o macOS espera a resposta da pessoa.
    private static var gerenteDoBluetooth: CBCentralManager?

    func estado(_ acesso: AcessoMac) -> EstadoDoAcesso? {
        switch acesso {
        case .calendarios:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized, .fullAccess: return .liberado
            case .denied, .restricted: return .recusado
            default: return .naoPedido
            }
        case .acessibilidade:
            return AXIsProcessTrusted() ? .liberado : nil
        case .discoTotal:
            return DetectoresDoMac().discoTotal() ? .liberado : nil
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .liberado
            case .notDetermined: return .naoPedido
            default: return .recusado
            }
        case .automacao, .navegadores, .redeLocal:
            return nil
        }
    }

    /// O macOS põe a janelinha dele (ou os Ajustes do Sistema) na frente do Deck: terminado o pedido, o Deck volta.
    func pedir(_ acesso: AcessoMac) async -> EstadoDoAcesso {
        let r = await pedirSemFoco(acesso)
        FocoDoDeck.trazer()
        return r
    }

    private func pedirSemFoco(_ acesso: AcessoMac) async -> EstadoDoAcesso {
        if (acesso == .bluetooth || acesso == .redeLocal) && !Variante.atual.pedeBluetoothERedeLocal { return .naoPedido }
        switch acesso {
        case .calendarios:
            let loja = EKEventStore()
            let ok = await withCheckedContinuation { c in
                if #available(macOS 14.0, *) {
                    // No macOS 14 o pedido antigo não dá leitura dos eventos: só o de acesso total.
                    loja.requestFullAccessToEvents { concedido, _ in c.resume(returning: concedido) }
                } else {
                    loja.requestAccess(to: .event) { concedido, _ in c.resume(returning: concedido) }
                }
            }
            return ok ? .liberado : .recusado
        case .automacao:
            return await Self.pedirAutomacao(VerificadorVivo.spotify)
        case .navegadores:
            var respostas: [EstadoDoAcesso] = []
            for n in navegadores { respostas.append(await Self.pedirAutomacao(n)) }
            if respostas.contains(.recusado) { return .recusado }
            return respostas.contains(.liberado) ? .liberado : .naoPedido
        case .acessibilidade:
            marcarPedido(acesso)
            let opcoes = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opcoes) ? .liberado : .recusado
        case .discoTotal:
            marcarPedido(acesso)
            // O macOS não tem janelinha para este: só dá para ligar nos Ajustes do Sistema.
            if DetectoresDoMac().discoTotal() { return .liberado }
            abrirAjustes(.discoTotal)
            return .recusado
        case .bluetooth:
            return await pedirBluetooth()
        case .redeLocal:
            return await Self.pedirRedeLocal(defaults: defaults)
        }
    }

    /// Abre a página certa dos Ajustes do Sistema e traz o Deck de volta quando a permissão mudar lá.
    func abrirAjustes(_ acesso: AcessoMac) {
        NSWorkspace.shared.open(acesso.enderecoDosAjustes)
        let defaults = defaults
        FocoDoDeck.vigiar { VerificadorVivo(defaults: defaults).ler(acesso)?.situacao }
    }

    /// Nome da página de Privacidade e Segurança de cada acesso.
    static func painel(_ acesso: AcessoMac) -> String {
        switch acesso {
        case .calendarios: return "Privacy_Calendars"
        case .automacao, .navegadores: return "Privacy_Automation"
        case .discoTotal: return "Privacy_AllFiles"
        case .acessibilidade: return "Privacy_Accessibility"
        case .bluetooth: return "Privacy_Bluetooth"
        case .redeLocal: return "Privacy_LocalNetwork"
        }
    }

    /// Lembra que o Deck pediu: sem isso, "não liberado" de Acessibilidade e Disco não diz se foi recusado.
    private func marcarPedido(_ acesso: AcessoMac) {
        defaults.set(true, forKey: VerificadorVivo.chavePedido(acesso))
    }

    /// Pergunta ao macOS se o Deck pode controlar o app. Com o app fechado o macOS não pergunta: fica como
    /// não pedido, e a pessoa tenta de novo com ele aberto. A chamada espera a resposta da pessoa, por isso
    /// roda fora da tela.
    private static func pedirAutomacao(_ bundle: String) async -> EstadoDoAcesso {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let alvo = NSAppleEventDescriptor(bundleIdentifier: bundle)
                let r = AEDeterminePermissionToAutomateTarget(alvo.aeDesc, typeWildCard, typeWildCard, true)
                switch r {
                case noErr: c.resume(returning: .liberado)
                case OSStatus(procNotFound): c.resume(returning: .naoPedido)
                default: c.resume(returning: .recusado)
                }
            }
        }
    }

    /// Criar o gerente é o que faz o macOS perguntar. Espera a pessoa responder (até 60 s).
    private func pedirBluetooth() async -> EstadoDoAcesso {
        if CBManager.authorization == .notDetermined {
            Self.gerenteDoBluetooth = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            for _ in 0..<200 where CBManager.authorization == .notDetermined { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        switch CBManager.authorization {
        case .allowedAlways: return .liberado
        case .notDetermined: return .naoPedido
        default:
            abrirAjustes(.bluetooth)
            return .recusado
        }
    }

    /// O macOS não diz se a Rede Local está liberada sem perguntar. Uma conexão curta ao endereço de multicast
    /// da rede local (o do Bonjour) faz o macOS perguntar, e o resultado fica guardado para a lista.
    private static func pedirRedeLocal(defaults: UserDefaults) async -> EstadoDoAcesso {
        let chave = VerificadorVivo.chaveUltima(AcessoMac.redeLocal.rawValue)
        let r: EstadoDoAcesso = await withCheckedContinuation { c in
            let fila = DispatchQueue(label: "deck.redelocal")
            let con = NWConnection(host: "224.0.0.251", port: 5353, using: .udp)
            let acabou = Acabou()
            let terminar: @Sendable (EstadoDoAcesso) -> Void = { r in
                fila.async { guard !acabou.sim else { return }; acabou.sim = true; con.cancel(); c.resume(returning: r) }
            }
            con.stateUpdateHandler = { estado in
                switch estado {
                case .ready: terminar(.liberado)
                // -65570 é kDNSServiceErr_PolicyDenied: o macOS negou a Rede Local ao Deck.
                case .waiting(.dns(let codigo)) where codigo == -65570: terminar(.recusado)
                case .failed: terminar(.naoPedido)
                default: break
                }
            }
            con.start(queue: fila)
            // Um pacote de consulta do Bonjour sem perguntas (só o cabeçalho de 12 bytes), inofensivo na rede.
            con.send(content: Data(count: 12), completion: .idempotent)
            fila.asyncAfter(deadline: .now() + 45) { terminar(.naoPedido) }
        }
        if r == .liberado { defaults.set("liberado", forKey: chave) }
        if r == .recusado { defaults.set("recusado", forKey: chave) }
        return r
    }

    private final class Acabou: @unchecked Sendable { var sim = false }
}
