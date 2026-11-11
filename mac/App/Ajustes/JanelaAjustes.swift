import SwiftUI
import AppKit

/// A janela de Ajustes, igual ao `.janela` do protótipo (mac.html e mac.css): barra lateral com as
/// seções e a assinatura, e à direita o título da seção, o estado da sincronia e o conteúdo.
/// Cada seção é uma View em arquivo próprio (Ajustes/*.swift).
struct JanelaAjustes: View {
    @ObservedObject var modelo: ModeloApp
    /// Só nas fotos: desenha os três botões do canto, que no app são os do próprio macOS.
    var desenhaSemaforo = false
    /// O app confere o ícone da barra ao abrir os Ajustes e a cada vez que o Deck ganha o foco. Testes e fotos não passam nada.
    var conferirIcone: (@MainActor () -> Void)?
    @Environment(\.emFoto) private var emFoto
    @ObservedObject private var painelUso = PainelUso.atual

    var body: some View {
        HStack(spacing: 0) {
            BarraLateral(modelo: modelo, desenhaSemaforo: desenhaSemaforo)
                .frame(width: Tema.Medida.lateral)
            Conteudo(modelo: modelo)
        }
        // 1 px de borda do protótipo (box-sizing: border-box): o conteúdo mede 2 px a menos.
        .frame(width: Tema.Medida.janelaLarg - 2, height: Tema.Medida.janelaAlt - 2)
        .padding(1)
        .background(Tema.Cor.telaFundo)
        .overlay(alignment: .bottom) { AvisoNaJanela(aviso: modelo.aviso) }
        // Nas fotos a tela monta a própria camada (Fotos/Telas.swift).
        .overlay { if !emFoto { CamadaDoUso(modelo: modelo, painel: painelUso) } }
        .background(ConfiguradorDaJanela())
        .onAppear { conferirIcone?() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in conferirIcone?() }
    }
}

/// A pílula do aviso, sozinha (as fotos a fotografam assim).
struct AvisoPilula: View {
    var aviso: AvisoDeTela

    var body: some View {
        Text(aviso.texto)
            .font(.system(size: Tema.Texto.sm))
            .foregroundColor(aviso.falha ? Tema.Cor.perigo : Tema.Cor.texto)
            .lineSpacing(Tema.Texto.sm * (Tema.Texto.altura - 1.2))
            .multilineTextAlignment(.center)
            .frame(minHeight: Tema.Texto.sm * Tema.Texto.altura)
            .padding(.horizontal, Tema.Espaco.pad)
            .padding(.vertical, Tema.Espaco.icone)
            .frame(maxWidth: Tema.Aviso.larguraMax)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).strokeBorder(Tema.Cor.anelForte, lineWidth: Tema.Espaco.fio) }
            .shadow(color: Tema.Sombra.difusaCor, radius: Tema.Sombra.difusaRaio, y: Tema.Sombra.difusaY)
    }
}

/// O `.aviso` do protótipo: pílula curta embaixo, no centro, que entra e some sozinha.
private struct AvisoNaJanela: View {
    var aviso: AvisoDeTela?

    var body: some View {
        ZStack {
            if let aviso {
                AvisoPilula(aviso: aviso)
                    .padding(.bottom, Tema.Espaco.pad)
                    .id(aviso.id)
                    .transition(.opacity.combined(with: .offset(y: Tema.Espaco.item)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(aviso == nil ? Tema.Mov.sai : Tema.Mov.entra, value: aviso)
        .allowsHitTesting(false)
    }
}

/// O quadro que o protótipo põe na janela (borda, raio). No app o macOS faz isso, então só nas fotos.
struct QuadroDaJanela<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        conteudo
            .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous).strokeBorder(Tema.Cor.molduraBorda, lineWidth: 1) }
    }
}

// MARK: - Barra lateral

private struct BarraLateral: View {
    @ObservedObject var modelo: ModeloApp
    var desenhaSemaforo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
            // O espaço dos três botões do macOS, que ficam em cima da barra lateral.
            Semaforo(desenha: desenhaSemaforo)
            Navegacao(modelo: modelo)
            Spacer(minLength: 0)
            Text("Feito por Leonardo Rejani").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                .padding(.horizontal, Tema.Espaco.item)
        }
        .padding(.horizontal, Tema.Espaco.item)
        .padding(.vertical, Tema.Espaco.icone)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) { Rectangle().fill(Tema.Cor.borda).frame(width: 1) }
    }
}

private struct Semaforo: View {
    var desenha: Bool

    var body: some View {
        let d = Tema.Medida.semaforo
        HStack(spacing: Tema.Espaco.item) {
            if desenha {
                Circle().fill(Tema.Cor.semaforo1).frame(width: d, height: d)
                Circle().fill(Tema.Cor.semaforo2).frame(width: d, height: d)
                Circle().fill(Tema.Cor.semaforo3).frame(width: d, height: d)
            }
        }
        .frame(height: d, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.init(top: Tema.Espaco.item, leading: Tema.Espaco.item, bottom: 0, trailing: Tema.Espaco.item))
    }
}

private struct Navegacao: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        let grupos = SecaoAjustes.grupos
        VStack(spacing: Tema.Espaco.fino) {
            ForEach(Array(grupos.enumerated()), id: \.offset) { i, grupo in
                if i > 0 { Color.clear.frame(height: Tema.Espaco.item) }
                ForEach(grupo) { secao in
                    ItemDaNavegacao(secao: secao, atual: modelo.secao == secao,
                                    selo: secao == .permissoes ? modelo.acessosRecusados.count : secao == .iphone && modelo.renovacaoApertando ? 1 : 0,
                                    descricaoDoSelo: secao == .iphone ? "aviso" : "faltando") { modelo.secao = secao }
                }
            }
        }
    }
}

