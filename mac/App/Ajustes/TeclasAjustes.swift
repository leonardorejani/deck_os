import SwiftUI

// Ajustes que moram dentro da tecla (passo 2 do editor): onde a Agenda salva, o que o Monitor mostra, as barras dos
// Controles, o que a tecla do Meet faz e o liga e desliga da tecla de comando. Saíram do "Este Mac" e usam controles
// nativos (menu e chave), alinhados à direita da linha, sem botão solto.

/// Qual ajuste a tecla de app tem, pelo app dela.
enum AjusteDeApp: Equatable {
    case agenda, monitor, controles, meet

    static func de(_ valor: String) -> AjusteDeApp? {
        switch valor {
        case "Calendar": return .agenda
        case "Activity Monitor": return .monitor
        case TeclasDeFabrica.controles.valor: return .controles
        case ControleDeReuniao.valorDoMeet: return .meet
        default: return nil
        }
    }

    var titulo: String {
        switch self {
        case .agenda: return "Agenda"
        case .monitor: return "Monitor de Atividade"
        case .controles: return "Controles do Mac"
        case .meet: return "Google Meet"
        }
    }
}

/// O cartão com as linhas de ajuste da tecla.
private struct CartaoDeAjustes<Conteudo: View>: View {
    var titulo: String
    var nota: String?
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text("Ajustes de \(titulo)").tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            VStack(spacing: 0) { conteudo }
                .padding(.horizontal, Tema.Espaco.pad)
                .frame(maxWidth: .infinity)
                .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.fino) }
            if let nota { NotaDeAjuste(nota) }
        }
    }
}

/// Chave nativa do macOS, verde como a tecla acesa, com o título e o apoio à esquerda.
struct LinhaComChave: View {
    var titulo: String
    var apoio: String?
    var divisoria = false
    var ligada: Bool
    var mudar: (Bool) -> Void

    var body: some View {
        LinhaDeAjuste(titulo: titulo, apoio: apoio, divisoria: divisoria) {
            Toggle(titulo, isOn: Binding(get: { ligada }, set: mudar))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Tema.Cor.led)
        }
    }
}

struct AjustesDaTecla: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    var body: some View {
        if tecla.tipo == "app", let ajuste = AjusteDeApp.de(tecla.valor) {
            switch ajuste {
            case .agenda: AjustesDaAgenda(modelo: tela.modelo)
            case .monitor: AjustesDoMonitor(modelo: tela.modelo)
            case .controles: AjustesDosControles(modelo: tela.modelo)
            case .meet: AjustesDoMeet(tela: tela, tecla: tecla)
            }
        }
    }
}

// MARK: - Agenda

/// Onde "Novo compromisso" do iPhone salva quando a pessoa não escolhe. De fábrica pergunta toda vez. A lista vem do
/// Calendário e dos Lembretes do Mac. Abrir o editor nunca pergunta acesso: para os Lembretes, o botão é que abre a janela do macOS.
struct AjustesDaAgenda: View {
    @ObservedObject var modelo: ModeloApp
    @State private var destinos: DestinosDaAgenda?
    private let criador = CriadorEventKit()

    private struct Opcao: Hashable { var destino: DestinoAgenda?; var texto: String }

    private var opcoes: [Opcao] {
        var r = [Opcao(destino: nil, texto: "Perguntar toda vez"), Opcao(destino: .padraoDoMac, texto: "Calendário padrão do Mac")]
        if let d = destinos {
            r += d.calendarios.map { Opcao(destino: DestinoAgenda(tipo: "calendario", id: $0.id), texto: "Calendário: \($0.nome)") }
            r += d.listas.map { Opcao(destino: DestinoAgenda(tipo: "lembretes", id: $0.id), texto: "Lembretes: \($0.nome)") }
        }
        // O que está gravado e ainda não está na lista (lendo, ou o calendário foi apagado) continua escolhido.
        if let atual = modelo.config.agendaPadrao, !r.contains(where: { $0.destino == atual }) {
            r.append(Opcao(destino: atual, texto: destinos == nil ? "Lendo os calendários..." : "Lugar que não existe mais"))
        }
        return r
    }

