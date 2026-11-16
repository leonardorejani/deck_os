import XCTest
@testable import Nucleo

/// Relógio de mentira, compartilhado entre a conta (429, resumo por minuto) e o complemento.
final class RelogioDoLimite: @unchecked Sendable {
    private let trava = NSLock()
    private var t: Date
    init(_ t: Date) { self.t = t }
    var agora: Date { trava.lock(); defer { trava.unlock() }; return t }
    func ir(_ s: TimeInterval) { trava.lock(); t = t.addingTimeInterval(s); trava.unlock() }
}

final class LogDoLimite: @unchecked Sendable {
    private let trava = NSLock()
    private var _linhas: [String] = []
    var linhas: [String] { trava.lock(); defer { trava.unlock() }; return _linhas }
    func gravar(_ l: String) { trava.lock(); _linhas.append(l); trava.unlock() }
}

/// Prova o gasto da API do Spotify: cada chamada conta para o limite do app inteiro (a chave do Deck é uma só).
final class SpotifyLimiteTestes: XCTestCase {
    private func montar(_ resposta: @escaping @Sendable (RequisicaoWeb) -> RespostaWeb?) -> (TransporteFalso, ContaSpotify, ComplementoSpotify, RelogioDoLimite, LogDoLimite) {
        let rel = RelogioDoLimite(Date(timeIntervalSince1970: 2_000_000))
        let t = TransporteFalso(resposta)
        let conta = ContaSpotify(armazem: ArmazemSpotifyMemoria(DadosSpotify(clientId: chaveDeTeste, acesso: "ACESSO", renovacao: "RENOVA",
                                                                            expiraEm: rel.agora.timeIntervalSince1970 + 90_000)),
                                 transporte: t, agora: { rel.agora })
        let reg = LogDoLimite()
        conta.registrar = { reg.gravar($0) }
        return (t, conta, ComplementoSpotify(conta: conta, disparar: { $0() }), rel, reg)
    }

    private let ok: @Sendable (RequisicaoWeb) -> RespostaWeb? = { r in
        r.url.contains("/contains") ? respostaJson(200, [false]) : respostaJson(200, ["repeat_state": "off", "device": ["name": "Mac"]])
    }

    private func estado(tocando: Bool) -> EstadoSpotify {
        EstadoSpotify(tocando: tocando, faixa: "A", artista: "B", posicao: 0, duracao: 210, capaId: nil, cores: [], repetir: false)
    }

    /// 1 h com um painel pedindo o estado a cada 1 s e o Spotify tocando (uma música nova a cada 3 min 30 s).
    func testUmaHoraDePainelAbertoTocandoGastaDezenasDeChamadas() {
        let (t, _, comp, rel, _) = montar(ok)
        for s in 0..<3600 {
            _ = comp.aplicar(estado(tocando: true), uri: "spotify:track:f\(s / 210)", agora: rel.agora)
            rel.ir(1)
        }
        print("CONTA spotify-limite: 1 h painel aberto tocando = \(t.pedidos.count) chamadas (antes da correção: 840 medidas com o código antigo)")
        XCTAssertLessThanOrEqual(t.pedidos.count, 30)
        XCTAssertEqual(t.pedidos.filter { $0.url.contains("/contains") }.count, 18, "uma por faixa")
    }

    func testUmaHoraComPainelFechadoOuSpotifyPausadoNaoChamaNada() {
        let (t, _, comp, rel, _) = montar(ok)
        // Painel fechado: ninguém pede o estado, então ninguém chama o complemento.
        rel.ir(3600)
        XCTAssertEqual(t.pedidos.count, 0)
        // Painel aberto com o Spotify pausado e ninguém no player: também nada.
        for _ in 0..<3600 { _ = comp.aplicar(estado(tocando: false), uri: "spotify:track:f0", agora: rel.agora); rel.ir(1) }
        XCTAssertEqual(t.pedidos.count, 0)
        // Abrir o player cheio libera a leitura por um tempo (aparelho e modo de repetir).
        comp.abrirPlayer(agora: rel.agora)
        _ = comp.aplicar(estado(tocando: false), uri: "spotify:track:f0", agora: rel.agora)
        XCTAssertEqual(t.pedidos.count, 2)
    }

