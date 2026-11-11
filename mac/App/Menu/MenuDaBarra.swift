import SwiftUI
import AppKit

/// O que o menu faz fora dele mesmo: abrir janelas e sair. No app vêm do sistema, nas fotos ficam vazias.
struct AcoesDoMenu {
    var abrirAjustes: () -> Void = {}
    var abrirConfiguracaoInicial: () -> Void = {}
    var sair: () -> Void = {}
}

/// O menu da barra, igual ao popover do protótipo (mac.js, pintarPop): topo com o estado do iPhone,
/// layout, perfil, aviso de acesso recusado, Ajustes e Sair.
struct MenuDaBarra: View {
    @ObservedObject var modelo: ModeloApp
    var acoes = AcoesDoMenu()

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Topo(iphone: modelo.iphoneAtivo)
            if let pedido = modelo.pedidoBluetooth {
                BlocoDoPedido(pedido: pedido) { modelo.responderPedido(permitir: $0) }
            }
            if !modelo.configuracaoInicialFeita {
                BlocoInicial(continuar: { acoes.abrirConfiguracaoInicial() })
            } else if modelo.iphoneAtivo != nil {
                BlocoLayout(atual: modelo.config.comp, escolher: modelo.usarComposicao)
            } else if modelo.pedidoBluetooth == nil {
                BotaoPrimario(texto: "Parear um iPhone") { modelo.secao = .iphone; acoes.abrirAjustes() }
            }
            if modelo.configuracaoInicialFeita, modelo.config.perfis.count > 1 {
                BlocoPerfil(perfis: modelo.config.perfis, ativo: modelo.config.perfilAtivo, escolher: modelo.usarPerfil)
            }
            if modelo.renovacaoApertando, case .apertando(let vence) = modelo.estadoDaRenovacao {
                AlertaDoMenu(texto: TextosDoNativo.venceEm(vence, agora: modelo.agora)) { modelo.secao = .iphone; acoes.abrirAjustes() }
            }
            if !modelo.acessosRecusados.isEmpty {
                AlertaDoMenu(texto: TextosDoMenu.acessosRecusados(modelo.acessosRecusados.count)) { modelo.secao = .permissoes; acoes.abrirAjustes() }
            }
            if case .falhou = modelo.servidor {
                AlertaDoMenu(texto: TextosDoMenu.servidorFalhou) { modelo.secao = .iphone; acoes.abrirAjustes() }
            }
            if let aviso = modelo.avisoDePorta {
                AlertaDoMenu(texto: aviso) { modelo.secao = .iphone; acoes.abrirAjustes() }
            }
            Separador()
            ItemDoMenu(titulo: "Ajustes...", atalho: "⌘,") { acoes.abrirAjustes() }
                .keyboardShortcut(",", modifiers: .command)
            Separador()
            ItemDoMenu(titulo: "Sair do Deck", atalho: "⌘Q") { acoes.sair() }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(Tema.Espaco.icone)
        .frame(width: Tema.Medida.popoverLarg - 2, alignment: .leading)
        // 1 px de borda do protótipo (box-sizing: border-box): o conteúdo mede 2 px a menos.
        .padding(1)
        .background(Tema.Cor.telaFundo)
    }
}

/// O popover como o protótipo o desenha (borda, raio e sombra próprios). O macOS põe a moldura dele
/// no app de verdade, então isto só entra nas fotos.
struct QuadroDoPopover<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        conteudo
            .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous).strokeBorder(Tema.Cor.molduraBorda, lineWidth: 1) }
    }
}

// MARK: - Partes

private struct Topo: View {
    var iphone: IphonePareado?

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            Logo()
            VStack(alignment: .leading, spacing: 0) {
                Text("Deck").tatile(Tema.Texto.base, .bold)
                HStack(spacing: Tema.Espaco.item) {
                    Ponto(ligado: iphone != nil)
                    Text(TextosDoMenu.estadoIphone(iphone)).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.init(top: Tema.Espaco.micro, leading: Tema.Espaco.micro, bottom: Tema.Espaco.item, trailing: Tema.Espaco.micro))
    }
}

