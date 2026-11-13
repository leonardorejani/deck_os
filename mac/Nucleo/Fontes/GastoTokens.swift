import Foundation

/// Tokens de um conjunto de mensagens, separados pelo que cada tipo custa.
struct Contagem: Codable, Equatable, Sendable {
    var entrada = 0
    var saida = 0
    var leitura = 0
    var escrita5m = 0
    var escrita1h = 0
    var turnos = 0

    var escrita: Int { escrita5m + escrita1h }
    var total: Int { entrada + saida + leitura + escrita }

    static func += (a: inout Contagem, b: Contagem) {
        a.entrada += b.entrada; a.saida += b.saida; a.leitura += b.leitura
        a.escrita5m += b.escrita5m; a.escrita1h += b.escrita1h; a.turnos += b.turnos
    }
}

enum FonteDeGasto: String, Sendable { case claude, codex }

/// Uma resposta de IA com o que ela gastou, já lida de uma linha de log.
struct EventoDeUso: Equatable, Sendable {
    var quando: Date
    var modelo: String
    var contagem: Contagem
    /// Identifica a resposta (id da mensagem e do pedido) para não somar duas vezes a mesma. nil: sem como identificar.
    var chave: String?
}

/// Lê as linhas dos logs que o Claude Code e o Codex gravam neste Mac. Só números saem daqui:
/// nenhum texto de conversa, pasta ou nome de projeto é guardado.
enum LeitorDeGasto {
    private static func inteiro(_ v: Any?) -> Int {
        if let i = v as? Int { return max(0, i) }
        if let d = v as? Double, d.isFinite { return max(0, Int(min(d, 9e15))) }
        return 0
    }

    static func hash(_ texto: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in texto.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }

    private static let marcaUsage = Data("\"usage\"".utf8)
    private static let marcaContagem = Data("token_count".utf8)
    private static let marcaTurno = Data("turn_context".utf8)

    /// Linha do Claude Code: resposta do assistente com `message.usage`.
    static func linhaClaude(_ linha: Data) -> EventoDeUso? {
        guard linha.range(of: marcaUsage) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: linha)) as? [String: Any],
              let msg = obj["message"] as? [String: Any], let uso = msg["usage"] as? [String: Any],
              let modelo = msg["model"] as? String, !modelo.hasPrefix("<"), !modelo.isEmpty,
              let quando = (obj["timestamp"] as? String).flatMap(Datas.ler) else { return nil }
        var c = Contagem(entrada: inteiro(uso["input_tokens"]), saida: inteiro(uso["output_tokens"]),
                         leitura: inteiro(uso["cache_read_input_tokens"]), turnos: 1)
        if let cc = uso["cache_creation"] as? [String: Any], cc["ephemeral_5m_input_tokens"] != nil || cc["ephemeral_1h_input_tokens"] != nil {
            c.escrita5m = inteiro(cc["ephemeral_5m_input_tokens"]); c.escrita1h = inteiro(cc["ephemeral_1h_input_tokens"])
        } else {
            c.escrita5m = inteiro(uso["cache_creation_input_tokens"])
        }
        guard c.total > 0 else { return nil }
        var chave: String?
        if let id = msg["id"] as? String, !id.isEmpty { chave = id + "|" + ((obj["requestId"] as? String) ?? "") }
        return EventoDeUso(quando: quando, modelo: modelo, contagem: c, chave: chave)
    }

    /// O que o Codex precisa lembrar de uma linha para a outra do mesmo arquivo.
    struct MemoriaCodex: Equatable, Sendable {
        var modelo: String?
        var totalVisto = 0
    }

    /// Linha do Codex. `turn_context` diz o modelo, `token_count` traz o gasto. O mesmo token_count volta repetido sem
    /// o total crescer, então só vale quando `total_token_usage.total_tokens` aumenta. `input_tokens` já inclui o cache lido.
    static func linhaCodex(_ linha: Data, memoria: inout MemoriaCodex) -> EventoDeUso? {
        let temTurno = linha.range(of: marcaTurno) != nil
        guard temTurno || linha.range(of: marcaContagem) != nil,
              let obj = (try? JSONSerialization.jsonObject(with: linha)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }
        if temTurno, let m = payload["model"] as? String, !m.isEmpty { memoria.modelo = m }
        guard (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = (info["total_token_usage"] as? [String: Any]).map({ inteiro($0["total_tokens"]) }),
              total > memoria.totalVisto else { return nil }
        memoria.totalVisto = total
        guard let ultimo = info["last_token_usage"] as? [String: Any],
              let quando = (obj["timestamp"] as? String).flatMap(Datas.ler) else { return nil }
        let entrada = inteiro(ultimo["input_tokens"]), lido = inteiro(ultimo["cached_input_tokens"])
        let c = Contagem(entrada: max(0, entrada - lido), saida: inteiro(ultimo["output_tokens"]), leitura: lido, turnos: 1)
        guard c.total > 0 else { return nil }
        return EventoDeUso(quando: quando, modelo: memoria.modelo ?? "desconhecido", contagem: c, chave: nil)
    }
}

