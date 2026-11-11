import Foundation
@testable import DeckCasca

/// Canal falso: guarda o que a página pediu e devolve a resposta combinada.
final class CanalFalso: Canal, @unchecked Sendable {
    let tipo: TipoCanal
    private let trava = NSLock()
    private var _pedidos: [PedidoCanal] = []
    var resposta = RespostaCanal(status: 200, tipo: "application/json; charset=utf-8", corpo: Data("{\"ok\":true}".utf8), cabecalhos: [:])
    var falha: ErroCanal?

    init(_ tipo: TipoCanal = .cabo) { self.tipo = tipo }

    var pedidos: [PedidoCanal] { trava.lock(); defer { trava.unlock() }; return _pedidos }

    func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal {
        trava.withLock { _pedidos.append(pedido) }
        if let falha { throw falha }
        return resposta
    }
}

/// Conta quantas vezes o aparelho vibrou.
final class Vibracoes: @unchecked Sendable {
    private let trava = NSLock()
    private var n = 0
    var total: Int { trava.lock(); defer { trava.unlock() }; return n }
    func vibrou() { trava.lock(); n += 1; trava.unlock() }
}

/// Pareador falso: dois Macs por perto e o código 483291, tanto na conferência quanto no cabo.
final class PareadorFalso: Pareador, @unchecked Sendable {
    static let perto = MacEncontrado(id: "mac-1", nome: "MacBook Pro de Exemplo", perto: true)
    static let longe = MacEncontrado(id: "mac-2", nome: "Mac mini do estúdio", perto: false)

    private let trava = NSLock()
    private var _concluidos: [Bool] = []
    var concluidos: [Bool] { trava.lock(); defer { trava.unlock() }; return _concluidos }
    var canal = CanalFalso(.bluetooth)
    var canalDoCabo = CanalFalso(.cabo)
    var falhaAoIniciar: ErroPareamento?
    var codigoCerto = "483291"

    func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> {
        AsyncStream { c in c.yield([Self.perto, Self.longe]) }
    }

    func iniciar(com mac: MacEncontrado) async throws -> String {
        if let falhaAoIniciar { throw falhaAoIniciar }
        return "483291"
    }

    func concluir(aceito: Bool) async throws -> PareamentoFeito {
        trava.withLock { _concluidos.append(aceito) }
        return PareamentoFeito(pareado: Pareado(codigoAcesso: "ABCDEFGHIJKLMNOPQRST", nomeMac: Self.perto.nome), canal: canal)
    }

    func procurarNoCabo() -> AsyncStream<MacEncontrado> {
        AsyncStream { c in c.yield(Self.perto) }
    }

    func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        guard codigo == codigoCerto else { throw ErroPareamento.recusado("Código errado. Confira o que aparece no Mac.") }
        return PareamentoFeito(pareado: Pareado(codigoAcesso: "ABCDEFGHIJKLMNOPQRST", nomeMac: mac.nome), canal: canalDoCabo)
    }
}

/// Espera a condição ficar verdadeira (as buscas do pareador rodam em tarefas soltas).
@MainActor
func esperar(_ condicao: @MainActor () -> Bool, segundos: Double = 2) async {
    let limite = Date().addingTimeInterval(segundos)
    while !condicao() && Date() < limite { try? await Task.sleep(nanoseconds: 5_000_000) }
}
