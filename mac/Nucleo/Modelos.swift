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
    /// Só no tipo "comando": com ele a tecla vira liga e desliga. `valor` é o comando para ligar e este é o para desligar.
    /// O `estado` (opcional) confere se está ligado (sai 0 = ligado). Sem `estado`, o Deck guarda o último estado que ele mesmo pôs.
    var desligar: String? = nil
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
    /// O monitor do Mac vem ligado de fábrica (SPEC, seção 13, 13/11/2026). A pessoa desliga na tecla do Monitor de Atividade.
    var monitor = true
    /// Se a pessoa mexeu na chave do monitor. Config gravada antes da V1.1.1 trazia `monitor: false` sem ninguém ter escolhido
    /// (era o padrão antigo), então só vale o `false` de quem escolheu.
    var monitorEscolhido = false
}

/// Quais itens o monitor do Mac mostra no iPhone ("não tem mais espaço": quem usa escolhe o que fica na tela).
struct ConfigMonitor: Codable, Equatable, Sendable {
    var cpu = true
    var memoria = true
    var bateria = true
    var rede = true
    /// Itens da tela do Monitor de Atividade no iPhone (12/11/2026). Só aparecem se o Mac souber ler.
    var gpu = true
    var disco = true
    var energia = true
    var ventoinhas = true
    var dispositivos = true
    var algum: Bool { !itens.isEmpty }
    var itens: [String] {
        [cpu ? "cpu" : nil, memoria ? "memoria" : nil, bateria ? "bateria" : nil, rede ? "rede" : nil, gpu ? "gpu" : nil,
         disco ? "disco" : nil, energia ? "energia" : nil, ventoinhas ? "ventoinhas" : nil, dispositivos ? "dispositivos" : nil].compactMap { $0 }
    }
}

/// Quais controles a tela "Controles do Mac" mostra no iPhone (volume, brilho e luz do teclado). Todos ligados de fábrica.
struct ConfigControles: Codable, Equatable, Sendable {
    var volume = true
    var brilho = true
    var teclado = true
    var algum: Bool { volume || brilho || teclado }
}

/// De onde o Deck lê as não lidas do WhatsApp.
struct ConfigWhatsApp: Codable, Equatable, Sendable {
    /// "auto" (o Deck descobre), "app" (banco do WhatsApp do Mac), "web" (aba do WhatsApp Web) ou "qr"
    /// (aparelho conectado por QR, só quando a pessoa liga: não é oficial). O "auto" nunca escolhe "qr".
    var origem = "auto"
    /// Navegador do WhatsApp Web: "Safari", "Google Chrome", "Arc", "Brave Browser" ou "Microsoft Edge".
    /// nil: o Deck acha a aba aberta e, sem aba, abre o WhatsApp Web no navegador padrão do Mac.
    var navegador: String?
    /// A origem que valia antes de ligar o "Conectar pelo QR": desligar a chave volta para ela, em vez de cair em "auto".
    var origemAntes: String?

    /// Liga o QR. Sem o ajudante no app (build sem Go) não liga: a origem "qr" sem ponte tiraria a leitura que já funcionava.
    @discardableResult
    mutating func ligarQR(disponivel: Bool) -> Bool {
        guard disponivel else { return false }
        if origem != "qr" { origemAntes = origem }
        origem = "qr"
        return true
    }

    /// Desliga o QR e devolve a origem de antes (ou "auto", se não havia).
    mutating func desligarQR() {
        origem = origemAntes.flatMap { $0 == "qr" ? nil : $0 } ?? "auto"
        origemAntes = nil
    }
}

struct Config: Codable, Equatable, Sendable {
    static let versaoAtual = 1
    var versao = Config.versaoAtual
    var perfis: [Perfil]
    var perfilAtivo: String
    /// Composição do painel: "a" (relógio em cima), "b" (deck ao lado) ou "c" (relógio e calendário do mês).
    var comp = "a"
    var contas: [ContaIA] = []
    var blocos = Blocos()
    var whatsapp = ConfigWhatsApp()
    /// Itens do monitor do Mac. Só aparece no iPhone com `blocos.monitor` ligado.
    var monitor = ConfigMonitor()
    /// Barras que a tela Controles do Mac mostra no iPhone.
    var controles = ConfigControles()
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
    /// O pedido inteiro da sessão (`needs`), quando é mais que o resumo de `pergunta`. Ausente em Mac antigo.
    var pedido: String? = nil
    /// A última mensagem da sessão antes de parar (o contexto do que ela espera), sem segredos e com limite de
    /// tamanho. Só vem em GET /api/sessoes, nunca no estado. Ausente em Mac antigo.
    var contexto: String? = nil
    /// A resposta que a própria sessão sugere (`suggestedReply`), só para ler. Ausente em Mac antigo.
    var sugestao: String? = nil
}

