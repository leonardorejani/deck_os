import SwiftUI

/// O grupo "App no iPhone, por cabo e Bluetooth" de Conectar iPhone, igual ao protótipo (prototipo/mac.js, natSecao).
/// Sem app pareado: o pedido de pareamento (mesmo código das duas telas, Recusar e Permitir) ou o convite para
/// abrir o Deck no iPhone, e os três passos. Com app pareado: o aviso de prazo, o canal em uso e a renovação.
struct GrupoDoAppNativo: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        GrupoDeAjuste(titulo: "App no iPhone, por cabo e Bluetooth", nota: nil) {
            if let pedido = modelo.pedidoBluetooth {
                CartaoDoPedido(pedido: pedido, responder: { modelo.responderPedido(permitir: $0) })
            }
            if let nativo = modelo.nativo {
                AppNativoPareado(modelo: modelo, nativo: nativo)
            } else {
                if modelo.pedidoBluetooth == nil { CartaoVisivel() }
                PassosDoNativo()
                NotaDeAjuste(TextosDoNativo.notaDaVia)
            }
        }
    }
}

/// O que o Mac mostra quando um iPhone pede para parear: o código e os dois botões. Também é o bloco do menu.
struct CartaoDoPedido: View {
    var pedido: PedidoDePareamento
    var responder: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
            VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                Text(TextosDoNativo.pedidoRotulo(pedido.iphone)).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
                Text(ParearIphone.codigoEmGrupos(pedido.codigo))
                    .font(.system(size: Tema.Medida.codigoTam, weight: .bold))
                    .tracking(Tema.Texto.trackingCodigo * Tema.Medida.codigoTam)
                    .monospacedDigit()
                    .foregroundColor(Tema.Cor.texto)
                    .lineLimit(1)
                    .frame(height: Tema.Medida.codigoTam, alignment: .leading)
                Text(TextosDoNativo.pedidoTexto).tatile(Tema.Texto.sm / Tema.Texto.menorDe, .regular, Tema.Cor.texto2)
            }
            HStack(spacing: Tema.Espaco.item) {
                BotaoDeAjuste(texto: "Recusar", estilo: .secundario) { responder(false) }
                BotaoDeAjuste(texto: "Permitir", estilo: .primario) { responder(true) }
            }
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

private struct CartaoVisivel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.item) {
            Text(TextosDoNativo.vazioRotulo).tatile(Tema.Texto.xs, .semibold, Tema.Cor.texto2)
            VStack(alignment: .leading, spacing: Tema.Espaco.item) {
                Text(TextosDoNativo.vazioTitulo).tatile(Tema.Texto.md, .semibold)
                Text(TextosDoNativo.vazioTexto).tatile(Tema.Texto.sm / Tema.Texto.menorDe, .regular, Tema.Cor.texto2)
            }
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}

private struct PassosDoNativo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.icone) {
            PassoDeParear(1, Text("Abra o ") + destaque("Deck") + Text(" no iPhone e toque em ") + destaque("Procurar por perto") + Text("."))
            PassoDeParear(2, Text("Toque no nome deste Mac na lista."))
            PassoDeParear(3, Text("Veja se o ") + destaque("código é o mesmo") + Text(" nas duas telas e toque em Permitir aqui."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Tema.Espaco.item)
    }

    private func destaque(_ t: String) -> Text { Text(t).fontWeight(.bold).foregroundColor(Tema.Cor.texto) }
}

private struct AppNativoPareado: View {
    @ObservedObject var modelo: ModeloApp
    var nativo: AppNativo

    var body: some View {
        // O relógio da tela: "agora" vira "há 1 min" sem ninguém mexer.
        TimelineView(.periodic(from: .now, by: 15)) { contexto in
            let agora = modelo.relogio?() ?? contexto.date
            let estado = modelo.renovacao.estado(agora: agora)
            VStack(alignment: .leading, spacing: Tema.Espaco.grade) {
                if case .apertando(let vence) = estado, modelo.nativo != nil {
                    AlertaDaRenovacao(vence: vence, agora: agora) { modelo.renovarAppNativo() }
                }
                LinhasDeAjuste {
                    LinhaDeAjuste(titulo: "App no iPhone", apoio: TextosDoNativo.instalado(modelo.renovacao)) {
                        if let v = modelo.renovacao.versao { ValorDeAjuste(v) }
                    }
                    LinhaDeAjuste(titulo: "Último canal", apoio: TextosDoNativo.canalApoio, divisoria: true) {
                        ValorDeAjuste(TextosDoNativo.ultimoCanal(nativo, agora: agora))
                    }
                    LinhaDeAjuste(titulo: "Renovação automática", apoio: TextosDoNativo.renovacaoApoio, divisoria: true) {
                        HStack(spacing: Tema.Espaco.item) {
                            if case .apertando = estado {
                                Text(TextosDoNativo.renovacao(estado, agora: agora)).tatile(Tema.Texto.sm, .regular, Tema.Cor.aviso)
                            } else {
                                ValorDeAjuste(TextosDoNativo.renovacao(estado, agora: agora))
                            }
                            BotaoDeAjuste(texto: "Renovar agora", estilo: .secundario) { modelo.renovarAppNativo() }
                        }
                    }
                }
                NotaDeAjuste(TextosDoNativo.renovacaoCondicoes)
            }
        }
    }
}

/// O cartão amarelo (`.alerta-linha`): só aparece com o prazo apertando sem a renovação ter dado certo.
private struct AlertaDaRenovacao: View {
    var vence: Date
    var agora: Date
    var tentar: () -> Void

    var body: some View {
        HStack(spacing: Tema.Espaco.icone) {
            Svg(Icone.alerta, lado: Tema.Medida.icSec).foregroundColor(Tema.Cor.aviso)
            VStack(alignment: .leading, spacing: Tema.Espaco.fino) {
                Text(TextosDoNativo.alertaDaRenovacao(vence, agora: agora)).tatile(Tema.Texto.sm, .bold, Tema.Cor.texto, linhas: nil)
                Text(TextosDoNativo.alertaApoio).tatile(Tema.Texto.xs, .regular, Tema.Cor.texto2, linhas: nil)
                    .lineSpacing(Tema.Texto.xs * (Tema.Texto.altura - 1.2))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            BotaoDeAjuste(texto: "Tentar agora", estilo: .primario, acao: tentar)
        }
        .padding(Tema.Espaco.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie()
    }
}
