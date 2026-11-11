import XCTest
@testable import Deck

private final class LinhasDeLog: @unchecked Sendable {
    private let trava = NSLock()
    private var _todas: [String] = []
    func guardar(_ l: String) { trava.lock(); _todas.append(l); trava.unlock() }
    var todas: [String] { trava.lock(); defer { trava.unlock() }; return _todas }
}

/// A API do Spotify de mentira (o núcleo compila dentro do app, então os falsos do pacote não chegam aqui).
private final class TransporteDeMentira: TransporteWeb, @unchecked Sendable {
    private let trava = NSLock()
    private var _pedidos: [RequisicaoWeb] = []
    let resposta: @Sendable (RequisicaoWeb) -> RespostaWeb?
    init(_ resposta: @escaping @Sendable (RequisicaoWeb) -> RespostaWeb?) { self.resposta = resposta }
    var pedidos: [RequisicaoWeb] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func enviar(_ r: RequisicaoWeb) -> RespostaWeb? {
        trava.lock(); _pedidos.append(r); trava.unlock()
        return resposta(r)
    }
}

private func respostaDeMentira(_ status: Int, _ corpo: String) -> RespostaWeb {
    RespostaWeb(status: status, corpo: Data(corpo.utf8))
}

private func tokenDeMentira() -> RespostaWeb {
    let obj: [String: Any] = ["access_token": "ACESSO", "token_type": "Bearer", "expires_in": 3600, "refresh_token": "RENOVA"]
    return RespostaWeb(status: 200, corpo: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
}

/// O login do Spotify de ponta a ponta no app do Mac: porta local de verdade, navegador simulado e a API
/// do Spotify de mentira. Nada toca no Chaveiro nem na internet.
@MainActor
final class SpotifyLoginTestes: XCTestCase {
    private func montar(embutida: String? = nil, _ resposta: @escaping @Sendable (RequisicaoWeb) -> RespostaWeb?) -> (ModeloSpotify, TransporteDeMentira, ArmazemSpotifyMemoria) {
        let t = TransporteDeMentira(resposta)
        let a = ArmazemSpotifyMemoria()
        let m = ModeloSpotify(conta: ContaSpotify(armazem: a, transporte: t, embutida: embutida))
        m.portaDoRetorno = 0
        return (m, t, a)
    }

    private static let chave = "0123456789abcdef0123456789abcdef"

    /// O "navegador": pega a URL de login, lê o redirect_uri e o state e chama o retorno local como o Spotify faria.
    private func navegador(codigo: String? = "CODIGO", estadoErrado: Bool = false, negar: Bool = false) -> @MainActor (URL) -> Void {
        { url in
            let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let base = q["redirect_uri"] ?? ""
            let estado = estadoErrado ? "outro" : (q["state"] ?? "")
            let alvo = negar ? "\(base)?error=access_denied&state=\(estado)" : "\(base)?code=\(codigo ?? "")&state=\(estado)"
            Task.detached { _ = try? await URLSession.shared.data(from: URL(string: alvo)!) }
        }
    }

    func testSituacoesDaSecao() {
        XCTAssertEqual(SpotifyLogica.situacao(chaveValida: false, conectado: false, conectando: false), .semChave)
        XCTAssertEqual(SpotifyLogica.situacao(chaveValida: true, conectado: false, conectando: false), .pronto)
        XCTAssertEqual(SpotifyLogica.situacao(chaveValida: true, conectado: true, conectando: false), .conectado)
        XCTAssertEqual(SpotifyLogica.situacao(chaveValida: true, conectado: false, conectando: true), .conectando)
    }

    func testTextosDaSecaoNaoTemTravessaoNemPontoEVirgula() {
        let todos = [SpotifyLogica.passos, SpotifyLogica.apoioDoCampo, SpotifyLogica.apoioDoEndereco, SpotifyLogica.avancado, SpotifyLogica.apoioDoAvancado]
            + [SituacaoSpotify.semChave, .pronto, .conectando, .conectado].map { SpotifyLogica.apoioDoLogin($0, erro: nil) }
        for t in todos {
            XCTAssertFalse(t.contains("—") || t.contains("–") || t.contains(";"), t)
        }
        XCTAssertTrue(SpotifyLogica.passos.contains("Web API"))
        XCTAssertEqual(SpotifyLogica.enderecoDoRetorno, "http://127.0.0.1:4778/retorno")
    }

    func testChaveInvalidaNaoAbreNavegador() async {
        let (m, t, _) = montar { _ in nil }
        var abriu = false
        m.abrirNavegador = { _ in abriu = true }
        m.chave = "curta"
        await m.conectar()
        XCTAssertFalse(abriu)
        XCTAssertFalse(m.conectado)
        XCTAssertNotNil(m.erro)
        XCTAssertEqual(t.pedidos.count, 0)
    }

    func testLoginCompletoGuardaOsTokensEMostraConectado() async {
        let (m, t, a) = montar { _ in tokenDeMentira() }
        var avisos: [String] = []
        m.avisar = { texto, _ in avisos.append(texto) }
        m.abrirNavegador = navegador()
        m.chave = Self.chave
        await m.conectar()
        XCTAssertTrue(m.conectado)
        XCTAssertNil(m.erro)
        XCTAssertEqual(m.situacao, .conectado)
        XCTAssertEqual(a.ler().renovacao, "RENOVA")
        XCTAssertEqual(a.ler().clientId, Self.chave)
        XCTAssertEqual(avisos, ["Spotify conectado"])
        XCTAssertEqual(t.pedidos.filter { $0.url.hasSuffix("/api/token") }.count, 1)
        XCTAssertTrue(String(decoding: t.pedidos[0].corpo ?? Data(), as: UTF8.self).contains("code=CODIGO"))
    }

    private static let chaveDoDeck = "fedcba9876543210fedcba9876543210"

    /// Com a chave do Deck, o login é só "Conectar": nada de colar, e o Spotify recebe a chave embutida.
    func testComChaveEmbutidaConectaSemColarNada() async {
        let (m, t, a) = montar(embutida: Self.chaveDoDeck) { _ in tokenDeMentira() }
        XCTAssertTrue(m.temChaveEmbutida)
        XCTAssertEqual(m.situacao, .pronto)
        var chaveNaUrl: String?
        let nav = navegador()
        m.abrirNavegador = { url in
            chaveNaUrl = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "client_id" }?.value
            nav(url)
        }
        await m.conectar()
        XCTAssertTrue(m.conectado)
        XCTAssertNil(m.erro)
        XCTAssertEqual(chaveNaUrl, Self.chaveDoDeck)
        XCTAssertNil(a.ler().clientId)
        XCTAssertFalse(m.usaChavePropria)
        XCTAssertTrue(String(decoding: t.pedidos[0].corpo ?? Data(), as: UTF8.self).contains("client_id=\(Self.chaveDoDeck)"))
    }

    func testComChaveEmbutidaUmaChaveCurtaNoAvancadoNaoConecta() async {
        let (m, t, _) = montar(embutida: Self.chaveDoDeck) { _ in nil }
        var abriu = false
        m.abrirNavegador = { _ in abriu = true }
        m.chave = "curta"
        XCTAssertEqual(m.situacao, .semChave)
        await m.conectar()
        XCTAssertFalse(abriu)
        XCTAssertNotNil(m.erro)
        XCTAssertEqual(t.pedidos.count, 0)
    }

    /// Conta fora da lista do app do Deck: a tela mostra a mensagem curta (sem erro cru do Spotify) e já abre o Avançado.
    func testContaForaDaListaAbreOAvancadoComAMensagemCurta() async {
        let (m, _, _) = montar(embutida: Self.chaveDoDeck) { _ in respostaDeMentira(403, "{\"error\":{\"status\":403,\"message\":\"User not registered in the Developer Dashboard\"}}") }
        XCTAssertFalse(m.avancadoAberto)
        m.abrirNavegador = navegador()
        await m.conectar()
        XCTAssertFalse(m.conectado)
        XCTAssertEqual(m.erro, ErroSpotify.semCadastro.texto)
        XCTAssertTrue(m.avancadoAberto)
        XCTAssertFalse((m.erro ?? "").contains("Dashboard"))
    }

    func testChaveCurtaNoAvancadoNaoAbreSozinhoOAvancado() async {
        let (m, _, _) = montar(embutida: Self.chaveDoDeck) { _ in nil }
        m.chave = "curta"
        await m.conectar()
        XCTAssertFalse(m.avancadoAberto)
    }

    func testSemChaveEmbutidaATelaFicaComoAntes() {
        let (m, _, _) = montar { _ in nil }
        XCTAssertFalse(m.temChaveEmbutida)
        XCTAssertEqual(m.situacao, .semChave)
    }

    func testRetornoDeOutroLoginNaoConecta() async {
        let (m, t, _) = montar { _ in tokenDeMentira() }
        m.esperaMaxima = 1
        m.abrirNavegador = navegador(estadoErrado: true)
        m.chave = Self.chave
        await m.conectar()
        XCTAssertFalse(m.conectado)
        XCTAssertNotNil(m.erro)
        XCTAssertEqual(t.pedidos.count, 0)
    }

    /// Um pedido de fora (state errado) não derruba o login: a espera segue e o retorno certo conecta.
    func testPedidoDeForaNaoDerrubaOLoginEmAndamento() async {
        let (m, t, _) = montar { _ in tokenDeMentira() }
        let certo = navegador()
        m.abrirNavegador = { url in
            let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let base = q["redirect_uri"] ?? ""
            Task.detached {
                _ = try? await URLSession.shared.data(from: URL(string: "\(base)?code=x&state=y")!)
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { certo(url) }
            }
        }
        m.chave = Self.chave
        await m.conectar()
        XCTAssertTrue(m.conectado)
        XCTAssertNil(m.erro)
        XCTAssertEqual(t.pedidos.filter { $0.url.hasSuffix("/api/token") }.count, 1)
    }

    func testPessoaNegandoNoSpotifyNaoConecta() async {
        let (m, _, _) = montar { _ in tokenDeMentira() }
        m.abrirNavegador = navegador(negar: true)
        m.chave = Self.chave
        await m.conectar()
        XCTAssertFalse(m.conectado)
        XCTAssertEqual(m.erro, "O login do Spotify foi cancelado.")
    }

    func testDemoraDemaisViraAviso() async {
        let (m, _, _) = montar { _ in tokenDeMentira() }
        m.esperaMaxima = 0.3
        m.abrirNavegador = { _ in }
        m.chave = Self.chave
        await m.conectar()
        XCTAssertFalse(m.conectando)
        XCTAssertTrue(m.erro?.contains("demorou") ?? false)
    }

    func testCancelarLiberaAEspera() async {
        let (m, _, _) = montar { _ in tokenDeMentira() }
        m.abrirNavegador = { [weak m] _ in Task { @MainActor in m?.cancelar() } }
        m.chave = Self.chave
        await m.conectar()
        XCTAssertFalse(m.conectando)
        XCTAssertEqual(m.erro, "Login do Spotify cancelado.")
    }

    func testDesconectarGuardaAChaveELimpaOLogin() async {
        let (m, _, a) = montar { _ in tokenDeMentira() }
        m.abrirNavegador = navegador()
        m.chave = Self.chave
        await m.conectar()
        m.desconectar()
        XCTAssertFalse(m.conectado)
        XCTAssertEqual(m.situacao, .pronto)
        XCTAssertEqual(a.ler().clientId, Self.chave)
        XCTAssertNil(a.ler().renovacao)
    }

    func testColarAChaveInteiraJaGuardaSemApertarOBotao() {
        let (m, _, a) = montar { _ in nil }
        m.chave = "curta"; m.guardarChave()
        XCTAssertNil(a.ler().clientId)
        m.chave = "  \(Self.chave)  "; m.guardarChave()
        XCTAssertEqual(a.ler().clientId, Self.chave)
    }

    /// A chave do Deck que ficou guardada no Chaveiro (colada em versão antiga) não pode aparecer no campo como se fosse colada.
    func testChaveDoDeckGuardadaNoChaveiroNaoApareceNoCampo() {
        let a = ArmazemSpotifyMemoria(DadosSpotify(clientId: Self.chaveDoDeck))
        let m = ModeloSpotify(conta: ContaSpotify(armazem: a, transporte: TransporteDeMentira { _ in nil }, embutida: Self.chaveDoDeck))
        XCTAssertEqual(m.chave, "")
        XCTAssertFalse(m.usaChavePropria)
        XCTAssertFalse(m.avancadoAberto)
        XCTAssertEqual(m.situacao, .pronto)
    }

    func testColarAChaveDoDeckNaoViraChavePropria() {
        let (m, _, a) = montar(embutida: Self.chaveDoDeck) { _ in nil }
        m.chave = Self.chaveDoDeck; m.guardarChave()
        XCTAssertNil(a.ler().clientId)
        XCTAssertFalse(m.usaChavePropria)
        XCTAssertNil(m.conta.definirClientId(Self.chaveDoDeck))
        XCTAssertNil(a.ler().clientId)
        XCTAssertNil(a.ler().clientId)
        // chave de outra pessoa continua valendo como própria
        XCTAssertNil(m.conta.definirClientId(Self.chave))
        XCTAssertEqual(m.conta.chavePropria, Self.chave)
    }

    /// Conectou: a tela mostra de quem é a conta, e Desconectar esquece o nome.
    func testConectadoMostraOQuemEntrou() async {
        let (m, _, a) = montar { r in
            r.url.hasSuffix("/me") ? respostaDeMentira(200, "{\"display_name\":\"Fulana\",\"id\":\"fulana123\"}") : tokenDeMentira()
        }
        m.abrirNavegador = navegador()
        m.chave = Self.chave
        await m.conectar()
        XCTAssertTrue(m.conectado)
        XCTAssertEqual(m.nome, "Fulana")
        XCTAssertEqual(a.ler().nome, "Fulana")
        m.desconectar()
        XCTAssertNil(m.nome)
        XCTAssertNil(a.ler().nome)
    }

    func testSemNomeNoSpotifyUsaOIdEConectadoSegueValendo() async {
        let (m, _, _) = montar { r in r.url.hasSuffix("/me") ? respostaDeMentira(200, "{\"id\":\"fulana123\"}") : tokenDeMentira() }
        m.abrirNavegador = navegador()
        m.chave = Self.chave
        await m.conectar()
        XCTAssertEqual(m.nome, "fulana123")
        let (m2, _, _) = montar { r in r.url.hasSuffix("/me") ? respostaDeMentira(500, "") : tokenDeMentira() }
        m2.abrirNavegador = navegador()
        m2.chave = Self.chave
        await m2.conectar()
        XCTAssertTrue(m2.conectado)
        XCTAssertNil(m2.nome)
    }

    /// A tela sempre sai do "Esperando": aqui o navegador nunca volta, e o log conta o que houve.
    func testTempoEsgotadoSaiDoEsperandoEDiscaNoLog() async {
        let (m, _, _) = montar { _ in tokenDeMentira() }
        let linhas = LinhasDeLog()
        m.registrar = { linhas.guardar($0) }
        m.esperaMaxima = 0.3
        m.abrirNavegador = { _ in }
        m.chave = Self.chave
        await m.conectar()
        XCTAssertFalse(m.conectando)
        XCTAssertEqual(m.situacao, .pronto)
        XCTAssertEqual(m.erro, ModeloSpotify.textoDeTempoEsgotado)
        let log = linhas.todas
        XCTAssertTrue(log.contains { $0.contains("navegador aberto") })
        XCTAssertTrue(log.contains { $0.contains("tempo esgotado") })
        XCTAssertFalse(log.contains { $0.contains("CODIGO") || $0.contains(Self.chave) })
    }

    func testLoginCompletoRegistraOsPassosSemSegredo() async {
        let (m, _, _) = montar { _ in tokenDeMentira() }
        let linhas = LinhasDeLog()
        m.registrar = { linhas.guardar($0) }
        m.abrirNavegador = navegador()
        m.chave = Self.chave
        await m.conectar()
        let log = linhas.todas.joined(separator: "\n")
        XCTAssertTrue(log.contains("retorno recebido"))
        XCTAssertTrue(log.contains("spotify: conectado"))
        XCTAssertFalse(log.contains("CODIGO") || log.contains("RENOVA") || log.contains("ACESSO"))
    }

    func testEnquantoConfirmaATelaDiz() {
        XCTAssertEqual(SpotifyLogica.apoioDoLogin(.conectando, erro: nil, confirmando: true), "O navegador voltou. Confirmando com o Spotify...")
        XCTAssertEqual(SpotifyLogica.apoioDoLogin(.conectando, erro: nil), "Esperando você permitir no navegador...")
    }

    func testPortaOcupadaAvisaOQueFazer() async throws {
        let ocupando = RetornoLocal(porta: 0)
        let porta = try ocupando.iniciar { _ in }
        defer { ocupando.parar() }
        let (m, _, _) = montar { _ in nil }
        m.portaDoRetorno = porta
        m.chave = Self.chave
        await m.conectar()
        XCTAssertTrue(m.erro?.contains("porta") ?? false)
        XCTAssertFalse(m.conectando)
    }
}
