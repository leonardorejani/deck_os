import XCTest
@testable import Nucleo
#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

final class FontesSpotifyTestes: XCTestCase {
    func testParseDaSaidaDoAppleScript() throws {
        let f = try XCTUnwrap(FonteSpotify.parse("playing\tAmazing Grace\tCoral\t12,5\t215000\thttps://i.scdn.co/image/abc\n"))
        XCTAssertEqual(f, FonteSpotify.Faixa(tocando: true, faixa: "Amazing Grace", artista: "Coral",
                                             posicao: 12.5, duracao: 215, arte: "https://i.scdn.co/image/abc"))
        let p = try XCTUnwrap(FonteSpotify.parse("paused\tA\tB\t3.25\t200\t"))
        XCTAssertFalse(p.tocando)
        XCTAssertEqual(p.duracao, 200)
        XCTAssertEqual(p.posicao, 3.25)
    }

    func testParseLeAlbumRepetirEAleatorio() throws {
        let f = try XCTUnwrap(FonteSpotify.parse("playing\tFaixa de Exemplo\tArtista Exemplo\t12,5\t221000\thttps://i.scdn.co/image/abc\tArtista Exemplo\ttrue\tfalse\n"))
        XCTAssertEqual(f.album, "Artista Exemplo")
        XCTAssertTrue(f.repetir)
        XCTAssertFalse(f.aleatorio)
        let g = try XCTUnwrap(FonteSpotify.parse("paused\tA\tB\t3\t200\t\tÁlbum\tfalse\ttrue"))
        XCTAssertFalse(g.repetir)
        XCTAssertTrue(g.aleatorio)
        // Saída da versão antiga do comando (6 campos): álbum vazio e os dois desligados, sem derrubar nada.
        let velha = try XCTUnwrap(FonteSpotify.parse("playing\tA\tB\t1\t100\t"))
        XCTAssertEqual(velha.album, "")
        XCTAssertFalse(velha.repetir)
        XCTAssertFalse(velha.aleatorio)
    }

