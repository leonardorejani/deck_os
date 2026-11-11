import Foundation
#if os(macOS)
import ApplicationServices
import CoreGraphics
#endif

/// Parte das ações que só existe no macOS. No Linux do CI vira respostas neutras.
enum AcoesSistema {
    static func temAcessibilidade() -> Bool {
        #if os(macOS)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// Mostra o pedido de acesso do sistema (usado pelo app na fase 2). Devolve se já está liberado.
    @discardableResult
    static func pedirAcessibilidade() -> Bool {
        #if os(macOS)
        // Texto da constante kAXTrustedCheckOptionPrompt, que o Swift 6 não deixa ler direto.
        let opcoes = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opcoes)
        #else
        return false
        #endif
    }

    static func enviar(_ c: Combinacao) {
        #if os(macOS)
        let origem = CGEventSource(stateID: .hidSystemState)
        for descendo in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: origem, virtualKey: c.codigo, keyDown: descendo) else { continue }
            ev.flags = c.modificadores.flagsCG
            ev.post(tap: .cghidEventTap)
        }
        #endif
    }
}
