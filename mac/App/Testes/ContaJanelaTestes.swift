import XCTest
import SwiftUI
@testable import Deck

/// "Clico pra adicionar contas e nada acontece" (Leonardo, 11/11/2026). A janela Adicionar conta era um NSHostingView
/// pendurado dentro do NSHostingView da janela (o SwiftUI avisa que isso não é suportado) e não desenhava. Aqui a janela
/// de Ajustes de verdade é montada fora da tela, o clique é o mesmo método do cartão e o resultado é conferido no desenho.
@MainActor
final class ContaJanelaTestes: XCTestCase {
    private func casa(perfis: [String], codex: Bool) throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("deck-casa-\(UUID().uuidString)")
        for p in perfis { try FileManager.default.createDirectory(at: raiz.appendingPathComponent(".config/claude-account/logins/\(p)"), withIntermediateDirectories: true) }
        if codex {
            try FileManager.default.createDirectory(at: raiz.appendingPathComponent(".codex"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: raiz.appendingPathComponent(".codex/auth.json").path, contents: Data("{}".utf8))
        }
        return raiz
    }

    private func desenho(_ v: NSView) -> NSBitmapImageRep? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }

    private func esperar(_ s: Double = 0.4) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    func testClicarEmAdicionarContaMostraAJanelaEAchaClaudeECodex() async throws {
        let c = try casa(perfis: ["leo"], codex: true)
        defer { try? FileManager.default.removeItem(at: c) }
        let m = ModeloApp(config: Config.padrao(nomeMac: "Mac de teste"))
        m.secao = .uso
        let painel = PainelUso(casa: c, cofre: CofreFalso())
        let anterior = PainelUso.atual
        PainelUso.atual = painel
        defer { PainelUso.atual = anterior }

        let host = NSHostingView(rootView: JanelaAjustes(modelo: m))
        let janela = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 732), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        janela.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: 732)
        await esperar()
        let antes = try XCTUnwrap(desenho(host))

        painel.abrirConta(modelo: m)   // o que o clique no cartão "Adicionar conta" chama
        await esperar()
        let depois = try XCTUnwrap(desenho(host))

        XCTAssertEqual(Set(painel.achadas.map(\.id)), ["claude-leo", "codex"], "acha as contas do Claude e do Codex deste Mac")
        // O véu da janela cobre o canto de baixo (fora da caixa): antes era a cor do fundo, depois tem que mudar.
        let x = Int(Double(antes.pixelsWide) * 0.9), y = Int(Double(antes.pixelsHigh) * 0.9)
        let a = try XCTUnwrap(antes.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let d = try XCTUnwrap(depois.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        XCTAssertNotEqual(a, d, "a janela Adicionar conta tem que aparecer por cima dos Ajustes (véu no canto)")
        janela.contentView = nil
    }
}
