import Foundation

/// Modificadores sem CoreGraphics, para o núcleo compilar no Linux do CI.
/// O app converte para CGEventFlags na hora de teclar.
struct Modificadores: OptionSet, Equatable, Sendable {
    let rawValue: UInt8
    static let comando = Modificadores(rawValue: 1 << 0)
    static let controle = Modificadores(rawValue: 1 << 1)
    static let opcao = Modificadores(rawValue: 1 << 2)
    static let shift = Modificadores(rawValue: 1 << 3)
    static let fn = Modificadores(rawValue: 1 << 4)
}

struct Combinacao: Equatable {
    /// Código virtual de tecla do macOS (o mesmo do CGKeyCode).
    let codigo: UInt16
    let modificadores: Modificadores
}

/// Converte texto tipo "ctrl+opt+cmd+k" em código de tecla + modificadores (layout ANSI/ABNT físico).
enum Teclas {
    static let codigos: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "espaco": 49,
        "`": 50, "delete": 51, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "esquerda": 123, "direita": 124, "baixo": 125, "cima": 126,
    ]

    static func ler(_ texto: String) -> Combinacao? {
        let partes = texto.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modificadores: Modificadores = []
        var codigo: UInt16?
        for p in partes {
            switch p {
            case "cmd", "command": modificadores.insert(.comando)
            case "ctrl", "control": modificadores.insert(.controle)
            case "opt", "option", "alt": modificadores.insert(.opcao)
            case "shift": modificadores.insert(.shift)
            case "fn": modificadores.insert(.fn)
            default:
                guard codigo == nil, let c = codigos[p] else { return nil }
                codigo = c
            }
        }
        guard let c = codigo else { return nil }
        return Combinacao(codigo: c, modificadores: modificadores)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension Modificadores {
    /// Flags do CGEvent equivalentes, para o app teclar de verdade no macOS.
    var flagsCG: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.comando) { f.insert(.maskCommand) }
        if contains(.controle) { f.insert(.maskControl) }
        if contains(.opcao) { f.insert(.maskAlternate) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.fn) { f.insert(.maskSecondaryFn) }
        return f
    }
}
#endif
