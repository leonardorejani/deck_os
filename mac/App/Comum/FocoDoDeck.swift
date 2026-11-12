import AppKit

/// Quem pede um acesso ao macOS perde a frente: o pedido do sistema ou os Ajustes do Sistema abrem por cima do Deck e ele
/// fica atrás de tudo. Aqui o Deck volta sozinho: quando o pedido termina e, se foi preciso abrir os Ajustes do Sistema,
/// assim que a permissão muda lá (a espera é do núcleo, `PrimeiroPlano`).
@MainActor
enum FocoDoDeck {
    private static var espera: Task<Void, Never>?

    /// O Deck na frente, com as janelas dele (Ajustes, configuração inicial) acima das do sistema.
    static func trazer() {
        NSApp.activate(ignoringOtherApps: true)
        for janela in NSApp.windows where janela.isVisible && !janela.isMiniaturized && janela.canBecomeMain {
            janela.orderFrontRegardless()
        }
    }

    /// Fica olhando o acesso enquanto a pessoa está nos Ajustes do Sistema. Mudou, o Deck volta para a frente.
    /// Um pedido novo cancela a espera do anterior.
    static func vigiar(situacao ler: @escaping @MainActor () -> SituacaoDoAcesso?) {
        espera?.cancel()
        let inicial = ler()
        espera = Task {
            _ = await PrimeiroPlano.trazerQuandoMudar(inicial: inicial, ler: ler, trazer: { trazer() })
        }
    }
}
