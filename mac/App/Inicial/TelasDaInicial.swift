import SwiftUI
import AppKit

// Uma View por passo, na ordem do protótipo (mac.js, TELAS_INI).

private let corpoLarg = Tema.Inicial.corpoLarg

private struct Titulo: View {
    var texto: String
    var tamanho = Tema.Texto.xl

    var body: some View {
        TextoBalanceado(texto: texto, tamanho: tamanho, peso: .bold, altura: Tema.Texto.alturaTitulo,
                        tracking: Tema.Texto.trackingTitulo(tamanho))
    }
}

private struct Prosa: View {
    var texto: String
    var ch: CGFloat = Tema.Inicial.paragrafoCh

    var body: some View {
        TextoBalanceado(texto: texto, tamanho: Tema.Texto.sm, cor: Tema.Cor.texto2,
                        larguraMax: min(corpoLarg, MedirTexto.ch(ch, tamanho: Tema.Texto.sm)))
    }
}

// MARK: 1. Boas-vindas

struct TelaBoasVindas: View {
    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Logo(lado: Tema.Medida.logoGrande)
                .shadow(color: Tema.Cor.sucessoSuave, radius: Tema.Inicial.logoSombraRaio, y: Tema.Inicial.logoSombraY)
            Titulo(texto: "Seu iPhone vira um painel do Mac", tamanho: Tema.Texto.xl2).padding(.top, Tema.Espaco.item)
            Prosa(texto: "Relógio, música, agenda, mensagens e teclas que controlam o Mac, numa tela só ao lado do teclado. Leva uns dois minutos.",
                  ch: Tema.Inicial.apresentacaoCh)
        }
    }
}

// MARK: 2. Conecte o iPhone

struct TelaIphone: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Titulo(texto: "Conecte o iPhone")
            Prosa(texto: "Os dois precisam estar no mesmo Wi-Fi. Nada sai da sua rede.")
            CartaoDePareamento(assistente: assistente)
            PassosDoPareamento()
        }
    }
}

private struct CartaoDePareamento: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espaco.pad) {
            QrDoPareamento(endereco: assistente.textoDoQr)
            VStack(alignment: .center, spacing: Tema.Espaco.pad) {
                Campo(rotulo: "Código") {
                    VStack(alignment: .center, spacing: Tema.Espaco.item) {
                        Text(assistente.codigoEmGrupos)
                            .font(.system(size: Tema.Medida.codigoTam, weight: .bold).monospacedDigit())
                            .tracking(Tema.Medida.codigoTam * Tema.Inicial.codigoSpacing)
                            .foregroundColor(Tema.Cor.texto)
                            .frame(height: Tema.Medida.codigoTam)
                            .lineLimit(1)
                        Text("vale por 10 minutos").tatile(Tema.Inicial.legendaCodigo, .regular, Tema.Cor.texto2)
                    }
                }
                Campo(rotulo: "Ou abra no Safari do iPhone") {
                    HStack(spacing: Tema.Espaco.item) {
                        // O CSS pede `ui-monospace`. A SF Mono é uns 3% mais larga e estica o cartão, então o app usa a
                        // Menlo, que mede o mesmo que a fonte do protótipo aprovado (ver Tema.Inicial.fonteDeCodigo).
                        Text(assistente.endereco)
                            .font(.custom(Tema.Inicial.fonteDeCodigo, size: Tema.Inicial.enderecoTexto))
                            .foregroundColor(Tema.Cor.texto).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        BotaoDaInicial(texto: "Copiar", estilo: .secundario, compacto: true, codigo: true, acao: assistente.copiarEndereco)
                    }
                    .padding(.horizontal, Tema.Espaco.icone)
                    .padding(.vertical, Tema.Espaco.item)
                    .frame(maxWidth: .infinity)
                    .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
                }
                EsperandoOIphone(assistente: assistente).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Tema.Espaco.pad)
        .fixedSize()
        .superficie()
    }
}