// MARK: - O que fica guardado

/// Por arquivo de log: até onde já foi lido e, no Codex, o modelo e o total de antes.
struct EstadoDeArquivo: Codable, Equatable, Sendable {
    var tamanho: Int64
    var offset: Int64
    var id: UInt32
    var modelo: String?
    var totalVisto: Int = 0
}

struct Celula: Codable, Equatable, Sendable {
    var h: Int
    var m: String
    var c: Contagem
}

/// Tudo de uma fonte (Claude ou Codex): os totais por hora e modelo, os arquivos lidos e as respostas já contadas.
struct BancoDeGasto: Sendable {
    var arquivos: [String: EstadoDeArquivo] = [:]
    var horas: [String: [String: Contagem]] = [:]   // "hora" -> modelo -> contagem
    var sessoes: [Int: Set<UInt32>] = [:]
    var vistos: [UInt64: Int] = [:]                 // resposta já somada -> hora dela

    mutating func somar(_ e: EventoDeUso, hora: Int, arquivo: UInt32) {
        horas[String(hora), default: [:]][e.modelo, default: Contagem()] += e.contagem
        sessoes[hora, default: []].insert(arquivo)
    }

    /// Joga fora o que é mais velho que a janela guardada.
    mutating func podar(antesDaHora corte: Int) {
        horas = horas.filter { (Int($0.key) ?? 0) >= corte }
        sessoes = sessoes.filter { $0.key >= corte }
        vistos = vistos.filter { $0.value >= corte }
    }
}

private struct BancoGravado: Codable {
    var arquivos: [String: EstadoDeArquivo]
    var celulas: [Celula]
    var sessoes: [Int: [UInt32]]
    var vistos: [[Int]]   // [hash como Int, hora], para ficar pequeno no JSON

    init(_ b: BancoDeGasto) {
        arquivos = b.arquivos
        celulas = b.horas.flatMap { h, ms in ms.map { Celula(h: Int(h) ?? 0, m: $0.key, c: $0.value) } }
        sessoes = b.sessoes.mapValues { Array($0) }
        vistos = b.vistos.map { [Int(bitPattern: UInt($0.key)), $0.value] }
    }

    func banco() -> BancoDeGasto {
        var b = BancoDeGasto()
        b.arquivos = arquivos
        for c in celulas { b.horas[String(c.h), default: [:]][c.m] = c.c }
        b.sessoes = sessoes.mapValues { Set($0) }
        for v in vistos where v.count == 2 { b.vistos[UInt64(UInt(bitPattern: v[0]))] = v[1] }
        return b
    }
}

private struct ArquivoDeCache: Codable {
    var v = 1
    var atualizadoEm: Double?
    var claude: BancoGravado
    var codex: BancoGravado
}

// MARK: - Varredura

/// O gasto de tokens do Claude Code e do Codex por dia, semana e mês, lido dos logs locais com cache incremental em disco:
/// na primeira vez só abre arquivo mexido nos últimos 31 dias, e depois só o trecho novo de cada um. Quem pergunta nunca espera
/// a varredura: recebe o que já foi somado, e `disparar` atualiza em segundo plano no máximo a cada 60 s.
final class GastoTokens: @unchecked Sendable {
    static let diasGuardados = 31
    static let intervaloMinimo: TimeInterval = 60

