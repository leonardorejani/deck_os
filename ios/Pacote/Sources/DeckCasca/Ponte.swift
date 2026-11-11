import Foundation

// A ponte entre a página (window.DeckCanal, em ios/Web/ponte.js) e o canal. A página fala em JSON
// pelo WKScriptMessageHandlerWithReply. Aqui o pedido vira PedidoCanal e a resposta volta em JSON.

/// Tudo que a página pode mandar. Cada `op` usa só os campos que lhe cabem.
public struct MensagemPonte: Codable, Equatable, Sendable {
    /// "requisitar", "vibrar", "estado" ou "acao".
    public var op: String
    public var metodo: String?
    public var caminho: String?
    public var query: [String: String]?
    public var cabecalhos: [String: String]?
    public var corpo: String?
    /// Só em "acao": procurar, escolher, confirmar, cabo, voltarParaBluetooth, voltar, digitos, abrirPainel, esquecer.
    public var acao: String?
    public var id: String?
    public var ok: Bool?
    public var digitos: String?

    public init(op: String, metodo: String? = nil, caminho: String? = nil, query: [String: String]? = nil,
                cabecalhos: [String: String]? = nil, corpo: String? = nil, acao: String? = nil,
                id: String? = nil, ok: Bool? = nil, digitos: String? = nil) {
        self.op = op
        self.metodo = metodo
        self.caminho = caminho
        self.query = query
        self.cabecalhos = cabecalhos
        self.corpo = corpo
        self.acao = acao
        self.id = id
        self.ok = ok
        self.digitos = digitos
    }
}

/// O que volta para a página. `erro` é "semCanal" (o Mac não respondeu), "canal" (o canal falhou, com
/// `mensagem` em português) ou "pedidoInvalido".
public struct RespostaPonte: Codable, Equatable, Sendable {
    public var status: Int?
    public var corpo: String?
    /// Valor do cabeçalho X-Deck-Codigo-Novo, quando o Mac trocou o código de acesso.
    public var codigoNovo: String?
    public var erro: String?
    public var mensagem: String?

    public init(status: Int? = nil, corpo: String? = nil, codigoNovo: String? = nil, erro: String? = nil, mensagem: String? = nil) {
        self.status = status
        self.corpo = corpo
        self.codigoNovo = codigoNovo
        self.erro = erro
        self.mensagem = mensagem
    }
}

public struct RespostaCapa: Equatable, Sendable {
    public var status: Int
    public var tipo: String
    public var corpo: Data
}

public struct Ponte: Sendable {
    public static let esquemaDaCapa = "deckcapa"
    static let cabecalhoCodigoNovo = "x-deck-codigo-novo"

    let canais: CanalAtual
    let cofre: Cofre
    let vibrar: @Sendable () -> Void
    let aoCodigoNovo: @Sendable (String) -> Void

    public init(canais: CanalAtual, cofre: Cofre, vibrar: @escaping @Sendable () -> Void,
                aoCodigoNovo: @escaping @Sendable (String) -> Void = { _ in }) {
        self.canais = canais
        self.cofre = cofre
        self.vibrar = vibrar
        self.aoCodigoNovo = aoCodigoNovo
    }

    public func requisitar(_ m: MensagemPonte) async -> RespostaPonte {
        guard let caminho = m.caminho, !caminho.isEmpty else { return RespostaPonte(erro: "pedidoInvalido") }
        let metodo = (m.metodo ?? "GET").uppercased()
        // O dedo sente a tecla na hora, antes de o Mac responder (e mesmo sem Mac).
        if metodo == "POST", caminho.hasPrefix("/api/botao/") { vibrar() }
        guard let canal = canais.obter() else { return RespostaPonte(erro: "semCanal") }

        var cabecalhos: [String: String] = [:]
        for (k, v) in m.cabecalhos ?? [:] { cabecalhos[k.lowercased()] = v }
        let pedido = PedidoCanal(metodo: metodo, caminho: caminho, query: m.query ?? [:], cabecalhos: cabecalhos,
                                 corpo: Data((m.corpo ?? "").utf8))
        do {
            let r = try await enviarComReserva(canal, pedido)
            return RespostaPonte(status: r.status, corpo: String(decoding: r.corpo, as: UTF8.self), codigoNovo: guardarCodigoNovo(r))
        } catch ErroCanal.semCanal {
            return RespostaPonte(erro: "semCanal")
        } catch ErroCanal.falhou(let texto) {
            return RespostaPonte(erro: "canal", mensagem: texto)
        } catch {
            return RespostaPonte(erro: "canal", mensagem: "Não consegui falar com o Mac.")
        }
    }

