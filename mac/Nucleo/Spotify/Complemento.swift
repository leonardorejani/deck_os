import Foundation

/// O que a API do Spotify acrescenta ao estado (curtida, repetição, aparelho). O estado é pedido a cada
/// segundo e a API é lenta e tem limite (o Spotify chegou a bloquear a chave do Deck por horas), então aqui só se devolve
/// o último valor guardado e, se ele precisa de renovação, uma atualização roda por trás. Nunca bloqueia o estado.
///
/// A API só é lida quando alguém usa: o pedido de estado de um painel (é ele que chama `aplicar`, então sem painel
/// não há leitura nenhuma) e, além disso, o Spotify tocando ou o player cheio aberto (`abrirPlayer`). Pausado e sem
/// ninguém no player, zero chamadas. Com o Spotify pedindo espera (429), também zero: nem tenta.
final class ComplementoSpotify: @unchecked Sendable {
    typealias Disparador = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let conta: ContaSpotify
    private let disparar: Disparador
    /// Validade do /me/player (repetir e aparelho) com o player cheio aberto.
    private let validade: TimeInterval
    /// Depois de uma falha (sem internet), espera isto antes de tentar de novo.
    private let espera: TimeInterval
    private let trava = NSLock()
    private var jogador: JogadorSpotify?
    private var jogadorEm: Date?
    private var tentouEm: Date?
    private var curtidas: [String: Bool] = [:]
    private var curtidasEm: [String: Date] = [:]
    private var abertoAte: Date?
    /// O último modo de repetir que se sabe ("faixa", "contexto", "nao"): o AppleScript só diz ligado ou desligado, então
    /// "só a música" vem do que o Deck escolheu ou da última leitura da API.
    private var modo: String?
    private var atualizando = false

    /// A curtida de uma faixa é lida uma vez (na troca de faixa) e guardada por tanto tempo. Curtir pelo Deck atualiza na hora.
    static let validadeDaCurtida: TimeInterval = 6 * 3600
    /// Com o player cheio (ou a lista de aparelhos ou a fila) aberto, ele conta como em uso por este tempo desde a última abertura.
    static let janelaDoPlayerAberto: TimeInterval = 120
    private static let maxCurtidas = 200

    init(conta: ContaSpotify, validade: TimeInterval = 30, espera: TimeInterval = 30,
         disparar: @escaping Disparador = { trabalho in DispatchQueue.global(qos: .utility).async(execute: trabalho) }) {
        self.conta = conta
        self.validade = validade
        self.espera = espera
        self.disparar = disparar
    }

    /// O player cheio, a lista de aparelhos ou a fila foram abertos: nos próximos minutos vale ler a API mesmo com o Spotify pausado,
    /// e o /me/player é relido na hora (`renovar`) para o repetir e o aparelho estarem certos.
    func abrirPlayer(agora: Date = Date(), renovar: Bool = true) {
        trava.lock()
        abertoAte = agora.addingTimeInterval(Self.janelaDoPlayerAberto)
        if renovar { jogadorEm = nil }
        trava.unlock()
    }

    /// Mudou algo que o /me/player mostra (trocou de aparelho): a próxima leitura vem da API de novo.
    func invalidar() {
        trava.lock(); jogadorEm = nil; trava.unlock()
    }