    private let raizClaude: URL
    private let raizCodex: URL
    private let arquivoDeCache: URL?
    private let trava = NSLock()
    private let fila = DispatchQueue(label: "deck.gasto-tokens", qos: .utility)
    private var claude = BancoDeGasto()
    private var codex = BancoDeGasto()
    private var carregado = false
    private var rodando = false
    private var concluidaUmaVez = false
    private var ultimoInicio: Date?
    private var ultimaVarredura: Date?

    init(raizClaude: URL, raizCodex: URL, pastaDeCache: URL?) {
        self.raizClaude = raizClaude
        self.raizCodex = raizCodex
        self.arquivoDeCache = pastaDeCache?.appendingPathComponent("uso-gasto.json")
    }

    /// Pede uma atualização em segundo plano. Não faz nada se já há uma rodando ou se a última começou há menos de 60 s.
    func disparar(agora: Date = Date()) {
        trava.lock()
        if rodando || (ultimoInicio.map { agora.timeIntervalSince($0) < Self.intervaloMinimo } ?? false) { trava.unlock(); return }
        rodando = true; ultimoInicio = agora
        trava.unlock()
        fila.async { [self] in
            atualizar(agora: agora)
            trava.lock(); rodando = false; trava.unlock()
        }
    }

    /// true enquanto ainda não há nenhuma varredura completa e nada vindo do disco: a tela mostra "calculando".
    var calculando: Bool {
        trava.lock(); defer { trava.unlock() }
        return rodando && !concluidaUmaVez
    }

    var atualizadoEm: Date? {
        trava.lock(); defer { trava.unlock() }
        return ultimaVarredura
    }

    /// A varredura inteira, na thread de quem chamou (os testes usam direto, o app usa `disparar`).
    func atualizar(agora: Date = Date()) {
        carregarDoDisco()
        let corte = Int(agora.addingTimeInterval(-Double(Self.diasGuardados) * 86_400).timeIntervalSince1970 / 3600)
        for fonte in [FonteDeGasto.claude, .codex] {
            trava.lock(); var banco = fonte == .claude ? claude : codex; trava.unlock()
            varrer(fonte, raiz: fonte == .claude ? raizClaude : raizCodex, banco: &banco, corte: corte) { parcial in
                self.trava.lock(); if fonte == .claude { self.claude = parcial } else { self.codex = parcial }; self.trava.unlock()
            }
        }
        trava.lock(); concluidaUmaVez = true; ultimaVarredura = agora; trava.unlock()
        gravarNoDisco(agora: agora)
    }

