import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Peças da tela "Suas teclas": botões, campo, tecla (a mesma do iPhone), quebra de linha e aviso.
// Valores sempre de Tema. Espelha prototipo/mac.css (.btn, .entrada, .tecla-m, .chip, .aviso).

struct EstiloDoBotao: ButtonStyle {
    enum Tipo { case primario, secundario, perigo, link }
    var tipo: Tipo = .secundario
    var desligado = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Tema.Texto.sm, weight: .semibold))
            .foregroundColor(cor)
            .padding(.horizontal, tipo == .perigo ? Tema.Espaco.item : Tema.Espaco.icone)
            .frame(minHeight: Tema.Espaco.alvoSm)
            .background { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).fill(fundo) }
            .opacity(desligado ? Tema.Opacidade.desligado : 1)
            .scaleEffect(configuration.isPressed && !desligado ? Tema.Escala.apertado : 1)
            .animation(Tema.Mov.move, value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var cor: Color {
        switch tipo {
        case .primario: return Tema.Cor.destaqueTexto
        case .secundario: return Tema.Cor.texto
        case .perigo: return Tema.Cor.perigo
        case .link: return Tema.Cor.texto2
        }
    }

    private var fundo: Color {
        switch tipo {
        case .primario: return Tema.Cor.destaque
        case .secundario: return Tema.Cor.superficie2
        case .perigo, .link: return .clear
        }
    }
}

extension View {
    /// A caixa de texto do protótipo (.entrada): fundo da tela, borda de 1 px, raio pequeno.
    func entrada(raio: CGFloat = Tema.Raio.sm, altura: CGFloat = Tema.Espaco.alvoSm) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, Tema.Espaco.icone)
            .padding(.leading, Tema.Medida.bordaDoCampo)
            .frame(minHeight: altura)
            .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: raio, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: raio, style: .continuous).strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.fino) }
    }
}

/// Itens em linha que quebram para a de baixo quando não cabem (o flex-wrap do CSS).
struct Quebra: Layout {
    var espaco: CGFloat
    var linhaEspaco: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        posicionar(largura: proposal.width ?? .infinity, subviews: subviews).tamanho
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = posicionar(largura: bounds.width, subviews: subviews)
        for (i, p) in r.pontos.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }

    private func posicionar(largura: CGFloat, subviews: Subviews) -> (pontos: [CGPoint], tamanho: CGSize) {
        var pontos: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, altura: CGFloat = 0, maior: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > largura { x = 0; y += altura + (linhaEspaco ?? espaco); altura = 0 }
            pontos.append(CGPoint(x: x, y: y))
            x += t.width + espaco
            altura = max(altura, t.height)
            maior = max(maior, x - espaco)
        }
        return (pontos, CGSize(width: maior, height: y + altura))
    }
}

// MARK: - Ícones

enum IconesDeTecla {
    static let busca = #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>"#
    static let teclado = #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/></svg>"#

    static func doTipo(_ t: TipoDeTecla) -> String {
        switch t {
        case .app: return Icone.teclas
        case .tecla: return teclado
        case .comando: return Icone.terminal
        case .atalho: return Icone.raio
        }
    }

    /// "svg:tela" do config.json vira o desenho do painel.
    static func svg(_ nome: String) -> String? {
        switch nome {
        case "tela": return Icone.tela
        case "terminal": return Icone.terminal
        case "raio": return Icone.raio
        case "microfone": return Icone.microfone
        default: return nil
        }
    }

    static let doPainel = ["svg:tela", "svg:terminal", "svg:raio", "svg:microfone"]
}

/// O ícone da tecla: o do app de verdade, o desenho do painel ou a inicial.
struct IconeDaTecla: View {
    var tecla: Tecla
    var catalogo: CatalogoDeApps
    var lado: CGFloat = Tema.Medida.teclaIcone

    var body: some View {
        if tecla.tipo == "app", !tecla.valor.isEmpty {
            DoApp(nome: tecla.valor, catalogo: catalogo, lado: lado)
        } else if let ic = tecla.icone, ic.hasPrefix("svg:"), let s = IconesDeTecla.svg(String(ic.dropFirst(4))) {
            Caixa(lado: lado) { Svg(s, lado: lado / 2).foregroundColor(Tema.Cor.texto) }
        } else if let ic = tecla.icone, !ic.isEmpty, catalogo.app(ic) != nil {
            DoApp(nome: ic, catalogo: catalogo, lado: lado)
        } else {
            Caixa(lado: lado) { Svg(Icone.raio, lado: lado / 2).foregroundColor(Tema.Cor.texto) }
        }
    }

    struct Caixa<C: View>: View {
        var lado: CGFloat
        @ViewBuilder var conteudo: C
        var body: some View {
            conteudo.frame(width: lado, height: lado)
                .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
        }
    }

