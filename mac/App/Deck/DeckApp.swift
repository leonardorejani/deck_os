import SwiftUI
import AppKit

/// O Deck é um app de barra de menus (LSUIElement: sem ícone no Dock). Um ícone na barra abre o
/// menu, "Ajustes..." abre a janela, e o servidor do iPhone sobe junto com o app.
@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(DeckDelegado.self) private var delegado
    @StateObject private var modelo: ModeloApp
    private let testando = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @Environment(\.openWindow) private var abrirJanela

    init() {
        // Nos testes o app é só o hospedeiro: não sobe servidor nem mexe na config do dono.
        let testando = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let m = testando ? ModeloApp(config: Config.padrao(nomeMac: "Mac de teste")) : ModeloApp()
        _modelo = StateObject(wrappedValue: m)
        if !testando {
            m.iniciar()
            m.ligarRenovacao()
            // Só para a prova: `--renovar-agora` reinstala o app no iPhone assim que o Deck abre, e o resultado vai para o log.
            if CommandLine.arguments.contains("--renovar-agora") { Task { await m.executarRenovacao(manual: true) } }
        }
    }

    var body: some Scene {
        if !testando { ligarReabertura() }
        return cenas
    }

    @SceneBuilder private var cenas: some Scene {
        // A reabertura é ligada aqui, ao montar a cena, e não no label da barra: com o ícone escondido pelo macOS
        // o label pode nunca aparecer, e era justamente aí que o app não abria.
        // O item fica inserido sempre (nos testes, nunca). Se o macOS esconder o item (a pessoa desligou o
        // Deck em Ajustes do Sistema > Barra de Menus), o SwiftUI fecharia o app e o iPhone perderia o Mac:
        // aqui o app segue de pé e o servidor continua.
        MenuBarExtra(isInserted: Binding(get: { !testando }, set: { _ in })) {
            MenuDaBarra(modelo: modelo, acoes: AcoesDoMenu(
                abrirAjustes: { abrirAjustes() },
                abrirConfiguracaoInicial: { NSApp.activate(ignoringOtherApps: true); abrirJanela(id: "inicial") },
                sair: { SaidaDoApp.pedida = true; modelo.encerrar(); NSApp.terminate(nil) }))
                .preferredColorScheme(.dark)
        } label: {
            Image(nsImage: GlifoDaBarra.imagem)
                // Primeira abertura (sem config.json): a configuração inicial abre sozinha.
                .onAppear {
                    guard !testando else { return }
                    ItemDaBarra.conferirNaAbertura(modelo: modelo, abrirAjustes: { abrirAjustes() })
                    // `--ajustes=<seção>` abre os Ajustes direto nela (para conferir uma tela sem clicar).
                    if let secao = SecaoAjustes.daLinhaDeComando(CommandLine.arguments) { modelo.secao = secao; abrirAjustes() }
                    guard !modelo.configuracaoInicialFeita else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    abrirJanela(id: "inicial")
                }
        }
        .menuBarExtraStyle(.window)

        // Janela comum, não a cena Settings: num app sem Dock o `showSettingsWindow:` responde "ok" e não abre nada.
        Window("Ajustes", id: "ajustes") {
            JanelaAjustes(modelo: modelo, conferirIcone: { ItemDaBarra.conferir(modelo: modelo) })
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)

        Window("Configuração inicial", id: "inicial") {
            ConfiguracaoInicial(modelo: modelo)
                .frame(width: Tema.Medida.iniLarg, height: Tema.Medida.iniAlt)
                .background(Tema.Cor.telaFundo)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
    }

    /// Abrir o app de novo com ele rodando (Finder, Spotlight, `open -a`) leva à janela certa e para a frente.
    private func ligarReabertura() {
        DeckDelegado.aoReabrir = { [modelo] temJanela in
            ItemDaBarra.reconferir(modelo: modelo)
            switch Reabertura.destino(configuracaoInicialFeita: modelo.configuracaoInicialFeita, temJanelaVisivel: temJanela) {
            case .ajustes: abrirAjustes()
            case .configuracaoInicial: NSApp.activate(ignoringOtherApps: true); abrirJanela(id: "inicial")
            case .nenhum: NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Sem Dock, o app precisa vir para a frente antes de abrir a janela.
    private func abrirAjustes() {
        NSApp.activate(ignoringOtherApps: true)
        abrirJanela(id: "ajustes")
    }
}

/// O desenho da barra de menus: as quatro teclas do ícone, a primeira cheia, numa cor só (o macOS
/// pede ícone de uma cor ali e o pinta de acordo com o fundo).
enum GlifoDaBarra {
    static let imagem: NSImage = {
        let lado: CGFloat = 17
        let img = NSImage(size: NSSize(width: lado, height: lado), flipped: true) { _ in
            let k = lado / 18
            NSColor.black.setFill(); NSColor.black.setStroke()
            func quadro(_ x: CGFloat, _ y: CGFloat, cheio: Bool) {
                let r = NSRect(x: x * k, y: y * k, width: 6 * k, height: 6 * k)
                if cheio {
                    NSBezierPath(roundedRect: r, xRadius: 1.6 * k, yRadius: 1.6 * k).fill()
                } else {
                    let c = NSBezierPath(roundedRect: r, xRadius: 1.6 * k, yRadius: 1.6 * k)
                    c.lineWidth = 1.4 * k
                    c.stroke()
                }
            }
            quadro(2, 2, cheio: true); quadro(10, 2, cheio: false); quadro(2, 10, cheio: false); quadro(10, 10, cheio: false)
            return true
        }
        img.isTemplate = true
        return img
    }()
}
