import SwiftUI

/// A janela "Adicionar conta" (SPEC 9a), igual ao `.modal-j` do protótipo: véu sobre a janela inteira
/// e a caixa no centro. Serviço, "Achei neste Mac" e, embaixo, como somar outra conta.
struct ContaModal: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var painel: PainelUso

    var body: some View {
        ZStack {
            Tema.Cor.veuSis
                .contentShape(Rectangle())
                // Clicar fora fecha, mas com token colado não: a pessoa não perde o que colou.
                .onTapGesture { if painel.conta?.token.isEmpty ?? true { painel.fecharConta() } }
            if painel.conta != nil {
                GeometryReader { g in
                    // A caixa abraça o conteúdo e só rola quando a janela é baixa demais.
                    CaixaQueAbraca(alturaMax: g.size.height - 2 * Tema.Espaco.pad - 2 * Tema.Uso.filete) {
                        ContaCaixa(modelo: modelo, painel: painel)
                    }
                    .padding(Tema.Uso.filete)
                    .background(Tema.Cor.telaFundo)
                    .frame(width: Tema.Medida.modalLarg)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous).strokeBorder(Tema.Cor.molduraBorda, lineWidth: Tema.Uso.filete) }
                    .shadow(color: Tema.Sombra.difusaCor, radius: Tema.Sombra.difusaRaio, y: Tema.Sombra.difusaY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background {
            Button("Fechar") { painel.fecharConta() }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        }
    }
}

/// A caixa abraça o conteúdo e só vira rolagem quando a janela é baixa demais.
/// A altura natural do conteúdo é medida de fato: um ScrollView sozinho ocuparia tudo o que lhe oferecem.
private struct CaixaQueAbraca<Conteudo: View>: View {
    var alturaMax: CGFloat
    @ViewBuilder var conteudo: () -> Conteudo
    @State private var natural: CGFloat = 0

    var body: some View {
        let medido = conteudo().background(GeometryReader { g in Color.clear.preference(key: AlturaNatural.self, value: g.size.height) })
        Group {
            if natural > alturaMax {
                ScrollView { medido }.frame(height: alturaMax)
            } else {
                medido
            }
        }
        .onPreferenceChange(AlturaNatural.self) { if $0 > 0 { natural = $0 } }
    }
}

private struct AlturaNatural: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContaCaixa: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject var painel: PainelUso
    @FocusState private var focoToken: Bool

    var body: some View {
        let c = painel.conta ?? EstadoConta()
        let achadas = painel.achadas.filter { $0.conta.nome == c.servico }
        VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
            Topo { painel.fecharConta() }
            HStack(spacing: Tema.Espaco.item) {
                BotaoServico(nome: "Claude", marcado: c.servico == "Claude") { escolher("Claude") }
                BotaoServico(nome: "Codex", marcado: c.servico == "Codex") { escolher("Codex") }
            }
            if !achadas.isEmpty {
                Bloco(titulo: "Achei neste Mac") {
                    VStack(spacing: 0) {
                        ForEach(Array(achadas.enumerated()), id: \.element.id) { i, a in
                            if i > 0 { Rectangle().fill(Tema.Cor.borda).frame(height: Tema.Uso.filete) }
                            LinhaAchada(achada: a, semana: painel.usos[a.id]?.semana) { painel.somar(a, modelo: modelo) }
                        }
                    }
                }
            }
            if c.servico == "Claude" { passosClaude(c, achadas: !achadas.isEmpty) } else { passosCodex(c, achadas: !achadas.isEmpty) }
            HStack(spacing: Tema.Espaco.item) {
                Spacer(minLength: 0)
                BotaoUso(texto: "Cancelar") { painel.fecharConta() }
                if c.servico == "Claude" {
                    BotaoUso(texto: c.conferindo ? "Conferindo..." : "Adicionar", tipo: .primario,
                             desligado: c.token.isEmpty || c.conferindo) { enviar() }
                }
            }
        }
        .padding(Tema.Espaco.pad)
        // 1 px de borda do protótipo (box-sizing: border-box): o conteúdo mede 2 px a menos.
        .frame(width: Tema.Medida.modalLarg - 2, alignment: .topLeading)
        .background(Tema.Cor.telaFundo)
        .onAppear { DispatchQueue.main.async { if c.servico == "Claude" { focoToken = true } } }
        .onChange(of: painel.conta?.erro ?? "") { e in if !e.isEmpty { focoToken = true } }
    }

    private func escolher(_ s: String) {
        painel.conta?.servico = s
        painel.conta?.erro = ""
    }

    private func enviar() { Task { await painel.adicionarToken(modelo: modelo) } }

    private func ligacao<T>(_ caminho: WritableKeyPath<EstadoConta, T>, padrao: T) -> Binding<T> {
        Binding(get: { painel.conta?[keyPath: caminho] ?? padrao }, set: { painel.conta?[keyPath: caminho] = $0 })
    }

    private func passosClaude(_ c: EstadoConta, achadas: Bool) -> some View {
        let token = Binding<String>(get: { painel.conta?.token ?? "" }, set: { novo in
            // O Terminal quebra o token em linhas: espaço e quebra de linha saem ao colar.
            let limpo = TokenClaude.limpar(novo)
            painel.conta?.token = limpo
            if !(painel.conta?.erro.isEmpty ?? true) { painel.conta?.erro = "" }
        })
        return Bloco(titulo: achadas ? "Ou outra conta" : "Outra conta") {
            VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
                Passo(numero: 1, titulo: "Gere um token no Terminal",
                      ajuda: "Ele abre o navegador. Entre na conta que você quer acompanhar e copie o token que aparece no fim.") {
                    LinhaDeComando(comando: "claude setup-token", modelo: modelo, painel: painel)
                }
                Passo(numero: 2, titulo: "Cole o token aqui",
                      ajuda: "Começa com \(TokenClaude.prefixo). Fica no Chaveiro deste Mac e só serve para ler o uso.", folga: false) {
                    VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                        HStack(spacing: Tema.Espaco.item) {
                            EntradaUso(placeholder: "\(TokenClaude.prefixo)...", texto: token, segredo: !c.mostrarToken, mono: true,
                                       invalido: !c.erro.isEmpty, rotulo: "Token", focoForcado: painel.focoFixo, foco: $focoToken, enviar: enviar)
                            BotaoUso(texto: c.mostrarToken ? "Esconder" : "Mostrar", tipo: .link) {
                                painel.conta?.mostrarToken.toggle()
                                focoToken = true
                            }
                        }
                        // Espaço do erro sempre reservado: o aviso aparece sem empurrar nada.
                        Text(c.erro).paragrafo(Tema.Texto.xs, .regular, Tema.Cor.perigo)
                            .frame(maxWidth: .infinity, minHeight: Tema.Texto.xs * Tema.Uso.alturaTextoPequeno, alignment: .leading)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                Passo(numero: 3, titulo: "Dê um nome", ajuda: "É o que aparece no iPhone.") {
                    EntradaUso(placeholder: "Ex.: Trabalho", texto: ligacao(\.nome, padrao: ""), rotulo: "Nome no iPhone")
                }
            }
        }
    }

    private func passosCodex(_ c: EstadoConta, achadas: Bool) -> some View {
        Bloco(titulo: achadas ? "Ou outra conta" : "Outra conta") {
            VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
                Passo(numero: 1, titulo: "Entre na conta pelo Terminal",
                      ajuda: "Ele abre o navegador para você entrar com a conta do ChatGPT.") {
                    LinhaDeComando(comando: "codex login", modelo: modelo, painel: painel)
                }
                Passo(numero: 2, titulo: "Volte aqui", ajuda: "O Deck acha a conta sozinho quando o login terminar.") {
                    HStack(spacing: Tema.Espaco.item) {
                        if c.esperando {
                            Girando()
                            Text("Esperando o login...").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Tema.Texto.xs * Tema.Uso.alturaTextoPequeno, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Partes

private struct Topo: View {
    var fechar: () -> Void

    var body: some View {
        HStack {
            Text("Adicionar conta")
                .font(.system(size: Tema.Texto.lg, weight: .bold))
                .tracking(Tema.Texto.trackingTitulo(Tema.Texto.lg))
                .foregroundColor(Tema.Cor.texto)
                .frame(height: Tema.Texto.lg * Tema.Texto.alturaTitulo)
            Spacer(minLength: 0)
            Button(action: fechar) {
                Svg(Icone.maisMac, lado: Tema.Uso.fecharIcone).rotationEffect(.degrees(Tema.Uso.fecharGiro))
                    .foregroundColor(Tema.Cor.texto2)
                    .frame(width: Tema.Espaco.alvoSm, height: Tema.Espaco.alvoSm)
                    .background(Tema.Cor.superficie2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar")
        }
    }
}

private struct BotaoServico: View {
    var nome: String
    var marcado: Bool
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.icone) {
                Image(nome == "Claude" ? "IcClaude" : "IcCodex").resizable().interpolation(.high)
                    .frame(width: Tema.Medida.icConta, height: Tema.Medida.icConta)
                Text(nome == "Claude" ? "Claude Code" : "Codex")
                    .font(.system(size: Tema.Texto.sm, weight: .semibold))
                    .foregroundColor(marcado ? Tema.Cor.texto : Tema.Cor.texto2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tema.Espaco.icone)
            .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvo)
            .background(marcado ? Tema.Cor.sucessoSuave : Tema.Cor.superficie, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .contornoInterno(marcado ? Tema.Cor.led : .clear, largura: Tema.Uso.servAnel, raio: Tema.Raio.normal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcado ? .isSelected : [])
    }
}

private struct Bloco<Conteudo: View>: View {
    var titulo: String
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            // h4 do protótipo: altura de linha de título (1.2), não a do texto corrido.
            Text(titulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
                .frame(height: Tema.Texto.xs * Tema.Texto.alturaTitulo)
            conteudo
        }
    }
}

private struct LinhaAchada: View {
    var achada: ContaEncontrada
    var semana: Int?
    var adicionar: () -> Void

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            Image(achada.conta.nome == "Claude" ? "IcClaude" : "IcCodex").resizable().interpolation(.high)
                .frame(width: Tema.Medida.icConta, height: Tema.Medida.icConta)
                .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
            VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                Text("Conta \(achada.conta.conta)").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto)
                Text(semana.map { "\($0)% da semana usado" } ?? "Sem medição ainda").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
            }
            Spacer(minLength: 0)
            BotaoUso(texto: "Adicionar", tipo: .primario, acao: adicionar)
        }
        .padding(.vertical, Tema.Espaco.icone)
        .frame(minHeight: Tema.Espaco.linha)
    }
}

private struct Passo<Conteudo: View>: View {
    var numero: Int
    var titulo: String
    var ajuda: String
    /// O grid do CSS reserva uma terceira linha (o número ocupa 3) e o espaço entre linhas fica como folga
    /// embaixo do passo. O passo do token tem três linhas de verdade e não tem essa folga.
    var folga = true
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espaco.icone) {
            Text("\(numero)").font(.system(size: Tema.Texto.xs, weight: .bold)).monospacedDigit().foregroundColor(Tema.Cor.texto2)
                .frame(width: Tema.Medida.selo, height: Tema.Medida.selo)
                .background(Tema.Cor.superficie2, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                    Text(titulo).tatile(Tema.Texto.sm, .bold, Tema.Cor.texto)
                    Text(ajuda).paragrafo(Tema.Texto.xs, .regular, Tema.Cor.texto2, altura: Tema.Uso.alturaTextoPequeno)
                        .frame(minHeight: Tema.Texto.xs * Tema.Uso.alturaAjuda, alignment: .topLeading)
                }
                conteudo
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, folga ? Tema.Espaco.item : 0)
    }
}

private struct LinhaDeComando: View {
    var comando: String
    var modelo: ModeloApp
    var painel: PainelUso

    var body: some View {
        HStack(spacing: Tema.Espaco.item) {
            Text(comando).font(.system(size: Tema.Uso.mono, design: .monospaced)).foregroundColor(Tema.Cor.texto)
                .padding(.horizontal, Tema.Espaco.icone)
                .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm, alignment: .leading)
                .background(Tema.Cor.superficie, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
                .textSelection(.enabled)
            BotaoUso(texto: "Copiar") { painel.copiar(comando) }
            BotaoUso(texto: "Abrir no Terminal") { painel.abrirNoTerminal(comando, modelo: modelo) }
        }
    }
}
