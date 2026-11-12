import SwiftUI
import AppKit

/// O que a seção Sobre mostra: versão e data. Sai do app em uso, ou de dados de exemplo nas fotos.
struct InformacoesDoApp: Equatable {
    var versao: String
    var compilacao: String
    var atualizadoEm: Date
    var macOS: String

    /// "0.1 (1)": a versão com o número da compilação.
    var versaoComCompilacao: String { "\(versao) (\(compilacao))" }

    /// "10 de novembro de 2026".
    var dataPorExtenso: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f.string(from: atualizadoEm)
    }

    static func doApp(_ bundle: Bundle = .main, sistema: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> InformacoesDoApp {
        let info = bundle.infoDictionary ?? [:]
        let data = bundle.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } ?? Date()
        return InformacoesDoApp(versao: info["CFBundleShortVersionString"] as? String ?? "0",
                                compilacao: info["CFBundleVersion"] as? String ?? "0",
                                atualizadoEm: data, macOS: "macOS \(sistema.majorVersion)")
    }

}

/// Os endereços do projeto aberto no GitHub. Abrem no navegador padrão (NSWorkspace).
enum LinksDoProjeto {
    private static let repositorio = URL(string: "https://github.com/leonardorejani/deck_os")!
    /// A página do repositório é o lugar da estrela: o botão "Star" fica no topo dela.
    static let estrela = repositorio
    static let problema = URL(string: "https://github.com/leonardorejani/deck_os/issues/new")!
}

private struct ChaveInformacoes: EnvironmentKey { static let defaultValue: InformacoesDoApp? = nil }

extension EnvironmentValues {
    /// Só nas fotos: a versão e a data de exemplo, para a foto sair igual à do protótipo em qualquer dia.
    var informacoesDoAppFixas: InformacoesDoApp? {
        get { self[ChaveInformacoes.self] }
        set { self[ChaveInformacoes.self] = newValue }
    }
}

/// Seção "Sobre o Deck" dos Ajustes (prototipo/mac.js, TELAS.sobre): o cartão do app, a versão e o projeto aberto no
/// GitHub (estrela e problema). A licença fica só no texto do grupo. Sem título em cima (a janela abre direto no cartão)
/// e sem linha de Mac ou iPhone: quem diz se há iPhone conectado é Conexões. A assinatura fica no rodapé da barra lateral.
struct Sobre: View {
    @ObservedObject var modelo: ModeloApp
    /// Abre o endereço no navegador padrão. Os testes trocam por um que só anota.
    var abrir: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @Environment(\.informacoesDoAppFixas) private var fixas
    private var informacoes: InformacoesDoApp { fixas ?? InformacoesDoApp.doApp() }

    var body: some View {
        VStack(alignment: .leading, spacing: Tema.Espaco.pad) {
            HStack(spacing: Tema.Espaco.pad) {
                Logo(lado: Tema.Medida.logoGrande)
                    .shadow(color: Tema.Cor.sucessoSuave, radius: Tema.Sombra.difusaRaio - 1, y: Tema.Espaco.item)
                VStack(alignment: .leading, spacing: Tema.Espaco.micro) {
                    Text("Deck")
                        .font(.system(size: Tema.Texto.xl, weight: .bold))
                        .tracking(Tema.Texto.trackingTitulo(Tema.Texto.xl))
                        .foregroundColor(Tema.Cor.texto)
                        .frame(height: Tema.Texto.xl * Tema.Texto.alturaTitulo, alignment: .leading)
                    Text("Painel de mesa no iPhone para controlar o Mac.").tatile(Tema.Texto.sm, .regular, Tema.Cor.texto2)
                }
            }
            .padding(.vertical, Tema.Espaco.item)
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Versão", apoio: "A mais recente") { ValorDeAjuste(informacoes.versaoComCompilacao) }
                LinhaDeAjuste(titulo: "Atualizado em", apoio: nil, divisoria: true) { ValorDeAjuste(informacoes.dataPorExtenso) }
            }
            GrupoDeAjuste(titulo: "Projeto aberto", nota: "O Deck é código aberto, com licença MIT. Uma estrela ajuda outras pessoas a achar o projeto.") {
                LinhasDeAjuste {
                    LinhaDeAjuste(titulo: "Gostou do Deck?", apoio: "Abre a página do projeto no GitHub") {
                        BotaoDeAjuste(texto: "Dar uma estrela no GitHub", estilo: .estrela, icone: "star.fill") { abrir(LinksDoProjeto.estrela) }
                    }
                    LinhaDeAjuste(titulo: "Achou um erro?", apoio: "Abre o formulário de problema no GitHub", divisoria: true) {
                        BotaoDeAjuste(texto: "Relatar um problema", estilo: .secundario) { abrir(LinksDoProjeto.problema) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
