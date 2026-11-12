import SwiftUI

/// O grupo "Agenda" de Este Mac: onde "Novo compromisso" do iPhone salva quando a pessoa não escolhe.
/// A lista vem do Calendário e dos Lembretes do Mac. Abrir os Ajustes nunca pergunta acesso: para os
/// Lembretes, o botão "Liberar Lembretes" é que abre a janela do macOS.
struct GrupoAgenda: View {
    @ObservedObject var modelo: ModeloApp
    @State private var destinos: DestinosDaAgenda?
    private let criador = CriadorEventKit()

    var body: some View {
        GrupoDeAjuste(titulo: "Agenda", nota: nil) {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Salvar compromissos em", apoio: apoio) {
                    VStack(alignment: .trailing, spacing: Tema.Espaco.item) {
                        Quebra(espaco: Tema.Espaco.item) {
                            BotaoDeAjuste(texto: "Perguntar toda vez", estilo: modelo.config.agendaPadrao == nil ? .primario : .secundario) {
                                modelo.gravar { $0.agendaPadrao = nil }
                            }
                            ForEach(opcoes, id: \.destino) { o in
                                BotaoDeAjuste(texto: o.texto, estilo: modelo.config.agendaPadrao == o.destino ? .primario : .secundario) {
                                    modelo.gravar { $0.agendaPadrao = o.destino }
                                }
                            }
                        }
                        if destinos?.permissaoLembretes == "pedir" {
                            BotaoDeAjuste(texto: "Liberar Lembretes", estilo: .secundario) {
                                CriadorEventKit.pedir(.reminder)
                                Task { try? await Task.sleep(nanoseconds: 4_000_000_000); carregar() }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { carregar() }
    }

    private struct Opcao { var destino: DestinoAgenda; var texto: String }

    private var opcoes: [Opcao] {
        guard let d = destinos else { return [] }
        return d.calendarios.map { Opcao(destino: DestinoAgenda(tipo: "calendario", id: $0.id), texto: "Calendário: \($0.nome)") }
            + d.listas.map { Opcao(destino: DestinoAgenda(tipo: "lembretes", id: $0.id), texto: "Lembretes: \($0.nome)") }
    }

    private var apoio: String {
        guard let d = destinos else { return "Lendo os calendários do Mac" }
        if d.permissaoCalendario == "recusado" { return "O Deck está sem acesso ao Calendário. Libere em Acessos do Mac" }
        if d.permissaoLembretes == "recusado" { return "O Deck está sem acesso aos Lembretes. Libere em Ajustes do Sistema > Privacidade" }
        return "Onde o \"Novo compromisso\" do iPhone grava sem perguntar. Pode ser um calendário ou uma lista dos Lembretes"
    }

    private func carregar() {
        let c = criador
        Task.detached { let d = c.destinos(pedirPermissao: false); await MainActor.run { destinos = d } }
    }
}