    var body: some View {
        CartaoDeAjustes(titulo: "Agenda", nota: nil) {
            LinhaDeAjuste(titulo: "Salvar compromissos em", apoio: apoio) {
                Picker("Salvar compromissos em", selection: Binding(get: { modelo.config.agendaPadrao }, set: { novo in modelo.gravar { $0.agendaPadrao = novo } })) {
                    ForEach(opcoes, id: \.self) { Text($0.texto).tag($0.destino) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if destinos?.permissaoLembretes == "pedir" {
                LinhaDeAjuste(titulo: "Lembretes", apoio: "Libere o acesso para salvar numa lista dos Lembretes", divisoria: true) {
                    BotaoDeAjuste(texto: "Liberar Lembretes", estilo: .secundario) {
                        CriadorEventKit.pedir(.reminder)
                        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); carregar() }
                    }
                }
            }
        }
        .onAppear { carregar() }
    }

    private var apoio: String {
        guard let d = destinos else { return "Lendo os calendários do Mac" }
        if d.permissaoCalendario == "recusado" { return "O Deck está sem acesso ao Calendário. Libere em Acessos do Mac" }
        if d.permissaoLembretes == "recusado" { return "O Deck está sem acesso aos Lembretes. Libere em Ajustes do Sistema > Privacidade" }
        return "Onde o \"Novo compromisso\" do iPhone grava sem perguntar"
    }

    private func carregar() {
        let c = criador
        Task.detached { let d = c.destinos(pedirPermissao: false); await MainActor.run { destinos = d } }
    }
}

// MARK: - Monitor

/// Um bloco pequeno no iPhone com processador, memória, bateria e rede, e a tela do Monitor de Atividade, que ainda mostra GPU, disco,
/// energia, ventoinhas e dispositivos (só o que este Mac conseguir ler). Nasce desligado, e cada item se liga ou desliga aqui,
/// porque a tela do iPhone não tem muito espaço. De fábrica, ligado o bloco, todos os itens aparecem.
struct AjustesDoMonitor: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        let c = modelo.config
        CartaoDeAjustes(titulo: "Monitor", nota: c.blocos.monitor ? nil : "Um bloco pequeno no iPhone com o que o Mac está usando agora") {
            LinhaComChave(titulo: "Mostrar na tela do iPhone", apoio: "Só aparece o que você deixar ligado abaixo", ligada: c.blocos.monitor) { v in
                modelo.gravar { $0.blocos.monitor = v }
            }
            if c.blocos.monitor {
                item("Processador", "Quanto do processador está em uso", c.monitor.cpu) { $0.monitor.cpu = $1 }
                item("Memória", "Quanto da memória está em uso", c.monitor.memoria) { $0.monitor.memoria = $1 }
                item("Bateria", "A carga e se está na tomada. Some em Mac sem bateria", c.monitor.bateria) { $0.monitor.bateria = $1 }
                item("Rede", "A velocidade de download e de upload", c.monitor.rede) { $0.monitor.rede = $1 }
                item("GPU", "Quanto da placa de vídeo está em uso. Na tela do Monitor de Atividade", c.monitor.gpu) { $0.monitor.gpu = $1 }
                item("Disco", "O espaço livre. Na tela do Monitor de Atividade", c.monitor.disco) { $0.monitor.disco = $1 }
                item("Energia", "Os watts que o Mac usa agora. Na tela do Monitor de Atividade", c.monitor.energia) { $0.monitor.energia = $1 }
                item("Ventoinhas", "A rotação em RPM. Some em Mac sem ventoinha. Na tela do Monitor de Atividade", c.monitor.ventoinhas) { $0.monitor.ventoinhas = $1 }
                item("Dispositivos", "Quantos dispositivos USB estão conectados. Na tela do Monitor de Atividade", c.monitor.dispositivos) { $0.monitor.dispositivos = $1 }
            }
        }
    }

    private func item(_ titulo: String, _ apoio: String, _ ligado: Bool, _ mudar: @escaping (inout Config, Bool) -> Void) -> some View {
        LinhaComChave(titulo: titulo, apoio: apoio, divisoria: true, ligada: ligado) { v in modelo.gravar { mudar(&$0, v) } }
    }
}