private struct Campo<Conteudo: View>: View {
    var rotulo: String
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .center, spacing: Tema.Espaco.item) {
            Text(rotulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            conteudo
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QrDoPareamento: View {
    var endereco: String

    var body: some View {
        Group {
            if let img = DesenhoDoQr.imagem(endereco) {
                Image(nsImage: img).interpolation(.none).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(Tema.Espaco.item)
        .frame(width: Tema.Medida.qr, height: Tema.Medida.qr)
        .background(Tema.Cor.branco, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
        .accessibilityLabel("QR code de pareamento")
    }
}

/// "Esperando o iPhone..." com o círculo girando, ou "<nome> conectado" em verde (mac.css, .esperando).
private struct EsperandoOIphone: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        HStack(spacing: Tema.Espaco.item) {
            if let iphone = assistente.iphone {
                Svg(Icone.ok, lado: Tema.Inicial.esperandoIcone)
                Text("\(iphone.nome) conectado").tatile(Tema.Texto.xs, .regular, Tema.Cor.led)
            } else {
                GirandoDaInicial()
                Text("Esperando o iPhone...").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
            }
        }
        .foregroundColor(assistente.iphone == nil ? Tema.Cor.texto2 : Tema.Cor.led)
        .frame(minHeight: Tema.Inicial.esperandoAlt, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct GirandoDaInicial: View {
    @State private var angulo = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduzir

    var body: some View {
        ZStack {
            Circle().strokeBorder(Tema.Cor.borda, lineWidth: Tema.Inicial.girandoLinha)
            Circle().inset(by: Tema.Inicial.girandoLinha / 2).trim(from: Tema.Inicial.girandoDe, to: Tema.Inicial.girandoAte)
                .stroke(Tema.Cor.texto, lineWidth: Tema.Inicial.girandoLinha)
        }
        .frame(width: Tema.Inicial.girando, height: Tema.Inicial.girando)
        .rotationEffect(.degrees(angulo))
        .opacity(reduzir ? Tema.Inicial.girandoReduzido : 1)
        .onAppear {
            guard !reduzir else { return }
            withAnimation(.linear(duration: Tema.Inicial.girandoVolta).repeatForever(autoreverses: false)) { angulo = 360 }
        }
        .accessibilityHidden(true)
    }
}

private struct PassosDoPareamento: View {
    private static let passos: [Text] = [
        Text("No iPhone, aponte a ") + Text("câmera").foregroundColor(Tema.Cor.texto) .bold() + Text(" para o código e toque no link."),
        Text("Instale o ") + Text("certificado").foregroundColor(Tema.Cor.texto).bold()
            + Text(" e ligue a confiança em Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados."),
        Text("No Safari, ") + Text("Compartilhar > Adicionar à Tela de Início").foregroundColor(Tema.Cor.texto).bold()
            + Text(". O Deck abre como app."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            ForEach(Array(Self.passos.enumerated()), id: \.offset) { i, texto in
                HStack(alignment: .top, spacing: Tema.Espaco.icone) {
                    Text("\(i + 1)").font(.system(size: Tema.Texto.xs).monospacedDigit()).foregroundColor(Tema.Cor.texto)
                        .frame(width: Tema.Inicial.passoNumero, height: Tema.Inicial.passoNumero)
                        .background(Tema.Cor.superficie2, in: Circle())
                    texto.font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                        .lineSpacing(Tema.Texto.sm * Tema.Texto.altura - MedirTexto.alturaNatural(MedirTexto.fonte(Tema.Texto.sm, .regular)))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tema.Espaco.fino)
                }
            }
        }
        .frame(maxWidth: corpoLarg, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, Tema.Espaco.item)
    }
}

// MARK: 3. Como o iPhone fica

struct TelaLayout: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Titulo(texto: "Como o iPhone fica")
            Prosa(texto: "O Deck mostra sozinho o que você tem no Mac: Spotify, agenda, WhatsApp, sessões e uso das IAs. Escolha só o jeito.")
            HStack(spacing: Tema.Espaco.grade) {
                ForEach(["a", "b"], id: \.self) { c in
                    ComposicaoEscolhivel(comp: c, marcada: assistente.comp == c) { assistente.comp = c }
                }
            }
            .frame(width: corpoLarg)
        }
    }
}

private struct ComposicaoEscolhivel: View {
    var comp: String
    var marcada: Bool
    var escolher: () -> Void

    private var titulo: String { comp == "a" ? "Relógio em cima" : "Deck 3 x 3" }
    private var legenda: String {
        comp == "a" ? "Relógio e player em cima, teclas numa fileira embaixo" : "Informações à esquerda, teclas grandes em grade à direita"
    }
    private var descricao: String {
        comp == "a" ? "Prévia do iPhone deitado: relógio e player em cima, teclas numa fileira embaixo"
                    : "Prévia do iPhone deitado: relógio, uso, player e sessões à esquerda, teclas em grade à direita"
    }

    var body: some View {
        let larg = (corpoLarg - Tema.Espaco.grade) / 2 - Tema.Espaco.icone * 2
        Button(action: escolher) {
            VStack(spacing: Tema.Espaco.mini) {
                ImagemDaInicial.ler("inicial-comp-\(comp)").resizable().interpolation(.high)
                    .aspectRatio(Tema.Inicial.comporRazao, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                    .padding(.bottom, Tema.Espaco.mini)
                    .accessibilityLabel(descricao)
                Text(titulo).tatile(Tema.Texto.sm, .bold)
                TextoBalanceado(texto: legenda, tamanho: Tema.Texto.xs, cor: Tema.Cor.texto2, larguraMax: larg)
            }
            .padding(Tema.Espaco.icone)
            .frame(maxWidth: .infinity)
            .background(marcada ? Tema.Cor.sucessoSuave : Tema.Cor.superficie, in: RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
            .contornoInterno(marcada ? Tema.Cor.led : .clear, largura: Tema.Inicial.contornoMarcado, raio: Tema.Raio.card)
            .shadow(color: marcada ? Tema.Cor.led.opacity(Tema.Inicial.brilhoOpacidade) : .clear, radius: Tema.Inicial.brilhoComp)
            .background { if !marcada { RoundedRectangle(cornerRadius: Tema.Raio.card + 1, style: .continuous).fill(Tema.Cor.anel).padding(-1) } }
            .contentShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }
}

// MARK: Peças de marcar (contas e teclas)

/// A bolinha de marcado: cinza vazia, verde com o visto quando marcada (mac.css, .marca).
private struct Marca: View {
    var marcada: Bool

    var body: some View {
        ZStack {
            Circle().fill(marcada ? Tema.Cor.led : Tema.Cor.superficie2)
            if marcada { Svg(Icone.ok, lado: Tema.Inicial.marcaIcone).foregroundColor(Tema.Cor.fundo) }
        }
        .frame(width: Tema.Medida.selo, height: Tema.Medida.selo)
        .accessibilityHidden(true)
    }
}

/// O fundo de uma peça marcável: cartão, ou verde suave com o contorno verde quando marcada.
private extension View {
    func cartaoMarcavel(marcada: Bool, suave: Bool = false, raio: CGFloat = Tema.Raio.card) -> some View {
        background {
            ZStack {
                if !marcada { RoundedRectangle(cornerRadius: raio + 1, style: .continuous).fill(Tema.Cor.anel).padding(-1) }
                RoundedRectangle(cornerRadius: raio, style: .continuous).fill(marcada || suave ? Tema.Cor.sucessoSuave : Tema.Cor.superficie)
            }
        }
        .contornoInterno(marcada ? Tema.Cor.led : .clear, largura: Tema.Inicial.contornoMarcado, raio: raio)
        .contentShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
    }
}

// MARK: 4. Suas contas de IA

struct TelaContas: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Titulo(texto: "Suas contas de IA")
            Prosa(texto: assistente.achadas.isEmpty
                  ? "Conecte o Claude Code ou o Codex para ver o uso da semana no iPhone."
                  : "Achamos estas neste Mac. Marque as que quer ver no iPhone ou conecte outra.")
            let colunas = [GridItem(.flexible(), spacing: Tema.Espaco.item), GridItem(.flexible(), spacing: Tema.Espaco.item)]
            LazyVGrid(columns: colunas, spacing: Tema.Espaco.item) {
                ForEach(assistente.achadas) { a in
                    EscolhaDeConta(conta: a, marcada: assistente.contasMarcadas.contains(a.id)) { assistente.alternarConta(a.id) }
                }
                EscolhaConectar { assistente.conectarOutraConta() }
            }
            .frame(width: corpoLarg)
        }
    }
}

private struct EscolhaDeConta: View {
    var conta: ContaAchada
    var marcada: Bool
    var alternar: () -> Void

    var body: some View {
        Button(action: alternar) {
            HStack(spacing: Tema.Espaco.icone) {
                ImagemDaInicial.ler(conta.servico == "Claude" ? "inicial-claude" : "inicial-codex").resizable().interpolation(.high)
                    .frame(width: Tema.Medida.logo, height: Tema.Medida.logo)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                    Text(conta.titulo).tatile(Tema.Texto.sm, .bold)
                    Text(conta.detalhe()).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                }
                Spacer(minLength: 0)
                Marca(marcada: marcada)
            }
            .padding(Tema.Espaco.icone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cartaoMarcavel(marcada: marcada)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }
}

private struct EscolhaConectar: View {
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.icone) {
                Svg(Icone.maisMac, lado: Tema.Inicial.conectarIcone).foregroundColor(Tema.Cor.texto2)
                    .frame(width: Tema.Medida.logo)
                VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                    Text("Conectar outra conta").tatile(Tema.Texto.sm, .bold)
                    Text("Claude Code ou Codex").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                }
                Spacer(minLength: 0)
            }
            .padding(Tema.Espaco.icone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contornoInterno(Tema.Cor.borda, largura: Tema.Inicial.contornoPontilhado, raio: Tema.Raio.card)
            .contentShape(RoundedRectangle(cornerRadius: Tema.Raio.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: 5. Primeiras teclas

struct TelaTeclas: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Titulo(texto: "Primeiras teclas")
            Prosa(texto: "Escolha algumas para começar. Depois você cria as suas: app, atalho, combinação de teclas ou comando.")
            // 5 por linha, ocupando a largura.
            let colunas = Array(repeating: GridItem(.flexible(), spacing: Tema.Espaco.icone), count: 5)
            LazyVGrid(columns: colunas, spacing: Tema.Espaco.icone) {
                ForEach(assistente.sugestoes) { s in
                    TeclaSugerida(sugestao: s, marcada: assistente.teclasMarcadas.contains(s.id)) { assistente.alternarTecla(s.id) }
                }
            }
            .frame(width: corpoLarg)
        }
    }
}

private struct TeclaSugerida: View {
    var sugestao: SugestaoDeTecla
    var marcada: Bool
    var alternar: () -> Void

    var body: some View {
        Button(action: alternar) {
            VStack(spacing: Tema.Espaco.item) {
                IconeDaSugestao(icone: sugestao.icone)
                Text(sugestao.nome).font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2).lineLimit(1)
                    .frame(height: Tema.Texto.sm * Tema.Texto.alturaTitulo)
            }
            .padding(.init(top: Tema.Espaco.icone, leading: Tema.Espaco.item, bottom: Tema.Espaco.pad, trailing: Tema.Espaco.item))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) { Marca(marcada: marcada).padding(Tema.Espaco.item) }
            .cartaoMarcavel(marcada: marcada)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sugestao.nome)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }
}

