import Foundation

/// Guarda um valor por alguns segundos. Chave diferente (ex.: a lista de contas mudou) invalida.
final class Cache<Chave: Equatable & Sendable, Valor: Sendable>: @unchecked Sendable {
    private let validade: TimeInterval
    private let trava = NSLock()
    private var guardado: (chave: Chave, quando: Date, valor: Valor)?
    private var calculando = false

    init(validade: TimeInterval) { self.validade = validade }

    /// Nunca empilha leituras: se uma já está em andamento (fonte travada ou lenta), devolve o último valor
    /// guardado, ou `padrao` se ainda não há nenhum. Vencido o valor, a leitura nova roda em segundo plano e
    /// quem pediu espera só `paciencia`: se a fonte responde nesse prazo o valor é o novo, se não (fonte lenta,
    /// osascript pendurado) devolve o último valor guardado e a leitura termina sozinha. Sem valor guardado
    /// ainda (primeira leitura, ou a chave mudou) espera a fonte, porque não há o que mostrar no lugar.
    func obterAgil(chave: Chave, agora: Date, padrao: Valor, paciencia: TimeInterval, calcular: @escaping @Sendable () -> Valor) -> Valor {
        trava.lock()
        if let g = guardado, g.chave == chave, agora.timeIntervalSince(g.quando) < validade, agora >= g.quando {
            trava.unlock(); return g.valor
        }
        if calculando { let v = guardado?.valor ?? padrao; trava.unlock(); return v }
        let velho = guardado.flatMap { $0.chave == chave ? $0.valor : nil }
        calculando = true
        trava.unlock()
        guard let velho else { let v = calcular(); gravar(v, chave, agora); return v }
        let pronto = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { [self] in
            gravar(calcular(), chave, agora)
            pronto.signal()
        }
        guard pronto.wait(timeout: .now() + paciencia) == .success else { return velho }
        trava.lock(); defer { trava.unlock() }
        return guardado?.valor ?? velho
    }

    private func gravar(_ v: Valor, _ chave: Chave, _ agora: Date) {
        trava.lock(); guardado = (chave, agora, v); calculando = false; trava.unlock()
    }

    func obter(chave: Chave, agora: Date, calcular: () -> Valor) -> Valor {
        trava.lock()
        if let g = guardado, g.chave == chave, agora.timeIntervalSince(g.quando) < validade, agora >= g.quando {
            trava.unlock(); return g.valor
        }
        trava.unlock()
        let v = calcular()
        trava.lock(); guardado = (chave, agora, v); trava.unlock()
        return v
    }

    /// O último valor calculado, mesmo vencido (para as rotas de lista, que não recalculam).
    func ultimo() -> Valor? {
        trava.lock(); defer { trava.unlock() }
        return guardado?.valor
    }
}

/// As fontes do estado. Cada campo é uma função, para o teste trocar por dado de exemplo.
struct Fontes: Sendable {
    var sessoes: @Sendable () -> Leitura<[Sessao]>
    var uso: @Sendable ([ContaIA], Date) -> Leitura<[UsoConta]>
    var whatsapp: @Sendable () -> Leitura<WhatsAppDados?>
    var seloWhatsApp: @Sendable () -> Int?
    var spotify: @Sendable (Date) -> Leitura<EstadoSpotify?>
    var capa: @Sendable () -> Data?
    var agenda: @Sendable (Date) -> Leitura<ResumoAgenda?>
    var acesas: @Sendable ([Tecla]) -> [String]

