import XCTest
@testable import Nucleo

final class RotasTestes: XCTestCase {
    // MARK: Autenticação

    func testSemCodigoDa401ComErro() throws {
        let c = try Cenario()
        for caminho in ["/api/estado", "/api/config", "/api/whatsapp", "/api/inexistente"] {
            let r = c.pedir("GET", caminho, codigo: nil)
            XCTAssertEqual(r.status, 401, caminho)
            XCTAssertNotNil(r.erroTexto)
        }
        XCTAssertEqual(c.pedir("POST", "/api/botao/acordado", codigo: nil).status, 401)
        XCTAssertTrue(c.registro.todos.isEmpty, "sem código nada pode ser executado")
    }

    func testCodigoErradoOuVazioDa401() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: "errado").status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: "").status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: Cenario.codigo + "x").status, 401)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: String(Cenario.codigo.dropLast())).status, 401)
    }

    func testCodigoPeloCabecalhoOuPelaQuery() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/estado").status, 200)
        XCTAssertEqual(c.pedir("GET", "/api/estado", viaQuery: true).status, 200)
    }

    func testConfigSemCodigoNaConfigDoMacNaoLiberaNada() throws {
        let c = try Cenario()
        var vazia = configDeTeste(codigo: "")
        vazia.nomeMac = "x"
        _ = c.armazem.aplicar(vazia)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: "").status, 401)
    }

    func testComparacaoEmTempoConstante() {
        XCTAssertTrue(Autenticacao.igual("abc", "abc"))
        XCTAssertFalse(Autenticacao.igual("abc", "abd"))
        XCTAssertFalse(Autenticacao.igual("abc", "abcd"))
        XCTAssertFalse(Autenticacao.igual("", "a"))
        XCTAssertTrue(Autenticacao.igual("", ""))
    }

    // MARK: Rotas de leitura

    func testEstadoEListas() throws {
        let c = try Cenario()
        let estado = c.pedir("GET", "/api/estado")
        XCTAssertEqual(estado.status, 200)
        XCTAssertEqual((estado.json as? [String: Any])?["nomeMac"] as? String, "Mac")
        XCTAssertEqual((c.pedir("GET", "/api/whatsapp").json as? [[String: Any]])?.first?["nome"] as? String, "Louvor")
        XCTAssertEqual((c.pedir("GET", "/api/sessoes").json as? [[String: Any]])?.first?["id"] as? String, "s1")
    }

    // MARK: WhatsApp por QR: foto, mídia e Responder no Mac (12/11/2026)

    func testFotoDePerfilVemEmBase64EOutroNomeDa404() throws {
        let c = try Cenario()
        let ok = c.pedir("GET", "/api/whatsapp/foto/0123456789abcdef.jpg")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual((ok.json as? [String: Any])?["tipo"] as? String, "image/jpeg")
        XCTAssertEqual((ok.json as? [String: Any])?["dados"] as? String, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(c.pedir("GET", "/api/whatsapp/foto/nao-existe.jpg").status, 404)
        XCTAssertEqual(c.pedir("POST", "/api/whatsapp/foto/0123456789abcdef.jpg").status, 405)
        XCTAssertEqual(c.pedir("GET", "/api/whatsapp/foto/0123456789abcdef.jpg", codigo: nil).status, 401)
    }

    func testMidiaDoWhatsAppPedeAConversaEAMensagem() throws {
        let c = try Cenario()
        let ok = c.pedir("GET", "/api/whatsapp/midia?chat=5%40s.whatsapp.net&id=M1")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual((ok.json as? [String: Any])?["tipo"] as? String, "audio/ogg")
        XCTAssertEqual((ok.json as? [String: Any])?["dados"] as? String, Data("oi".utf8).base64EncodedString())
        XCTAssertEqual(c.pedir("GET", "/api/whatsapp/midia?chat=a").status, 400)
        let grande = c.pedir("GET", "/api/whatsapp/midia?chat=a&id=grande")
        XCTAssertEqual(grande.status, 422)
        XCTAssertEqual((grande.json as? [String: Any])?["erro"] as? String, "Arquivo grande demais para abrir aqui.")
        XCTAssertEqual(c.pedir("POST", "/api/whatsapp/midia?chat=a&id=M1").status, 405)
    }

    func testResponderNoMacAbreAConversaESoPorPost() throws {
        let c = try Cenario()
        let ok = c.pedir("POST", "/api/whatsapp/abrir", corpo: #"{"id":"c1"}"#)
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual((ok.json as? [String: Any])?["ok"] as? Bool, true)
        XCTAssertNil((ok.json as? [String: Any])?["aviso"])
        let grupo = c.pedir("POST", "/api/whatsapp/abrir", corpo: #"{"id":"g1"}"#)
        XCTAssertEqual((grupo.json as? [String: Any])?["aviso"] as? String, "Grupo não tem link direto.")
        XCTAssertEqual(c.pedir("POST", "/api/whatsapp/abrir", corpo: #"{"id":"x"}"#).status, 422)
        XCTAssertEqual(c.pedir("POST", "/api/whatsapp/abrir", corpo: "{}").status, 400)
        XCTAssertEqual(c.pedir("GET", "/api/whatsapp/abrir").status, 405)
        XCTAssertEqual(c.registro.todos.filter { $0.hasPrefix("abrir-conversa") }, ["abrir-conversa c1", "abrir-conversa g1", "abrir-conversa x"])
    }

    func testApiNuncaEmCache() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/api/estado").extras["Cache-Control"], "no-store")
        XCTAssertEqual(c.pedir("GET", "/api/nada").extras["Cache-Control"], "no-store")
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: nil).extras["Cache-Control"], "no-store")
        XCTAssertEqual(c.pedir("GET", "/api/capa").extras["Cache-Control"], "no-store")
    }

    func testCapaDevolveOTipoDoProvedor() throws {
        let c = try Cenario()
        let r = c.pedir("GET", "/api/capa")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.tipo, "image/png")
        XCTAssertEqual(r.corpo, Data([1, 2, 3]))
    }

    func testAgendaValidaParametros() throws {
        let c = try Cenario()
        let ok = c.pedir("GET", "/api/agenda?de=2026-11-10&dias=7")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(c.registro.todos, ["agenda 2026-11-10 7"])
        _ = c.pedir("GET", "/api/agenda?de=2026-11-10")
        XCTAssertEqual(c.registro.todos.last, "agenda 2026-11-10 1")
        for ruim in ["/api/agenda", "/api/agenda?de=ontem", "/api/agenda?de=2026-02-30", "/api/agenda?de=2026-13-01",
                     "/api/agenda?de=2026-11-10&dias=0", "/api/agenda?de=2026-11-10&dias=999", "/api/agenda?de=2026-11-10&dias=x"] {
            let r = c.pedir("GET", ruim)
            XCTAssertEqual(r.status, 400, ruim)
            XCTAssertNotNil(r.erroTexto)
        }
        XCTAssertTrue(Roteador.dataValida("2028-02-29"))
        XCTAssertFalse(Roteador.dataValida("2026-02-29"))
        XCTAssertFalse(Roteador.dataValida("2100-02-29"))
    }

    // MARK: Ações

    func testBotaoExecutaATeclaDoPerfilAtivo() throws {
        let c = try Cenario()
        let r = c.pedir("POST", "/api/botao/acordado")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(c.registro.todos, ["tecla acordado"])
        XCTAssertEqual(c.pedir("POST", "/api/botao/so-no-outro").status, 404, "tecla de outro perfil não roda")
        XCTAssertEqual(c.pedir("POST", "/api/botao/nao-existe").status, 404)
        XCTAssertEqual(c.pedir("POST", "/api/botao/").status, 404)
        XCTAssertEqual(c.registro.todos, ["tecla acordado"])
    }

    func testBotaoComErroDoExecutorVira4xxComTexto() throws {
        let c = try Cenario()
        let r = c.pedir("POST", "/api/botao/quebrada")
        XCTAssertEqual(r.status, 422)
        XCTAssertEqual(r.erroTexto, "A tecla falhou.")
    }

    func testSpotify() throws {
        let c = try Cenario()
        for acao in ["tocar", "pausar", "anterior", "proxima"] {
            XCTAssertEqual(c.pedir("POST", "/api/spotify/\(acao)").status, 200)
        }
        XCTAssertEqual(c.pedir("POST", "/api/spotify/posicao?s=42.5").status, 200)
        XCTAssertEqual(c.registro.todos, ["spotify tocar", "spotify pausar", "spotify anterior", "spotify proxima", "posicao 42.5"])
        XCTAssertEqual(c.pedir("POST", "/api/spotify/posicao").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/posicao?s=-1").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/posicao?s=abc").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/explodir").status, 404)
        XCTAssertEqual(c.registro.todos.count, 5)
    }

    func testSpotifyRepetirEAleatorio() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?v=1").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?v=0").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/aleatorio?v=true").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/aleatorio?v=false").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/aleatorio").status, 200)
        XCTAssertEqual(c.registro.todos, ["repetir 1", "repetir 0", "aleatorio 1", "aleatorio 0", "aleatorio alterna"])
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?v=talvez").status, 400)
        XCTAssertEqual(c.pedir("GET", "/api/spotify/repetir").status, 405)
        XCTAssertEqual(c.registro.todos.count, 5, "pedido recusado não chega no Spotify")
    }

    func testSpotifyVolume() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=40").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=0&alvo=mac").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=100&alvo=aparelho").status, 200)
        XCTAssertEqual(c.registro.todos, ["volume spotify 40", "volume mac 0", "volume aparelho 100"])
        for ruim in ["volume", "volume?v=abc", "volume?v=101", "volume?v=-1", "volume?v=4.5"] {
            XCTAssertEqual(c.pedir("POST", "/api/spotify/\(ruim)").status, 400, ruim)
        }
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=10&alvo=lua").status, 400)
        XCTAssertEqual(c.pedir("GET", "/api/spotify/volume?v=10").status, 405)
        XCTAssertEqual(c.registro.todos.count, 3)
    }

    func testSpotifyVolumeDoSpotifyEDoMacFuncionamSemLogin() throws {
        let c = try Cenario(spotifyConectado: false)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=40").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=40&alvo=mac").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/volume?v=40&alvo=aparelho").status, 409)
    }

    func testSpotifyComLoginAparelhosFilaCurtirERepetir() throws {
        let c = try Cenario()
        let aparelhos = c.pedir("GET", "/api/spotify/dispositivos")
        XCTAssertEqual(aparelhos.status, 200)
        let lista = try XCTUnwrap(aparelhos.json as? [[String: Any]])
        XCTAssertEqual(lista.first?["nome"] as? String, "Caixa da sala")
        XCTAssertEqual(lista.first?["ativo"] as? Bool, true)
        let fila = try XCTUnwrap(c.pedir("GET", "/api/spotify/fila").json as? [String: Any])
        XCTAssertEqual((fila["proximas"] as? [[String: Any]])?.first?["faixa"] as? String, "Depois")
        XCTAssertEqual(c.pedir("POST", "/api/spotify/dispositivo?id=d1").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/curtir?v=1").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/curtir?v=0").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?modo=faixa").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?modo=nao").status, 200)
        XCTAssertEqual(c.registro.todos, ["transferir d1", "curtir true", "curtir false", "repetirModo faixa", "repetirModo nao"])
    }

    func testSpotifyRotasNovasRecusamPedidoMalFeito() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/spotify/dispositivo").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/dispositivo?id=").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/curtir").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/curtir?v=2").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/repetir?modo=tudo").status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/dispositivos").status, 405)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/fila").status, 405)
        XCTAssertEqual(c.pedir("GET", "/api/spotify/curtir?v=1").status, 405)
        XCTAssertEqual(c.registro.todos, [])
    }

    func testSemLoginAsRotasDaApiRespondem409ComTextoEOQueJaExistiaSegue() throws {
        let c = try Cenario(spotifyConectado: false)
        for (metodo, rota) in [("GET", "dispositivos"), ("GET", "fila"), ("POST", "dispositivo?id=d1"), ("POST", "curtir?v=1"), ("POST", "repetir?modo=faixa")] {
            let r = c.pedir(metodo, "/api/spotify/\(rota)")
            XCTAssertEqual(r.status, 409, rota)
            XCTAssertEqual(r.erroTexto, ErroSpotify.naoConectado.texto)
        }
        // O que já funcionava só pelo AppleScript não muda.
        XCTAssertEqual(c.pedir("POST", "/api/spotify/tocar").status, 200)
        XCTAssertEqual(c.pedir("POST", "/api/spotify/posicao?s=3").status, 200)
    }

    func testErroDaApiDoSpotifyVira422ComOTexto() throws {
        let c = try Cenario()
        let r = c.pedir("POST", "/api/spotify/dispositivo?id=premium")
        XCTAssertEqual(r.status, 422)
        XCTAssertEqual(r.erroTexto, ErroSpotify.soPremium.texto)
    }

    func testRotasDoSpotifyExigemOCodigoDeAcesso() throws {
        let c = try Cenario()
        for (m, r) in [("GET", "dispositivos"), ("GET", "fila"), ("POST", "volume?v=1"), ("POST", "curtir?v=1")] {
            XCTAssertEqual(c.pedir(m, "/api/spotify/\(r)", codigo: nil).status, 401, r)
        }
    }

    // MARK: Config

    func testConfigNaoExpoeOCodigoDeAcesso() throws {
        let c = try Cenario()
        let r = c.pedir("GET", "/api/config")
        XCTAssertEqual(r.status, 200)
        XCTAssertFalse(r.texto.contains("codigoAcesso"))
        XCTAssertFalse(r.texto.contains(Cenario.codigo))
        XCTAssertEqual((r.json as? [String: Any])?["nomeMac"] as? String, "Mac")
    }

    /// O que o iPhone manda: a config pública (a do GET), sem codigoAcesso e porta, com o nome trocado.
    private func corpoCompleto(_ c: Cenario, nomeMac: String, extra: [String: Any] = [:]) throws -> String {
        var obj = try XCTUnwrap(c.pedir("GET", "/api/config").json as? [String: Any])
        obj.removeValue(forKey: "porta")
        obj["nomeMac"] = nomeMac
        for (k, v) in extra { obj[k] = v }
        return String(decoding: try JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    func testPutConfigGravaEIgnoraCodigoEPorta() throws {
        let c = try Cenario()
        let corpo = try corpoCompleto(c, nomeMac: "Novo", extra: ["codigoAcesso": "invasor", "porta": 1])
        let r = c.pedir("PUT", "/api/config", corpo: corpo)
        XCTAssertEqual(r.status, 200, r.texto)
        let gravada = c.armazem.ler()
        XCTAssertEqual(gravada.nomeMac, "Novo")
        XCTAssertEqual(gravada.codigoAcesso, Cenario.codigo)
        XCTAssertEqual(gravada.porta, 4777)
        XCTAssertEqual(gravada.perfis.count, 2)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: "invasor").status, 401)
    }

    func testPutConfigSemCodigoEPortaPreservaAsDaAtual() throws {
        let c = try Cenario()
        let corpo = try corpoCompleto(c, nomeMac: "Novo")
        XCTAssertFalse(corpo.contains("codigoAcesso"))
        XCTAssertFalse(corpo.contains("\"porta\""))
        XCTAssertEqual(c.pedir("PUT", "/api/config", corpo: corpo).status, 200)
        XCTAssertEqual(c.armazem.ler().codigoAcesso, Cenario.codigo)
        XCTAssertEqual(c.armazem.ler().porta, 4777)
    }

    func testPutConfigParcialEhRecusadoSemGravar() throws {
        let c = try Cenario()
        let r = c.pedir("PUT", "/api/config", corpo: #"{"nomeMac":"Novo"}"#)
        XCTAssertEqual(r.status, 400)
        XCTAssertNotNil(r.erroTexto)
        XCTAssertEqual(c.armazem.ler().nomeMac, "Mac")
        XCTAssertEqual(c.armazem.ler().perfis.count, 2)
    }

    func testPutConfigInvalidaDa400SemGravar() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("PUT", "/api/config", corpo: "lixo").status, 400)
        XCTAssertEqual(c.pedir("PUT", "/api/config", corpo: #"{"perfis":"nada"}"#).status, 400)
        XCTAssertEqual(c.pedir("PUT", "/api/config", corpo: "[1,2]").status, 400)
        c.armazem.erroAoAplicar = "Botão sem nome."
        let r = c.pedir("PUT", "/api/config", corpo: try corpoCompleto(c, nomeMac: "Novo"))
        XCTAssertEqual(r.status, 400)
        XCTAssertEqual(r.erroTexto, "Botão sem nome.")
        XCTAssertEqual(c.armazem.ler().nomeMac, "Mac")
    }

    // MARK: Erros

    func testMetodoErradoDa405ComAllow() throws {
        let c = try Cenario()
        let r = c.pedir("POST", "/api/estado")
        XCTAssertEqual(r.status, 405)
        XCTAssertEqual(r.extras["Allow"], "GET")
        XCTAssertNotNil(r.erroTexto)
        XCTAssertEqual(c.pedir("GET", "/api/botao/acordado").status, 405)
        XCTAssertEqual(c.pedir("GET", "/api/spotify/tocar").status, 405)
        XCTAssertEqual(c.pedir("DELETE", "/api/config").status, 405)
        XCTAssertEqual(c.pedir("GET", "/api/parear", codigo: nil).status, 405)
        XCTAssertEqual(c.pedir("POST", "/index.html", codigo: nil).status, 405)
    }

    func testRotaDesconhecidaDa404() throws {
        let c = try Cenario()
        let r = c.pedir("GET", "/api/nada")
        XCTAssertEqual(r.status, 404)
        XCTAssertNotNil(r.erroTexto)
    }

    func testRespostaSerializaComoHttp() throws {
        let c = try Cenario()
        let bruto = String(decoding: c.pedir("GET", "/api/nada").serializar(), as: UTF8.self)
        XCTAssertTrue(bruto.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(bruto.contains("Cache-Control: no-store\r\n"))
    }

    // MARK: Pareamento pela rota

    func testPearearDevolveOCodigoDeAcessoSemExigirCodigo() throws {
        let c = try Cenario()
        let r = c.pedir("POST", "/api/parear", corpo: #"{"codigo":"123456"}"#, codigo: nil)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual((r.json as? [String: Any])?["codigoAcesso"] as? String, Cenario.codigo)
        // De uso único.
        XCTAssertEqual(c.pedir("POST", "/api/parear", corpo: #"{"codigo":"123456"}"#, codigo: nil).status, 401)
    }

    func testPearearErradoCorpoInvalidoELimite() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/api/parear", corpo: "lixo", codigo: nil).status, 400)
        XCTAssertEqual(c.pedir("POST", "/api/parear", corpo: #"{"outro":1}"#, codigo: nil).status, 400)
        for _ in 0..<5 {
            let r = c.pedir("POST", "/api/parear", corpo: #"{"codigo":"000000"}"#, codigo: nil)
            XCTAssertEqual(r.status, 401)
            XCTAssertFalse(r.texto.contains(Cenario.codigo))
        }
        // Passou do limite: nem o código certo entra mais.
        XCTAssertEqual(c.pedir("POST", "/api/parear", corpo: #"{"codigo":"123456"}"#, codigo: nil).status, 429)
        _ = c.pareamento.gerar()
        XCTAssertEqual(c.pedir("POST", "/api/parear", corpo: #"{"codigo":"123456"}"#, codigo: nil).status, 200)
    }

    // MARK: Certificado do CA

    func testCertificadoDoCAEPublicoEComTipoDeCertificado() throws {
        let c = try Cenario()
        let r = c.pedir("GET", "/ca.crt", codigo: nil)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.tipo, "application/x-x509-ca-cert")
        XCTAssertEqual(r.texto, Cenario.conteudoCA)
        XCTAssertTrue(String(decoding: r.serializar(), as: UTF8.self).contains("Content-Type: application/x-x509-ca-cert\r\n"))
        XCTAssertFalse(r.texto.contains("CHAVE-PRIVADA"))
    }

    func testCertificadoDoCASoPorGETESemArquivoDa404() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("POST", "/ca.crt", codigo: nil).status, 405)
        XCTAssertEqual(c.pedir("GET", "/ca.key", codigo: nil).status, 404)
        let sem = try Cenario(comCA: false)
        let r = sem.pedir("GET", "/ca.crt", codigo: nil)
        XCTAssertEqual(r.status, 404)
        XCTAssertNotNil(r.erroTexto)
    }

    // MARK: Página

    func testPaginaServeIndexETipos() throws {
        let c = try Cenario()
        let raiz = c.pedir("GET", "/", codigo: nil)
        XCTAssertEqual(raiz.status, 200)
        XCTAssertEqual(raiz.texto, "<h1>deck</h1>")
        XCTAssertEqual(raiz.tipo, "text/html; charset=utf-8")
        XCTAssertEqual(c.pedir("GET", "/deck.css", codigo: nil).tipo, "text/css; charset=utf-8")
        XCTAssertEqual(c.pedir("GET", "/app.webmanifest", codigo: nil).status, 200)
        XCTAssertEqual(c.pedir("GET", "/sub/", codigo: nil).texto, "<p>sub</p>")
        XCTAssertEqual(c.pedir("GET", "/sub", codigo: nil).texto, "<p>sub</p>")
        XCTAssertEqual(c.pedir("GET", "/nao-existe.js", codigo: nil).status, 404)
    }

    func testPaginaNaoSaiDaPasta() throws {
        let c = try Cenario()
        let tentativas = ["/../fora.txt", "/sub/../../fora.txt", "/..", "/%2e%2e/fora.txt", "//etc/passwd", "/etc/passwd",
                          "/..%2Ffora.txt", "/sub/..\\..\\fora.txt", "/escapa.txt", "/.env", "/sub/./../.env", "/\0"]
        for t in tentativas {
            // Direto no roteador (caminho já decodificado) e pelo parser, como o servidor faz.
            let direto = c.roteador.responder(HttpRequisicao(metodo: "GET", caminho: t, query: [:], cabecalhos: [:], corpo: Data()))
            XCTAssertEqual(direto.status, 404, t)
            XCTAssertFalse(direto.texto.contains("segredo"), t)
            XCTAssertFalse(direto.texto.contains("env"), t)
            if case .ok(let req) = Http.ler(Data("GET \(t) HTTP/1.1\r\n\r\n".utf8)) {
                let r = c.roteador.responder(req)
                XCTAssertEqual(r.status, 404, "via parser: \(t)")
                XCTAssertFalse(r.texto.contains("segredo"), t)
            }
        }
    }

    func testPaginaNaoExigeCodigoMasApiExige() throws {
        let c = try Cenario()
        XCTAssertEqual(c.pedir("GET", "/", codigo: nil).status, 200)
        XCTAssertEqual(c.pedir("GET", "/api/estado", codigo: nil).status, 401)
    }

    func testAgendaRecusaSinalDentroDaData() throws {
        let c = try Cenario()
        for ruim in ["2026-%2B1-%2B5", "%2B202-%2B1-%2B5", "2026--1-05", "2026-1%2B-05"] {
            let r = c.pedir("GET", "/api/agenda?de=\(ruim)")
            XCTAssertEqual(r.status, 400, ruim)
        }
        XCTAssertEqual(c.registro.todos, [])
    }

    func testLinkVisivelParaArquivoOcultoNaoSai() throws {
        let c = try Cenario()
        try FileManager.default.createSymbolicLink(at: c.raiz.appendingPathComponent("visivel.txt"),
                                                   withDestinationURL: c.raiz.appendingPathComponent(".env"))
        try FileManager.default.createDirectory(at: c.raiz.appendingPathComponent(".oculta"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: c.raiz.appendingPathComponent(".oculta/a.txt"))
        try FileManager.default.createSymbolicLink(at: c.raiz.appendingPathComponent("pasta"),
                                                   withDestinationURL: c.raiz.appendingPathComponent(".oculta"))
        XCTAssertEqual(c.pedir("GET", "/visivel.txt", codigo: nil).status, 404)
        XCTAssertEqual(c.pedir("GET", "/pasta/a.txt", codigo: nil).status, 404)
        XCTAssertEqual(c.pedir("GET", "/deck.css", codigo: nil).status, 200)
    }
}
