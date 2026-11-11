import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A lógica da seção Conectar iPhone que não depende da tela: endereço, código em grupos e o QR.
enum ParearIphone {
    /// "MacBook Pro de Exemplo" vira "macbook-pro-de-exemplo" (igual a parearHTML em prototipo/mac.js).
    static func nomeNaRede(_ nomeMac: String) -> String {
        let semAcento = nomeMac.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        let limpo = semAcento.unicodeScalars.filter { ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0 == " " }
        let aparado = String(String.UnicodeScalarView(limpo)).trimmingCharacters(in: .whitespaces)
        let juntado = aparado.split(separator: " ", omittingEmptySubsequences: true).joined(separator: "-")
        return juntado.isEmpty ? "mac" : juntado
    }

    /// Endereço que o iPhone abre no Safari. `nomeDoServidor` é o nome que o macOS usa na rede
    /// (o mesmo do certificado). Sem ele, vale o derivado do nome do Mac.
    static func endereco(nomeMac: String, porta: Int, nomeDoServidor: String? = nil) -> String {
        let host: String
        if let n = nomeDoServidor?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            host = n.lowercased().hasSuffix(".local") ? n : n + ".local"
        } else {
            host = nomeNaRede(nomeMac) + ".local"
        }
        return "https://\(host):\(porta)"
    }

    /// O que o QR leva: o endereço do Mac com o código de pareamento e o link do certificado no fragmento
    /// (o navegador não manda o fragmento ao servidor). O certificado é baixado de GET /ca.crt.
    static func textoDoQr(endereco: String, codigo: String) -> String {
        let base = endereco.hasSuffix("/") ? String(endereco.dropLast()) : endereco
        let parear = codigo.isEmpty ? "" : "parear=\(codigo)&"
        return "\(base)/#\(parear)certificado=\(base)/ca.crt"
    }

    /// "482913" vira "482 913": o código de 6 dígitos é lido de longe, em dois grupos.
    static func codigoEmGrupos(_ codigo: String) -> String {
        guard codigo.count == 6 else { return codigo }
        return codigo.prefix(3) + " " + codigo.suffix(3)
    }

    /// O QR do texto (CIQRCodeGenerator), em módulos nítidos. `modulo` é o lado de cada módulo em pixels.
    /// O CoreImage deixa 1 módulo em branco em volta: sai daqui, porque o quadro branco da tela já é a
    /// margem (como no protótipo, onde os módulos vão até a borda do desenho).
    static func qr(_ texto: String, modulo: CGFloat = 8) -> CGImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let saida = filtro.outputImage else { return nil }
        let grande = saida.transformed(by: CGAffineTransform(scaleX: modulo, y: modulo))
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(grande, from: grande.extent.insetBy(dx: modulo, dy: modulo))
    }
}

/// O código curto que o iPhone digita, enquanto a tela o mostra. Olha o Pareamento do núcleo a cada
/// segundo: venceu, foi usado ou estourou os erros, entra um novo na hora. Ao parar (a tela fechou)
/// o código é apagado no núcleo: sem tela, não fica código ativo.
@MainActor
final class CodigoDePareamento: ObservableObject {
    @Published private(set) var codigo = ""
    private var tarefa: Task<Void, Never>?
    private var pareamento: Pareamento?

    /// `fixo` só nas fotos e nos testes: um código conhecido, sem tocar no Pareamento.
    func iniciar(_ pareamento: Pareamento, fixo: String? = nil, intervalo: TimeInterval = 1) {
        tarefa?.cancel()
        self.pareamento = nil
        if let fixo { codigo = fixo; return }
        self.pareamento = pareamento
        codigo = pareamento.codigoAtivo ?? pareamento.gerar()
        tarefa = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalo * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.codigo = pareamento.codigoAtivo ?? pareamento.gerar()
            }
        }
    }

    func parar() {
        tarefa?.cancel(); tarefa = nil
        if let pareamento { pareamento.encerrar(); codigo = "" }
        pareamento = nil
    }
}

private struct ChaveCodigoFixo: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Só nas fotos: o código de exemplo que aparece no lugar do sorteado.
    var codigoDePareamentoFixo: String? {
        get { self[ChaveCodigoFixo.self] }
        set { self[ChaveCodigoFixo.self] = newValue }
    }
}

extension ModeloApp {
    /// Desconectar o iPhone: o código de acesso muda, então o aparelho antigo para de ler e de executar
    /// e volta a pedir pareamento. É assim que o Mac "esquece" um iPhone (a API só conhece o código).
    func desconectarIphone() {
        guard revogarCodigos() else { return }
        avisar("iPhone desconectado. Ele volta a pedir pareamento")
    }

    /// O botão "Desconectar iPhones": o mesmo efeito, dito no plural porque vale para todos de uma vez.
    func desconectarIphones() {
        guard revogarCodigos() else { return }
        avisar("iPhones desconectados. Todos voltam a pedir pareamento")
    }
}
