import XCTest
@testable import Nucleo

/// Transporte de mentira: guarda os pedidos e responde pelo roteiro (a API do Spotify nunca é chamada de verdade).
final class TransporteFalso: TransporteWeb, @unchecked Sendable {
    private let trava = NSLock()
    private var _pedidos: [RequisicaoWeb] = []
    var resposta: @Sendable (RequisicaoWeb) -> RespostaWeb?
    init(_ resposta: @escaping @Sendable (RequisicaoWeb) -> RespostaWeb?) { self.resposta = resposta }
    var pedidos: [RequisicaoWeb] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func enviar(_ r: RequisicaoWeb) -> RespostaWeb? {
        trava.lock(); _pedidos.append(r); trava.unlock()
        return resposta(r)
    }
}

func respostaJson(_ status: Int = 200, _ obj: Any? = nil) -> RespostaWeb {
    RespostaWeb(status: status, corpo: obj.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data())
}

/// O 403 do Spotify para conta fora da lista de um app em modo de desenvolvimento.
func respostaForaDaLista() -> RespostaWeb {
    respostaJson(403, ["error": ["status": 403, "message": "User not registered in the Developer Dashboard"]])
}

let chaveDeTeste = "0123456789abcdef0123456789abcdef"

func tokenOk(acesso: String = "ACESSO", renovacao: String? = "RENOVA", expira: Int = 3600) -> RespostaWeb {
    var o: [String: Any] = ["access_token": acesso, "token_type": "Bearer", "expires_in": expira]
    if let renovacao { o["refresh_token"] = renovacao }
    return respostaJson(200, o)
}

func corpoTexto(_ r: RequisicaoWeb) -> String { String(decoding: r.corpo ?? Data(), as: UTF8.self) }

final class SpotifyApiTestes: XCTestCase {
    // MARK: PKCE

