import Foundation

/// Rodízio do código de acesso: troca a cada 24 h sem o iPhone parear de novo. O código anterior
/// vale mais 10 min depois da troca e, nesse período, toda resposta leva o novo no cabeçalho
/// X-Deck-Codigo-Novo (ver Modelos.swift). A troca é preguiçosa: acontece no primeiro pedido depois
/// dos 24 h ou quando o app do Mac chama gerarSeVencido(). Tudo passa pela trava, para dois pedidos
/// ao mesmo tempo não trocarem duas vezes e perderem o código anterior.
final class Rodizio: @unchecked Sendable {
    static let validade: TimeInterval = 24 * 60 * 60
    static let folga: TimeInterval = 10 * 60
    /// De quanto em quanto tempo o app do Mac chama gerarSeVencido(): a troca de 24 h não depende de pedido do iPhone.
    static let checagem: TimeInterval = 5 * 60
    static let cabecalhoNovo = "X-Deck-Codigo-Novo"

    enum Via: Equatable, Sendable {
        /// Código atual.
        case atual
        /// Código anterior, ainda na folga: a resposta leva o novo.
        case anterior
        case invalido
    }

    private let trava = NSLock()
    private let agora: @Sendable () -> Date

    init(agora: @escaping @Sendable () -> Date = { Date() }) { self.agora = agora }

    private func segundos() -> Int { Int(agora().timeIntervalSince1970) }

    /// Confere o código do pedido e troca antes, se o atual já venceu. Devolve também a config
    /// vigente (já trocada), que é a que o roteador deve usar.
    func autenticar(_ recebido: String?, em armazem: ArmazemDeConfig) -> (via: Via, config: Config) {
        trava.lock(); defer { trava.unlock() }
        let c = trocarSeVencido(armazem)
        guard let recebido, !c.codigoAcesso.isEmpty else { return (.invalido, c) }
        // As duas comparações rodam sempre: o tempo não revela qual dos códigos bateu.
        let batAtual = Autenticacao.igual(recebido, c.codigoAcesso)
        let batAnterior = Autenticacao.igual(recebido, c.codigoAnterior ?? "")
        let naFolga = c.codigoAnterior != nil && segundos() < (c.anteriorValeAte ?? 0)
        if batAtual { return (.atual, c) }
        if batAnterior && naFolga { return (.anterior, c) }
        return (.invalido, c)
    }

    /// Para o app do Mac chamar num cronômetro: troca se passou de 24 h. Devolve true se trocou.
    @discardableResult
    func gerarSeVencido(em armazem: ArmazemDeConfig) -> Bool {
        trava.lock(); defer { trava.unlock() }
        let antes = armazem.ler().codigoAcesso
        return trocarSeVencido(armazem).codigoAcesso != antes
    }

    /// Quando o código atual vence, para o app do Mac saber quando chamar gerarSeVencido().
    func vencimento(em armazem: ArmazemDeConfig) -> Date {
        Date(timeIntervalSince1970: TimeInterval(armazem.ler().codigoCriadoEm) + Self.validade)
    }

    /// Invalida o atual e o anterior na hora e gera um novo que nenhum iPhone tem: todos precisam
    /// parear de novo. Devolve o erro em texto, ou nil se gravou.
    func revogar(em armazem: ArmazemDeConfig) -> String? {
        trava.lock(); defer { trava.unlock() }
        var c = armazem.ler()
        c.codigoAcesso = Config.novoCodigoAcesso()
        c.codigoCriadoEm = segundos()
        c.codigoAnterior = nil
        c.anteriorValeAte = nil
        return armazem.aplicar(c)
    }

    /// Chamar com a trava. Se não conseguir gravar, segue com a config antiga: melhor atrasar a
    /// troca do que ter um código na memória que o disco não tem.
    private func trocarSeVencido(_ armazem: ArmazemDeConfig) -> Config {
        let c = armazem.ler()
        guard !c.codigoAcesso.isEmpty, TimeInterval(segundos() - c.codigoCriadoEm) >= Self.validade else { return c }
        var nova = c
        nova.codigoAnterior = c.codigoAcesso
        nova.anteriorValeAte = segundos() + Int(Self.folga)
        nova.codigoAcesso = Config.novoCodigoAcesso()
        nova.codigoCriadoEm = segundos()
        return armazem.aplicar(nova) == nil ? nova : c
    }
}
