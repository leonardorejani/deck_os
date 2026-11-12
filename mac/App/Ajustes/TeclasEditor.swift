import SwiftUI
import AppKit
import CoreText

/// O editor da tecla escolhida, na largura toda (prototipo/mac.js, editorMac): em cima a prévia, o nome
/// e "Excluir tecla", embaixo os dois passos (o que a tecla faz e a configuração do tipo).
struct EditorDeTecla: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    var body: some View {
        let tipo = TipoDeTecla.de(tecla.tipo)
        VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
            topo(tipo)
            passo1(tipo)
            passo2(tipo)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .superficie()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editar \(tecla.nome)")
    }

    // MARK: Topo

    private func topo(_ tipo: TipoDeTecla) -> some View {
        HStack(spacing: Tema.Espaco.pad) {
            TeclaMac(tecla: tecla, catalogo: tela.catalogo, acesa: tela.acesas.contains(tecla.id), previa: true)
            VStack(alignment: .leading, spacing: Tema.Espaco.micro) {
                CampoDeLinha(dica: "Nome da tecla", texto: Binding(get: { tecla.nome }, set: { tela.renomear($0) }), pedidoDeFoco: tela.pedidoDeFocoNoNome)
                    .textFieldStyle(.plain)
                    .font(.system(size: Tema.Texto.lg, weight: .bold))
                    .tracking(Tema.Texto.trackingTitulo(Tema.Texto.lg))
                    .foregroundColor(Tema.Cor.texto)
                    .padding(.horizontal, Tema.Espaco.item)
                    .frame(minHeight: Tema.Medida.tituloAlt)
                    .padding(.leading, -Tema.Espaco.item + Tema.Espaco.fino / 2)
                    .accessibilityLabel("Nome da tecla")
                Text("\(tipo.diz). O nome é o que aparece no iPhone")
                    .font(.system(size: Tema.Texto.pequeno)).foregroundColor(Tema.Cor.texto2).lineLimit(1)
                    .frame(height: Tema.Texto.pequeno * Tema.Texto.altura)
                    .padding(.leading, Tema.Espaco.fino)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Excluir tecla", action: tela.excluirTecla).buttonStyle(EstiloDoBotao(tipo: .perigo))
        }
        .padding(.bottom, Tema.Espaco.pad)
        .overlay(alignment: .bottom) { Rectangle().fill(Tema.Cor.borda).frame(height: Tema.Traco.fino) }
    }

    // MARK: Passo 1

    private func titulo(_ n: Int, _ texto: String) -> some View {
        HStack(spacing: Tema.Espaco.item) {
            Text("\(n)").font(.system(size: Tema.Texto.xs, weight: .regular)).monospacedDigit().foregroundColor(Tema.Cor.texto2)
                .frame(width: Tema.Medida.selo, height: Tema.Medida.selo)
                .background(Tema.Cor.superficie2, in: Circle())
            Text(texto).titulinho(Tema.Texto.sm, .bold, Tema.Cor.texto)
        }
        .accessibilityElement(children: .combine)
    }

    private func passo1(_ tipo: TipoDeTecla) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            titulo(1, "O que a tecla faz")
            HStack(spacing: Tema.Espaco.item) {
                ForEach(TipoDeTecla.allCases) { t in
                    CartaoDeTipo(tipo: t, escolhido: t == tipo) { tela.escolherTipo(t) }
                }
            }
        }
    }

    // MARK: Passo 2

    private func passo2(_ tipo: TipoDeTecla) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            titulo(2, tipo.tituloDoPasso)
            switch tipo {
            case .app: PassoApp(tela: tela, tecla: tecla)
            case .atalho: PassoAtalho(tela: tela, tecla: tecla)
            case .tecla: PassoTeclado(tela: tela, tecla: tecla)
            case .comando: PassoComando(tela: tela, tecla: tecla)
            }
            if tipo != .app { EscolhaDeIcone(tela: tela, tecla: tecla) }
        }
    }
}

