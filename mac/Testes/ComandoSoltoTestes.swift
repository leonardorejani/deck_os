import XCTest
@testable import Nucleo

/// Tecla de comando lenta (o "mudar foco" fecha apps e desliga o Colima, passa de 10 s): o pedido do iPhone não pode esperar
/// o comando acabar, o comando não pode ser derrubado no meio e o estado da tecla tem que mostrar o que está acontecendo.
final class ComandoSoltoTestes: XCTestCase {
    private func tecla(desligar: String? = "foco trabalho", estado: String? = nil) -> Tecla {
        Tecla(id: "foco", nome: "Mudar foco", tipo: "comando", valor: "foco jogo", estado: estado, icone: nil, desligar: desligar)
    }

    private func executor(_ f: Executor, _ m: MemoriaLigaDesliga, _ a: ComandosEmAndamento, graca: TimeInterval = 0.2) -> ExecutorAcoes {
        ExecutorAcoes(shell: f, limiteSegundos: 10, shellDoUsuario: { "/bin/zsh" }, memoria: m, graca: graca, tetoSegundos: 600, andamento: a)
    }

    private func esperar(_ ate: TimeInterval = 5, _ condicao: () -> Bool) {
        let fim = Date().addingTimeInterval(ate)
        while !condicao() && Date() < fim { Thread.sleep(forTimeInterval: 0.02) }
    }

    func testComandoLentoRespondeNaHoraELigaDepoisDeTerminar() {
        let f = ExecutorFalso([("foco jogo", SaidaShell(status: 0, saida: "")), ("foco trabalho", SaidaShell(status: 0, saida: ""))], atraso: { _ in 1.0 })
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        let ex = executor(f, m, a)
        let ini = Date()
        XCTAssertNil(ex.executar(tecla()), "comando lento: o pedido responde sem erro")
        XCTAssertLessThan(Date().timeIntervalSince(ini), 0.8, "o pedido não espera o comando acabar")
        XCTAssertEqual(a.foto()["foco"]?.fase, "ligando")
        XCTAssertFalse(m.ligada("foco"), "ainda não terminou: não está ligada")
        esperar { m.ligada("foco") }
        XCTAssertTrue(m.ligada("foco"), "terminou com 0: ligada")
        esperar { a.foto().isEmpty }
        XCTAssertTrue(a.foto().isEmpty)
        // o toque seguinte desliga, também solto
        XCTAssertNil(ex.executar(tecla()))
        XCTAssertEqual(a.foto()["foco"]?.fase, "desligando")
        esperar { !m.ligada("foco") }
        XCTAssertFalse(m.ligada("foco"))
        XCTAssertTrue(f.comandos.last!.contains("foco trabalho"))
    }

    /// O vigia derrubava o comando aos 10 s (status 142), e o "mudar foco" ficava pela metade.
    func testComandoSoltoNaoLevaOPrazoDe10Segundos() {
        let f = ExecutorFalso([("foco jogo", SaidaShell(status: 0, saida: ""))])
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        XCTAssertNil(executor(f, m, a).executar(tecla()))
        let linha = f.comandos.last!
        XCTAssertTrue(linha.contains(" 600 "), "o vigia leva o teto de 10 minutos")
        XCTAssertFalse(linha.contains(" 10 "), "não leva mais o prazo de 10 segundos")
    }

    func testComandoLentoQueFalhaAvisaPeloEstadoEPorUmTempo() {
        let f = ExecutorFalso([("foco jogo", SaidaShell(status: 3, saida: "Spotify: nao fechou"))], atraso: { _ in 0.6 })
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        XCTAssertNil(executor(f, m, a).executar(tecla()))
        esperar { a.foto()["foco"]?.fase == "falhou" }
        let falha = a.foto()["foco"]
        XCTAssertEqual(falha?.fase, "falhou")
        XCTAssertEqual(falha?.erro, "O comando falhou: Spotify: nao fechou")
        XCTAssertFalse(m.ligada("foco"), "falhou: não fica ligada")
        XCTAssertTrue(a.foto(agora: Date().addingTimeInterval(ComandosEmAndamento.validadeDaFalha + 1)).isEmpty, "a falha some do estado")
    }