    /// As fontes de verdade deste Mac. `casa` é a pasta do usuário.
    /// `origemWhatsApp` é quem decide entre o banco do app e o WhatsApp Web: o roteador passa o mesmo
    /// que usa para abrir o WhatsApp, e sem ele vale o automático.
    static func vivas(executor: any Executor = ExecutorShell(), casa: String = NSHomeDirectory(),
                      origemWhatsApp: OrigemWhatsApp? = nil, ponteQR: PonteWhatsAppQR? = nil, complementoSpotify: ComplementoSpotify? = nil,
                      spotifyAberto: (@Sendable () -> Bool)? = nil) -> Fontes {
        let base = URL(fileURLWithPath: casa)
        let jobs = base.appendingPathComponent(".claude/jobs")
        let medicaoClaude = base.appendingPathComponent(".config/claude-account/measure.json")
        let sessoesCodex = base.appendingPathComponent(".codex/sessions")
        let banco = FonteWhatsApp.caminhoPadrao(casa: casa)
        let whats = FonteWhatsAppEscolhida(origem: origemWhatsApp ?? OrigemWhatsApp(executor: executor, banco: banco),
                                           app: FonteWhatsApp(executor: executor, banco: banco), qr: ponteQR)
        // Só o executor de verdade consulta o sistema: com executor falso (teste) o Spotify vale como aberto.
        var aberto: @Sendable () -> Bool = { true }
        if let spotifyAberto { aberto = spotifyAberto } else if executor is ExecutorShell { aberto = { FonteSpotify.spotifyAberto() } }
        let spotify = FonteSpotify(executor: executor, aberto: aberto)
        let agenda = FonteAgenda.viva()
        return Fontes(
            sessoes: { FonteSessoes.ler(raiz: jobs) },
            uso: { contas, agora in FonteUso.ler(contas: contas, claude: medicaoClaude, codex: sessoesCodex, agora: agora) },
            whatsapp: { whats.ler() },
            seloWhatsApp: { Selo.total(executor: executor, app: "WhatsApp") },
            spotify: { agora in
                var leitura = spotify.ler(agora: agora)
                // Com login, a API do Spotify soma curtida, repetição e aparelho (sem travar o estado).
                if let c = complementoSpotify, let v = leitura.valor { leitura.valor = c.aplicar(v, uri: spotify.uriAtual(), agora: agora) }
                return leitura
            },
            capa: { spotify.capa() },
            agenda: { agenda.ler($0) },
            acesas: { TeclasAcesas.ler($0, executor: executor) }
        )
    }
}

/// Monta o Estado do contrato a partir das fontes. O painel pede isso a cada 1 s, então as fontes
/// lentas (WhatsApp, uso, sessões, agenda) ficam em cache por alguns segundos.
final class Agregador: @unchecked Sendable {
    let fontes: Fontes
    private let cacheSessoes = Cache<Int, Leitura<[Sessao]>>(validade: 3)
    private let cacheUso = Cache<[ContaIA], Leitura<[UsoConta]>>(validade: 15)
    private let cacheWhatsApp = Cache<Int, Leitura<WhatsAppDados?>>(validade: 5)
    private let cacheAgenda = Cache<Int, Leitura<ResumoAgenda?>>(validade: 10)

    /// Quanto o estado espera pelas fontes. Passou disso, a fonte que não respondeu entra com o
    /// último valor que deu certo (ou vazia), e o iPhone não fica sem painel por causa de uma só.
    private let limite: TimeInterval
    private let cacheSpotify = Cache<Int, Leitura<EstadoSpotify?>>(validade: 0)
    /// O selo do Dock, que só entra quando o banco do WhatsApp não abre. Também fica em cache e dentro do prazo.
    private let cacheSelo = Cache<Int, Int?>(validade: 5)

    /// Quanto o estado espera uma fonte que já tem valor guardado e venceu: passou disso, o painel recebe o valor
    /// guardado e a leitura nova termina em segundo plano. Fonte lenta atrasa o próprio dado, nunca a conexão.
    private let paciencia: TimeInterval

    init(fontes: Fontes, limite: TimeInterval = 2, paciencia: TimeInterval = 0.5) {
        self.fontes = fontes; self.limite = limite; self.paciencia = paciencia
    }

