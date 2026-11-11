import SwiftUI
import AppKit

/// Mede texto como o navegador do protótipo o quebra em linhas. O CSS usa `text-wrap: balance`
/// (as linhas saem do mesmo tamanho) e larguras em `ch`. O SwiftUI não tem nenhum dos dois, então
/// a conta fica aqui: a largura é a menor que mantém o número de linhas.
enum MedirTexto {
    static func fonte(_ tamanho: CGFloat, _ peso: NSFont.Weight) -> NSFont { .systemFont(ofSize: tamanho, weight: peso) }

    /// A unidade `ch` do CSS na fonte do texto.
    static func ch(_ n: CGFloat, tamanho: CGFloat) -> CGFloat {
        // O navegador do protótipo mede o zero do SF em 0,6286 do tamanho (46ch a 13 px dão 375,9 px).
        n * Tema.Inicial.zeroCh * tamanho
    }

    static func alturaNatural(_ fonte: NSFont) -> CGFloat { NSLayoutManager().defaultLineHeight(for: fonte) }

    private static func disposicao(_ texto: String, _ fonte: NSFont, _ kern: CGFloat, largura: CGFloat) -> (linhas: Int, usada: CGFloat) {
        let armazem = NSTextStorage(string: texto, attributes: [.font: fonte, .kern: kern])
        let gerente = NSLayoutManager()
        let recipiente = NSTextContainer(size: CGSize(width: largura, height: .greatestFiniteMagnitude))
        recipiente.lineFragmentPadding = 0
        gerente.addTextContainer(recipiente)
        armazem.addLayoutManager(gerente)
        gerente.ensureLayout(for: recipiente)
        var n = 0
        var maior: CGFloat = 0
        gerente.enumerateLineFragments(forGlyphRange: gerente.glyphRange(for: recipiente)) { _, usada, _, _, _ in
            n += 1
            maior = max(maior, usada.width)
        }
        return (n, maior)
    }

    /// Menor largura (até `maxima`) que mantém as mesmas linhas que `maxima` daria. 0 sem texto.
    static func balanceada(_ texto: String, tamanho: CGFloat, peso: NSFont.Weight, kern: CGFloat, maxima: CGFloat) -> CGFloat {
        guard !texto.isEmpty else { return 0 }
        // O Chrome mede o texto cerca de 0,7% mais estreito que o AppKit: sem a folga, uma linha que
        // cabe no navegador por meio pixel quebra no app.
        let maxima = maxima + Tema.Inicial.folgaDeMedida
        let f = fonte(tamanho, peso)
        let alvo = disposicao(texto, f, kern, largura: maxima)
        if alvo.linhas <= 1 { return ceil(alvo.usada) + 1 }
        var baixo: CGFloat = 1, alto = maxima
        while alto - baixo > 1 {
            let meio = (baixo + alto) / 2
            if disposicao(texto, f, kern, largura: meio).linhas <= alvo.linhas { alto = meio } else { baixo = meio }
        }
        return min(maxima, alto + 2)
    }
}

/// Parágrafo ou título centralizado, com altura de linha e quebra balanceada do protótipo.
struct TextoBalanceado: View {
    var texto: String
    var tamanho: CGFloat
    var peso: Font.Weight = .regular
    var cor: Color = Tema.Cor.texto
    var altura: CGFloat = Tema.Texto.altura
    var tracking: CGFloat = 0
    var larguraMax: CGFloat = Tema.Inicial.corpoLarg

    private static func nsPeso(_ p: Font.Weight) -> NSFont.Weight {
        switch p {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        default: return .regular
        }
    }

    var body: some View {
        let natural = MedirTexto.alturaNatural(MedirTexto.fonte(tamanho, Self.nsPeso(peso)))
        let desejada = tamanho * altura
        let extra = desejada - natural
        let w = MedirTexto.balanceada(texto, tamanho: tamanho, peso: Self.nsPeso(peso), kern: tracking, maxima: larguraMax)
        Text(texto)
            .font(.system(size: tamanho, weight: peso))
            .tracking(tracking)
            .foregroundColor(cor)
            .multilineTextAlignment(.center)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
            .frame(width: w)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Imagens soltas da configuração (Inicial/Imagens), lidas direto do pacote do app.
enum ImagemDaInicial {
    static func ler(_ nome: String) -> Image {
        for ext in ["png", "jpg"] {
            if let url = Bundle.main.url(forResource: nome, withExtension: ext), let img = NSImage(contentsOf: url) {
                return Image(nsImage: img)
            }
        }
        return Image(systemName: "questionmark")
    }
}
