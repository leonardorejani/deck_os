import SwiftUI

/// WhatsApp por QR, as linhas do cartão "Conectar pelo QR" em Conexões > WhatsApp. Nasce desligado. O aviso fica sempre à vista,
/// antes e depois de ligar: a opção não é oficial. Ligada, mostra o QR, o estado e os botões.
struct GrupoWhatsAppQR: View {
    @ObservedObject var modelo: ModeloApp
    @ObservedObject private var qr: ModeloWhatsAppQR
    @State private var confirmandoApagar = false

    init(modelo: ModeloApp) {
        self.modelo = modelo
        self.qr = modelo.whatsappQR
    }

    private var ligado: Bool { modelo.config.whatsapp.origem == "qr" }

    var body: some View {
        Group {
            LinhaDeAjuste(titulo: "Conectar pelo QR (aparelho conectado)", apoio: TextosWhatsAppQR.aviso) {
                ChaveDeAjuste(rotulo: "Conectar pelo QR", ligada: ligado) { ligar in
                    if ligar {
                        modelo.gravar { $0.whatsapp.origem = "qr" }
                        qr.ligar()
                    } else {
                        modelo.gravar { $0.whatsapp.origem = "auto" }
                        qr.desligar()
                    }
                }
            }
            if ligado { corpo }
        }
        .onAppear { if ligado { qr.ligar() } }
    }

    @ViewBuilder private var corpo: some View {
        let e = qr.estado
        LinhaDeAjuste(titulo: "Situação", apoio: e.fase == .aguardandoQR ? TextosWhatsAppQR.passos : nil, divisoria: true) {
            HStack(spacing: Tema.Espaco.item) {
                ValorDeAjuste(TextosWhatsAppQR.situacao(e))
                if e.fase == .qrExpirou || e.fase == .erro {
                    BotaoDeAjuste(texto: "Gerar outro QR", estilo: .primario, desligado: !qr.disponivel) { qr.gerarOutroQR() }
                }
            }
        }
        if let codigo = e.qr, e.fase == .aguardandoQR {
            HStack {
                Spacer(minLength: 0)
                QrDoWhatsApp(texto: codigo)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Tema.Espaco.pad)
            .overlay(alignment: .top) { Rectangle().fill(Tema.Cor.borda).frame(height: 1) }
        }
        if qr.ponte.temSessao || e.fase == .conectado {
            LinhaDeAjuste(titulo: "Apagar este aparelho", apoio: "Sai do aparelho no WhatsApp e apaga a sessão guardada neste Mac. Para entrar de novo, leia um QR novo", divisoria: true) {
                if confirmandoApagar {
                    HStack(spacing: Tema.Espaco.item) {
                        BotaoDeAjuste(texto: "Cancelar", estilo: .secundario) { confirmandoApagar = false }
                        BotaoDeAjuste(texto: "Apagar", estilo: .perigo) { confirmandoApagar = false; qr.apagarSessao() }
                    }
                } else {
                    BotaoDeAjuste(texto: "Apagar", estilo: .perigo) { confirmandoApagar = true }
                }
            }
        }
    }
}

private struct QrDoWhatsApp: View {
    var texto: String

    var body: some View {
        Group {
            if let img = ParearIphone.qr(texto, modulo: 4) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .padding(Tema.Espaco.item)
        .frame(width: Tema.Medida.qr + 56, height: Tema.Medida.qr + 56)
        .background(Tema.Cor.branco, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
        .accessibilityLabel("QR code do WhatsApp")
    }
}
