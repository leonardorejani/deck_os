import SwiftUI
import AppKit

/// Configuração inicial em 7 passos, igual ao protótipo (prototipo/mac.js, abrirIni e TELAS_INI).
/// Abre sozinha na primeira vez (sem config.json) e quando a pessoa escolhe "Refazer". Nenhum passo
/// é obrigatório, e tudo fica centralizado, na largura e na altura.
struct ConfiguracaoInicial: View {
    @ObservedObject var modelo: ModeloApp
    @StateObject private var assistente: AssistenteInicial

    @MainActor init(modelo: ModeloApp, acoes: AcoesDaInicial? = nil) {
        self.modelo = modelo
        _assistente = StateObject(wrappedValue: AssistenteInicial(modelo: modelo, acoes: acoes ?? AcoesDaInicial.doSistema()))
    }

    var body: some View {
        ConteudoDaInicial(modelo: modelo, assistente: assistente)
            .onAppear { assistente.abriu() }
            .onDisappear { assistente.fechou() }
    }
}

extension AcoesDaInicial {
    /// As ações do app de verdade: fechar a janela da configuração e abrir o menu da barra.
    @MainActor static func doSistema(conectarOutraConta: @escaping (@escaping (ContaAchada) -> Void) -> Void = { _ in }) -> AcoesDaInicial {
        var a = AcoesDaInicial()
        a.fechar = { NSApp.keyWindow?.close() }
        a.abrirMenuDaBarra = { MenuDaBarraAberto.abrir() }
        a.conectarOutraConta = conectarOutraConta
        return a
    }
}

/// O conteúdo, separado para o renderizador de fotos montar sem passar pelo StateObject.
struct ConteudoDaInicial: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: 0) {
            BarraDeProgresso(passo: assistente.passo)
            CorpoDaInicial(assistente: assistente)
            RodapeDaInicial(assistente: assistente)
        }
        .padding(Tema.Inicial.borda)
        .frame(width: Tema.Medida.iniLarg, height: Tema.Medida.iniAlt)
        .background { FundoDaInicial() }
        .overlay(alignment: .bottom) {
            if let aviso = assistente.aviso { AvisoDaInicial(texto: aviso).padding(.bottom, Tema.Espaco.pad).transition(.opacity) }
        }
        .animation(Tema.Mov.entra, value: assistente.aviso)
    }
}

// MARK: - Fundo, barra e rodapé

/// O brilho verde do Deck no topo: `radial-gradient(80% 60% at 50% 0%, sucesso-suave, transparent 70%)` sobre a tela.
private struct FundoDaInicial: View {
    var body: some View {
        Canvas { ctx, tamanho in
            ctx.fill(Path(CGRect(origin: .zero, size: tamanho)), with: .color(Tema.Cor.telaFundo))
            let rx = tamanho.width * Tema.Inicial.fundoLarg, ry = tamanho.height * Tema.Inicial.fundoAlt
            ctx.translateBy(x: tamanho.width / 2, y: 0)
            ctx.scaleBy(x: 1, y: ry / rx)
            let gradiente = Gradient(colors: [Tema.Cor.sucessoSuave, Tema.Cor.sucessoSuave.opacity(0)])
            ctx.fill(Path(CGRect(x: -tamanho.width, y: 0, width: tamanho.width * 2, height: rx)),
                     with: .radialGradient(gradiente, center: .zero, startRadius: 0, endRadius: rx * Tema.Inicial.fundoFim))
        }
    }
}

private struct BarraDeProgresso: View {
    var passo: PassoInicial

    var body: some View {
        HStack(spacing: Tema.Espaco.mini) {
            ForEach(PassoInicial.allCases, id: \.rawValue) { p in
                let cheia = p.rawValue <= passo.rawValue
                Capsule()
                    .fill(cheia ? Tema.Cor.led : Tema.Cor.superficie2)
                    .frame(height: Tema.Inicial.barraAlt)
                    .shadow(color: cheia ? Tema.Cor.led : .clear, radius: Tema.Inicial.barraBrilho)
            }
        }
        .animation(Tema.Mov.move, value: passo)
        .padding(.horizontal, Tema.Espaco.secao)
        .padding(.top, Tema.Espaco.pad)
        .accessibilityHidden(true)
    }
}

