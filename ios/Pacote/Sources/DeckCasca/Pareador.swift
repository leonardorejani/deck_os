import Foundation

// O que o fluxo de pareamento pede para a camada de baixo. As fases 6 e 7 implementam isto com o
// cabo e o Bluetooth. Nesta fase o app usa PareadorSemMac: sem canal ainda, não acha Mac nenhum.

public struct MacEncontrado: Codable, Equatable, Sendable {
    public var id: String
    public var nome: String
    /// Sinal forte. Só o Mac de perto aceita parear na lista.
    public var perto: Bool

    public init(id: String, nome: String, perto: Bool) {
        self.id = id
        self.nome = nome
        self.perto = perto
    }
}

/// O que sobra de um pareamento que deu certo: o que guardar e o canal já pronto para usar.
public struct PareamentoFeito: Sendable {
    public var pareado: Pareado
    public var canal: any Canal

    public init(pareado: Pareado, canal: any Canal) {
        self.pareado = pareado
        self.canal = canal
    }
}

public enum ErroPareamento: Error, Equatable, Sendable {
    case indisponivel
    /// O texto é o que a pessoa lê.
    case recusado(String)

    public var mensagem: String {
        switch self {
        case .indisponivel: return "Ainda não dá para parear por aqui."
        case .recusado(let texto): return texto
        }
    }
}

public protocol Pareador: Sendable {
    /// Os Macs com o Deck aberto por perto, a cada mudança da lista.
    func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]>
    /// Toca no Mac da lista: devolve o código de 6 dígitos que os dois lados mostram para conferir.
    func iniciar(com mac: MacEncontrado) async throws -> String
    /// A pessoa confirmou (ou recusou) o código igual nas duas telas.
    func concluir(aceito: Bool) async throws -> PareamentoFeito
    /// Segunda via: avisa quando acha um Mac com Deck pelo cabo.
    func procurarNoCabo() -> AsyncStream<MacEncontrado>
    /// Segunda via: o código de 6 dígitos que o Mac mostra, digitado no iPhone.
    func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito
    /// Depois de começar a procurar por Bluetooth: por que a lista pode ficar vazia (rádio desligado, sem permissão), ou nil.
    func avisoDaProcura() async -> String?
}

public extension Pareador {
    func avisoDaProcura() async -> String? { nil }
}

/// Sem canal ainda (fase 5): a procura nunca acha ninguém e o resto não é possível.
public struct PareadorSemMac: Pareador {
    public init() {}

    public func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> {
        AsyncStream { $0.yield([]) }
    }

    public func iniciar(com mac: MacEncontrado) async throws -> String { throw ErroPareamento.indisponivel }
    public func concluir(aceito: Bool) async throws -> PareamentoFeito { throw ErroPareamento.indisponivel }

    /// Fica de pé sem achar nada, até a tarefa ser cancelada.
    public func procurarNoCabo() -> AsyncStream<MacEncontrado> {
        AsyncStream { _ in }
    }

    public func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        throw ErroPareamento.indisponivel
    }
}
