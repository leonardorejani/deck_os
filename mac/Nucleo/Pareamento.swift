import Foundation

enum ResultadoPareamento: Equatable, Sendable {
    case aceito
    /// Quantas tentativas ainda restam neste código.
    case errado(restantes: Int)
    case vencido
    case bloqueado
}

/// Código curto que o Mac mostra e o iPhone digita para receber o código de acesso longo.
/// Vale 10 minutos, serve uma vez e aguenta 5 erros: com 6 dígitos, mais tentativas deixariam
/// adivinhar. Passou do limite, só um código novo (gerado no Mac) volta a funcionar.
final class Pareamento: @unchecked Sendable {
    static let validade: TimeInterval = 10 * 60
    static let maxErros = 5

    private struct Ativo {
        var codigo: String
        var vence: Date
        var erros = 0
    }

    private let trava = NSLock()
    private var ativo: Ativo?
    /// Chamado (fora da trava) cada vez que um iPhone acerta o código. É como o app do Mac fica sabendo
    /// que há um aparelho pareado: o núcleo só entrega o código de acesso, não guarda quem o recebeu.
    private var aoAceitarCodigo: (@Sendable () -> Void)?
    private let agora: @Sendable () -> Date
    private let sorteio: @Sendable () -> String

    init(agora: @escaping @Sendable () -> Date = { Date() },
         sorteio: @escaping @Sendable () -> String = Pareamento.sortear) {
        self.agora = agora
        self.sorteio = sorteio
    }

    static func sortear() -> String {
        String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    /// Gera um código novo e invalida o anterior, junto com a contagem de erros dele.
    @discardableResult
    func gerar() -> String {
        trava.lock(); defer { trava.unlock() }
        let c = sorteio()
        ativo = Ativo(codigo: c, vence: agora().addingTimeInterval(Self.validade))
        return c
    }

    /// O código que ainda serve: nil se venceu, já foi usado, estourou os erros ou foi encerrado. A tela
    /// pergunta isso para trocar o código que mostra sem esperar os 10 minutos.
    var codigoAtivo: String? {
        trava.lock(); defer { trava.unlock() }
        guard let a = ativo, agora() < a.vence, a.erros < Self.maxErros else { return nil }
        return a.codigo
    }

    /// O mesmo que `codigoAtivo`. O cabo usa este nome para provar ao iPhone que o Mac conhece os dígitos (ProvaCabo),
    /// nunca para mostrar ou registrar.
    func vigente() -> String? { codigoAtivo }

    /// Apaga o código: ninguém mais consegue parear até o Mac gerar outro. É o que a tela faz ao fechar.
    func encerrar() {
        trava.lock(); defer { trava.unlock() }
        ativo = nil
    }

    func aoAceitar(_ acao: (@Sendable () -> Void)?) {
        trava.lock(); defer { trava.unlock() }
        aoAceitarCodigo = acao
    }

    func tentar(_ codigo: String) -> ResultadoPareamento {
        let r = tentarSemAviso(codigo)
        if r == .aceito {
            trava.lock(); let acao = aoAceitarCodigo; trava.unlock()
            acao?()
        }
        return r
    }

    private func tentarSemAviso(_ codigo: String) -> ResultadoPareamento {
        trava.lock(); defer { trava.unlock() }
        guard var a = ativo else { return .vencido }
        if agora() >= a.vence { ativo = nil; return .vencido }
        if a.erros >= Self.maxErros { return .bloqueado }
        if Autenticacao.igual(codigo, a.codigo) {
            ativo = nil
            return .aceito
        }
        a.erros += 1
        ativo = a
        return .errado(restantes: Self.maxErros - a.erros)
    }
}
