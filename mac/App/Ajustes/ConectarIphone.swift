import SwiftUI
import AppKit

/// Seção "Conectar iPhone" dos Ajustes, igual ao protótipo (prototipo/mac.js, TELAS.iphone e parearHTML):
/// os aparelhos pareados e o cartão de parear com o QR, o código curto e o endereço, com os três
/// passos embaixo. O código curto vem do Pareamento do núcleo e é trocado pelo código de acesso longo
/// quando o iPhone o digita.
struct ConectarIphone: View {
    @ObservedObject var modelo: ModeloApp
    @StateObject private var codigo = CodigoDePareamento()
    @Environment(\.codigoDePareamentoFixo) private var codigoFixo
    /// Nome do Mac na rede, lido do sistema quando o servidor está no ar (o mesmo do certificado).
    @State private var nomeNaRede: String?
    @State private var confirmando = false

    private var porta: Int {
        if case .ligado(let p) = modelo.servidor { return p }
        return modelo.config.porta
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    private var endereco: String {
        ParearIphone.endereco(nomeMac: modelo.config.nomeMac, porta: porta, nomeDoServidor: nomeNaRede)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            if modelo.iphone != nil || modelo.nativo != nil {
                GrupoDeAjuste(titulo: "Aparelhos", nota: nil) {
                    LinhasDeAjuste {
                        if let iphone = modelo.iphone {
                            LinhaDeAjuste(titulo: iphone.nome, apoio: TextosDeAjuste.conexao(iphone)) {
                                BotaoDeAjuste(texto: "Desconectar", estilo: .secundario) { modelo.desconectarIphone() }
                            }
                        }
                        if let nativo = modelo.nativo {
                            LinhaDeAjuste(titulo: nativo.nome, apoio: TextosDoNativo.aparelhoNativo(nativo), divisoria: modelo.iphone != nil) {
                                BotaoDeAjuste(texto: "Desconectar", estilo: .secundario) { modelo.desconectarNativo() }
                            }
                        }
                    }
                }
            }
            GrupoDoAppNativo(modelo: modelo)
            GrupoDeAjuste(titulo: modelo.iphone != nil ? "Parear outro iPhone pelo Wi-Fi" : "Parear um iPhone pelo Wi-Fi",
                          nota: "O iPhone e o Mac precisam estar no mesmo Wi-Fi. Nada sai da sua rede.") {
                if case .falhou(let motivo) = modelo.servidor {
                    CartaoServidorFalhou(motivo: motivo) { modelo.tentarServidorDeNovo() }
                } else {
                    CartaoDeParear(codigo: ParearIphone.codigoEmGrupos(codigo.codigo), endereco: endereco,
                                   textoDoQr: ParearIphone.textoDoQr(endereco: endereco, codigo: codigo.codigo)) {
                        copiar(endereco)
                        modelo.avisar("Endereço copiado")
                    }
                    PassosDeParear().padding(.vertical, Tema.Espaco.item)
                }
                // Discreto, no fim do grupo: tira o acesso de todos os iPhones de uma vez.
                BotaoDeAjuste(texto: "Desconectar iPhones", estilo: .perigo) { confirmando = true }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { codigo.iniciar(modelo.pareamento, fixo: codigoFixo) }
        .onDisappear { codigo.parar() }
        // O Bluetooth só aceita pedido de pareamento com esta tela aberta: a janela vale 60 s e a tela a renova.
        .task {
            while !Task.isCancelled {
                modelo.janelaDePareamento.renovar()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        .confirmationDialog("Desconectar todos os iPhones?", isPresented: $confirmando, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { modelo.desconectarIphones() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todos os iPhones pareados param de funcionar e precisam parear de novo.")
        }
        .task(id: modelo.servidor) {
            guard case .ligado = modelo.servidor else { return }
            nomeNaRede = await Task.detached { try? GeradorCertificado().lerRede().nome }.value
        }
    }
}

// MARK: - Cartão de parear

private struct CartaoDeParear: View {
    var codigo: String
    var endereco: String
    var textoDoQr: String
    var copiar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espaco.pad) {
            QrDoPareamento(texto: textoDoQr)
            VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
                CampoRotulado(rotulo: "Código") {
                    VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                        Text(codigo)
                            .font(.system(size: Tema.Medida.codigoTam, weight: .bold))
                            .tracking(Tema.Texto.trackingCodigo * Tema.Medida.codigoTam)
                            .monospacedDigit()
                            .foregroundColor(Tema.Cor.texto)
                            .lineLimit(1)
                            .frame(height: Tema.Medida.codigoTam, alignment: .leading)
                        // `small` do navegador: um degrau menor que o texto ao redor.
                        Text("vale por 10 minutos").tatile(Tema.Texto.sm / Tema.Texto.menorDe, .regular, Tema.Cor.texto2)
                    }
                }
                CampoRotulado(rotulo: "Ou abra no Safari do iPhone") {
                    HStack(spacing: Tema.Espaco.item) {
                        Text(endereco)
                            .font(.system(size: Tema.Texto.xs, design: .monospaced))
                            .foregroundColor(Tema.Cor.texto)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        BotaoDeAjuste(texto: "Copiar", estilo: .secundario, monoespaco: true) { copiar() }
                    }
                    .padding(.horizontal, Tema.Espaco.icone)
                    .padding(.vertical, Tema.Espaco.item)
                    .background(Tema.Cor.telaFundo, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

/// O servidor não subiu (certificado, porta ou página): em vez de um QR que não leva a lugar nenhum,
/// o motivo e o botão para tentar de novo.
private struct CartaoServidorFalhou: View {
    var motivo: String
    var tentar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text("Não consegui abrir o Deck para o iPhone").tatile(Tema.Texto.sm, .bold, Tema.Cor.perigo)
            Text(motivo).tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2, linhas: nil)
                .fixedSize(horizontal: false, vertical: true)
            BotaoDeAjuste(texto: "Tentar de novo", estilo: .primario, acao: tentar)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

private struct CampoRotulado<Conteudo: View>: View {
    var rotulo: String
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text(rotulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            conteudo
        }
    }
}

/// O QR em quadro branco, com o desenho gerado pelo CoreImage.
private struct QrDoPareamento: View {
    var texto: String

    var body: some View {
        Group {
            if let img = ParearIphone.qr(texto) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .padding(Tema.Espaco.item)
        .frame(width: Tema.Medida.qr, height: Tema.Medida.qr)
        .background(Tema.Cor.branco, in: RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous))
        .accessibilityLabel("QR code de pareamento")
    }
}

// MARK: - Os três passos

private struct PassosDeParear: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            PassoDeParear(1, Text("No iPhone, aponte a ") + destaque("câmera") + Text(" para o código e toque no link."))
            PassoDeParear(2, Text("Instale o ") + destaque("certificado") + Text(" e ligue a confiança em Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados."))
            PassoDeParear(3, Text("No Safari, ") + destaque("Compartilhar > Adicionar à Tela de Início") + Text(". O Deck abre como app."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func destaque(_ t: String) -> Text { Text(t).fontWeight(.bold).foregroundColor(Tema.Cor.texto) }
}

struct PassoDeParear: View {
    var numero: Int
    var texto: Text

    init(_ numero: Int, _ texto: Text) { self.numero = numero; self.texto = texto }

    var body: some View {
        HStack(alignment: .top, spacing: Tema.Espaco.icone) {
            Text("\(numero)").font(.system(size: Tema.Texto.xs)).monospacedDigit().foregroundColor(Tema.Cor.texto)
                .frame(width: Tema.Medida.selo, height: Tema.Medida.selo)
                .background(Tema.Cor.superficie2, in: Circle())
            texto.font(.system(size: Tema.Texto.sm)).foregroundColor(Tema.Cor.texto2)
                .lineSpacing(Tema.Texto.sm * (Tema.Texto.altura - 1.2))
                .frame(minHeight: Tema.Texto.sm * Tema.Texto.altura, alignment: .topLeading)
                .padding(.top, Tema.Espaco.fino)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum TextosDeAjuste {
    /// "Safari, pelo Wi-Fi desde 09:12" (sem a hora quando não se sabe). Um aparelho por forma de conexão.
    static func conexao(_ iphone: IphonePareado) -> String {
        let base = "\(iphone.canal == .wifi ? "Safari" : "App nativo"), \(iphone.canal.texto)"
        guard let desde = iphone.desde else { return base }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return "\(base) desde \(f.string(from: desde))"
    }
}