    func testSha256ComVetoresConhecidos() {
        func hex(_ s: String) -> String { Sha256.resumo(Array(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Duas passadas de bloco (mais de 55 bytes).
        XCTAssertEqual(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testDesafioPkceBateComOExemploDaRfc7636() {
        XCTAssertEqual(Pkce.desafio("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerificadorTemTamanhoEAlfabetoDaNorma() {
        let v = Pkce.verificador()
        XCTAssertEqual(v.count, 64)
        XCTAssertTrue(v.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) })
        XCTAssertNotEqual(v, Pkce.verificador())
    }

    // MARK: Login

    private func conta(_ t: TransporteFalso, _ dados: DadosSpotify = DadosSpotify(clientId: chaveDeTeste), agora: @escaping @Sendable () -> Date = { Date() }) -> (ContaSpotify, ArmazemSpotifyMemoria) {
        let a = ArmazemSpotifyMemoria(dados)
        return (ContaSpotify(armazem: a, transporte: t, agora: agora), a)
    }

    private func logada(_ t: TransporteFalso, expira: Double? = nil, agora: @escaping @Sendable () -> Date = { Date() }) -> (ContaSpotify, ArmazemSpotifyMemoria) {
        conta(t, DadosSpotify(clientId: chaveDeTeste, acesso: "ACESSO", renovacao: "RENOVA",
                              expiraEm: expira ?? agora().timeIntervalSince1970 + 3000), agora: agora)
    }

    private let chaveDoDeck = "fedcba9876543210fedcba9876543210"

    private func comEmbutida(_ embutida: String?, _ dados: DadosSpotify = DadosSpotify()) -> (ContaSpotify, ArmazemSpotifyMemoria) {
        let a = ArmazemSpotifyMemoria(dados)
        return (ContaSpotify(armazem: a, transporte: TransporteFalso { _ in nil }, embutida: embutida), a)
    }

    func testChaveEmbutidaValeQuandoNaoHaColada() throws {
        let (c, _) = comEmbutida(chaveDoDeck)
        XCTAssertEqual(c.clientId, chaveDoDeck)
        XCTAssertTrue(c.temChaveEmbutida)
        XCTAssertNil(c.chavePropria)
        let p = try XCTUnwrap(try? c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get())
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: p.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["client_id"], chaveDoDeck)
    }

    func testChaveColadaVenceAEmbutida() {
        let (c, _) = comEmbutida(chaveDoDeck, DadosSpotify(clientId: chaveDeTeste))
        XCTAssertEqual(c.clientId, chaveDeTeste)
        XCTAssertEqual(c.chavePropria, chaveDeTeste)
    }

    func testChaveEmbutidaInvalidaViraAusente() {
        for ruim in [nil, "", "curta", String(repeating: "z", count: 32), chaveDoDeck + "0"] as [String?] {
            let (c, _) = comEmbutida(ruim)
            XCTAssertNil(c.clientId, ruim ?? "nil")
            XCTAssertFalse(c.temChaveEmbutida)
        }
        XCTAssertNil(ChaveSpotify.valida("curta"))
        XCTAssertEqual(ChaveSpotify.valida(" \(chaveDoDeck)\n"), chaveDoDeck)
    }

    /// O Client ID que vai no Deck tem que ser uma chave de verdade: 32 letras e números (hexadecimal).
    func testChaveEmbutidaDoDeckEValida() {
        let c = ChaveSpotify.embutida
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.count, 32)
        XCTAssertEqual(ChaveSpotify.valida(c), c)
        XCTAssertTrue(ContaSpotify(armazem: ArmazemSpotifyMemoria(), transporte: TransporteFalso { _ in nil }).temChaveEmbutida)
    }

    func testDesconectarComEmbutidaMantemAChaveColadaESemColadaNaoGuardaNada() {
        let (c, a) = comEmbutida(chaveDoDeck, DadosSpotify(clientId: chaveDeTeste, acesso: "A", renovacao: "R", expiraEm: 1))
        c.desconectar()
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(a.ler().clientId, chaveDeTeste)
        let (d, b) = comEmbutida(chaveDoDeck, DadosSpotify(acesso: "A", renovacao: "R", expiraEm: 1))
        XCTAssertTrue(d.conectado)
        d.desconectar()
        XCTAssertFalse(d.conectado)
        XCTAssertNil(b.ler().clientId)
        XCTAssertEqual(d.clientId, chaveDoDeck)
    }

    func testColarChaveDiferenteDaEmbutidaDesconectaOLoginDoDeck() {
        let (c, a) = comEmbutida(chaveDoDeck, DadosSpotify(acesso: "A", renovacao: "R", expiraEm: 1))
        XCTAssertTrue(c.conectado)
        XCTAssertNil(c.definirClientId(chaveDeTeste))
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(a.ler().clientId, chaveDeTeste)
    }

    func testVoltarParaAChaveDoDeckEsqueceAColadaEOLogin() {
        let (c, a) = comEmbutida(chaveDoDeck, DadosSpotify(clientId: chaveDeTeste, acesso: "A", renovacao: "R", expiraEm: 1))
        c.usarChaveDoDeck()
        XCTAssertNil(a.ler().clientId)
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(c.clientId, chaveDoDeck)
    }

    // MARK: Conta fora da lista do app do Deck (modo de desenvolvimento)

    private let logado = DadosSpotify(acesso: "ACESSO", renovacao: "RENOVA", expiraEm: Date().timeIntervalSince1970 + 3000)

    private func contaComTransporte(_ t: TransporteFalso, embutida: String?, _ dados: DadosSpotify) -> (ContaSpotify, ArmazemSpotifyMemoria) {
        let a = ArmazemSpotifyMemoria(dados)
        return (ContaSpotify(armazem: a, transporte: t, embutida: embutida), a)
    }

    /// Caminho 1: o Spotify deixa logar e devolve 403 na Web API. Com a chave do Deck, desconecta e pede a chave da pessoa.
    func testWebApi403ContaForaDaListaComChaveEmbutidaDesconectaEPedeChavePropria() {
        let t = TransporteFalso { _ in respostaForaDaLista() }
        let (c, a) = contaComTransporte(t, embutida: chaveDoDeck, logado)
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertEqual(e, .semCadastro)
        XCTAssertTrue(e.pedeChavePropria)
        XCTAssertTrue(e.texto.contains("pedem uma chave sua"))
        XCTAssertFalse(e.texto.contains("Developer Dashboard"))
        XCTAssertFalse(c.conectado)
        XCTAssertNil(a.ler().renovacao)
        XCTAssertTrue(c.precisaChavePropria)
    }

    func testWebApi403ComOutraMensagemDeCadastroTambemVale() {
        let t = TransporteFalso { _ in respostaJson(403, ["error": ["status": 403, "message": "Check settings on developer.spotify.com/dashboard, the user may not be registered."]]) }
        let (c, _) = contaComTransporte(t, embutida: chaveDoDeck, logado)
        guard case .failure(let e) = c.fila() else { return XCTFail() }
        XCTAssertEqual(e, .semCadastro)
    }

    /// Com chave própria o erro segue como hoje: recusa comum, sem desconectar nem mexer na tela.
    func testWebApi403ContaForaDaListaComChavePropriaSegueComoAntes() {
        let t = TransporteFalso { _ in respostaForaDaLista() }
        var dados = logado; dados.clientId = chaveDeTeste
        let (c, _) = contaComTransporte(t, embutida: chaveDoDeck, dados)
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertEqual(e, .recusou)
        XCTAssertFalse(e.pedeChavePropria)
        XCTAssertTrue(c.conectado)
        XCTAssertFalse(c.precisaChavePropria)
    }

    /// Caminho 2: o Spotify recusa no login (o retorno traz um erro que não é o de Cancelar).
    func testRetornoComErroDeCadastroComChaveEmbutidaPedeChavePropria() throws {
        let (c, a) = comEmbutida(chaveDoDeck)
        let p = try XCTUnwrap(try? c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get())
        let texto = c.concluirLogin(p, retorno: RetornoLogin(codigo: nil, estado: p.estado, erro: "invalid_client"))
        XCTAssertEqual(texto, ErroSpotify.semCadastro.texto)
        XCTAssertTrue(c.precisaChavePropria)
        XCTAssertFalse(c.conectado)
        XCTAssertNil(a.ler().renovacao)
    }

    func testCancelarNoSpotifyContinuaSendoCancelarMesmoComChaveEmbutida() throws {
        let (c, _) = comEmbutida(chaveDoDeck)
        let p = try XCTUnwrap(try? c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get())
        XCTAssertEqual(c.concluirLogin(p, retorno: RetornoLogin(codigo: nil, estado: p.estado, erro: "access_denied")), "O login do Spotify foi cancelado.")
        XCTAssertFalse(c.precisaChavePropria)
    }

    func testRetornoComErroComChavePropriaSegueComoAntes() throws {
        let (c, _) = comEmbutida(chaveDoDeck, DadosSpotify(clientId: chaveDeTeste))
        let p = try XCTUnwrap(try? c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get())
        XCTAssertEqual(c.concluirLogin(p, retorno: RetornoLogin(codigo: nil, estado: p.estado, erro: "invalid_client")), "O login do Spotify foi cancelado.")
        XCTAssertFalse(c.precisaChavePropria)
    }

    /// A troca do código pode vir com a mensagem de conta fora da lista.
    func testTrocaDeTokenRecusadaPorCadastroComChaveEmbutidaPedeChavePropria() throws {
        let t = TransporteFalso { _ in respostaForaDaLista() }
        let (c, _) = contaComTransporte(t, embutida: chaveDoDeck, DadosSpotify())
        let p = try XCTUnwrap(try? c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get())
        XCTAssertEqual(c.concluirLogin(p, retorno: RetornoLogin(codigo: "X", estado: p.estado, erro: nil)), ErroSpotify.semCadastro.texto)
        XCTAssertTrue(c.precisaChavePropria)
    }

    func testColarChavePropriaLimpaOPedidoDeChavePropria() {
        let t = TransporteFalso { _ in respostaForaDaLista() }
        let (c, _) = contaComTransporte(t, embutida: chaveDoDeck, logado)
        _ = c.dispositivos()
        XCTAssertTrue(c.precisaChavePropria)
        XCTAssertNil(c.definirClientId(chaveDeTeste))
        XCTAssertFalse(c.precisaChavePropria)
    }

    func testChaveDoAppPrecisaTer32CaracteresHexadecimais() {
        let (c, a) = conta(TransporteFalso { _ in nil }, DadosSpotify())
        XCTAssertNotNil(c.definirClientId("curta"))
        XCTAssertNotNil(c.definirClientId(String(repeating: "z", count: 32)))
        XCTAssertNil(a.ler().clientId)
        XCTAssertNil(c.definirClientId("  \(chaveDeTeste)\n"))
        XCTAssertEqual(c.clientId, chaveDeTeste)
    }

    func testTrocarAChaveDesconectaOLoginAntigo() {
        let (c, a) = logada(TransporteFalso { _ in nil })
        XCTAssertTrue(c.conectado)
        XCTAssertNil(c.definirClientId(String(repeating: "a", count: 32)))
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(a.ler().clientId, String(repeating: "a", count: 32))
    }

    func testUrlDeLoginTemPkceEstadoEEscopos() throws {
        let (c, _) = conta(TransporteFalso { _ in nil })
        let p = try c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get()
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: p.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(p.url.host, "accounts.spotify.com")
        XCTAssertEqual(p.url.path, "/authorize")
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["client_id"], chaveDeTeste)
        XCTAssertEqual(q["redirect_uri"], "http://127.0.0.1:4778/retorno")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["code_challenge"], Pkce.desafio(p.verificador))
        XCTAssertEqual(q["state"], p.estado)
        for e in ["user-read-playback-state", "user-modify-playback-state", "user-library-read", "user-library-modify", "user-read-recently-played"] {
            XCTAssertTrue((q["scope"] ?? "").contains(e), e)
        }
        XCTAssertNil(q["client_secret"])
    }

    func testLoginSemChaveNaoComeca() {
        // Fork sem chave embutida: o caso que o teste cobre continua sendo "nenhuma chave".
        let (c, _) = comEmbutida(nil)
        if case .success = c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno") { XCTFail("não devia preparar") }
    }

    func testConcluirLoginTrocaOCodigoESoGuardaNoArmazem() throws {
        let t = TransporteFalso { _ in tokenOk() }
        let (c, a) = conta(t, agora: { Date(timeIntervalSince1970: 1_000) })
        let p = try c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get()
        XCTAssertNil(c.concluirLogin(p, retorno: RetornoLogin(codigo: "COD", estado: p.estado, erro: nil)))
        let pedido = try XCTUnwrap(t.pedidos.first)
        XCTAssertEqual(pedido.url, "https://accounts.spotify.com/api/token")
        let corpo = corpoTexto(pedido)
        XCTAssertTrue(corpo.contains("grant_type=authorization_code"))
        XCTAssertTrue(corpo.contains("code=COD"))
        XCTAssertTrue(corpo.contains("code_verifier=\(p.verificador)"))
        XCTAssertTrue(corpo.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A4778%2Fretorno"))
        XCTAssertFalse(corpo.contains("secret"))
        let d = a.ler()
        XCTAssertEqual(d.acesso, "ACESSO")
        XCTAssertEqual(d.renovacao, "RENOVA")
        XCTAssertEqual(d.expiraEm, 4_600)
        XCTAssertTrue(c.conectado)
    }

    func testRetornoComEstadoDeOutroLoginOuCancelamentoNaoConecta() throws {
        let t = TransporteFalso { _ in tokenOk() }
        let (c, _) = conta(t)
        let p = try c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get()
        XCTAssertNotNil(c.concluirLogin(p, retorno: RetornoLogin(codigo: "COD", estado: "outro", erro: nil)))
        XCTAssertNotNil(c.concluirLogin(p, retorno: RetornoLogin(codigo: nil, estado: p.estado, erro: "access_denied")))
        XCTAssertEqual(t.pedidos.count, 0)
        XCTAssertFalse(c.conectado)
    }

    func testChaveNaoReconhecidaViraMensagemClara() throws {
        let t = TransporteFalso { _ in respostaJson(400, ["error": "invalid_client"]) }
        let (c, _) = conta(t)
        let p = try c.prepararLogin(redirecionamento: "http://127.0.0.1:4778/retorno").get()
        let erro = c.concluirLogin(p, retorno: RetornoLogin(codigo: "COD", estado: p.estado, erro: nil))
        XCTAssertTrue(erro?.contains("chave") ?? false)
    }

    // MARK: Renovação

    func testTokenQueVenceEmBreveETrocadoAntesDaChamada() {
        let agora = Date(timeIntervalSince1970: 10_000)
        let t = TransporteFalso { r in
            r.url.contains("/api/token") ? tokenOk(acesso: "NOVO", renovacao: nil) : respostaJson(200, ["devices": []])
        }
        let (c, a) = logada(t, expira: 10_030, agora: { agora })
        _ = c.dispositivos()
        XCTAssertEqual(t.pedidos.count, 2)
        XCTAssertTrue(corpoTexto(t.pedidos[0]).contains("grant_type=refresh_token"))
        XCTAssertTrue(corpoTexto(t.pedidos[0]).contains("refresh_token=RENOVA"))
        XCTAssertEqual(t.pedidos[1].cabecalhos["Authorization"], "Bearer NOVO")
        // O Spotify não mandou outro refresh token: o antigo continua valendo.
        XCTAssertEqual(a.ler().renovacao, "RENOVA")
        XCTAssertEqual(a.ler().expiraEm, 13_600)
    }

    func testTokenValidoNaoPedeRenovacao() {
        let t = TransporteFalso { _ in respostaJson(200, ["devices": []]) }
        let (c, _) = logada(t)
        _ = c.dispositivos(); _ = c.dispositivos()
        XCTAssertEqual(t.pedidos.count, 2)
        XCTAssertTrue(t.pedidos.allSatisfy { $0.url.hasPrefix("https://api.spotify.com/v1/") })
    }

    func testRefreshTokenNovoDoSpotifyEGuardado() {
        let agora = Date(timeIntervalSince1970: 10_000)
        let t = TransporteFalso { r in r.url.contains("/api/token") ? tokenOk(acesso: "N", renovacao: "RENOVA2") : respostaJson(200, ["devices": []]) }
        let (c, a) = logada(t, expira: 10_000, agora: { agora })
        _ = c.dispositivos()
        XCTAssertEqual(a.ler().renovacao, "RENOVA2")
    }

    func testRespostaDe401TrocaOTokenETentaUmaVezMais() {
        let chamadas = Contador()
        let t = TransporteFalso { r in
            if r.url.contains("/api/token") { return tokenOk(acesso: "DEPOIS", renovacao: nil) }
            chamadas.somar()
            return chamadas.valor == 1 ? respostaJson(401, ["error": ["status": 401, "message": "The access token expired"]]) : respostaJson(200, ["devices": []])
        }
        let (c, _) = logada(t)
        guard case .success = c.dispositivos() else { return XCTFail("devia ter dado certo na segunda") }
        XCTAssertEqual(t.pedidos.map { $0.cabecalhos["Authorization"] ?? "-" }, ["Bearer ACESSO", "-", "Bearer DEPOIS"])
    }

    func testLoginRecusadoDeVezApagaOsTokensMasGuardaAChave() {
        let agora = Date(timeIntervalSince1970: 10_000)
        let t = TransporteFalso { _ in respostaJson(400, ["error": "invalid_grant"]) }
        let (c, a) = logada(t, expira: 10_000, agora: { agora })
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertTrue(e.semLogin)
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(a.ler().clientId, chaveDeTeste)
        XCTAssertNil(a.ler().renovacao)
    }

    func testSemInternetNaRenovacaoNaoDesconecta() {
        let agora = Date(timeIntervalSince1970: 10_000)
        let t = TransporteFalso { _ in nil }
        let (c, _) = logada(t, expira: 10_000, agora: { agora })
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertEqual(e, .semRede)
        XCTAssertTrue(c.conectado)
    }

    func testDesconectarApagaOsTokensEGuardaAChave() {
        let (c, a) = logada(TransporteFalso { _ in nil })
        c.desconectar()
        XCTAssertFalse(c.conectado)
        XCTAssertEqual(a.ler().clientId, chaveDeTeste)
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertEqual(e, .naoConectado)
    }

    // MARK: Chamadas da API

    func testListaDeAparelhos() throws {
        let t = TransporteFalso { _ in respostaJson(200, ["devices": [
            ["id": "d1", "is_active": true, "is_restricted": false, "name": "MacBook do Leo", "type": "Computer", "volume_percent": 55],
            ["id": "d2", "is_active": false, "is_restricted": false, "name": "Caixa da sala", "type": "Speaker", "volume_percent": 30],
            ["id": "d3", "is_active": false, "is_restricted": true, "name": "TV", "type": "TV"],
        ]]) }
        let (c, _) = logada(t)
        let lista = try c.dispositivos().get()
        XCTAssertEqual(lista, [
            DispositivoSpotify(id: "d1", nome: "MacBook do Leo", tipo: "computer", ativo: true, volume: 55, restrito: false),
            DispositivoSpotify(id: "d2", nome: "Caixa da sala", tipo: "speaker", ativo: false, volume: 30, restrito: false),
            DispositivoSpotify(id: "d3", nome: "TV", tipo: "tv", ativo: false, volume: nil, restrito: true),
        ])
        XCTAssertEqual(t.pedidos.last?.url, "https://api.spotify.com/v1/me/player/devices")
    }

    func testTransferirMandaOAparelhoNoCorpo() throws {
        let t = TransporteFalso { _ in respostaJson(204) }
        let (c, _) = logada(t)
        XCTAssertNil(c.transferir(para: "d2"))
        let p = try XCTUnwrap(t.pedidos.last)
        XCTAssertEqual(p.metodo, "PUT")
        XCTAssertEqual(p.url, "https://api.spotify.com/v1/me/player")
        let corpo = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(p.corpo)) as? [String: Any])
        XCTAssertEqual(corpo["device_ids"] as? [String], ["d2"])
        XCTAssertNotNil(c.transferir(para: ""))
    }