    /// Soma ao estado o que vem da API. Sem login só marca `conectado = false`, e o painel esconde o resto.
    func aplicar(_ estado: EstadoSpotify, uri: String?, agora: Date = Date()) -> EstadoSpotify {
        var e = estado
        guard conta.conectado else {
            e.conectado = false
            trava.lock(); jogador = nil; jogadorEm = nil; tentouEm = nil; curtidas = [:]; curtidasEm = [:]; abertoAte = nil; modo = nil; trava.unlock()
            return e
        }
        e.conectado = true
        conta.resumirChamadas()
        let resta = conta.limiteRestante()
        e.limitadoAte = resta.map { agora.addingTimeInterval($0).timeIntervalSince1970.rounded(.up) }
        trava.lock()
        // Repetir e aleatório já vêm do AppleScript (estado.repetir). Da API só falta separar "a música" de "a lista".
        if estado.repetir == false { modo = "nao"; jogador?.repetir = "nao" } else if estado.repetir == true, modo == nil || modo == "nao" { modo = jogador?.repetir.flatMap { $0 == "nao" ? nil : $0 } ?? "contexto" }
        e.repetirFaixa = modo.map { $0 == "faixa" }
        e.aparelho = jogador?.aparelho
        if let uri, let c = curtidas[uri] { e.curtida = c }
        let aberto = abertoAte.map { agora < $0 } ?? false
        let emUso = estado.tocando || aberto
        // /me/player só para o aparelho e para confirmar o modo de repetir: uma vez, e depois só com o player cheio, a fila ou os aparelhos abertos.
        let velho = jogadorEm.map { aberto && agora.timeIntervalSince($0) >= validade } ?? true
        let faltaCurtida = uri != nil && Self.faltaCurtida(curtidasEm[uri!], agora)
        let esperando = tentouEm.map { agora.timeIntervalSince($0) < espera } ?? false
        let iniciar = emUso && resta == nil && (velho || faltaCurtida) && !atualizando && !esperando
        if iniciar { atualizando = true; tentouEm = agora }
        trava.unlock()
        if iniciar { disparar { [self] in atualizar(uri: uri, agora: agora) } }
        return e
    }

    private static func faltaCurtida(_ em: Date?, _ agora: Date) -> Bool {
        em.map { agora.timeIntervalSince($0) >= validadeDaCurtida } ?? true
    }

    /// Lê a API e guarda, só o que está faltando: o /me/player se venceu, a curtida se a faixa ainda não foi lida.
    /// Público para o teste chamar direto.
    func atualizar(uri: String?, agora: Date = Date()) {
        defer { trava.lock(); atualizando = false; trava.unlock() }
        var falhou = false
        trava.lock()
        let aberto = abertoAte.map { agora < $0 } ?? false
        let jogadorVelho = jogadorEm.map { aberto && agora.timeIntervalSince($0) >= validade } ?? true
        trava.unlock()
        if jogadorVelho {
            switch conta.jogador() {
            case .success(let j):
                trava.lock(); jogador = j; jogadorEm = agora; if let r = j.repetir { modo = r }; trava.unlock()
            case .failure(let f):
                falhou = true
                if f == .esperar { return }
            }
        }
        trava.lock(); let curtidaVelha = uri.map { Self.faltaCurtida(curtidasEm[$0], agora) } ?? false; trava.unlock()
        if let uri, curtidaVelha {
            switch conta.curtida(uri) {
            case .success(let c): guardarCurtida(uri, c, agora)
            case .failure: falhou = true
            }
        }
        if !falhou { trava.lock(); tentouEm = nil; trava.unlock() }
    }

    private func guardarCurtida(_ uri: String, _ valor: Bool, _ agora: Date) {
        trava.lock()
        if curtidas.count >= Self.maxCurtidas, curtidas[uri] == nil, let velha = curtidasEm.min(by: { $0.value < $1.value })?.key {
            curtidas[velha] = nil; curtidasEm[velha] = nil
        }
        curtidas[uri] = valor; curtidasEm[uri] = agora
        trava.unlock()
    }

    /// Depois de curtir ou mudar a repetição, o estado já mostra o novo valor sem esperar a API.
    func marcarCurtida(_ uri: String, _ valor: Bool) { guardarCurtida(uri, valor, Date()) }

    func marcarRepetir(_ modo: String) {
        trava.lock()
        var j = jogador ?? JogadorSpotify()
        j.repetir = modo
        jogador = j
        self.modo = modo
        if jogadorEm == nil { jogadorEm = Date() }
        trava.unlock()
    }
}
