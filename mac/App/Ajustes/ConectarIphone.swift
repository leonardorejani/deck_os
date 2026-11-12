import SwiftUI
import AppKit

/// Seção "Conexões" dos Ajustes (antes "Conectar iPhone"). No topo, o método (Cabo e Bluetooth, WhatsApp ou PWA pelo
/// Wi-Fi) e embaixo só o que é daquele método. O Spotify, que é um login à parte, fica no fim, sempre à mão.
/// O que diz se há iPhone e se ele está falando é sempre `modelo.iphoneAtivo` (uma fonte só, a mesma do cabeçalho,
/// do menu e do Sobre). O código curto do PWA vem do Pareamento do núcleo e é trocado pelo código de acesso longo
/// quando o iPhone o digita. Cada tela mostra um código só: o do pedido de Bluetooth, ou o do cabo, ou o do PWA.
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

    /// O código curto só existe enquanto uma tela que o mostra está aberta (cabo, sem pedido de Bluetooth, e PWA).
    private var precisaDeCodigo: Bool {
        switch modelo.metodoDeConexao {
        case .pwa: return true
        case .cabo: return modelo.pedidoBluetooth == nil && modelo.nativo == nil
        case .whatsapp: return false
        }
    }

    private func acertarCodigo() {
        if precisaDeCodigo { codigo.iniciar(modelo.pareamento, fixo: codigoFixo) } else { codigo.parar() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.secao) {
            SeletorDeMetodo(escolhido: modelo.metodoDeConexao, aoVivo: aoVivoPorMetodo) { modelo.metodoDeConexao = $0 }
            switch modelo.metodoDeConexao {
            case .cabo: MetodoCaboEBluetooth(modelo: modelo, codigo: ParearIphone.codigoEmGrupos(codigo.codigo))
            case .whatsapp: MetodoWhatsApp(modelo: modelo)
            case .pwa: metodoPwa
            }
            GrupoSpotify(spotify: modelo.spotify)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { acertarCodigo() }
        .onChange(of: modelo.metodoDeConexao) { _ in acertarCodigo() }
        .onChange(of: precisaDeCodigo) { _ in acertarCodigo() }
        // Um pedido de Bluetooth chegou com outro método aberto: leva a pessoa para onde ele aparece.
        .onChange(of: modelo.pedidoBluetooth) { novo in if novo != nil { modelo.metodoDeConexao = .cabo } }
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

    /// O ponto verde de cada método: só quando há aparelho daquele método falando agora (mesma fonte do cabeçalho).
    private var aoVivoPorMetodo: Set<MetodoDeConexao> {
        let agora = modelo.agora
        var r = Set<MetodoDeConexao>()
        if let n = modelo.nativo, IphonePareado(nome: n.nome, canal: n.canal, visto: n.visto).aoVivo(agora: agora) { r.insert(.cabo) }
        if let i = modelo.iphone, i.aoVivo(agora: agora) { r.insert(.pwa) }
        return r
    }

    @ViewBuilder private var metodoPwa: some View {
        if let iphone = modelo.iphone {
            GrupoDeAjuste(titulo: "Aparelho", nota: nil) {
                LinhasDeAjuste {
                    LinhaDeAjuste(titulo: iphone.nome, apoio: TextosDeAjuste.conexao(iphone, agora: modelo.agora)) {
                        BotaoDeAjuste(texto: "Desconectar", estilo: .secundario) { modelo.desconectarIphone() }
                    }
                }
            }
        }
        GrupoDeAjuste(titulo: modelo.iphone != nil ? "Parear outro iPhone pelo Wi-Fi" : "Parear um iPhone pelo Wi-Fi",
                      nota: TextosDeAjuste.notaDoWifi) {
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
}

/// O seletor do topo: um segmento por método, o escolhido em destaque e um ponto verde no que está falando agora.
struct SeletorDeMetodo: View {
    var escolhido: MetodoDeConexao
    var aoVivo: Set<MetodoDeConexao>
    var escolher: (MetodoDeConexao) -> Void

    var body: some View {
        HStack(spacing: Tema.Espaco.fino) {
            ForEach(MetodoDeConexao.allCases) { m in Segmento(metodo: m, selecionado: m == escolhido, aoVivo: aoVivo.contains(m)) { escolher(m) } }
        }
        .padding(Tema.Espaco.fino)
        .frame(maxWidth: .infinity)
        .superficie(raio: Tema.Raio.normal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Método de conexão")
    }

    private struct Segmento: View {
        var metodo: MetodoDeConexao
        var selecionado: Bool
        var aoVivo: Bool
        var acao: () -> Void

        var body: some View {
            let forma = RoundedRectangle(cornerRadius: Tema.Raio.sm, style: .continuous)
            Button(action: acao) {
                HStack(spacing: Tema.Espaco.item) {
                    Text(metodo.rotulo).font(.system(size: Tema.Texto.sm, weight: selecionado ? .semibold : .regular))
                    if aoVivo { Ponto(ligado: true).accessibilityLabel("falando agora") }
                }
                .foregroundColor(selecionado ? Tema.Cor.texto : Tema.Cor.texto2)
                .frame(maxWidth: .infinity, minHeight: Tema.Espaco.alvoSm)
                .background {
                    if selecionado { ZStack { forma.fill(Tema.Cor.anel).padding(-1); forma.fill(Tema.Cor.superficie2) } }
                }
                .contentShape(forma)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selecionado ? .isSelected : [])
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
    /// Explica o que o Wi-Fi (PWA) tem a menos que o app nativo. Cada diferença existe no código:
    /// cabo e Bluetooth só na casca nativa (SPEC 13, item 9), e a tela acesa é da casca (painel/pwa.js só pede o Wake Lock no Safari).
    static let notaDoWifi = "Pelo Wi-Fi o iPhone usa o Deck como app da Tela de Início (PWA), e por isso funcionam menos coisas. Só funciona com o iPhone na mesma rede do Mac, não conecta por cabo nem por Bluetooth, deixa de atualizar quando o iPhone sai do Wi-Fi e a tela pode apagar sozinha. Para ter tudo isso, use o app no iPhone, em Cabo e Bluetooth. Nada sai da sua rede."

    /// "Safari, pelo Wi-Fi desde 09:12" (sem a hora quando não se sabe). Um aparelho por forma de conexão.
    /// Sem falar com o Mac faz mais de 30 s, diz que está fora de alcance em vez de fingir que está conectado.
    static func conexao(_ iphone: IphonePareado, agora: Date = Date()) -> String {
        let quem = iphone.canal == .wifi ? "Safari" : "App nativo"
        guard iphone.aoVivo(agora: agora) else { return "\(quem), pareado e fora de alcance agora" }
        let base = "\(quem), \(iphone.canal.texto)"
        guard let desde = iphone.desde else { return base }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return "\(base) desde \(f.string(from: desde))"
    }
}
