import SwiftUI
import Foundation

// Os ícones do protótipo são SVG de linha (24 x 24, traço da cor do texto). Em vez de redesenhar
// cada um, o app lê o mesmo texto SVG de prototipo/dados.js e mac.js e desenha com Canvas. Assim o
// traço, o arredondamento e o tamanho saem iguais ao protótipo.

struct Svg: View {
    private let desenho: DesenhoSvg
    private let lado: CGFloat

    init(_ marcacao: String, lado: CGFloat) {
        self.desenho = DesenhoSvg.de(marcacao)
        self.lado = lado
    }

    var body: some View {
        Canvas { ctx, tamanho in
            let k = tamanho.width / desenho.caixa
            ctx.scaleBy(x: k, y: k)
            for forma in desenho.formas {
                if forma.preenche { ctx.fill(forma.caminho, with: .foreground) }
                if forma.largura > 0 {
                    ctx.stroke(forma.caminho, with: .foreground,
                               style: StrokeStyle(lineWidth: forma.largura, lineCap: forma.ponta, lineJoin: forma.juncao))
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }
}

struct FormaSvg {
    var caminho: Path
    var preenche: Bool
    var largura: CGFloat
    var ponta: CGLineCap
    var juncao: CGLineJoin
}

struct DesenhoSvg {
    var caixa: CGFloat
    var formas: [FormaSvg]

    private static var cache: [String: DesenhoSvg] = [:]

    static func de(_ marcacao: String) -> DesenhoSvg {
        if let c = cache[marcacao] { return c }
        let leitor = LeitorSvg()
        let xml = XMLParser(data: Data(marcacao.utf8))
        xml.delegate = leitor
        xml.parse()
        let d = DesenhoSvg(caixa: leitor.caixa, formas: leitor.formas)
        cache[marcacao] = d
        return d
    }
}

private final class LeitorSvg: NSObject, XMLParserDelegate {
    var caixa: CGFloat = 24
    var formas: [FormaSvg] = []
    private var raiz: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement nome: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if nome == "svg" {
            raiz = a
            if let vb = a["viewBox"]?.split(separator: " ").compactMap({ Double($0) }), vb.count == 4 { caixa = CGFloat(vb[2]) }
            return
        }
        var caminho = Path()
        func n(_ k: String) -> CGFloat { CGFloat(Double(a[k] ?? "") ?? 0) }
        switch nome {
        case "path": caminho = CaminhoSvg.ler(a["d"] ?? "")
        case "rect":
            let r = CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
            caminho = n("rx") > 0 ? Path(roundedRect: r, cornerRadius: n("rx")) : Path(r)
        case "circle":
            let c = n("r")
            caminho = Path(ellipseIn: CGRect(x: n("cx") - c, y: n("cy") - c, width: c * 2, height: c * 2))
        default: return
        }
        func prop(_ k: String) -> String? { a[k] ?? raiz[k] }
        let preenche = (prop("fill") ?? "currentColor") != "none"
        let tracado = prop("stroke") != nil && prop("stroke") != "none"
        let ponta: CGLineCap = prop("stroke-linecap") == "round" ? .round : prop("stroke-linecap") == "square" ? .square : .butt
        let juncao: CGLineJoin = prop("stroke-linejoin") == "round" ? .round : prop("stroke-linejoin") == "bevel" ? .bevel : .miter
        let largura = tracado ? CGFloat(Double(prop("stroke-width") ?? "1") ?? 1) : 0
        formas.append(FormaSvg(caminho: caminho, preenche: preenche && !(raiz["fill"] == "none" && a["fill"] == nil),
                               largura: largura, ponta: ponta, juncao: juncao))
    }
}

/// Lê o atributo `d` de um path: M L H V C S Q A Z, maiúsculas e minúsculas.
enum CaminhoSvg {
    static func ler(_ d: String) -> Path {
        var t = Tokens(d)
        var p = Path()
        var atual = CGPoint.zero, inicio = CGPoint.zero
        var ultimoControle: CGPoint?
        var cmd: Character = "M"
        while let c = t.proximoComando(padrao: cmd) {
            cmd = c
            let rel = c.isLowercase
            func ponto(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: atual.x + x, y: atual.y + y) : CGPoint(x: x, y: y) }
            switch Character(c.uppercased()) {
            case "M":
                guard let x = t.numero(), let y = t.numero() else { return p }
                atual = ponto(x, y); inicio = atual; p.move(to: atual); ultimoControle = nil
                cmd = rel ? "l" : "L"
            case "L":
                guard let x = t.numero(), let y = t.numero() else { return p }
                atual = ponto(x, y); p.addLine(to: atual); ultimoControle = nil
            case "H":
                guard let x = t.numero() else { return p }
                atual = CGPoint(x: rel ? atual.x + x : x, y: atual.y); p.addLine(to: atual); ultimoControle = nil
            case "V":
                guard let y = t.numero() else { return p }
                atual = CGPoint(x: atual.x, y: rel ? atual.y + y : y); p.addLine(to: atual); ultimoControle = nil
            case "C":
                guard let a = t.numero(), let b = t.numero(), let c2 = t.numero(), let d2 = t.numero(), let e = t.numero(), let f = t.numero() else { return p }
                let c1 = ponto(a, b), cc = ponto(c2, d2), fim = ponto(e, f)
                p.addCurve(to: fim, control1: c1, control2: cc); atual = fim; ultimoControle = cc
            case "S":
                guard let c2 = t.numero(), let d2 = t.numero(), let e = t.numero(), let f = t.numero() else { return p }
                let c1 = ultimoControle.map { CGPoint(x: 2 * atual.x - $0.x, y: 2 * atual.y - $0.y) } ?? atual
                let cc = ponto(c2, d2), fim = ponto(e, f)
                p.addCurve(to: fim, control1: c1, control2: cc); atual = fim; ultimoControle = cc
            case "Q":
                guard let a = t.numero(), let b = t.numero(), let e = t.numero(), let f = t.numero() else { return p }
                let cc = ponto(a, b), fim = ponto(e, f)
                p.addQuadCurve(to: fim, control: cc); atual = fim; ultimoControle = cc
            case "A":
                guard let rx = t.numero(), let ry = t.numero(), let rot = t.numero(), let g = t.flag(), let s = t.flag(),
                      let x = t.numero(), let y = t.numero() else { return p }
                let fim = ponto(x, y)
                arco(&p, de: atual, para: fim, rx: abs(rx), ry: abs(ry), rotacao: rot, grande: g, varre: s)
                atual = fim; ultimoControle = nil
            case "Z":
                p.closeSubpath(); atual = inicio; ultimoControle = nil
            default: return p
            }
        }
        return p
    }

    /// Arco do SVG (centro a partir dos pontos, como na especificação) convertido em curvas de Bézier.
    private static func arco(_ p: inout Path, de a: CGPoint, para b: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotacao: CGFloat, grande: Bool, varre: Bool) {
        if a == b { return }
        var rx = rx0, ry = ry0
        if rx == 0 || ry == 0 { p.addLine(to: b); return }
        let fi = rotacao * .pi / 180, cf = cos(fi), sf = sin(fi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x1 = cf * dx + sf * dy, y1 = -sf * dx + cf * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num) / den).squareRoot()
        if grande == varre { coef = -coef }
        let cxl = coef * rx * y1 / ry, cyl = -coef * ry * x1 / rx
        let cx = cf * cxl - sf * cyl + (a.x + b.x) / 2, cy = sf * cxl + cf * cyl + (a.y + b.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let s = ux * vy - uy * vx, c = ux * vx + uy * vy
            return atan2(s, c)
        }
        let t1 = ang(1, 0, (x1 - cxl) / rx, (y1 - cyl) / ry)
        var dt = ang((x1 - cxl) / rx, (y1 - cyl) / ry, (-x1 - cxl) / rx, (-y1 - cyl) / ry)
        if !varre && dt > 0 { dt -= 2 * .pi }
        if varre && dt < 0 { dt += 2 * .pi }
        let partes = max(1, Int((abs(dt) / (.pi / 2)).rounded(.up)))
        let passo = dt / CGFloat(partes)
        let alfa = 4 / 3 * tan(passo / 4)
        var t = t1
        for _ in 0..<partes {
            let c1 = cos(t), s1 = sin(t), c2 = cos(t + passo), s2 = sin(t + passo)
            func mapa(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cf * rx * x - sf * ry * y + cx, y: sf * rx * x + cf * ry * y + cy)
            }
            p.addCurve(to: mapa(c2, s2),
                       control1: mapa(c1 - alfa * s1, s1 + alfa * c1),
                       control2: mapa(c2 + alfa * s2, s2 - alfa * c2))
            t += passo
        }
    }

    private struct Tokens {
        private let s: [Character]
        private var i = 0
        init(_ d: String) { s = Array(d) }

        private mutating func pular() { while i < s.count, s[i] == " " || s[i] == "," || s[i] == "\n" || s[i] == "\t" { i += 1 } }

        mutating func proximoComando(padrao: Character) -> Character? {
            pular()
            guard i < s.count else { return nil }
            if s[i].isLetter { defer { i += 1 }; return s[i] }
            // Número sem letra: repete o comando anterior (já ajustado por quem chama).
            return padrao
        }

        mutating func numero() -> CGFloat? {
            pular()
            guard i < s.count else { return nil }
            var t = ""
            if s[i] == "-" || s[i] == "+" { t.append(s[i]); i += 1 }
            var ponto = false
            while i < s.count {
                let c = s[i]
                if c.isNumber { t.append(c); i += 1 }
                else if c == ".", !ponto { ponto = true; t.append(c); i += 1 }
                else { break }
            }
            return Double(t).map { CGFloat($0) }
        }

        /// Os flags do arco são um dígito só e podem vir colados ("a2 2 0 011 1").
        mutating func flag() -> Bool? {
            pular()
            guard i < s.count, s[i] == "0" || s[i] == "1" else { return nil }
            defer { i += 1 }
            return s[i] == "1"
        }
    }
}