private struct BlocoMenu<Conteudo: View>: View {
    var rotulo: String
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text(rotulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            conteudo
        }
        .padding(Tema.Espaco.icone)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

/// O pedido de pareamento por Bluetooth no menu (mac.js, natPop): o código, o aviso e Recusar e Permitir.
private struct BlocoDoPedido: View {
    var pedido: PedidoDePareamento
    var responder: (Bool) -> Void

    var body: some View {
        BlocoMenu(rotulo: TextosDoNativo.pedidoRotulo(pedido.iphone)) {
            Text(ParearIphone.codigoEmGrupos(pedido.codigo))
                .font(.system(size: Tema.Texto.xl2, weight: .bold))
                .tracking(0.1 * Tema.Texto.xl2)
                .monospacedDigit()
                .foregroundColor(Tema.Cor.texto)
                .lineLimit(1)
                .frame(height: Tema.Texto.xl2, alignment: .leading)
            Text(TextosDoNativo.pedidoTexto).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2, linhas: nil)
                .lineSpacing(4).padding(.vertical, 2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Tema.Espaco.item) {
                MenuBotao(texto: "Recusar", primario: false) { responder(false) }
                MenuBotao(texto: "Permitir", primario: true) { responder(true) }
            }
        }
    }
}

private struct MenuBotao: View {
    var texto: String
    var primario: Bool
    var acao: () -> Void

    var body: some View {
        if primario { BotaoPrimario(texto: texto, acao: acao) } else { Button(action: acao) {
                Text(texto).tatile(Tema.Texto.sm, .semibold, Tema.Cor.texto)
                    .padding(.horizontal, Tema.Espaco.icone)
                    .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm)
                    .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain) }
    }
}

private struct BlocoInicial: View {
    var continuar: () -> Void

    var body: some View {
        BlocoMenu(rotulo: "Configuração inicial") {
            Text("Faltam alguns passos para o iPhone mostrar o Deck.")
                .tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2, linhas: nil)
                // altura de linha de 1.5: 4 pt entre linhas e meio espaço em cima e embaixo, como a caixa do CSS
                .lineSpacing(4)
                .padding(.vertical, 2)
                .fixedSize(horizontal: false, vertical: true)
            BotaoPrimario(texto: "Continuar configuração", acao: continuar)
        }
    }
}

private struct BlocoLayout: View {
    var atual: String
    var escolher: (String) -> Void

    var body: some View {
        BlocoMenu(rotulo: "Layout no iPhone") {
            HStack(spacing: Tema.Espaco.item) {
                ForEach(["a", "b"], id: \.self) { c in
                    Button { escolher(c) } label: {
                        VStack(spacing: Tema.Espaco.mini) {
                            MiniTela(composicao: c)
                            Text(TextosDoMenu.composicao(c)).tatile(Tema.Texto.xs, .regular, atual == c ? Tema.Cor.texto : Tema.Cor.texto2)
                        }
                        .padding(Tema.Espaco.item)
                        .frame(maxWidth: .infinity)
                        .background(atual == c ? Tema.Cor.sucessoSuave : Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
                        .contornoInterno(atual == c ? Tema.Cor.led : .clear, largura: 2, raio: Tema.Raio.card)
                        .contentShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(atual == c ? .isSelected : [])
                }
            }
        }
    }
}

/// O desenho da composição (mac.css, .mini-tela): proporção da tela do iPhone deitado.
private struct MiniTela: View {
    var composicao: String

    var body: some View {
        GeometryReader { g in
            let folga = Tema.Espaco.mini, vao = Tema.Espaco.micro
            let w = g.size.width - folga * 2, h = g.size.height - folga * 2
            Group {
                if composicao == "a" { desenhoA(w, h, vao) } else { desenhoB(w, h, vao) }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(932.0 / 430.0, contentMode: .fit)
        .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
    }

    private func caixa(_ cor: Color = Tema.Cor.superficie2) -> some View {
        RoundedRectangle(cornerRadius: Tema.Raio.fino, style: .continuous).fill(cor)
    }

    /// Relógio em cima: duas colunas e duas linhas, e a fileira de teclas (5, um traço fino, 1).
    private func desenhoA(_ w: CGFloat, _ h: CGFloat, _ vao: CGFloat) -> some View {
        let fr = (h - vao * 2) / 3.1
        let col = (w - vao) / 2
        let tecla = (w - vao * 6 - 2) / 6
        return VStack(spacing: vao) {
            HStack(spacing: vao) { caixa(Tema.Cor.texto3).frame(width: col); caixa().frame(width: col) }.frame(height: fr)
            HStack(spacing: vao) { caixa().frame(width: col); caixa().frame(width: col) }.frame(height: fr)
            HStack(spacing: vao) {
                ForEach(0..<5, id: \.self) { _ in caixa().frame(width: tecla) }
                caixa().frame(width: 2)
                caixa().frame(width: tecla)
            }
            .frame(height: fr * 1.1)
        }
    }

    /// Deck 3 x 3: à esquerda três faixas, à direita nove teclas.
    private func desenhoB(_ w: CGFloat, _ h: CGFloat, _ vao: CGFloat) -> some View {
        let col = (w - vao) / 2
        let linha = (h - vao * 2) / 3
        let tecla = (col - vao * 2) / 3
        return HStack(spacing: vao) {
            VStack(spacing: vao) {
                caixa(Tema.Cor.texto3).frame(height: linha)
                caixa().frame(height: linha)
                caixa().frame(height: linha)
            }
            .frame(width: col)
            VStack(spacing: vao) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: vao) { ForEach(0..<3, id: \.self) { _ in caixa().frame(width: tecla) } }.frame(height: linha)
                }
            }
            .frame(width: col)
        }
    }
}

private struct BlocoPerfil: View {
    var perfis: [Perfil]
    var ativo: String
    var escolher: (String) -> Void

