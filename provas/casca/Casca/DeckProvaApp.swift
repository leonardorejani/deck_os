import SwiftUI
import WebKit

/// Prova 0.3: a página do protótipo dentro de um WKWebView, em tela cheia e com a tela sempre acesa.
@main
struct DeckProvaApp: App {
    var body: some Scene {
        WindowGroup {
            Painel()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

struct Painel: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if let pasta = Bundle.main.url(forResource: "prototipo", withExtension: nil) {
            web.loadFileURL(pasta.appendingPathComponent("index.html"), allowingReadAccessTo: pasta)
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}
