import Foundation
#if canImport(AppKit)
import AppKit
#endif

// Os apps instalados no Mac de quem usa: nome, id do pacote e ícone. É o que o editor de tecla lista
// (GET /api/apps) para escolher o app. Nada aqui é fixo para um Mac: tudo vem das pastas de aplicativos.

/// O que a API devolve de cada app.
struct AppInstalado: Codable, Equatable, Sendable {
    /// O que o macOS mostra ("Calculadora").
    var nome: String
    /// O que vai na tecla e no `open -a` (nome do arquivo sem .app: "Calculator").
    var valor: String
    /// Id do pacote ("com.apple.calculator"), que também é a chave das rotas de ícone e ações.
    var bundle: String
    /// Abre endereço da internet (http e https): só estes aceitam as ações de link e Gmail.
    var navegador: Bool
}

/// O app achado no disco, com o que só o Mac precisa saber e a API não mostra.
struct AppAchado: Equatable, Sendable {
    var app: AppInstalado
    var caminho: String
    /// Declara tipos de documento: aceita a ação "abrir um arquivo ou pasta neste app".
    var abreArquivos: Bool
}

struct DescobridorDeApps: Sendable {
    var pastas: [String]
    /// Apps fora das pastas de aplicativos (o Finder mora em CoreServices).
    var extras: [String]
    /// Nome que o macOS mostra. No Mac é o do Finder (já traduzido), fora dele o nome do arquivo.
    var nomeExibido: @Sendable (String) -> String

    static func padrao(casa: String = NSHomeDirectory()) -> DescobridorDeApps {
        DescobridorDeApps(
            pastas: ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications", casa + "/Applications"],
            extras: ["/System/Library/CoreServices/Finder.app"],
            nomeExibido: { caminho in
                #if os(macOS)
                return FileManager.default.displayName(atPath: caminho).replacingOccurrences(of: ".app", with: "")
                #else
                return DescobridorDeApps.semExtensao(caminho)
                #endif
            })
    }

    static func semExtensao(_ caminho: String) -> String {
        let arquivo = (caminho as NSString).lastPathComponent
        return arquivo.hasSuffix(".app") ? String(arquivo.dropLast(4)) : arquivo
    }

    /// Todos os apps, de A a Z. Cada pasta é lida até um nível abaixo (Utilitários, pastas de loja), e
    /// app repetido (mesmo id de pacote) vale só o primeiro.
    func listar() -> [AppAchado] {
        let fm = FileManager.default
        var caminhos = extras.filter { fm.fileExists(atPath: $0) }
        for pasta in pastas {
            for item in ((try? fm.contentsOfDirectory(atPath: pasta)) ?? []).sorted() where !item.hasPrefix(".") {
                let completo = pasta + "/" + item
                if item.hasSuffix(".app") {
                    caminhos.append(completo)
                } else {
                    let dentro = ((try? fm.contentsOfDirectory(atPath: completo)) ?? []).sorted()
                    caminhos += dentro.filter { $0.hasSuffix(".app") }.map { completo + "/" + $0 }
                }
            }
        }
        var vistos = Set<String>()
        var achados: [AppAchado] = []
        for c in caminhos {
            guard let a = ler(c), vistos.insert(a.app.bundle).inserted else { continue }
            achados.append(a)
        }
        return achados.sorted { $0.app.nome.compare($1.app.nome, locale: Locale(identifier: "pt_BR")) == .orderedAscending }
    }

