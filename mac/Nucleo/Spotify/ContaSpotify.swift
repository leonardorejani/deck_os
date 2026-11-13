import Foundation

// A conta do Spotify no Deck: login por PKCE (sem segredo, só a chave pública do app), renovação do
// token e as chamadas da API que o AppleScript não faz (aparelhos, curtir, fila, repetir a música).
// Sem login nada daqui roda e o player segue só com o AppleScript.

struct ErroSpotify: Error, Equatable, Sendable {
    var texto: String
    /// O erro é "não está conectado": a rota responde 409 e o painel esconde o que depende do login.
    var semLogin = false
    /// A conta não está na lista do app do Deck no Spotify: a tela abre o Avançado e ensina a criar a própria chave.
    var pedeChavePropria = false

    static let naoConectado = ErroSpotify(texto: "Conecte o Spotify nos Ajustes do Mac para usar isso.", semLogin: true)
    static let loginVenceu = ErroSpotify(texto: "O login do Spotify venceu. Conecte de novo nos Ajustes do Mac.", semLogin: true)
    static let semRede = ErroSpotify(texto: "Não consegui falar com o Spotify. Confira a internet do Mac.")
    static let semAparelho = ErroSpotify(texto: "Nenhum aparelho do Spotify está ativo. Toque algo em um aparelho primeiro.")
    static let soPremium = ErroSpotify(texto: "Isso só funciona com o Spotify Premium.")
    static let esperar = ErroSpotify(texto: "O Spotify pediu para esperar um pouco. Tente de novo em instantes.")
    static let faltaPermissao = ErroSpotify(texto: "Falta uma permissão. Desconecte e conecte o Spotify de novo nos Ajustes do Mac.")
    static let recusou = ErroSpotify(texto: "O Spotify recusou o pedido.")
    static let semCadastro = ErroSpotify(texto: "Os extras do Spotify (aparelhos, curtir, fila, repetir a música) pedem uma chave sua. Leva 2 minutos.",
                                         semLogin: true, pedeChavePropria: true)
}

struct DispositivoSpotify: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    /// "computer", "smartphone", "speaker", "tv"... como o Spotify chama (em minúsculas).
    var tipo: String
    var ativo: Bool
    var volume: Int?
    /// O Spotify não deixa controlar esse aparelho (aparece na lista, mas não aceita a transferência).
    var restrito: Bool
}

struct ItemDaFila: Codable, Equatable, Sendable {
    var faixa: String
    var artista: String
    /// Para pular até a música da fila (confere que a fila não andou entre ver e tocar).
    var uri: String? = nil
    /// Capa pequena do Spotify (a menor com pelo menos 128 px, para não ficar borrada na miniatura).
    var capa: String? = nil
}

struct FilaSpotify: Codable, Equatable, Sendable {
    var atual: ItemDaFila?
    var proximas: [ItemDaFila]
    /// Nome da lista, do álbum ou do artista que está tocando ("Próximas de: ..."). nil quando o Spotify não deixa saber.
    var contexto: String? = nil
}

struct RecentesSpotify: Codable, Equatable, Sendable {
    var itens: [ItemDaFila]
}

/// O que o /me/player sabe e o AppleScript não: repetir a música, aparelho ativo e o volume dele.
struct JogadorSpotify: Equatable, Sendable {
    /// "faixa", "contexto" ou "nao". nil: nada tocando em aparelho nenhum.
    var repetir: String?
    var aparelho: String?
    var aparelhoId: String?
    var volumeAparelho: Int?
    var uri: String?
}

/// O que o navegador devolve ao redirecionamento local.
struct RetornoLogin: Equatable, Sendable {
    var codigo: String?
    var estado: String?
    /// "access_denied" quando a pessoa clicou em Cancelar na página do Spotify.
    var erro: String?
}

struct LoginPendente: Equatable, Sendable {
    var url: URL
    var estado: String
    var verificador: String
    var redirecionamento: String
}

final class ContaSpotify: @unchecked Sendable {
    static let api = "https://api.spotify.com/v1"
    static let contas = "https://accounts.spotify.com"
    static let escopos = "user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-library-modify user-read-recently-played"
    /// Quanto antes do vencimento o token já é trocado.
    static let folgaDoToken: Double = 60