private struct RodapeDaInicial: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        HStack(spacing: Tema.Espaco.item) {
            if !assistente.passo.primeiro {
                BotaoDaInicial(texto: "Voltar", estilo: .secundario) { assistente.voltar() }
            }
            Spacer(minLength: 0)
            if assistente.podePular {
                BotaoDaInicial(texto: "Fazer depois", estilo: .link) { assistente.pular() }
            }
            BotaoDaInicial(texto: assistente.textoDoBotao, estilo: .primario, desligado: !assistente.podeAvancar) { assistente.avancar() }
        }
        .padding(.horizontal, Tema.Espaco.secao)
        .padding(.vertical, Tema.Espaco.pad)
        .overlay(alignment: .top) { Rectangle().fill(Tema.Cor.borda).frame(height: 1) }
    }
}

struct BotaoDaInicial: View {
    enum Estilo { case primario, secundario, link }

    var texto: String
    var estilo: Estilo
    var desligado = false
    /// Os botões do rodapé medem 36 e têm 20 de margem. Os de dentro das telas (.btn) medem 32 e têm 12.
    var compacto = false
    /// Dentro do endereço o botão herda a fonte de código.
    var codigo = false
    var acao: () -> Void

    var body: some View {
        // Não usa .disabled: o SwiftUI esmaece o botão por conta própria (cerca de 50%) e o protótipo pede 40%.
        Button(action: { if !desligado { acao() } }) {
            Text(texto)
                .font(codigo ? .custom(Tema.Inicial.fonteDeCodigoNegrito, size: Tema.Texto.sm) : .system(size: Tema.Texto.sm, weight: .semibold))
                .foregroundColor(cor)
                .lineLimit(1)
                .frame(height: Tema.Texto.sm * Tema.Texto.altura)
                .padding(.horizontal, compacto ? Tema.Espaco.icone : Tema.Inicial.botaoPad)
                .frame(minHeight: compacto ? Tema.Espaco.alvoSm : Tema.Inicial.botaoAlt)
                .background(fundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(desligado ? Tema.Inicial.desligadoOpacidade : 1)
        .allowsHitTesting(!desligado)
    }

    private var cor: Color {
        switch estilo {
        case .primario: return Tema.Cor.destaqueTexto
        case .secundario: return Tema.Cor.texto
        case .link: return Tema.Cor.texto2
        }
    }

    private var fundo: Color {
        switch estilo {
        case .primario: return Tema.Cor.destaque
        case .secundario: return Tema.Cor.superficie2
        case .link: return .clear
        }
    }
}

/// O aviso curto de baixo (mac.css, .aviso).
private struct AvisoDaInicial: View {
    var texto: String

    var body: some View {
        Text(texto).tatile(Tema.Texto.sm)
            .padding(.horizontal, Tema.Espaco.pad)
            .padding(.vertical, Tema.Espaco.icone)
            .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .shadow(color: Tema.Sombra.difusaCor, radius: Tema.Sombra.difusaRaio, y: Tema.Sombra.difusaY)
    }
}

// MARK: - Corpo

private struct CorpoDaInicial: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        // Tudo no meio, na largura e na altura. Passo que não cabe (muitas contas) ganha rolagem.
        ViewThatFits(in: .vertical) {
            tela.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView(.vertical, showsIndicators: false) { tela.frame(maxWidth: .infinity) }
        }
        .padding(.top, Tema.Espaco.secao)
        .padding(.horizontal, Tema.Espaco.secao)
        .padding(.bottom, Tema.Espaco.pad)
        .frame(maxHeight: .infinity)
        .id(assistente.passo)
        .transition(.opacity)
    }

    @ViewBuilder private var tela: some View {
        switch assistente.passo {
        case .boas: TelaBoasVindas()
        case .iphone: TelaIphone(assistente: assistente)
        case .layout: TelaLayout(assistente: assistente)
        case .contas: TelaContas(assistente: assistente)
        case .teclas: TelaTeclas(assistente: assistente)
        case .acessos: TelaAcessos(assistente: assistente)
        case .pronto: TelaPronto(assistente: assistente)
        }
    }
}
