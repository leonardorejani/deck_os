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

/// Um passo do envio da combinação: a tecla desce ou sobe com as flags dos modificadores.
struct PassoDeTecla: Equatable {
    let codigo: UInt16
    let descendo: Bool
    let modificadores: Modificadores
}

extension Teclas {
    /// O que o Deck posta no HID para apertar a combinação: a tecla desce e sobe, e os dois eventos
    /// levam os modificadores (um app que escuta o atalho global confere as flags de cada evento).
    static func passos(_ c: Combinacao) -> [PassoDeTecla] {
        [true, false].map { PassoDeTecla(codigo: c.codigo, descendo: $0, modificadores: c.modificadores) }
    }

    /// Ordem fixa do texto gravado: o mesmo "ctrl+opt+cmd+shift" que o gravador sempre escreveu.
    private static let ordemDoTexto: [(Modificadores, String)] = [(.fn, "fn"), (.controle, "ctrl"), (.opcao, "opt"), (.comando, "cmd"), (.shift, "shift")]

    /// Escreve a combinação no formato do config.json. Nil se a tecla não existe ou se faltou modificador
    /// (combinação sem modificador dispararia a tecla solta em qualquer app).
    static func escrever(modificadores: Modificadores, tecla: String) -> String? {
        guard !modificadores.isEmpty, codigos[tecla] != nil else { return nil }
        return (ordemDoTexto.filter { modificadores.contains($0.0) }.map(\.1) + [tecla]).joined(separator: "+")
    }

    /// Teclas do seletor na tela, por grupo. Só nomes que o `codigos` entende (o teste cobra).
    static let grupos: [GrupoDeTeclas] = [
        GrupoDeTeclas(nome: "Letras", teclas: "abcdefghijklmnopqrstuvwxyz".map { TeclaDoSeletor(nome: String($0), rotulo: String($0).uppercased()) }),
        GrupoDeTeclas(nome: "Números", teclas: "1234567890".map { TeclaDoSeletor(nome: String($0), rotulo: String($0)) }),
        GrupoDeTeclas(nome: "F1 a F12", teclas: (1...12).map { TeclaDoSeletor(nome: "f\($0)", rotulo: "F\($0)") }),
        GrupoDeTeclas(nome: "Setas", teclas: [("left", "←"), ("up", "↑"), ("down", "↓"), ("right", "→"),
                                              ("home", "Home"), ("end", "End"), ("pageup", "Page Up"), ("pagedown", "Page Down")]
            .map { TeclaDoSeletor(nome: $0.0, rotulo: $0.1) }),
        GrupoDeTeclas(nome: "Outras", teclas: [("space", "Espaço"), ("return", "Return"), ("tab", "Tab"), ("delete", "Delete"), ("esc", "Esc"),
                                               ("-", "-"), ("=", "="), ("[", "["), ("]", "]"), (";", ";"), ("'", "'"), (",", ","), (".", "."),
                                               ("/", "/"), ("\\", "\\"), ("`", "`")]
            .map { TeclaDoSeletor(nome: $0.0, rotulo: $0.1) }),
    ]
}

struct TeclaDoSeletor: Equatable, Identifiable {
    let nome: String
    let rotulo: String
    var id: String { nome }
}

struct GrupoDeTeclas: Equatable, Identifiable {
    let nome: String
    let teclas: [TeclaDoSeletor]
    var id: String { nome }
}

/// A combinação sendo montada na tela, sem apertar nada: modificadores ligados e a tecla escolhida.
/// Só vira texto (e vai para a config) quando está completa.
struct MontagemDeCombinacao: Equatable {
    var modificadores: Modificadores = []
    var tecla: String?

    init() {}

    /// Parte de um texto já gravado ("cmd+shift+4"). Texto que não entende começa vazio.
    init(valor: String) {
        guard let c = Teclas.ler(valor), let nome = Teclas.nome(doCodigo: c.codigo) else { return }
        modificadores = c.modificadores
        tecla = nome
    }

    /// O texto da combinação, ou nil enquanto falta modificador ou tecla.
    var valor: String? { tecla.flatMap { Teclas.escrever(modificadores: modificadores, tecla: $0) } }

    /// O que falta, em português simples, para o aviso embaixo do seletor. Nil quando está completa.
    var faltaDizer: String? {
        switch (modificadores.isEmpty, tecla == nil) {
        case (true, true): return "Ligue pelo menos um modificador e escolha a tecla."
        case (true, false): return "Ligue pelo menos um modificador."
        case (false, true): return "Escolha a tecla."
        case (false, false): return nil
        }
    }

    mutating func alternar(_ m: Modificadores) {
        if modificadores.contains(m) { modificadores.remove(m) } else { modificadores.insert(m) }
    }
}

extension Teclas {
    /// Nome da tecla a partir do código virtual (o inverso de `codigos`). O nome mais legível quando há apelidos.
    static func nome(doCodigo codigo: UInt16) -> String? {
        let preferidos = ["return", "left", "right", "down", "up", "space"]
        let candidatos = codigos.filter { $0.value == codigo }.map(\.key)
        if let p = preferidos.first(where: candidatos.contains) { return p }
        return candidatos.min { ($0.count, $0) < ($1.count, $1) }
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