    /// Comando rápido segue como sempre: o erro volta no próprio pedido, sem sobrar nada no estado.
    func testComandoRapidoQueFalhaDevolveOErroNoPedido() {
        let f = ExecutorFalso([("foco jogo", SaidaShell(status: 1, saida: "deu ruim"))])
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        XCTAssertEqual(executor(f, m, a, graca: 2).executar(tecla()), "O comando falhou: deu ruim")
        XCTAssertTrue(a.foto().isEmpty)
    }

    func testToqueEnquantoRodaNaoDisparaDeNovo() {
        let f = ExecutorFalso([("foco jogo", SaidaShell(status: 0, saida: ""))], atraso: { _ in 0.8 })
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        let ex = executor(f, m, a)
        XCTAssertNil(ex.executar(tecla()))
        XCTAssertEqual(ex.executar(tecla()), "Mudar foco ainda está ligando. Espere terminar.")
        esperar { a.foto().isEmpty }
        XCTAssertEqual(f.comandos.filter { $0.contains("foco jogo") }.count, 1, "o comando rodou uma vez só")
    }

    func testComandoSemDesligarMostraRodando() {
        let f = ExecutorFalso([("limpar", SaidaShell(status: 0, saida: ""))], atraso: { _ in 0.6 })
        let a = ComandosEmAndamento()
        let t = Tecla(id: "l", nome: "Limpar", tipo: "comando", valor: "limpar", estado: nil, icone: nil)
        XCTAssertNil(executor(f, MemoriaLigaDesliga(), a).executar(t))
        XCTAssertEqual(a.foto()["l"]?.fase, "rodando")
        esperar { a.foto().isEmpty }
        XCTAssertTrue(a.foto().isEmpty)
    }

    func testEstadoTrazOAndamentoSoDasTeclasDoPerfil() {
        let f = Fontes(
            sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
            whatsapp: { Leitura(valor: nil, aviso: nil) }, seloWhatsApp: { nil },
            spotify: { _ in Leitura(valor: nil, aviso: nil) }, capa: { nil }, agenda: { _ in Leitura(valor: nil, aviso: nil) },
            acesas: { _ in [] },
            andamento: { ["foco": AndamentoDeTecla(fase: "ligando"), "outra": AndamentoDeTecla(fase: "rodando")] })
        let cfg = config(perfil: [tecla()])
        let e = Agregador(fontes: f).estado(config: cfg, agora: Date())
        XCTAssertEqual(e.andamento, ["foco": AndamentoDeTecla(fase: "ligando")])
        let vazio = Agregador(fontes: Fontes(
            sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
            whatsapp: { Leitura(valor: nil, aviso: nil) }, seloWhatsApp: { nil },
            spotify: { _ in Leitura(valor: nil, aviso: nil) }, capa: { nil }, agenda: { _ in Leitura(valor: nil, aviso: nil) },
            acesas: { _ in [] })).estado(config: cfg, agora: Date())
        XCTAssertNil(vazio.andamento, "sem nada rodando o campo nem vai no JSON")
    }

    /// Processo de verdade: um comando de 3 s com o prazo do shell em 1 s. Antes ele era derrubado e o marcador nunca aparecia.
    func testProcessoRealLentoTerminaSemSerDerrubado() throws {
        let marca = try pastaTemporaria().appendingPathComponent("terminou").path
        let m = MemoriaLigaDesliga(), a = ComandosEmAndamento()
        let ex = ExecutorAcoes(shell: ExecutorShell(), limiteSegundos: 1, shellDoUsuario: { "/bin/zsh" }, memoria: m, graca: 0.3, tetoSegundos: 60, andamento: a)
        let t = Tecla(id: "foco", nome: "Mudar foco", tipo: "comando", valor: "sleep 3; touch '\(marca)'", estado: nil, icone: nil, desligar: "true")
        XCTAssertNil(ex.executar(t))
        XCTAssertEqual(a.foto()["foco"]?.fase, "ligando")
        esperar(15) { m.ligada("foco") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marca), "o comando foi até o fim")
        XCTAssertTrue(m.ligada("foco"))
    }
}