    private func varrer(_ fonte: FonteDeGasto, raiz: URL, banco: inout BancoDeGasto, corte: Int, publicar: (BancoDeGasto) -> Void) {
        let limite = Date(timeIntervalSince1970: Double(corte) * 3600)
        var presentes: [String: (URL, Int64)] = [:]
        if let it = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in it where url.pathExtension == "jsonl" {
                let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                guard v?.isRegularFile == true, let m = v?.contentModificationDate, m >= limite else { continue }
                presentes[String(LeitorDeGasto.hash(url.path), radix: 16)] = (url, Int64(v?.fileSize ?? 0))
            }
        }
        banco.arquivos = banco.arquivos.filter { presentes[$0.key] != nil }
        // ordem fixa: quando duas sessões trazem a mesma resposta, quem a conta é sempre o mesmo arquivo
        for (chave, (url, tamanho)) in presentes.sorted(by: { $0.value.0.path < $1.value.0.path }) {
            var est = banco.arquivos[chave] ?? EstadoDeArquivo(tamanho: 0, offset: 0, id: UInt32(truncatingIfNeeded: LeitorDeGasto.hash(url.path)))
            if tamanho < est.offset { est = EstadoDeArquivo(tamanho: 0, offset: 0, id: est.id) } // arquivo recomeçou
            guard tamanho > est.offset else { banco.arquivos[chave] = est; continue }
            lerArquivo(url, fonte: fonte, estado: &est, banco: &banco, corte: corte)
            est.tamanho = tamanho
            banco.arquivos[chave] = est
            publicar(banco)
        }
        banco.podar(antesDaHora: corte)
        publicar(banco)
    }

    /// Lê do offset até o fim, em blocos, e só avança até a última linha inteira (linha pela metade fica para a próxima vez).
    private func lerArquivo(_ url: URL, fonte: FonteDeGasto, estado: inout EstadoDeArquivo, banco: inout BancoDeGasto, corte: Int) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: UInt64(estado.offset))) != nil else { return }
        var memoria = LeitorDeGasto.MemoriaCodex(modelo: estado.modelo, totalVisto: estado.totalVisto)
        var pendente = Data()
        var posicao = estado.offset
        func tratar(_ linha: Data) {
            let evento = fonte == .claude ? LeitorDeGasto.linhaClaude(linha) : LeitorDeGasto.linhaCodex(linha, memoria: &memoria)
            guard let e = evento else { return }
            let hora = Int(e.quando.timeIntervalSince1970 / 3600)
            guard hora >= corte else { return }
            if let k = e.chave {
                let hk = LeitorDeGasto.hash(k)
                if banco.vistos[hk] != nil { return }
                banco.vistos[hk] = hora
            }
            banco.somar(e, hora: hora, arquivo: estado.id)
        }
        while let bloco = try? h.read(upToCount: 4 << 20), !bloco.isEmpty {
            pendente.append(bloco)
            var ini = pendente.startIndex
            while let fim = pendente[ini...].firstIndex(of: 10) {
                tratar(pendente[ini..<fim])
                posicao += Int64(fim - ini + 1)
                ini = fim + 1
            }
            pendente = Data(pendente[ini...])
        }
        estado.offset = posicao
        estado.modelo = memoria.modelo
        estado.totalVisto = memoria.totalVisto
    }

    // MARK: Disco

    private func carregarDoDisco() {
        trava.lock(); defer { trava.unlock() }
        guard !carregado else { return }
        carregado = true
        guard let url = arquivoDeCache, let dados = try? Data(contentsOf: url),
              let a = try? JSONDecoder().decode(ArquivoDeCache.self, from: dados), a.v == 1 else { return }
        claude = a.claude.banco(); codex = a.codex.banco()
        ultimaVarredura = a.atualizadoEm.map { Date(timeIntervalSince1970: $0) }
        concluidaUmaVez = ultimaVarredura != nil
    }

    /// Para quem só consulta: traz o que ficou no disco da última vez, sem varrer nada.
    func carregarSemVarrer() { carregarDoDisco() }

    private func gravarNoDisco(agora: Date) {
        guard let url = arquivoDeCache else { return }
        trava.lock()
        let a = ArquivoDeCache(atualizadoEm: agora.timeIntervalSince1970, claude: BancoGravado(claude), codex: BancoGravado(codex))
        trava.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let dados = try? JSONEncoder().encode(a) { try? dados.write(to: url, options: .atomic) }
    }

    // MARK: Consulta

    func consultar(_ fonte: FonteDeGasto, periodo: PeriodoUso, agora: Date, calendario: Calendar = .current) -> GastoPeriodo {
        trava.lock(); let banco = fonte == .claude ? claude : codex; trava.unlock()
        return GastoPeriodo.montar(banco: banco, periodo: periodo, agora: agora, calendario: calendario)
    }
}

// MARK: - Resposta

enum PeriodoUso: String, Sendable {
    case dia, semana, mes

    /// Quantas barras o gráfico tem: horas do dia, ou dias da semana e do mês.
    var barras: Int { switch self { case .dia: return 24; case .semana: return 7; case .mes: return 30 } }
}

struct ModeloDeUso: Codable, Equatable, Sendable {
    var nome: String
    var tokens: Int
    /// Dólares estimados. nil: modelo fora da tabela de preços.
    var custo: Double?
    /// Percentual dos tokens do período, de 0 a 100.
    var parte: Int
}

struct GastoPeriodo: Codable, Equatable, Sendable {
    var entrada: Int
    var saida: Int
    var cacheLeitura: Int
    var cacheEscrita: Int
    var total: Int
    var turnos: Int
    var sessoes: Int
    /// Dólares estimados a preço de API. nil: nenhum modelo do período está na tabela.
    var custo: Double?
    /// true: parte dos tokens é de modelo sem preço, então o custo está subestimado.
    var custoParcial: Bool?
    /// Tokens por barra: 24 horas (dia), 7 dias (semana) ou 30 dias (mês), do mais antigo ao de agora.
    var serie: [Int]
    var modelos: [ModeloDeUso]