    struct DoApp: View {
        var nome: String
        var catalogo: CatalogoDeApps
        var lado: CGFloat
        var body: some View {
            if let c = catalogo.app(nome)?.caminhoDoIcone {
                Image(nsImage: IconesDeApps.imagem(c)).resizable().interpolation(.high)
                    .frame(width: lado, height: lado)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Caixa(lado: lado) { Text(String(nome.prefix(1)).uppercased()).font(.system(size: Tema.Texto.lg)).foregroundColor(Tema.Cor.texto2) }
            }
        }
    }
}

// MARK: - A tecla (a mesma do iPhone)

struct TeclaMac: View {
    var tecla: Tecla
    var catalogo: CatalogoDeApps
    var acesa = false
    var selecionada = false
    /// A prévia do editor: sem o lápis e com o fundo da tela.
    var previa = false
    var arrastando = false
    @State private var sobre = false

    private var nomeCabe: Bool {
        let largura = (tecla.nome as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: Tema.Texto.xs)]).width
        return largura <= Tema.Medida.teclaMac - 2 * Tema.Espaco.item
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous)
        VStack(spacing: Tema.Espaco.item) {
            IconeDaTecla(tecla: tecla, catalogo: catalogo)
            Text(tecla.nome)
                .font(.system(size: Tema.Texto.xs))
                .foregroundColor(acesa || selecionada ? Tema.Cor.texto : Tema.Cor.texto2)
                .lineLimit(1)
                .truncationMode(.tail)
                // Nome curto fica no meio. Nome que não cabe ocupa a largura toda e começa na borda (o
                // `text-overflow: ellipsis` do navegador), em vez de o texto cortado ficar centrado.
                .frame(maxWidth: .infinity, alignment: nomeCabe ? .center : .leading)
        }
        .padding(.init(top: Tema.Espaco.icone, leading: Tema.Espaco.item, bottom: Tema.Espaco.pad, trailing: Tema.Espaco.item))
        .frame(width: Tema.Medida.teclaMac, height: Tema.Medida.teclaMac)
        .overlay(alignment: .bottom) {
            Capsule().fill(acesa ? Tema.Cor.led : Tema.Cor.borda)
                .frame(width: acesa ? Tema.Medida.ledAcesoLarg : Tema.Medida.ledLarg, height: acesa ? Tema.Medida.ledAcesoAlt : Tema.Medida.ledAlt)
                .shadow(color: acesa ? Tema.Cor.led : .clear, radius: Tema.Sombra.brilhoRaio)
                .padding(.bottom, Tema.Espaco.item)
        }
        .overlay(alignment: .topLeading) {
            if selecionada && !previa {
                Svg(Icone.lapis, lado: Tema.Glifo.lapis).foregroundColor(Tema.Cor.fundo)
                    .frame(width: Tema.Medida.selo, height: Tema.Medida.selo)
                    .background(Tema.Cor.texto2, in: Circle())
                    .padding(Tema.Espaco.item)
            }
        }
        .background {
            ZStack {
                if !acesa { forma.fill(Tema.Cor.anel).padding(-1) }
                forma.fill(previa ? Tema.Cor.telaFundo : selecionada ? Tema.Cor.superficie2 : acesa ? Tema.Cor.sucessoSuave : (sobre ? Tema.Cor.superficie2 : Tema.Cor.superficie))
            }
        }
        .overlay { if acesa { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.forte) } }
        .shadow(color: acesa ? Tema.Cor.led.opacity(Tema.Opacidade.brilho) : .clear, radius: Tema.Sombra.brilhoRaio)
        .opacity(arrastando ? Tema.Opacidade.arrastando : 1)
        .contentShape(forma)
        .onHover { sobre = !previa && $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tecla.nome)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }
}

/// O "Nova" no fim da última página: o mesmo tamanho, só o contorno.
struct TeclaNova: View {
    var acao: () -> Void

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous)
        Button(action: acao) {
            VStack(spacing: Tema.Espaco.item) {
                Svg(Icone.mais, lado: Tema.Medida.teclaIcone / 2).frame(width: Tema.Medida.teclaIcone, height: Tema.Medida.teclaIcone)
                Text("Nova").font(.system(size: Tema.Texto.xs)).lineLimit(1)
            }
            .foregroundColor(Tema.Cor.texto2)
            .padding(.init(top: Tema.Espaco.icone, leading: Tema.Espaco.item, bottom: Tema.Espaco.pad, trailing: Tema.Espaco.item))
            .frame(width: Tema.Medida.teclaMac, height: Tema.Medida.teclaMac)
            .overlay { forma.strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.medio) }
            .contentShape(forma)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aviso