private struct CartaoDeTipo: View {
    var tipo: TipoDeTecla
    var escolhido: Bool
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous)
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.icone) {
                Svg(IconesDeTecla.doTipo(tipo), lado: Tema.Glifo.tipo)
                    .foregroundColor(escolhido ? Tema.Cor.led : Tema.Cor.texto)
                    .frame(width: Tema.Medida.icTipo, height: Tema.Medida.icTipo)
                    .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                    Text(tipo.nome).tatile(Tema.Texto.sm, .bold, Tema.Cor.texto)
                    Text(tipo.diz).font(.system(size: Tema.Texto.xs)).foregroundColor(Tema.Cor.texto2).lineLimit(1)
                        .frame(height: Tema.Texto.xs * Tema.Texto.alturaTipo)
                }
                Spacer(minLength: 0)
            }
            .padding(Tema.Espaco.icone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(forma.fill(escolhido ? Tema.Cor.sucessoSuave : (sobre ? Tema.Cor.superficie2 : Tema.Cor.telaFundo)))
            .overlay { if escolhido { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.forte) } }
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .accessibilityAddTraits(escolhido ? .isSelected : [])
    }
}

// MARK: - Busca (App e Atalho)

private struct CampoDeBusca: View {
    @Binding var texto: String
    var dica: String

    var body: some View {
        HStack(spacing: Tema.Espaco.item) {
            Svg(IconesDeTecla.busca, lado: Tema.Glifo.busca).foregroundColor(Tema.Cor.texto2)
            CampoDeLinha(dica: dica, texto: $texto)
                .textFieldStyle(.plain)
                .padding(.leading, Tema.Medida.recuoDoInput)
                .font(.system(size: Tema.Texto.sm))
                .foregroundColor(Tema.Cor.texto)
                .accessibilityLabel(dica)
        }
        .padding(.horizontal, Tema.Espaco.icone)
        .padding(.leading, Tema.Medida.bordaDoCampo)
        .frame(minHeight: Tema.Medida.busca)
        .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.fino) }
    }
}

/// Cresce até 300 e passa a rolar (o max-height do protótipo). `altura` é a conta do conteúdo: o ImageRenderer
/// não mede conteúdo que rola, então a altura vem das medidas dos itens, não de leitura da tela.
private struct ListaQueRola<C: View>: View {
    var altura: CGFloat
    @ViewBuilder var conteudo: C
    @Environment(\.fotografando) private var foto

