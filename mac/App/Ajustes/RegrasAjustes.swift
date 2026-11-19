import SwiftUI

/// Seção "Regras" dos Ajustes (SPEC 13, item 40): a lista de regras "quando, então" com ligar, desligar, Testar e Editar, a
/// pausa geral e o editor. Quem decide quando uma regra vale é o núcleo (Nucleo/Regras.swift, testado lá). Aqui só se
/// edita a lista, que vai para a config e daí para o iPhone.
struct Regras: View {
    @ObservedObject var modelo: ModeloApp
    @State private var editando: Regra?

    /// `editando` só nas fotos, para fotografar o editor aberto.
    init(modelo: ModeloApp, editando: Regra? = nil) {
        self.modelo = modelo
        _editando = State(initialValue: editando)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            if let r = editando {
                EditorDeRegra(modelo: modelo, original: r) { editando = nil }
                    .id(r.id)
            } else {
                lista
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Sair da seção com o editor aberto joga o rascunho fora.
        .onDisappear { editando = nil }
    }

    @ViewBuilder private var lista: some View {
        let regras = modelo.config.regras
        GrupoDeAjuste(titulo: nil, nota: nil) {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Pausar todas as regras", apoio: modelo.config.regrasPausadas ? "Nada troca sozinho no iPhone" : "As regras ligadas valem") {
                    ChaveDeAjuste(rotulo: "Pausar todas as regras", ligada: modelo.config.regrasPausadas) { novo in modelo.gravar { $0.regrasPausadas = novo } }
                }
            }
        }
        GrupoDeAjuste(titulo: "Suas regras", nota: "Antes de trocar, o iPhone mostra uma contagem de 3 segundos com Ficar e Ir agora. Nunca troca enquanto você toca na tela.") {
            if regras.isEmpty {
                NotaDeAjuste("Nenhuma regra ainda.")
            } else {
                LinhasDeAjuste {
                    ForEach(Array(regras.enumerated()), id: \.element.id) { i, r in
                        LinhaDeAjuste(titulo: r.nome, apoio: r.resumo(perfis: modelo.config.perfis), divisoria: i > 0) {
                            HStack(spacing: Tema.Espaco.item) {
                                BotaoDeAjuste(texto: "Testar", estilo: .link) { modelo.testarRegra(r.id) }
                                BotaoDeAjuste(texto: "Editar", estilo: .secundario) { editando = r }
                                ChaveDeAjuste(rotulo: "Ligar \(r.nome)", ligada: r.ligada) { novo in
                                    modelo.gravar { c in if let k = c.regras.firstIndex(where: { $0.id == r.id }) { c.regras[k].ligada = novo } }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                BotaoDeAjuste(texto: "Nova regra", estilo: .secundario) { editando = Regra.nova(entre: regras) }
                Spacer(minLength: 0)
            }
        }
    }
}

/// O editor de uma regra: um rascunho que só vai para a config no Salvar.
private struct EditorDeRegra: View {
    @ObservedObject var modelo: ModeloApp
    let original: Regra
    var fechar: () -> Void
    @State private var r: Regra
    @State private var erro: String?

    init(modelo: ModeloApp, original: Regra, fechar: @escaping () -> Void) {
        self.modelo = modelo
        self.original = original
        self.fechar = fechar
        _r = State(initialValue: original)
    }

    private var existe: Bool { modelo.config.regras.contains { $0.id == original.id } }
    private var perfis: [Perfil] { modelo.config.perfis }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Nome") {
                    CampoDeAjuste(rotulo: "Nome da regra", texto: $r.nome, largura: Tema.Medida.campoNome)
                }
                LinhaDeAjuste(titulo: "Quando", divisoria: true) {
                    menu("Quando", selecao: Binding(get: { r.quando.fonte }, set: { trocarFonte($0) }), opcoes: Gatilho.fontes.map { ($0, Gatilho.rotulo($0)) })
                }
                if r.quando.fonte == "uso" {
                    LinhaDeAjuste(titulo: "Limite de uso", apoio: "Percentual da semana da conta mais usada", divisoria: true) {
                        CampoDeAjuste(rotulo: "Limite de uso", texto: Binding(get: { String(r.quando.limite ?? 90) },
                                                                              set: { r.quando.limite = Int($0.filter(\.isNumber)) }), largura: Tema.Medida.campoHora)
                    }
                }
                LinhaDeAjuste(titulo: "Então", divisoria: true) {
                    menu("Então", selecao: Binding(get: { r.entao.tipo }, set: { trocarTipo($0) }), opcoes: AcaoDeRegra.tipos.map { ($0, AcaoDeRegra.rotuloDoTipo($0)) })
                }
                LinhaDeAjuste(titulo: rotuloDoAlvo, divisoria: true) { campoDoAlvo }
                LinhaDeAjuste(titulo: "Dias", apoio: "Sem nenhum marcado vale todos os dias", divisoria: true) { dias }
                LinhaDeAjuste(titulo: "Horário", apoio: r.quando.fonte == "horario" ? "Obrigatório nesta condição" : "Vazio vale o dia todo", divisoria: true) {
                    HStack(spacing: Tema.Espaco.item) {
                        CampoDeAjuste(rotulo: "Hora de início", texto: hora(\.de), largura: Tema.Medida.campoHora)
                        Text("às").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
                        CampoDeAjuste(rotulo: "Hora de fim", texto: hora(\.ate), largura: Tema.Medida.campoHora)
                    }
                }
                LinhaDeAjuste(titulo: "Enquanto durar", apoio: "Desfaz a troca quando a condição acaba", divisoria: true) {
                    ChaveDeAjuste(rotulo: "Enquanto durar", ligada: r.enquantoDurar) { r.enquantoDurar = $0 }
                }
                LinhaDeAjuste(titulo: "Descanso", apoio: "Tempo sem disparar de novo", divisoria: true) {
                    menu("Descanso", selecao: $r.descanso, opcoes: descansos)
                }
                LinhaDeAjuste(titulo: "Prioridade", apoio: "A maior vence quando duas valem juntas", divisoria: true) {
                    menu("Prioridade", selecao: $r.prioridade, opcoes: (1...9).map { ($0, $0 == 5 ? "5 (normal)" : "\($0)") })
                }
            }
            HStack(spacing: Tema.Espaco.item) {
                if existe { BotaoDeAjuste(texto: "Excluir", estilo: .perigo) { excluir() } }
                Text(erro ?? " ").tatile(Tema.Texto.xs, .regular, Tema.Cor.perigo, linhas: 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                BotaoDeAjuste(texto: "Cancelar", estilo: .secundario, acao: fechar)
                BotaoDeAjuste(texto: "Salvar", estilo: .primario) { salvar() }
            }
        }
    }

    // MARK: Peças

    private func menu<V: Hashable>(_ rotulo: String, selecao: Binding<V>, opcoes: [(V, String)]) -> some View {
        Picker(rotulo, selection: selecao) {
            ForEach(opcoes, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var descansos: [(Int, String)] {
        var v = Regra.opcoesDeDescanso
        if !v.contains(r.descanso) { v.append(r.descanso); v.sort() }
        return v.map { ($0, Regra.rotuloDoDescanso($0)) }
    }

    private var rotuloDoAlvo: String {
        switch r.entao.tipo {
        case "tela": return "Tela"
        case "composicao": return "Composição"
        case "perfil": return "Perfil"
        default: return "Texto do aviso"
        }
    }

    @ViewBuilder private var campoDoAlvo: some View {
        switch r.entao.tipo {
        case "tela":
            menu("Tela", selecao: $r.entao.alvo, opcoes: AcaoDeRegra.telas.map { ($0, AcaoDeRegra.nomeDaTela($0)) })
        case "composicao":
            menu("Composição", selecao: $r.entao.alvo, opcoes: AcaoDeRegra.composicoes.map { ($0, AcaoDeRegra.nomeDaComposicao($0)) })
        case "perfil":
            menu("Perfil", selecao: $r.entao.alvo, opcoes: opcoesDePerfil)
        default:
            CampoDeAjuste(rotulo: "Texto do aviso", texto: $r.entao.alvo, largura: Tema.Medida.campoNome)
        }
    }

    private var opcoesDePerfil: [(String, String)] {
        var v = perfis.map { ($0.id, $0.nome) }
        if !r.entao.alvo.isEmpty, !v.contains(where: { $0.0 == r.entao.alvo }) { v.append((r.entao.alvo, "Perfil que não existe mais")) }
        return v
    }

    private var dias: some View {
        HStack(spacing: Tema.Espaco.micro) {
            ForEach(0..<7, id: \.self) { d in
                let ligado = r.dias.contains(d)
                Button {
                    if ligado { r.dias.removeAll { $0 == d } } else { r.dias.append(d); r.dias.sort() }
                } label: {
                    Text(Regra.diasCurtos[d]).tatile(Tema.Texto.xs, .semibold, ligado ? Tema.Cor.destaqueTexto : Tema.Cor.texto)
                        .frame(width: Tema.Espaco.alvoSm, height: Tema.Espaco.alvoSm)
                        .background(ligado ? Tema.Cor.destaque : Tema.Cor.superficie2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Regra.diasPorExtenso[d])
                .accessibilityAddTraits(ligado ? .isSelected : [])
            }
        }
    }

    private func hora(_ caminho: WritableKeyPath<Regra, String?>) -> Binding<String> {
        Binding(get: { r[keyPath: caminho] ?? "" }, set: { r[keyPath: caminho] = $0.isEmpty ? nil : $0 })
    }

    // MARK: Ações

    private func trocarFonte(_ fonte: String) {
        r.quando.fonte = fonte
        r.quando.limite = fonte == "uso" ? (r.quando.limite ?? 90) : nil
        if fonte == "horario", r.de == nil { r.de = "09:00"; r.ate = "18:00" }
    }

    private func trocarTipo(_ tipo: String) {
        r.entao = AcaoDeRegra(tipo: tipo, alvo: AcaoDeRegra.alvoPadrao(tipo: tipo, perfis: perfis))
    }

    private func salvar() {
        r.nome = r.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        if let falha = Config.validarRegras([r]) { erro = falha; return }
        erro = nil
        let nova = r
        modelo.gravar { c in
            if let i = c.regras.firstIndex(where: { $0.id == nova.id }) { c.regras[i] = nova } else { c.regras.append(nova) }
        }
        fechar()
    }

    private func excluir() {
        let id = original.id
        modelo.gravar { $0.regras.removeAll { $0.id == id } }
        fechar()
    }
}
