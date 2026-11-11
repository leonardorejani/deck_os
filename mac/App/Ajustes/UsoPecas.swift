import SwiftUI
import AppKit

// Peças de formulário da seção Uso das IAs e da janela Adicionar conta: botão, interruptor, campo.
// Iguais a .btn, .chave, .entrada e .nome-conta de prototipo/mac.css.

private struct EmFotoChave: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Só nas fotos: o ImageRenderer não desenha campo de texto do AppKit, então o campo vira texto.
    var emFoto: Bool {
        get { self[EmFotoChave.self] }
        set { self[EmFotoChave.self] = newValue }
    }
}

extension Text {
    /// Parágrafo de várias linhas com a altura de linha pedida (o `line-height` do CSS).
    func paragrafo(_ tamanho: CGFloat, _ peso: Font.Weight = .regular, _ cor: Color = Tema.Cor.texto,
                   altura: CGFloat = Tema.Texto.altura) -> some View {
        font(.system(size: tamanho, weight: peso))
            .foregroundColor(cor)
            .lineSpacing(max(0, (altura - Tema.Uso.alturaNatural) * tamanho))
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum TipoBotao { case primario, secundario, perigo, link }

struct EstiloBotao: ButtonStyle {
    var tipo: TipoBotao

    func makeBody(configuration: Configuration) -> some View {
        let cor: Color = {
            switch tipo {
            case .primario: return Tema.Cor.destaqueTexto
            case .secundario: return Tema.Cor.texto
            case .perigo: return Tema.Cor.perigo
            case .link: return Tema.Cor.texto2
            }
        }()
        let fundo: Color = tipo == .primario ? Tema.Cor.destaque : tipo == .secundario ? Tema.Cor.superficie2 : .clear
        return configuration.label
            .font(.system(size: Tema.Texto.sm, weight: .semibold))
            .foregroundColor(cor)
            .lineLimit(1)
            .padding(.horizontal, tipo == .perigo ? Tema.Espaco.item : Tema.Espaco.icone)
            .frame(minHeight: Tema.Espaco.alvoSm)
            .background(fundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .scaleEffect(configuration.isPressed ? Tema.Uso.botaoApertado : 1)
            .animation(Tema.Mov.move, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct BotaoUso: View {
    var texto: String
    var tipo: TipoBotao = .secundario
    var desligado = false
    var acao: () -> Void

    var body: some View {
        Button(action: acao) { Text(texto) }
            .buttonStyle(EstiloBotao(tipo: tipo))
            .disabled(desligado)
            .opacity(desligado ? Tema.Uso.opacidadeDesligado : 1)
    }
}

/// O interruptor: verde ligado, como a tecla acesa.
struct ChaveUso: View {
    var ligada: Bool
    var rotulo: String
    var mudar: (Bool) -> Void

    var body: some View {
        let botao = Tema.Uso.chaveAlt - 2 * Tema.Espaco.fino
        Button { mudar(!ligada) } label: {
            ZStack(alignment: ligada ? .trailing : .leading) {
                Capsule().fill(ligada ? Tema.Cor.led : Tema.Cor.superficie2)
                Circle().fill(Tema.Cor.branco).frame(width: botao, height: botao)
                    .overlay { Circle().strokeBorder(Tema.Cor.anel, lineWidth: Tema.Uso.filete) }
                    .padding(Tema.Espaco.fino)
            }
            .frame(width: Tema.Uso.chaveLarg, height: Tema.Uso.chaveAlt)
            .animation(Tema.Mov.move, value: ligada)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotulo)
        .accessibilityValue(ligada ? "ligado" : "desligado")
    }
}

/// Campo de texto de uma linha (.entrada): 32 de altura, borda fina, foco com contorno azul.
struct EntradaUso: View {
    var placeholder: String
    @Binding var texto: String
    var segredo = false
    var mono = false
    var invalido = false
    var rotulo: String
    var focoForcado = false
    var foco: FocusState<Bool>.Binding?
    var enviar: () -> Void = {}

    @FocusState private var focoProprio: Bool
    @Environment(\.emFoto) private var emFoto

    var body: some View {
        let fonte = Font.system(size: mono ? Tema.Uso.mono : Tema.Texto.sm, design: mono ? .monospaced : .default)
        let prompt = Text(placeholder).foregroundColor(Tema.Cor.texto3)
        Group {
            if emFoto {
                (texto.isEmpty ? prompt : Text(segredo ? String(repeating: "\u{2022}", count: texto.count) : texto).foregroundColor(Tema.Cor.texto))
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            } else if segredo { SecureField("", text: $texto, prompt: prompt) } else { TextField("", text: $texto, prompt: prompt) }
        }
        .textFieldStyle(.plain)
        .font(fonte)
        .foregroundColor(Tema.Cor.texto)
        .autocorrectionDisabled()
        .accessibilityLabel(rotulo)
        .onSubmit(enviar)
        .modifier(FocoOpcional(foco: foco, proprio: $focoProprio))
        .padding(.horizontal, Tema.Espaco.icone)
        .frame(minHeight: Tema.Espaco.alvoSm)
        .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
        .contornoInterno(invalido ? Tema.Cor.perigo : Tema.Cor.borda, largura: 1, raio: Tema.Raio.sm)
        .overlay {
            if focoForcado || (foco?.wrappedValue ?? focoProprio) {
                RoundedRectangle(cornerRadius: Tema.Raio.sm + Tema.Uso.focoRecuo + Tema.Uso.focoLargura, style: .continuous)
                    .strokeBorder(Tema.Cor.destaque, lineWidth: Tema.Uso.focoLargura)
                    .padding(-(Tema.Uso.focoRecuo + Tema.Uso.focoLargura))
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct FocoOpcional: ViewModifier {
    var foco: FocusState<Bool>.Binding?
    var proprio: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if let foco { content.focused(foco) } else { content.focused(proprio) }
    }
}

/// O nome da conta no cartão (.nome-conta): sem borda em repouso, com borda ao passar o mouse ou editar.
struct CampoNomeConta: View {
    var nome: String
    var salvar: (String) -> Void
    @State private var texto: String
    @State private var sobre = false
    @FocusState private var focado: Bool
    @State private var espera: Task<Void, Never>?
    @Environment(\.emFoto) private var emFoto

    init(nome: String, salvar: @escaping (String) -> Void) {
        self.nome = nome
        self.salvar = salvar
        _texto = State(initialValue: nome)
    }

    var body: some View {
        Group {
            if emFoto { Text(texto).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1) } else { TextField("", text: $texto) }
        }
            .textFieldStyle(.plain)
            .font(.system(size: Tema.Texto.sm, weight: .semibold))
            .foregroundColor(Tema.Cor.texto)
            .focused($focado)
            .accessibilityLabel("Nome no iPhone")
            .padding(.horizontal, Tema.Espaco.micro + Tema.Uso.focoSimples)
            .frame(minHeight: Tema.Espaco.alvoSm)
            .background((sobre || focado) ? Tema.Cor.telaFundo : .clear, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
            .contornoInterno((sobre || focado) ? Tema.Cor.borda : .clear, largura: 1, raio: Tema.Raio.sm)
            .onHover { sobre = $0 }
            .onChange(of: texto) { novo in
                // Grava depois de uma pausa na digitação (400 ms, como o protótipo). Vazio não vale: fica o nome antigo.
                espera?.cancel()
                espera = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    let limpo = novo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !limpo.isEmpty, limpo != nome { salvar(limpo) }
                }
            }
            .onChange(of: nome) { novo in if !focado { texto = novo } }
            .onChange(of: focado) { f in
                if !f, texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texto = nome }
            }
    }
}

/// O círculo girando do "Esperando o login...".
struct Girando: View {
    @State private var angulo = 0.0

    var body: some View {
        ZStack {
            Circle().strokeBorder(Tema.Cor.borda, lineWidth: Tema.Uso.focoLargura)
            Circle().trim(from: 0, to: Tema.Uso.girarArco).stroke(Tema.Cor.texto, lineWidth: Tema.Uso.focoLargura).rotationEffect(.degrees(Tema.Uso.girarInicio))
                .padding(Tema.Uso.focoLargura / 2)
        }
        .frame(width: Tema.Uso.girando, height: Tema.Uso.girando)
        .rotationEffect(.degrees(angulo))
        .onAppear { withAnimation(.linear(duration: Tema.Uso.girarDuracao).repeatForever(autoreverses: false)) { angulo = Tema.Uso.girarVolta } }
        .accessibilityHidden(true)
    }
}
