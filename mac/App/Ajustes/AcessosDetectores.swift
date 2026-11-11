import Foundation
import AppKit
import ApplicationServices
import EventKit
import CoreBluetooth

/// Como está um acesso do macOS, pelo que o macOS deixa saber sem abrir janela nenhuma.
enum SituacaoDoAcesso: Equatable {
    case liberado
    /// O macOS nunca perguntou: o botão é "Permitir" e o pedido sai do próprio Deck.
    case naoPedido
    case recusado
    /// O macOS não deixa conferir agora (o Spotify está fechado, por exemplo). O texto diz o que fazer.
    case semComoSaber(String)
}

/// Um acesso e o que se sabe dele, uma linha da seção Acessos do Mac.
struct AcessoLido: Identifiable, Equatable {
    var acesso: AcessoMac
    var situacao: SituacaoDoAcesso
    /// Complemento da linha (quais navegadores, de onde veio a leitura).
    var detalhe: String? = nil

    var id: String { acesso.rawValue }
}

/// A resposta do macOS sobre controlar outro app por AppleScript.
enum RespostaDeAutomacao: Equatable {
    case liberado, recusado
    /// O macOS ainda não perguntou (-1744).
    case naoPerguntado
    /// O macOS só responde com o app aberto.
    case fechado
    case naoInstalado
}

/// Cada leitura do estado, atrás de um protocolo: os testes trocam por respostas combinadas, e o app de
/// verdade só consulta, nunca pergunta (nenhuma destas funções abre alerta do macOS).
protocol DetectoresDeAcesso {
    func calendario() -> SituacaoDoAcesso
    func bluetooth() -> SituacaoDoAcesso
    /// Acessibilidade só diz "liberado" ou "não": o macOS não separa "nunca pedi" de "recusei".
    func acessibilidade() -> Bool
    /// Acesso Total ao Disco também: ou consegue abrir um arquivo protegido, ou não.
    func discoTotal() -> Bool
    func automacao(bundle: String) -> RespostaDeAutomacao
    func instalado(bundle: String) -> Bool
}

struct DetectoresDoMac: DetectoresDeAcesso {
    func calendario() -> SituacaoDoAcesso {
        // Pelo número, como em FonteAgenda.temPermissao: 3 é "autorizado" (acesso total no macOS 14 em diante).
        // 4 é "só escrever" (macOS 14): o Deck não consegue ler os eventos, então vale como não liberado.
        switch EKEventStore.authorizationStatus(for: .event).rawValue {
        case 0: return .naoPedido
        case 3: return .liberado
        default: return .recusado
        }
    }

    func bluetooth() -> SituacaoDoAcesso {
        switch CBManager.authorization {
        case .notDetermined: return .naoPedido
        case .allowedAlways: return .liberado
        default: return .recusado
        }
    }

    func acessibilidade() -> Bool { AXIsProcessTrusted() }

    /// Só quem tem Acesso Total ao Disco abre estes arquivos. O primeiro que existe decide: abrir não faz o
    /// macOS perguntar nada, só recusa com EPERM.
    func discoTotal() -> Bool {
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        for caminho in ["/Library/Application Support/com.apple.TCC/TCC.db", casa + "/Library/Safari/Bookmarks.plist"] {
            let fd = open(caminho, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return false
    }

    func automacao(bundle: String) -> RespostaDeAutomacao {
        guard instalado(bundle: bundle) else { return .naoInstalado }
        // Com o app fechado o macOS responde "não achei o processo", que não diz nada sobre a permissão.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { return .fechado }
        let alvo = NSAppleEventDescriptor(bundleIdentifier: bundle)
        guard let desc = alvo.aeDesc else { return .fechado }
        // askUserIfNeeded false: só consulta.
        let r = AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        switch r {
        case noErr: return .liberado
        case OSStatus(errAEEventNotPermitted): return .recusado
        case OSStatus(procNotFound): return .fechado
        default: return .naoPerguntado
        }
    }

    func instalado(bundle: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
    }
}
