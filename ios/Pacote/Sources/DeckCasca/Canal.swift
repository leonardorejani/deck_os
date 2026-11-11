import Foundation

// O canal só transporta um pedido HTTP e a resposta. Quem entende de rota é o roteador do Mac
// (mac/Nucleo/Rotas.swift): estes tipos têm os mesmos campos de HttpRequisicao e RespostaRota para
// as fases 6 (cabo) e 7 (Bluetooth) levarem em JSON entre o iPhone e o Mac sem tradução.

public enum TipoCanal: String, Codable, Equatable, Sendable {
    case cabo
    case bluetooth
}

public struct PedidoCanal: Codable, Equatable, Sendable {
    public var metodo: String
    public var caminho: String
    public var query: [String: String]
    /// Nomes em minúsculas, como o Mac lê.
    public var cabecalhos: [String: String]
    public var corpo: Data

    public init(metodo: String, caminho: String, query: [String: String] = [:], cabecalhos: [String: String] = [:], corpo: Data = Data()) {
        self.metodo = metodo
        self.caminho = caminho
        self.query = query
        self.cabecalhos = cabecalhos
        self.corpo = corpo
    }
}

public struct RespostaCanal: Codable, Equatable, Sendable {
    public var status: Int
    public var tipo: String
    public var corpo: Data
    public var cabecalhos: [String: String]

    public init(status: Int, tipo: String, corpo: Data, cabecalhos: [String: String] = [:]) {
        self.status = status
        self.tipo = tipo
        self.corpo = corpo
        self.cabecalhos = cabecalhos
    }

    /// Cabeçalho pelo nome, sem diferenciar maiúscula (o Mac manda `X-Deck-Codigo-Novo`).
    public func cabecalho(_ nome: String) -> String? {
        cabecalhos.first { $0.key.caseInsensitiveCompare(nome) == .orderedSame }?.value
    }
}

public enum ErroCanal: Error, Equatable, Sendable {
    /// Nenhum Mac ligado por nenhum canal.
    case semCanal
    /// O canal existe mas não conseguiu levar o pedido. O texto é o que a pessoa lê.
    case falhou(String)
}

/// Uma forma de chegar ao Mac. O cabo (fase 6) e o Bluetooth (fase 7) implementam isto.
public protocol Canal: Sendable {
    var tipo: TipoCanal { get }
    func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal
}

/// O canal em uso agora. Quem decide qual é (cabo quando plugado, Bluetooth quando não) é a Casca.
public final class CanalAtual: @unchecked Sendable {
    private let trava = NSLock()
    private var canal: (any Canal)?
    private var procurarAlternativa: (@Sendable (TipoCanal) -> (any Canal)?)?

    public init() {}

    /// Quem sabe dizer qual outro canal está de pé (o cabo caiu no meio de um pedido e o Bluetooth já estava conectado).
    public func definirAlternativa(_ f: @escaping @Sendable (TipoCanal) -> (any Canal)?) {
        trava.lock(); defer { trava.unlock() }
        procurarAlternativa = f
    }

    public func alternativa(para tipo: TipoCanal) -> (any Canal)? {
        trava.lock()
        let f = procurarAlternativa
        trava.unlock()
        return f?(tipo)
    }

    public func definir(_ novo: (any Canal)?) {
        trava.lock(); defer { trava.unlock() }
        canal = novo
    }

    public func obter() -> (any Canal)? {
        trava.lock(); defer { trava.unlock() }
        return canal
    }
}

/// O Bluetooth como a Casca o enxerga: uma conexão que liga sozinha quando já pareado e avisa quando o Mac
/// aparece ou some. Existe como protocolo para a Casca compilar onde não há CryptoKit (o Linux do CI).
public protocol ConexaoBluetooth: AnyObject, Sendable {
    /// O Mac que se apresentou pelo Bluetooth, ou nil.
    var mac: MacEncontrado? { get }
    func aoMudar(_ f: @escaping @Sendable (MacEncontrado?) -> Void)
    func canal() -> any Canal
    func iniciar()
    func retomar()
    /// Pareou ou esqueceu: liga ou desliga a reconexão conforme o cofre.
    func reavaliar()
    /// O Mac conhecido recusou este iPhone mais de uma vez seguida: o pareamento acabou (o Mac desconectou o aparelho).
    func aoNaoReconhecido(_ f: @escaping @Sendable () -> Void)
}
