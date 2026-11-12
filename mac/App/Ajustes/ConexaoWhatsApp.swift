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
            ConectarWhatsAppPeloQr(modelo: modelo)
        }
    }
}

/// "Conectar pelo QR": o WhatsApp como aparelho conectado (ajudante de leitura, desligado por padrão). O aviso de que não
/// é oficial fica sempre à vista. O conteúdo está em `GrupoWhatsAppQR`.
struct ConectarWhatsAppPeloQr: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        GrupoDeAjuste(titulo: nil, nota: nil) {
            LinhasDeAjuste {
                GrupoWhatsAppQR(modelo: modelo)
            }
        }
    }
}
