import Foundation

/// Junta o que o app precisa: o fluxo de pareamento, o canal em uso e a ponte com a página.
/// Nada aqui sabe de UIKit: o app entrega `executarJS` e `recarregarPagina`.
@MainActor
public final class Casca {
    public let fluxo: FluxoPareamento
    public let canais = CanalAtual()
    public let cofre: Cofre
    /// A porta do cabo (fase 6). Sem ela, o app não tem canal nenhum, como na fase 5.
    public let cabo: GerenteDoCabo?
    /// O Bluetooth (fase 7). Cabo e Bluetooth ficam conectados ao mesmo tempo: o cabo é o canal em uso quando está
    /// plugado e o Bluetooth assume na hora quando ele sai.
    public let bluetooth: (any ConexaoBluetooth)?

    /// Roda um trecho de JavaScript na página.
    public var executarJS: (String) -> Void = { _ in }
    public var recarregarPagina: () -> Void = {}

    private var ponte: Ponte!
    private var tipoDoCanal: TipoCanal?

    public init(pareador: Pareador, cofre: Cofre, vibrar: @escaping @Sendable () -> Void, permanenciaNoCabo: TimeInterval = 2.2,
                cabo: GerenteDoCabo? = nil, bluetooth: (any ConexaoBluetooth)? = nil) {
        self.cofre = cofre
        self.cabo = cabo
        self.bluetooth = bluetooth
        fluxo = FluxoPareamento(pareador: pareador, cofre: cofre, permanenciaNoCabo: permanenciaNoCabo)
        ponte = Ponte(canais: canais, cofre: cofre, vibrar: vibrar, aoCodigoNovo: { [weak self] novo in
            Task { @MainActor in self?.executarJS("DeckCanal.codigo(\(Self.literal(novo)))") }
        })
        fluxo.aoMudar = { [weak self] estado in
            guard let self, let json = Self.json(estado) else { return }
            executarJS("DeckNativo.estado(\(json))")
        }
        fluxo.aoPareado = { [weak self] feito in
            guard let self else { return }
            executarJS("DeckCanal.codigo(\(Self.literal(feito.pareado.codigoAcesso)))")
            // Pareou: o Bluetooth passa a se manter conectado. O cabo, se já está plugado, continua sendo o canal em uso.
            bluetooth?.reavaliar()
            if let cabo, cabo.mac != nil, feito.canal.tipo != .cabo { usar(canal: CanalCabo(cabo)) } else { usar(canal: feito.canal) }
        }
    }

    public func iniciar() {
        fluxo.iniciar()
        cabo?.aoMudar { [weak self] _ in
            Task { @MainActor in self?.reavaliarCanal() }
        }
        bluetooth?.aoMudar { [weak self] _ in
            Task { @MainActor in self?.reavaliarCanal() }
        }
        // O cabo caiu no meio de uma leitura e o Bluetooth já está de pé (ou o contrário): a ponte repete a leitura no outro.
        canais.definirAlternativa { [cabo, bluetooth] tipo in
            switch tipo {
            case .cabo: return bluetooth?.mac != nil ? bluetooth?.canal() : nil
            case .bluetooth: return cabo.flatMap { $0.mac != nil ? CanalCabo($0) : nil }
            }
        }
        // O Mac desconectou este iPhone (mudou o código de acesso): esquece o pareamento e volta à tela de parear,
        // o mesmo que a página faz num 401. Sem isto, nenhum canal conecta e a tela fica em "Mac desconectado".
        bluetooth?.aoNaoReconhecido { [weak self] in
            Task { @MainActor in await self?.esquecerPareamento() }
        }
        cabo?.iniciar()
        bluetooth?.iniciar()
    }

    private func esquecerPareamento() async {
        guard cofre.ler() != nil else { return }
        _ = await fluxo.tratar(.esquecer)
        bluetooth?.reavaliar()
        usar(canal: nil)
        recarregarPagina()
    }

    /// O app voltou ao primeiro plano: o iOS pode ter fechado a porta do cabo e derrubado o Bluetooth em segundo plano.
    public func retomar() {
        cabo?.retomar()
        bluetooth?.retomar()
    }

