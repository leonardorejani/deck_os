import Foundation
#if os(macOS)
import ApplicationServices
#endif

// "Responder no Mac" sem mexer na página (13/11/2026). Trocar o endereço da aba para /send?phone=... recarrega o WhatsApp
// Web inteiro e o Chrome pergunta "Sair do site?". Agora a aba que já está aberta é trazida para a frente e a conversa
// abre pela busca do próprio WhatsApp Web, achada na árvore de Acessibilidade do navegador: o Deck foca o campo de busca
// da lista de conversas, escreve o nome (ou o número) e aperta Enter, que abre o primeiro resultado. O endereço da aba
// não muda e a página não recarrega. Só se escreve num campo que a Acessibilidade confirma como a busca: nunca no campo
// de mensagem, e nunca com dois candidatos.

/// O que um campo de texto da página diz de si (título, descrição, dica e texto de exemplo).
struct CampoWeb: Equatable, Sendable {
    var rotulos: [String]
}

enum CampoDoWhatsApp {
    private static func normalizar(_ texto: String) -> String {
        texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// O campo de mensagem da conversa nunca serve ("Digite uma mensagem", "Type a message").
    private static let mensagem = #"(mensagem|message|mensaje)"#
    /// "Pesquisar ou começar uma nova conversa" e os equivalentes em inglês e espanhol. As versões mais novas do
    /// WhatsApp Web chamam o campo de "Search input textbox" ("Caixa de texto de pesquisa"): ficam como segunda opção
    /// e só valem com um único candidato na página.
    private static let busca = [
        #"(comecar|iniciar) (uma )?nova conversa"#,
        #"start (a )?new chat"#,
        #"^buscar un chat o iniciar (uno|un chat) nuevo$"#,
        #"^search input textbox$"#,
        #"^caixa de (texto|entrada) de (pesquisa|busca)$"#,
        #"^cuadro de (texto|entrada) de busqueda$"#,
    ]

    static func ehBusca(_ rotulo: String) -> Bool {
        let t = normalizar(rotulo)
        if t.range(of: mensagem, options: .regularExpression) != nil { return false }
        return busca.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    static func ehBusca(_ campo: CampoWeb) -> Bool { campo.rotulos.contains { ehBusca($0) } }

    /// O que se escreve na busca: o nome da conversa (grupo ou contato), ou o número de quem não tem nome. Nome que é só
    /// o rótulo de reserva do Deck ("Contato", "Grupo") ou só um número não vale: aí vai o número, se houver.
    static func termo(nome: String?, numero: String?) -> String? {
        let n = (nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.contains(where: \.isLetter), n != "Contato", n != "Grupo" {
            return String(n.filter { !$0.isNewline }.prefix(80))
        }
        let d = (numero ?? "").filter { $0.isASCII && $0.isNumber }
        return (8...15).contains(d.count) ? d : nil
    }
}

enum ResultadoBusca: Equatable, Sendable {
    /// Escreveu na busca e apertou Enter.
    case aberta
    /// O Deck não tem o acesso de Acessibilidade.
    case semAcesso
    /// Não achou o campo de busca (página ainda carregando, tela do QR, ou o WhatsApp mudou o rótulo).
    case semCampo
    /// Mais de um campo parece a busca: não escreve em nenhum.
    case ambiguo
    /// O foco não ficou no campo de busca: não escreve nada.
    case naoFocou
}

/// Quem acha o campo de busca na árvore do navegador e escreve nele. Só o macOS responde de verdade.
protocol BuscaNaPagina: Sendable {
    /// Procura o campo por até `aguardar` segundos (a página pode estar carregando), foca, escreve `texto` e aperta Enter.
    func pesquisar(pid: Int32, texto: String, aguardar: TimeInterval) -> ResultadoBusca
}

enum BuscaPadrao {
    static func para(_ executor: any Executor) -> (any BuscaNaPagina)? {
        #if os(macOS)
        return executor is ExecutorShell ? AcessibilidadeReal.compartilhada : nil
        #else
        return nil
        #endif
    }
}

#if os(macOS)
extension AcessibilidadeReal: BuscaNaPagina {
    private static let papeisDeTexto: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private enum Achado { case campo(AXUIElement), nenhum, ambiguo }

    private func rotulosDoCampo(_ el: AXUIElement) -> [String] {
        ["AXTitle", "AXDescription", "AXHelp", "AXPlaceholderValue"].compactMap { texto(el, $0) }
    }

    /// O único campo de texto que se diz busca de conversas. Em profundidade, até o limite de nós e o prazo.
    private func localizarBusca(_ app: AXUIElement) -> Achado {
        let prazo = Date().addingTimeInterval(Self.limiteDeSegundos + 1)
        var candidatos: [AXUIElement] = []
        for janela in janelasDe(app) {
            var pilha: [AXUIElement] = [janela]
            var vistos = 0
            while let el = pilha.popLast(), vistos < 30000, Date() < prazo {
                vistos += 1
                if let papel = texto(el, "AXRole"), Self.papeisDeTexto.contains(papel) {
                    if CampoDoWhatsApp.ehBusca(CampoWeb(rotulos: rotulosDoCampo(el))), !candidatos.contains(where: { CFEqual($0, el) }) {
                        candidatos.append(el)
                    }
                    continue
                }
                pilha.append(contentsOf: filhos(el).reversed())
            }
            if !candidatos.isEmpty { break } // a aba do WhatsApp está numa janela só
        }
        switch candidatos.count {
        case 0: return .nenhum
        case 1: return .campo(candidatos[0])
        default: return .ambiguo
        }
    }

    private func focoEstaNo(_ campo: AXUIElement, app: AXUIElement) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXFocusedUIElement" as CFString, &v) == .success, let f = v,
              CFGetTypeID(f) == AXUIElementGetTypeID() else { return false }
        return CFEqual(f, campo)
    }

    private func valorDe(_ campo: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(campo, "AXValue" as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func tecla(_ pid: Int32, _ codigo: CGKeyCode, comando: Bool = false) {
        for baixo in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: codigo, keyDown: baixo) else { continue }
            if comando { e.flags = .maskCommand }
            e.postToPid(pid)
        }
    }

    private func escrever(_ pid: Int32, _ texto: String) {
        var unidades = Array(texto.utf16)[...]
        while !unidades.isEmpty {
            let pedaco = Array(unidades.prefix(16)); unidades = unidades.dropFirst(pedaco.count)
            for baixo in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: baixo) else { continue }
                e.keyboardSetUnicodeString(stringLength: pedaco.count, unicodeString: pedaco)
                e.postToPid(pid)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func pesquisar(pid: Int32, texto: String, aguardar: TimeInterval) -> ResultadoBusca {
        guard AXIsProcessTrusted() else { return .semAcesso }
        let app = aplicacao(pid)
        if liberarArvore(app, pid: pid) { Thread.sleep(forTimeInterval: 0.5) }
        let limite = Date().addingTimeInterval(aguardar)
        var campo: AXUIElement?
        while true {
            switch localizarBusca(app) {
            case .campo(let c): campo = c
            case .ambiguo: return .ambiguo
            case .nenhum: break
            }
            if campo != nil || Date() >= limite { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let campo else { return .semCampo }
        // Foco no campo confirmado, e só com o foco nele se escreve (conferido antes de cada passo).
        guard AXUIElementSetAttributeValue(campo, "AXFocused" as CFString, kCFBooleanTrue) == .success else { return .naoFocou }
        Thread.sleep(forTimeInterval: 0.2)
        guard focoEstaNo(campo, app: app) else { return .naoFocou }
        tecla(pid, 0, comando: true) // Cmd+A: o que sobrou de uma busca antiga é trocado pelo texto novo
        Thread.sleep(forTimeInterval: 0.05)
        guard focoEstaNo(campo, app: app) else { return .naoFocou }
        escrever(pid, texto)
        // Espera o campo mostrar o texto (e a lista filtrar) antes do Enter.
        let ate = Date().addingTimeInterval(2)
        while Date() < ate, let v = valorDe(campo), v != texto { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: 0.6)
        guard focoEstaNo(campo, app: app) else { return .naoFocou }
        tecla(pid, 36) // Enter: abre o primeiro resultado
        return .aberta
    }
}
#endif
