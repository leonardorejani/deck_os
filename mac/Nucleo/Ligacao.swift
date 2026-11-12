import Foundation

// A ligação das peças reais ao roteador: fontes, ações, Spotify e config em disco entram pelos
// protocolos de Rotas.swift. Tudo passa pelo Executor injetado, então os testes usam um falso.

// MARK: - Painéis

struct PaineisReais: ProvedorPaineis {
    let armazem: ArmazemDeConfig
    let agregador: Agregador
    let agenda: FonteAgenda

    func estado() -> Estado { agregador.estado(config: armazem.ler()) }
    func whatsapp() -> [ConversaWhatsApp] { agregador.conversasWhatsApp() }
    func sessoes() -> [Sessao] { agregador.sessoes() }

    func agenda(de: String, dias: Int) -> [Evento] {
        let p = de.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let inicio = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return [] }
        return agenda.eventos(inicio, dias)
    }

    func capa() -> CapaAtual? {
        guard let dados = agregador.capa(), !dados.isEmpty else { return nil }
        // PNG começa com 0x89 "PNG". Todo o resto que o Spotify serve é JPEG.
        let png = dados.starts(with: [0x89, 0x50, 0x4E, 0x47])
        return CapaAtual(tipo: png ? "image/png" : "image/jpeg", dados: dados)
    }
}

// MARK: - Teclas

extension ExecutorAcoes: ExecutorTeclas {}

// MARK: - Spotify

/// Controle do Spotify. O que já existia vai por AppleScript (osascript pelo Executor) e continua igual sem
/// login. Volume também é AppleScript. Aparelhos, curtir, fila e repetir só a música vão pela API e só existem com
/// o Spotify conectado. Os textos de cada comando são fixos e os números entram formatados aqui, então
/// nada vindo do iPhone vira script.
struct SpotifyReal: ControleSpotify {
    let executor: any Executor
    var conta: ContaSpotify? = nil
    var complemento: ComplementoSpotify? = nil

    static let erroFechado = "O Spotify está fechado. Abra o app no Mac."
    static let erroFalha = "Não consegui controlar o Spotify. Libere o controle dele para o Deck nos Ajustes do Mac."

    func acao(_ nome: String) -> String? {
        let comando: String
        switch nome {
        case "tocar": comando = "play"
        case "pausar": comando = "pause"
        case "anterior": comando = "previous track"
        case "proxima": comando = "next track"
        default: return "Essa ação do Spotify não existe."
        }
        return rodar(comando)
    }

    func posicao(_ segundos: Double) -> String? {
        guard segundos.isFinite, segundos >= 0 else { return "Posição inválida." }
        return rodar("set player position to \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), segundos))")
    }

    // MARK: Volume

    func volume(_ alvo: AlvoVolume, _ valor: Int) -> ErroSpotify? {
        let n = max(0, min(100, valor))
        switch alvo {
        case .spotify: return rodar("set sound volume to \(n)").map { ErroSpotify(texto: $0) }
        case .mac:
            // O volume de saída do Mac não pede acesso nenhum e não abre o Spotify.
            let r = executor.rodar("osascript -e \(Shell.aspas("set volume output volume \(n)"))")
            return r.status == 0 ? nil : ErroSpotify(texto: "Não consegui mudar o volume do Mac.")
        case .aparelho:
            guard let conta, conta.conectado else { return .naoConectado }
            return conta.volumeDoAparelho(n)
        }
    }

    // MARK: Com login

    func dispositivos() -> Result<[DispositivoSpotify], ErroSpotify> { conta?.dispositivos() ?? .failure(.naoConectado) }

    func transferir(para id: String) -> ErroSpotify? { conta?.transferir(para: id) ?? .naoConectado }

    /// Quem diz qual é a faixa é o próprio Spotify do Mac, na hora do toque (não um valor guardado).
    func curtir(_ curtir: Bool) -> ErroSpotify? {
        guard let conta, conta.conectado else { return .naoConectado }
        let r = executor.rodar(Self.comandoDoId)
        let uri = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.status == 0, uri == "fechado" { return ErroSpotify(texto: Self.erroFechado) }
        guard r.status == 0, !uri.isEmpty, uri != "parado" else { return ErroSpotify(texto: "Nenhuma música tocando agora.") }
        if let erro = conta.curtir(uri, curtir) { return erro }
        complemento?.marcarCurtida(uri, curtir)
        return nil
    }

    func fila() -> Result<FilaSpotify, ErroSpotify> { conta?.fila() ?? .failure(.naoConectado) }

    func repetirModo(_ modo: String) -> ErroSpotify? {
        guard let conta else { return .naoConectado }
        if let erro = conta.repetir(modo) { return erro }
        complemento?.marcarRepetir(modo)
        return nil
    }

    static let comandoDoId: String = {
        let linhas = [
            #"if application "Spotify" is running then"#,
            #"tell application "Spotify""#,
            "try",
            "return id of current track",
            "on error",
            #"return "parado""#,
            "end try",
            "end tell",
            "else",
            #"return "fechado""#,
            "end if",
        ]
        return "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
    }()