private struct ItemDaNavegacao: View {
    var secao: SecaoAjustes
    var atual: Bool
    var selo: Int
    var descricaoDoSelo = "faltando"
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.icone) {
                Svg(secao.icone, lado: Tema.Medida.iconeNav)
                    .foregroundColor(atual ? Tema.Cor.led : Tema.Cor.texto)
                    .frame(width: Tema.Medida.icSec, height: Tema.Medida.icSec)
                    .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                Text(secao.nome).tatile(Tema.Texto.sm, atual ? .semibold : .regular, atual ? Tema.Cor.texto : (sobre ? Tema.Cor.texto : Tema.Cor.texto2))
                Spacer(minLength: 0)
                if selo > 0 {
                    Text("\(selo)").font(.system(size: Tema.Texto.xs, weight: .bold)).monospacedDigit()
                        .foregroundColor(Tema.Cor.fundo)
                        .padding(.horizontal, Tema.Espaco.mini)
                        .frame(minWidth: Tema.Medida.seloNavAlt, minHeight: Tema.Medida.seloNavAlt)
                        .background(Tema.Cor.perigo, in: Capsule())
                        .accessibilityLabel("\(selo) \(descricaoDoSelo)")
                }
            }
            .padding(.horizontal, Tema.Espaco.item)
            .frame(maxWidth: .infinity, minHeight: Tema.Medida.navAlt, alignment: .leading)
            .background {
                if atual {
                    ZStack {
                        RoundedRectangle(cornerRadius: Tema.Raio.normal + 1, style: .continuous).fill(Tema.Cor.anel).padding(-1)
                        RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).fill(Tema.Cor.superficie)
                    }
                } else if sobre {
                    RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).fill(Tema.Cor.superficie)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .accessibilityAddTraits(atual ? .isSelected : [])
    }
}

// MARK: - Conteúdo

private struct Conteudo: View {
    @ObservedObject var modelo: ModeloApp
    @Environment(\.emFoto) private var emFoto
    @Environment(\.fotografando) private var fotografando

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tema.Espaco.icone) {
                Text(modelo.secao.nome)
                    .font(.system(size: Tema.Texto.lg, weight: .bold))
                    .tracking(Tema.Texto.trackingTitulo(Tema.Texto.lg))
                    .foregroundColor(Tema.Cor.texto)
                    .frame(height: Tema.Texto.lg * Tema.Texto.alturaTitulo)
                Spacer(minLength: 0)
                HStack(spacing: Tema.Espaco.item) {
                    Ponto(ligado: modelo.iphoneAtivo != nil)
                    Text(TextosDoMenu.sincronia(modelo.iphoneAtivo, salvoAgora: modelo.salvoAgora))
                        .tatile(Tema.Texto.xs, .regular, modelo.salvoAgora ? Tema.Cor.led : Tema.Cor.texto2)
                        .animation(Tema.Mov.move, value: modelo.salvoAgora)
                }
            }
            .padding(.init(top: Tema.Espaco.pad, leading: Tema.Espaco.margem, bottom: Tema.Espaco.icone, trailing: Tema.Espaco.margem))

            if modelo.iconeEscondido {
                AvisoIconeEscondido { NSWorkspace.shared.open(ItemDaBarra.urlDosAjustes) }
                    .padding(.init(top: 0, leading: Tema.Espaco.margem, bottom: Tema.Espaco.icone, trailing: Tema.Espaco.margem))
            }

            Group {
                if emFoto || fotografando {
                    // Mais alto que a janela: o protótipo rola e a foto corta embaixo, sempre a partir do topo.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).overlay(alignment: .top) { corpoComMargem.fixedSize(horizontal: false, vertical: true) }.clipped()
                } else {
                    ScrollView { corpoComMargem }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var corpoComMargem: some View {
        corpo
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.init(top: Tema.Espaco.item, leading: Tema.Espaco.margem, bottom: Tema.Espaco.margem, trailing: Tema.Espaco.margem))
    }

    @ViewBuilder private var corpo: some View {
        switch modelo.secao {
        case .teclas: SuasTeclas(modelo: modelo)
        case .uso: UsoIAs(modelo: modelo)
        case .iphone: ConectarIphone(modelo: modelo)
        case .permissoes: Acessos(modelo: modelo)
        case .geral: EsteMac(modelo: modelo)
        case .sobre: Sobre(modelo: modelo)
        }
    }
}

/// O cartão amarelo do ícone escondido, no visual do alerta da renovação.
struct AvisoIconeEscondido: View {
    var abrir: () -> Void

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            Svg(Icone.alerta, lado: Tema.Medida.icSec).foregroundColor(Tema.Cor.aviso)
            VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                Text(ItemDaBarra.tituloDoAviso).tatile(Tema.Texto.sm, .bold, Tema.Cor.texto, linhas: nil)
                Text(ItemDaBarra.caminhoDoAviso).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto, linhas: nil)
                Text(ItemDaBarra.apoioDoAviso).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2, linhas: nil)
                    .lineSpacing(Tema.Texto.xs * (Tema.Texto.altura - 1.2))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            BotaoDeAjuste(texto: "Abrir Barra de Menus", estilo: .primario, acao: abrir)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

// MARK: - Janela do macOS

/// Deixa a janela de Ajustes como a do protótipo: sem barra de título, com o conteúdo por baixo dos
/// três botões, tamanho fixo e fundo do Deck. Os botões continuam sendo os do macOS.
struct ConfiguradorDaJanela: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let w = v?.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.styleMask.remove(.resizable)
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(Tema.Cor.telaFundo)
            w.appearance = NSAppearance(named: .darkAqua)
            w.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            w.standardWindowButton(.zoomButton)?.isEnabled = false
        }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}
