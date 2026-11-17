import SwiftUI
import AppKit

/// O grupo "Spotify" de Este Mac. Com a chave do app embutida no Deck, é só "Conectar" (login). Abaixo, o bloco "Usar a sua
/// própria chave" explica o porquê e o passo a passo para quem quiser a própria chave. Sem chave embutida (fork que não
/// configurou), o bloco fica sempre aberto. Sem login o player do iPhone segue como sempre. Com login ganha aparelhos,
/// curtir, fila e repetir.
struct GrupoSpotify: View {
    @ObservedObject var spotify: ModeloSpotify
    @State private var verMais = false
    private var blocoAberto: Bool { !spotify.temChaveEmbutida || spotify.avancadoAberto }

    var body: some View {
        let situacao = spotify.situacao
        GrupoDeAjuste(titulo: "Spotify", nota: nil) {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Login no Spotify", apoio: SpotifyLogica.apoioDoLogin(situacao, erro: spotify.contaNaoLiberada ? nil : spotify.erro, confirmando: spotify.confirmando), divisoria: false) {
                    HStack(spacing: Tema.Espaco.item) {
                        switch situacao {
                        case .conectado:
                            ValorDeAjuste(spotify.nome.map { "Conectado como \($0)" } ?? "Conectado")
                            BotaoDeAjuste(texto: "Desconectar", estilo: .perigo) { spotify.desconectar() }
                        case .conectando:
                            BotaoDeAjuste(texto: "Cancelar", estilo: .secundario) { spotify.cancelar() }
                        case .pronto, .semChave:
                            BotaoDeAjuste(texto: "Conectar", estilo: .primario, desligado: situacao == .semChave) { Task { await spotify.conectar() } }
                        }
                    }
                }
                if spotify.temChaveEmbutida {
                    LinhaDeAjuste(titulo: "Chave em uso", apoio: nil, divisoria: true) {
                        HStack(spacing: Tema.Espaco.item) {
                            ValorDeAjuste(spotify.nomeDaChaveEmUso)
                            if spotify.usaChavePropria {
                                BotaoDeAjuste(texto: "Voltar para a chave do Deck", estilo: .secundario) { spotify.usarChaveDoDeck() }
                            }
                        }
                    }
                }
                if spotify.contaNaoLiberada {
                    LinhaDeAjuste(titulo: SpotifyLogica.avisoDeCadastro, apoio: nil, divisoria: true) {
                        BotaoDeAjuste(texto: "Ver o passo a passo", estilo: .primario) { spotify.avancadoAberto = true }
                    }
                }
                if spotify.avisoDeLimite {
                    LinhaDeAjuste(titulo: SpotifyLogica.tituloDoLimite, apoio: SpotifyLogica.apoioDoLimite, divisoria: true) {
                        BotaoDeAjuste(texto: "Usar a minha chave", estilo: .secundario) { spotify.avancadoAberto = true }
                    }
                }
                LinhaDeAjuste(titulo: SpotifyLogica.tituloDoBloco, apoio: SpotifyLogica.resumoDoBloco, divisoria: true) {
                    if spotify.temChaveEmbutida {
                        BotaoDeAjuste(texto: blocoAberto ? "Esconder" : "Mostrar", estilo: .secundario) { spotify.avancadoAberto.toggle() }
                    }
                }
                if blocoAberto {
                    LinhaDeAjuste(titulo: "Mais detalhes", apoio: verMais ? SpotifyLogica.detalheDoBloco : nil, divisoria: true) {
                        BotaoDeAjuste(texto: verMais ? "Ver menos" : "Ver mais", estilo: .link) { verMais.toggle() }
                    }
                    ForEach(Array(SpotifyLogica.passos.enumerated()), id: \.offset) { n, passo in
                        LinhaDeAjuste(titulo: passo.titulo, apoio: passo.apoio, divisoria: true) { ladoDoPasso(n + 1, situacao) }
                    }
                }
            }
        }
        .onChange(of: spotify.chave) { _ in spotify.guardarChave() }
        .onAppear { spotify.atualizar() }
        // O login vive no Chaveiro e o painel lê de lá: ao voltar para o Deck a tela relê, para não dizer "Conectado" de um login que caiu.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in spotify.atualizar() }
    }

    @ViewBuilder
    private func ladoDoPasso(_ n: Int, _ situacao: SituacaoSpotify) -> some View {
        switch n {
        case 1:
            BotaoDeAjuste(texto: "Abrir o painel", estilo: .secundario) { NSWorkspace.shared.open(SpotifyLogica.siteDoSpotify) }
        case 4:
            HStack(spacing: Tema.Espaco.item) {
                Text(SpotifyLogica.enderecoDoRetorno)
                    .font(.system(size: Tema.Texto.xs, design: .monospaced))
                    .foregroundColor(Tema.Cor.texto)
                    .lineLimit(1)
                    .textSelection(.enabled)
                BotaoDeAjuste(texto: "Copiar", estilo: .secundario) { copiar(SpotifyLogica.enderecoDoRetorno) }
            }
        case 6:
            CampoDeAjuste(rotulo: "Chave do app do Spotify (Client ID)", texto: $spotify.chave, largura: Tema.Medida.campoChave)
        case 7:
            if situacao == .conectando {
                BotaoDeAjuste(texto: "Cancelar", estilo: .secundario) { spotify.cancelar() }
            } else if situacao != .conectado {
                BotaoDeAjuste(texto: "Conectar", estilo: .primario, desligado: situacao == .semChave) { Task { await spotify.conectar() } }
            }
        default:
            EmptyView()
        }
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}
