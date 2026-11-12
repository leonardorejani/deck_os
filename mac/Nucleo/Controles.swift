import Foundation
#if os(macOS)
import CoreGraphics
import ObjectiveC
#endif

// "Controles do Mac" no iPhone: volume (com mudo), brilho da tela e brilho do teclado. Cada controle só aparece
// se o Mac mostrou que consegue: o que não funciona neste Mac volta nil e some da tela, em vez de fingir.

/// O que o iPhone pode mexer agora. Campo nil = este Mac não oferece (ou não deu para ler): a tela esconde.
struct EstadoControles: Codable, Equatable, Sendable {
    /// Volume de saída, de 0 a 100. nil quando a saída de som não tem volume (algumas telas HDMI).
    var volume: Int? = nil
    var mudo: Bool? = nil
    /// Brilho da tela interna, de 0 a 100. nil sem tela interna (Mac fechado numa tela externa, Mac mini...).
    var brilho: Int? = nil
    /// Brilho da luz do teclado, de 0 a 100. nil sem teclado iluminado, ou sem teclado interno.
    var teclado: Int? = nil
}

protocol ControlesDoMac: Sendable {
    func estado() -> EstadoControles
    /// De 0 a 100. Erro em texto, ou nil se deu certo.
    func definirVolume(_ valor: Int) -> String?
    func definirMudo(_ mudo: Bool) -> String?
    func definirBrilho(_ valor: Int) -> String?
    func definirTeclado(_ valor: Int) -> String?
}

/// Os dois brilhos, que dependem de APIs privadas do macOS. Nos testes entra um falso.
protocol BrilhoDoMac: Sendable {
    /// De 0 a 100, ou nil se este Mac não tem o recurso.
    func lerTela() -> Int?
    func definirTela(_ valor: Int) -> Bool
    func lerTeclado() -> Int?
    func definirTeclado(_ valor: Int) -> Bool
}

/// Sem o recurso (Linux do CI, ou framework privado que sumiu numa versão futura do macOS).
struct BrilhoIndisponivel: BrilhoDoMac {
    func lerTela() -> Int? { nil }
    func definirTela(_ valor: Int) -> Bool { false }
    func lerTeclado() -> Int? { nil }
    func definirTeclado(_ valor: Int) -> Bool { false }
}

enum Controles {
    /// Lê a saída de `osascript -e "get volume settings"`:
    /// "output volume:40, input volume:47, alert volume:57, output muted:false".
    /// Saída sem volume próprio dá "missing value": volume e mudo voltam nil.
    static func lerVolume(_ saida: String) -> (volume: Int?, mudo: Bool?) {
        var campos: [String: String] = [:]
        for parte in saida.split(separator: ",") {
            let kv = parte.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if kv.count == 2 { campos[kv[0]] = kv[1] }
        }
        guard let v = campos["output volume"].flatMap({ Int($0) }) else { return (nil, nil) }
        return (max(0, min(100, v)), campos["output muted"].map { $0 == "true" })
    }

    static func limitar(_ v: Int) -> Int { max(0, min(100, v)) }

    /// Teclado que dá para controlar. "Suprimida" é só o auto-brilho de luz ambiente: a escrita funciona (provado com a tampa aberta).
    static func tecladoServe(interno: Bool, suprimida _: Bool) -> Bool { interno }
}

final class ControlesReais: ControlesDoMac, @unchecked Sendable {
    private let executor: any Executor
    private let brilho: any BrilhoDoMac

    init(executor: any Executor = ExecutorShell(), brilho: (any BrilhoDoMac)? = nil) {
        self.executor = executor
        #if os(macOS)
        self.brilho = brilho ?? BrilhoReal()
        #else
        self.brilho = brilho ?? BrilhoIndisponivel()
        #endif
    }

    func estado() -> EstadoControles {
        let r = executor.rodar("osascript -e \(Shell.aspas("get volume settings"))")
        let (volume, mudo) = r.status == 0 ? Controles.lerVolume(r.saida) : (nil, nil)
        return EstadoControles(volume: volume, mudo: mudo, brilho: brilho.lerTela(), teclado: brilho.lerTeclado())
    }

    func definirVolume(_ valor: Int) -> String? {
        let r = executor.rodar("osascript -e \(Shell.aspas("set volume output volume \(Controles.limitar(valor))"))")
        return r.status == 0 ? nil : "Não consegui mudar o volume do Mac."
    }

