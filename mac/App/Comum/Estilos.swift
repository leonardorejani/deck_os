import SwiftUI

// Peças de aparência que todas as telas repetem: cartão com anel, texto com a altura de linha do
// protótipo e o ponto de estado. Valores sempre de Tema.

extension View {
    /// Fundo com o anel fino de 1 px por fora (a sombra-1 da tatile). O anel não ocupa espaço.
    func superficie(_ cor: Color = Tema.Cor.superficie, raio: CGFloat = Tema.Raio.card, anel: Bool = true) -> some View {
        background {
            ZStack {
                if anel {
                    RoundedRectangle(cornerRadius: raio + 1, style: .continuous).fill(Tema.Cor.anel).padding(-1)
                }
                RoundedRectangle(cornerRadius: raio, style: .continuous).fill(cor)
            }
        }
    }

    /// Contorno por dentro (box-shadow inset do CSS).
    func contornoInterno(_ cor: Color, largura: CGFloat, raio: CGFloat) -> some View {
        overlay { RoundedRectangle(cornerRadius: raio, style: .continuous).strokeBorder(cor, lineWidth: largura) }
    }
}

extension Text {
    /// Texto no tamanho do token, com a altura de linha de 1.5 do protótipo (a caixa de uma linha só).
    func tatile(_ tamanho: CGFloat, _ peso: Font.Weight = .regular, _ cor: Color = Tema.Cor.texto, linhas: Int? = 1) -> some View {
        font(.system(size: tamanho, weight: peso))
            .foregroundColor(cor)
            .lineLimit(linhas)
            .frame(height: linhas == 1 ? tamanho * Tema.Texto.altura : nil)
    }
}

/// Ponto de estado: verde com brilho quando ligado, cinza quando não.
struct Ponto: View {
    var ligado: Bool
    var lado: CGFloat = Tema.Medida.ponto

    var body: some View {
        Circle()
            .fill(ligado ? Tema.Cor.led : Tema.Cor.texto3)
            .frame(width: lado, height: lado)
            .shadow(color: ligado ? Tema.Cor.led : .clear, radius: 3)
    }
}

/// O ícone do app (A-3) nos lugares grandes.
struct Logo: View {
    var lado: CGFloat = Tema.Medida.logo

    var body: some View {
        Image("Logo").resizable().interpolation(.high).frame(width: lado, height: lado).accessibilityHidden(true)
    }
}
