import Foundation

// A lógica pura da seção "Suas teclas" (sem tela nem disco): paginar, reordenar, soltar numa aba,
// nomear e escrever a combinação de teclas. Espelha prototipo/mac.js (porPaginaMac, drop, nomes).

/// Os quatro tipos de tecla (o campo `tipo` do config.json) com o texto de cada cartão do passo 1.
enum TipoDeTecla: String, CaseIterable, Identifiable {
    case app, tecla, comando, atalho

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .app: return "App"
        case .tecla: return "Teclado"
        case .comando: return "Comando"
        case .atalho: return "Atalho"
        }
    }

    var diz: String {
        switch self {
        case .app: return "Abre um app"
        case .tecla: return "Aperta teclas"
        case .comando: return "Roda no Terminal"
        case .atalho: return "Roda um atalho"
        }
    }

    /// Título do passo 2.
    var tituloDoPasso: String {
        switch self {
        case .app: return "Qual app abre"
        case .tecla: return "Qual combinação"
        case .comando: return "Qual comando"
        case .atalho: return "Qual atalho do app Atalhos roda"
        }
    }

    /// Tipo "painel" de config antiga já vira app na leitura. Qualquer tipo desconhecido cai em app.
    static func de(_ texto: String) -> TipoDeTecla { TipoDeTecla(rawValue: texto) ?? .app }
}

enum LogicaTeclas {
    static let nomePadrao = "Nova tecla"

    /// Quantas teclas cabem numa página do iPhone: 5 na composição A, 9 na B.
    static func porPagina(comp: String) -> Int { comp == "b" ? 9 : 5 }

    /// Páginas em fatias. Sempre ao menos uma (vazia), para o "Nova" ter onde ficar.
    static func paginas(_ teclas: [Tecla], porPagina: Int) -> [[Tecla]] {
        var r: [[Tecla]] = []
        var i = 0
        while i < teclas.count { r.append(Array(teclas[i..<min(i + porPagina, teclas.count)])); i += porPagina }
        return r.isEmpty ? [[]] : r
    }

    static func paginaDe(indice: Int, porPagina: Int) -> Int { max(0, indice) / porPagina }

    /// Arrastar uma tecla para a posição de outra (ela fica no lugar da outra, como no protótipo).
    static func mover(_ teclas: [Tecla], id: String, para alvo: String) -> [Tecla] {
        guard id != alvo, let de = teclas.firstIndex(where: { $0.id == id }), let para = teclas.firstIndex(where: { $0.id == alvo }) else { return teclas }
        var novas = teclas
        let item = novas.remove(at: de)
        novas.insert(item, at: para)
        return novas
    }

    /// Soltar numa aba de página: a tecla vai para o fim daquela página.
    static func soltarNaPagina(_ teclas: [Tecla], id: String, pagina: Int, porPagina: Int) -> [Tecla] {
        guard let de = teclas.firstIndex(where: { $0.id == id }) else { return teclas }
        var novas = teclas
        let item = novas.remove(at: de)
        novas.insert(item, at: min((pagina + 1) * porPagina - 1, novas.count))
        return novas
    }

    /// Sem acento e sem maiúscula, para a busca de app e de atalho.
    static func semAcento(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    static func filtrar<T>(_ itens: [T], busca: String, nome: (T) -> String) -> [T] {
        let q = semAcento(busca.trimmingCharacters(in: .whitespaces))
        return q.isEmpty ? itens : itens.filter { semAcento(nome($0)).contains(q) }
    }

    /// O nome da tecla acompanha o que a pessoa escolheu enquanto ela não deu um nome próprio.
    static func nomeAposEscolher(atual: String, escolhido: String, nomesDeApps: Set<String> = []) -> String {
        let a = atual.trimmingCharacters(in: .whitespaces)
        return a.isEmpty || a == nomePadrao || nomesDeApps.contains(a) ? escolhido : atual
    }

    static func idNovo(prefixo: String, existentes: [String], agora: Date = Date()) -> String {
        var n = Int(agora.timeIntervalSince1970 * 1000)
        while existentes.contains("\(prefixo)\(n)") { n += 1 }
        return "\(prefixo)\(n)"
    }

    /// Depois de excluir a tecla de índice `i`, a vizinha que fica escolhida.
    static func escolhidaApos(excluir i: Int, restantes: [Tecla]) -> String? {
        restantes.isEmpty ? nil : restantes[min(i, restantes.count - 1)].id
    }
}

/// Texto da combinação ("ctrl+opt+cmd+k") e o nome que cada peça mostra no gravador.
enum CombinacaoEmTexto {
    static let nomesDosModificadores: [String: String] = ["ctrl": "⌃ control", "opt": "⌥ option", "cmd": "⌘ command", "shift": "⇧ shift", "fn": "fn"]

    static func pecas(_ valor: String) -> [String] {
        valor.split(separator: "+").map { String($0) }.map { nomesDosModificadores[$0] ?? $0.uppercased() }
    }

    /// Nome da tecla a partir do código virtual do macOS (mora no núcleo, junto da tabela de códigos).
    static func nome(doCodigo codigo: UInt16) -> String? { Teclas.nome(doCodigo: codigo) }

    enum Resultado: Equatable {
        case cancelou
        case faltaControle
        case ignorar
        case gravou(String)
    }

    /// Interpreta uma tecla apertada no gravador. Esc cancela, só modificador espera a próxima, e a
    /// combinação precisa de pelo menos uma tecla de controle.
    static func interpretar(codigo: UInt16, controle: Bool, opcao: Bool, comando: Bool, shift: Bool) -> Resultado {
        if codigo == 53 { return .cancelou }
        let somenteModificador: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if somenteModificador.contains(codigo) { return .ignorar }
        if !controle && !opcao && !comando && !shift { return .faltaControle }
        var mods: Modificadores = []
        if controle { mods.insert(.controle) }
        if opcao { mods.insert(.opcao) }
        if comando { mods.insert(.comando) }
        if shift { mods.insert(.shift) }
        guard let base = nome(doCodigo: codigo), let texto = Teclas.escrever(modificadores: mods, tecla: base) else { return .ignorar }
        return .gravou(texto)
    }
}