    static let vazio = GastoPeriodo(entrada: 0, saida: 0, cacheLeitura: 0, cacheEscrita: 0, total: 0, turnos: 0, sessoes: 0, custo: nil, custoParcial: nil, serie: [], modelos: [])

    static func montar(banco: BancoDeGasto, periodo: PeriodoUso, agora: Date, calendario cal: Calendar) -> GastoPeriodo {
        let hoje = cal.startOfDay(for: agora)
        let inicio: Date
        switch periodo {
        case .dia: inicio = hoje
        case .semana: inicio = cal.date(byAdding: .day, value: -6, to: hoje) ?? hoje
        case .mes: inicio = cal.date(byAdding: .day, value: -29, to: hoje) ?? hoje
        }
        let fim = agora.addingTimeInterval(3600)
        var serie = [Int](repeating: 0, count: periodo.barras)
        var total = Contagem(), porModelo: [String: Contagem] = [:], horasUsadas = Set<Int>()
        for (chaveHora, modelos) in banco.horas {
            guard let hora = Int(chaveHora) else { continue }
            let quando = Date(timeIntervalSince1970: Double(hora) * 3600)
            guard quando >= inicio.addingTimeInterval(-1), quando < fim else { continue }
            let barra = periodo == .dia ? cal.component(.hour, from: quando)
                : max(0, cal.dateComponents([.day], from: inicio, to: cal.startOfDay(for: quando)).day ?? 0)
            guard barra >= 0, barra < serie.count else { continue }
            horasUsadas.insert(hora)
            for (modelo, c) in modelos {
                serie[barra] += c.total
                total += c
                porModelo[PrecosModelos.rotulo(modelo), default: Contagem()] += c
            }
        }
        // Custo pelo modelo de verdade (versões de um mesmo rótulo podem ter preços diferentes).
        var custo = 0.0, algumPreco = false, semPreco = false
        var custoPorRotulo: [String: Double] = [:], semPrecoRotulo = Set<String>()
        for (chaveHora, modelos) in banco.horas {
            guard let hora = Int(chaveHora), horasUsadas.contains(hora) else { continue }
            for (modelo, c) in modelos {
                let rot = PrecosModelos.rotulo(modelo)
                if let v = PrecosModelos.custo(modelo: modelo, c) { custo += v; algumPreco = true; custoPorRotulo[rot, default: 0] += v }
                else if c.total > 0 { semPreco = true; semPrecoRotulo.insert(rot) }
            }
        }
        var linhas = porModelo.map { (rot, c) in
            ModeloDeUso(nome: rot, tokens: c.total, custo: semPrecoRotulo.contains(rot) ? nil : custoPorRotulo[rot].map(arredondar),
                        parte: total.total > 0 ? Int((Double(c.total) / Double(total.total) * 100).rounded()) : 0)
        }.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.nome < $1.nome }
        if linhas.count > 5 {
            let resto = linhas[4...]
            let outros = ModeloDeUso(nome: "Outros", tokens: resto.reduce(0) { $0 + $1.tokens },
                                     custo: resto.contains { $0.custo == nil } ? nil : arredondar(resto.reduce(0) { $0 + ($1.custo ?? 0) }),
                                     parte: resto.reduce(0) { $0 + $1.parte })
            linhas = Array(linhas[..<4]) + [outros]
        }
        var sessoes = Set<UInt32>()
        for h in horasUsadas { sessoes.formUnion(banco.sessoes[h] ?? []) }
        return GastoPeriodo(entrada: total.entrada, saida: total.saida, cacheLeitura: total.leitura, cacheEscrita: total.escrita,
                            total: total.total, turnos: total.turnos, sessoes: sessoes.count,
                            custo: algumPreco ? arredondar(custo) : nil, custoParcial: algumPreco && semPreco ? true : nil,
                            serie: serie, modelos: linhas)
    }

    private static func arredondar(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}
