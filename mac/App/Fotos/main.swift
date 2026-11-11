import SwiftUI
import AppKit

// DeckFotos: fotografa as telas do app (ImageRenderer) com dados de exemplo iguais aos do protótipo,
// para comparar lado a lado com a foto da mesma tela em prototipo/mac.html.
//
// Uso:  DeckFotos <pasta-de-saida> [nome-da-tela ...]
//   Sem nomes, fotografa todas as telas de Telas.swift. Cada uma vira <pasta>/mac-swift-<tela>.png
//   em escala 2 (o protótipo é fotografado em escala 2 também).
//
// Fluxo completo (script mac/App/Fotos/comparar.sh):
//   1. xcodegen + xcodebuild do alvo DeckFotos
//   2. este programa gera .teste/mac-swift-<tela>.png
//   3. prototipo-fotos.mjs gera .teste/mac-proto-<tela>.png (Playwright no prototipo/)
//   4. a página de comparação junta as duas e a diferença em .teste/mac-comparacao-<tela>.png
// Tela nova: uma entrada em Telas.swift e uma em prototipo-fotos.mjs, com o mesmo nome.
// As fotos ficam em .teste/, fora do git.

let argumentos = Array(CommandLine.arguments.dropFirst())
guard let destino = argumentos.first else {
    FileHandle.standardError.write(Data("Uso: DeckFotos <pasta-de-saida> [tela ...]\n".utf8))
    exit(2)
}
let pedidas = Set(argumentos.dropFirst())

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

@MainActor func fotografar() -> Int32 {
    let pasta = URL(fileURLWithPath: destino, isDirectory: true)
    try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    var falhas: Int32 = 0
    for tela in CatalogoDeFotos.telas where pedidas.isEmpty || pedidas.contains(tela.nome) {
        var vista = AnyView(tela.vista().environment(\.colorScheme, .dark).environment(\.fotografando, true))
        if let t = tela.tamanho { vista = AnyView(vista.frame(width: t.width, height: t.height)) }
        let r = ImageRenderer(content: vista)
        r.scale = 2
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Não consegui fotografar \(tela.nome).\n".utf8))
            falhas += 1
            continue
        }
        let arquivo = pasta.appendingPathComponent("mac-swift-\(tela.nome).png")
        do { try png.write(to: arquivo); print("ok \(arquivo.path) (\(cg.width)x\(cg.height))") } catch {
            FileHandle.standardError.write(Data("Não consegui gravar \(arquivo.path).\n".utf8))
            falhas += 1
        }
    }
    return falhas
}

exit(MainActor.assumeIsolated { fotografar() })