    var body: some View {
        if altura > Tema.Medida.listaMax && foto {
            conteudo.padding(.trailing, Tema.Espaco.micro).frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: Tema.Medida.listaMax, alignment: .top).clipped()
        } else if altura > Tema.Medida.listaMax {
            ScrollView { conteudo.padding(.trailing, Tema.Espaco.micro).frame(maxWidth: .infinity, alignment: .topLeading) }
                .frame(height: Tema.Medida.listaMax)
        } else {
            conteudo.padding(.trailing, Tema.Espaco.micro).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// Grade com as linhas já montadas (sem LazyVGrid, que o ImageRenderer das fotos não desenha).
private struct GradeDeLinhas<Item: Identifiable, Celula: View>: View {
    var itens: [Item]
    var colunas: Int
    @ViewBuilder var celula: (Item) -> Celula

    var body: some View {
        VStack(spacing: Tema.Espaco.micro) {
            ForEach(Array(stride(from: 0, to: itens.count, by: colunas)), id: \.self) { i in
                HStack(spacing: Tema.Espaco.micro) {
                    ForEach(0..<colunas, id: \.self) { k in
                        if i + k < itens.count { celula(itens[i + k]).frame(maxWidth: .infinity) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                    }
                }
            }
        }
    }
}

/// Medidas dos itens das listas de busca (mac.css: .grade-apps, .lista-atalhos, .lista-busca h5).
private enum MedidasDaBusca {
    static let celulaDeApp = Tema.Medida.appBusca + Tema.Espaco.mini + Tema.Texto.xs * Tema.Texto.altura + 2 * Tema.Espaco.item
    static let linhaDeAtalho = Tema.Medida.busca
    static let titulinho = Tema.Texto.xs * Tema.Texto.altura + Tema.Espaco.micro

    static func grade(itens: Int, colunas: Int, linha: CGFloat) -> CGFloat {
        guard itens > 0 else { return 0 }
        let linhas = CGFloat((itens + colunas - 1) / colunas)
        return linhas * linha + (linhas - 1) * Tema.Espaco.micro
    }
}

/// Largura do texto dentro do editor (a janela tem tamanho fixo).
private let larguraDoTextoDoEditor = Tema.Medida.janelaLarg - 2 - Tema.Medida.lateral - 2 * Tema.Espaco.margem - 2 * Tema.Espaco.pad

/// Quebra de linha gulosa, como a do navegador. O Text do SwiftUI equilibra as linhas e deixava "aqui"
/// na linha de baixo, o que o protótipo não faz.
private func linhasGulosas(_ texto: String, largura: CGFloat) -> [String] {
    let atributos = NSAttributedString(string: texto, attributes: [.font: NSFont.systemFont(ofSize: Tema.Texto.xs)])
    let tipografo = CTTypesetterCreateWithAttributedString(atributos)
    let total = (texto as NSString).length
    var linhas: [String] = []
    var inicio = 0
    while inicio < total {
        let n = max(1, CTTypesetterSuggestLineBreak(tipografo, inicio, Double(largura)))
        linhas.append((texto as NSString).substring(with: NSRange(location: inicio, length: n)).trimmingCharacters(in: .whitespaces))
        inicio += n
    }
    return linhas
}

private func ajuda(_ texto: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(linhasGulosas(texto, largura: larguraDoTextoDoEditor).enumerated()), id: \.offset) { _, linha in
            Text(linha).font(.system(size: Tema.Texto.xs)).foregroundColor(Tema.Cor.texto2)
                .lineLimit(1).fixedSize()
                .frame(height: Tema.Texto.xs * Tema.Texto.altura, alignment: .leading)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(texto)
}

private struct GradeDeApps: View {
    var apps: [AppDoMac]
    var valor: String
    var escolher: (AppDoMac) -> Void

    /// A janela tem tamanho fixo: quantas colunas de 100 cabem na lista (auto-fill do protótipo).
    static var colunas: Int {
        let largura = larguraDoTextoDoEditor - Tema.Espaco.micro
        return max(1, Int((largura + Tema.Espaco.micro) / (Tema.Medida.appBuscaCol + Tema.Espaco.micro)))
    }

    var body: some View {
        GradeDeLinhas(itens: apps, colunas: Self.colunas) { a in
            CelulaDeApp(app: a, escolhido: a.valor == valor) { escolher(a) }
        }
    }
}

private struct CelulaDeApp: View {
    var app: AppDoMac
    var escolhido: Bool
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous)
        Button(action: acao) {
            VStack(spacing: Tema.Espaco.mini) {
                if let c = app.caminhoDoIcone {
                    Image(nsImage: IconesDeApps.imagem(c)).resizable().interpolation(.high)
                        .frame(width: Tema.Medida.appBusca, height: Tema.Medida.appBusca)
                        .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
                } else {
                    Text(String(app.nome.prefix(1)).uppercased()).font(.system(size: Tema.Texto.lg)).foregroundColor(Tema.Cor.texto2)
                        .frame(width: Tema.Medida.appBusca, height: Tema.Medida.appBusca)
                        .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icone, style: .continuous))
                }
                Text(app.nome).tatile(Tema.Texto.xs, .regular, escolhido || sobre ? Tema.Cor.texto : Tema.Cor.texto2)
            }
            .padding(.horizontal, Tema.Espaco.micro)
            .padding(.vertical, Tema.Espaco.item)
            .frame(maxWidth: .infinity)
            .background(forma.fill(escolhido ? Tema.Cor.sucessoSuave : (sobre ? Tema.Cor.superficie2 : .clear)))
            .overlay { if escolhido { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.medio) } }
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .accessibilityLabel(app.nome)
        .accessibilityAddTraits(escolhido ? .isSelected : [])
    }
}

private struct PassoApp: View {
    @ObservedObject var tela: ModeloTeclas
    @ObservedObject private var catalogo: CatalogoDeApps
    var tecla: Tecla

