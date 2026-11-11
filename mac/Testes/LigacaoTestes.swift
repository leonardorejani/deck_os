import XCTest
@testable import Nucleo

final class LigacaoTestes: XCTestCase {
    let codigo = "abcdefghjkmnpqrstuvw"

    // MARK: Spotify

    func testSpotifyMandaOComandoCertoDeCadaAcao() {
        let f = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "ok\n"))])
        let s = SpotifyReal(executor: f)
        for (acao, trecho) in [("tocar", "to play"), ("pausar", "to pause"), ("anterior", "previous track"), ("proxima", "next track")] {
            XCTAssertNil(s.acao(acao), acao)
            XCTAssertTrue(f.comandos.last!.contains(trecho), "\(acao): \(f.comandos.last!)")
            XCTAssertTrue(f.comandos.last!.hasPrefix("osascript "))
        }
        XCTAssertNil(s.posicao(42.55))
        XCTAssertTrue(f.comandos.last!.contains("set player position to 42.5") || f.comandos.last!.contains("set player position to 42.6"))
    }

    func testSpotifyRepetirEAleatorioLigamDesligamEAlternam() {
        let f = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "ok\n"))])
        let s = SpotifyReal(executor: f)
        XCTAssertNil(s.definir("repetir", ligado: true))
        XCTAssertTrue(f.comandos.last!.contains("set repeating to true"), f.comandos.last!)
        XCTAssertNil(s.definir("repetir", ligado: false))
        XCTAssertTrue(f.comandos.last!.contains("set repeating to false"), f.comandos.last!)
        XCTAssertNil(s.definir("aleatorio", ligado: true))
        XCTAssertTrue(f.comandos.last!.contains("set shuffling to true"), f.comandos.last!)
        XCTAssertNil(s.definir("aleatorio", ligado: nil))
        XCTAssertTrue(f.comandos.last!.contains("set shuffling to not shuffling"), f.comandos.last!)
        let antes = f.comandos.count
        XCTAssertNotNil(s.definir("apagar tudo", ligado: true))
        XCTAssertEqual(f.comandos.count, antes, "nome desconhecido não roda nada")
    }

    func testSpotifyRepetirComOSpotifyFechadoDaErroEmPortugues() {
        let s = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "fechado\n"))]))
        XCTAssertEqual(s.definir("repetir", ligado: true), SpotifyReal.erroFechado)
    }

    func testSpotifyFechadoDaErroEmPortugues() {
        let s = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "fechado\n"))]))
        XCTAssertEqual(s.acao("tocar"), SpotifyReal.erroFechado)
        XCTAssertEqual(s.posicao(10), SpotifyReal.erroFechado)
    }

    func testSpotifySemPermissaoOuComFalhaDaErroEmPortugues() {
        let s = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 1, saida: "execution error: Not authorized (-1743)"))]))
        XCTAssertEqual(s.acao("proxima"), SpotifyReal.erroFalha)
    }

    func testSpotifyRecusaAcaoDesconhecidaEPosicaoInvalidaSemRodarNada() {
        let f = ExecutorFalso([])
        let s = SpotifyReal(executor: f)
        XCTAssertNotNil(s.acao("apagar tudo"))
        XCTAssertNotNil(s.posicao(-1))
        XCTAssertNotNil(s.posicao(.nan))
        XCTAssertEqual(f.comandos, [])
    }

    // MARK: Teclas

    func testTeclaDoTipoTeclaDoContratoEhExecutada() {
        let enviadas = Registro()
        let acoes = ExecutorAcoes(shell: ExecutorFalso([]), temAcessibilidade: { true }, enviarTecla: { _ in enviadas.anotar("enviou") })
        let t = Tecla(id: "a", nome: "A", tipo: "tecla", valor: "ctrl+opt+cmd+k", estado: nil, icone: nil)
        XCTAssertNil(acoes.executar(t))
        XCTAssertEqual(enviadas.todos, ["enviou"])
    }

    // MARK: Config em disco

    private func armazem() throws -> (ArmazemEmDisco, URL) {
        let url = try pastaTemporaria().appendingPathComponent("config.json")
        return (try ArmazemEmDisco(ArmazemConfig(url: url, nomeMac: "Mac de teste")), url)
    }

    func testCriaAConfigPadraoSeNaoExisteEPreservaSeExiste() throws {
        let (a, url) = try armazem()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let criada = a.ler()
        XCTAssertEqual(criada.nomeMac, "Mac de teste")
        let outro = try ArmazemEmDisco(ArmazemConfig(url: url, nomeMac: "Outro nome"))
        XCTAssertEqual(outro.ler().codigoAcesso, criada.codigoAcesso, "não sobrescreve o que já existe")
    }

    func testAplicarGravaEmDiscoERecusaInvalida() throws {
        let (a, url) = try armazem()
        var nova = a.ler()
        nova.comp = "b"
        XCTAssertNil(a.aplicar(nova))
        XCTAssertEqual(try ArmazemEmDisco(ArmazemConfig(url: url)).ler().comp, "b")
        var ruim = nova
        ruim.comp = "z"
        XCTAssertNotNil(a.aplicar(ruim))
        XCTAssertEqual(a.ler().comp, "b")
    }

    func testArquivoIlegivelMantemAUltimaConfigBoa() throws {
        let (a, url) = try armazem()
        let boa = a.ler()
        try Data("{ lixo".utf8).write(to: url)
        XCTAssertEqual(a.ler(), boa)
    }

    // MARK: Roteador montado de ponta a ponta

    func testRoteadorComPecasReaisFalamComOExecutorFalso() throws {
        let (a, _) = try armazem()
        var c = a.ler()
        c.perfis = [Perfil(id: "p", nome: "P", teclas: [Tecla(id: "t", nome: "T", tipo: "comando", valor: "touch /tmp/x", estado: nil, icone: nil)])]
        c.perfilAtivo = "p"
        XCTAssertNil(a.aplicar(c))
        let f = ExecutorFalso([("perl", SaidaShell(status: 0, saida: "")), ("osascript", SaidaShell(status: 0, saida: "ok"))])
        let fontes = Fontes(
            sessoes: { Leitura(valor: [Sessao(id: "s", nome: "n", projeto: "p", pergunta: "?", desde: "2026-11-10T10:00:00Z")], aviso: nil) },
            uso: { _, _ in Leitura(valor: [], aviso: nil) }, whatsapp: { Leitura(valor: nil, aviso: nil) }, seloWhatsApp: { nil },
            spotify: { _ in Leitura(valor: nil, aviso: nil) }, capa: { Data([0x89, 0x50, 0x4E, 0x47, 1]) },
            agenda: { _ in Leitura(valor: ResumoAgenda(permissao: true, proximo: nil), aviso: nil) }, acesas: { _ in [] })
        let agenda = FonteAgenda(ler: { _ in Leitura(valor: nil, aviso: nil) },
                                 eventos: { de, dias in [Evento(titulo: "\(Datas.iso(de, fuso: utc).prefix(4)) \(dias)", inicio: "x", diaTodo: false, calendario: "c", cor: "#000000", local: nil)] })
        let r = Ligacao.roteador(armazem: a, pareamento: Pareamento(), pagina: ArquivosPagina(raiz: try pastaTemporaria()),
                                 executor: f, fontes: fontes, agenda: agenda)
        func pedir(_ m: String, _ alvo: String, _ corpo: String = "") -> RespostaRota {
            let (caminho, query) = Http.separarAlvo(alvo)
            return r.responder(HttpRequisicao(metodo: m, caminho: caminho, query: query,
                                              cabecalhos: ["x-deck-codigo": c.codigoAcesso], corpo: Data(corpo.utf8)))
        }
        XCTAssertEqual(pedir("GET", "/api/estado").status, 200)
        XCTAssertEqual(pedir("GET", "/api/sessoes").status, 200)
        XCTAssertEqual(pedir("GET", "/api/capa").extras["Cache-Control"], "no-store")
        XCTAssertEqual(pedir("GET", "/api/capa").tipo, "image/png")
        XCTAssertEqual(pedir("GET", "/api/agenda?de=2026-11-10&dias=3").status, 200)
        XCTAssertTrue(pedir("GET", "/api/agenda?de=2026-11-10&dias=3").texto.contains("2026 3"))
        XCTAssertEqual(pedir("POST", "/api/botao/t").status, 200)
        XCTAssertTrue(f.comandos.last!.contains("touch /tmp/x"))
        XCTAssertEqual(pedir("POST", "/api/botao/nao-existe").status, 404)
        XCTAssertEqual(pedir("POST", "/api/spotify/proxima").status, 200)
        // PUT: a config pública sem codigoAcesso e porta é aceita, e as duas ficam como estavam.
        let publica = pedir("GET", "/api/config")
        XCTAssertFalse(publica.texto.contains("codigoAcesso"))
        var obj = try XCTUnwrap(publica.json as? [String: Any])
        obj.removeValue(forKey: "porta")
        obj["comp"] = "b"
        let put = pedir("PUT", "/api/config", String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self))
        XCTAssertEqual(put.status, 200, put.texto)
        XCTAssertEqual(a.ler().comp, "b")
        XCTAssertEqual(a.ler().codigoAcesso, c.codigoAcesso)
        XCTAssertEqual(a.ler().porta, c.porta)
        // Corpo parcial: recusado, nada muda.
        XCTAssertEqual(pedir("PUT", "/api/config", #"{"comp":"a"}"#).status, 400)
        XCTAssertEqual(a.ler().comp, "b")
    }

    // MARK: Spotify: volume e API

    func testVolumeDoSpotifyEPeloAppleScriptEComNumeroFormatado() {
        let f = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "ok\n"))])
        let s = SpotifyReal(executor: f)
        XCTAssertNil(s.volume(.spotify, 37))
        XCTAssertNil(s.volume(.spotify, 500))
        XCTAssertTrue(f.comandos[0].contains("set sound volume to 37"))
        XCTAssertTrue(f.comandos[1].contains("set sound volume to 100"), "limita a 100")
        XCTAssertTrue(f.comandos[0].contains(#"application "Spotify" is running"#))
    }

    func testVolumeDoSpotifyComAppFechadoDizOMotivo() {
        let s = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "fechado\n"))]))
        XCTAssertEqual(s.volume(.spotify, 10)?.texto, SpotifyReal.erroFechado)
    }

    func testVolumeDoMacNaoMexeNoSpotify() {
        let f = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: ""))])
        let s = SpotifyReal(executor: f)
        XCTAssertNil(s.volume(.mac, -5))
        XCTAssertEqual(f.comandos.count, 1)
        XCTAssertTrue(f.comandos[0].contains("set volume output volume 0"))
        XCTAssertFalse(f.comandos[0].contains("Spotify"))
        let ruim = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 1, saida: "erro"))]))
        XCTAssertNotNil(ruim.volume(.mac, 10))
    }

    func testVolumeDoAparelhoPedeLogin() {
        XCTAssertEqual(SpotifyReal(executor: ExecutorFalso([])).volume(.aparelho, 10), .naoConectado)
    }

    func testSemContaOQueDependeDaApiDizQueNaoEstaConectado() {
        let s = SpotifyReal(executor: ExecutorFalso([]))
        XCTAssertEqual(s.transferir(para: "x"), .naoConectado)
        XCTAssertEqual(s.curtir(true), .naoConectado)
        XCTAssertEqual(s.repetirModo("faixa"), .naoConectado)
        if case .failure(let e) = s.dispositivos() { XCTAssertTrue(e.semLogin) } else { XCTFail() }
        if case .failure(let e) = s.fila() { XCTAssertTrue(e.semLogin) } else { XCTFail() }
    }

    func testCurtirLeAFaixaNaHoraEMarcaNoEstado() {
        let f = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "spotify:track:abc123\n"))])
        let t = TransporteFalso { _ in respostaJson(200) }
        let conta = ContaSpotify(armazem: ArmazemSpotifyMemoria(DadosSpotify(clientId: chaveDeTeste, acesso: "A", renovacao: "R",
                                                                            expiraEm: Date().timeIntervalSince1970 + 3000)), transporte: t)
        let comp = ComplementoSpotify(conta: conta, disparar: { _ in })
        let s = SpotifyReal(executor: f, conta: conta, complemento: comp)
        XCTAssertNil(s.curtir(true))
        XCTAssertEqual(t.pedidos.last?.url, "https://api.spotify.com/v1/me/library?uris=spotify%3Atrack%3Aabc123")
        XCTAssertEqual(comp.aplicar(EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 0, duracao: 1, capaId: nil, cores: []), uri: "spotify:track:abc123").curtida, true)
    }

    func testCurtirSemMusicaOuComSpotifyFechadoNaoChamaAApi() {
        let t = TransporteFalso { _ in respostaJson(200) }
        let conta = ContaSpotify(armazem: ArmazemSpotifyMemoria(DadosSpotify(clientId: chaveDeTeste, acesso: "A", renovacao: "R",
                                                                            expiraEm: Date().timeIntervalSince1970 + 3000)), transporte: t)
        for saida in ["fechado", "parado"] {
            let s = SpotifyReal(executor: ExecutorFalso([("osascript", SaidaShell(status: 0, saida: saida))]), conta: conta)
            XCTAssertNotNil(s.curtir(true), saida)
        }
        XCTAssertEqual(t.pedidos.count, 0)
    }
}
