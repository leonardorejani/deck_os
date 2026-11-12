import Foundation

// Contrato do núcleo: o formato do config.json e das respostas da API. O painel (iPhone) e o app
// do Mac só conversam por estes tipos. Mudou aqui, muda `prototipo/dados.js` e o painel junto.

// MARK: - Config (~/Library/Application Support/Deck/config.json)

/// Tipos de tecla: "app" (abre ou traz para frente), "tecla" (combinação de teclado),
/// "comando" (linha de zsh) e "atalho" (Atalhos da Apple, `shortcuts run`).
struct Tecla: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var tipo: String
    /// Nome do app, combinação ("ctrl+opt+cmd+k"), comando de shell ou nome do Atalho.
    var valor: String
    /// Comando de shell opcional: saída 0 = tecla acesa (ex.: o Manter acordado).
    var estado: String?
    /// Nome de um app ("Spotify") ou "svg:<nome>" de um ícone do painel.
    var icone: String?
    /// Só no tipo "app": abre o app numa coisa específica (a caixa de entrada de uma conta do Mail, um
    /// endereço no navegador...). Sem ele a tecla só abre o app. O catálogo vem de GET /api/apps/<bundle>/acoes.
    var acao: AcaoDeApp? = nil
}

/// O que a tecla de app faz além de abrir o app. `id` é o da ação no catálogo do Mac (AcoesDeApp.swift) e
/// `valor` é a escolha da pessoa (id da conta, endereço, pasta), vazio nas ações sem escolha.
struct AcaoDeApp: Codable, Equatable, Sendable {
    var id: String
    var valor: String?
}

struct Perfil: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var teclas: [Tecla]
}

/// Conta de IA cujo uso semanal aparece no painel.
struct ContaIA: Codable, Equatable, Sendable {
    var id: String
    /// "Claude" ou "Codex".
    var nome: String
    /// Rótulo da conta no painel ("leo", "equipe", "pro").
    var conta: String
    /// Perfil da troca de contas do Claude (`~/.config/claude-account`), quando houver.
    var perfil: String?
    /// false esconde a conta no iPhone ("No iPhone" desligado no Mac).
    var mostrar: Bool?
}

struct Blocos: Codable, Equatable, Sendable {
    var spotify = true
    var agenda = true
    var whatsapp = true
    var sessoes = true
    var uso = true
}

/// De onde o Deck lê as não lidas do WhatsApp.
struct ConfigWhatsApp: Codable, Equatable, Sendable {
    /// "auto" (o Deck descobre), "app" (banco do WhatsApp do Mac) ou "web" (aba do WhatsApp Web).
    var origem = "auto"
    /// Navegador do WhatsApp Web: "Safari", "Google Chrome", "Arc", "Brave Browser" ou "Microsoft Edge".
    /// nil: o Deck acha a aba aberta e, sem aba, abre o WhatsApp Web no navegador padrão do Mac.
    var navegador: String?
}

struct Config: Codable, Equatable, Sendable {
    static let versaoAtual = 1
    var versao = Config.versaoAtual
    var perfis: [Perfil]
    var perfilAtivo: String
    /// Composição do painel: "a" (relógio em cima) ou "b" (deck ao lado).
    var comp = "a"
    var contas: [ContaIA] = []
    var blocos = Blocos()
    var whatsapp = ConfigWhatsApp()
    var nomeMac: String
    var porta = 4777
    /// Código longo da API (20 letras). Sem ele nada é lido nem executado. Troca sozinho a cada 24 h
    /// (Rodizio.swift), sem o iPhone precisar parear de novo.
    var codigoAcesso: String
    /// Quando o codigoAcesso atual foi criado, em segundos desde 1970. Config antiga sem o campo
    /// vira "agora" na primeira leitura e é regravada.
    var codigoCriadoEm = Int(Date().timeIntervalSince1970)
    /// O código que valia antes da última troca, aceito só até `anteriorValeAte` (folga de 10 min
    /// para o iPhone pegar o novo). Nunca sai pela API.
    var codigoAnterior: String?
    /// Fim da folga do codigoAnterior, em segundos desde 1970.
    var anteriorValeAte: Int?
    /// Onde "Novo compromisso" da agenda salva quando a pessoa não escolhe (um calendário ou uma lista dos Lembretes).
    /// Nil: pergunta toda vez.
    var agendaPadrao: DestinoAgenda? = nil
}