    func definirMudo(_ mudo: Bool) -> String? {
        let r = executor.rodar("osascript -e \(Shell.aspas("set volume output muted \(mudo)"))")
        return r.status == 0 ? nil : "Não consegui mudar o mudo do Mac."
    }

    func definirBrilho(_ valor: Int) -> String? {
        guard brilho.lerTela() != nil else { return "Este Mac não deixa mexer no brilho da tela." }
        return brilho.definirTela(Controles.limitar(valor)) ? nil : "Não consegui mudar o brilho da tela."
    }

    func definirTeclado(_ valor: Int) -> String? {
        guard brilho.lerTeclado() != nil else { return "Este Mac não tem luz no teclado para mexer agora." }
        return brilho.definirTeclado(Controles.limitar(valor)) ? nil : "Não consegui mudar a luz do teclado."
    }
}

#if os(macOS)
/// DisplayServices (tela interna) e CoreBrightness (teclado) são frameworks privados da Apple: sem contrato, então tudo
/// é carregado na hora (dlopen) e qualquer peça que faltar vira nil, nunca queda. Só a tela interna: tela externa não responde.
struct BrilhoReal: BrilhoDoMac {
    private typealias LerTela = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias PorTela = @convention(c) (UInt32, Float) -> Int32
    private typealias KLer = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KBool = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias KPor = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let caminhoTela = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let caminhoTeclado = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    // MARK: Tela

    private static func telaInterna() -> UInt32? {
        var n: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &n) == .success else { return nil }
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func simbolo<T>(_ nome: String, _ tipo: T.Type) -> T? {
        guard let h = dlopen(caminhoTela, RTLD_NOW), let s = dlsym(h, nome) else { return nil }
        return unsafeBitCast(s, to: tipo)
    }

    func lerTela() -> Int? {
        guard let id = Self.telaInterna(), let ler = Self.simbolo("DisplayServicesGetBrightness", LerTela.self) else { return nil }
        var v: Float = -1
        guard ler(id, &v) == 0, v.isFinite, v >= 0 else { return nil }
        return Controles.limitar(Int((v * 100).rounded()))
    }

    func definirTela(_ valor: Int) -> Bool {
        guard let id = Self.telaInterna(), let por = Self.simbolo("DisplayServicesSetBrightness", PorTela.self) else { return false }
        return por(id, Float(valor) / 100) == 0
    }

    // MARK: Teclado

    /// O cliente do teclado e o id do teclado interno. Sem os dois, o Mac não tem luz de teclado para mexer.
    private static func teclado() -> (cliente: NSObject, id: UInt64)? {
        guard dlopen(caminhoTeclado, RTLD_NOW) != nil,
              let classe = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let c = classe.init()
        let listar = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard c.responds(to: listar),
              let lista = c.perform(listar)?.takeRetainedValue() as? [NSNumber] else { return nil }
        for n in lista {
            let id = n.uint64Value
            guard Controles.tecladoServe(interno: booleano(c, "isKeyboardBuiltIn:", id), suprimida: booleano(c, "isBacklightSuppressedOnKeyboard:", id)) else { continue }
            return (c, id)
        }
        return nil
    }

    private static func booleano(_ c: NSObject, _ nome: String, _ id: UInt64) -> Bool {
        let s = NSSelectorFromString(nome)
        guard c.responds(to: s), let imp = c.method(for: s) else { return false }
        return unsafeBitCast(imp, to: KBool.self)(c, s, id)
    }

    func lerTeclado() -> Int? {
        guard let (c, id) = Self.teclado() else { return nil }
        let s = NSSelectorFromString("brightnessForKeyboard:")
        guard c.responds(to: s), let imp = c.method(for: s) else { return nil }
        let v = unsafeBitCast(imp, to: KLer.self)(c, s, id)
        guard v.isFinite, v >= 0 else { return nil }
        return Controles.limitar(Int((v * 100).rounded()))
    }

    func definirTeclado(_ valor: Int) -> Bool {
        guard let (c, id) = Self.teclado() else { return false }
        let s = NSSelectorFromString("setBrightness:forKeyboard:")
        guard c.responds(to: s), let imp = c.method(for: s) else { return false }
        return unsafeBitCast(imp, to: KPor.self)(c, s, Float(valor) / 100, id)
    }
}
#endif