    private let armazem: ArmazemSpotify
    private let transporte: TransporteWeb
    private let agora: @Sendable () -> Date
    private let trava = NSLock()
    private var nomesDeContexto: [String: String] = [:]
    /// A chave do Deck (`ChaveSpotify.embutida`), já validada. Nos testes entra à mão.
    private let embutida: String?
    private let travaAviso = NSLock()
    private var _precisaChavePropria = false

    /// O Spotify recusou esta conta na chave embutida (ela não está em User Management do app do Deck). Fica até a pessoa
    /// colar a própria chave ou conectar. Só vale na memória: a tela lê e mostra o passo a passo.
    var precisaChavePropria: Bool {
        get { travaAviso.lock(); defer { travaAviso.unlock() }; return _precisaChavePropria }
        set { travaAviso.lock(); _precisaChavePropria = newValue; travaAviso.unlock() }
    }

    /// Mensagem do Spotify para conta fora da lista de um app em modo de desenvolvimento.
    static func contaForaDaLista(_ texto: String) -> Bool {
        let t = texto.lowercased()
        return t.contains("not registered") || t.contains("not be registered") || t.contains("developer dashboard")
    }

    /// Conta fora da lista só vira "peça a sua chave" quando a chave em uso é a do Deck. Com chave própria o erro segue como era.
    private func conferirCadastro(_ e: ErroSpotify) -> ErroSpotify {
        guard e == .semCadastro else { return e }
        guard chavePropria == nil else { return .recusou }
        precisaChavePropria = true
        return e
    }

    init(armazem: ArmazemSpotify, transporte: TransporteWeb = TransporteUrlSession(), agora: @escaping @Sendable () -> Date = { Date() },
         embutida: String? = ChaveSpotify.embutida) {
        self.embutida = ChaveSpotify.valida(embutida)
        self.armazem = armazem
        self.transporte = transporte
        self.agora = agora
    }

    // MARK: Estado

