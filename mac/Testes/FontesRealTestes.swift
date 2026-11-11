import XCTest
@testable import Nucleo

/// Prova contra este Mac, só leitura. Só roda com DECK_PROVA_REAL=1 (no CI e no Linux fica pulado).
/// Imprime contagens e se os campos estão vazios, nunca o conteúdo de mensagem nem de pergunta.
///   DECK_PROVA_REAL=1 swift test --package-path mac --filter FontesRealTestes
final class FontesRealTestes: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DECK_PROVA_REAL"] == "1", "prova real desligada")
    }

    func testLeOsDadosDesteMac() {
        let casa = NSHomeDirectory()
        let f = Fontes.vivas(casa: casa)
        let agora = Date()
        func t<T>(_ nome: String, _ bloco: () -> T) -> T {
            let t0 = Date(); let r = bloco()
            print("[\(nome)] \(Int(Date().timeIntervalSince(t0) * 1000)) ms"); return r
        }

        let s = t("sessoes") { f.sessoes() }
        print("sessoes: \(s.valor.count) esperando, perguntas vazias: \(s.valor.filter { $0.pergunta.isEmpty }.count), projeto vazio: \(s.valor.filter { $0.projeto.isEmpty }.count), aviso: \(s.aviso?.texto ?? "nenhum")")
        if let p = s.valor.first { print("sessoes[0] (mais recente): desde=\(p.desde) id=\(p.id)") }
        if let u = s.valor.last { print("sessoes[ultima] (mais antiga): desde=\(u.desde)") }

        let contas = [ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo"),
                      ContaIA(id: "claude-equipe", nome: "Claude", conta: "equipe", perfil: "equipe"),
                      ContaIA(id: "codex", nome: "Codex", conta: "pro")]
        let u = t("uso") { f.uso(contas, agora) }
        for c in u.valor { print("uso: \(c.id) semana=\(c.semana.map(String.init) ?? "nil") renova=\(c.renova ?? "nil")") }
        print("uso aviso: \(u.aviso?.texto ?? "nenhum")")

        let w = t("whatsapp") { f.whatsapp() }
        if let d = w.valor {
            print("whatsapp: total=\(d.resumo.total) conversas=\(d.resumo.conversas) grupos=\(d.conversas.filter(\.grupo).count) mensagens=\(d.conversas.map { $0.mensagens.count }.reduce(0, +)) conversasSemMensagem=\(d.conversas.filter { $0.mensagens.isEmpty }.count) nomesVazios=\(d.conversas.filter { $0.nome.isEmpty }.count) mensagensEmGrupoSemRemetente=\(d.conversas.filter(\.grupo).flatMap(\.mensagens).filter { $0.de.isEmpty }.count)")
            let incoerentes = d.conversas.filter { $0.mensagens.count > $0.naoLidas }.count
            print("whatsapp: conversas com mais mensagens que naoLidas: \(incoerentes)")
        }
        print("whatsapp aviso: \(w.aviso?.texto ?? "nenhum")")
        print("selo do Dock (WhatsApp): \(f.seloWhatsApp().map(String.init) ?? "nil (app fechado ou sem selo)")")

        let sp = t("spotify") { f.spotify(agora) }
        if let e = sp.valor {
            print("spotify: tocando=\(e.tocando) faixaVazia=\(e.faixa.isEmpty) artistaVazio=\(e.artista.isEmpty) posicao=\(e.posicao) duracao=\(e.duracao) capaId=\(e.capaId ?? "nil") cores=\(e.cores) bytesDaCapa=\(f.capa()?.count ?? 0)")
        } else { print("spotify: nil (fechado ou sem faixa)") }
        print("spotify aviso: \(sp.aviso?.texto ?? "nenhum")")

        let ag = t("agenda") { f.agenda(agora) }
        print("agenda: \(String(describing: ag.valor)) aviso: \(ag.aviso?.texto ?? "nenhum")")

        let teclas = [Tecla(id: "acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k",
                            estado: "pmset -g assertions | grep -q 'Vorssaint: keep the Mac awake'", icone: nil),
                      Tecla(id: "sempre", nome: "x", tipo: "comando", valor: "true", estado: "true", icone: nil),
                      Tecla(id: "nunca", nome: "x", tipo: "comando", valor: "true", estado: "false", icone: nil)]
        print("acesas: \(t("acesas") { f.acesas(teclas) })")

        var cfg = config(perfil: [Tecla(id: "whats", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: nil),
                                  Tecla(id: "cal", nome: "Calendário", tipo: "app", valor: "Calendar", estado: nil, icone: nil)] + teclas, contas: contas)
        cfg.perfilAtivo = "p"
        let ag2 = Agregador(fontes: f)
        let e1 = t("estado (frio)") { ag2.estado(config: cfg, agora: agora) }
        let e2 = t("estado (cache)") { ag2.estado(config: cfg, agora: agora.addingTimeInterval(1)) }
        print("estado: spotify=\(e1.spotify != nil) uso=\(e1.uso.count) sessoes=\(e1.sessoes.count) whatsapp=\(String(describing: e1.whatsapp)) agenda=\(String(describing: e1.agenda)) acesas=\(e1.acesas) selos=\(e1.selos)")
        print("estado avisos: \(e1.avisos.map { $0.fonte })")
        XCTAssertEqual(e1.acesas, e2.acesas)
        let json = try? JSONEncoder().encode(e1)
        print("estado como JSON: \(json?.count ?? 0) bytes")
    }
}