// MARK: - Controles

/// Quais barras a tela Controles do Mac mostra no iPhone. De fábrica, as três.
struct AjustesDosControles: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        let c = modelo.config.controles
        CartaoDeAjustes(titulo: "Controles", nota: c.algum ? nil : "Sem nenhuma barra ligada a tela fica vazia no iPhone") {
            LinhaComChave(titulo: "Volume", apoio: "A barra do volume e o botão de mudo", ligada: c.volume) { v in modelo.gravar { $0.controles.volume = v } }
            LinhaComChave(titulo: "Brilho da tela", apoio: "Só nos Macs que deixam mudar o brilho", divisoria: true, ligada: c.brilho) { v in modelo.gravar { $0.controles.brilho = v } }
            LinhaComChave(titulo: "Luz do teclado", apoio: "Some sozinha em Mac sem luz no teclado", divisoria: true, ligada: c.teclado) { v in modelo.gravar { $0.controles.teclado = v } }
        }
    }
}

// MARK: - Meet

/// O Meet que a pessoa usa no navegador, sem app instalado: a tecla acha a sala aberta em qualquer navegador.
struct AjustesDoMeet: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    private static let opcoes: [(id: String?, texto: String)] = [
        (nil, "Abrir o Meet no navegador"),
        (IdsDeAcao.reuniaoMicrofone, "Mutar ou desmutar o microfone"),
        (IdsDeAcao.reuniaoCamera, "Ligar ou desligar a câmera"),
    ]

    var body: some View {
        CartaoDeAjustes(titulo: "Google Meet", nota: "Vale para a sala aberta no Safari, Chrome, Arc, Brave ou Edge. Não precisa de app instalado. O Mac pede Acessibilidade e o controle do navegador na primeira vez.") {
            LinhaDeAjuste(titulo: "Ao apertar a tecla", apoio: nil) {
                Picker("Ao apertar a tecla", selection: Binding(get: { tecla.acao?.id }, set: { id in tela.escolherAcao(id.map { AcaoDeApp(id: $0, valor: nil) }) })) {
                    ForEach(Self.opcoes, id: \.id) { Text($0.texto).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }
}

// MARK: - Comando liga e desliga

/// "Liga e desliga" da tecla de comando: um comando para ligar (o principal da tecla), um para desligar e, se a pessoa
/// quiser, um que confere se está ligado (sai 0 = ligado). Sem o que confere, o Deck guarda o estado.
struct LigaEDesliga: View {
    @ObservedObject var tela: ModeloTeclas
    var tecla: Tecla

    var body: some View {
        let ligado = tecla.desligar != nil
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            VStack(spacing: 0) {
                LinhaComChave(titulo: "Liga e desliga", apoio: "O mesmo botão liga e desliga. Ex.: entrar no modo jogo e voltar às configs de trabalho",
                              ligada: ligado) { tela.definirLigaEDesliga($0) }
            }
            .padding(.horizontal, Tema.Espaco.pad)
            .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Tema.Raio.normal, style: .continuous).strokeBorder(Tema.Cor.borda, lineWidth: Tema.Traco.fino) }
            if ligado {
                campo("Comando para desligar", Binding(get: { tecla.desligar ?? "" }, set: { tela.escolherDesligar($0) }))
                campo("Comando que confere se está ligado (opcional)", Binding(get: { tecla.estado ?? "" }, set: { tela.escolherConferir($0) }))
                NotaDeAjuste("O que confere sai com 0 quando está ligado. Sem ele, o Deck lembra o que você apertou por último e a tecla acende sozinha.")
            }
        }
    }

    private func campo(_ rotulo: String, _ texto: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.micro) {
            Text(rotulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            CampoDeAjuste(rotulo: rotulo, texto: texto, largura: nil)
        }
    }
}
