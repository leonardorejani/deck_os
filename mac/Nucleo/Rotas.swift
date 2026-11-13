import Foundation

// O roteador não sabe de rede: recebe uma HttpRequisicao e devolve uma RespostaRota. Assim o mesmo
// código atende o HTTPS agora e o cabo e o Bluetooth depois. Tudo que não é dele (fontes de dados,
// ações no Mac, config em disco) entra por protocolo e nos testes é trocado por falso.

struct RespostaRota: Equatable, Sendable {
    var status: Int
    var tipo: String
    var corpo: Data
    var extras: [String: String] = [:]

    func serializar() -> Data { Http.resposta(status: status, tipo: tipo, corpo: corpo, extras: extras) }

    /// A API nunca é guardada em cache: o painel pede o estado a cada segundo e não pode ver dado velho.
    static func json(_ status: Int, _ valor: Data, extras: [String: String] = [:]) -> RespostaRota {
        var e = extras
        e["Cache-Control"] = "no-store"
        return RespostaRota(status: status, tipo: "application/json; charset=utf-8", corpo: valor, extras: e)
    }

    static func codificar<T: Encodable>(_ status: Int, _ valor: T) -> RespostaRota {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let dados = try? enc.encode(valor) else {
            return erro(500, "Não consegui montar a resposta.")
        }
        return json(status, dados)
    }

    static func erro(_ status: Int, _ texto: String, extras: [String: String] = [:]) -> RespostaRota {
        let corpo = (try? JSONSerialization.data(withJSONObject: ["erro": texto], options: [])) ?? Data("{}".utf8)
        return json(status, corpo, extras: extras)
    }
}

/// O corpo de GET /api/apps/<bundle>/acoes.
struct AcoesDoApp: Codable, Equatable, Sendable {
    var bundle: String
    var acoes: [AcaoDisponivel]
}

/// O corpo de POST /api/agenda/criar quando deu certo.
struct CompromissoCriado: Codable, Equatable, Sendable {
    var ok: Bool
    /// true se o destino foi guardado como padrão.
    var padraoSalvo: Bool
}

// MARK: - O que o servidor pede para as outras frentes

struct CapaAtual: Equatable, Sendable {
    /// "image/png" ou "image/jpeg".
    var tipo: String
    var dados: Data
}

protocol ProvedorPaineis: Sendable {
    func estado() -> Estado
    func whatsapp() -> [ConversaWhatsApp]
    /// Muda a cada lista nova do WhatsApp por QR. nil: a lista não tem versão (banco do app, Web), então vai sempre inteira.
    func versaoWhatsApp() -> Int?
    /// A foto de perfil de uma conversa do WhatsApp por QR (nil: sem foto).
    func fotoWhatsApp(arquivo: String) -> MidiaBaixada?
    /// A foto ou o áudio de uma mensagem do WhatsApp por QR, baixado agora (só leitura, com limite de tamanho).
    func midiaWhatsApp(chat: String, id: String) -> ResultadoMidia
    /// "Responder no Mac": abre a conversa no WhatsApp Web.
    func abrirConversaWhatsApp(id: String) -> AberturaDeConversa
    func agenda(de: String, dias: Int) -> [Evento]
    func sessoes() -> [Sessao]
    func capa() -> CapaAtual?
}

extension ProvedorPaineis {
    func versaoWhatsApp() -> Int? { nil }
    func fotoWhatsApp(arquivo: String) -> MidiaBaixada? { nil }
    func midiaWhatsApp(chat: String, id: String) -> ResultadoMidia { .erro("Essa mídia não abre aqui.") }
    func abrirConversaWhatsApp(id: String) -> AberturaDeConversa { .falhou("Não consegui abrir a conversa.") }
}

protocol ExecutorTeclas: Sendable {
    /// Executa a tecla. Devolve o erro em texto para mostrar no iPhone, ou nil se deu certo.
    func executar(_ tecla: Tecla) -> String?
}

