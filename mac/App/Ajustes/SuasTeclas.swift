import SwiftUI
import UniformTypeIdentifiers

/// Seção "Suas teclas" dos Ajustes, igual ao protótipo (prototipo/mac.js, TELAS.teclas): perfis em
/// abas, as páginas do iPhone (uma por vez), a grade de teclas que arrasta e o editor em 2 passos.
/// Tudo grava pela config do ModeloApp, e o iPhone vê na hora.
struct SuasTeclas: View {
    @ObservedObject var modelo: ModeloApp
    @StateObject private var tela: ModeloTeclas

    /// `catalogo`, `acesas` e `preparar` só as fotos usam: lista de apps fixa, tecla acesa e o estado de partida.
    init(modelo: ModeloApp, catalogo: CatalogoDeApps? = nil, acesas: Set<String> = [], preparar: ((ModeloTeclas) -> Void)? = nil) {
        self.modelo = modelo
        let m = ModeloTeclas(modelo: modelo, catalogo: catalogo ?? .compartilhado, acesas: acesas)
        preparar?(m)
        _tela = StateObject(wrappedValue: m)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            if let e = modelo.erro { CartaoDeErro(texto: e) }
            BarraDePerfis(tela: tela)
            GrupoNoIphone(tela: tela)
            if let t = tela.tecla {
                EditorDeTecla(tela: tela, tecla: t)
            } else {
                Text(#"Crie a primeira tecla no "Nova"."#)
                    .font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                    .frame(height: Tema.Texto.sm * Tema.Texto.altura)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Tema.Espaco.secao)
                    .superficie()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) { AvisoPosicionado(tela: tela) }
        .background { Button("") { tela.desfazerAgora() }.keyboardShortcut("z", modifiers: .command).disabled(!tela.podeDesfazer).opacity(0).allowsHitTesting(false) }
        .onAppear { tela.catalogo.carregarSeFaltar(); tela.conferir(); tela.atualizarAcesas() }
        .onChange(of: modelo.config) { _ in tela.conferir() }
        .onChange(of: modelo.mudancasDeFora) { _ in tela.avisar("O iPhone mudou a ordem ou uma tecla") }
        .onDisappear { tela.parar() }
    }
}

// MARK: - Perfis

private struct BarraDePerfis: View {
    @ObservedObject var tela: ModeloTeclas

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(tela.perfis, id: \.id) { p in
                    AbaDePerfil(nome: p.nome, selecionada: p.id == tela.editando, noIphone: p.id == tela.perfilAtivo) { tela.editarPerfil(p.id) }
                }
                Button(action: tela.novoPerfil) {
                    HStack(spacing: Tema.Espaco.item) {
                        Svg(Icone.mais, lado: Tema.Glifo.mais)
                        Text("Perfil").font(.system(size: Tema.Texto.sm))
                    }
                    .foregroundColor(Tema.Cor.texto2)
                    .padding(.horizontal, Tema.Espaco.pad)
                    .frame(minHeight: Tema.Medida.perfilAba)
                    .overlay { Capsule().strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.medio) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Tema.Espaco.icone) {
                CampoDeLinha(dica: "Nome do perfil", texto: Binding(get: { tela.perfil.nome }, set: { tela.renomearPerfil($0) }), pedidoDeFoco: tela.pedidoDeFocoNoPerfil)
                    .textFieldStyle(.plain)
                    .font(.system(size: Tema.Texto.sm, weight: .semibold))
                    .foregroundColor(Tema.Cor.texto)
                    .entrada()
                    .frame(width: Tema.Medida.campoPerfil)
                    .accessibilityLabel("Nome do perfil")
                if tela.iphoneMostraEstePerfil {
                    HStack(spacing: Tema.Espaco.item) {
                        Ponto(ligado: true)
                        Text("No iPhone agora").tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2)
                    }
                } else {
                    Button("Usar no iPhone agora", action: tela.usarNoIphone).buttonStyle(EstiloDoBotao())
                }
                Spacer(minLength: 0)
                if tela.perfis.count > 1 {
                    Button("Excluir perfil", action: tela.excluirPerfil).buttonStyle(EstiloDoBotao(tipo: .perigo))
                }
            }
        }
    }
}

private struct AbaDePerfil: View {
    var nome: String
    var selecionada: Bool
    var noIphone: Bool
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: Tema.Espaco.item) {
                Text(nome).font(.system(size: Tema.Texto.sm, weight: .semibold)).lineLimit(1)
                if noIphone { Ponto(ligado: true).help("É o que o iPhone mostra agora") }
            }
            .foregroundColor(selecionada ? Tema.Cor.texto : Tema.Cor.texto2)
            .padding(.horizontal, Tema.Espaco.pad)
            .frame(minHeight: Tema.Medida.perfilAba)
            .background {
                if selecionada {
                    Capsule().fill(Tema.Cor.superficie2)
                } else {
                    ZStack { Capsule().fill(Tema.Cor.anel).padding(-1); Capsule().fill(Tema.Cor.superficie) }
                }
            }
            .overlay { if selecionada { Capsule().strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.medio) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }
}