    init(tela: ModeloTeclas, tecla: Tecla) { self.tela = tela; self.catalogo = tela.catalogo; self.tecla = tecla }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            CampoDeBusca(texto: $tela.busca, dica: "Buscar entre \(catalogo.apps.count) apps")
            ListaQueRola(altura: alturaDaLista) { lista }
            ajuda(#"WhatsApp e Calendário abrem a lista no próprio iPhone, com "Abrir no Mac" dentro."#)
        }
    }

    @ViewBuilder private var lista: some View {
        let achados = LogicaTeclas.filtrar(catalogo.apps, busca: tela.busca) { $0.nome }
        if tela.busca.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                titulinho("Mais usados").padding(.top, Tema.Espaco.micro)
                GradeDeApps(apps: catalogo.maisUsados, valor: tecla.valor, escolher: tela.escolherApp)
                titulinho("Todos, de A a Z").padding(.top, Tema.Espaco.micro)
                GradeDeApps(apps: catalogo.apps.filter { a in !catalogo.maisUsados.contains(a) }, valor: tecla.valor, escolher: tela.escolherApp)
            }
        } else if achados.isEmpty {
            Text(#"Nenhum app com "\#(tela.busca)" na pasta Aplicativos."#)
                .font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                .padding(.vertical, Tema.Espaco.pad)
        } else {
            GradeDeApps(apps: achados, valor: tecla.valor, escolher: tela.escolherApp)
        }
    }

    private func titulinho(_ t: String) -> some View { Text(t).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2) }

    private var alturaDaLista: CGFloat {
        let col = GradeDeApps.colunas, h = MedidasDaBusca.celulaDeApp
        if tela.busca.trimmingCharacters(in: .whitespaces).isEmpty {
            let resto = catalogo.apps.filter { a in !catalogo.maisUsados.contains(a) }.count
            return 2 * MedidasDaBusca.titulinho + 4 * Tema.Espaco.item + MedidasDaBusca.grade(itens: catalogo.maisUsados.count, colunas: col, linha: h)
                + MedidasDaBusca.grade(itens: resto, colunas: col, linha: h)
        }
        return MedidasDaBusca.grade(itens: LogicaTeclas.filtrar(catalogo.apps, busca: tela.busca) { $0.nome }.count, colunas: col, linha: h)
    }
}

private struct PassoAtalho: View {
    @ObservedObject var tela: ModeloTeclas
    @ObservedObject private var catalogo: CatalogoDeApps
    var tecla: Tecla

    init(tela: ModeloTeclas, tecla: Tecla) { self.tela = tela; self.catalogo = tela.catalogo; self.tecla = tecla }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            CampoDeBusca(texto: $tela.busca, dica: "Buscar atalho")
            ListaQueRola(altura: alturaDaLista) { lista }
            ajuda("São as automações que você monta no app Atalhos da Apple (ícone de raio no Mac). Criou uma nova lá, ela aparece aqui sozinha.")
        }
    }

    private var alturaDaLista: CGFloat {
        MedidasDaBusca.grade(itens: LogicaTeclas.filtrar(catalogo.atalhos ?? [], busca: tela.busca) { $0 }.count, colunas: 2, linha: MedidasDaBusca.linhaDeAtalho)
    }

    @ViewBuilder private var lista: some View {
        if let todos = catalogo.atalhos {
            let achados = LogicaTeclas.filtrar(todos, busca: tela.busca) { $0 }
            if todos.isEmpty {
                Text("Você ainda não tem atalhos no app Atalhos.").font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                    .padding(.vertical, Tema.Espaco.pad)
            } else if achados.isEmpty {
                Text(#"Nenhum atalho com "\#(tela.busca)"."#).font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                    .padding(.vertical, Tema.Espaco.pad)
            } else {
                GradeDeLinhas(itens: achados.map(NomeDeAtalho.init), colunas: 2) { n in
                    LinhaDeAtalho(nome: n.id, escolhido: n.id == tecla.valor) { tela.escolherAtalho(n.id) }
                }
            }
        } else {
            Text("Procurando seus Atalhos...").font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                .padding(.vertical, Tema.Espaco.pad)
        }
    }
}

private struct NomeDeAtalho: Identifiable { var id: String }

private struct LinhaDeAtalho: View {
    var nome: String
    var escolhido: Bool
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous)
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.item) {
                Svg(Icone.raio, lado: Tema.Glifo.atalho).foregroundColor(Tema.Cor.texto2)
                Text(nome).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tema.Espaco.icone)
            .frame(maxWidth: .infinity, minHeight: Tema.Medida.busca, alignment: .leading)
            .background(forma.fill(escolhido ? Tema.Cor.sucessoSuave : (sobre ? Tema.Cor.superficie2 : Tema.Cor.telaFundo)))
            .overlay { if escolhido { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.medio) } }
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .onHover { sobre = $0 }
        .accessibilityAddTraits(escolhido ? .isSelected : [])
    }
}

// MARK: - Teclado