/// De quem é o volume que o iPhone mexe.
enum AlvoVolume: String, Sendable {
    /// O volume do player do Spotify no Mac (AppleScript). É o padrão e funciona sem login.
    case spotify
    /// O volume de saída do Mac (o da barra de menus do sistema).
    case mac
    /// O aparelho do Spotify Connect que está tocando (alto-falante, TV). Pede login e Premium.
    case aparelho
}

protocol ControleSpotify: Sendable {
    /// "tocar", "pausar", "anterior" ou "proxima". Erro em texto, ou nil se deu certo.
    func acao(_ nome: String) -> String?
    func posicao(_ segundos: Double) -> String?
    /// "repetir" ou "aleatorio". `ligado` nil alterna, senão liga ou desliga. Erro em texto, ou nil se deu certo.
    func definir(_ nome: String, ligado: Bool?) -> String?
    /// De 0 a 100. Erro em texto, ou nil se deu certo.
    func volume(_ alvo: AlvoVolume, _ valor: Int) -> ErroSpotify?
    // O que só existe com o Spotify conectado nos Ajustes do Mac (login pela API do Spotify).
    func dispositivos() -> Result<[DispositivoSpotify], ErroSpotify>
    func transferir(para id: String) -> ErroSpotify?
    func curtir(_ curtir: Bool) -> ErroSpotify?
    func fila() -> Result<FilaSpotify, ErroSpotify>
    /// "faixa" (repetir só a música), "nao" ou "contexto". Pela API, por isso só com login.
    func repetirModo(_ modo: String) -> ErroSpotify?
}

extension ControleSpotify {
    func volume(_ alvo: AlvoVolume, _ valor: Int) -> ErroSpotify? { ErroSpotify(texto: "O volume não está disponível.") }
    func dispositivos() -> Result<[DispositivoSpotify], ErroSpotify> { .failure(.naoConectado) }
    func transferir(para id: String) -> ErroSpotify? { .naoConectado }
    func curtir(_ curtir: Bool) -> ErroSpotify? { .naoConectado }
    func fila() -> Result<FilaSpotify, ErroSpotify> { .failure(.naoConectado) }
    func repetirModo(_ modo: String) -> ErroSpotify? { .naoConectado }
}

protocol ArmazemDeConfig: Sendable {
    func ler() -> Config
    /// Valida e grava a config nova. Devolve o erro em texto (nada é gravado), ou nil se gravou.
    func aplicar(_ nova: Config) -> String?
}

// MARK: - Autenticação

enum Autenticacao {
    static func codigoDaRequisicao(_ r: HttpRequisicao) -> String? {
        r.cabecalhos["x-deck-codigo"] ?? r.query["codigo"]
    }

    static func autorizado(_ r: HttpRequisicao, esperado: String) -> Bool {
        guard !esperado.isEmpty, let recebido = codigoDaRequisicao(r) else { return false }
        return igual(recebido, esperado)
    }

    /// Compara sem parar no primeiro byte diferente, para o tempo de resposta não revelar o código.
    static func igual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            diff |= Int(p ^ q)
        }
        return diff == 0
    }
}

// MARK: - Roteador

struct Roteador: Sendable {
    let paineis: ProvedorPaineis
    let teclas: ExecutorTeclas
    let spotify: ControleSpotify
    let config: ArmazemDeConfig
    let pareamento: Pareamento
    let pagina: ArquivosPagina
    /// Rodízio do código de acesso. O app do Mac e o roteador precisam compartilhar o mesmo, por causa da trava.
    var rodizio = Rodizio()
    /// O ca.crt público do Deck, que o iPhone instala para confiar no HTTPS do Mac. Nil = rota sem arquivo (404).
    var certificadoCA: URL? = nil
    /// "Entrar na reunião" da agenda. Nil: a rota /api/reuniao/entrar não existe (404).
    var reunioes: (any ProvedorDeReuniao)? = nil
    /// Criar compromisso na agenda (Calendário e Lembretes). Nil: as rotas /api/agenda/destinos e /api/agenda/criar não existem (404).
    var criadorDeAgenda: (any CriadorDeAgenda)? = nil
    /// "Abrir no Mac" das sessões. Nil: a rota /api/sessoes/<id>/abrir não existe (404).
    var abridorDeSessao: (any AbridorDeSessao)? = nil
    /// Os apps do Mac de quem usa (lista, ícone e ações de tecla). Nil: as rotas /api/apps não existem (404).
    var apps: (any ProvedorDeApps)? = nil
    /// Volume, brilho da tela e da luz do teclado do Mac. Nil: as rotas /api/controles não existem (404).
    var controles: (any ControlesDoMac)? = nil
    /// Os processos que mais usam processador e memória, e o encerrar (tela do Monitor de Atividade). Nil: as rotas /api/processos não existem (404).
    var processos: (any ProcessosDoMac)? = nil