    func testLerPassaAlbumRepetirEAleatorioParaOEstado() throws {
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "playing\tFaixa de Exemplo\tArtista Exemplo\t12\t221000\t\tÁlbum X\ttrue\ttrue"))])
        let e = try XCTUnwrap(FonteSpotify(executor: ex).ler().valor)
        XCTAssertEqual(e.album, "Álbum X")
        XCTAssertEqual(e.repetir, true)
        XCTAssertEqual(e.aleatorio, true)
    }

    func testEstadoDeMacAntigoSemOsCamposNovosAindaDecodifica() throws {
        let json = #"{"tocando":true,"faixa":"F","artista":"A","posicao":1,"duracao":2,"capaId":null,"cores":[]}"#
        let e = try JSONDecoder().decode(EstadoSpotify.self, from: Data(json.utf8))
        XCTAssertNil(e.album)
        XCTAssertNil(e.repetir)
        XCTAssertNil(e.aleatorio)
    }

    func testParseTrazVolumeDoSpotifyIdDaFaixaEVolumeDoMac() throws {
        let f = try XCTUnwrap(FonteSpotify.parse("playing\tA\tB\t1,5\t200000\thttps://x/c\tAlb\ttrue\tfalse\t65\tspotify:track:abc123\t30\n"))
        XCTAssertEqual(f.volume, 65)
        XCTAssertEqual(f.uri, "spotify:track:abc123")
        XCTAssertEqual(f.volumeMac, 30)
    }

    func testParseDoVolumeTolerante() throws {
        // Saída sem controle de volume (HDMI) devolve "-" no Mac, e volume fora da faixa é limitado.
        let f = try XCTUnwrap(FonteSpotify.parse("paused\tA\tB\t0\t100\t\t\tfalse\tfalse\t140\t\t-"))
        XCTAssertEqual(f.volume, 100)
        XCTAssertNil(f.uri)
        XCTAssertNil(f.volumeMac)
        let k = try XCTUnwrap(FonteSpotify.parse("paused\tA\tB\t0\t100\t\t\tfalse\tfalse\tmissing value\tspotify:local:a:b:c:1\tmissing value"))
        XCTAssertNil(k.volume); XCTAssertNil(k.volumeMac)
        XCTAssertEqual(k.uri, "spotify:local:a:b:c:1")
    }

    func testEstadoLeVolumesEGuardaAUriDaFaixa() throws {
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "playing\tA\tB\t1\t100000\t\t\tfalse\tfalse\t42\tspotify:track:zzz\t18"))])
        let fonte = FonteSpotify(executor: ex)
        let e = try XCTUnwrap(fonte.ler().valor)
        XCTAssertEqual(e.volume, 42)
        XCTAssertEqual(e.volumeMac, 18)
        XCTAssertEqual(fonte.uriAtual(), "spotify:track:zzz")
        XCTAssertNil(e.conectado, "o login é coisa do complemento, não do AppleScript")
    }

    func testComandoDeLeituraPedeVolumeDoSpotifyEDoMacSemAbrirOApp() {
        XCTAssertTrue(FonteSpotify.comando.contains("sound volume"))
        XCTAssertTrue(FonteSpotify.comando.contains("output volume of (get volume settings)"))
    }

    func testEstadoSemOsCamposNovosSerializaIgualAoDeAntes() throws {
        let e = EstadoSpotify(tocando: true, faixa: "A", artista: "B", posicao: 1, duracao: 2, capaId: nil, cores: [])
        let chaves = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any]).keys)
        XCTAssertEqual(chaves, ["tocando", "faixa", "artista", "posicao", "duracao", "cores"])
    }

    func testParseRecusaSaidaQueNaoEUmaFaixa() {
        XCTAssertNil(FonteSpotify.parse("fechado"))
        XCTAssertNil(FonteSpotify.parse(""))
    }

    func testSpotifyFechadoDevolveNilSemAviso() {
        for fim in ["fechado\n", "parado\n"] {
            let r = FonteSpotify(executor: ExecutorFalso([("osascript", SaidaShell(status: 0, saida: fim))])).ler()
            XCTAssertNil(r.valor)
            XCTAssertNil(r.aviso)
        }
    }

    func testFalhaDoOsascriptViraAviso() {
        let r = FonteSpotify(executor: ExecutorFalso([("osascript", SaidaShell(status: 1, saida: "execution error: Not authorized (-1743)"))])).ler()
        XCTAssertNil(r.valor)
        XCTAssertEqual(r.aviso?.fonte, "spotify")
    }

    func testComandoNaoAbreOSpotifyEVaiPeloOsascript() {
        XCTAssertTrue(FonteSpotify.comando.hasPrefix("osascript -e "))
        XCTAssertTrue(FonteSpotify.comando.contains(#"application "Spotify" is running"#))
        XCTAssertTrue(FonteSpotify.comando.contains("repeating"))
        XCTAssertTrue(FonteSpotify.comando.contains("shuffling"))
    }

    func testCapaIdMudaQuandoAArteMuda() {
        XCTAssertEqual(FonteSpotify.capaId("https://a/1"), FonteSpotify.capaId("https://a/1"))
        XCTAssertNotEqual(FonteSpotify.capaId("https://a/1"), FonteSpotify.capaId("https://a/2"))
        XCTAssertNil(FonteSpotify.capaId(""))
    }

    func testBaixaACapaUmaVezSoETiraAsCores() throws {
        let contagem = Contador()
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "playing\tA\tB\t1\t100000\thttps://x/capa1"))])
        let fonte = FonteSpotify(executor: ex,
                                 baixar: { _ in contagem.somar(); return Data([1, 2, 3]) },
                                 pixels: { _ in Array(repeating: Pixel(r: 200, g: 10, b: 10), count: 50) + Array(repeating: Pixel(r: 10, g: 10, b: 200), count: 30) })
        let a = try XCTUnwrap(fonte.ler().valor)
        _ = fonte.ler()
        XCTAssertEqual(contagem.valor, 1)
        XCTAssertEqual(a.cores, ["#c80a0a", "#0a0ac8"])
        XCTAssertEqual(a.capaId, FonteSpotify.capaId("https://x/capa1"))
        XCTAssertEqual(fonte.capa(), Data([1, 2, 3]))
    }

    func testFalhaNoDownloadNaoDerrubaOEstadoETentaDepoisDe30s() throws {
        let contagem = Contador()
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "playing\tA\tB\t1\t100000\thttps://x/capa1"))])
        let fonte = FonteSpotify(executor: ex, baixar: { _ in contagem.somar(); return nil }, pixels: { _ in nil })
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = try XCTUnwrap(fonte.ler(agora: t0).valor)
        XCTAssertEqual(a.cores, [])
        XCTAssertNil(fonte.ler(agora: t0).aviso)
        _ = fonte.ler(agora: t0.addingTimeInterval(5))
        XCTAssertEqual(contagem.valor, 1)
        _ = fonte.ler(agora: t0.addingTimeInterval(31))
        XCTAssertEqual(contagem.valor, 2)
    }

    // MARK: cores da capa

    func testDuasCoresDominantesComPixelsDeExemplo() {
        let px = Array(repeating: Pixel(r: 255, g: 0, b: 0), count: 100) + Array(repeating: Pixel(r: 0, g: 0, b: 255), count: 60)
        XCTAssertEqual(CoresCapa.dominantes(px), ["#ff0000", "#0000ff"])
    }

    func testCorVivaGanhaDoFundoCinzaMesmoSendoMenor() {
        let px = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100) + Array(repeating: Pixel(r: 220, g: 20, b: 20), count: 70)
        XCTAssertEqual(CoresCapa.dominantes(px).first, "#dc1414")
    }

    func testCapaDeUmaCorSoGanhaUmaVersaoMaisEscura() {
        let px = Array(repeating: Pixel(r: 200, g: 100, b: 50), count: 80)
        XCTAssertEqual(CoresCapa.dominantes(px), ["#c86432", "#5a2d16"])
    }

    func testCoresParecidasNaoViramAsDuas() {
        let px = Array(repeating: Pixel(r: 200, g: 20, b: 20), count: 80) + Array(repeating: Pixel(r: 215, g: 25, b: 25), count: 60)
        // As duas caem no mesmo grupo e viram uma média só, mais a versão escura dela.
        XCTAssertEqual(CoresCapa.dominantes(px), ["#ce1616", "#5c0909"])
    }

    func testPretoPuroEListaVaziaNaoDaoCor() {
        XCTAssertEqual(CoresCapa.dominantes(Array(repeating: Pixel(r: 0, g: 0, b: 0), count: 100)), [])
        XCTAssertEqual(CoresCapa.dominantes([]), [])
    }

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    /// Prova com uma imagem de verdade (PNG gerado aqui), passando pela decodificação do ImageIO.
    func testLeUmPngDeVerdadeEAchaAsCores() throws {
        let lado = 64
        let espaco = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: 0, space: espaco,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: lado, height: 40))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 40, width: lado, height: 24))
        let imagem = try XCTUnwrap(ctx.makeImage())
        let dados = NSMutableData()
        let destino = try XCTUnwrap(CGImageDestinationCreateWithData(dados, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destino, imagem, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destino))
        let px = try XCTUnwrap(CoresCapa.pixels(de: dados as Data))
        XCTAssertEqual(px.count, 32 * 32)
        // O ImageIO suaviza a borda ao reduzir, então vale a cor aproximada: vermelho e azul.
        let cores = CoresCapa.dominantes(px)
        XCTAssertEqual(cores.count, 2)
        func canais(_ hex: String) -> [Int] { [1, 3, 5].map { Int(hex.dropFirst($0).prefix(2), radix: 16)! } }
        XCTAssertGreaterThan(canais(cores[0])[0], 230); XCTAssertLessThan(canais(cores[0])[2], 60)
        XCTAssertGreaterThan(canais(cores[1])[2], 230); XCTAssertLessThan(canais(cores[1])[0], 60)
        XCTAssertNil(CoresCapa.pixels(de: Data([0, 1, 2])))
    }
    #endif

    // MARK: - Spotify fecha e abre de novo (12/11/2026: "reaberto não apareceu de volta, mesmo dando play")

    private final class Chave: @unchecked Sendable {
        private let trava = NSLock()
        private var _aberto = false
        var aberto: Bool { get { trava.lock(); defer { trava.unlock() }; return _aberto } set { trava.lock(); _aberto = newValue; trava.unlock() } }
    }

    func testSpotifyFechadoNoSistemaNaoRodaAppleScriptNenhum() {
        // Falar com o Spotify por AppleScript pode abrir o app. Fechado, o osascript nem roda.
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "playing\tA\tB\t1\t100\t"))])
        let r = FonteSpotify(executor: ex, aberto: { false }).ler()
        XCTAssertNil(r.valor)
        XCTAssertNil(r.aviso)
        XCTAssertEqual(ex.comandos, [], "com o app fechado nenhum comando pode ser rodado")
    }

    func testLeituraQueEstouraOTempoNaoViraAvisoENaoTravaAProxima() throws {
        // 142 é o status do vigia (Shell.limitado) quando o Spotify não atende a tempo.
        let ex = ExecutorMutavel("")
        ex.status = 142
        let f = FonteSpotify(executor: ex, aberto: { true })
        let r = f.ler()
        XCTAssertNil(r.valor)
        XCTAssertNil(r.aviso, "Spotify ainda abrindo não é erro para mostrar")
        ex.status = 0
        ex.saida = "playing\tFaixa\tArtista\t3\t200000\t"
        XCTAssertEqual(f.ler().valor?.faixa, "Faixa")
    }

    func testLeituraLentaComSpotifyTocandoSegueAUltimaFaixaPorUmTempo() {
        // Defeito: o 142 virava nil e o player sumia do iPhone por uma leitura lenta passageira.
        let ex = ExecutorMutavel("playing\tFaixa\tArtista\t3\t200000\t")
        let f = FonteSpotify(executor: ex, aberto: { true })
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(f.ler(agora: t0).valor?.faixa, "Faixa")
        ex.status = 142
        let lenta = f.ler(agora: t0.addingTimeInterval(5))
        XCTAssertEqual(lenta.valor?.faixa, "Faixa", "leitura lenta passageira não derruba o player")
        XCTAssertNil(lenta.aviso)
        let velha = f.ler(agora: t0.addingTimeInterval(FonteSpotify.validadeDaUltimaFaixa + 1))
        XCTAssertNil(velha.valor, "sem resposta além da validade o player sai")
        XCTAssertNil(velha.aviso)
    }

    func testFecharOuPararLimpaAUltimaFaixaAntesDoTempoLimite() {
        let ex = ExecutorMutavel("playing\tFaixa\tArtista\t3\t200000\t")
        let chave = Chave(); chave.aberto = true
        let f = FonteSpotify(executor: ex, aberto: { chave.aberto })
        XCTAssertNotNil(f.ler().valor)
        chave.aberto = false
        XCTAssertNil(f.ler().valor)
        chave.aberto = true
        ex.status = 142
        XCTAssertNil(f.ler().valor, "fechou e abriu: a faixa velha não ressuscita")
    }

    func testLeituraVaiDentroDoVigiaComTempoLimite() {
        let ex = ExecutorFalso([("osascript", SaidaShell(status: 0, saida: "paused\tA\tB\t1\t100\t"))])
        _ = FonteSpotify(executor: ex, aberto: { true }).ler()
        XCTAssertEqual(ex.comandos.count, 1)
        XCTAssertTrue(ex.comandos[0].hasPrefix("perl -e "), "sem tempo limite um osascript pendurado segura a leitura para sempre")
    }

    func testVigiaDeVerdadeMataOSpotifyQueNaoAtende() throws {
        // O vigia de verdade usa o perl do macOS, que a imagem Linux do CI não tem.
        #if !os(macOS)
        throw XCTSkip("o vigia de tempo limite usa o perl do macOS")
        #endif
        let t0 = Date()
        let r = ExecutorShell().rodar(Shell.limitado("sleep 30", segundos: 1))
        XCTAssertEqual(r.status, 142)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 5)
    }

    func testCicloFechadoAbertoTocandoVoltaNoEstado() throws {
        // O Spotify do Mac só existe no macOS: no Linux do CI o agregador soma avisos das fontes do Mac.
        #if !os(macOS)
        throw XCTSkip("o player do Spotify só existe no macOS")
        #endif
        // O ciclo do defeito: tocando, o app fecha (sai do painel), abre de novo (ainda sem faixa) e toca (volta).
        let chave = Chave()
        let ex = ExecutorMutavel("playing\tQuero Ser Feliz\tCoral\t10\t200000\t")
        var fontes = Fontes.vivas(executor: ex, casa: "/nonexistent", spotifyAberto: { chave.aberto })
        fontes.sessoes = { Leitura(valor: [], aviso: nil) }
        let agregador = Agregador(fontes: fontes)
        let cfg = config(perfil: [])
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        chave.aberto = true
        XCTAssertEqual(agregador.estado(config: cfg, agora: t0).spotify?.faixa, "Quero Ser Feliz")

        chave.aberto = false
        let antes = ex.chamadas
        XCTAssertNil(agregador.estado(config: cfg, agora: t0.addingTimeInterval(1)).spotify, "fechou: o player sai")
        XCTAssertEqual(ex.chamadas, antes, "fechado, nenhum AppleScript (abriria o app sozinho)")

        chave.aberto = true
        ex.saida = "parado"
        XCTAssertNil(agregador.estado(config: cfg, agora: t0.addingTimeInterval(2)).spotify, "abriu mas sem faixa: ainda sem player")

        ex.status = 142
        XCTAssertNil(agregador.estado(config: cfg, agora: t0.addingTimeInterval(3)).spotify, "Spotify abrindo e sem atender: sem player e sem travar")

        ex.status = 0
        ex.saida = "playing\tQuero Ser Feliz\tCoral\t0\t200000\t"
        let volta = agregador.estado(config: cfg, agora: t0.addingTimeInterval(4))
        XCTAssertEqual(volta.spotify?.faixa, "Quero Ser Feliz", "deu play: o player volta")
        XCTAssertEqual(volta.spotify?.tocando, true)
        XCTAssertTrue(volta.avisos.isEmpty)
    }
}

final class Contador: @unchecked Sendable {
    private let t = NSLock()
    private var n = 0
    func somar() { t.lock(); n += 1; t.unlock() }
    var valor: Int { t.lock(); defer { t.unlock() }; return n }
}