    private final class Colheita: @unchecked Sendable {
        private let trava = NSLock()
        private var sessoes: Leitura<[Sessao]>?
        private var uso: Leitura<[UsoConta]>?
        private var whatsapp: Leitura<WhatsAppDados?>?
        private var spotify: Leitura<EstadoSpotify?>?
        private var agenda: Leitura<ResumoAgenda?>?
        private var acesas: [String]?
        private var selo: Int?
        func gravar(_ f: (Colheita) -> Void) { trava.lock(); f(self); trava.unlock() }
        func guardar(sessoes v: Leitura<[Sessao]>) { gravar { $0.sessoes = v } }
        func guardar(uso v: Leitura<[UsoConta]>) { gravar { $0.uso = v } }
        func guardar(whatsapp v: Leitura<WhatsAppDados?>) { gravar { $0.whatsapp = v } }
        func guardar(spotify v: Leitura<EstadoSpotify?>) { gravar { $0.spotify = v } }
        func guardar(agenda v: Leitura<ResumoAgenda?>) { gravar { $0.agenda = v } }
        func guardar(acesas v: [String]) { gravar { $0.acesas = v } }
        func guardar(selo v: Int?) { gravar { $0.selo = v } }
        /// Cópia do que já chegou. Fonte lenta ainda escreve depois do limite, então ninguém lê o
        /// objeto vivo: cada campo nil é uma fonte que não respondeu a tempo.
        func foto() -> (Leitura<[Sessao]>?, Leitura<[UsoConta]>?, Leitura<WhatsAppDados?>?, Leitura<EstadoSpotify?>?, Leitura<ResumoAgenda?>?, [String]?, Int?) {
            trava.lock(); defer { trava.unlock() }
            return (sessoes, uso, whatsapp, spotify, agenda, acesas, selo)
        }
    }

