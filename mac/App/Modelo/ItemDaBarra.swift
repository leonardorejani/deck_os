import AppKit

/// O item do Deck na barra de menus pode ser desligado pela pessoa (Ajustes do Sistema > Barra de Menus).
/// O app não encerra por isso (o servidor do iPhone segue de pé), mas sem o ícone não há como abrir o menu:
/// no primeiro uso em que o item aparece escondido, o app explica como liberar.
enum ItemDaBarra {
    struct Janela: Equatable {
        var classe: String
        var visivel: Bool
        /// A janela está dentro de alguma tela. O macOS manda o item escondido para fora dela.
        var naTela: Bool
    }

    static let urlDosAjustes = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    private static let chaveAvisado = "avisoDaBarraEscondidaFeito"

    /// Escondido = nenhuma janela de item de barra visível dentro de uma tela.
    static func escondido(janelas: [Janela]) -> Bool {
        !janelas.contains { $0.classe.contains("StatusBar") && $0.visivel && $0.naTela }
    }

    /// Avisa só na primeira vez que o item aparece escondido.
    static func deveAvisar(escondido: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard escondido, !defaults.bool(forKey: chaveAvisado) else { return false }
        defaults.set(true, forKey: chaveAvisado)
        return true
    }

    @MainActor static func janelasDoApp() -> [Janela] {
        NSApp.windows.map { j in
            // isVisible fica verdadeiro mesmo com o item escondido pelo macOS: o que muda é a oclusão (sem o bit `visible`).
            Janela(classe: String(describing: type(of: j)), visivel: j.isVisible && j.occlusionState.contains(.visible),
                   naTela: NSScreen.screens.contains { $0.frame.intersects(j.frame) })
        }
    }

    /// Olha o item pouco depois de o app abrir (o macOS leva um instante para posicioná-lo). Escondido: o aviso
    /// fica no topo dos Ajustes (enquanto durar) e, na primeira vez, os Ajustes abrem sozinhos.
    @MainActor static func conferirNaAbertura(modelo: ModeloApp, abrirAjustes: @escaping @MainActor () -> Void,
                                              depoisDe segundos: Double = 3, defaults: UserDefaults = .standard,
                                              vigiarCada intervalo: Double = intervaloDaVigia,
                                              janelas: @escaping @MainActor () -> [Janela] = { janelasDoApp() }) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            conferir(modelo: modelo, vigiarCada: intervalo, janelas: janelas)
            guard modelo.iconeEscondido, deveAvisar(escondido: true, defaults: defaults) else { return }
            abrirAjustes()
        }
    }

    /// Reconfere quando a pessoa reabre o app, abre os Ajustes ou volta para o Deck: o aviso some sozinho se ela já liberou o ícone.
    @MainActor static func reconferir(modelo: ModeloApp) { conferir(modelo: modelo) }

    static let intervaloDaVigia = 3.0

    /// Olha o item agora e, se ele está escondido, segue olhando a cada poucos segundos até aparecer: a pessoa libera o
    /// ícone em Ajustes do Sistema com os Ajustes do Deck abertos, e o aviso tem que sair sem ela precisar reabrir nada.
    @MainActor static func conferir(modelo: ModeloApp, vigiarCada intervalo: Double = intervaloDaVigia,
                                    janelas: @escaping @MainActor () -> [Janela] = { janelasDoApp() }) {
        let escondidoAgora = escondido(janelas: janelas())
        if modelo.iconeEscondido != escondidoAgora { modelo.iconeEscondido = escondidoAgora }
        guard escondidoAgora, modelo.vigiaDoIcone == nil else { return }
        modelo.vigiaDoIcone = Task { @MainActor [weak modelo] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalo * 1_000_000_000))
                guard let modelo, !Task.isCancelled else { return }
                let ainda = escondido(janelas: janelas())
                if modelo.iconeEscondido != ainda { modelo.iconeEscondido = ainda }
                if !ainda { modelo.vigiaDoIcone = nil; return }
            }
        }
    }

    static let tituloDoAviso = "O ícone do Deck está escondido na barra de menus"
    static let caminhoDoAviso = "Ajustes do Sistema > Barra de Menus > Permitir na barra de menus"
    static let apoioDoAviso = "Sem o ícone você não abre o menu. Se já estiver permitido, falta espaço na barra: feche outro ícone. Se abriu o Deck por um terminal, feche e abra pelo Finder. O iPhone continua funcionando."
}

/// O que o app faz quando a pessoa o abre de novo (duplo clique, Spotlight, `open -a`) com ele já rodando.
/// Num app só de barra de menus isso era ignorado: sem o ícone visível não havia jeito de abrir nada.
enum Reabertura {
    enum Destino: Equatable { case ajustes, configuracaoInicial, nenhum }

    static func destino(configuracaoInicialFeita: Bool, temJanelaVisivel: Bool) -> Destino {
        if temJanelaVisivel { return .nenhum }
        return configuracaoInicialFeita ? .ajustes : .configuracaoInicial
    }
}

/// Quando o macOS esconde o item do Deck na barra, o SwiftUI chama `terminate` sozinho e o app sumia (o
/// iPhone perdia o Mac). O app de barra de menus só encerra quando a pessoa manda: pelo "Sair do Deck", pelo
/// ⌘Q, por um evento do sistema (desligar, reiniciar, sair da conta) ou por um pedido de outro app.
enum SaidaDoApp {
    /// Ligado pelo "Sair do Deck" antes de chamar `terminate`.
    nonisolated(unsafe) static var pedida = false

    static func permitir(pedida: Bool, vemDeEventoDoSistema: Bool, vemDeAcaoDaPessoa: Bool) -> Bool {
        pedida || vemDeEventoDoSistema || vemDeAcaoDaPessoa
    }
}

final class DeckDelegado: NSObject, NSApplicationDelegate {
    /// Ligados pelo `DeckApp` assim que a cena existe (o delegado nasce antes do modelo e do `openWindow`).
    @MainActor static var aoReabrir: ((Bool) -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in DeckDelegado.aoReabrir?(flag) }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let tipo = NSApp.currentEvent?.type
        let pessoa = tipo == .keyDown || tipo == .leftMouseUp || tipo == .leftMouseDown
        let ok = SaidaDoApp.permitir(pedida: SaidaDoApp.pedida,
                                     vemDeEventoDoSistema: NSAppleEventManager.shared().currentAppleEvent != nil,
                                     vemDeAcaoDaPessoa: pessoa)
        return ok ? .terminateNow : .terminateCancel
    }
}