// MARK: - Estado (GET /api/estado, pedido pelo painel a cada 1 s)

/// Uma fonte que falhou não derruba o estado: o campo dela vem nil e o motivo vai em `avisos`.
struct Aviso: Codable, Equatable, Sendable {
    /// "spotify", "agenda", "whatsapp", "uso", "sessoes", "teclas".
    var fonte: String
    var texto: String
}

struct EstadoSpotify: Codable, Equatable, Sendable {
    var tocando: Bool
    var faixa: String
    var artista: String
    /// Segundos.
    var posicao: Double
    var duracao: Double
    /// Muda quando a capa muda. A imagem vem de GET /api/capa.
    var capaId: String?
    /// Duas cores dominantes da capa, "#rrggbb".
    var cores: [String]
    /// Álbum da faixa. Opcional: ausente em Mac de versão antiga.
    var album: String? = nil
    /// `repeating` do Spotify: repete a lista ou o álbum. O AppleScript não tem "repetir só a música".
    var repetir: Bool? = nil
    /// `shuffling` do Spotify.
    var aleatorio: Bool? = nil
    /// Volume do Spotify no Mac (0 a 100). Ausente quando o AppleScript não respondeu com ele.
    var volume: Int? = nil
    /// Volume de saída do Mac (0 a 100). Ausente quando a saída não tem controle de volume (HDMI, por exemplo).
    var volumeMac: Int? = nil
    /// true quando o Spotify está conectado nos Ajustes do Mac. Sem isso o painel esconde aparelhos, curtir, fila e repetir a música.
    var conectado: Bool? = nil
    /// Só com login: a faixa está nas curtidas.
    var curtida: Bool? = nil
    /// Só com login: repetir só a música está ligado (o `repetir` acima é o AppleScript, que só vê a lista).
    var repetirFaixa: Bool? = nil
    /// Só com login: nome do aparelho onde o Spotify toca agora.
    var aparelho: String? = nil
}

struct UsoConta: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var conta: String
    /// Percentual da semana, nil sem medição recente.
    var semana: Int?
    /// Quando renova, ISO 8601.
    var renova: String?
}

struct Sessao: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var projeto: String
    var pergunta: String
    /// Desde quando espera, ISO 8601.
    var desde: String
}

struct ResumoWhatsApp: Codable, Equatable, Sendable {
    var total: Int
    var conversas: Int
    /// De onde o total veio: "app" (banco do WhatsApp do Mac) ou "web" (título da aba do WhatsApp Web).
    /// Ausente em Mac antigo: o painel trata como "app". Em "web" não há lista por conversa.
    var origem: String?
    /// Navegador da aba do WhatsApp Web, quando a origem é "web" e há aba.
    var navegador: String?
    /// Só na origem "web": false quando não há aba do WhatsApp Web aberta (o total 0 não é medição).
    var aberto: Bool?
}

struct Evento: Codable, Equatable, Sendable {
    var titulo: String
    /// ISO 8601. Em evento de dia todo, meia-noite do dia.
    var inicio: String
    var diaTodo: Bool
    var calendario: String
    /// "#rrggbb" do calendário.
    var cor: String
    var local: String?
    /// Link de reunião de vídeo (Meet, Zoom ou Teams) achado no evento. Ausente em Mac antigo e em evento sem reunião:
    /// o painel só mostra "Entrar na reunião" quando ele vem.
    var link: String? = nil
}

struct ResumoAgenda: Codable, Equatable, Sendable {
    /// false: o macOS recusou o Calendário (a tecla mostra "!").
    var permissao: Bool
    var proximo: Evento?
}

struct Estado: Codable, Equatable, Sendable {
    var agora: String
    var nomeMac: String
    var perfilAtivo: String
    var comp: String
    var blocos: Blocos
    var spotify: EstadoSpotify?
    var uso: [UsoConta]
    var sessoes: [Sessao]
    var whatsapp: ResumoWhatsApp?
    var agenda: ResumoAgenda?
    /// Ids das teclas acesas no perfil ativo.
    var acesas: [String]
    /// Selo por id de tecla (não lidas do WhatsApp, "!" da agenda sem permissão).
    var selos: [String: String]
    var avisos: [Aviso]
}

// MARK: - Painéis