    var body: some View {
        BlocoMenu(rotulo: "Perfil no iPhone") {
            let folga: CGFloat = 3
            HStack(spacing: folga) {
                ForEach(perfis, id: \.id) { p in
                    Button { escolher(p.id) } label: {
                        Text(p.nome).tatile(Tema.Texto.sm, .regular, p.id == ativo ? Tema.Cor.texto : Tema.Cor.texto2)
                            .padding(.horizontal, Tema.Espaco.icone)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background {
                                if p.id == ativo {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Tema.Raio.normal - folga + 1, style: .continuous).fill(Tema.Cor.anel).padding(-1)
                                        RoundedRectangle(cornerRadius: Tema.Raio.normal - folga, style: .continuous).fill(Tema.Cor.superficie2)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(folga)
            .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
        }
    }
}

private struct AlertaDoMenu: View {
    var texto: String
    var abrir: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: abrir) {
            HStack(spacing: Tema.Espaco.icone) {
                Svg(Icone.alerta, lado: 16)
                Text(texto).tatile(Tema.Texto.sm, .regular, Tema.Cor.aviso, linhas: nil).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(Tema.Cor.aviso)
            .padding(.horizontal, Tema.Espaco.icone)
            .padding(.vertical, Tema.Espaco.item)
            .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm)
            .background(sobre ? Tema.Cor.superficie2 : Tema.Cor.superficie, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
    }
}

private struct Separador: View {
    var body: some View {
        Rectangle().fill(Tema.Cor.borda).frame(height: 1)
            .padding(.horizontal, Tema.Espaco.item).padding(.vertical, Tema.Espaco.micro)
    }
}

private struct ItemDoMenu: View {
    var titulo: String
    var atalho: String
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        Button(action: acao) {
            HStack {
                Text(titulo).tatile(Tema.Texto.sm)
                Spacer(minLength: 0)
                Text(atalho).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
            }
            .padding(.horizontal, Tema.Espaco.item)
            .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm)
            .background(sobre ? Tema.Cor.superficie : .clear, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
    }
}

/// Botão principal (o único azul da tela), como `.btn.primario` do protótipo.
struct BotaoPrimario: View {
    var texto: String
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(texto).tatile(Tema.Texto.sm, .semibold, Tema.Cor.destaqueTexto)
                .padding(.horizontal, Tema.Espaco.icone)
                .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm)
                .background(Tema.Cor.destaque, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
