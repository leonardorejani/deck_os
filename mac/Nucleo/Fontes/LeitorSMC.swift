import Foundation
#if os(macOS)
import IOKit

/// Lê a rotação das ventoinhas no SMC (o chip que cuida de sensores e energia). Só leitura, sem privilégio.
/// Chaves: FNum (quantas), F<n>Ac (rotação agora) e F<n>Mx (rotação máxima). Apple Silicon devolve "flt " (float) e Mac Intel "fpe2".
enum LeitorSMC {
    private struct Versao { var maior: UInt8 = 0, menor: UInt8 = 0, build: UInt8 = 0, reservado: UInt8 = 0, lancamento: UInt16 = 0 }
    private struct LimiteP { var versao: UInt16 = 0, tamanho: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    /// Os 3 bytes finais completam o alinhamento do struct em C (sem eles o conjunto tem 76 bytes e o SMC recusa a chamada: o certo são 80).
    private struct InfoChave { var tamanho: UInt32 = 0, tipo: UInt32 = 0, atributos: UInt8 = 0, preenchimento: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Dados {
        var chave: UInt32 = 0
        var versao = Versao()
        var limite = LimiteP()
        var info = InfoChave()
        var resultado: UInt8 = 0
        var status: UInt8 = 0
        var comando: UInt8 = 0
        var dado32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    private static let lerChave: UInt8 = 5, lerInfo: UInt8 = 9
    static var tamanhoDoStruct: Int { MemoryLayout<Dados>.size }

    private static func codigo(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private static func chamar(_ conexao: io_connect_t, _ entrada: inout Dados) -> Dados? {
        var saida = Dados()
        var tamanho = MemoryLayout<Dados>.size
        let r = IOConnectCallStructMethod(conexao, 2, &entrada, MemoryLayout<Dados>.size, &saida, &tamanho)
        return r == KERN_SUCCESS && saida.resultado == 0 ? saida : nil
    }

    private static func ler(_ conexao: io_connect_t, _ nome: String) -> (tipo: UInt32, bytes: [UInt8])? {
        var e = Dados(); e.chave = codigo(nome); e.comando = lerInfo
        guard let info = chamar(conexao, &e)?.info, info.tamanho > 0, info.tamanho <= 32 else { return nil }
        var l = Dados(); l.chave = codigo(nome); l.info.tamanho = info.tamanho; l.comando = lerChave
        guard let d = chamar(conexao, &l) else { return nil }
        let todos = withUnsafeBytes(of: d.bytes) { Array($0) }
        return (info.tipo, Array(todos.prefix(Int(info.tamanho))))
    }

    private static func numero(_ v: (tipo: UInt32, bytes: [UInt8])) -> Double? {
        switch v.tipo {
        case codigo("flt "):
            guard v.bytes.count == 4 else { return nil }
            return Double(Float(bitPattern: UInt32(v.bytes[0]) | UInt32(v.bytes[1]) << 8 | UInt32(v.bytes[2]) << 16 | UInt32(v.bytes[3]) << 24))
        case codigo("fpe2"):
            guard v.bytes.count == 2 else { return nil }
            return Double((Int(v.bytes[0]) << 6) + (Int(v.bytes[1]) >> 2))
        case codigo("ui8 "): return v.bytes.first.map(Double.init)
        case codigo("ui16"): return v.bytes.count == 2 ? Double(Int(v.bytes[0]) << 8 | Int(v.bytes[1])) : nil
        default: return nil
        }
    }

    /// Rotação de cada ventoinha e a maior rotação entre as máximas. nil sem ventoinha ou sem acesso ao SMC.
    static func ventoinhas() -> (rpm: [Int], maximo: Int)? {
        let servico = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard servico != 0 else { return nil }
        defer { IOObjectRelease(servico) }
        var conexao: io_connect_t = 0
        guard IOServiceOpen(servico, mach_task_self_, 0, &conexao) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conexao) }
        guard let n = ler(conexao, "FNum").flatMap(numero), n >= 1, n <= 8 else { return nil }
        var rpm: [Int] = [], maximo = 0
        for i in 0..<Int(n) {
            guard let atual = ler(conexao, "F\(i)Ac").flatMap(numero), atual.isFinite else { continue }
            rpm.append(Int(max(0, atual).rounded()))
            if let m = ler(conexao, "F\(i)Mx").flatMap(numero), m.isFinite { maximo = max(maximo, Int(m.rounded())) }
        }
        return rpm.isEmpty ? nil : (rpm, maximo)
    }
}
#else
enum LeitorSMC {
    static func ventoinhas() -> (rpm: [Int], maximo: Int)? { nil }
}
#endif
