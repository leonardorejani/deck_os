import Foundation

// Avisos e valores que chegam de fora do Deck (um script, um build, um cron): o Mac recebe por uma porta que só abre
// neste Mac (loopback), com uma chave própria que não é o código do iPhone, guarda em memória com validade e o iPhone
// mostra. A ideia do endpoint veio do PhoneBox (MIT, https://github.com/Mastermindzh/PhoneBox, Program.cs, /api/push
// e /api/notify): aqui o código é novo, com limite de tamanho, de taxa e de quantidade.

/// Um aviso curto, que o iPhone mostra uma vez como toast. `nivel`: info, ok, aviso ou erro.
struct AvisoDeFora: Codable, Equatable, Sendable {
    var id: Int
    var titulo: String
    var texto: String
    var nivel: String
    /// Quando chegou, ISO 8601.
    var em: String
}

/// Um valor com nome (a chave) e prazo, que o iPhone mostra na tecla Valores.
struct ValorDeFora: Codable, Equatable, Sendable {
    var chave: String
    var valor: String
    /// Quando chegou e até quando vale, ISO 8601.
    var em: String
    var ate: String
}

/// Recusa com o texto pronto para quem mandou (vai em {"erro"}).
struct ErroDeFora: Error, Equatable, Sendable {
    var status: Int
    var texto: String
}

/// A memória dos avisos e valores. Nada vai a disco: reiniciar o Deck limpa tudo, e o que venceu sai sozinho.
final class ArmazemDeAvisos: @unchecked Sendable {
    static let niveis = ["info", "ok", "aviso", "erro"]
    static let maxTitulo = 60
    static let maxTexto = 140
    static let maxChave = 32
    static let maxValor = 40
    static let maxCorpo = 4 * 1024
    /// O aviso fica disponível por este tempo no estado (o iPhone mostra cada id uma vez) e a lista guarda os últimos.
    static let validadeDoAviso: TimeInterval = 120
    static let maxAvisos = 10
    static let maxValores = 20
    static let validadePadrao: TimeInterval = 3600
    static let validadeMaxima: TimeInterval = 86_400
    /// Pedidos aceitos por janela. Passou, o Mac responde 429 e diz em quantos segundos tentar de novo.
    static let pedidosPorJanela = 30
    static let janela: TimeInterval = 60

    private let trava = NSLock()
    private var avisos: [(aviso: AvisoDeFora, chegou: Date)] = []
    private var valores: [String: (valor: ValorDeFora, ate: Date)] = [:]
    private var proximoId = 1
    private var pedidos: [Date] = []
    private let fuso: TimeZone

    init(fuso: TimeZone = .current) { self.fuso = fuso }

    // MARK: Taxa

    /// Conta o pedido na janela. Devolve nil se cabe, ou os segundos de espera quando passou do limite.
    func pedirVaga(agora: Date) -> Int? {
        trava.lock(); defer { trava.unlock() }
        pedidos.removeAll { agora.timeIntervalSince($0) >= Self.janela || $0 > agora }
        if pedidos.count >= Self.pedidosPorJanela {
            let maisAntigo = pedidos.min() ?? agora
            return max(1, Int((Self.janela - agora.timeIntervalSince(maisAntigo)).rounded(.up)))
        }
        pedidos.append(agora)
        return nil
    }

    // MARK: Gravar