    func testComLimiteDoSpotifyNaoTentaDeNovoEAvisaAteQuando() {
        let (t, conta, comp, rel, reg) = montar { r in
            r.url.contains("/contains") ? RespostaWeb(status: 429, corpo: Data(), esperar: 26_657) : respostaJson(200, ["repeat_state": "off"])
        }
        let e0 = comp.aplicar(estado(tocando: true), uri: "spotify:track:f0", agora: rel.agora)
        XCTAssertNil(e0.limitadoAte)
        let depoisDoPrimeiro = t.pedidos.count
        rel.ir(1)
        let e1 = comp.aplicar(estado(tocando: true), uri: "spotify:track:f0", agora: rel.agora)
        XCTAssertEqual(e1.limitadoAte ?? 0, (rel.agora.timeIntervalSince1970 + 26_656).rounded(.up), accuracy: 1)
        for _ in 0..<3600 { rel.ir(1); _ = comp.aplicar(estado(tocando: true), uri: "spotify:track:f0", agora: rel.agora) }
        XCTAssertEqual(t.pedidos.count, depoisDoPrimeiro, "durante o bloqueio nenhum pedido sai")
        XCTAssertNotNil(conta.bloqueadoAte)
        XCTAssertTrue(reg.linhas.contains { $0.contains("HTTP 429") && $0.contains("26657") })
        // O bloqueio passa: volta a ler.
        rel.ir(26_657)
        XCTAssertNil(comp.aplicar(estado(tocando: true), uri: "spotify:track:f0", agora: rel.agora).limitadoAte)
    }

    func testTocarPausarEPularSeguemSemAApiNoBloqueio() {
        let (t, conta, _, rel, _) = montar { _ in RespostaWeb(status: 429, corpo: Data(), esperar: 3600) }
        _ = conta.curtida("spotify:track:x")
        let antes = t.pedidos.count
        XCTAssertNotNil(conta.limiteRestante())
        let exec = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "ok\n"))])
        let s = SpotifyReal(executor: exec, conta: conta)
        for a in ["tocar", "pausar", "proxima", "anterior"] { XCTAssertNil(s.acao(a), a) }
        XCTAssertEqual(t.pedidos.count, antes, "as ações vão pelo AppleScript, sem a API")
        _ = rel
    }

    func testFilaGuardadaPor10sEPedidosJuntosNaoSeDuplicam() {
        let (t, conta, _, rel, _) = montar { r in
            r.url.contains("/queue") ? respostaJson(200, ["currently_playing": ["name": "A", "uri": "u:a"], "queue": [["name": "B", "uri": "u:b"]]]) : respostaJson(200, [:])
        }
        func lidas() -> Int { t.pedidos.filter { $0.url.contains("/queue") }.count }
        _ = conta.fila(); _ = conta.fila()
        XCTAssertEqual(lidas(), 1)
        let grupo = DispatchGroup()
        for _ in 0..<6 { DispatchQueue.global().async(group: grupo) { _ = conta.fila() } }
        grupo.wait()
        XCTAssertEqual(lidas(), 1, "pedidos em paralelo dentro da validade usam a mesma leitura")
        rel.ir(11)
        _ = conta.fila()
        XCTAssertEqual(lidas(), 2)
        _ = conta.fila(fresca: true)
        XCTAssertEqual(lidas(), 3, "o pulo lê a fila de agora")
        _ = conta.cancelarCorrecaoDoPulo()
        _ = conta.fila()
        XCTAssertEqual(lidas(), 4, "uma ação que muda o que toca descarta a fila guardada")
    }

    func testResumoPorMinutoNoLogContaPorRotaESemToken() {
        let (_, conta, comp, rel, reg) = montar(ok)
        for _ in 0..<130 { _ = comp.aplicar(estado(tocando: true), uri: "spotify:track:f0", agora: rel.agora); rel.ir(1) }
        let resumos = reg.linhas.filter { $0.contains("chamadas à API no último minuto") }
        XCTAssertEqual(resumos.count, 1, "uma linha por minuto com chamadas, e minuto sem chamada não escreve")
        XCTAssertTrue(resumos[0].contains("GET /me/player=1"), resumos[0])
        XCTAssertTrue(resumos[0].contains("GET /me/library/contains=1"), resumos[0])
        XCTAssertTrue(resumos[0].contains(": 2 ("), resumos[0])
        XCTAssertFalse(reg.linhas.joined().contains("ACESSO"))
        _ = conta
    }
}