    /// Lê o Info.plist do app. Sem id de pacote, ou app que só roda em segundo plano, não entra na lista.
    func ler(_ caminho: String) -> AppAchado? {
        guard let dados = try? Data(contentsOf: URL(fileURLWithPath: caminho + "/Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: dados, format: nil)) as? [String: Any],
              let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty,
              (info["LSBackgroundOnly"] as? Bool) != true else { return nil }
        let esquemas = (info["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { ($0["CFBundleURLSchemes"] as? [String] ?? []).map { $0.lowercased() } }
        let nome = nomeExibido(caminho)
        return AppAchado(
            app: AppInstalado(nome: nome.isEmpty ? Self.semExtensao(caminho) : nome, valor: Self.semExtensao(caminho),
                              bundle: bundle, navegador: esquemas.contains("http") && esquemas.contains("https")),
            caminho: caminho,
            abreArquivos: !(info["CFBundleDocumentTypes"] as? [Any] ?? []).isEmpty || bundle == "com.apple.finder")
    }
}

/// Ícone de um app em PNG. Só o macOS sabe desenhar: nos outros sistemas devolve nil.
protocol FabricaDeIcones: Sendable {
    func png(doApp caminho: String, lado: Int) -> Data?
}

struct FabricaDeIconesReal: FabricaDeIcones {
    func png(doApp caminho: String, lado: Int) -> Data? {
        #if canImport(AppKit)
        let imagem = NSWorkspace.shared.icon(forFile: caminho)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let contexto = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = contexto
        imagem.draw(in: NSRect(x: 0, y: 0, width: lado, height: lado), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

/// O que o roteador pede sobre os apps do Mac.
protocol ProvedorDeApps: Sendable {
    func apps() -> [AppInstalado]
    /// nil: app que não existe neste Mac (ou sem ícone).
    func icone(bundle: String) -> Data?
    /// nil: app que não existe neste Mac.
    func acoes(bundle: String) -> [AcaoDisponivel]?
}

/// A lista de apps lida do disco, guardada por um tempo curto: o editor pede a lista e depois um
/// ícone por app, e reler ~200 pacotes a cada pedido seria à toa.
final class AppsDoMac: ProvedorDeApps, @unchecked Sendable {
    private let descobridor: DescobridorDeApps
    private let icones: FabricaDeIcones
    private let pastaDeCache: URL?
    private let catalogo: CatalogoDeAcoes
    private let agora: @Sendable () -> Date
    private let validade: TimeInterval
    private let trava = NSLock()
    private var lista: [AppAchado] = []
    private var lidaEm: Date?

    static let ladoDoIcone = 64

    init(descobridor: DescobridorDeApps = .padrao(), icones: FabricaDeIcones = FabricaDeIconesReal(),
         pastaDeCache: URL? = nil, executor: any Executor = ExecutorShell(),
         agora: @escaping @Sendable () -> Date = { Date() }, validade: TimeInterval = 30) {
        self.descobridor = descobridor
        self.icones = icones
        self.pastaDeCache = pastaDeCache
        self.catalogo = CatalogoDeAcoes(executor: executor)
        self.agora = agora
        self.validade = validade
    }

    /// ~/Library/Caches/Deck/icones
    static func pastaDeCachePadrao() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Deck/icones", isDirectory: true)
    }

    private func achados() -> [AppAchado] {
        trava.lock(); defer { trava.unlock() }
        if let l = lidaEm, agora().timeIntervalSince(l) < validade { return lista }
        lista = descobridor.listar()
        lidaEm = agora()
        return lista
    }

    /// O id do pacote só vale se for de um app que a lista achou: o texto que chega pela rota nunca vira caminho.
    private func achado(_ bundle: String) -> AppAchado? { achados().first { $0.app.bundle == bundle } }

    func apps() -> [AppInstalado] { achados().map(\.app) }

    func icone(bundle: String) -> Data? {
        guard let a = achado(bundle) else { return nil }
        let arquivo = pastaDeCache.map { $0.appendingPathComponent(Self.nomeDoCache(a)) }
        if let arquivo, let guardado = try? Data(contentsOf: arquivo), !guardado.isEmpty { return guardado }
        guard let png = icones.png(doApp: a.caminho, lado: Self.ladoDoIcone), !png.isEmpty else { return nil }
        if let arquivo {
            try? FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: arquivo, options: .atomic)
        }
        return png
    }

    /// O app atualizado (mudou a data do pacote) ganha ícone novo, sem apagar nada do que ficou para trás.
    static func nomeDoCache(_ a: AppAchado) -> String {
        let data = (try? FileManager.default.attributesOfItem(atPath: a.caminho))?[.modificationDate] as? Date
        return "\(a.app.bundle)-\(Int(data?.timeIntervalSince1970 ?? 0))-\(ladoDoIcone).png"
    }

    func acoes(bundle: String) -> [AcaoDisponivel]? {
        if bundle == CatalogoDeAcoes.navegadorPadrao { return catalogo.acoes(para: nil) }
        return achado(bundle).map { catalogo.acoes(para: $0) }
    }
}
