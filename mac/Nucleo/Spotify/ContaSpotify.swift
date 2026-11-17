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
    /// A uri do contexto (lista ou álbum) que toca. O painel devolve ela em pular, e o Mac toca sem perguntar de novo.
    var contextoUri: String? = nil
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
    private let limite: ArmazemDoLimite
    private let transporte: TransporteWeb
    private let agora: @Sendable () -> Date
    private let trava = NSLock()
    private var nomesDeContexto: [String: String] = [:]
    /// A chave do Deck (`ChaveSpotify.embutida`), já validada. Nos testes entra à mão.
    private let embutida: String?
    private let travaAviso = NSLock()
    private var _precisaChavePropria = false
    private var _registrar: @Sendable (String) -> Void = { _ in }
    /// Até quando o Spotify mandou esperar (429 com Retry-After). Enquanto não passa, nenhum pedido sai.
    private let travaLimite = NSLock()
    private var _bloqueadoAte: Date?
    private var recentesGuardados: (itens: RecentesSpotify, limite: Int, em: Date)?
    private var filaGuardada: (fila: FilaSpotify, limite: Int, em: Date)?
    /// Um pedido de fila por vez: quem chega junto espera e já pega o resultado guardado, sem pedir de novo.
    private let travaDaFila = NSLock()
    /// Quantas chamadas saíram para a API no minuto corrente, por rota. O resumo vai ao log a cada minuto (sem token nem query).
    private let travaContagem = NSLock()
    private var contagem: [String: Int] = [:]
    private var bloqueadas = 0
    private var janelaDaContagem: Date?
    private var pulosFeitos = 0
    /// Quanto os recentes ficam guardados antes de pedir de novo (a aba pode abrir e fechar à vontade).
    static let validadeDosRecentes: TimeInterval = 60
    /// A fila anda a cada música, mas a tela só a pede ao abrir a folha: 10 s bastam para dois pedidos juntos não irem duas vezes.
    static let validadeDaFila: TimeInterval = 10
    /// Espera quando o Spotify manda 429 sem dizer quanto.
    static let esperaPadraoDoLimite: TimeInterval = 30
    /// Roda o que sobra do pulo depois que o painel já foi respondido. Os testes trocam por execução na hora.
    var emSegundoPlano: @Sendable (@escaping @Sendable () -> Void) -> Void = { trabalho in DispatchQueue.global(qos: .userInitiated).async(execute: trabalho) }

    /// Escreve no log do app (deck.log) o rastro do que a conta fez. Padrão: nada. Nunca recebe token, código nem cabeçalho.
    var registrar: @Sendable (String) -> Void {
        get { travaAviso.lock(); defer { travaAviso.unlock() }; return _registrar }
        set { travaAviso.lock(); _registrar = newValue; travaAviso.unlock() }
    }

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

    init(armazem: ArmazemSpotify, limite: ArmazemDoLimite = LimiteEmMemoria(), transporte: TransporteWeb = TransporteUrlSession(), agora: @escaping @Sendable () -> Date = { Date() },
         embutida: String? = ChaveSpotify.embutida) {
        self.embutida = ChaveSpotify.valida(embutida)
        self.armazem = armazem
        self.limite = limite
        self.transporte = transporte
        self.agora = agora
        // O pedido de espera sobrevive ao reinício do app: sem isso o 429 volta e a punição só cresce.
        // Vem de um arquivo comum: a abertura do app não pode tocar no Chaveiro.
        _bloqueadoAte = limite.ler()
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
        if clientId != c { d.acesso = nil; d.renovacao = nil; d.expiraEm = nil; d.nome = nil; esquecerLimite() }
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
        esquecerLimite()
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
        contar("POST accounts/api/token")
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

    /// Corpo enviado, resumido para o log (só uris e ids do Spotify, sem texto longo).
    private static func resumoDoCorpo(_ json: [String: Any]?) -> String {
        guard let json, let d = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), let t = String(data: d, encoding: .utf8) else { return "-" }
        return t.count > 300 ? String(t.prefix(300)) + "..." : t
    }

    private func chamar(_ metodo: String, _ caminho: String, _ query: [(String, String)] = [], json: [String: Any]? = nil, rastro: String? = nil) -> Result<RespostaWeb, ErroSpotify> {
        var url = Self.api + caminho
        if !query.isEmpty { url += "?" + Self.formulario(query) }
        let corpo = json.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        resumirChamadas()
        if let resta = limiteRestante() {
            contar(nil)
            if let rastro { registrar("spotify: \(rastro) \(metodo) \(caminho) não enviado, o Spotify mandou esperar mais \(Int(resta.rounded(.up))) s") }
            return .failure(.esperar)
        }
        func uma(_ forcar: Bool) -> Result<RespostaWeb, ErroSpotify> {
            switch tokenDeAcesso(forcar: forcar) {
            case .failure(let e): return .failure(e)
            case .success(let t):
                var cab = ["Authorization": "Bearer \(t)"]
                if corpo != nil { cab["Content-Type"] = "application/json" }
                contar(Self.rotaParaContar(metodo, caminho))
                guard let r = transporte.enviar(RequisicaoWeb(metodo: metodo, url: url, cabecalhos: cab, corpo: corpo)) else { return .failure(.semRede) }
                return .success(r)
            }
        }
        var resposta = uma(false)
        // O Spotify pode ter invalidado o token antes da hora: uma troca e uma segunda tentativa.
        if case .success(let r) = resposta, r.status == 401 { resposta = uma(true) }
        guard case .success(let r) = resposta else {
            if let rastro, case .failure(let f) = resposta { registrar("spotify: \(rastro) \(metodo) \(caminho) sem resposta (\(f.texto))") }
            return resposta
        }
        if let rastro {
            let trecho = (200..<300).contains(r.status) ? "" : " corpo=" + String(String(decoding: r.corpo, as: UTF8.self).prefix(200)).replacingOccurrences(of: "\n", with: " ")
            registrar("spotify: \(rastro) \(metodo) \(caminho) corpo enviado=\(Self.resumoDoCorpo(json)) -> HTTP \(r.status)\(trecho)")
        }
        if (200..<300).contains(r.status) { return .success(r) }
        if r.status == 429 { registrarLimite(r.esperar, metodo: metodo, caminho: caminho) }
        let e = conferirCadastro(Self.traduzir(r))
        // Meio logado não serve: com a chave do Deck e conta fora da lista, sai do login para a tela pedir a chave própria.
        if e == .semCadastro { desconectar() }
        return .failure(e)
    }

    private static func rotaParaContar(_ metodo: String, _ caminho: String) -> String {
        let p = caminho.split(separator: "/", omittingEmptySubsequences: true)
        if p.count == 2, ["playlists", "albums", "artists"].contains(String(p[0])) { return "\(metodo) /\(p[0])/:id" }
        return "\(metodo) \(caminho)"
    }

    /// Soma uma chamada enviada (rota) ou, sem rota, uma que nem saiu porque o Spotify mandou esperar.
    private func contar(_ rota: String?) {
        travaContagem.lock(); defer { travaContagem.unlock() }
        if janelaDaContagem == nil { janelaDaContagem = agora() }
        if let rota { contagem[rota, default: 0] += 1 } else { bloqueadas += 1 }
    }

    /// A cada minuto, uma linha no log com quantas chamadas saíram por rota, para ver o gasto da cota. Minuto sem chamada não escreve.
    func resumirChamadas() {
        let agoraMesmo = agora()
        travaContagem.lock()
        guard let inicio = janelaDaContagem else { travaContagem.unlock(); return }
        guard agoraMesmo.timeIntervalSince(inicio) >= 60 else { travaContagem.unlock(); return }
        let c = contagem, b = bloqueadas
        contagem = [:]; bloqueadas = 0; janelaDaContagem = nil
        travaContagem.unlock()
        let total = c.values.reduce(0, +)
        let rotas = c.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        registrar("spotify: chamadas à API no último minuto: \(total)\(rotas.isEmpty ? "" : " (" + rotas + ")"), seguradas pelo limite: \(b)")
    }

    /// Até quando o Spotify mandou esperar, ou nil se já pode chamar.
    var bloqueadoAte: Date? {
        guard let resta = limiteRestante() else { return nil }
        return agora().addingTimeInterval(resta)
    }

    /// O limite do Spotify é do app (da chave): trocando a chave, a espera da anterior não vale.
    private func esquecerLimite() { travaLimite.lock(); _bloqueadoAte = nil; travaLimite.unlock(); limite.gravar(nil) }

    /// Segundos que ainda faltam do pedido de espera do Spotify, ou nil se já pode chamar.
    func limiteRestante() -> TimeInterval? {
        travaLimite.lock(); defer { travaLimite.unlock() }
        guard let ate = _bloqueadoAte else { return nil }
        let resta = ate.timeIntervalSince(agora())
        if resta <= 0 { _bloqueadoAte = nil; return nil }
        return resta
    }

    /// O Spotify disse 429: respeita o Retry-After (sem ele, 30 s). Insistir durante a espera só a alonga.
    private func registrarLimite(_ segundos: TimeInterval?, metodo: String, caminho: String) {
        let s = min(max(segundos ?? Self.esperaPadraoDoLimite, 1), 86_400)
        let ate = agora().addingTimeInterval(s)
        travaLimite.lock(); _bloqueadoAte = ate; travaLimite.unlock()
        limite.gravar(ate)
        registrar("spotify: limite de pedidos em \(metodo) \(caminho) (HTTP 429), esperando \(Int(s.rounded(.up))) s\(segundos == nil ? " (o Spotify não disse quanto)" : "")")
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

    /// Guarda a fila por `validadeDaFila` e serializa os pedidos. `fresca` pula o guardado (o pulo confere a fila de agora).
    /// Com o Spotify pedindo espera, devolve a que já tinha, mesmo velha.
    func fila(limite: Int = 20, rastro: String? = nil, fresca: Bool = false) -> Result<FilaSpotify, ErroSpotify> {
        travaDaFila.lock(); defer { travaDaFila.unlock() }
        travaLimite.lock(); let guardada = filaGuardada; travaLimite.unlock()
        if !fresca, let g = guardada, g.limite == limite, agora().timeIntervalSince(g.em) < Self.validadeDaFila { return .success(g.fila) }
        let nova = lerFila(limite: limite, rastro: rastro)
        switch nova {
        case .success(let f): travaLimite.lock(); filaGuardada = (f, limite, agora()); travaLimite.unlock()
        case .failure(let e): if e == .esperar, let g = guardada, g.limite == limite { return .success(g.fila) }
        }
        return nova
    }

    private func lerFila(limite: Int, rastro: String?) -> Result<FilaSpotify, ErroSpotify> {
        let r = chamar("GET", "/me/player/queue", rastro: rastro).map { r in
            let obj = (json(r) as? [String: Any]) ?? [:]
            let proximas = ((obj["queue"] as? [Any]) ?? []).compactMap(Self.itemDaFila).prefix(limite)
            return FilaSpotify(atual: Self.itemDaFila(obj["currently_playing"]), proximas: Array(proximas))
        }
        guard case .success(var f) = r else { return r }
        let c = nomeDoContexto()
        f.contexto = c?.nome
        f.contextoUri = c?.uri
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
    private func nomeDoContexto() -> (nome: String?, uri: String)? {
        guard case .success(let r) = chamar("GET", "/me/player"),
              let ctx = (json(r) as? [String: Any])?["context"] as? [String: Any],
              let uri = ctx["uri"] as? String else { return nil }
        let partes = uri.split(separator: ":").map(String.init)
        guard partes.count == 3, ["playlist", "album", "artist"].contains(partes[1]) else { return nil }
        trava.lock(); let guardado = nomesDeContexto[uri]; trava.unlock()
        if let guardado { return (guardado, uri) }
        let caminho = ["playlist": "/playlists/", "album": "/albums/", "artist": "/artists/"][partes[1]]! + partes[2]
        let query = partes[1] == "playlist" ? [("fields", "name")] : []
        guard case .success(let n) = chamar("GET", caminho, query), let nome = (json(n) as? [String: Any])?["name"] as? String else { return (nil, uri) }
        trava.lock(); nomesDeContexto[uri] = nome; trava.unlock()
        return (nome, uri)
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
    ///
    /// Com `contexto` (a lista ou o álbum que o painel viu na fila), o salto sai na hora: um `play` com context_uri e offset,
    /// sem ler nada antes, e o painel é respondido assim que o Spotify aceita. A conferência (o Spotify trocou mesmo?) e o
    /// plano B do play de uris correm depois, em segundo plano. Sem contexto, ou se o play recusar, vale o caminho lento.
    func pularFila(posicao: Int, uri: String?, contexto: String? = nil) -> ErroSpotify? {
        let meu = cancelarCorrecaoDoPulo()
        if let uri, let contexto, Self.contextoDeSalto(contexto), (1...50).contains(posicao) {
            let rt = "pular"
            registrar("spotify: \(rt) pedido posicao=\(posicao) uri=\(uri) contexto do painel=\(contexto)")
            let r = chamar("PUT", "/me/player/play", json: ["context_uri": contexto, "offset": ["uri": uri]], rastro: rt)
            if case .success = r {
                registrar("spotify: \(rt) play aceito na hora, conferência em segundo plano")
                registrar("spotify: \(rt) resultado para o painel: ok")
                emSegundoPlano { [self] in conferirPulo(uri: uri, vez: meu) }
                return nil
            }
            if case .failure(let e) = r, e == .esperar { return e }
            registrar("spotify: \(rt) play direto não passou, segue o caminho com conferência")
        }
        return pularFilaConferindo(posicao: posicao, uri: uri)
    }

    /// Qualquer outra ação que muda o que toca (próxima, anterior, pausa, outro pulo, trocar de aparelho) chama isto:
    /// a conferência do pulo anterior, que ainda corre em segundo plano, deixa de valer e não refaz a fila por cima.
    @discardableResult
    func cancelarCorrecaoDoPulo() -> Int {
        travaLimite.lock(); defer { travaLimite.unlock() }
        filaGuardada = nil
        pulosFeitos += 1
        return pulosFeitos
    }

    /// Só lista e álbum entram no salto direto, e só no formato do Spotify (a uri vai para o corpo do pedido).
    static func contextoDeSalto(_ c: String) -> Bool {
        let p = c.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        return p.count == 3 && p[0] == "spotify" && ["playlist", "album"].contains(p[1])
            && !p[2].isEmpty && p[2].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Depois do play direto: confere se o Spotify trocou. Se não, o plano B (play de uris). Um toque novo cancela este.
    private func conferirPulo(uri: String, vez: Int) {
        let rt = "pular"
        func atual() -> Bool { travaLimite.lock(); defer { travaLimite.unlock() }; return pulosFeitos == vez }
        if esperaDoPulo > 0 { Thread.sleep(forTimeInterval: esperaDoPulo) }
        let ok = tocaAgora(uri, rastro: rt, ate: atual)
        registrar("spotify: \(rt) conferência em segundo plano, tocaAgora=\(ok)")
        guard !ok, atual() else { return }
        guard case .success(let f) = fila(limite: 50, rastro: rt, fresca: true), let i = f.proximas.firstIndex(where: { $0.uri == uri }) else {
            registrar("spotify: \(rt) plano B sem a música na fila, não mexe")
            return
        }
        let depois = f.proximas[i...].compactMap { $0.uri }
        guard atual() else { return }
        // O Spotify pode ter assentado nesse meio tempo: reiniciar a faixa que já começou seria pior que não corrigir.
        if case .success(let j) = jogador(rastro: rt), j.uri == uri {
            registrar("spotify: \(rt) plano B dispensado, o Spotify já toca a escolhida")
            return
        }
        guard atual() else { return }
        let r = chamar("PUT", "/me/player/play", json: ["uris": depois], rastro: rt)
        registrar("spotify: \(rt) plano B em segundo plano (play de uris): \(erro(r)?.texto ?? "aceito")")
    }

    private func pularFilaConferindo(posicao: Int, uri: String?) -> ErroSpotify? {
        guard let uri else {
            guard (1...50).contains(posicao) else { return .recusou }
            for _ in 0..<posicao { if let e = erro(chamar("POST", "/me/player/next")) { return e } }
            return nil
        }
        let rt = "pular"
        registrar("spotify: \(rt) pedido posicao=\(posicao) uri=\(uri)")
        func fim(_ e: ErroSpotify?) -> ErroSpotify? {
            registrar("spotify: \(rt) resultado para o painel: \(e.map { "erro '\($0.texto)'" } ?? "ok")")
            return e
        }
        let lida = fila(limite: 50, rastro: rt, fresca: true)
        guard case .success(let f) = lida else {
            // Com o Spotify pedindo espera, a fila não mudou: o aviso certo é o de esperar.
            if case .failure(let e) = lida, e == .esperar { return fim(e) }
            return fim(ErroSpotify(texto: "A fila mudou. Abra a fila de novo."))
        }
        // A mesma música pode aparecer mais de uma vez: fica com a cópia mais perto da vez que a tela mandou.
        let achadas = f.proximas.indices.filter { f.proximas[$0].uri == uri }
        registrar("spotify: \(rt) fila tem \(f.proximas.count) próximas, uri achada nos índices \(achadas), primeira da fila=\(f.proximas.first?.uri ?? "-")")
        guard let i = achadas.min(by: { abs($0 + 1 - posicao) < abs($1 + 1 - posicao) }) else {
            return fim(ErroSpotify(texto: "A fila mudou. Abra a fila de novo."))
        }
        guard (1...50).contains(i + 1) else { return fim(.recusou) }
        let depois = f.proximas[i...].compactMap { $0.uri }
        let contexto = contextoQueToca(rastro: rt)
        registrar("spotify: \(rt) índice=\(i) (vez \(i + 1)), contexto que toca=\(contexto ?? "nenhum"), uris do fallback=\(depois.count)")
        if let contexto, ["playlist", "album"].contains(contexto.split(separator: ":").dropFirst().first.map(String.init) ?? "") {
            let r = chamar("PUT", "/me/player/play", json: ["context_uri": contexto, "offset": ["uri": uri]], rastro: rt)
            if case .success = r {
                let ok = tocaAgora(uri, rastro: rt)
                registrar("spotify: \(rt) play com contexto aceito, tocaAgora=\(ok)")
                if ok { return fim(nil) }
            }
        } else {
            registrar("spotify: \(rt) contexto não é playlist nem álbum, vai direto no play de uris")
        }
        let r = chamar("PUT", "/me/player/play", json: ["uris": depois], rastro: rt)
        if case .success = r {
            // só para o log: o play de uris foi aceito, mas o Spotify trocou mesmo? (não muda o resultado)
            if esperaDoPulo > 0 { Thread.sleep(forTimeInterval: esperaDoPulo) }
            if case .success(let j) = jogador(rastro: rt) {
                registrar("spotify: \(rt) depois do play de uris, toca=\(j.uri ?? "-") (pedida \(uri)) trocou=\(j.uri == uri)")
            }
        }
        return fim(erro(r))
    }

    private func contextoQueToca(rastro: String? = nil) -> String? {
        guard case .success(let r) = chamar("GET", "/me/player", rastro: rastro) else { return nil }
        return ((json(r) as? [String: Any])?["context"] as? [String: Any])?["uri"] as? String
    }

    /// O Spotify às vezes aceita o `play` com um offset que não é da lista e toca outra coisa. Confere o que tocou.
    private func tocaAgora(_ uri: String, rastro: String? = nil, ate continuar: () -> Bool = { true }) -> Bool {
        for tentativa in 0..<3 {
            guard continuar() else { return true }
            if case .success(let j) = jogador(rastro: rastro) {
                if j.uri == uri { return true }
                registrar("spotify: \(rastro ?? "tocaAgora") tentativa \(tentativa + 1): toca \(j.uri ?? "-"), esperava \(uri)")
            }
            if tentativa < 2 && esperaDoPulo > 0 { Thread.sleep(forTimeInterval: esperaDoPulo) }
        }
        return false
    }

    /// O que tocou por último, mais recente primeiro. Pede a permissão de histórico, que logins antigos não têm.
    /// Fica guardado por `validadeDosRecentes`, e com o Spotify pedindo espera devolve o que já tinha (mesmo velho).
    func recentes(limite: Int = 20) -> Result<RecentesSpotify, ErroSpotify> {
        travaLimite.lock(); let guardado = recentesGuardados; travaLimite.unlock()
        if let g = guardado, g.limite == limite, agora().timeIntervalSince(g.em) < Self.validadeDosRecentes { return .success(g.itens) }
        let r = chamar("GET", "/me/player/recently-played", [("limit", String(limite))], rastro: "recentes").map { r in
            let itens = ((json(r) as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            return RecentesSpotify(itens: itens.compactMap { Self.itemDaFila($0["track"]) })
        }
        switch r {
        case .success(let novo):
            travaLimite.lock(); recentesGuardados = (novo, limite, agora()); travaLimite.unlock()
        case .failure(let e):
            if e == .esperar, let g = guardado, g.limite == limite { return .success(g.itens) }
        }
        return r
    }

    /// "faixa" repete só a música, "nao" desliga, "contexto" repete o álbum ou a lista.
    func repetir(_ modo: String) -> ErroSpotify? {
        guard let estado = ["faixa": "track", "nao": "off", "contexto": "context"][modo] else { return .recusou }
        return erro(chamar("PUT", "/me/player/repeat", [("state", estado)]))
    }

    func jogador(rastro: String? = nil) -> Result<JogadorSpotify, ErroSpotify> {
        chamar("GET", "/me/player", rastro: rastro).map { r in
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