    func definir(_ nome: String, ligado: Bool?) -> String? {
        let propriedade: String
        switch nome {
        case "repetir": propriedade = "repeating"
        case "aleatorio": propriedade = "shuffling"
        default: return "Essa ação do Spotify não existe."
        }
        let valor = ligado.map { $0 ? "true" : "false" } ?? "not \(propriedade)"
        return rodar("set \(propriedade) to \(valor)")
    }

    /// `application "Spotify" is running` não abre o app: fechado devolve o texto "fechado".
    private func rodar(_ dentro: String) -> String? {
        let linhas = [
            #"if application "Spotify" is running then"#,
            #"tell application "Spotify" to "# + dentro,
            #"return "ok""#,
            "else",
            #"return "fechado""#,
            "end if",
        ]
        let r = executor.rodar("osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " "))
        let saida = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.status == 0, saida == "fechado" { return Self.erroFechado }
        return r.status == 0 ? nil : Self.erroFalha
    }
}

// MARK: - Config

/// A config em disco atrás do protocolo. Relê o arquivo só quando ele muda (o roteador pergunta a
/// cada requisição), e arquivo ilegível não derruba nada: fica a última config boa.
final class ArmazemEmDisco: ArmazemDeConfig, @unchecked Sendable {
    private let armazem: ArmazemConfig
    private let trava = NSLock()
    private var atual: Config
    private var visto: Date?

    /// Lê (ou cria a padrão, se o arquivo não existe). Lança com o texto pronto se o arquivo não abre.
    init(_ armazem: ArmazemConfig) throws {
        self.armazem = armazem
        atual = try armazem.ler()
        visto = modificacao()
    }

    private func modificacao() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: armazem.url.path))?[.modificationDate] as? Date
    }

    func ler() -> Config {
        trava.lock(); defer { trava.unlock() }
        let m = modificacao()
        if m != visto {
            visto = m
            if let nova = try? armazem.ler() { atual = nova }
        }
        return atual
    }

    func aplicar(_ nova: Config) -> String? {
        if let erro = Config.validar(nova) { return erro }
        trava.lock(); defer { trava.unlock() }
        do { try armazem.gravar(nova) } catch { return (error as? ErroConfig)?.mensagem ?? "Não consegui salvar a configuração do Deck." }
        atual = nova
        visto = modificacao()
        return nil
    }
}

// MARK: - Montagem

enum Ligacao {
    /// O roteador com as peças reais deste Mac.
    static func roteador(armazem: ArmazemDeConfig, pareamento: Pareamento, pagina: ArquivosPagina,
                         executor: any Executor = ExecutorShell(), fontes: Fontes? = nil,
                         agenda: FonteAgenda = .viva(), rodizio: Rodizio = Rodizio(),
                         certificadoCA: URL? = nil, contaSpotify: ContaSpotify? = nil,
                         apps: (any ProvedorDeApps)? = nil, criadorDeAgenda: (any CriadorDeAgenda)? = nil) -> Roteador {
        // A mesma decisão de origem do WhatsApp serve a leitura (estado) e a abertura (tecla e "Abrir no Mac").
        let origemWhats = OrigemWhatsApp(executor: executor, banco: FonteWhatsApp.caminhoPadrao(casa: NSHomeDirectory()),
                                         config: { armazem.ler().whatsapp })
        let complemento = contaSpotify.map { ComplementoSpotify(conta: $0) }
        let agregador = Agregador(fontes: fontes ?? .vivas(executor: executor, origemWhatsApp: origemWhats, complementoSpotify: complemento))
        let abridor = AbridorWhatsApp(origem: origemWhats, executor: executor)
        return Roteador(
            paineis: PaineisReais(armazem: armazem, agregador: agregador, agenda: agenda),
            teclas: ExecutorAcoes(shell: executor, whatsappWeb: { abridor.abrir() }), spotify: SpotifyReal(executor: executor, conta: contaSpotify, complemento: complemento),
            config: armazem, pareamento: pareamento, pagina: pagina, rodizio: rodizio, certificadoCA: certificadoCA,
            reunioes: AbridorDeReuniao(shell: executor), criadorDeAgenda: criadorDeAgenda ?? Self.criadorPadrao(),
            abridorDeSessao: AbridorDeSessaoNoMac(raiz: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/jobs"), shell: executor),
            apps: apps ?? AppsDoMac(pastaDeCache: AppsDoMac.pastaDeCachePadrao(), executor: executor))
    }

    /// Só o Mac grava na agenda: no Linux (CI) a rota fica sem criador e responde 404.
    static func criadorPadrao() -> (any CriadorDeAgenda)? {
        #if canImport(EventKit) && canImport(CoreGraphics)
        return CriadorEventKit()
        #else
        return nil
        #endif
    }

    /// Nome do Mac para a config padrão ("MacBook do Leo"), ou "Mac" se o sistema não responde.
    static func nomeDoMac(executor: any Executor = ExecutorShell()) -> String {
        let r = executor.rodar("scutil --get ComputerName")
        let nome = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.status == 0 && !nome.isEmpty ? nome : "Mac"
    }
}
