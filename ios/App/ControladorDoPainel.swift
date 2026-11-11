import UIKit
import WebKit
import DeckCasca

/// A WKWebView em tela cheia com a página do painel. O painel não sabe que está dentro de um app:
/// ele usa window.DeckCanal, que a ponte (Web/ponte.js) define e o Swift atende pelo canal em uso.
final class ControladorDoPainel: UIViewController, WKScriptMessageHandlerWithReply, WKURLSchemeHandler, WKNavigationDelegate {
    let casca: Casca
    private(set) var web: WKWebView!
    private var capasParadas = Set<ObjectIdentifier>()

    /// Chamado quando a página termina de carregar (o modo de prova espera por isto).
    var aoCarregar: (() -> Void)?

    init(casca: Casca) {
        self.casca = casca
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func loadView() {
        let conf = WKWebViewConfiguration()
        conf.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "deck")
        conf.setURLSchemeHandler(self, forURLScheme: Ponte.esquemaDaCapa)

        let web = WKWebView(frame: .zero, configuration: conf)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.allowsLinkPreview = false
        web.navigationDelegate = self
        #if DEBUG
        web.isInspectable = true
        #endif
        self.web = web
        view = web

        casca.executarJS = { [weak web] js in web?.evaluateJavaScript(js, completionHandler: nil) }
        casca.recarregarPagina = { [weak self] in self?.carregarPagina() }
        carregarPagina()
    }

    // MARK: Página

    private func carregarPagina() {
        // Recarregar refaz o script de início: o código e a etapa nascem certos.
        web.configuration.userContentController.removeAllUserScripts()
        for script in scripts() { web.configuration.userContentController.addUserScript(script) }
        guard let pasta = Bundle.main.url(forResource: "Pagina", withExtension: nil) else {
            web.loadHTMLString("<body style='background:#000;color:#fff;font:16px sans-serif;padding:24px'>A página do painel não está no app.</body>", baseURL: nil)
            return
        }
        web.loadFileURL(pasta.appendingPathComponent("index.html"), allowingReadAccessTo: pasta)
    }

    /// Começo: o estado e o código guardado, o CSS das telas novas e a ponte. Fim: as telas.
    private func scripts() -> [WKUserScript] {
        let css = (try? String(contentsOf: recurso("nativo", "css"), encoding: .utf8)) ?? ""
        let ponte = (try? String(contentsOf: recurso("ponte", "js", em: "Web"), encoding: .utf8)) ?? ""
        let telas = (try? String(contentsOf: recurso("casca", "js", em: "Web"), encoding: .utf8)) ?? ""
        let cssJS = "(function(){var s=document.createElement('style');s.textContent=\(Self.literal(css));var t=document.head||document.documentElement;if(t){t.appendChild(s)}else{document.addEventListener('DOMContentLoaded',function(){document.head.appendChild(s)})}})();"
        return [
            WKUserScript(source: casca.scriptDeInicio() + cssJS + ponte, injectionTime: .atDocumentStart, forMainFrameOnly: true),
            WKUserScript(source: telas, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
        ]
    }

    private func recurso(_ nome: String, _ extensao: String, em pasta: String? = nil) -> URL {
        Bundle.main.url(forResource: nome, withExtension: extensao, subdirectory: pasta) ?? URL(fileURLWithPath: "/nao-existe/\(nome).\(extensao)")
    }

    private static func literal(_ texto: String) -> String {
        guard let dados = try? JSONEncoder().encode(texto) else { return "\"\"" }
        return String(decoding: dados, as: UTF8.self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { aoCarregar?() }

    // MARK: Ponte

    func userContentController(_ controle: WKUserContentController, didReceive mensagem: WKScriptMessage) async -> (Any?, String?) {
        guard JSONSerialization.isValidJSONObject(mensagem.body),
              let dados = try? JSONSerialization.data(withJSONObject: mensagem.body) else {
            return ("{\"erro\":\"Não entendi o pedido da página.\"}", nil)
        }
        return (await casca.tratar(dados), nil)
    }

    // MARK: Capa (deckcapa://)

    func webView(_ webView: WKWebView, start tarefa: any WKURLSchemeTask) {
        guard let url = tarefa.request.url else { return tarefa.didFailWithError(URLError(.badURL)) }
        let id = ObjectIdentifier(tarefa as AnyObject)
        Task { @MainActor in
            let r = await casca.capa(url)
            if capasParadas.remove(id) != nil { return }
            let resposta = HTTPURLResponse(url: url, statusCode: r.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": r.tipo, "Cache-Control": url.host == "apps" ? "private, max-age=86400" : "no-store"])!
            tarefa.didReceive(resposta)
            tarefa.didReceive(r.corpo)
            tarefa.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop tarefa: any WKURLSchemeTask) {
        capasParadas.insert(ObjectIdentifier(tarefa as AnyObject))
    }
}