    func responder(_ r: HttpRequisicao) -> RespostaRota {
        if r.caminho == "/api/parear" {
            if r.metodo != "POST" { return naoPermitido(["POST"]) }
            return parear(r)
        }
        if r.caminho == "/ca.crt" {
            if r.metodo != "GET" { return naoPermitido(["GET"]) }
            return certificado()
        }
        if r.caminho == "/api" || r.caminho.hasPrefix("/api/") {
            // Antes de qualquer outra checagem: quem não tem o código não descobre nem quais rotas existem.
            let entrada = rodizio.autenticar(Autenticacao.codigoDaRequisicao(r), em: config)
            guard entrada.via != .invalido else {
                return .erro(401, "Código de acesso ausente ou incorreto. Pareie o celular de novo pelo Mac.")
            }
            var resposta = api(r, entrada.config)
            // Veio com o código anterior (folga): entrega o atual para o iPhone trocar sem parear de novo.
            if entrada.via == .anterior { resposta.extras[Rodizio.cabecalhoNovo] = entrada.config.codigoAcesso }
            return resposta
        }
        if r.metodo != "GET" { return naoPermitido(["GET"]) }
        return pagina.responder(r.caminho)
    }

    // MARK: Certificado

    /// Só o ca.crt (público por natureza, sem a chave): o iPhone ainda não confia no Deck quando o baixa,
    /// então não dá para pedir o código de acesso aqui.
    private func certificado() -> RespostaRota {
        guard let url = certificadoCA, let dados = try? Data(contentsOf: url), !dados.isEmpty else {
            return .erro(404, "O certificado do Deck ainda não foi criado neste Mac.")
        }
        return RespostaRota(status: 200, tipo: "application/x-x509-ca-cert", corpo: dados,
                            extras: ["Cache-Control": "no-cache", "Content-Disposition": "attachment; filename=\"Deck.crt\""])
    }

    // MARK: API