    func testCurtirEDescurtirUsamAUriDaFaixa() throws {
        let t = TransporteFalso { _ in respostaJson(200) }
        let (c, _) = logada(t)
        XCTAssertNil(c.curtir("spotify:track:4uLU6hMCjMI75M1A2tKUQC", true))
        XCTAssertNil(c.curtir("spotify:track:4uLU6hMCjMI75M1A2tKUQC", false))
        XCTAssertEqual(t.pedidos.map { $0.metodo }, ["PUT", "DELETE"])
        XCTAssertEqual(t.pedidos[0].url, "https://api.spotify.com/v1/me/library?uris=spotify%3Atrack%3A4uLU6hMCjMI75M1A2tKUQC")
        // Arquivo local e texto solto não vão para a API.
        XCTAssertNotNil(c.curtir("spotify:local:Artista:Album:Faixa:200", true))
        XCTAssertNotNil(c.curtir("spotify:track:", true))
        XCTAssertNotNil(c.curtir("https://x/y", true))
        XCTAssertEqual(t.pedidos.count, 2)
    }

    func testSaberSeFaixaEstaCurtida() throws {
        let t = TransporteFalso { _ in respostaJson(200, [true]) }
        let (c, _) = logada(t)
        XCTAssertTrue(try c.curtida("spotify:track:abc123").get())
        XCTAssertEqual(t.pedidos.last?.url, "https://api.spotify.com/v1/me/library/contains?uris=spotify%3Atrack%3Aabc123")
    }