    func estado(config: Config, agora: Date = Date()) -> Estado {
        let perfil = config.perfis.first { $0.id == config.perfilAtivo }
        let teclas = perfil?.teclas ?? []
        let b = config.blocos
        let c = Colheita()
        let grupo = DispatchGroup()
        func em(_ trabalho: @escaping @Sendable () -> Void) {
            grupo.enter()
            DispatchQueue.global().async { trabalho(); grupo.leave() }
        }
        let vazioSessoes = Leitura<[Sessao]>(valor: [], aviso: nil)
        let vazioUso = Leitura<[UsoConta]>(valor: [], aviso: nil)
        let vazioWhats = Leitura<WhatsAppDados?>(valor: nil, aviso: nil)
        let vazioSpotify = Leitura<EstadoSpotify?>(valor: nil, aviso: nil)
        let vazioAgenda = Leitura<ResumoAgenda?>(valor: nil, aviso: nil)
        // Bloco desligado nem chega a ler a fonte: o que o Mac esconde, o iPhone não pede.
        // Fonte com valor guardado que venceu só é esperada por `paciencia` (ver obterAgil).
        let p = paciencia
        if b.sessoes { em { c.guardar(sessoes: self.cacheSessoes.obterAgil(chave: 0, agora: agora, padrao: vazioSessoes, paciencia: p) { self.fontes.sessoes() }) } }
        if b.uso { em { c.guardar(uso: self.cacheUso.obterAgil(chave: config.contas, agora: agora, padrao: vazioUso, paciencia: p) { self.fontes.uso(config.contas, agora) }) } }
        if b.whatsapp {
            em {
                let leitura = self.cacheWhatsApp.obterAgil(chave: 0, agora: agora, padrao: vazioWhats, paciencia: p) { self.fontes.whatsapp() }
                c.guardar(whatsapp: leitura)
                // Banco fechado: o selo do Dock dá o total. Roda aqui dentro, no mesmo prazo das outras fontes.
                if leitura.valor == nil { c.guardar(selo: self.cacheSelo.obterAgil(chave: 0, agora: agora, padrao: nil, paciencia: p) { self.fontes.seloWhatsApp() }) }
            }
        }
        // Validade 0: o Spotify é lido a cada pedido, mas só uma leitura por vez e com o último valor de reserva.
        if b.spotify { em { c.guardar(spotify: self.cacheSpotify.obterAgil(chave: 0, agora: agora, padrao: vazioSpotify, paciencia: p) { self.fontes.spotify(agora) }) } }
        if b.agenda { em { c.guardar(agenda: self.cacheAgenda.obterAgil(chave: 0, agora: agora, padrao: vazioAgenda, paciencia: p) { self.fontes.agenda(agora) }) } }
        em { c.guardar(acesas: self.fontes.acesas(teclas)) }
        _ = grupo.wait(timeout: .now() + limite)

        // O que não chegou a tempo cai no último valor bom de cada cache (vazio se nunca houve).
        let (fs, fu, fw, fp, fa, fz, fselo) = c.foto()
        let leituraSessoes = fs ?? cacheSessoes.ultimo() ?? vazioSessoes
        let leituraUso = fu ?? cacheUso.ultimo() ?? vazioUso
        let leituraWhats = fw ?? cacheWhatsApp.ultimo() ?? vazioWhats
        let leituraSpotify = fp ?? cacheSpotify.ultimo() ?? vazioSpotify
        let leituraAgenda = fa ?? cacheAgenda.ultimo() ?? vazioAgenda
        let acesas = fz ?? []

        var avisos: [Aviso] = []
        func avisar(_ a: Aviso?) { if let a, !avisos.contains(a) { avisos.append(a) } }
        if perfil == nil { avisar(Aviso(fonte: "teclas", texto: "O perfil escolhido não existe mais. Escolha outro no Mac.")) }
        if b.sessoes { avisar(leituraSessoes.aviso) }
        if b.uso { avisar(leituraUso.aviso) }
        if b.spotify { avisar(leituraSpotify.aviso) }
        if b.agenda { avisar(leituraAgenda.aviso) }

        // WhatsApp: se o banco não abre, o selo do Dock ainda dá o total (sem separar conversas).
        var resumoWhats: ResumoWhatsApp?
        if b.whatsapp {
            avisar(leituraWhats.aviso)
            if let d = leituraWhats.valor {
                resumoWhats = d.resumo
            } else if let n = fselo ?? (cacheSelo.ultimo() ?? nil) {
                resumoWhats = ResumoWhatsApp(total: n, conversas: n)
            }
        }

        var selos: [String: String] = [:]
        for t in teclas where t.tipo == "app" {
            let app = t.valor.lowercased()
            if app == "whatsapp", let w = resumoWhats, w.total > 0 {
                selos[t.id] = w.total > 99 ? "99+" : String(w.total)
            } else if app == "calendar" || app == "calendário" || app == "calendario", b.agenda, leituraAgenda.valor?.permissao == false {
                selos[t.id] = "!"
            }
        }

        return Estado(
            agora: Datas.iso(agora), nomeMac: config.nomeMac, perfilAtivo: config.perfilAtivo, comp: config.comp, blocos: b,
            spotify: leituraSpotify.valor, uso: leituraUso.valor, sessoes: FonteSessoes.semContexto(leituraSessoes.valor), whatsapp: resumoWhats,
            agenda: leituraAgenda.valor, acesas: acesas, selos: selos, avisos: avisos
        )
    }

    // Para as rotas de lista (GET /api/whatsapp, /api/sessoes, /api/capa, /api/agenda).
    func conversasWhatsApp(agora: Date = Date()) -> [ConversaWhatsApp] {
        cacheWhatsApp.obter(chave: 0, agora: agora) { fontes.whatsapp() }.valor?.conversas ?? []
    }
    func sessoes(agora: Date = Date()) -> [Sessao] {
        cacheSessoes.obter(chave: 0, agora: agora) { fontes.sessoes() }.valor
    }
    func capa() -> Data? { fontes.capa() }
}