struct ResumoWhatsApp: Codable, Equatable, Sendable {
    var total: Int
    var conversas: Int
    /// De onde o total veio: "app" (banco do WhatsApp do Mac), "web" (título da aba do WhatsApp Web) ou "qr" (aparelho conectado).
    /// Ausente em Mac antigo: o painel trata como "app". Em "web" não há lista por conversa.
    var origem: String?
    /// Navegador da aba do WhatsApp Web, quando a origem é "web" e há aba.
    var navegador: String?
    /// Só nas origens "web" e "qr": false quando não há aba aberta (web) ou a conexão por QR está caída (o total 0 não é medição).
    var aberto: Bool?
    /// Só na origem "qr": true quando a conexão está subindo ou voltando sozinha (rede que caiu um instante). O painel
    /// não manda ler o QR de novo nesse caso: não precisa.
    var reconectando: Bool?
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
    /// ISO 8601 do fim. Ausente em Mac antigo: o painel trata como evento de um dia só. Vem para o evento de vários dias
    /// (viagem, feriado prolongado) aparecer em todos os dias e meses que cobre.
    var fim: String? = nil
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
    /// Só com o bloco do monitor ligado, e só os itens que a pessoa escolheu nos Ajustes do Mac.
    var monitor: EstadoMonitor? = nil
    /// Por id de tecla de microfone ou de câmera da reunião: ligado, desligado, desconhecido ou sem-reuniao.
    /// Ausente em Mac antigo e quando o perfil não tem tecla dessas: o painel trata como "não sabe" e desenha a tecla de sempre.
    var reuniao: [String: EstadoDeReuniao]? = nil
}

/// Medidas do Mac. Cada uma é nil quando o item está escondido nos Ajustes ou o Mac não tem a medida
/// (bateria num Mac de mesa, por exemplo).
struct EstadoMonitor: Codable, Equatable, Sendable {
    /// Os itens que a pessoa deixou ligados nos Ajustes do Mac ("cpu", "memoria", "bateria", "rede"). É daqui que o painel
    /// sabe o que desenhar, porque medida ausente também quer dizer "ainda sem leitura" ou "Mac sem bateria".
    var itens: [String] = []
    /// Uso do processador, 0 a 100.
    var cpu: Int? = nil
    /// Memória em uso, 0 a 100.
    var memoria: Int? = nil
    /// Carga da bateria, 0 a 100. nil em Mac sem bateria.
    var bateria: Int? = nil
    /// Na tomada (carregando ou cheia). Só vem junto com `bateria`.
    var naTomada: Bool? = nil
    /// Bytes por segundo recebidos e enviados. nil na primeira leitura, porque taxa precisa de duas medidas.
    var baixa: Int? = nil
    var sobe: Int? = nil
    /// Uso da GPU, 0 a 100. nil quando o Mac não informa.
    var gpu: Int? = nil
    /// Espaço livre e total do disco, em bytes.
    var discoLivre: Int? = nil
    var discoTotal: Int? = nil
    /// Consumo do Mac em watts (a carga total do sistema, ou o fluxo da bateria quando só isso estiver disponível). nil em Mac sem a medida.
    var watts: Double? = nil
    /// A bateria está recebendo carga. Só vem junto com `watts`.
    var carregando: Bool? = nil
    /// Rotação de cada ventoinha, em RPM, e a maior rotação possível. nil em Mac sem ventoinha (MacBook Air).
    var ventoinhas: [Int]? = nil
    var ventoinhaMax: Int? = nil
    /// Quantos dispositivos USB estão conectados.
    var dispositivos: Int? = nil
}

// MARK: - Painéis

struct MensagemWhatsApp: Codable, Equatable, Sendable {
    /// Quem mandou, em grupo. Vazio em conversa direta.
    var de: String
    var texto: String
    var hora: String
    /// Só na origem "qr". O id da mensagem (serve para pedir a mídia) e o tipo: "foto", "audio" ou "video". Ausente = texto.
    var id: String? = nil
    var tipo: String? = nil
    /// Visualização única: o painel mostra só o balão com o ícone, e o Mac nunca entrega o conteúdo.
    var unica: Bool? = nil
    /// Dá para abrir a mídia no iPhone (foto e áudio comuns, até o limite de tamanho).
    var midia: Bool? = nil
}

struct ConversaWhatsApp: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var grupo: Bool
    var naoLidas: Int
    /// Hora da última mensagem, ISO 8601.
    var ultima: String
    var mensagens: [MensagemWhatsApp]
    /// Só na origem "qr". Arquivada aparece só no filtro Arquivadas e não entra na conta das não lidas.
    var arquivada: Bool? = nil
    /// Só na origem "qr". Os dígitos do telefone (conversa direta), para abrir a conversa no WhatsApp Web.
    var numero: String? = nil
    /// Só na origem "qr". O arquivo da foto de perfil (pedida em /api/whatsapp/foto/<arquivo>). Ausente = sem foto.
    var foto: String? = nil
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
// GET  /api/spotify/recentes       -> RecentesSpotify (só conectado)
// POST /api/spotify/pular?n=3[&uri=...]   toca a música na vez n da fila, pulando as de antes (só conectado)
// POST /api/spotify/repetir?modo=faixa|nao|contexto   repetir só a música, nada ou a lista pela API (só conectado, senão 409).
//                                  Sem `modo`, `repetir[?v=1|0]` segue sendo o do AppleScript acima.
// GET  /api/capa                   PNG ou JPEG da capa atual
// GET  /api/whatsapp               -> [ConversaWhatsApp] (vazia quando Estado.whatsapp.origem é "web": o navegador só dá o total)
// GET  /api/whatsapp/foto/<arquivo> -> {"tipo", "dados" (base64)}  a foto de perfil (origem "qr"; 404 sem foto)
// GET  /api/whatsapp/midia?chat=<id>&id=<mensagem> -> {"tipo", "dados" (base64)}  a foto ou o áudio de uma mensagem (origem "qr", até 8 MB, nunca visualização única)
// POST /api/whatsapp/abrir         <- {"id": "<conversa>"}  abre a conversa no WhatsApp Web do Mac -> {"ok": true, "aviso"?}
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
