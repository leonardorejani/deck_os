import Foundation

/// Onde está a página que o iPhone recebe: `painel/` se existir (no pacote do app ou no repo),
/// senão `prototipo/`. Procura subindo as pastas a partir dos pontos dados, como o DeckServidor.
enum PastaDaPagina {
    static func achar(pacote: URL?, partidas: [URL], fm: FileManager = .default) -> URL? {
        func pasta(_ u: URL) -> Bool {
            var ehPasta: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &ehPasta) && ehPasta.boolValue
        }
        // Instalado fora do repo (em /Applications) a página vem dentro do pacote: o painel, ou o protótipo enquanto o painel não existe.
        if let pacote {
            for nome in ["painel", "prototipo"] where pasta(pacote.appendingPathComponent(nome)) { return pacote.appendingPathComponent(nome) }
        }
        for nome in ["painel", "prototipo"] {
            for inicio in partidas {
                var dir = inicio
                for _ in 0..<10 {
                    let candidata = dir.appendingPathComponent(nome)
                    if pasta(candidata), fm.fileExists(atPath: dir.appendingPathComponent("SPEC.md").path) { return candidata }
                    let pai = dir.deletingLastPathComponent()
                    if pai == dir { break }
                    dir = pai
                }
            }
        }
        return nil
    }

    static func daInstalacao() -> URL? {
        achar(pacote: Bundle.main.resourceURL,
              partidas: [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), Bundle.main.bundleURL])
    }
}

/// A porta de partida e as seguintes: se a 4777 está ocupada, o Deck escolhe outra sozinho e o QR
/// já leva a certa (SPEC 9a, "Este Mac").
enum Portas {
    static let tentativas = 20

    static func candidatas(a partir: Int) -> [Int] {
        (0..<tentativas).map { partir + $0 }.filter { (1024...65535).contains($0) }
    }
}