    func registrarAviso(titulo: String, texto: String?, nivel: String?, agora: Date) -> Result<AvisoDeFora, ErroDeFora> {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        let x = (texto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let n = (nivel ?? "info").lowercased()
        guard !t.isEmpty else { return .failure(ErroDeFora(status: 400, texto: "Informe o título do aviso.")) }
        guard Self.limpo(t, maximo: Self.maxTitulo) else { return .failure(ErroDeFora(status: 400, texto: "O título tem no máximo \(Self.maxTitulo) letras e nenhum caractere de controle.")) }
        guard x.isEmpty || Self.limpo(x, maximo: Self.maxTexto) else { return .failure(ErroDeFora(status: 400, texto: "O texto tem no máximo \(Self.maxTexto) letras e nenhum caractere de controle.")) }
        guard Self.niveis.contains(n) else { return .failure(ErroDeFora(status: 400, texto: "O nível é info, ok, aviso ou erro.")) }
        trava.lock(); defer { trava.unlock() }
        let aviso = AvisoDeFora(id: proximoId, titulo: t, texto: x, nivel: n, em: Datas.iso(agora, fuso: fuso))
        proximoId += 1
        avisos.append((aviso, agora))
        if avisos.count > Self.maxAvisos { avisos.removeFirst(avisos.count - Self.maxAvisos) }
        return .success(aviso)
    }

    func registrarValor(chave: String, valor: String, validade: TimeInterval?, agora: Date) -> Result<ValorDeFora, ErroDeFora> {
        let k = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.chaveValida(k) else {
            return .failure(ErroDeFora(status: 400, texto: "A chave tem de 1 a \(Self.maxChave) letras, números, ponto, traço ou sublinhado."))
        }
        guard !v.isEmpty, Self.limpo(v, maximo: Self.maxValor) else {
            return .failure(ErroDeFora(status: 400, texto: "O valor tem de 1 a \(Self.maxValor) letras e nenhum caractere de controle."))
        }
        let prazo = validade ?? Self.validadePadrao
        guard prazo.isFinite, prazo >= 1, prazo <= Self.validadeMaxima else {
            return .failure(ErroDeFora(status: 400, texto: "A validade vai de 1 segundo a 24 horas (86400)."))
        }
        trava.lock(); defer { trava.unlock() }
        limparVencidos(agora)
        if valores[k] == nil, valores.count >= Self.maxValores {
            return .failure(ErroDeFora(status: 409, texto: "Já há \(Self.maxValores) valores guardados. Espere algum vencer ou reuse uma chave."))
        }
        let ate = agora.addingTimeInterval(prazo)
        let item = ValorDeFora(chave: k, valor: v, em: Datas.iso(agora, fuso: fuso), ate: Datas.iso(ate, fuso: fuso))
        valores[k] = (item, ate)
        return .success(item)
    }

    // MARK: Ler

    /// Os avisos que ainda valem (do mais antigo ao mais novo) e os valores que não venceram (por chave).
    func foto(agora: Date) -> (avisos: [AvisoDeFora], valores: [ValorDeFora]) {
        trava.lock(); defer { trava.unlock() }
        limparVencidos(agora)
        return (avisos.map(\.aviso), valores.values.map(\.valor).sorted { $0.chave < $1.chave })
    }

    private func limparVencidos(_ agora: Date) {
        avisos.removeAll { agora.timeIntervalSince($0.chegou) >= Self.validadeDoAviso }
        valores = valores.filter { $0.value.ate > agora }
    }

    // MARK: Regras do texto

    static func chaveValida(_ s: String) -> Bool {
        !s.isEmpty && s.count <= maxChave && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// Sem caractere de controle (quebra de linha inclusive) e dentro do tamanho.
    static func limpo(_ s: String, maximo: Int) -> Bool {
        !s.isEmpty && s.count <= maximo && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// As duas teclas de fábrica deste recurso: não são apps do Mac, abrem uma tela do próprio iPhone (como Controles do Mac).
enum TeclasDeFora {
    static let valorDoGitHub = "Deck GitHub"
    static let valorDosValores = "Deck Valores"
    static func ehGitHub(_ t: Tecla) -> Bool { t.tipo == "app" && t.acao == nil && t.valor == valorDoGitHub }
    static func ehValores(_ t: Tecla) -> Bool { t.tipo == "app" && t.acao == nil && t.valor == valorDosValores }
}

// MARK: - A porta de fora (loopback)

/// Responde só ao que chega pela porta de fora. Não é o Roteador do iPhone: não tem código de acesso, tem a chave própria.
///   POST /aviso  {"titulo", "texto"?, "nivel"?}      -> {"ok": true, "id": N}
///   POST /valor  {"chave", "valor", "validade"?}     -> {"ok": true}   (validade em segundos, padrão 3600, máximo 86400)
/// A chave vai no cabeçalho `X-Deck-Chave`. Erro sempre em {"erro": "<texto>"}.
struct RoteadorDeFora: Sendable {
    let armazem: ArmazemDeAvisos
    /// A chave de agora (lida a cada pedido, para a troca de chave valer na hora).
    let chave: @Sendable () -> String

    func responder(_ r: HttpRequisicao, agora: Date = Date()) -> RespostaRota {
        // A taxa vem antes de tudo, inclusive da chave: chute de chave também gasta a vaga.
        if let espera = armazem.pedirVaga(agora: agora) {
            return .erro(429, "Pedidos demais. Tente de novo em \(espera) s.", extras: ["Retry-After": String(espera)])
        }
        let esperada = chave()
        guard !esperada.isEmpty, let recebida = r.cabecalhos["x-deck-chave"], Autenticacao.igual(recebida, esperada) else {
            return .erro(401, "Chave ausente ou incorreta. Copie a chave nos Ajustes do Deck, em Este Mac.")
        }
        guard r.caminho == "/aviso" || r.caminho == "/valor" else { return .erro(404, "Essa rota não existe. Use /aviso ou /valor.") }
        guard r.metodo == "POST" else { return .erro(405, "Use POST.", extras: ["Allow": "POST"]) }
        guard r.corpo.count <= ArmazemDeAvisos.maxCorpo else { return .erro(413, "O pedido é grande demais (máximo \(ArmazemDeAvisos.maxCorpo / 1024) KB).") }
        guard let corpo = try? JSONDecoder().decode(CorpoDeFora.self, from: r.corpo) else {
            return .erro(400, "Mande um JSON com os campos certos, por exemplo {\"titulo\": \"Build pronto\"}. Texto vai entre aspas e a validade é um número.")
        }
        if r.caminho == "/aviso" {
            guard let titulo = corpo.titulo else { return .erro(400, "Informe o título do aviso.") }
            switch armazem.registrarAviso(titulo: titulo, texto: corpo.texto, nivel: corpo.nivel, agora: agora) {
            case .success(let a): return .json(200, Data("{\"ok\":true,\"id\":\(a.id)}".utf8))
            case .failure(let e): return .erro(e.status, e.texto)
            }
        }
        guard let chave = corpo.chave else { return .erro(400, "Informe a chave do valor.") }
        guard let valor = corpo.valor?.texto else { return .erro(400, "Informe o valor (texto ou número).") }
        let validade = corpo.validade
        switch armazem.registrarValor(chave: chave, valor: valor, validade: validade, agora: agora) {
        case .success: return .json(200, Data("{\"ok\":true}".utf8))
        case .failure(let e): return .erro(e.status, e.texto)
        }
    }

    /// O que a porta de fora entende. Tipo errado em qualquer campo (booleano no valor, texto na validade) recusa o pedido.
    private struct CorpoDeFora: Decodable {
        var titulo: String?
        var texto: String?
        var nivel: String?
        var chave: String?
        var valor: ValorFlexivel?
        var validade: Double?
    }

    /// O valor pode vir como texto ou como número ("42", 42, 3.5).
    private enum ValorFlexivel: Decodable {
        case texto(String), numero(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .texto(s) } else { self = .numero(try c.decode(Double.self)) }
        }
        var texto: String {
            switch self {
            case .texto(let s): return s
            case .numero(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
            }
        }
    }
}

// MARK: - A chave da porta de fora

/// A chave que quem manda aviso de fora usa. Não é o código do iPhone: quem tem uma não tem a outra. Mora num arquivo só
/// do dono (0600) na pasta de dados da variante, nunca na config nem no que o iPhone lê. Nasce na primeira vez que alguém pede.
final class ChaveDeAvisos: @unchecked Sendable {
    static let tamanho = 32
    private let arquivo: URL
    private let trava = NSLock()
    private var guardada: String?

    init(pasta: URL) { arquivo = pasta.appendingPathComponent("chave-avisos") }

    /// A chave de agora. Arquivo sumido ou fora do formato vira uma chave nova.
    func atual() -> String {
        trava.lock(); defer { trava.unlock() }
        if let g = guardada { return g }
        if let lida = try? String(contentsOf: arquivo, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), Self.valida(lida) {
            guardada = lida
            return lida
        }
        return gerar()
    }

    /// Troca a chave: a antiga para de valer na hora.
    @discardableResult
    func trocar() -> String {
        trava.lock(); defer { trava.unlock() }
        return gerar()
    }

    private func gerar() -> String {
        var gerador = SystemRandomNumberGenerator()
        let letras = Array(Config.alfabetoCodigo)
        let nova = String((0..<Self.tamanho).map { _ in letras.randomElement(using: &gerador)! })
        let fm = FileManager.default
        try? fm.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Cria já com 0600: nunca existe um instante em que outro usuário do Mac possa ler.
        fm.createFile(atPath: arquivo.path, contents: Data(nova.utf8), attributes: [.posixPermissions: 0o600])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arquivo.path)
        guardada = nova
        return nova
    }

    static func valida(_ s: String) -> Bool { s.count == tamanho && s.allSatisfy { Config.alfabetoCodigo.contains($0) } }
}

/// O que os Ajustes mostram para copiar: o exemplo de curl com a porta e a chave de agora.
enum ExemploDeFora {
    static func curlAviso(porta: Int, chave: String) -> String {
        "curl -s -X POST http://127.0.0.1:\(porta)/aviso -H 'X-Deck-Chave: \(chave)' -d '{\"titulo\":\"Build pronto\",\"texto\":\"Passou em 2 min\",\"nivel\":\"ok\"}'"
    }
    static func curlValor(porta: Int, chave: String) -> String {
        "curl -s -X POST http://127.0.0.1:\(porta)/valor -H 'X-Deck-Chave: \(chave)' -d '{\"chave\":\"build\",\"valor\":\"ok\",\"validade\":600}'"
    }
}
