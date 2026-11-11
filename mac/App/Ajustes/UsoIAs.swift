import SwiftUI

/// Seção "Uso das IAs" dos Ajustes, igual ao protótipo (prototipo/mac.js, TELAS.uso): "Mais perto do
/// limite", um cartão por conta com o uso real da semana e o cartão "Adicionar conta".
struct UsoIAs: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject private var painel = PainelUso.atual
    var body: some View {
        let contas = modelo.config.contas
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            if let perto = UsoLogica.maisPerto(contas: contas, uso: painel.usos) {
                HStack(spacing: 0) {
                    Text("Mais perto do limite: ").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
                    Text(perto.conta.conta).tatile(Tema.Texto.sm, .bold, Tema.Cor.texto)
                    Text(", \(perto.semana)% da semana.").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
                }
                .accessibilityElement(children: .combine)
            }
            Grade(contas: contas, modelo: modelo, painel: painel)
            Text("O nome é o que aparece no iPhone. Conta só a janela semanal.").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Sair da seção fecha a janela Adicionar conta (a camada dela mora em JanelaAjustes, por cima da janela inteira).
        .onDisappear { painel.fecharConta() }
        .background {
            // ⌘Z desfaz a última remoção enquanto o aviso com "Desfazer" está na tela.
            Button("Desfazer") { painel.desfazerUltimo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!painel.podeDesfazer)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task(id: contas.map(\.id)) {
            while !Task.isCancelled {
                await painel.atualizar(modelo.config.contas)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

/// Três cartões por linha. Na última linha o cartão mais baixo estica até a altura do vizinho (o grid do CSS).
private struct Grade: View {
    var contas: [ContaIA]
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var painel: PainelUso

    private enum Item: Identifiable {
        case conta(ContaIA), nova
        var id: String { if case .conta(let c) = self { return c.id } else { return "nova" } }
    }

    var body: some View {
        let itens = contas.map(Item.conta) + [.nova]
        let linhas = stride(from: 0, to: itens.count, by: Tema.Uso.colunas).map { Array(itens[$0..<min($0 + Tema.Uso.colunas, itens.count)]) }
        VStack(spacing: Tema.Espaco.grade) {
            ForEach(Array(linhas.enumerated()), id: \.offset) { _, linha in
                HStack(spacing: Tema.Espaco.grade) {
                    ForEach(0..<Tema.Uso.colunas, id: \.self) { i in
                        if i < linha.count {
                            switch linha[i] {
                            case .conta(let c): CartaoConta(conta: c, modelo: modelo, painel: painel)
                            case .nova: CartaoNovaConta { painel.abrirConta(modelo: modelo) }
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CartaoConta: View {
    var conta: ContaIA
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var painel: PainelUso
    @State private var sobre = false
    @FocusState private var focoRemover: Bool

    var body: some View {
        let uso = painel.usos[conta.id]
        let nivel = uso?.semana.map(UsoLogica.nivel) ?? .normal
        let destaque: Color = nivel == .cheio ? Tema.Cor.perigo : nivel == .alto ? Tema.Cor.aviso : Tema.Cor.texto
        let barra: Color = nivel == .cheio ? Tema.Cor.perigo : nivel == .alto ? Tema.Cor.aviso : Tema.Cor.texto2
        let oculta = conta.mostrar == false
        let mostraRemover = sobre || focoRemover || painel.sobreFixo == conta.id
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            HStack(spacing: Tema.Espaco.item) {
                Image(conta.nome == "Claude" ? "IcClaude" : "IcCodex").resizable().interpolation(.high)
                    .frame(width: Tema.Medida.icConta, height: Tema.Medida.icConta)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                    .accessibilityHidden(true)
                CampoNomeConta(nome: conta.conta) { modelo.renomearConta(id: conta.id, para: $0) }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(-1)
                HStack(spacing: Tema.Espaco.item) {
                    Text("No iPhone").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2).fixedSize()
                    ChaveUso(ligada: !oculta, rotulo: "Mostrar \(conta.conta) no iPhone") { modelo.mostrarConta(id: conta.id, noIphone: $0) }
                }
            }
            Text(UsoLogica.subtitulo(conta)).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
            HStack(alignment: .firstTextBaseline, spacing: Tema.Espaco.item) {
                if let s = uso?.semana {
                    Text("\(s)%").font(.system(size: Tema.Texto.xl2, weight: .bold)).monospacedDigit().foregroundColor(destaque)
                        .frame(height: Tema.Texto.xl2)
                    Text("da semana").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
                } else {
                    Text("Sem medição").font(.system(size: Tema.Texto.lg, weight: .bold)).foregroundColor(Tema.Cor.texto2)
                        .frame(height: Tema.Texto.xl2)
                }
            }
            .padding(.top, Tema.Espaco.item)
            .accessibilityElement(children: .combine)
            Trilho(percentual: uso?.semana ?? 0, cor: barra)
            HStack {
                if let r = UsoLogica.textoRenova(uso?.renova, agora: painel.agora()) {
                    Text(r.texto).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2).help(r.exata)
                }
                Spacer(minLength: 0)
                BotaoUso(texto: "Remover", tipo: .perigo) { painel.remover(conta.id, modelo: modelo) }
                    .focused($focoRemover)
                    .opacity(mostraRemover ? 1 : 0)
                    .animation(Tema.Mov.move, value: mostraRemover)
            }
            .padding(.top, Tema.Espaco.micro)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .superficie()
        .opacity(oculta ? Tema.Uso.opacidadeOculta : 1)
        .onHover { sobre = $0 }
        .contextMenu { Button("Remover") { painel.remover(conta.id, modelo: modelo) } }
    }
}

private struct Trilho: View {
    var percentual: Int
    var cor: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.Cor.superficie2)
                Capsule().fill(cor).frame(width: g.size.width * CGFloat(max(0, min(100, percentual))) / 100)
            }
        }
        .frame(height: Tema.Uso.trilhoAlt)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct CartaoNovaConta: View {
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            VStack(spacing: Tema.Espaco.item) {
                Svg(Icone.maisMac, lado: Tema.Uso.novaIcone).foregroundColor(Tema.Cor.texto2)
                Text("Adicionar conta").tatile(Tema.Texto.sm, .bold, Tema.Cor.texto)
                Text("Claude Code ou Codex").tatile(Tema.Uso.pequeno, .regular, Tema.Cor.texto2)
            }
            .padding(Tema.Espaco.pad)
            .frame(maxWidth: .infinity, minHeight: Tema.Uso.novaAltMin, maxHeight: .infinity)
            .contornoInterno(Tema.Cor.borda, largura: Tema.Uso.novaAnel, raio: Tema.Raio.card)
            .contentShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// O aviso de baixo ("Conta removida", com Desfazer), igual ao `.aviso` do protótipo.
/// "Desfazer" do aviso: azul de destaque, sem folga nas laterais (`.aviso button` do protótipo).
private struct EstiloDesfazer: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Tema.Texto.sm, weight: .semibold))
            .foregroundColor(Tema.Cor.destaque)
            .frame(minHeight: Tema.Espaco.alvoSm)
            .opacity(configuration.isPressed ? Tema.Uso.opacidadeOculta : 1)
            .contentShape(Rectangle())
    }
}

struct AvisoDoUso: View {
    @ObservedObject var painel: PainelUso

    var body: some View {
        if let a = painel.aviso {
            HStack(spacing: Tema.Espaco.icone) {
                Text(a.texto).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto)
                if a.comDesfazer {
                    Button("Desfazer") { painel.desfazerUltimo() }
                        .buttonStyle(EstiloDesfazer())
                }
            }
            .padding(.horizontal, Tema.Espaco.pad)
            .padding(.vertical, Tema.Espaco.icone)
            .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).strokeBorder(Tema.Cor.anelForte, lineWidth: Tema.Uso.filete) }
            .shadow(color: Tema.Sombra.difusaCor, radius: Tema.Sombra.difusaRaio, y: Tema.Sombra.difusaY)
            .fixedSize()
            .accessibilityElement(children: .contain)
        }
    }
}

/// A janela Adicionar conta e o aviso de Desfazer ficam por cima da janela de Ajustes inteira (não só da área que
/// rola), como no protótipo. É camada do próprio SwiftUI: pendurar um NSHostingView dentro do NSHostingView da janela
/// não é suportado e, no macOS 26, o clique em "Adicionar conta" não mostrava nada.
struct CamadaDoUso: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var painel: PainelUso

    var body: some View {
        ZStack(alignment: .bottom) {
            if painel.conta != nil { ContaModal(modelo: modelo, painel: painel) }
            AvisoDoUso(painel: painel).padding(.bottom, Tema.Espaco.pad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