private struct Chip: View {
    var texto: String
    var escolhido = false
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(texto).font(.system(size: Tema.Texto.xs)).foregroundColor(escolhido ? Tema.Cor.texto : Tema.Cor.texto2)
                .padding(.horizontal, Tema.Espaco.icone)
                .frame(minHeight: Tema.Medida.chipAlt)
                .background(escolhido ? Tema.Cor.sucessoSuave : Tema.Cor.superficie2, in: Capsule())
                .overlay { if escolhido { Capsule().strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.fino) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(escolhido ? .isSelected : [])
    }
}

private struct PassoTeclado: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    static let exemplos: [(String, String)] = [("ctrl+opt+cmd+k", "Manter acordado no Vorssaint"), ("cmd+shift+4", "Captura de parte da tela"), ("ctrl+cmd+q", "Bloquear o Mac")]
    static let modificadores: [(Modificadores, String)] = [(.controle, "⌃ control"), (.opcao, "⌥ option"), (.comando, "⌘ command"), (.shift, "⇧ shift"), (.fn, "fn")]
    @State private var grupo = Teclas.grupos[0].id

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous)
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            Button(action: tela.alternarGravacao) {
                Quebra(espaco: Tema.Espaco.item) {
                    if tela.ouvindo {
                        Text("Aperte a combinação no teclado. Esc cancela").font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto)
                    } else if !tecla.valor.isEmpty {
                        ForEach(Array(CombinacaoEmTexto.pecas(tecla.valor).enumerated()), id: \.offset) { _, p in Kbd(texto: p) }
                    } else {
                        Text("Clique aqui e aperte as teclas").font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                    }
                }
                .padding(.vertical, Tema.Espaco.micro)
                .padding(.horizontal, Tema.Espaco.item)
                .frame(maxWidth: .infinity, minHeight: Tema.Medida.gravadorAlt, alignment: .leading)
                .background(forma.fill(Tema.Cor.telaFundo))
                .overlay {
                    if tela.ouvindo { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.fino) }
                    else { forma.strokeBorder(Tema.Cor.borda, style: StrokeStyle(lineWidth: Tema.Traco.fino, dash: Tema.Traco.tracejado)) }
                }
                .shadow(color: tela.ouvindo ? Tema.Cor.led.opacity(Tema.Opacidade.brilho) : .clear, radius: Tema.Sombra.brilhoRaio)
                .contentShape(forma)
            }
            .buttonStyle(.plain)
            if tela.ouvindo && !tela.capturaGlobal {
                ajuda("Se o atalho abrir outro app em vez de gravar, use \"Montar escolhendo as teclas\" aqui embaixo.")
            }
            ajuda("Serve para atalho de qualquer app, mesmo em segundo plano. Exemplos:")
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(Self.exemplos, id: \.0) { v, d in Chip(texto: d) { tela.escolherCombinacao(v) } }
            }
            .padding(.top, Tema.Espaco.item)
            montagem
        }
    }

    /// Montar escolhendo os modificadores e a tecla na tela, para o atalho que outro app (CleanShot, Raycast) já usa
    /// e que o gravador não consegue pegar.
    private var montagem: some View {
        let m = tela.montagem(de: tecla)
        let teclas = Teclas.grupos.first { $0.id == grupo }?.teclas ?? []
        return VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            Text("Montar escolhendo as teclas").tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2).padding(.top, Tema.Espaco.item)
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(Self.modificadores, id: \.1) { mod, nome in
                    Chip(texto: nome, escolhido: m.modificadores.contains(mod)) { tela.alternarModificador(mod) }
                }
            }
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(Teclas.grupos) { g in Chip(texto: g.nome, escolhido: g.id == grupo) { grupo = g.id } }
            }
            Quebra(espaco: Tema.Espaco.micro) {
                ForEach(teclas) { t in Chip(texto: t.rotulo, escolhido: m.tecla == t.nome) { tela.escolherTeclaDaMontagem(t.nome) } }
            }
            ajuda(m.faltaDizer ?? "Pronto, a combinação já está gravada na tecla.")
        }
    }
}

private struct Kbd: View {
    var texto: String
    var body: some View {
        Text(texto).font(.system(size: Tema.Texto.xs)).foregroundColor(Tema.Cor.texto)
            .padding(.horizontal, Tema.Espaco.item)
            .frame(minWidth: Tema.Medida.chipAlt, minHeight: Tema.Medida.chipAlt)
            .background {
                let f = RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous)
                ZStack(alignment: .bottom) { f.fill(Tema.Cor.superficie2); f.fill(Color.black.opacity(Tema.Opacidade.sombraDaTecla)).frame(height: Tema.Espaco.fino).clipShape(f) }
                    .clipShape(f)
            }
    }
}

