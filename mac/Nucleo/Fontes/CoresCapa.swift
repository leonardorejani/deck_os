import Foundation
#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics
#endif

struct Pixel: Equatable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

/// As duas cores dominantes da capa, para o degradê do player. Algoritmo puro: agrupa os pixels em
/// 8 níveis por canal (512 grupos) e escolhe o grupo de maior peso, dando mais peso a cor viva
/// (uma capa com fundo cinza e um objeto vermelho tem que dar vermelho, não cinza).
enum CoresCapa {
    /// Menos que isso, o pixel é preto demais para servir de degradê.
    static let brilhoMinimo = 24
    /// Distância mínima entre as duas cores, no espaço RGB, para não devolver duas quase iguais.
    static let distanciaMinima = 80.0

    static func dominantes(_ pixels: [Pixel]) -> [String] {
        struct Grupo { var n = 0; var r = 0; var g = 0; var b = 0 }
        var grupos: [Int: Grupo] = [:]
        for p in pixels where max(p.r, p.g, p.b) >= brilhoMinimo {
            let chave = Int(p.r >> 5) << 6 | Int(p.g >> 5) << 3 | Int(p.b >> 5)
            var g = grupos[chave] ?? Grupo()
            g.n += 1; g.r += Int(p.r); g.g += Int(p.g); g.b += Int(p.b)
            grupos[chave] = g
        }
        // Média de cada grupo e o peso dele. Empate resolvido pela chave, para o resultado ser sempre igual.
        let medias: [(chave: Int, r: Int, g: Int, b: Int, peso: Double)] = grupos.map { chave, g in
            let r = g.r / g.n, gg = g.g / g.n, b = g.b / g.n
            let mx = Double(max(r, gg, b)), mn = Double(min(r, gg, b))
            let saturacao = mx == 0 ? 0 : (mx - mn) / mx
            return (chave, r, gg, b, Double(g.n) * (0.5 + saturacao))
        }.sorted { $0.peso != $1.peso ? $0.peso > $1.peso : $0.chave < $1.chave }
        guard let primeira = medias.first else { return [] }
        func distancia(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
            let dr = Double(a.r - b.r), dg = Double(a.g - b.g), db = Double(a.b - b.b)
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        let c1 = (r: primeira.r, g: primeira.g, b: primeira.b)
        // A segunda é o grupo de maior peso que seja bem diferente da primeira. Capa de uma cor só
        // ganha uma versão mais escura da mesma cor.
        let segunda = medias.dropFirst().first { distancia(c1, (r: $0.r, g: $0.g, b: $0.b)) >= distanciaMinima }
        let c2 = segunda.map { (r: $0.r, g: $0.g, b: $0.b) } ?? (r: c1.r * 45 / 100, g: c1.g * 45 / 100, b: c1.b * 45 / 100)
        return [Cor.hex(c1.r, c1.g, c1.b), Cor.hex(c2.r, c2.g, c2.b)]
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    /// Reduz a imagem (PNG, JPEG...) a um quadrado de `lado` pixels e devolve os pixels opacos.
    static func pixels(de dados: Data, lado: Int = 32) -> [Pixel]? {
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil) else { return nil }
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let imagem = CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary),
              let espaco = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = imagem.width, h = imagem.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let desenhou = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: espaco, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard desenhou else { return nil }
        var saida: [Pixel] = []
        saida.reserveCapacity(w * h)
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] >= 128 {
            saida.append(Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2]))
        }
        return saida
    }
    #endif
}
