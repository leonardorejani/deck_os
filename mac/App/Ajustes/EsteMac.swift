import SwiftUI
import AppKit

/// Seção "Este Mac" dos Ajustes, igual ao protótipo (prototipo/mac.js, TELAS.geral): nome do Mac, abrir
/// junto com o Mac, procurar atualizações e refazer a configuração inicial, e os grupos WhatsApp e Spotify.
/// Sem porta e sem composição: a porta é escolhida sozinha (SPEC 14.4) e a composição fica
/// no menu da barra.
struct EsteMac: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject private var abrirComMac: AbrirComMac
    @Environment(\.openWindow) private var abrirJanela
    @State private var nome: String
    @State private var procurarAtualizacoes: Bool
    @State private var gravando: Task<Void, Never>?

    private let defaults: UserDefaults

    init(modelo: ModeloApp, defaults: UserDefaults = .standard) {
        self.modelo = modelo
        self.abrirComMac = modelo.abrirComMac
        self.defaults = defaults
        _nome = State(initialValue: modelo.config.nomeMac)
        _procurarAtualizacoes = State(initialValue: PreferenciasDoMac.procurarAtualizacoes(defaults))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            GrupoDeAjuste(titulo: nil, nota: nil) {
                LinhasDeAjuste {
                    LinhaDeAjuste(titulo: "Nome deste Mac", apoio: "Aparece no iPhone quando o Mac sai da rede") {
                        CampoDeAjuste(rotulo: "Nome deste Mac", texto: $nome, largura: Tema.Medida.campoNome)
                    }
                    LinhaDeAjuste(titulo: "Abrir junto com o Mac", apoio: apoioDoLogin, divisoria: true) {
                        ChaveDeAjuste(rotulo: "Abrir junto com o Mac", ligada: abrirComMac.ligado || abrirComMac.precisaAprovar) { abrirComMac.definir($0) }
                    }
                    LinhaDeAjuste(titulo: "Procurar atualizações", apoio: "Uma vez por dia", divisoria: true) {
                        ChaveDeAjuste(rotulo: "Procurar atualizações", ligada: procurarAtualizacoes) {
                            procurarAtualizacoes = $0
                            PreferenciasDoMac.definirProcurarAtualizacoes($0, defaults)
                        }
                    }
                    LinhaDeAjuste(titulo: "Configuração inicial", apoio: "Refaz os passos da primeira vez, sem apagar suas teclas", divisoria: true) {
                        BotaoDeAjuste(texto: "Refazer", estilo: .secundario) { refazerConfiguracaoInicial() }
                    }
                }
            }
            GrupoDeAjuste(titulo: "WhatsApp", nota: nil) {
                LinhasDeAjuste {
                    LinhaDeAjuste(titulo: "Ler as não lidas de", apoio: PreferenciasDoMac.apoioDoWhatsApp(modelo.config.whatsapp.origem)) {
                        HStack(spacing: Tema.Espaco.fino) {
                            ForEach(PreferenciasDoMac.origensDoWhatsApp, id: \.id) { o in
                                BotaoDeAjuste(texto: o.rotulo, estilo: modelo.config.whatsapp.origem == o.id ? .primario : .secundario) {
                                    modelo.gravar { $0.whatsapp.origem = o.id }
                                }
                            }
                        }
                    }
                    GrupoWhatsAppQR(modelo: modelo)
                }
            }
            GrupoSpotify(spotify: modelo.spotify)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { abrirComMac.atualizar() }
        .onChange(of: nome) { novo in guardarNome(novo) }
    }

    private var apoioDoLogin: String {
        if let erro = abrirComMac.erro { return erro }
        if abrirComMac.precisaAprovar { return "Falta aprovar o Deck em Ajustes do Sistema > Geral > Itens de Início" }
        return "O Deck fica na barra de menus, sem ícone no Dock"
    }

    /// O nome só vai para a config 400 ms depois da última tecla (como o protótipo), sem gravar a cada letra.
    private func guardarNome(_ novo: String) {
        gravando?.cancel()
        gravando = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            modelo.gravar { $0.nomeMac = PreferenciasDoMac.nomeLimpo(novo) }
        }
    }

    private func refazerConfiguracaoInicial() {
        modelo.marcarConfiguracaoInicialFeita(false)
        NSApp.activate(ignoringOtherApps: true)
        abrirJanela(id: "inicial")
    }
}

/// Os poucos ajustes que ficam no UserDefaults do app (não na config do iPhone).
enum PreferenciasDoMac {
    static let chaveAtualizacoes = "procurarAtualizacoes"

    /// Ligado por padrão.
    static func procurarAtualizacoes(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: chaveAtualizacoes) as? Bool ?? true
    }

    static func definirProcurarAtualizacoes(_ ligado: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(ligado, forKey: chaveAtualizacoes)
    }

    /// As três origens do WhatsApp, na ordem em que aparecem nos Ajustes.
    static let origensDoWhatsApp: [(id: String, rotulo: String)] = [("auto", "Automático"), ("app", "App"), ("web", "WhatsApp Web")]

    static func apoioDoWhatsApp(_ origem: String) -> String {
        switch origem {
        case "app": return "Só o app do WhatsApp no Mac. Mostra cada conversa"
        case "web": return "Só o WhatsApp Web aberto no navegador. O iPhone vê o total, sem separar por conversa"
        case "qr": return "Lendo pelo aparelho conectado (QR), aí embaixo. Escolha uma opção daqui para voltar"
        default: return "O Deck usa o app do WhatsApp e, se ele estiver parado, o WhatsApp Web aberto no navegador"
        }
    }

    /// Campo vazio volta para "Mac", como o protótipo.
    static func nomeLimpo(_ texto: String) -> String {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Mac" : t
    }
}