struct MensagemWhatsApp: Codable, Equatable, Sendable {
    /// Quem mandou, em grupo. Vazio em conversa direta.
    var de: String
    var texto: String
    var hora: String
}

struct ConversaWhatsApp: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var grupo: Bool
    var naoLidas: Int
    /// Hora da última mensagem, ISO 8601.
    var ultima: String
    var mensagens: [MensagemWhatsApp]
}

// MARK: - Rotas (todas exigem o código de acesso, menos os arquivos da página e /api/parear)
//
// GET  /api/estado                 -> Estado
// GET  /api/config                 -> Config sem o codigoAcesso
// PUT  /api/config                 <- Config (modo organizar do iPhone), valida antes de gravar
// POST /api/botao/<id>             executa a tecla do perfil ativo -> {"ok": true} ou 4xx com {"erro"}
// POST /api/spotify/<acao>         tocar | pausar | anterior | proxima | posicao?s=<segundos>
//                                  | repetir[?v=1|0] | aleatorio[?v=1|0]  (sem v, alterna)
// POST /api/spotify/volume?v=0..100[&alvo=spotify|mac|aparelho]   volume do Spotify (padrão), da saída do Mac ou do aparelho ativo
// GET  /api/spotify/dispositivos   -> [DispositivoSpotify]   (só com Spotify conectado, senão 409)
// POST /api/spotify/dispositivo?id=<id>   passa a reprodução para o aparelho (só conectado)
// POST /api/spotify/curtir?v=1|0   curte ou descurte a faixa que toca (só conectado)
// GET  /api/spotify/fila           -> FilaSpotify (só conectado)
// POST /api/spotify/repetir?modo=faixa|nao|contexto   repetir só a música, nada ou a lista pela API (só conectado, senão 409).
//                                  Sem `modo`, `repetir[?v=1|0]` segue sendo o do AppleScript acima.
// GET  /api/capa                   PNG ou JPEG da capa atual
// GET  /api/whatsapp               -> [ConversaWhatsApp] (vazia quando Estado.whatsapp.origem é "web": o navegador só dá o total)
// GET  /api/agenda?de=AAAA-MM-DD&dias=N -> [Evento]
// GET  /api/sessoes                -> [Sessao]
// POST /api/sessoes/<id>/abrir     traz para a frente o terminal da sessão no Mac -> SessaoAberta {"ok", "como": "terminal"|"pasta", "app"}
// POST /api/reuniao/entrar         <- {"link": "https://..."} abre a reunião no Mac (Meet e Teams no navegador padrão, Zoom no app se houver). Só Meet, Zoom e Teams, senão 400.
// POST /api/parear                 <- {"codigo": "<6 dígitos mostrados no Mac>"} -> {"codigoAcesso"}
// GET  /ca.crt                     o certificado do CA do Deck (application/x-x509-ca-cert), sem código de acesso
// GET  /<arquivo>                  a página do painel
//
// Código de acesso: cabeçalho `X-Deck-Codigo` ou `?codigo=`. Erro sempre em {"erro": "<texto
// em português para mostrar no iPhone>"}.
//
// Rodízio do código: ele troca sozinho a cada 24 h e o anterior vale mais 10 min. Toda resposta
// autenticada (qualquer status, 200 ou 4xx) leva o cabeçalho `X-Deck-Codigo-Novo` com o código
// atual quando o pedido veio com o código anterior, ou seja, logo depois da troca. O iPhone então
// troca o que guarda por esse valor e passa a mandá-lo em `X-Deck-Codigo`. Sem o cabeçalho o código
// que ele tem segue valendo. Código fora da validade: 401, e só pareando de novo.

// MARK: - Shell

struct SaidaShell: Equatable, Sendable {
    var status: Int32
    var saida: String
}

/// Tudo que roda comando passa por aqui, para os testes trocarem por um falso.
protocol Executor: Sendable {
    func rodar(_ comando: String) -> SaidaShell
}

struct ExecutorShell: Executor {
    func rodar(_ comando: String) -> SaidaShell {
        let p = Process()
        #if os(macOS)
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        #else
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        #endif
        p.arguments = ["-c", comando]
        let cano = Pipe()
        p.standardOutput = cano
        p.standardError = cano
        do { try p.run() } catch { return SaidaShell(status: -1, saida: "\(error)") }
        let dados = cano.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return SaidaShell(status: p.terminationStatus, saida: String(decoding: dados, as: UTF8.self))
    }
}
