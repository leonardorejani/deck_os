import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Spotify por AppleScript (via Executor, `osascript`). Spotify fechado devolve nil sem aviso: o
/// player só some do painel (SPEC seção 6). Quem diz se o app está aberto é o sistema (bundle id), antes
/// de qualquer AppleScript: com ele fechado o `osascript` nem roda. E o `osascript` roda dentro do vigia
/// com tempo limite, porque um Spotify que acabou de abrir (ou está fechando) pode não atender o
/// evento por minutos, e uma leitura pendurada segurava o cache e o player não voltava.
final class FonteSpotify: @unchecked Sendable {
    struct Faixa: Equatable {
        var tocando: Bool
        var faixa: String
        var artista: String
        var posicao: Double
        var duracao: Double
        var arte: String
        var album: String = ""
        var repetir: Bool = false
        var aleatorio: Bool = false
        /// Volume do Spotify (0 a 100), o id da faixa (`spotify:track:...`) e o volume de saída do Mac.
        /// Ausentes quando o AppleScript é de uma versão que não os devolve.
        var volume: Int? = nil
        var uri: String? = nil
        var volumeMac: Int? = nil
    }

    /// Cada linha é um `-e`. `application "Spotify" is running` não abre o app. O separador é a
    /// tabulação, que não aparece em nome de faixa.
    static let comando: String = {
        let linhas = [
            #"if application "Spotify" is running then"#,
            // A saída sem controle de volume (HDMI) devolve "missing value": vira "-" e o painel não mostra o volume do Mac.
            #"set mv to "-""#,
            "try",
            "set mv to (output volume of (get volume settings)) as text",
            "end try",
            #"tell application "Spotify""#,
            "try",
            "set d to duration of current track",
            // Álbum, repetir e aleatório vêm cada um no seu try: se o Spotify não souber um deles, o resto do estado segue.
            #"set al to """#, "try", "set al to album of current track", "end try",
            #"set rp to "false""#, "try", "set rp to repeating as text", "end try",
            #"set sh to "false""#, "try", "set sh to shuffling as text", "end try",
            // Volume do Spotify e id da faixa também, cada um no seu try ("-" e vazio quando não vierem).
            #"set sv to "-""#, "try", "set sv to (sound volume as text)", "end try",
            #"set ti to """#, "try", "set ti to (id of current track)", "end try",
            #"return (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (player position as text) & tab & (d as text) & tab & (artwork url of current track) & tab & al & tab & rp & tab & sh & tab & sv & tab & ti & tab & mv"#,
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

    /// nil: app fechado ou sem faixa carregada. O AppleScript em pt-BR escreve decimal com vírgula.
    static func parse(_ saida: String) -> Faixa? {
        let t = saida.trimmingCharacters(in: .newlines)
        let campos = t.components(separatedBy: "\t")
        guard campos.count >= 6 else { return nil }
        func numero(_ s: String) -> Double {
            Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        // O Spotify entrega a duração em milissegundos, apesar do dicionário dizer segundos.
        // Nenhuma faixa passa de 3 h, então acima de 10 000 só pode ser milissegundo.
        let duracao = numero(campos[4])
        func inteiro(_ i: Int) -> Int? {
            guard campos.count > i, let d = Double(campos[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), d.isFinite else { return nil }
            return max(0, min(100, Int(d.rounded())))
        }
        let uri = campos.count > 10 ? campos[10].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return Faixa(
            tocando: campos[0].trimmingCharacters(in: .whitespaces) == "playing",
            faixa: campos[1], artista: campos[2],
            posicao: numero(campos[3]),
            duracao: duracao > 10_000 ? duracao / 1000 : duracao,
            arte: campos[5].trimmingCharacters(in: .whitespaces),
            // Os campos depois da arte só existem na versão nova do comando.
            album: campos.count > 6 ? campos[6] : "",
            repetir: campos.count > 7 && campos[7].trimmingCharacters(in: .whitespaces) == "true",
            aleatorio: campos.count > 8 && campos[8].trimmingCharacters(in: .whitespaces) == "true",
            volume: inteiro(9), uri: uri.isEmpty ? nil : uri, volumeMac: inteiro(11)
        )
    }

    /// Identificador curto da capa (FNV-1a da URL, em hex). A URL da arte muda quando a capa muda.
    static func capaId(_ arte: String) -> String? {
        guard !arte.isEmpty else { return nil }
        var h: UInt64 = 0xcbf29ce484222325
        for b in arte.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// O Spotify guarda a mesma capa em três tamanhos, e o que muda na URL é o prefixo do código: 00001e02 (300 px) e 0000b273 (640 px).
    static func urlDaCapaGrande(_ arte: String) -> String {
        arte.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273")
    }

    /// Bundle id do app do Spotify no Mac.
    static let bundleId = "com.spotify.client"
    /// Tempo máximo de uma leitura por AppleScript. O estado espera 2 s, então 4 s já é folga de sobra.
    static let limiteDaLeitura = 4

    /// O Spotify está aberto? Consulta o sistema (NSRunningApplication) e nunca abre o app, ao contrário
    /// de falar com ele por AppleScript. Fora do macOS (CI no Linux) devolve true e vale a checagem do próprio script. O `init` não
    /// consulta o sistema sozinho: o teste com executor falso não pode depender de o Spotify estar aberto neste Mac.
    @Sendable static func spotifyAberto() -> Bool {
        #if canImport(AppKit)
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
        #else
        return true
        #endif
    }

    private let executor: any Executor
    private let aberto: @Sendable () -> Bool
    private let baixar: @Sendable (String) -> Data?
    private let pixels: @Sendable (Data) -> [Pixel]?
    private let trava = NSLock()
    private var capaAtual: String?
    private var coresAtuais: [String] = []
    private var imagemAtual: Data?
    private var falhouEm: Date?
    private var falhouId: String?
    private var baixando: String?
    private var uriDaFaixa: String?
    private var ultimoEstado: EstadoSpotify?
    private var ultimoEstadoEm: Date?
    /// Quanto tempo a última faixa segue valendo quando uma leitura estoura o limite (Mac acordando, Spotify ocupado).
    static let validadeDaUltimaFaixa: TimeInterval = 30

    /// `baixar` e `pixels` entram de fora para o teste não precisar de rede nem de ImageIO.
    init(executor: any Executor,
         aberto: @escaping @Sendable () -> Bool = { true },
         baixar: @escaping @Sendable (String) -> Data? = FonteSpotify.baixarDoSpotify,
         pixels: @escaping @Sendable (Data) -> [Pixel]? = FonteSpotify.pixelsDaImagem) {
        self.executor = executor
        self.aberto = aberto
        self.baixar = baixar
        self.pixels = pixels
    }

    /// A imagem da capa atual, para GET /api/capa.
    func capa() -> Data? {
        trava.lock(); defer { trava.unlock() }
        return imagemAtual
    }

    /// O id da faixa que tocava na última leitura, para curtir e para o complemento da API.
    func uriAtual() -> String? {
        trava.lock(); defer { trava.unlock() }
        return uriDaFaixa
    }

    func ler(agora: Date = Date()) -> Leitura<EstadoSpotify?> {
        // Fechado: nada de AppleScript. Some o player e, quando ele abrir de novo, a próxima leitura já o traz.
        guard aberto() else {
            trava.lock(); uriDaFaixa = nil; ultimoEstado = nil; trava.unlock()
            return Leitura(valor: nil, aviso: nil)
        }
        let r = executor.rodar(Shell.limitado(Self.comando, segundos: Self.limiteDaLeitura))
        // Estourou o tempo (142 do vigia): o Spotify ainda não atende. Sem aviso, e a próxima leitura tenta de novo.
        // Com ele aberto e tocando é só uma leitura lenta: segue a última faixa por um tempo curto (comportamento
        // aprovado do painel). Passou da validade sem resposta, o player sai.
        if r.status == 142 {
            trava.lock(); defer { trava.unlock() }
            if let e = ultimoEstado, let em = ultimoEstadoEm, agora.timeIntervalSince(em) <= Self.validadeDaUltimaFaixa {
                return Leitura(valor: e, aviso: nil)
            }
            uriDaFaixa = nil; ultimoEstado = nil
            return Leitura(valor: nil, aviso: nil)
        }
        let saida = r.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.status == 0, saida == "fechado" || saida == "parado" {
            trava.lock(); uriDaFaixa = nil; ultimoEstado = nil; trava.unlock()
            return Leitura(valor: nil, aviso: nil)
        }
        guard r.status == 0, let f = Self.parse(r.saida) else {
            return Leitura(valor: nil, aviso: Aviso(fonte: "spotify", texto: "Não consegui falar com o Spotify. Libere o controle dele para o Deck nos Ajustes do Mac."))
        }
        let id = Self.capaId(f.arte)
        atualizarCapa(id: id, arte: f.arte, agora: agora)
        trava.lock()
        let cores = capaAtual == id ? coresAtuais : []
        uriDaFaixa = f.uri
        let estado = EstadoSpotify(tocando: f.tocando, faixa: f.faixa, artista: f.artista,
                                            posicao: f.posicao, duracao: f.duracao, capaId: id, cores: cores,
                                            album: f.album, repetir: f.repetir, aleatorio: f.aleatorio,
                                            volume: f.volume, volumeMac: f.volumeMac)
        ultimoEstado = estado; ultimoEstadoEm = agora
        trava.unlock()
        return Leitura(valor: estado, aviso: nil)
    }

    /// Baixa a arte e tira as cores só quando ela muda. Se o download falha, tenta de novo em 30 s,
    /// mas só para a mesma capa: uma capa diferente é tentada na hora.
    private func atualizarCapa(id: String?, arte: String, agora: Date) {
        trava.lock()
        let esperando = falhouId == id && (falhouEm.map { agora.timeIntervalSince($0) <= 30 } ?? false)
        let precisa = id != capaAtual && !esperando && (id == nil || baixando != id)
        if precisa, let id { baixando = id }
        trava.unlock()
        guard precisa else { return }
        guard let id else {
            trava.lock(); capaAtual = nil; coresAtuais = []; imagemAtual = nil; falhouId = nil; falhouEm = nil; trava.unlock()
            return
        }
        defer { trava.lock(); if baixando == id { baixando = nil }; trava.unlock() }
        // A arte do AppleScript vem em 300 px. Pede a de 640 (a images[0] da API do Spotify) e, se não houver, fica com a que veio.
        let grande = Self.urlDaCapaGrande(arte)
        guard let dados = (grande != arte ? baixar(grande) : nil) ?? baixar(arte), let px = pixels(dados) else {
            // A faixa já é outra: a imagem e as cores da anterior não podem ir junto com o id novo.
            trava.lock()
            capaAtual = nil; coresAtuais = []; imagemAtual = nil; falhouId = id; falhouEm = agora
            trava.unlock()
            return
        }
        let cores = CoresCapa.dominantes(px)
        trava.lock()
        capaAtual = id; coresAtuais = cores; imagemAtual = dados; falhouId = nil; falhouEm = nil
        trava.unlock()
    }

    private final class Caixa: @unchecked Sendable { var dados: Data? }

    @Sendable static func baixarDoSpotify(_ url: String) -> Data? {
        #if os(macOS)
        guard let u = URL(string: url), u.scheme == "https" || u.scheme == "http" else { return nil }
        let caixa = Caixa()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 3)) { d, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200 { caixa.dados = d }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
        return caixa.dados
        #else
        return nil
        #endif
    }

    @Sendable static func pixelsDaImagem(_ dados: Data) -> [Pixel]? {
        #if canImport(ImageIO) && canImport(CoreGraphics)
        return CoresCapa.pixels(de: dados)
        #else
        return nil
        #endif
    }
}
