import SwiftUI
import AppKit

/// Em Este Mac: a chave e o exemplo de curl para scripts deste Mac mandarem aviso ou valor ao iPhone. A porta só abre no próprio
/// Mac (127.0.0.1) e a chave não é o código do iPhone.
struct AjustesAvisosDeFora: View {
    @ObservedObject var modelo: ModeloApp
    @State private var chave: String

    init(modelo: ModeloApp) {
        self.modelo = modelo
        _chave = State(initialValue: modelo.chaveDeFora.atual())
    }

    private var porta: Int { modelo.portaDeFora ?? Variante.atual.portaDeFora }

    var body: some View {
        GrupoDeAjuste(titulo: "Avisos de fora", nota: modelo.portaDeFora == nil ? "A porta dos avisos de fora não abriu. Feche e abra o Deck de novo." : "Um script deste Mac manda o aviso e o iPhone mostra. Os valores vão para a tecla Valores. A porta só abre neste Mac.") {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Chave", apoio: "Não é o código do iPhone") {
                    HStack(spacing: Tema.Espaco.item) {
                        Text(chave).font(.system(size: Tema.Texto.xs, design: .monospaced)).foregroundColor(Tema.Cor.texto2)
                            .lineLimit(1).textSelection(.enabled)
                        BotaoDeAjuste(texto: "Copiar") { copiar(chave, "Chave copiada") }
                    }
                }
                LinhaDeAjuste(titulo: "Exemplo de aviso", apoio: "Cole no Terminal para testar", divisoria: true) {
                    BotaoDeAjuste(texto: "Copiar") { copiar(ExemploDeFora.curlAviso(porta: porta, chave: chave), "Exemplo copiado") }
                }
                LinhaDeAjuste(titulo: "Exemplo de valor", apoio: "Fica na tecla Valores até vencer", divisoria: true) {
                    BotaoDeAjuste(texto: "Copiar") { copiar(ExemploDeFora.curlValor(porta: porta, chave: chave), "Exemplo copiado") }
                }
                LinhaDeAjuste(titulo: "Trocar a chave", apoio: "Quem usa a chave de agora para de funcionar", divisoria: true) {
                    BotaoDeAjuste(texto: "Trocar", estilo: .secundario) {
                        chave = modelo.chaveDeFora.trocar()
                        modelo.avisar("Chave trocada")
                    }
                }
            }
        }
    }

    private func copiar(_ texto: String, _ aviso: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        modelo.avisar(aviso)
    }
}
