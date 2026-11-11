import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// As contas de IA que este Mac já tem: os perfis medidos do Claude Code e o login do Codex.
enum ContasDeste {
    static func achar(casa: URL = FileManager.default.homeDirectoryForCurrentUser, agora: Date = Date()) -> [ContaAchada] {
        var saida: [ContaAchada] = []
        let medicao = casa.appendingPathComponent(".config/claude-account/measure.json")
        if let dados = try? Data(contentsOf: medicao), let m = UsoClaude.parse(dados) {
            for nome in m.perfis.keys.sorted() {
                let p = m.perfis[nome]
                saida.append(ContaAchada(id: "claude-\(nome)", servico: "Claude", conta: nome, perfil: nome,
                                         semana: p?.semana, renova: p?.renova.flatMap { $0 > agora ? $0 : nil }))
            }
        }
        let codex = casa.appendingPathComponent(".codex")
        if FileManager.default.fileExists(atPath: codex.appendingPathComponent("auth.json").path) {
            let r = UsoCodex.ler(raiz: codex, conta: ContaIA(id: "codex", nome: "Codex", conta: "principal", perfil: nil, mostrar: nil), agora: agora)
            saida.append(ContaAchada(id: "codex", servico: "Codex", conta: "principal", semana: r.valor.semana,
                                     renova: r.valor.renova.flatMap(Datas.ler)))
        }
        return saida
    }
}

/// O endereço que o iPhone abre: o nome .local do Mac e a porta (o mesmo do certificado).
enum EnderecoDoMac {
    /// O nome do protótipo: "MacBook Pro" vira "macbook-pro.local" (usado quando o sistema não responde).
    static func apelido(_ nomeMac: String) -> String {
        let limpo = nomeMac.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " ") }
            .trimmingCharacters(in: .whitespaces)
        let trocado = limpo.split(separator: " ").joined(separator: "-")
        return trocado + ".local"
    }

    static func url(nomeMac: String, porta: Int, hostLocal: String? = nil) -> String {
        "https://\(hostLocal ?? apelido(nomeMac)):\(porta)"
    }

    /// `scutil --get LocalHostName` + ".local", o nome que o certificado leva no SAN.
    static func hostLocal(executor: any Executor = ExecutorShell()) -> String? {
        let r = executor.rodar("scutil --get LocalHostName")
        let nome = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !nome.isEmpty ? nome + ".local" : nil
    }

    /// Código curto de 6 dígitos em dois grupos: "123 456".
    static func codigoEmGrupos(_ c: String) -> String {
        guard c.count == 6 else { return c }
        return "\(c.prefix(3)) \(c.suffix(3))"
    }
}

/// QR de verdade do endereço, em quadrados nítidos.
enum DesenhoDoQr {
    static func imagem(_ texto: String) -> NSImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let saida = filtro.outputImage else { return nil }
        let escala: CGFloat = 8
        let grande = saida.transformed(by: CGAffineTransform(scaleX: escala, y: escala))
        let contexto = CIContext()
        guard let cg = contexto.createCGImage(grande, from: grande.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: grande.extent.width, height: grande.extent.height))
    }
}