    func testFilaComMusicaEPodcast() throws {
        let t = TransporteFalso { _ in respostaJson(200, [
            "currently_playing": ["name": "Agora", "artists": [["name": "Coral"]]],
            "queue": [
                ["name": "Próxima", "artists": [["name": "Ana"], ["name": "Beto"]]],
                ["name": "Episódio 4", "show": ["name": "Podcast"]],
                ["sem": "nome"],
            ],
        ]) }
        let (c, _) = logada(t)
        let f = try c.fila().get()
        XCTAssertEqual(f.atual, ItemDaFila(faixa: "Agora", artista: "Coral"))
        XCTAssertEqual(f.proximas, [ItemDaFila(faixa: "Próxima", artista: "Ana, Beto"), ItemDaFila(faixa: "Episódio 4", artista: "Podcast")])
    }

    func testFilaTrazUriCapaPequenaENomeDaLista() throws {
        let t = TransporteFalso { r in
            let imagens: [[String: Any]] = [["url": "https://i/640", "width": 640], ["url": "https://i/300", "width": 300], ["url": "https://i/64", "width": 64]]
            if r.url.hasSuffix("/me/player/queue") {
                return respostaJson(200, ["currently_playing": ["name": "Agora", "artists": [["name": "Coral"]], "uri": "u:0", "album": ["images": imagens]],
                                         "queue": [["name": "Depois", "artists": [["name": "Ana"]], "uri": "u:1", "album": ["images": imagens]]]])
            }
            if r.url.hasSuffix("/me/player") { return respostaJson(200, ["context": ["uri": "spotify:playlist:abc", "type": "playlist"]]) }
            if r.url.contains("/playlists/abc") { return respostaJson(200, ["name": "Minha Lista"]) }
            return nil
        }
        let (c, _) = logada(t)
        let f = try c.fila().get()
        XCTAssertEqual(f.contexto, "Minha Lista")
        XCTAssertEqual(f.atual, ItemDaFila(faixa: "Agora", artista: "Coral", uri: "u:0", capa: "https://i/300"))
        XCTAssertEqual(f.proximas, [ItemDaFila(faixa: "Depois", artista: "Ana", uri: "u:1", capa: "https://i/300")])
        _ = try c.fila().get()
        XCTAssertEqual(t.pedidos.filter { $0.url.contains("/playlists/abc") }.count, 1, "o nome da lista é pedido uma vez só")
    }

