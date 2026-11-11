import AppKit

/// Ao concluir a configuração, o menu da barra abre sozinho para mostrar onde o Deck mora. O
/// MenuBarExtra não tem chamada para isso: o jeito é clicar no botão do ícone, que o AppKit guarda
/// numa janela própria da barra de menus.
enum MenuDaBarraAberto {
    @MainActor static func abrir() {
        for janela in NSApp.windows where String(describing: type(of: janela)).contains("StatusBar") {
            if let botao = botao(em: janela.contentView) {
                botao.performClick(nil)
                return
            }
        }
    }

    private static func botao(em vista: NSView?) -> NSButton? {
        guard let vista else { return nil }
        if let b = vista as? NSButton { return b }
        for filha in vista.subviews { if let b = botao(em: filha) { return b } }
        return nil
    }
}