struct AvisoView: View {
    var aviso: AvisoDaJanela
    var desfazer: () -> Void

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            Text(aviso.texto).font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto)
                .frame(height: Tema.Texto.sm * Tema.Texto.altura)
            if aviso.temDesfazer {
                Button(action: desfazer) {
                    Text("Desfazer").font(.system(size: Tema.Texto.sm, weight: .semibold)).foregroundColor(Tema.Cor.destaque)
                        .frame(minHeight: Tema.Espaco.alvoSm)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Tema.Espaco.pad)
        .padding(.vertical, Tema.Espaco.icone)
        .background {
            RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).fill(Tema.Cor.superficie2)
                .shadow(color: Tema.Sombra.difusaCor, radius: Tema.Sombra.difusaRaio, y: Tema.Sombra.difusaY)
        }
    }
}

/// Quando a config não pôde ser salva: diz o motivo, em vez de a edição sumir sem aviso.
struct CartaoDeErro: View {
    var texto: String

    var body: some View {
        Text(texto)
            .font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.perigo)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tema.Espaco.pad)
            .padding(.vertical, Tema.Espaco.icone)
            .background(Tema.Cor.perigoSuave, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .accessibilityLabel("Problema ao salvar: \(texto)")
    }
}

// MARK: - Medidas só desta tela (mac.css, sem token próprio no CSS)

extension Tema.Medida {
    static let perfilAba: CGFloat = 34
    static let campoPerfil: CGFloat = 220
    static let busca: CGFloat = 36
    static let listaMax: CGFloat = 300
    static let icTipo: CGFloat = 28
    static let chipAlt: CGFloat = 28
    static let gravadorAlt: CGFloat = 44
    static let icEscolha: CGFloat = 36
    static let comandoMin: CGFloat = 64
    static let tituloAlt: CGFloat = 40
}

// MARK: - Modo foto

private struct FotografandoChave: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Só o renderizador de fotos liga. O ImageRenderer não desenha campo de texto nem arrastar do AppKit
    /// (vira um quadro amarelo), então nas fotos o campo vira texto parado, com o mesmo visual.
    var fotografando: Bool {
        get { self[FotografandoChave.self] }
        set { self[FotografandoChave.self] = newValue }
    }
}

/// Campo de texto que não aceita ficar vazio na config (nome de tecla, de perfil, comando): enquanto a
/// pessoa digita, o texto vive aqui. Só o que não é vazio vai para a config, e ao sair do campo vazio
/// volta o último valor gravado. Assim dá para apagar tudo e escrever de novo.
struct TextoComRascunho<Campo: View>: View {
    @Binding var texto: String
    var pedidoDeFoco = 0
    @ViewBuilder var campo: (Binding<String>) -> Campo
    @State private var rascunho: String
    @FocusState private var focado: Bool

    init(texto: Binding<String>, pedidoDeFoco: Int = 0, @ViewBuilder campo: @escaping (Binding<String>) -> Campo) {
        _texto = texto
        self.pedidoDeFoco = pedidoDeFoco
        self.campo = campo
        _rascunho = State(initialValue: texto.wrappedValue)
    }

    var body: some View {
        campo(Binding(get: { rascunho }, set: { novo in
            rascunho = novo
            if !novo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texto = novo }
        }))
        .focused($focado)
        .onChange(of: texto) { rascunho = $0 }
        .onChange(of: focado) { if !$0 { rascunho = texto } }
        .onChange(of: pedidoDeFoco) { _ in focado = true }
    }
}

/// Campo de uma linha. Nas fotos, o texto parado no mesmo lugar.
struct CampoDeLinha: View {
    var dica: String
    @Binding var texto: String
    var pedidoDeFoco = 0
    @Environment(\.fotografando) private var foto

    var body: some View {
        if foto {
            Text(texto.isEmpty ? dica : texto).foregroundColor(texto.isEmpty ? Tema.Cor.texto3 : nil).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextoComRascunho(texto: $texto, pedidoDeFoco: pedidoDeFoco) { TextField(dica, text: $0) }
        }
    }
}

extension View {
    /// Arrastar e soltar de uma tecla. Fora das fotos.
    @ViewBuilder func arrastavel(_ ativo: Bool, ao arrastar: @escaping () -> NSItemProvider, soltar delegate: some DropDelegate) -> some View {
        if ativo { onDrag(arrastar).onDrop(of: [.plainText], delegate: delegate) } else { self }
    }
}

extension Tema.Texto {
    /// `<small>` do navegador: 5/6 do texto de quem o contém (13 px no Mac).
    static let pequeno: CGFloat = Tema.Texto.sm * 5 / 6
    /// Altura de linha do texto pequeno dos cartões de tipo (.tipo small).
    static let alturaTipo: CGFloat = 1.35
}

extension Text {
    /// Título de grupo ou de passo (h3 e h4 do protótipo): altura de linha 1.2 e -0.02em de espaço entre letras.
    func titulinho(_ tamanho: CGFloat, _ peso: Font.Weight, _ cor: Color) -> some View {
        font(.system(size: tamanho, weight: peso))
            .tracking(Tema.Texto.trackingTitulo(Tema.Texto.sm))
            .foregroundColor(cor)
            .lineLimit(1)
            .frame(height: Tema.Texto.sm * Tema.Texto.alturaTitulo)
    }
}