    func testFilaSemNomeDeListaSegueSemContexto() throws {
        let t = TransporteFalso { r in
            r.url.hasSuffix("/me/player/queue") ? respostaJson(200, ["queue": [["name": "X", "artists": [["name": "A"]]]]])
                : respostaJson(403, ["error": ["status": 403, "message": "Forbidden"]])
        }
        let (c, _) = logada(t)
        let f = try c.fila().get()
        XCTAssertNil(f.contexto)
        XCTAssertEqual(f.proximas.map { $0.faixa }, ["X"])
    }

    /// Fila de mentira de uma lista: toca "agora" e vêm a, b, c, d, e. `offsetAceito` diz se o Spotify aceita o salto na lista.
    private func filaDeLista(contexto: String? = "spotify:playlist:p", tocaAposPlay: String? = nil, offsetAceito: Bool = true) -> TransporteFalso {
        let nomes = ["a", "b", "c", "d", "e"]
        return TransporteFalso { r in
            if r.url.hasSuffix("/me/player/queue") {
                return respostaJson(200, ["queue": nomes.map { ["name": $0, "artists": [["name": "X"]], "uri": "u:\($0)"] }])
            }
            if r.metodo == "GET" && r.url.hasSuffix("/me/player") {
                var o: [String: Any] = ["item": ["uri": tocaAposPlay ?? "u:agora"]]
                if let contexto { o["context"] = ["uri": contexto] }
                return respostaJson(200, o)
            }
            if r.metodo == "GET" { return respostaJson(200, ["name": "Lista"]) }
            if r.metodo == "PUT", !offsetAceito, r.url.hasSuffix("/me/player/play"),
               String(data: r.corpo ?? Data(), encoding: .utf8)?.contains("context_uri") == true {
                return respostaJson(404, ["error": ["status": 404, "message": "Not found"]])
            }
            return respostaJson(204)
        }
    }

