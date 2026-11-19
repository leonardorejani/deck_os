import Foundation
#if canImport(AppKit)
import AppKit
#endif

// Escrever ou ditar no iPhone e mandar para o app em foco no Mac (SPEC 13, item 7 de 19/11/2026).
// A ideia do caminho (guardar a prancheta, pôr o texto, Cmd+V, devolver a prancheta) vem do WinDock
// (MIT), public/pc-clipboard.js e remote-keyboard.js. Aqui o Mac faz tudo e o texto nunca vai para o log.

/// Tudo o que estava na prancheta: cada item com seus tipos e dados, para devolver como estava (imagem, arquivo, texto).
struct PranchetaGuardada: Equatable, Sendable {
    var itens: [[String: Data]] = []
}

protocol PranchetaDoMac: Sendable {
    /// Quantas vezes a prancheta mudou. Se mudar entre o Cmd+V e a devolução, alguém copiou algo e a devolução não vale.
    func contagem() -> Int
    func guardar() -> PranchetaGuardada
    /// Troca o conteúdo pelo texto e devolve a contagem de depois.
    func colocar(texto: String) -> Int
    func devolver(_ guardada: PranchetaGuardada)
}

/// O app que está na frente no Mac agora.
struct AppEmFoco: Equatable, Sendable {
    var bundle: String
    var nome: String
}

struct ErroColar: Error, Equatable {
    var status: Int
    var texto: String
}

protocol ColadorDeTexto: Sendable {
    func colar(_ texto: String) -> ErroColar?
}

final class ColadorReal: ColadorDeTexto, @unchecked Sendable {
    /// Teto de caracteres de um envio (o mesmo do campo no iPhone).
    static let limite = 32_000
    /// O que o Deck nunca cola: ele mesmo, a tela de login e o Finder (Cmd+V ali cola arquivo, não texto).
    static let recusados: [String] = ["com.leonardorejani.deck", "com.apple.loginwindow", "com.apple.finder", "com.apple.ScreenSaver.Engine",
                                      "com.apple.SecurityAgent", "com.apple.dock"]
    static let erroSemApp = "Nenhum app do Mac está pronto para receber texto. Abra o app e clique no campo."
    static let erroOcupado = "O Mac ainda está colando o texto anterior."

    private let prancheta: any PranchetaDoMac
    private let emFoco: @Sendable () -> AppEmFoco?
    private let temAcessibilidade: @Sendable () -> Bool
    private let enviarTecla: @Sendable (Combinacao) -> Void
    private let pausar: @Sendable (TimeInterval) -> Void
    private let espera: TimeInterval
    private let trava = NSLock()

    init(prancheta: (any PranchetaDoMac)? = nil,
         emFoco: @escaping @Sendable () -> AppEmFoco? = { ColadorReal.appEmFocoDoSistema() },
         temAcessibilidade: @escaping @Sendable () -> Bool = { AcoesSistema.temAcessibilidade() },
         enviarTecla: @escaping @Sendable (Combinacao) -> Void = { AcoesSistema.enviar($0) },
         pausar: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         espera: TimeInterval = 0.5) {
        self.prancheta = prancheta ?? PranchetaPadrao.vinda()
        self.emFoco = emFoco
        self.temAcessibilidade = temAcessibilidade
        self.enviarTecla = enviarTecla
        self.pausar = pausar
        self.espera = espera
    }

    /// Texto válido para colar: não vazio, até o limite, sem caractere de controle além de quebra de linha e tabulação.
    static func textoValido(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= limite else { return false }
        return !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && !"\n\r\t".unicodeScalars.contains($0) }
    }

    static func aceitavel(_ app: AppEmFoco?) -> Bool {
        guard let app, !app.bundle.isEmpty else { return false }
        return !recusados.contains { app.bundle == $0 || app.bundle.hasPrefix($0 + ".") }
    }

    func colar(_ texto: String) -> ErroColar? {
        guard Self.textoValido(texto) else {
            return ErroColar(status: 400, texto: "Escreva um texto de até \(Self.limite / 1000) mil caracteres.")
        }
        guard temAcessibilidade() else { return ErroColar(status: 422, texto: ExecutorAcoes.erroAcessibilidade) }
        // Antes de mexer na prancheta: sem app aceitável na frente, nada é tocado.
        guard Self.aceitavel(emFoco()) else { return ErroColar(status: 409, texto: Self.erroSemApp) }
        guard trava.try() else { return ErroColar(status: 409, texto: Self.erroOcupado) }
        defer { trava.unlock() }

        let guardada = prancheta.guardar()
        let contagem = prancheta.colocar(texto: texto)
        enviarTecla(Combinacao(codigo: Teclas.codigos["v"] ?? 9, modificadores: .comando))
        // O app lê a prancheta de forma assíncrona: devolver cedo demais colaria o conteúdo antigo.
        pausar(espera)
        // Se alguém copiou outra coisa nesse meio tempo, o que está lá é mais novo que o guardado: não pisar.
        if prancheta.contagem() == contagem { prancheta.devolver(guardada) }
        return nil
    }

    static func appEmFocoDoSistema() -> AppEmFoco? {
        #if canImport(AppKit)
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        return AppEmFoco(bundle: id, nome: app.localizedName ?? id)
        #else
        return nil
        #endif
    }
}

/// A prancheta do macOS. Sem AppKit (Linux do CI) não há prancheta: colar responde que não dá.
enum PranchetaPadrao {
    static func vinda() -> any PranchetaDoMac {
        #if canImport(AppKit)
        return PranchetaGeral()
        #else
        return PranchetaIndisponivel()
        #endif
    }
}

struct PranchetaIndisponivel: PranchetaDoMac {
    func contagem() -> Int { 0 }
    func guardar() -> PranchetaGuardada { PranchetaGuardada() }
    func colocar(texto: String) -> Int { 0 }
    func devolver(_ guardada: PranchetaGuardada) {}
}

#if canImport(AppKit)
struct PranchetaGeral: PranchetaDoMac {
    func contagem() -> Int { NSPasteboard.general.changeCount }

    func guardar() -> PranchetaGuardada {
        let itens = (NSPasteboard.general.pasteboardItems ?? []).map { item -> [String: Data] in
            var tipos: [String: Data] = [:]
            for tipo in item.types { if let dados = item.data(forType: tipo) { tipos[tipo.rawValue] = dados } }
            return tipos
        }
        return PranchetaGuardada(itens: itens)
    }

    func colocar(texto: String) -> Int {
        let p = NSPasteboard.general
        p.clearContents()
        p.setString(texto, forType: .string)
        return p.changeCount
    }

    func devolver(_ guardada: PranchetaGuardada) {
        let p = NSPasteboard.general
        p.clearContents()
        let itens = guardada.itens.map { tipos -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (tipo, dados) in tipos { item.setData(dados, forType: NSPasteboard.PasteboardType(tipo)) }
            return item
        }
        if !itens.isEmpty { p.writeObjects(itens) }
    }
}
#endif
