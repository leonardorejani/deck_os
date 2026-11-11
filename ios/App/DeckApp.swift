import SwiftUI
import DeckCasca

/// O Deck no iPhone: a página do painel numa WKWebView em tela cheia, a ponte com o Swift e as
/// telas de pareamento por cima. Sem Mac no cabo, abre no estado "sem Mac" e procura sozinho.
@main
struct DeckApp: App {
    @Environment(\.scenePhase) private var fase
    @State private var casca = Montagem.casca()

    var body: some Scene {
        WindowGroup {
            Painel(casca: casca)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .background(Color.black)
                // A tela fica sempre acesa: o Deck é um painel de mesa.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: fase) { nova in
                    guard nova == .active else { return }
                    UIApplication.shared.isIdleTimerDisabled = true
                    // O iOS pode ter fechado a porta do cabo em segundo plano.
                    casca.retomar()
                }
        }
    }
}

/// Escolhe as peças do app. Sem argumentos de prova, é o app de verdade: código no Keychain, o cabo (porta do
/// loopback que o Mac alcança pelo USB) e o Bluetooth (o Mac anuncia, o iPhone conecta). Argumentos de prova
/// (ver Prova.swift) só desligam o cabo (-prova-sem-cabo) ou o derrubam depois de um tempo (-prova-cabo-sai-em).
enum Montagem {
    @MainActor
    static func casca() -> Casca {
        let vibrador = Vibrador()
        let args = ProcessInfo.processInfo.arguments
        // Prova técnica do Bluetooth: mede a vazão contra o Mac (DeckServidor --bt-vazao) e registra em Documents/prova.log.
        if args.contains("-prova-bt-vazao") {
            Task { _ = await ProvaBluetooth.vazao(log: { Prova.registrar($0) }) }
        }
        if let prova = Prova.ler(), prova.tela != Prova.telaReal {
            return prova.montar(vibrar: { vibrador.vibrar() })
        }
        let cofre = CofreKeychain()
        if args.contains("-prova-esquecer") { cofre.apagar() }
        let log: @Sendable (String) -> Void = { Prova.registrar($0) }
        let gerente = GerenteDoCabo(segredo: { cofre.ler()?.codigoAcesso }, log: log)
        let bluetooth = GerenteBluetooth(cofre: cofre, nomeDoIphone: UIDevice.current.name, log: log)
        let semCabo = args.contains("-prova-sem-cabo")
        let casca = Casca(pareador: PareadorCompleto(cabo: gerente, bluetooth: bluetooth), cofre: cofre, vibrar: { vibrador.vibrar() },
                          cabo: semCabo ? nil : gerente, bluetooth: bluetooth)
        casca.iniciar()
        if let i = args.firstIndex(of: "-prova-cabo-sai-em"), i + 1 < args.count, let s = Double(args[i + 1]) {
            // Faz o que o cabo puxado faz: a conexão com o Mac cai de repente.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
                gerente.parar()
                Prova.registrar("PROVA_CABO_SAIU o cabo foi derrubado")
            }
        }
        return casca
    }
}

/// Vibração leve do toque de tecla.
final class Vibrador: @unchecked Sendable {
    func vibrar() {
        DispatchQueue.main.async {
            let g = UIImpactFeedbackGenerator(style: .light)
            g.impactOccurred()
        }
    }
}

struct Painel: UIViewControllerRepresentable {
    let casca: Casca

    func makeUIViewController(context: Context) -> ControladorDoPainel {
        let controlador = ControladorDoPainel(casca: casca)
        Prova.ler()?.acompanhar(controlador)
        return controlador
    }
    func updateUIViewController(_ controlador: ControladorDoPainel, context: Context) {}
}
