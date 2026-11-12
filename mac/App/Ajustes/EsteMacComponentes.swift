import SwiftUI

// Peças que as seções Conectar iPhone, Acessos do Mac, Este Mac e Sobre dividem: grupo com título,
// cartão de linhas, linha, botão, campo e chave. Igual ao `grupo`, `linha`, `.btn`, `.entrada` e
// `.chave` de prototipo/mac.js e mac.css. Todos os valores vêm de Tema.

/// Título pequeno, o conteúdo e uma nota embaixo (`grupo` do protótipo).
struct GrupoDeAjuste<Conteudo: View>: View {
    var titulo: String?
    var nota: String?
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            if let titulo { TituloDeGrupo(titulo) }
            conteudo
            if let nota { NotaDeAjuste(nota) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// O `h3` do grupo: o tatile põe nos títulos altura de linha 1.2 e tracking de -0.02em, não o 1.5 do texto.
struct TituloDeGrupo: View {
    var texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .font(.system(size: Tema.Texto.sm, weight: .semibold))
            .tracking(Tema.Texto.trackingTitulo(Tema.Texto.sm))
            .foregroundColor(Tema.Cor.texto2)
            .lineLimit(1)
            .frame(height: Tema.Texto.sm * Tema.Texto.alturaTitulo, alignment: .leading)
    }
}

/// `.nota` do protótipo: tamanho pequeno, cor secundária, quebra de linha se precisar.
struct NotaDeAjuste: View {
    var texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .font(.system(size: Tema.Texto.xs))
            .foregroundColor(Tema.Cor.texto2)
            .lineSpacing(Tema.Texto.xs * (Tema.Texto.altura - 1.2))
            .frame(minHeight: Tema.Texto.xs * Tema.Texto.altura, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// O cartão que junta linhas (`.linhas`).
struct LinhasDeAjuste<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(spacing: 0) { conteudo }
            .padding(.horizontal, Tema.Espaco.pad)
            .frame(maxWidth: .infinity)
            .superficie()
    }
}

/// Uma linha do cartão (`linha` do protótipo): título, texto de apoio embaixo e o controle à direita.
/// Da segunda linha em diante, `divisoria` desenha o fio de cima.
struct LinhaDeAjuste<Lado: View>: View {
    var titulo: String
    var apoio: String?
    var divisoria = false
    @ViewBuilder var lado: Lado

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                Text(titulo).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto)
                if let apoio, !apoio.isEmpty {
                    Text(apoio).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2, linhas: nil)
                        .frame(minHeight: Tema.Texto.xs * Tema.Texto.altura)
                        .lineSpacing(Tema.Texto.xs * (Tema.Texto.altura - 1.2))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            lado
        }
        .padding(.vertical, Tema.Espaco.icone)
        // O fio de cima ocupa 1 px dentro da altura mínima, como o `border-top` do protótipo.
        .padding(.top, divisoria ? Tema.Espaco.fio : 0)
        .frame(minHeight: Tema.Espaco.linha)
        .overlay(alignment: .top) {
            if divisoria { Rectangle().fill(Tema.Cor.borda).frame(height: 1) }
        }
    }
}

extension LinhaDeAjuste where Lado == EmptyView {
    init(titulo: String, apoio: String? = nil, divisoria: Bool = false) {
        self.init(titulo: titulo, apoio: apoio, divisoria: divisoria) { EmptyView() }
    }
}

/// Valor em cinza no fim da linha (`.valor`).
struct ValorDeAjuste: View {
    var texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2).monospacedDigit()
    }
}

// MARK: - Botão

enum EstiloDeBotao { case primario, secundario, link, perigo, estrela }

private struct AperteDoBotao: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tema.Estado.escalaAperto : 1)
            .animation(Tema.Mov.move, value: configuration.isPressed)
    }
}

/// `.btn` do protótipo.
struct BotaoDeAjuste: View {
    var texto: String
    var estilo: EstiloDeBotao = .secundario
    var desligado = false
    /// Ícone SF Symbol antes do texto (só o botão da estrela usa).
    var icone: String? = nil
    /// O botão herda a fonte do campo onde está (o endereço, em monoespaçada).
    var monoespaco = false
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.item) {
                if let icone { Image(systemName: icone).font(.system(size: Tema.Medida.iconeBotao, weight: .semibold)) }
                Text(texto).font(.system(size: Tema.Texto.sm, weight: .semibold, design: monoespaco ? .monospaced : .default))
            }
                .foregroundColor(cor).lineLimit(1).frame(height: Tema.Texto.sm * Tema.Texto.altura)
                .padding(.horizontal, estilo == .perigo ? Tema.Espaco.item : Tema.Espaco.icone)
                .frame(minHeight: Tema.Espaco.alvoSm)
                .background(fundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(AperteDoBotao())
        .disabled(desligado)
        .opacity(desligado ? Tema.Estado.opacidadeDesligado : 1)
        .fixedSize()
    }

    private var cor: Color {
        switch estilo {
        case .primario: return Tema.Cor.destaqueTexto
        case .estrela: return Tema.Cor.estrelaTexto
        case .secundario: return Tema.Cor.texto
        case .link: return Tema.Cor.texto2
        case .perigo: return Tema.Cor.perigo
        }
    }

    private var fundo: Color {
        switch estilo {
        case .primario: return Tema.Cor.destaque
        case .estrela: return Tema.Cor.estrela
        case .secundario: return Tema.Cor.superficie2
        case .link, .perigo: return .clear
        }
    }
}

// MARK: - Campo e chave

/// `.entrada` do protótipo: campo de uma linha com fundo da tela e fio fino.
struct CampoDeAjuste: View {
    var rotulo: String
    @Binding var texto: String
    var largura: CGFloat?
    @Environment(\.fotografando) private var fotografando

    var body: some View {
        Group {
            if fotografando {
                // O ImageRenderer não desenha campo de texto nativo: nas fotos entra o texto no lugar.
                Text(texto).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $texto).textFieldStyle(.plain)
            }
        }
            .font(.system(size: Tema.Texto.sm))
            .foregroundColor(Tema.Cor.texto)
            .padding(.horizontal, Tema.Espaco.icone)
            .frame(width: largura, height: Tema.Espaco.alvoSm)
            .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
            .contornoInterno(Tema.Cor.borda, largura: 1, raio: Tema.Raio.sm)
            .accessibilityLabel(rotulo)
    }
}

/// `.chave`: verde quando ligada, como a tecla acesa.
struct ChaveDeAjuste: View {
    var rotulo: String
    var ligada: Bool
    var mudar: (Bool) -> Void

    var body: some View {
        Button { mudar(!ligada) } label: {
            ZStack(alignment: ligada ? .trailing : .leading) {
                Capsule().fill(ligada ? Tema.Cor.led : Tema.Cor.superficie2)
                Circle().fill(Tema.Cor.branco)
                    .frame(width: Tema.Medida.chaveAlt - 2 * Tema.Espaco.fino, height: Tema.Medida.chaveAlt - 2 * Tema.Espaco.fino)
                    .padding(Tema.Espaco.fino)
            }
            .frame(width: Tema.Medida.chaveLarg, height: Tema.Medida.chaveAlt)
            .animation(Tema.Mov.move, value: ligada)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
        .accessibilityValue(ligada ? "ligado" : "desligado")
        .accessibilityAddTraits(.isButton)
    }
}
