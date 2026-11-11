import Foundation

// Medida de vazão do Bluetooth (fase 7, prova técnica): decide o tamanho da capa e do estado nesse canal.
// Roda sobre o mesmo fio de bytes das sessões, antes de qualquer criptografia, para medir o rádio e não a
// conta. O Mac (servidor) obedece a um pedido de 5 bytes e o iPhone (cliente) cronometra. O espelho disto
// no Mac é mac/Nucleo/VazaoBluetooth.swift: mudou aqui, muda lá.
//
// Pedido: 1 byte de operação e 4 de tamanho (big endian).
//   'P'  eco curto: o Mac devolve 1 byte (mede a latência de ida e volta).
//   'D'  o Mac manda n bytes (descida, Mac para iPhone).
//   'U'  o iPhone manda n bytes depois do pedido (subida) e o Mac responde 'K' com o tempo que levou.

enum VazaoBluetooth {
    struct Resultado: Equatable, Sendable {
        var pings: [Double]
        var descidaBytes: Int
        var descidaSegundos: Double
        var subidaBytes: Int
        var subidaSegundos: Double

        var descidaKBs: Double { descidaSegundos > 0 ? Double(descidaBytes) / 1024 / descidaSegundos : 0 }
        var subidaKBs: Double { subidaSegundos > 0 ? Double(subidaBytes) / 1024 / subidaSegundos : 0 }
        var pingMedioMs: Double { pings.isEmpty ? 0 : pings.reduce(0, +) / Double(pings.count) * 1000 }
        var pingMaximoMs: Double { (pings.max() ?? 0) * 1000 }
    }

    private static func pedido(_ op: UInt8, _ n: Int) -> Data {
        Data([op, UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
    }

    private static func agora() -> Double { Date().timeIntervalSince1970 }

    /// Lado do Mac: atende até o fio acabar.
    static func servir(_ fluxo: FluxoBytes) {
        while let cab = fluxo.lerExato(5) {
            let b = [UInt8](cab)
            let n = Int(b[1]) << 24 | Int(b[2]) << 16 | Int(b[3]) << 8 | Int(b[4])
            guard n >= 0, n <= 4 * 1024 * 1024 else { return }
            switch b[0] {
            case UInt8(ascii: "P"):
                if !fluxo.escrever(Data([0x50])) { return }
            case UInt8(ascii: "D"):
                if !fluxo.escrever(Data(repeating: 0x44, count: n)) { return }
            case UInt8(ascii: "U"):
                let inicio = agora()
                guard fluxo.lerExato(n) != nil else { return }
                let ms = Int((agora() - inicio) * 1000)
                if !fluxo.escrever(pedido(UInt8(ascii: "K"), ms)) { return }
            default:
                return
            }
        }
    }

    /// Lado do iPhone: 5 pings, uma descida e uma subida de `bytes` cada. nil se o fio cair no meio.
    static func medir(_ fluxo: FluxoBytes, bytes: Int, pings: Int = 5) -> Resultado? {
        var latencias: [Double] = []
        for _ in 0..<pings {
            let t = agora()
            guard fluxo.escrever(pedido(UInt8(ascii: "P"), 0)), fluxo.lerExato(1) != nil else { return nil }
            latencias.append(agora() - t)
        }
        let td = agora()
        guard fluxo.escrever(pedido(UInt8(ascii: "D"), bytes)), fluxo.lerExato(bytes) != nil else { return nil }
        let descida = agora() - td

        let tu = agora()
        guard fluxo.escrever(pedido(UInt8(ascii: "U"), bytes) + Data(repeating: 0x55, count: bytes)), fluxo.lerExato(5) != nil else { return nil }
        let subida = agora() - tu
        return Resultado(pings: latencias, descidaBytes: bytes, descidaSegundos: descida, subidaBytes: bytes, subidaSegundos: subida)
    }
}