private struct IconeDaSugestao: View {
    var icone: String

    private static let imagens = ["Spotify": "inicial-spotify", "WhatsApp": "inicial-whatsapp", "Calendar": "inicial-calendario",
                                  "Safari": "inicial-safari", "Notes": "inicial-notas", "Terminal": "inicial-terminal", "Finder": "inicial-finder"]

    var body: some View {
        Group {
            if icone == "svg:tela" {
                Svg(Icone.tela, lado: Tema.Inicial.iconeDoTipo).foregroundColor(Tema.Cor.texto)
                    .frame(width: Tema.Medida.appBusca, height: Tema.Medida.appBusca)
                    .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
            } else if let nome = Self.imagens[icone] {
                ImagemDaInicial.ler(nome).resizable().interpolation(.high)
                    .frame(width: Tema.Medida.appBusca, height: Tema.Medida.appBusca)
                    .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
            } else {
                Svg(Icone.raio, lado: Tema.Inicial.iconeDoTipo).foregroundColor(Tema.Cor.texto)
                    .frame(width: Tema.Medida.appBusca, height: Tema.Medida.appBusca)
                    .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: 6. Libere os acessos

struct TelaAcessos: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Titulo(texto: "Libere os acessos")
            Prosa(texto: "O macOS pergunta uma vez cada um. Sem eles, só a parte que depende deles fica de fora. Dá para liberar depois em Ajustes.")
            VStack(spacing: Tema.Espaco.item) {
                ForEach(OrdemDosAcessos.todos) { a in LinhaDeAcesso(assistente: assistente, acesso: a) }
            }
            .frame(width: corpoLarg)
        }
    }
}

private struct LinhaDeAcesso: View {
    @ObservedObject var assistente: AssistenteInicial
    var acesso: AcessoMac

