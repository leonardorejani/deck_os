import XCTest
@testable import Nucleo

/// Defeitos achados na verificação adversarial das fontes.
final class FontesVerificacaoTestes: XCTestCase {
    private let faixa = "playing\tA\tB\t1,0\t200000\t"

    func testCapaNovaComDownloadQueFalhaNaoServeAImagemVelha() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let mut = ExecutorMutavel(faixa + "https://x/a")
        let g = FonteSpotify(executor: mut,
                             baixar: { u in u.hasSuffix("/a") ? Data("IMG-A".utf8) : nil },
                             pixels: { _ in [Pixel(r: 200, g: 10, b: 10)] })
        let r1 = g.ler(agora: t0)
        XCTAssertEqual(g.capa(), Data("IMG-A".utf8))
        XCTAssertFalse(r1.valor!.cores.isEmpty)
        mut.saida = faixa + "https://x/b"
        let r2 = g.ler(agora: t0.addingTimeInterval(1))
        XCTAssertNil(g.capa(), "não pode servir a arte da faixa anterior")
        XCTAssertEqual(r2.valor?.cores, [])
    }

    func testCapaNovaLogoDepoisDeUmaFalhaETentadaNaHora() {
        let mut = ExecutorMutavel(faixa + "https://x/b")
        let g = FonteSpotify(executor: mut,
                             baixar: { u in u.hasSuffix("/c") ? Data("IMG-C".utf8) : nil },
                             pixels: { _ in [Pixel(r: 200, g: 10, b: 10)] })
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        _ = g.ler(agora: t0)
        mut.saida = faixa + "https://x/c"
        _ = g.ler(agora: t0.addingTimeInterval(1))
        XCTAssertEqual(g.capa(), Data("IMG-C".utf8), "capa nova não espera os 30 s da falha da capa anterior")
    }

    func testFonteLentaNaoTravaOEstado() {
        var f = Fontes.vivas(executor: ExecutorFalso([]), casa: "/nonexistent")
        f.spotify = { _ in Thread.sleep(forTimeInterval: 3); return Leitura(valor: nil, aviso: nil) }
        let ag = Agregador(fontes: f, limite: 0.5)
        let ini = Date()
        _ = ag.estado(config: config(perfil: []))
        XCTAssertLessThan(Date().timeIntervalSince(ini), 1.5)
    }

    func testFonteLentaUsaOUltimoValorEmVezDeEsvaziar() {
        let chamadas = ContadorDeChamadas()
        var f = Fontes.vivas(executor: ExecutorFalso([]), casa: "/nonexistent")
        f.spotify = { _ in
            if chamadas.proximo() == 1 {
                return Leitura(valor: EstadoSpotify(tocando: true, faixa: "F", artista: "A", posicao: 1, duracao: 2, capaId: nil, cores: []), aviso: nil)
            }
            Thread.sleep(forTimeInterval: 2)
            return Leitura(valor: nil, aviso: nil)
        }
        let ag = Agregador(fontes: f, limite: 0.3)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ag.estado(config: config(perfil: []), agora: t0).spotify?.faixa, "F")
        XCTAssertEqual(ag.estado(config: config(perfil: []), agora: t0.addingTimeInterval(1)).spotify?.faixa, "F")
        XCTAssertEqual(ag.estado(config: config(perfil: []), agora: t0.addingTimeInterval(2)).spotify?.faixa, "F")
        XCTAssertEqual(chamadas.valor, 2, "enquanto uma leitura está em andamento, não começa outra")
    }

    func testNumeroGiganteNoUsoViraVazioEmVezDeDerrubar() {
        let j = UsoCodex.parse(#"{"payload":{"rate_limits":{"primary":{"window_minutes":10080,"used_percent":1e30,"resets_at":1794500000}}}}"#)
        XCTAssertEqual(j?.percentual, 100)
        XCTAssertNil(UsoCodex.parse(#"{"payload":{"rate_limits":{"primary":{"window_minutes":1e30,"used_percent":5,"resets_at":1794500000}}}}"#))
        let m = UsoClaude.parse(Data(#"{"measured_at":"2026-11-10T10:00:00Z","profiles":{"leo":{"util_7d":1e30,"reset_7d":1}}}"#.utf8))
        XCTAssertEqual(m?.perfis["leo"]?.semana, 100)
    }
}

final class ContadorDeChamadas: @unchecked Sendable {
    private let t = NSLock(); private var n = 0
    func proximo() -> Int { t.lock(); defer { t.unlock() }; n += 1; return n }
    var valor: Int { t.lock(); defer { t.unlock() }; return n }
}
final class ExecutorMutavel: Executor, @unchecked Sendable {
    private let t = NSLock(); private var _s: String; private var _st: Int32 = 0; private var _n = 0
    init(_ s: String) { _s = s }
    var saida: String { get { t.lock(); defer { t.unlock() }; return _s } set { t.lock(); _s = newValue; t.unlock() } }
    var status: Int32 { get { t.lock(); defer { t.unlock() }; return _st } set { t.lock(); _st = newValue; t.unlock() } }
    /// Quantas vezes algum comando foi rodado.
    var chamadas: Int { t.lock(); defer { t.unlock() }; return _n }
    func rodar(_ comando: String) -> SaidaShell { t.lock(); _n += 1; t.unlock(); return SaidaShell(status: status, saida: saida) }
}
