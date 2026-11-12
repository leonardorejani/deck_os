import SwiftUI
import AppKit

/// Seção "Acessos do Mac" dos Ajustes: todos os acessos que o Deck usa, cada um com o nome que o macOS usa,
/// o motivo, o estado real (liberado, não perguntado, recusado) e os botões: "Permitir", que faz o próprio Deck
/// pedir ao macOS, e "Abrir Ajustes do Sistema", que abre a página certa. A lista se atualiza sozinha.
struct Acessos: View {
    @ObservedObject var modelo: ModeloApp
    /// O que os botões fazem. Nas fotos e nos testes não abrem nada. Sem nada passado, "Abrir Ajustes do Sistema" abre a
    /// página e traz o Deck de volta quando a permissão mudar.
    var abrir: ((AcessoMac) -> Void)?
    var permitir: ((AcessoMac) -> Void)?
    @Environment(\.fotografando) private var fotografando

    var body: some View {
        GrupoDeAjuste(titulo: "O que o Deck usa neste Mac",
                      nota: "O macOS só deixa o próprio dono liberar. \"Permitir\" faz o Deck pedir agora, e o botão dos Ajustes do Sistema abre a página certa. Esta lista se atualiza sozinha quando você volta.") {
            LinhasDeAjuste {
                ForEach(Array(modelo.acessos.enumerated()), id: \.element.id) { i, lido in
                    LinhaDeAjuste(titulo: lido.acesso.nomeNaLista, apoio: apoio(lido), divisoria: i > 0) {
                        HStack(spacing: Tema.Espaco.item) {
                            EstadoDoAcessoNaLinha(situacao: lido.situacao)
                            if lido.podePermitir {
                                BotaoDeAjuste(texto: "Permitir", estilo: .primario) { pedir(lido.acesso) }
                            }
                            BotaoDeAjuste(texto: "Abrir Ajustes do Sistema", estilo: lido.situacao == .recusado ? .primario : .secundario) { abrirAjustes(lido.acesso) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Ao abrir a seção lê de novo, mas nas fotos vale o que o modelo de exemplo diz.
        .onAppear { if !fotografando { modelo.atualizarAcessos() } }
    }

    private func abrirAjustes(_ acesso: AcessoMac) {
        if let abrir { abrir(acesso) } else { PedidosDoMac(defaults: modelo.defaults).abrirAjustes(acesso) }
    }

    private func pedir(_ acesso: AcessoMac) {
        if let permitir { permitir(acesso) } else { Task { await modelo.permitirAcesso(acesso) } }
    }

    private func apoio(_ lido: AcessoLido) -> String {
        var linhas = [lido.acesso.para]
        if case .semComoSaber(let texto) = lido.situacao { linhas.append(texto) }
        if let detalhe = lido.detalhe { linhas.append(detalhe) }
        return linhas.joined(separator: "\n")
    }
}

extension AcessoLido {
    /// "Permitir" aparece quando o macOS ainda não perguntou. A Rede Local também: o macOS não deixa conferir
    /// sem perguntar, então o botão é o jeito de saber, e continua valendo com "Recusado" guardado (a pessoa pode
    /// ter liberado depois nos Ajustes do Sistema, e só uma nova leitura limpa a resposta velha).
    var podePermitir: Bool {
        switch situacao {
        case .naoPedido: return true
        case .semComoSaber, .recusado: return acesso == .redeLocal
        default: return false
        }
    }
}

/// O estado à esquerda dos botões: o verde de "Liberado", o vermelho de "Recusado" e o cinza de "Não perguntado".
private struct EstadoDoAcessoNaLinha: View {
    var situacao: SituacaoDoAcesso

    var body: some View {
        switch situacao {
        case .liberado:
            HStack(spacing: Tema.Espaco.mini) {
                Svg(Icone.ok, lado: Tema.Inicial.liberadoIcone)
                Text("Liberado").tatile(Tema.Texto.sm, .semibold, Tema.Cor.led)
            }
            .foregroundColor(Tema.Cor.led)
        case .recusado:
            Text("Recusado").tatile(Tema.Texto.sm, .semibold, Tema.Cor.perigo)
        case .naoPedido:
            Text("Não perguntado").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
        case .semComoSaber:
            Text("Sem como conferir").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
        }
    }
}
