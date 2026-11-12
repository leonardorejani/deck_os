import SwiftUI

/// O método "WhatsApp" de Conexões: de onde o Deck lê as não lidas (App, WhatsApp Web ou automático) e, embaixo, o
/// espaço do "Conectar pelo QR". A escolha de origem é a mesma que ficava em Este Mac (config `whatsapp.origem`).
struct MetodoWhatsApp: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
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
                }
            }
            ConectarWhatsAppPeloQr()
        }
    }
}

/// O lugar do "Conectar pelo QR". Fica reservado e sem ação até a conexão por QR existir: nada aqui finge funcionar.
struct ConectarWhatsAppPeloQr: View {
    var body: some View {
        GrupoDeAjuste(titulo: nil, nota: nil) {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Conectar pelo QR", apoio: "Em breve: ler o QR do WhatsApp aqui, sem depender do navegador aberto") {
                    BotaoDeAjuste(texto: "Conectar", estilo: .secundario, desligado: true) {}
                }
            }
        }
    }
}