    var body: some View {
        let estado = assistente.estado(acesso)
        HStack(spacing: Tema.Espaco.pad) {
            VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                Text(acesso.nome).tatile(Tema.Texto.sm, .bold)
                Text(acesso.para).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
            }
            Spacer(minLength: 0)
            switch estado {
            case .liberado:
                HStack(spacing: Tema.Espaco.mini) {
                    Svg(Icone.ok, lado: Tema.Inicial.liberadoIcone)
                    Text("Liberado").tatile(Tema.Texto.sm, .semibold, Tema.Cor.led)
                }
                .foregroundColor(Tema.Cor.led)
                .frame(minHeight: Tema.Espaco.alvoSm)
            case .recusado:
                BotaoDaInicial(texto: "Abrir Ajustes do Sistema", estilo: .secundario, compacto: true) { assistente.abrirAjustesDoSistema(acesso) }
            case .naoPedido:
                BotaoDaInicial(texto: "Permitir", estilo: .primario, compacto: true) { Task { await assistente.permitir(acesso) } }
            }
        }
        .padding(.horizontal, Tema.Espaco.pad)
        .padding(.vertical, Tema.Espaco.icone)
        .frame(maxWidth: .infinity, minHeight: Tema.Inicial.linhaAcessoAlt, alignment: .leading)
        .cartaoMarcavel(marcada: false, suave: estado == .liberado)
    }
}

// MARK: 7. Pronto

struct TelaPronto: View {
    @ObservedObject var assistente: AssistenteInicial

    var body: some View {
        VStack(spacing: Tema.Espaco.pad) {
            Svg(Icone.ok, lado: Tema.Inicial.feitoIcone).foregroundColor(Tema.Cor.fundo)
                .frame(width: Tema.Inicial.feito, height: Tema.Inicial.feito)
                .background(Tema.Cor.led, in: Circle())
                .shadow(color: Tema.Cor.led.opacity(Tema.Inicial.brilhoOpacidade), radius: Tema.Inicial.feitoBrilho)
            Titulo(texto: "Pronto, o Deck está no ar", tamanho: Tema.Texto.xl2).padding(.top, Tema.Espaco.item)
            Prosa(texto: "Ele mora no ícone da barra de menus. " + (assistente.iphoneConectado
                  ? "O que você escolheu já está no iPhone."
                  : "Conecte o iPhone quando quiser em Ajustes, Conectar iPhone."),
                  ch: Tema.Inicial.apresentacaoCh)
        }
    }
}
