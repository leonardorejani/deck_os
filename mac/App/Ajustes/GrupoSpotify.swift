import SwiftUI
import AppKit

/// O grupo "Spotify" de Este Mac. Com a chave do app embutida no Deck, é só "Conectar" (login), e a chave própria fica
/// recolhida em "Avançado". Sem chave embutida (fork que não configurou), a tela pede a chave, o endereço de retorno e
/// o passo a passo para criar uma de graça. Sem login o player do iPhone segue como sempre. Com login ganha aparelhos,
/// curtir, fila e repetir.
struct GrupoSpotify: View {
    @ObservedObject var spotify: ModeloSpotify
    private var avancadoAberto: Bool { spotify.avancadoAberto }

    var body: some View {
        let situacao = spotify.situacao
        GrupoDeAjuste(titulo: "Spotify", nota: spotify.temChaveEmbutida ? nil : SpotifyLogica.passos) {
            LinhasDeAjuste {
                if !spotify.temChaveEmbutida {
                    linhaDaChave
                }
                LinhaDeAjuste(titulo: "Login no Spotify", apoio: SpotifyLogica.apoioDoLogin(situacao, erro: spotify.erro), divisoria: !spotify.temChaveEmbutida) {
                    HStack(spacing: Tema.Espaco.item) {
                        switch situacao {
                        case .conectado:
                            ValorDeAjuste("Conectado")
                            BotaoDeAjuste(texto: "Desconectar", estilo: .perigo) { spotify.desconectar() }
                        case .conectando:
                            BotaoDeAjuste(texto: "Cancelar", estilo: .secundario) { spotify.cancelar() }
                        case .pronto, .semChave:
                            BotaoDeAjuste(texto: "Conectar", estilo: .primario, desligado: situacao == .semChave) { Task { await spotify.conectar() } }
                        }
                    }
                }
                if spotify.temChaveEmbutida {
                    LinhaDeAjuste(titulo: SpotifyLogica.avancado, apoio: SpotifyLogica.apoioDoAvancado, divisoria: true) {
                        BotaoDeAjuste(texto: avancadoAberto ? "Esconder" : "Mostrar", estilo: .secundario) { spotify.avancadoAberto.toggle() }
                    }
                    if avancadoAberto {
                        linhaDaChave
                        if spotify.usaChavePropria {
                            LinhaDeAjuste(titulo: "Chave do Deck", apoio: "Esquece a sua chave e volta para a que vem no Deck. Pede para conectar de novo", divisoria: true) {
                                BotaoDeAjuste(texto: "Voltar", estilo: .secundario) { spotify.usarChaveDoDeck() }
                            }
                        }
                    }
                }
                if !spotify.temChaveEmbutida || avancadoAberto {
                    linhaDoEndereco
                    LinhaDeAjuste(titulo: "Criar a chave", apoio: "Abre o site de desenvolvedor do Spotify (grátis)", divisoria: true) {
                        BotaoDeAjuste(texto: "Abrir site", estilo: .secundario) { NSWorkspace.shared.open(SpotifyLogica.siteDoSpotify) }
                    }
                }
            }
            if spotify.temChaveEmbutida && avancadoAberto {
                NotaDeAjuste(SpotifyLogica.passos)
            }
        }
        .onChange(of: spotify.chave) { _ in spotify.guardarChave() }
        .onAppear { spotify.atualizar() }
    }

    private var linhaDaChave: some View {
        LinhaDeAjuste(titulo: "Chave do app (Client ID)", apoio: SpotifyLogica.apoioDoCampo, divisoria: spotify.temChaveEmbutida) {
            CampoDeAjuste(rotulo: "Chave do app do Spotify", texto: $spotify.chave, largura: Tema.Medida.campoChave)
        }
    }

    private var linhaDoEndereco: some View {
        LinhaDeAjuste(titulo: "Endereço de retorno", apoio: SpotifyLogica.apoioDoEndereco, divisoria: true) {
            HStack(spacing: Tema.Espaco.item) {
                Text(SpotifyLogica.enderecoDoRetorno)
                    .font(.system(size: Tema.Texto.xs, design: .monospaced))
                    .foregroundColor(Tema.Cor.texto)
                    .lineLimit(1)
                    .textSelection(.enabled)
                BotaoDeAjuste(texto: "Copiar", estilo: .secundario) { copiar(SpotifyLogica.enderecoDoRetorno) }
            }
        }
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}