// MARK: - Comando

private struct PassoComando: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    static let exemplos: [(String, String)] = [("Apagar tela", "pmset displaysleepnow"), ("Abrir Downloads", "open ~/Downloads"),
                                                ("Silenciar", "osascript -e 'set volume output muted true'"),
                                                ("Esvaziar Lixeira", #"osascript -e 'tell app "Finder" to empty trash'"#)]

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            CampoDeComando(texto: Binding(get: { tecla.valor }, set: { tela.escolherComando($0) }))
                .font(.system(size: Tema.Texto.sm, design: .monospaced))
                .foregroundColor(Tema.Cor.texto)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Tema.Espaco.icone - Tema.Medida.editorMargem)
                .padding(.vertical, Tema.Espaco.item - Tema.Medida.editorMargem)
                .frame(minHeight: Tema.Medida.comandoMin, alignment: .topLeading)
                .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous).strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.fino) }
                .accessibilityLabel("Comando")
            HStack(spacing: Tema.Espaco.item) {
                Text(tela.saidaDoTeste).font(.system(size: Tema.Texto.xs, design: .monospaced)).foregroundColor(Tema.Cor.texto2).lineLimit(2)
                Spacer(minLength: 0)
                Button("Testar agora", action: tela.testarComando).buttonStyle(EstiloDoBotao())
            }
            ajuda("Roda no zsh do Mac. Prontos para usar:")
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(Self.exemplos, id: \.0) { n, v in Chip(texto: n) { tela.escolherComando(v, nome: n) } }
            }
            .padding(.top, Tema.Espaco.item)
        }
    }
}

// MARK: - Ícone (todos menos App)

private struct EscolhaDeIcone: View {
    @ObservedObject var tela: ModeloTeclas
    @ObservedObject private var catalogo: CatalogoDeApps
    var tecla: Tecla

    init(tela: ModeloTeclas, tecla: Tecla) { self.tela = tela; self.catalogo = tela.catalogo; self.tecla = tecla }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text("Ícone").tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            Quebra(espaco: Tema.Espaco.mini) {
                ForEach(catalogo.maisUsados) { a in
                    Opcao(escolhido: tecla.icone == a.valor, acao: { tela.escolherIcone(a.valor) }, rotulo: a.nome) {
                        if let c = a.caminhoDoIcone {
                            Image(nsImage: IconesDeApps.imagem(c)).resizable().interpolation(.high)
                                .frame(width: Tema.Medida.icEscolha, height: Tema.Medida.icEscolha)
                                .background(Tema.Cor.superficie2)
                                .clipShape(RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                        }
                    }
                }
                ForEach(IconesDeTecla.doPainel, id: \.self) { o in
                    Opcao(escolhido: tecla.icone == o, acao: { tela.escolherIcone(o) }, rotulo: String(o.dropFirst(4))) {
                        Svg(IconesDeTecla.svg(String(o.dropFirst(4))) ?? Icone.raio, lado: Tema.Glifo.opcao).foregroundColor(Tema.Cor.texto)
                            .frame(width: Tema.Medida.icEscolha, height: Tema.Medida.icEscolha)
                            .background(Tema.Cor.superficie2, in: RoundedRectangle(cornerRadius: Tema.Raio.icP, style: .continuous))
                    }
                }
            }
        }
    }

    private struct Opcao<C: View>: View {
        var escolhido: Bool
        var acao: () -> Void
        var rotulo: String
        @ViewBuilder var conteudo: C

        var body: some View {
            Button(action: acao) {
                conteudo
                    .overlay { if escolhido { RoundedRectangle(cornerRadius: Tema.Raio.icP + Tema.Traco.forte, style: .continuous).strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.forte).padding(-Tema.Traco.forte) } }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rotulo)
            .accessibilityAddTraits(escolhido ? .isSelected : [])
        }
    }
}

/// A caixa grande do comando. Nas fotos, o texto parado.
private struct CampoDeComando: View {
    @Binding var texto: String
    @Environment(\.fotografando) private var foto

    var body: some View {
        if foto {
            Text(texto).frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, Tema.Medida.editorMargem).padding(.vertical, Tema.Espaco.item)
        } else {
            TextoComRascunho(texto: $texto) { TextEditor(text: $0) }
        }
    }
}