// MARK: - Páginas e grade

private struct GrupoNoIphone: View {
    @ObservedObject var tela: ModeloTeclas
    @Environment(\.fotografando) private var foto

    var body: some View {
        let paginas = tela.paginas
        let atual = tela.paginaAtual
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            HStack(alignment: .firstTextBaseline, spacing: Tema.Espaco.item) {
                Text("No iPhone").titulinho(Tema.Texto.sm, .semibold, Tema.Cor.texto2)
                Text("Arraste para mudar a ordem, ou solte numa aba para mudar de página. É a mesma lista do modo organizar do iPhone")
                    .titulinho(Tema.Texto.xs, .regular, Tema.Cor.texto2)
            }
            if paginas.count > 1 {
                HStack(spacing: Tema.Espaco.fino) {
                    ForEach(0..<paginas.count, id: \.self) { i in
                        AbaDePagina(numero: i + 1, selecionada: i == atual, soltando: tela.abaDeSoltar == i) { tela.irParaPagina(i) }
                            .arrastavel(!foto, ao: { NSItemProvider() }, soltar: SoltarNaAba(tela: tela, indice: i))
                    }
                }
                .padding(Tema.Espaco.fino)
                .superficie(raio: Tema.Raio.normal)
                .padding(.bottom, Tema.Espaco.icone)
            }
            Quebra(espaco: Tema.Espaco.item) {
                ForEach(paginas[atual], id: \.id) { t in
                    TeclaMac(tecla: t, catalogo: tela.catalogo, acesa: tela.acesas.contains(t.id), selecionada: t.id == tela.sel,
                             arrastando: tela.arrastando == t.id)
                        .onTapGesture { tela.escolher(t.id) }
                        .arrastavel(!foto, ao: { tela.arrastar(t.id); return NSItemProvider(object: t.id as NSString) },
                                    soltar: SoltarNaTecla(tela: tela, id: t.id))
                }
                if atual == paginas.count - 1 { TeclaNova(acao: tela.novaTecla) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Teclas da página \(atual + 1)")
        }
    }
}

private struct AbaDePagina: View {
    var numero: Int
    var selecionada: Bool
    var soltando: Bool
    var acao: () -> Void
    @State private var sobre = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous)
        Button(action: acao) {
            Text("Página \(numero)")
                .font(.system(size: Tema.Texto.sm, weight: selecionada ? .semibold : .regular))
                .foregroundColor(selecionada || soltando ? Tema.Cor.texto : Tema.Cor.texto2)
                .padding(.horizontal, Tema.Espaco.icone)
                .frame(minHeight: Tema.Espaco.alvoSm)
                .background {
                    if selecionada {
                        ZStack { forma.fill(Tema.Cor.anel).padding(-1); forma.fill(Tema.Cor.superficie2) }
                    }
                }
                .overlay { if soltando { forma.strokeBorder(Tema.Cor.led, lineWidth: Tema.Traco.medio) } }
                .contentShape(forma)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecionada ? .isSelected : [])
    }
}

/// Soltar em cima de outra tecla: a arrastada passa a ocupar o lugar dela, ao vivo.
private struct SoltarNaTecla: DropDelegate {
    var tela: ModeloTeclas
    var id: String

    func dropEntered(info: DropInfo) { tela.moverArrastada(para: id) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { tela.terminouDeArrastar(); return true }
}

/// Soltar numa aba: a tecla vai para o fim daquela página.
private struct SoltarNaAba: DropDelegate {
    var tela: ModeloTeclas
    var indice: Int

    func dropEntered(info: DropInfo) { tela.abaDeSoltar = indice }
    func dropExited(info: DropInfo) { if tela.abaDeSoltar == indice { tela.abaDeSoltar = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { tela.soltarNaAba(indice); return true }
}

// MARK: - Aviso na janela

/// O aviso fica no pé da janela, não no pé da lista que rola. A janela tem tamanho fixo, então a conta
/// é a posição do conteúdo na janela.
private struct AvisoPosicionado: View {
    @ObservedObject var tela: ModeloTeclas

    var body: some View {
        GeometryReader { g in
            let topo = g.frame(in: .global).minY
            Group {
                if let a = tela.aviso {
                    AvisoView(aviso: a) { tela.desfazerAgora() }
                        .padding(.bottom, Tema.Espaco.pad)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: g.size.width, height: Tema.Medida.janelaAlt, alignment: .bottom)
            .offset(y: -topo)
        }
    }
}