    /// A chave que a pessoa colou nos Ajustes, se houver.
    /// A mesma chave do Deck guardada no Chaveiro (colada em versão antiga) não é "própria": vale como a do Deck.
    var chavePropria: String? {
        let c = (armazem.ler().clientId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty || c == embutida ? nil : c
    }

    /// O nome da conta do Spotify conectada, guardado depois do login. nil até o Spotify responder.
    var nome: String? { conectado ? armazem.ler().nome : nil }

    var temChaveEmbutida: Bool { embutida != nil }

    /// A que vale: a colada pela pessoa vence, senão a que vem no Deck.
    var clientId: String? { chavePropria ?? embutida }

    var conectado: Bool { armazem.ler().logado }

    /// A chave do app do Spotify tem 32 letras e números (hexadecimal). Devolve o erro em texto, ou nil se gravou.
    func definirClientId(_ texto: String) -> String? {
        let c = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.chaveValida(c) else { return "A chave do app tem 32 letras e números. Copie de novo no site do Spotify." }
        precisaChavePropria = false
        var d = armazem.ler()
        if clientId != c { d.acesso = nil; d.renovacao = nil; d.expiraEm = nil; d.nome = nil }
        d.clientId = c == embutida ? nil : c
        return armazem.gravar(d) ? nil : "Não consegui guardar a chave no Chaveiro do Mac."
    }

    static func chaveValida(_ c: String) -> Bool {
        c.count == 32 && c.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Esquece a chave colada e volta para a do Deck. Os tokens eram de outra chave, então saem junto.
    func usarChaveDoDeck() {
        precisaChavePropria = false
        var d = armazem.ler()
        guard d.clientId != nil else { return }
        d.clientId = nil; d.acesso = nil; d.renovacao = nil; d.expiraEm = nil; d.nome = nil
        armazem.gravar(d)
    }

    /// Sai do Spotify neste Mac. A chave do app fica, para conectar de novo sem colar outra vez.
    func desconectar() {
        var d = armazem.ler()
        d.acesso = nil; d.renovacao = nil; d.expiraEm = nil; d.nome = nil
        armazem.gravar(d)
    }

    /// Pergunta ao Spotify quem é a conta conectada e guarda o nome. nil se não conseguiu (a conta segue conectada).
    @discardableResult
    func atualizarNome() -> String? {
        guard conectado else { return nil }
        guard case .success(let r) = chamar("GET", "/me") else { return nome }
        let obj = json(r) as? [String: Any]
        let nome = ((obj?["display_name"] as? String) ?? (obj?["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return self.nome }
        var d = armazem.ler()
        d.nome = nome
        armazem.gravar(d)
        return nome
    }

    // MARK: Login

    func prepararLogin(redirecionamento: String) -> Result<LoginPendente, ErroSpotify> {
        guard let cid = clientId else { return .failure(ErroSpotify(texto: "Cole a chave do app do Spotify antes de conectar.")) }
        let verificador = Pkce.verificador()
        let estado = Pkce.estado()
        var c = URLComponents(string: Self.contas + "/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "scope", value: Self.escopos),
            URLQueryItem(name: "redirect_uri", value: redirecionamento),
            URLQueryItem(name: "state", value: estado),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Pkce.desafio(verificador)),
        ]
        guard let url = c.url else { return .failure(.recusou) }
        return .success(LoginPendente(url: url, estado: estado, verificador: verificador, redirecionamento: redirecionamento))
    }

    /// Troca o código pelos tokens e guarda. Devolve o erro em texto, ou nil se conectou.
    func concluirLogin(_ p: LoginPendente, retorno: RetornoLogin) -> String? {
        if let erro = retorno.erro {
            // Conta fora da lista do app do Deck: o Spotify devolve outro erro que não o de "Cancelar" (access_denied).
            if erro != "access_denied", chavePropria == nil, embutida != nil { return conferirCadastro(.semCadastro).texto }
            return "O login do Spotify foi cancelado."
        }
        guard retorno.estado == p.estado else { return "O retorno do Spotify não é deste login. Tente conectar de novo." }
        guard let codigo = retorno.codigo, !codigo.isEmpty, let cid = clientId else { return "O Spotify não mandou o código do login." }
        let r = pedirToken([("grant_type", "authorization_code"), ("code", codigo), ("redirect_uri", p.redirecionamento),
                            ("client_id", cid), ("code_verifier", p.verificador)])
        switch r {
        case .failure(let e): return e.texto
        case .success(let t):
            guard let renovacao = t.renovacao else { return "O Spotify não entregou o login completo. Tente de novo." }
            var d = armazem.ler()
            d.acesso = t.acesso; d.renovacao = renovacao; d.expiraEm = agora().timeIntervalSince1970 + t.duracao; d.nome = nil
            precisaChavePropria = false
            return armazem.gravar(d) ? nil : "Não consegui guardar o login no Chaveiro do Mac."
        }
    }

    // MARK: Token

    private struct Token { var acesso: String; var renovacao: String?; var duracao: Double }

    private func pedirToken(_ campos: [(String, String)]) -> Result<Token, ErroSpotify> {
        let corpo = Self.formulario(campos)
        let req = RequisicaoWeb(metodo: "POST", url: Self.contas + "/api/token",
                                cabecalhos: ["Content-Type": "application/x-www-form-urlencoded"], corpo: Data(corpo.utf8))
        guard let r = transporte.enviar(req) else { return .failure(.semRede) }
        let obj = (try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any]
        guard (200..<300).contains(r.status), let acesso = obj?["access_token"] as? String else {
            if Self.contaForaDaLista(String(decoding: r.corpo, as: UTF8.self)) { return .failure(conferirCadastro(.semCadastro)) }
            let motivo = obj?["error"] as? String
            if motivo == "invalid_grant" { return .failure(.loginVenceu) }
            if motivo == "invalid_client" { return .failure(ErroSpotify(texto: "O Spotify não reconheceu a chave do app. Confira se copiou inteira.")) }
            if r.status >= 500 { return .failure(.semRede) }
            return .failure(.recusou)
        }
        let duracao = (obj?["expires_in"] as? Double) ?? Double((obj?["expires_in"] as? Int) ?? 3600)
        return .success(Token(acesso: acesso, renovacao: obj?["refresh_token"] as? String, duracao: duracao))
    }

    /// O token de acesso, trocado antes de vencer. Login vencido de vez (o Spotify recusou a renovação)
    /// apaga os tokens: a tela volta a pedir "Conectar".
    private func tokenDeAcesso(forcar: Bool = false) -> Result<String, ErroSpotify> {
        trava.lock(); defer { trava.unlock() }
        var d = armazem.ler()
        guard d.logado, let cid = clientId, let renovacao = d.renovacao else { return .failure(.naoConectado) }
        if !forcar, let a = d.acesso, let e = d.expiraEm, e - agora().timeIntervalSince1970 > Self.folgaDoToken { return .success(a) }
        switch pedirToken([("grant_type", "refresh_token"), ("refresh_token", renovacao), ("client_id", cid)]) {
        case .failure(let e):
            if e == .loginVenceu { d.acesso = nil; d.renovacao = nil; d.expiraEm = nil; d.nome = nil; armazem.gravar(d) }
            return .failure(e)
        case .success(let t):
            d.acesso = t.acesso
            if let nova = t.renovacao { d.renovacao = nova }
            d.expiraEm = agora().timeIntervalSince1970 + t.duracao
            armazem.gravar(d)
            return .success(t.acesso)
        }
    }

    // MARK: Chamada

    static func formulario(_ campos: [(String, String)]) -> String {
        let livres = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return campos.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: livres) ?? "")"
        }.joined(separator: "&")
    }

    private func chamar(_ metodo: String, _ caminho: String, _ query: [(String, String)] = [], json: [String: Any]? = nil) -> Result<RespostaWeb, ErroSpotify> {
        var url = Self.api + caminho
        if !query.isEmpty { url += "?" + Self.formulario(query) }
        let corpo = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        func uma(_ forcar: Bool) -> Result<RespostaWeb, ErroSpotify> {
            switch tokenDeAcesso(forcar: forcar) {
            case .failure(let e): return .failure(e)
            case .success(let t):
                var cab = ["Authorization": "Bearer \(t)"]
                if corpo != nil { cab["Content-Type"] = "application/json" }
                guard let r = transporte.enviar(RequisicaoWeb(metodo: metodo, url: url, cabecalhos: cab, corpo: corpo)) else { return .failure(.semRede) }
                return .success(r)
            }
        }
        var resposta = uma(false)
        // O Spotify pode ter invalidado o token antes da hora: uma troca e uma segunda tentativa.
        if case .success(let r) = resposta, r.status == 401 { resposta = uma(true) }
        guard case .success(let r) = resposta else { return resposta }
        if (200..<300).contains(r.status) { return .success(r) }
        let e = conferirCadastro(Self.traduzir(r))
        // Meio logado não serve: com a chave do Deck e conta fora da lista, sai do login para a tela pedir a chave própria.
        if e == .semCadastro { desconectar() }
        return .failure(e)
    }

    static func traduzir(_ r: RespostaWeb) -> ErroSpotify {
        let erro = ((try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any])?["error"] as? [String: Any]
        let motivo = (erro?["reason"] as? String) ?? ""
        let mensagem = ((erro?["message"] as? String) ?? "").lowercased()
        if motivo == "PREMIUM_REQUIRED" || mensagem.contains("premium") { return .soPremium }
        if motivo == "NO_ACTIVE_DEVICE" { return .semAparelho }
        switch r.status {
        case 401: return .loginVenceu
        case 403:
            if contaForaDaLista(mensagem) { return .semCadastro }
            return mensagem.contains("scope") ? .faltaPermissao : .recusou
        case 404: return .semAparelho
        case 429: return .esperar
        case 500...: return .semRede
        default: return .recusou
        }
    }

    private func json(_ r: RespostaWeb) -> Any? { r.corpo.isEmpty ? nil : try? JSONSerialization.jsonObject(with: r.corpo) }

    // MARK: Aparelhos

    func dispositivos() -> Result<[DispositivoSpotify], ErroSpotify> {
        chamar("GET", "/me/player/devices").map { r in
            let lista = ((json(r) as? [String: Any])?["devices"] as? [[String: Any]]) ?? []
            return lista.compactMap { d in
                guard let nome = d["name"] as? String else { return nil }
                return DispositivoSpotify(id: (d["id"] as? String) ?? "", nome: nome, tipo: ((d["type"] as? String) ?? "").lowercased(),
                                          ativo: (d["is_active"] as? Bool) ?? false, volume: d["volume_percent"] as? Int,
                                          restrito: (d["is_restricted"] as? Bool) ?? false)
            }
        }
    }

    /// Passa a música para o aparelho. Quem estava tocando segue tocando, e quem estava pausado segue pausado.
    func transferir(para id: String) -> ErroSpotify? {
        guard !id.isEmpty else { return .recusou }
        return erro(chamar("PUT", "/me/player", json: ["device_ids": [id]]))
    }

    func volumeDoAparelho(_ n: Int, aparelho: String? = nil) -> ErroSpotify? {
        var q: [(String, String)] = [("volume_percent", String(max(0, min(100, n))))]
        if let aparelho, !aparelho.isEmpty { q.append(("device_id", aparelho)) }
        return erro(chamar("PUT", "/me/player/volume", q))
    }

    // MARK: Curtir

    /// O Spotify só aceita `spotify:track:<id>` (o AppleScript devolve nesse formato). Arquivo local não entra.
    static func uriDeFaixa(_ uri: String) -> Bool {
        let p = uri.split(separator: ":", omittingEmptySubsequences: false)
        return p.count == 3 && p[0] == "spotify" && p[1] == "track" && !p[2].isEmpty && p[2].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    func curtir(_ uri: String, _ curtir: Bool) -> ErroSpotify? {
        guard Self.uriDeFaixa(uri) else { return ErroSpotify(texto: "Essa faixa não é do catálogo do Spotify, então não dá para curtir.") }
        return erro(chamar(curtir ? "PUT" : "DELETE", "/me/library", [("uris", uri)]))
    }

    func curtida(_ uri: String) -> Result<Bool, ErroSpotify> {
        guard Self.uriDeFaixa(uri) else { return .success(false) }
        return chamar("GET", "/me/library/contains", [("uris", uri)]).map { r in ((json(r) as? [Bool]) ?? []).first ?? false }
    }

    // MARK: Fila e repetição

    func fila(limite: Int = 20) -> Result<FilaSpotify, ErroSpotify> {
        let r = chamar("GET", "/me/player/queue").map { r in
            let obj = (json(r) as? [String: Any]) ?? [:]
            let proximas = ((obj["queue"] as? [Any]) ?? []).compactMap(Self.itemDaFila).prefix(limite)
            return FilaSpotify(atual: Self.itemDaFila(obj["currently_playing"]), proximas: Array(proximas))
        }
        guard case .success(var f) = r else { return r }
        f.contexto = nomeDoContexto()
        return .success(f)
    }

    /// Música ou episódio do JSON do Spotify. A capa vem do álbum (ou do programa, no podcast).
    static func itemDaFila(_ o: Any?) -> ItemDaFila? {
        guard let d = o as? [String: Any], let nome = d["name"] as? String else { return nil }
        let artistas = (d["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")
        // Podcast não tem artista: vale o nome do programa.
        let quem = (artistas?.isEmpty == false ? artistas : nil) ?? ((d["show"] as? [String: Any])?["name"] as? String) ?? ""
        let imagens = ((d["album"] as? [String: Any])?["images"] as? [[String: Any]]) ?? (d["images"] as? [[String: Any]]) ?? []
        return ItemDaFila(faixa: nome, artista: quem, uri: d["uri"] as? String, capa: capaPequena(imagens))
    }

    /// Das imagens do Spotify (da maior para a menor), a menor que ainda tem 128 px de largura. Sem tamanho, a última.
    static func capaPequena(_ imagens: [[String: Any]]) -> String? {
        let urls = imagens.compactMap { i -> (String, Int)? in (i["url"] as? String).map { ($0, (i["width"] as? Int) ?? 0) } }
        return (urls.filter { $0.1 >= 128 }.min { $0.1 < $1.1 } ?? urls.last)?.0
    }

    /// De onde vêm as próximas: a lista, o álbum ou o artista que toca. O nome é pedido uma vez por contexto e guardado.
    /// Lista privada não deixa ler o nome (falta permissão): fica nil e a tela diz só "Próximas".
    private func nomeDoContexto() -> String? {
        guard case .success(let r) = chamar("GET", "/me/player"),
              let ctx = (json(r) as? [String: Any])?["context"] as? [String: Any],
              let uri = ctx["uri"] as? String else { return nil }
        let partes = uri.split(separator: ":").map(String.init)
        guard partes.count == 3, ["playlist", "album", "artist"].contains(partes[1]) else { return nil }
        trava.lock(); let guardado = nomesDeContexto[uri]; trava.unlock()
        if let guardado { return guardado }
        let caminho = ["playlist": "/playlists/", "album": "/albums/", "artist": "/artists/"][partes[1]]! + partes[2]
        let query = partes[1] == "playlist" ? [("fields", "name")] : []
        guard case .success(let n) = chamar("GET", caminho, query), let nome = (json(n) as? [String: Any])?["name"] as? String else { return nil }
        trava.lock(); nomesDeContexto[uri] = nome; trava.unlock()
        return nome
    }

    /// Quanto esperar o Spotify assentar o que está tocando antes de conferir o pulo. Os testes zeram.
    var esperaDoPulo: TimeInterval = 0.4

    /// Toca a música da fila que a pessoa escolheu, direto, sem tocar as do meio. `posicao` é a vez dela (1 é a próxima).
    /// Com `uri`, confere na fila de agora: se ela andou, acha a música onde estiver, e se sumiu, não pula nada.
    /// Salto direto, nunca `next` em sequência (cada `next` faz a faixa do meio começar a tocar):
    /// 1. lista ou álbum que toca: `play` com `context_uri` e `offset` na música, e a lista segue dali.
    /// 2. música da fila manual (fora da lista), artista ou o Spotify recusou o salto: `play` com `uris`, a escolhida
    ///    seguida das que vinham depois dela na fila. A lista de origem deixa de ser o contexto, mas a ordem da tela se mantém.
    /// Sem `uri` não há como saltar: cai nos `next` de antes.
    func pularFila(posicao: Int, uri: String?) -> ErroSpotify? {
        guard let uri else {
            guard (1...50).contains(posicao) else { return .recusou }
            for _ in 0..<posicao { if let e = erro(chamar("POST", "/me/player/next")) { return e } }
            return nil
        }
        guard case .success(let f) = fila(limite: 50) else { return ErroSpotify(texto: "A fila mudou. Abra a fila de novo.") }
        // A mesma música pode aparecer mais de uma vez: fica com a cópia mais perto da vez que a tela mandou.
        let achadas = f.proximas.indices.filter { f.proximas[$0].uri == uri }
        guard let i = achadas.min(by: { abs($0 + 1 - posicao) < abs($1 + 1 - posicao) }) else {
            return ErroSpotify(texto: "A fila mudou. Abra a fila de novo.")
        }
        guard (1...50).contains(i + 1) else { return .recusou }
        let depois = f.proximas[i...].compactMap { $0.uri }
        let contexto = contextoQueToca()
        if let contexto, ["playlist", "album"].contains(contexto.split(separator: ":").dropFirst().first.map(String.init) ?? "") {
            let r = chamar("PUT", "/me/player/play", json: ["context_uri": contexto, "offset": ["uri": uri]])
            if case .success = r, tocaAgora(uri) { return nil }
        }
        return erro(chamar("PUT", "/me/player/play", json: ["uris": depois]))
    }

    private func contextoQueToca() -> String? {
        guard case .success(let r) = chamar("GET", "/me/player") else { return nil }
        return ((json(r) as? [String: Any])?["context"] as? [String: Any])?["uri"] as? String
    }

    /// O Spotify às vezes aceita o `play` com um offset que não é da lista e toca outra coisa. Confere o que tocou.
    private func tocaAgora(_ uri: String) -> Bool {
        for tentativa in 0..<3 {
            if case .success(let j) = jogador(), j.uri == uri { return true }
            if tentativa < 2 && esperaDoPulo > 0 { Thread.sleep(forTimeInterval: esperaDoPulo) }
        }
        return false
    }

    /// O que tocou por último, mais recente primeiro. Pede a permissão de histórico, que logins antigos não têm.
    func recentes(limite: Int = 20) -> Result<RecentesSpotify, ErroSpotify> {
        chamar("GET", "/me/player/recently-played", [("limit", String(limite))]).map { r in
            let itens = ((json(r) as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            return RecentesSpotify(itens: itens.compactMap { Self.itemDaFila($0["track"]) })
        }
    }

    /// "faixa" repete só a música, "nao" desliga, "contexto" repete o álbum ou a lista.
    func repetir(_ modo: String) -> ErroSpotify? {
        guard let estado = ["faixa": "track", "nao": "off", "contexto": "context"][modo] else { return .recusou }
        return erro(chamar("PUT", "/me/player/repeat", [("state", estado)]))
    }

    func jogador() -> Result<JogadorSpotify, ErroSpotify> {
        chamar("GET", "/me/player").map { r in
            guard let obj = json(r) as? [String: Any] else { return JogadorSpotify() }
            let modos = ["track": "faixa", "off": "nao", "context": "contexto"]
            let aparelho = obj["device"] as? [String: Any]
            return JogadorSpotify(repetir: (obj["repeat_state"] as? String).flatMap { modos[$0] },
                                  aparelho: aparelho?["name"] as? String, aparelhoId: aparelho?["id"] as? String,
                                  volumeAparelho: aparelho?["volume_percent"] as? Int,
                                  uri: (obj["item"] as? [String: Any])?["uri"] as? String)
        }
    }

    private func erro(_ r: Result<RespostaWeb, ErroSpotify>) -> ErroSpotify? {
        if case .failure(let e) = r { return e }
        return nil
    }
}
