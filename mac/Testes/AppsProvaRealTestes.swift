#if os(macOS)
import XCTest
@testable import Nucleo

/// Prova no Mac de verdade: DECK_PROVA_REAL=1 swift test --filter AppsProvaRealTestes
/// Só lê: lista os apps, tira um ícone e lista as contas do Mail (só os nomes, nada de mensagem).
/// Não abre janela nem executa tecla: a ação de abrir a caixa de entrada fica de fora.
final class AppsProvaRealTestes: XCTestCase {
    func testProvaReal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DECK_PROVA_REAL"] == "1", "defina DECK_PROVA_REAL=1")
        let apps = AppsDoMac(pastaDeCache: FileManager.default.temporaryDirectory.appendingPathComponent("deck-prova-icones-\(UUID().uuidString)"))

        let lista = apps.apps()
        print("PROVA apps instalados: \(lista.count)")
        XCTAssertGreaterThan(lista.count, 10)
        for valor in ["Calculator", "Safari", "Mail", "Notes", "Calendar", "Finder", "Google Chrome"] {
            let a = lista.first { $0.valor == valor }
            print("PROVA \(valor): \(a.map { "\($0.nome) | \($0.bundle) | navegador=\($0.navegador)" } ?? "nao instalado")")
        }
        let navegadores = lista.filter(\.navegador).map(\.nome)
        print("PROVA navegadores achados: \(navegadores.joined(separator: ", "))")
        XCTAssertTrue(navegadores.contains("Safari"))

        let png = try XCTUnwrap(apps.icone(bundle: "com.apple.calculator"))
        print("PROVA icone da Calculadora: \(png.count) bytes, cabecalho \(png.prefix(4).map { String($0, radix: 16) }.joined(separator: " "))")
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertNil(apps.icone(bundle: "com.nao.existe"))

        let g = try XCTUnwrap(apps.acoes(bundle: "com.apple.Safari"))
        print("PROVA acoes do Safari: \(g.map(\.id))")
        XCTAssertEqual(g.map(\.id), ["link", "gmail"])
        print("PROVA acoes do Calendario: \(try XCTUnwrap(apps.acoes(bundle: "com.apple.iCal")).map(\.id))")
        print("PROVA acoes do Finder: \(try XCTUnwrap(apps.acoes(bundle: "com.apple.finder")).map(\.id))")
        XCTAssertNil(apps.acoes(bundle: "com.nao.existe"))

        // Mail e Notas: o catálogo abre o app escondido se preciso e lê a lista por AppleScript.
        // Mail sem nenhuma conta (como neste Mac) responde com o aviso de vazio, e nunca com erro de permissão.
        func lerLista(_ bundle: String, _ id: String, processo: String) throws -> AcaoDisponivel {
            let estavaAberto = ExecutorShell().rodar("pgrep -x \(processo) >/dev/null").status == 0
            let acoes = try XCTUnwrap(apps.acoes(bundle: bundle))
            let acao = try XCTUnwrap(acoes.first { $0.id == id })
            print("PROVA \(processo) estava aberto: \(estavaAberto)")
            if !estavaAberto { _ = ExecutorShell().rodar(#"osascript -e 'tell application id "\#(bundle)" to quit'"#) }
            return acao
        }
        let caixa = try lerLista("com.apple.mail", "mail-caixa", processo: "Mail")
        print("PROVA contas do Mail (so os nomes): \((caixa.opcoes ?? []).map(\.nome))")
        print("PROVA aviso do Mail: \(caixa.aviso ?? "nenhum")")
        XCTAssertTrue(caixa.aviso == nil || caixa.aviso == "Nenhuma conta configurada no Mail. Adicione uma conta no app Mail.")

        let pastas = try lerLista("com.apple.Notes", "notas-pasta", processo: "Notes")
        print("PROVA pastas das Notas: \((pastas.opcoes ?? []).count), contas: \(Set((pastas.opcoes ?? []).compactMap(\.detalhe)).sorted())")
        print("PROVA aviso das Notas: \(pastas.aviso ?? "nenhum")")
        XCTAssertNil(pastas.aviso)
        XCTAssertFalse((pastas.opcoes ?? []).isEmpty)
    }
}
#endif