    private func corpoJson(_ r: RequisicaoWeb) -> [String: Any] {
        (r.corpo.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    func testPularNaFilaDaListaSaltaDiretoSemTocarAsDoMeio() {
        let t = filaDeLista(tocaAposPlay: "u:d")
        let (c, _) = logada(t); c.esperaDoPulo = 0
        XCTAssertNil(c.pularFila(posicao: 1, uri: "u:d"), "a vez certa vem da fila de agora, não do que a tela achava")
        XCTAssertTrue(t.pedidos.filter { $0.url.hasSuffix("/me/player/next") }.isEmpty, "nenhum next: as do meio não tocam")
        let plays = t.pedidos.filter { $0.metodo == "PUT" && $0.url.hasSuffix("/me/player/play") }
        XCTAssertEqual(plays.count, 1, "um play só, direto na escolhida")
        XCTAssertEqual(corpoJson(plays[0])["context_uri"] as? String, "spotify:playlist:p")
        XCTAssertEqual((corpoJson(plays[0])["offset"] as? [String: Any])?["uri"] as? String, "u:d")
    }

    func testPularNaFilaForaDaListaTocaAEscolhidaESeguintesSemAsDoMeio() {
        // Faixa da fila manual: a lista recusa o offset e o play toca outra coisa.
        let t = filaDeLista(offsetAceito: false)
        let (c, _) = logada(t); c.esperaDoPulo = 0
        XCTAssertNil(c.pularFila(posicao: 3, uri: "u:c"))
        XCTAssertTrue(t.pedidos.filter { $0.url.hasSuffix("/me/player/next") }.isEmpty)
        let ultimo = t.pedidos.last { $0.metodo == "PUT" }!
        XCTAssertEqual(corpoJson(ultimo)["uris"] as? [String], ["u:c", "u:d", "u:e"], "a escolhida e as que vinham depois, nada de a e b")
    }

    func testPularNaFilaQuandoOSpotifyAceitaMasToCaOutraCoisaCaiNoPlayDeUris() {
        let t = filaDeLista(tocaAposPlay: "u:agora")
        let (c, _) = logada(t); c.esperaDoPulo = 0
        XCTAssertNil(c.pularFila(posicao: 2, uri: "u:b"))
        XCTAssertEqual(corpoJson(t.pedidos.last { $0.metodo == "PUT" }!)["uris"] as? [String], ["u:b", "u:c", "u:d", "u:e"])
        XCTAssertTrue(t.pedidos.filter { $0.url.hasSuffix("/me/player/next") }.isEmpty)
    }

    func testPularNaFilaDeArtistaOuSemContextoUsaUris() {
        for contexto in ["spotify:artist:z", nil] {
            let t = filaDeLista(contexto: contexto)
            let (c, _) = logada(t); c.esperaDoPulo = 0
            XCTAssertNil(c.pularFila(posicao: 4, uri: "u:d"))
            XCTAssertFalse(t.pedidos.contains { String(data: $0.corpo ?? Data(), encoding: .utf8)?.contains("context_uri") == true })
            XCTAssertEqual(corpoJson(t.pedidos.last { $0.metodo == "PUT" }!)["uris"] as? [String], ["u:d", "u:e"])
        }
    }

    func testPularNaFilaComMusicaRepetidaSaltaParaACopiaQueFoiTocada() {
        let t = TransporteFalso { r in
            if r.metodo == "GET" { return respostaJson(200, ["queue": ["X", "A", "B", "X"].map { ["name": $0, "artists": [["name": "Y"]], "uri": "u:\($0)"] }]) }
            return respostaJson(204)
        }
        let (c, _) = logada(t); c.esperaDoPulo = 0
        XCTAssertNil(c.pularFila(posicao: 4, uri: "u:X"))
        XCTAssertEqual(corpoJson(t.pedidos.last { $0.metodo == "PUT" }!)["uris"] as? [String], ["u:X"], "a cópia da posição 4, não a da 1")
    }

    func testPularNaFilaQueMudouNaoPulaNada() {
        let t = TransporteFalso { r in r.metodo == "GET" ? respostaJson(200, ["queue": [["name": "a", "uri": "u:a"]]]) : respostaJson(204) }
        let (c, _) = logada(t)
        XCTAssertEqual(c.pularFila(posicao: 2, uri: "u:z")?.texto, "A fila mudou. Abra a fila de novo.")
        XCTAssertTrue(t.pedidos.filter { $0.metodo == "POST" }.isEmpty)
    }

    func testPularNaFilaSemUriUsaAPosicaoDaTela() {
        let t = TransporteFalso { _ in respostaJson(204) }
        let (c, _) = logada(t)
        XCTAssertNil(c.pularFila(posicao: 2, uri: nil), "sem uri não há como saltar")
        XCTAssertEqual(t.pedidos.filter { $0.metodo == "POST" }.count, 2)
        XCTAssertNotNil(c.pularFila(posicao: 0, uri: nil))
    }

    func testRecentesTrazAsFaixasDoHistorico() throws {
        let t = TransporteFalso { _ in respostaJson(200, ["items": [["track": ["name": "Velha", "artists": [["name": "Zé"]], "uri": "u:v"]], ["played_at": "x"]]]) }
        let (c, _) = logada(t)
        XCTAssertEqual(try c.recentes().get().itens, [ItemDaFila(faixa: "Velha", artista: "Zé", uri: "u:v")])
        XCTAssertEqual(t.pedidos.last?.url, "https://api.spotify.com/v1/me/player/recently-played?limit=20")
    }

    func testFilaLimitaAQuantidadeDeProximas() throws {
        let muitas = (1...50).map { ["name": "F\($0)", "artists": [["name": "A"]]] }
        let resposta = respostaJson(200, ["queue": muitas])
        let t = TransporteFalso { _ in resposta }
        let (c, _) = logada(t)
        let f = try c.fila(limite: 5).get()
        XCTAssertNil(f.atual)
        XCTAssertEqual(f.proximas.map { $0.faixa }, ["F1", "F2", "F3", "F4", "F5"])
    }

    func testRepetirSoAMusicaMandaOEstadoDoSpotify() {
        let t = TransporteFalso { _ in respostaJson(204) }
        let (c, _) = logada(t)
        XCTAssertNil(c.repetir("faixa"))
        XCTAssertNil(c.repetir("nao"))
        XCTAssertNil(c.repetir("contexto"))
        XCTAssertNotNil(c.repetir("tudo"))
        XCTAssertEqual(t.pedidos.map { $0.url }, [
            "https://api.spotify.com/v1/me/player/repeat?state=track",
            "https://api.spotify.com/v1/me/player/repeat?state=off",
            "https://api.spotify.com/v1/me/player/repeat?state=context",
        ])
        XCTAssertTrue(t.pedidos.allSatisfy { $0.metodo == "PUT" })
    }

    func testVolumeDoAparelho() {
        let t = TransporteFalso { _ in respostaJson(204) }
        let (c, _) = logada(t)
        XCTAssertNil(c.volumeDoAparelho(150, aparelho: "d 1"))
        XCTAssertEqual(t.pedidos.last?.url, "https://api.spotify.com/v1/me/player/volume?volume_percent=100&device_id=d%201")
    }

    func testJogadorTraduzARepeticaoEOAparelho() throws {
        let t = TransporteFalso { _ in respostaJson(200, ["repeat_state": "track", "device": ["id": "d1", "name": "Caixa", "volume_percent": 42], "item": ["uri": "spotify:track:abc"]]) }
        let (c, _) = logada(t)
        let j = try c.jogador().get()
        XCTAssertEqual(j, JogadorSpotify(repetir: "faixa", aparelho: "Caixa", aparelhoId: "d1", volumeAparelho: 42, uri: "spotify:track:abc"))
    }

    func testNenhumAparelhoAtivoDevolveJogadorVazio() throws {
        let (c, _) = logada(TransporteFalso { _ in respostaJson(204) })
        XCTAssertEqual(try c.jogador().get(), JogadorSpotify())
    }

    func testErrosDaApiViramTextoEmPortugues() {
        func erro(_ status: Int, _ corpo: [String: Any]?) -> ErroSpotify {
            let resposta = respostaJson(status, corpo)
            let (c, _) = logada(TransporteFalso { _ in resposta })
            guard case .failure(let e) = c.dispositivos() else { XCTFail("devia falhar"); return .recusou }
            return e
        }
        XCTAssertEqual(erro(403, ["error": ["status": 403, "message": "Player command failed: Premium required", "reason": "PREMIUM_REQUIRED"]]), .soPremium)
        XCTAssertEqual(erro(404, ["error": ["status": 404, "message": "Player command failed: No active device found", "reason": "NO_ACTIVE_DEVICE"]]), .semAparelho)
        XCTAssertEqual(erro(403, ["error": ["status": 403, "message": "Insufficient client scope"]]), .faltaPermissao)
        XCTAssertEqual(erro(429, nil), .esperar)
        XCTAssertEqual(erro(503, nil), .semRede)
        XCTAssertEqual(erro(400, nil), .recusou)
    }

    func testSemLoginNenhumaChamadaSai() {
        let t = TransporteFalso { _ in respostaJson(200, ["devices": []]) }
        let (c, _) = conta(t)
        guard case .failure(let e) = c.dispositivos() else { return XCTFail() }
        XCTAssertEqual(e, .naoConectado)
        XCTAssertNotNil(c.transferir(para: "x"))
        XCTAssertNotNil(c.repetir("faixa"))
        XCTAssertEqual(t.pedidos.count, 0)
    }

    // MARK: Complemento do estado

    func testComplementoSemLoginMarcaDesconectadoENaoChamaNada() {
        let t = TransporteFalso { _ in nil }
        let (c, _) = conta(t)
        let comp = ComplementoSpotify(conta: c, disparar: { $0() })
        let e = comp.aplicar(EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: []), uri: "spotify:track:x")
        XCTAssertEqual(e.conectado, false)
        XCTAssertNil(e.curtida); XCTAssertNil(e.repetirFaixa); XCTAssertNil(e.aparelho)
        XCTAssertEqual(t.pedidos.count, 0)
    }

    func testComplementoComLoginTrazCurtidaRepeticaoEAparelhoDepoisDaLeitura() {
        let t = TransporteFalso { r in
            r.url.hasSuffix("/me/player") ? respostaJson(200, ["repeat_state": "track", "device": ["name": "Caixa"]]) : respostaJson(200, [true])
        }
        let (c, _) = logada(t)
        let comp = ComplementoSpotify(conta: c, disparar: { $0() })
        let base = EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: [])
        let agora = Date()
        // A primeira chamada devolve o que há (nada ainda) e dispara a leitura. A segunda já vê o resultado.
        XCTAssertEqual(comp.aplicar(base, uri: "spotify:track:x", agora: agora).conectado, true)
        let e = comp.aplicar(base, uri: "spotify:track:x", agora: agora.addingTimeInterval(1))
        XCTAssertEqual(e.curtida, true)
        XCTAssertEqual(e.repetirFaixa, true)
        XCTAssertEqual(e.aparelho, "Caixa")
    }