    private func api(_ r: HttpRequisicao, _ atual: Config) -> RespostaRota {
        switch r.caminho {
        case "/api/estado":
            return somente(["GET"], r) ?? .codificar(200, paineis.estado())
        case "/api/config":
            switch r.metodo {
            case "GET": return configSemCodigo(atual)
            case "PUT": return gravarConfig(r, atual)
            default: return naoPermitido(["GET", "PUT"])
            }
        case "/api/capa":
            if let e = somente(["GET"], r) { return e }
            guard let capa = paineis.capa() else { return .erro(404, "Nenhuma capa tocando agora.") }
            return RespostaRota(status: 200, tipo: capa.tipo, corpo: capa.dados, extras: ["Cache-Control": "no-store"])
        case "/api/whatsapp":
            return somente(["GET"], r) ?? listaDoWhatsApp(r)
        case "/api/whatsapp/midia":
            return somente(["GET"], r) ?? midiaDoWhatsApp(r)
        case "/api/whatsapp/abrir":
            return somente(["POST"], r) ?? abrirConversaDoWhatsApp(r)
        case "/api/sessoes":
            return somente(["GET"], r) ?? .codificar(200, paineis.sessoes())
        case "/api/agenda":
            return somente(["GET"], r) ?? agenda(r)
        default:
            break
        }
        if let arquivo = sufixo(r.caminho, "/api/whatsapp/foto/") {
            return somente(["GET"], r) ?? fotoDoWhatsApp(arquivo)
        }
        if let id = sufixo(r.caminho, "/api/botao/") {
            return somente(["POST"], r) ?? botao(id, atual)
        }
        if r.caminho == "/api/agenda/destinos" {
            return somente(["GET"], r) ?? destinosDaAgenda(r)
        }
        if r.caminho == "/api/agenda/criar" {
            return somente(["POST"], r) ?? criarNaAgenda(r)
        }
        if r.caminho == "/api/reuniao/entrar" {
            return somente(["POST"], r) ?? entrarNaReuniao(r)
        }
        if r.caminho.hasPrefix("/api/sessoes/"), r.caminho.hasSuffix("/abrir") {
            let id = String(r.caminho.dropFirst("/api/sessoes/".count).dropLast("/abrir".count))
            return somente(["POST"], r) ?? abrirSessao(id)
        }
        if r.caminho == "/api/apps" || r.caminho.hasPrefix("/api/apps/") {
            return somente(["GET"], r) ?? rotaDeApps(r)
        }
        if r.caminho == "/api/controles" {
            // O que a pessoa desligou na tecla Controles do Mac não sai daqui: a barra some no iPhone, como a que o Mac não oferece.
            return somente(["GET"], r) ?? controles.map { .codificar(200, $0.estado().somente(config.ler().controles)) } ?? .erro(404, "Essa rota não existe.")
        }
        if r.caminho == "/api/processos" {
            return somente(["GET"], r) ?? processos.map { .codificar(200, $0.maiores()) } ?? .erro(404, "Essa rota não existe.")
        }
        if r.caminho.hasPrefix("/api/processos/"), r.caminho.hasSuffix("/encerrar") {
            let pid = String(r.caminho.dropFirst("/api/processos/".count).dropLast("/encerrar".count))
            return somente(["POST"], r) ?? encerrarProcesso(pid, r)
        }
        if let item = sufixo(r.caminho, "/api/controles/") {
            return somente(["POST"], r) ?? controlar(item, r)
        }
        if let acao = sufixo(r.caminho, "/api/spotify/") {
            if acao == "dispositivos" { return somente(["GET"], r) ?? respostaSpotify(spotify.dispositivos()) }
            if acao == "fila" { return somente(["GET"], r) ?? respostaSpotify(spotify.fila()) }
            return somente(["POST"], r) ?? controlarSpotify(acao, r)
        }
        return .erro(404, "Essa rota não existe.")
    }

    private func sufixo(_ caminho: String, _ prefixo: String) -> String? {
        guard caminho.hasPrefix(prefixo), caminho.count > prefixo.count else { return nil }
        return String(caminho.dropFirst(prefixo.count))
    }

    private func somente(_ metodos: [String], _ r: HttpRequisicao) -> RespostaRota? {
        metodos.contains(r.metodo) ? nil : naoPermitido(metodos)
    }

    private func naoPermitido(_ metodos: [String]) -> RespostaRota {
        .erro(405, "Esse pedido não é aceito nessa rota.", extras: ["Allow": metodos.joined(separator: ", ")])
    }

    // MARK: Rotas

