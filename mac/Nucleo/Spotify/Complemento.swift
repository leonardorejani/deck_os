import Foundation

/// O que a API do Spotify acrescenta ao estado (curtida, repetição, aparelho). O estado é pedido a cada
/// segundo e a API é lenta e tem limite, então aqui só se devolve o último valor guardado e, se ele
/// está velho, uma atualização roda por trás. Nunca bloqueia o estado.
final class ComplementoSpotify: @unchecked Sendable {
    typealias Disparador = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let conta: ContaSpotify
    private let disparar: Disparador
    private let validade: TimeInterval
    /// Depois de uma falha (sem internet, limite), espera isto antes de tentar de novo.
    private let espera: TimeInterval
    private let trava = NSLock()
    private var jogador: JogadorSpotify?
    private var jogadorEm: Date?
    private var tentouEm: Date?
    private var curtidaDe: String?
    private var curtida: Bool?
    private var atualizando = false

    init(conta: ContaSpotify, validade: TimeInterval = 5, espera: TimeInterval = 30,
         disparar: @escaping Disparador = { trabalho in DispatchQueue.global(qos: .utility).async(execute: trabalho) }) {
        self.conta = conta
        self.validade = validade
        self.espera = espera
        self.disparar = disparar
    }

    /// Soma ao estado o que vem da API. Sem login só marca `conectado = false`, e o painel esconde o resto.
    func aplicar(_ estado: EstadoSpotify, uri: String?, agora: Date = Date()) -> EstadoSpotify {
        var e = estado
        guard conta.conectado else {
            e.conectado = false
            trava.lock(); jogador = nil; jogadorEm = nil; tentouEm = nil; curtidaDe = nil; curtida = nil; trava.unlock()
            return e
        }
        e.conectado = true
        trava.lock()
        e.repetirFaixa = jogador?.repetir.map { $0 == "faixa" }
        e.aparelho = jogador?.aparelho
        if let uri, curtidaDe == uri { e.curtida = curtida }
        let velho = jogadorEm.map { agora.timeIntervalSince($0) >= validade } ?? true
        let faltaCurtida = uri != nil && curtidaDe != uri
        let esperando = tentouEm.map { agora.timeIntervalSince($0) < espera } ?? false
        let iniciar = (velho || faltaCurtida) && !atualizando && !esperando
        if iniciar { atualizando = true; tentouEm = agora }
        trava.unlock()
        if iniciar { disparar { [self] in atualizar(uri: uri, agora: agora) } }
        return e
    }

    /// Lê a API e guarda. Público para o teste chamar direto e para as rotas pedirem leitura na hora.
    func atualizar(uri: String?, agora: Date = Date()) {
        defer { trava.lock(); atualizando = false; trava.unlock() }
        var falhou = false
        switch conta.jogador() {
        case .success(let j):
            trava.lock(); jogador = j; jogadorEm = agora; trava.unlock()
        case .failure: falhou = true
        }
        if let uri {
            switch conta.curtida(uri) {
            case .success(let c): trava.lock(); curtidaDe = uri; curtida = c; trava.unlock()
            case .failure: falhou = true
            }
        }
        if !falhou { trava.lock(); tentouEm = nil; trava.unlock() }
    }

    /// Depois de curtir ou mudar a repetição, o estado já mostra o novo valor sem esperar a API.
    func marcarCurtida(_ uri: String, _ valor: Bool) {
        trava.lock(); curtidaDe = uri; curtida = valor; trava.unlock()
    }

    func marcarRepetir(_ modo: String) {
        trava.lock()
        var j = jogador ?? JogadorSpotify()
        j.repetir = modo
        jogador = j
        if jogadorEm == nil { jogadorEm = Date() }
        trava.unlock()
    }
}
