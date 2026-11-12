import SwiftUI
import AppKit
import CoreServices

// Os apps instalados no Mac (com o ícone de verdade) e os Atalhos do app Atalhos, para o passo 2 do
// editor de tecla. A leitura do disco fica aqui e roda fora da tela. Nas fotos entra uma lista fixa.

struct AppDoMac: Equatable, Identifiable {
    /// O que o macOS mostra (Calendário).
    var nome: String
    /// O que vai para a tecla e para `open -a` (nome do arquivo, sem .app).
    var valor: String
    /// O .app (ícone tirado do sistema) ou um .png (só nas fotos).
    var caminhoDoIcone: String?

    var id: String { valor }
}

/// Ícones de app sem refazer a conta a cada desenho.
@MainActor
enum IconesDeApps {
    private static var cache: [String: NSImage] = [:]

    static func imagem(_ caminho: String) -> NSImage {
        if let c = cache[caminho] { return c }
        let img = caminho.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: caminho) : (NSImage(contentsOfFile: caminho) ?? NSImage())
        cache[caminho] = img
        return img
    }
}

enum LeitorDeApps {
    static let pastas = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                         NSHomeDirectory() + "/Applications"]
    /// O Finder mora fora das pastas de aplicativos.
    static let extras = ["/System/Library/CoreServices/Finder.app"]
    static let pastasDoSistema = ["/System/Library/CoreServices"]
    /// Quando o Spotlight ainda não sabe o que a pessoa mais abre.
    static let padraoMaisUsados = ["Safari", "Calendar", "Notes", "Terminal", "Finder", "Mail", "Music", "Spotify", "WhatsApp", "Messages"]
    static let quantosMaisUsados = 8

    /// Todos os apps das pastas de Aplicativos, de A a Z.
    static func ler(pastas: [String] = LeitorDeApps.pastas, extras: [String] = LeitorDeApps.extras) -> [AppDoMac] {
        let fm = FileManager.default
        var caminhos = extras.filter { fm.fileExists(atPath: $0) }
        for pasta in pastas {
            let itens = (try? fm.contentsOfDirectory(atPath: pasta)) ?? []
            caminhos += itens.filter { $0.hasSuffix(".app") }.map { pasta + "/" + $0 }
        }
        var vistos = Set<String>()
        var apps: [AppDoMac] = []
        for c in caminhos {
            let arquivo = (c as NSString).lastPathComponent
            let valor = String(arquivo.dropLast(4))
            guard vistos.insert(valor).inserted else { continue }
            let nome = fm.displayName(atPath: c).replacingOccurrences(of: ".app", with: "")
            apps.append(AppDoMac(nome: nome, valor: valor, caminhoDoIcone: c))
        }
        return apps.sorted { $0.nome.compare($1.nome, locale: Locale(identifier: "pt_BR")) == .orderedAscending }
    }

    /// Quantas vezes o Spotlight viu a pessoa abrir o app.
    static func usos(_ caminho: String) -> Int {
        guard let item = MDItemCreate(nil, caminho as CFString),
              let n = MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber else { return 0 }
        return n.intValue
    }

    static func maisUsados(_ apps: [AppDoMac], usos: (AppDoMac) -> Int) -> [AppDoMac] {
        let usados = apps.map { ($0, usos($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        if usados.count >= quantosMaisUsados { return Array(usados.prefix(quantosMaisUsados)) }
        // completa com os de sempre, sem repetir
        var r = usados
        for nome in padraoMaisUsados where r.count < quantosMaisUsados {
            if let a = apps.first(where: { $0.valor == nome }), !r.contains(a) { r.append(a) }
        }
        return r
    }

    /// Saída do `shortcuts list`: um atalho por linha.
    static func atalhos(daSaida saida: String) -> [String] {
        saida.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// O que o editor mostra e busca. Carrega uma vez, fora da tela.
@MainActor
final class CatalogoDeApps: ObservableObject {
    @Published private(set) var apps: [AppDoMac] = []
    @Published private(set) var maisUsados: [AppDoMac] = []
    /// nil enquanto procura.
    @Published private(set) var atalhos: [String]?
    private var carregou = false

    /// O catálogo do app: carrega ao abrir o Deck e é o que os Ajustes usam, para os ícones das teclas já estarem prontos.
    static let compartilhado = CatalogoDeApps()

    init() {}

    /// Lista pronta (as fotos e os testes).
    init(apps: [AppDoMac], maisUsados: [AppDoMac], atalhos: [String]) {
        self.apps = apps
        self.maisUsados = maisUsados
        self.atalhos = atalhos
        carregou = true
    }

    func carregarSeFaltar() {
        guard !carregou else { return }
        carregou = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let todos = LeitorDeApps.ler()
            // A lista sai antes dos "mais usados" (o Spotlight demora): os ícones das teclas só precisam dela.
            await self?.recebeuTodos(todos)
            let mais = LeitorDeApps.maisUsados(todos) { a in a.caminhoDoIcone.map(LeitorDeApps.usos) ?? 0 }
            await self?.recebeuMaisUsados(mais)
            let r = ExecutorShell().rodar("shortcuts list")
            await self?.recebeuAtalhos(r.status == 0 ? LeitorDeApps.atalhos(daSaida: r.saida) : [])
        }
    }

    private func recebeuTodos(_ todos: [AppDoMac]) { apps = todos }
    private func recebeuMaisUsados(_ mais: [AppDoMac]) { maisUsados = mais }
    private func recebeuAtalhos(_ l: [String]) { atalhos = l }

    func app(_ valor: String) -> AppDoMac? { apps.first { $0.valor == valor } ?? maisUsados.first { $0.valor == valor } }
}