    private func botao(_ id: String, _ atual: Config) -> RespostaRota {
        let perfil = atual.perfis.first { $0.id == atual.perfilAtivo }
        guard let tecla = perfil?.teclas.first(where: { $0.id == id }) else {
            return .erro(404, "Essa tecla não existe no perfil atual.")
        }
        if let erro = teclas.executar(tecla) { return .erro(422, erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }

    private func entrarNaReuniao(_ r: HttpRequisicao) -> RespostaRota {
        guard let reunioes else { return .erro(404, "Essa rota não existe.") }
        guard let obj = (try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any], let link = obj["link"] as? String,
              Reuniao.validar(link) != nil else {
            return .erro(400, "Esse link não é de uma reunião do Meet, do Zoom ou do Teams.")
        }
        if let erro = reunioes.entrar(link) { return .erro(422, erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }


    /// GET /api/whatsapp: a lista inteira, como sempre. Com `?v=<versão>` (o iPhone manda a que já tem) o Mac responde
    /// {"v", "conversas"} e, se nada mudou, só {"v", "igual": true}. Pelo Bluetooth (uns 25 KB/s) reenviar a lista a cada
    /// segundo entupia o canal e estourava o tempo do pedido. Sem versão no Mac (banco do app, Web), vai a lista de sempre.
    private func listaDoWhatsApp(_ r: HttpRequisicao) -> RespostaRota {
        guard r.query["v"] != nil, let versao = paineis.versaoWhatsApp() else { return .codificar(200, paineis.whatsapp()) }
        if r.query["v"] == String(versao) { return .codificar(200, ListaComVersao(v: versao, igual: true)) }
        return .codificar(200, ListaComVersao(v: versao, conversas: paineis.whatsapp()))
    }

    private struct ListaComVersao: Encodable { var v: Int; var conversas: [ConversaWhatsApp]? = nil; var igual: Bool? = nil }

    /// GET /api/whatsapp/foto/<arquivo>: a foto de perfil, em base64 (a mesma forma serve ao Wi-Fi, ao cabo e ao Bluetooth).
    private func fotoDoWhatsApp(_ arquivo: String) -> RespostaRota {
        guard let f = paineis.fotoWhatsApp(arquivo: arquivo) else { return .erro(404, "Sem foto.") }
        return Self.midia(f)
    }

    /// GET /api/whatsapp/midia?chat=<id>&id=<mensagem>: a foto ou o áudio, baixado agora.
    private func midiaDoWhatsApp(_ r: HttpRequisicao) -> RespostaRota {
        guard let chat = r.query["chat"], let id = r.query["id"], Self.textoSimples(chat, maximo: 200), Self.textoSimples(id, maximo: 200) else {
            return .erro(400, "Informe a conversa e a mensagem, por exemplo ?chat=<id>&id=<mensagem>.")
        }
        switch paineis.midiaWhatsApp(chat: chat, id: id) {
        case .pronta(let m): return Self.midia(m)
        case .erro(let e): return .erro(422, e)
        }
    }

    private static func midia(_ m: MidiaBaixada) -> RespostaRota {
        .codificar(200, ["tipo": m.tipo, "dados": m.dados.base64EncodedString()])
    }

    /// POST /api/whatsapp/abrir, corpo {"id": "<conversa>"}: abre a conversa no WhatsApp Web do Mac. Não envia nem marca nada.
    private func abrirConversaDoWhatsApp(_ r: HttpRequisicao) -> RespostaRota {
        guard let obj = (try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any], let id = obj["id"] as? String,
              Self.textoSimples(id, maximo: 200) else {
            return .erro(400, "Informe a conversa a abrir, por exemplo {\"id\": \"<conversa>\"}.")
        }
        switch paineis.abrirConversaWhatsApp(id: id) {
        case .aberta(let aviso):
            var corpo: [String: Any] = ["ok": true]
            if let aviso { corpo["aviso"] = aviso }
            return .json(200, (try? JSONSerialization.data(withJSONObject: corpo)) ?? Data("{\"ok\":true}".utf8))
        case .falhou(let e): return .erro(422, e)
        }
    }

    /// Texto sem caractere de controle e sem tamanho absurdo.
    static func textoSimples(_ s: String, maximo: Int) -> Bool {
        !s.isEmpty && s.count <= maximo && !s.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// GET /api/agenda/destinos: onde dá para salvar, o padrão e a permissão de cada app. `?pedir=1` abre no Mac a
    /// janela de acesso aos Lembretes (só quando a pessoa escolheu Lembretes).
    private func destinosDaAgenda(_ r: HttpRequisicao) -> RespostaRota {
        guard let criadorDeAgenda else { return .erro(404, "Essa rota não existe.") }
        var d = criadorDeAgenda.destinos(pedirPermissao: r.query["pedir"] == "1")
        if var p = config.ler().agendaPadrao {
            // "Calendário padrão do Mac" vira o calendário de verdade, que é o que a lista do iPhone sabe mostrar.
            if p.ehPadraoDoMac, let id = criadorDeAgenda.idDoCalendarioPadrao() { p = DestinoAgenda(tipo: "calendario", id: id) }
            // Padrão que sumiu (calendário apagado) não vai para a tela, mas só dá para saber com a lista liberada.
            let existe = p.tipo == "calendario"
                ? d.permissaoCalendario != "liberado" || d.calendarios.contains { $0.id == p.id }
                : d.permissaoLembretes != "liberado" || d.listas.contains { $0.id == p.id }
            d.padrao = existe ? p : nil
        }
        return .codificar(200, d)
    }

    /// POST /api/agenda/criar. Corpo: titulo, dia (AAAA-MM-DD), diaTodo, inicio e fim (HH:MM), destino {tipo, id},
    /// alertaMin e padrao (guardar o destino como padrão).
    private func criarNaAgenda(_ r: HttpRequisicao) -> RespostaRota {
        guard let criadorDeAgenda else { return .erro(404, "Essa rota não existe.") }
        switch NovoCompromisso.ler(corpo: r.corpo, padrao: config.ler().agendaPadrao) {
        case .failure(let e): return .erro(e.status, e.texto)
        case .success(var novo):
            if novo.destino.ehPadraoDoMac {
                guard let id = criadorDeAgenda.idDoCalendarioPadrao() else {
                    return .erro(409, "O Mac não disse qual é o calendário padrão. Libere o Calendário para o Deck ou escolha onde salvar.")
                }
                novo.destino = DestinoAgenda(tipo: "calendario", id: id)
            }
            if case .failure(let e) = criadorDeAgenda.criar(novo) { return .erro(e.status, e.texto) }
            var padraoSalvo = false
            if novo.definirPadrao {
                var c = config.ler()
                c.agendaPadrao = novo.destino
                padraoSalvo = config.aplicar(c) == nil
            }
            return .codificar(200, CompromissoCriado(ok: true, padraoSalvo: padraoSalvo))
        }
    }

    private func abrirSessao(_ id: String) -> RespostaRota {
        guard let abridorDeSessao else { return .erro(404, "Essa rota não existe.") }
        switch abridorDeSessao.abrir(id: id) {
        case .success(let aberta): return .codificar(200, aberta)
        case .failure(let e): return .erro(e.status, e.texto)
        }
    }

    /// GET /api/apps, /api/apps/<bundle>/icone e /api/apps/<bundle>/acoes.
    private func rotaDeApps(_ r: HttpRequisicao) -> RespostaRota {
        guard let apps else { return .erro(404, "Essa rota não existe.") }
        if r.caminho == "/api/apps" { return .codificar(200, apps.apps()) }
        let partes = r.caminho.dropFirst("/api/apps/".count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard partes.count == 2, Self.bundleValido(partes[0]) else { return .erro(404, "Essa rota não existe.") }
        switch partes[1] {
        case "icone":
            guard let png = apps.icone(bundle: partes[0]) else { return .erro(404, "Esse app não tem ícone neste Mac.") }
            // O ícone só muda quando o app é atualizado: o iPhone pode guardar por um dia.
            return RespostaRota(status: 200, tipo: "image/png", corpo: png, extras: ["Cache-Control": "private, max-age=86400"])
        case "acoes":
            guard let acoes = apps.acoes(bundle: partes[0]) else { return .erro(404, "Esse app não está instalado neste Mac.") }
            return .codificar(200, AcoesDoApp(bundle: partes[0], acoes: acoes))
        default:
            return .erro(404, "Essa rota não existe.")
        }
    }

    /// Id de pacote é letra, número, ponto, traço e sublinhado. O resto nem chega a procurar.
    static func bundleValido(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }

    /// POST /api/controles/<volume|brilho|teclado>?v=0..100 e /api/controles/mudo?v=0|1.
    private func controlar(_ item: String, _ r: HttpRequisicao) -> RespostaRota {
        guard let controles, ["volume", "mudo", "brilho", "teclado"].contains(item) else { return .erro(404, "Essa rota não existe.") }
        let erro: String?
        if item == "mudo" {
            guard let v = r.query["v"], ["0", "1"].contains(v) else { return .erro(400, "Informe mudo?v=1 para silenciar ou mudo?v=0 para voltar o som.") }
            erro = controles.definirMudo(v == "1")
        } else {
            guard let texto = r.query["v"], let v = Int(texto), (0...100).contains(v) else {
                return .erro(400, "Informe o valor de 0 a 100, por exemplo \(item)?v=40.")
            }
            switch item {
            case "volume": erro = controles.definirVolume(v)
            case "brilho": erro = controles.definirBrilho(v)
            default: erro = controles.definirTeclado(v)
            }
        }
        if let erro { return .erro(422, erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }

    /// POST /api/processos/<pid>/encerrar?nome=<o nome que a tela mostrava>. O nome evita fechar o programa errado se o pid foi reaproveitado.
    private func encerrarProcesso(_ texto: String, _ r: HttpRequisicao) -> RespostaRota {
        guard let processos else { return .erro(404, "Essa rota não existe.") }
        guard let pid = Int(texto), pid > 1 else { return .erro(400, "Informe o número do processo.") }
        guard let nome = r.query["nome"], !nome.isEmpty, nome.count <= 200 else { return .erro(400, "Informe o nome do processo, por exemplo encerrar?nome=Safari.") }
        if let erro = processos.encerrar(pid: pid, nome: nome) { return .erro(422, erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }

    private func controlarSpotify(_ acao: String, _ r: HttpRequisicao) -> RespostaRota {
        let erro: String?
        switch acao {
        case "tocar", "pausar", "anterior", "proxima":
            erro = spotify.acao(acao)
        case "posicao":
            guard let texto = r.query["s"], let s = Double(texto), s.isFinite, s >= 0 else {
                return .erro(400, "Informe a posição em segundos, por exemplo posicao?s=42.")
            }
            erro = spotify.posicao(s)
        case "volume":
            guard let texto = r.query["v"], let v = Int(texto), (0...100).contains(v) else {
                return .erro(400, "Informe o volume de 0 a 100, por exemplo volume?v=40.")
            }
            guard let alvo = AlvoVolume(rawValue: r.query["alvo"] ?? "spotify") else {
                return .erro(400, "O alvo do volume é spotify, mac ou aparelho.")
            }
            return respostaSpotify(spotify.volume(alvo, v))
        case "dispositivo":
            guard let id = r.query["id"], !id.isEmpty else { return .erro(400, "Informe o aparelho, por exemplo dispositivo?id=<id>.") }
            return respostaSpotify(spotify.transferir(para: id))
        case "curtir":
            guard let v = r.query["v"], ["0", "1"].contains(v) else { return .erro(400, "Informe curtir?v=1 para curtir ou curtir?v=0 para tirar a curtida.") }
            return respostaSpotify(spotify.curtir(v == "1"))
        case "repetir", "aleatorio":
            // Com `modo`, é o repetir da API (só a música, pede login). Sem ele, o do AppleScript, que já existia.
            if acao == "repetir", let modo = r.query["modo"] {
                guard ["faixa", "nao", "contexto"].contains(modo) else {
                    return .erro(400, "Informe o modo: repetir?modo=faixa, nao ou contexto.")
                }
                return respostaSpotify(spotify.repetirModo(modo))
            }
            var ligado: Bool?
            if let v = r.query["v"] {
                switch v {
                case "1", "true": ligado = true
                case "0", "false": ligado = false
                default: return .erro(400, "Informe v=1 para ligar ou v=0 para desligar.")
                }
            }
            erro = spotify.definir(acao, ligado: ligado)
        default:
            return .erro(404, "Essa ação do Spotify não existe.")
        }
        if let erro { return .erro(422, erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }

    /// Sem login no Spotify a resposta é 409 (o painel esconde o que depende dele). Outras falhas, 422 com o texto.
    private func statusDoErro(_ e: ErroSpotify) -> RespostaRota { .erro(e.semLogin ? 409 : 422, e.texto) }

    private func respostaSpotify(_ erro: ErroSpotify?) -> RespostaRota {
        if let erro { return statusDoErro(erro) }
        return .json(200, Data("{\"ok\":true}".utf8))
    }

    private func respostaSpotify<T: Encodable>(_ r: Result<T, ErroSpotify>) -> RespostaRota {
        switch r {
        case .success(let v): return .codificar(200, v)
        case .failure(let e): return statusDoErro(e)
        }
    }

    private func agenda(_ r: HttpRequisicao) -> RespostaRota {
        guard let de = r.query["de"], Self.dataValida(de) else {
            return .erro(400, "Informe a data inicial no formato AAAA-MM-DD, por exemplo de=2026-11-10.")
        }
        var dias = 1
        if let texto = r.query["dias"] {
            guard let n = Int(texto), (1...366).contains(n) else {
                return .erro(400, "Informe quantos dias quer ver, de 1 a 366.")
            }
            dias = n
        }
        return .codificar(200, paineis.agenda(de: de, dias: dias))
    }

    static func dataValida(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let a = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              p.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }), (1...12).contains(m) else { return false }
        let bissexto = (a % 4 == 0 && a % 100 != 0) || a % 400 == 0
        let dias = [31, bissexto ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        return (1...dias).contains(d)
    }

    // MARK: Config

    /// O código de acesso nunca sai pela config: quem lê a config já tem o código, e quem só vê
    /// a tela do iPhone não precisa dele.
    private func configSemCodigo(_ c: Config) -> RespostaRota {
        guard let dados = try? JSONEncoder().encode(c),
              var obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else {
            return .erro(500, "Não consegui ler a configuração.")
        }
        obj.removeValue(forKey: "codigoAcesso")
        obj.removeValue(forKey: "codigoCriadoEm")
        obj.removeValue(forKey: "codigoAnterior")
        obj.removeValue(forKey: "anteriorValeAte")
        guard let saida = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else {
            return .erro(500, "Não consegui ler a configuração.")
        }
        return .json(200, saida)
    }

    /// O iPhone manda a config pública inteira (sem código de acesso nem porta). Corpo parcial é
    /// recusado por Config.receber, e o código e a porta ficam sempre os da config atual.
    private func gravarConfig(_ r: HttpRequisicao, _ atual: Config) -> RespostaRota {
        switch Config.receber(corpo: r.corpo, sobre: config.ler()) {
        case .failure(let e):
            return .erro(400, e.mensagem)
        case .success(let nova):
            if let erro = config.aplicar(nova) { return .erro(400, erro) }
            return configSemCodigo(config.ler())
        }
    }

    // MARK: Pareamento

    private func parear(_ r: HttpRequisicao) -> RespostaRota {
        guard let obj = (try? JSONSerialization.jsonObject(with: r.corpo)) as? [String: Any],
              let codigo = obj["codigo"] as? String else {
            return .erro(400, "Envie o código de 6 dígitos que aparece no Mac.")
        }
        switch pareamento.tentar(codigo.trimmingCharacters(in: .whitespaces)) {
        case .aceito:
            rodizio.gerarSeVencido(em: config)
            return .codificar(200, ["codigoAcesso": config.ler().codigoAcesso])
        case .errado(let restantes):
            let sobra = restantes == 1 ? "Resta 1 tentativa." : "Restam \(restantes) tentativas."
            return restantes == 0
                ? .erro(401, "Código incorreto. Gere um novo no Mac para tentar de novo.")
                : .erro(401, "Código incorreto. \(sobra)")
        case .vencido:
            return .erro(401, "Esse código venceu ou não existe. Gere um novo no Mac.")
        case .bloqueado:
            return .erro(429, "Muitas tentativas erradas. Gere um novo código no Mac.")
        }
    }
}