    func testComplementoNaoRepeteALeituraDentroDaValidadeENemEmFalha() {
        let t = TransporteFalso { _ in nil }
        let (c, _) = logada(t)
        let comp = ComplementoSpotify(conta: c, validade: 5, espera: 30, disparar: { $0() })
        let base = EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: [])
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        _ = comp.aplicar(base, uri: nil, agora: t0)
        let depoisDaPrimeira = t.pedidos.count
        XCTAssertGreaterThan(depoisDaPrimeira, 0)
        _ = comp.aplicar(base, uri: nil, agora: t0.addingTimeInterval(10))
        XCTAssertEqual(t.pedidos.count, depoisDaPrimeira, "sem internet, espera 30 s antes de tentar de novo")
        _ = comp.aplicar(base, uri: nil, agora: t0.addingTimeInterval(31))
        XCTAssertGreaterThan(t.pedidos.count, depoisDaPrimeira)
    }

    func testComplementoMostraNaHoraACurtidaEARepeticaoQueAPessoaAcabouDeMudar() {
        let (c, _) = logada(TransporteFalso { _ in nil })
        let comp = ComplementoSpotify(conta: c, disparar: { _ in })
        comp.marcarCurtida("spotify:track:x", true)
        comp.marcarRepetir("faixa")
        let e = comp.aplicar(EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: []), uri: "spotify:track:x")
        XCTAssertEqual(e.curtida, true)
        XCTAssertEqual(e.repetirFaixa, true)
        // Outra faixa: a curtida da anterior não vale.
        XCTAssertNil(comp.aplicar(EstadoSpotify(tocando: true, faixa: "C", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: []), uri: "spotify:track:y").curtida)
    }
}