    /// Puxaram o cabo no meio de uma leitura e o Bluetooth já estava de pé: repete a leitura nele, para a tela não
    /// perceber. Só leitura (GET): repetir uma tecla poderia executá-la duas vezes.
    private func enviarComReserva(_ canal: any Canal, _ pedido: PedidoCanal) async throws -> RespostaCanal {
        do { return try await canal.enviar(pedido) } catch {
            guard pedido.metodo == "GET", let outro = canais.alternativa(para: canal.tipo) else { throw error }
            return try await outro.enviar(pedido)
        }
    }

    // MARK: Capa

    /// A capa e os ícones dos apps vão numa <img>, que não manda cabeçalho: a página usa deckcapa://capa/?codigo=...&v=...
    /// (a capa do Spotify) e deckcapa://apps/<bundle>/icone?codigo=... (o ícone de um app do Mac, no editor de tecla).
    /// O código segue na query, como no endereço HTTPS. Qualquer outro caminho não vira pedido.
    public static func pedidoDaCapa(_ url: URL) -> PedidoCanal? {
        guard url.scheme == esquemaDaCapa,
              let partes = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let caminho: String
        switch partes.host {
        case "capa": caminho = "/api/capa"
        case "apps":
            let p = partes.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3, p[0].isEmpty, p[2] == "icone", idDePacoteValido(p[1]) else { return nil }
            caminho = "/api/apps/\(p[1])/icone"
        default: return nil
        }
        var query: [String: String] = [:]
        for item in partes.queryItems ?? [] { query[item.name] = item.value ?? "" }
        var cabecalhos: [String: String] = [:]
        if let codigo = query["codigo"] { cabecalhos["x-deck-codigo"] = codigo }
        return PedidoCanal(metodo: "GET", caminho: caminho, query: query, cabecalhos: cabecalhos)
    }

    /// Id de pacote: letra, número, ponto, traço e sublinhado (o mesmo que o Mac aceita em /api/apps/<bundle>).
    static func idDePacoteValido(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }

    public func capa(_ url: URL) async -> RespostaCapa {
        guard let pedido = Self.pedidoDaCapa(url) else { return RespostaCapa(status: 400, tipo: "text/plain", corpo: Data()) }
        guard let canal = canais.obter() else { return RespostaCapa(status: 503, tipo: "text/plain", corpo: Data()) }
        guard let r = try? await enviarComReserva(canal, pedido) else { return RespostaCapa(status: 503, tipo: "text/plain", corpo: Data()) }
        if let novo = guardarCodigoNovo(r) { aoCodigoNovo(novo) }
        return RespostaCapa(status: r.status, tipo: r.tipo, corpo: r.corpo)
    }

    // MARK: Rodízio do código

    /// O Mac troca o código de acesso e avisa no cabeçalho da resposta. Só vale em resposta de sucesso,
    /// e fica no cofre na hora para o app abrir já com o código novo.
    private func guardarCodigoNovo(_ r: RespostaCanal) -> String? {
        guard (200..<300).contains(r.status),
              let bruto = r.cabecalho(Self.cabecalhoCodigoNovo) else { return nil }
        let novo = bruto.trimmingCharacters(in: .whitespaces)
        guard !novo.isEmpty else { return nil }
        cofre.trocarCodigo(novo)
        return novo
    }
}