    /// Um Mac apareceu ou sumiu em algum canal. Pareado, o cabo é o canal em uso quando está plugado, e o Bluetooth
    /// quando não está (o aviso de 3 segundos aparece a cada troca). Sem pareamento, só o fluxo de pareamento usa
    /// as conexões. Sem nenhum dos dois, a página mostra "Mac desconectado" até um voltar (a reconexão é sozinha).
    func reavaliarCanal() {
        guard cofre.ler() != nil else { return }
        if let cabo, cabo.mac != nil {
            usar(canal: CanalCabo(cabo))
        } else if let bluetooth, bluetooth.mac != nil {
            usar(canal: bluetooth.canal())
        } else if canais.obter() != nil {
            usar(canal: nil)
        }
    }

    public var vibrar: @Sendable () -> Void { ponte.vibrar }

    /// O canal em uso mudou: a página mostra o aviso de 3 segundos ("Pelo cabo", "Pelo Bluetooth").
    public func usar(canal: (any Canal)?) {
        canais.definir(canal)
        guard let tipo = canal?.tipo, tipo != tipoDoCanal else {
            if canal == nil { tipoDoCanal = nil }
            return
        }
        tipoDoCanal = tipo
        executarJS("DeckNativo.canal(\(Self.literal(tipo.rawValue)))")
    }

    /// A capa do Spotify, pedida pela <img> da página (deckcapa://).
    public func capa(_ url: URL) async -> RespostaCapa { await ponte.capa(url) }

    /// Roda antes de a página carregar: entrega o código guardado e a etapa de agora, para a tela já
    /// nascer certa, sem piscar o painel antes do pareamento.
    public func scriptDeInicio() -> String {
        let inicio = Inicio(codigo: cofre.ler()?.codigoAcesso, estado: fluxo.estado, canal: tipoDoCanal)
        return "window.DECK_NATIVO_INICIO = \(Self.json(inicio) ?? "{}");"
    }

    public func tratar(_ dados: Data) async -> String {
        guard let m = try? JSONDecoder().decode(MensagemPonte.self, from: dados) else {
            return Self.json(RespostaCasca(erro: "Não entendi o pedido da página.")) ?? "{}"
        }
        switch m.op {
        case "requisitar":
            return Self.json(await ponte.requisitar(m)) ?? "{}"
        case "vibrar":
            ponte.vibrar()
            return "{}"
        case "codigo":
            // O código que está no Keychain agora: a página confere antes de esquecer o Mac num 401 (rodízio em andamento).
            return Self.json(["codigo": cofre.ler()?.codigoAcesso ?? ""]) ?? "{}"
        case "estado":
            return Self.json(RespostaCasca(estado: fluxo.estado, canal: tipoDoCanal)) ?? "{}"
        case "acao":
            guard let acao = Self.acao(m) else { return Self.json(RespostaCasca(erro: "Essa ação não existe.")) ?? "{}" }
            let erro = await fluxo.tratar(acao)
            if case .esquecer = acao {
                bluetooth?.reavaliar()
                usar(canal: nil)
                recarregarPagina()
            }
            return Self.json(RespostaCasca(estado: fluxo.estado, erro: erro)) ?? "{}"
        default:
            return Self.json(RespostaCasca(erro: "Não entendi o pedido da página.")) ?? "{}"
        }
    }

    // MARK: Apoio

    private static func acao(_ m: MensagemPonte) -> AcaoPareamento? {
        switch m.acao {
        case "procurar": return .procurar
        case "escolher": return m.id.map { .escolher($0) }
        case "confirmar": return .confirmar(m.ok ?? false)
        case "cabo": return .cabo
        case "voltarParaBluetooth": return .voltarParaBluetooth
        case "voltar": return .voltar
        case "digitos": return m.digitos.map { .digitos($0) }
        case "abrirPainel": return .abrirPainel
        case "esquecer": return .esquecer
        default: return nil
        }
    }

    private struct Inicio: Encodable {
        var codigo: String?
        var estado: EstadoPareamento
        var canal: TipoCanal?
        // Codifica o nulo de verdade: a página distingue "sem código" de "campo ausente".
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Chave.self)
            try c.encode(codigo, forKey: .codigo)
            try c.encode(estado, forKey: .estado)
            try c.encodeIfPresent(canal, forKey: .canal)
        }
        enum Chave: String, CodingKey { case codigo, estado, canal }
    }

    struct RespostaCasca: Codable {
        var estado: EstadoPareamento?
        var erro: String?
        var canal: TipoCanal?
    }

    static func json<T: Encodable>(_ valor: T) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let dados = try? enc.encode(valor) else { return nil }
        return String(decoding: dados, as: UTF8.self)
    }

    /// Texto como literal JavaScript (JSON de uma string é uma string válida em JS).
    static func literal(_ texto: String) -> String { json(texto) ?? "\"\"" }
}
