import Foundation

/// Sessões do Claude Code: `~/.claude/jobs/<id>/state.json`. As paradas esperando resposta (`state` = "blocked") vêm sem
/// `situacao`. As outras (working, stopped, done) vêm com `situacao` e `passo`. Só leitura, esses arquivos são do Claude Code.
enum FonteSessoes {
    /// Lê um state.json. Devolve nil se a sessão não está bloqueada ou o arquivo não faz sentido.
    /// `contexto` é o texto da última mensagem da sessão (lido do `timeline.jsonl`, que o parse não vê).
    static func parse(_ dados: Data, pasta: String, contexto: String? = nil) -> Sessao? {
        guard let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              (obj["state"] as? String) == "blocked" else { return nil }
        func texto(_ chave: String) -> String? {
            guard let t = obj[chave] as? String, !t.isEmpty else { return nil }
            return t
        }
        // A pasta do projeto: originCwd é a raiz mesmo quando a sessão roda numa worktree.
        let raiz = texto("originCwd") ?? texto("cwd") ?? ""
        let projeto = raiz.split(separator: "/").last.map(String.init) ?? ""
        // `detail` é o resumo da pergunta. Algumas sessões só trazem `needs`, que é o pedido inteiro.
        let pergunta = texto("detail") ?? texto("needs") ?? ""
        let pedido = texto("needs").flatMap { $0 == pergunta ? nil : Mascara.segredos($0, limite: limitePedido) }
        return Sessao(
            id: pasta,
            nome: texto("name") ?? pasta,
            projeto: projeto,
            pergunta: Mascara.segredos(pergunta, limite: limitePedido),
            desde: texto("updatedAt") ?? texto("createdAt") ?? "",
            pedido: pedido,
            contexto: contexto.flatMap { $0.isEmpty ? nil : $0 },
            sugestao: texto("suggestedReply").map { Mascara.segredos($0, limite: limitePedido) }
        )
    }

    /// Quanto tempo uma sessão que não espera resposta continua na lista: a que parou (stopped) some depois de um dia, a que
    /// terminou (done) depois de poucos minutos (só serve para o aviso "terminou"), e a que diz estar trabalhando mas não mexe
    /// no estado há horas é job morto, não trabalho.
    static let validadeParada: TimeInterval = 24 * 3600
    static let validadeConcluida: TimeInterval = 10 * 60
    static let validadeTrabalhando: TimeInterval = 12 * 3600

    /// Lê um state.json de sessão que não espera resposta. Nil: está bloqueada (é de `parse`), é antiga demais, ou não faz sentido.
    static func parseOutra(_ dados: Data, pasta: String, agora: Date) -> Sessao? {
        guard let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let estado = obj["state"] as? String else { return nil }
        let (situacao, validade): (String, TimeInterval)
        switch estado {
        case "working": (situacao, validade) = ("trabalhando", validadeTrabalhando)
        case "stopped": (situacao, validade) = ("parada", validadeParada)
        case "done": (situacao, validade) = ("concluida", validadeConcluida)
        default: return nil
        }
        func texto(_ chave: String) -> String? {
            guard let t = obj[chave] as? String, !t.isEmpty else { return nil }
            return t
        }
        let desde = texto("updatedAt") ?? texto("createdAt") ?? ""
        guard let quando = Datas.ler(desde), agora.timeIntervalSince(quando) <= validade else { return nil }
        let raiz = texto("originCwd") ?? texto("cwd") ?? ""
        let projeto = raiz.split(separator: "/").last.map(String.init) ?? ""
        // `detail` é o último passo. Em sessão parada ele só repete o estado ("stopped"), e aí não diz nada.
        let passo = texto("detail").flatMap { $0 == estado ? nil : Mascara.segredos($0, limite: limitePasso) }
        return Sessao(id: pasta, nome: texto("name") ?? pasta, projeto: projeto, pergunta: "", desde: desde,
                      situacao: situacao, passo: passo)
    }

    static let limitePasso = 160
    static let limitePedido = 2000
    static let limiteContexto = 4000

    /// O estado do painel leva a lista leve: o contexto (até 4 mil caracteres por sessão) só vai em /api/sessoes.
    static func semContexto(_ s: [Sessao]) -> [Sessao] {
        s.map { var x = $0; x.contexto = nil; return x }
    }

    /// Texto da última mensagem da sessão: a última linha do `timeline.jsonl`, se ela é de espera (`blocked`).
    /// Lê só o fim do arquivo (ele passa de 70 KB e cresce), no máximo 256 KB para trás.
    static func contexto(timeline: URL) -> String? {
        guard let f = try? FileHandle(forReadingFrom: timeline) else { return nil }
        defer { try? f.close() }
        guard let fim = try? f.seekToEnd(), fim > 0 else { return nil }
        let passo: UInt64 = 32 * 1024, maximo: UInt64 = 256 * 1024
        var inicio = fim, bloco = Data()
        while inicio > 0, UInt64(bloco.count) < maximo {
            let de = inicio > passo ? inicio - passo : 0
            guard (try? f.seek(toOffset: de)) != nil, let d = try? f.read(upToCount: Int(inicio - de)) else { return nil }
            bloco = d + bloco
            inicio = de
            var aparado = bloco
            while aparado.last == 0x0A || aparado.last == 0x0D || aparado.last == 0x20 { aparado.removeLast() }
            if aparado.contains(0x0A) || inicio == 0 { bloco = aparado; break }
        }
        let linha = bloco.split(separator: 0x0A, omittingEmptySubsequences: true).last.map { Data($0) } ?? Data()
        guard let obj = (try? JSONSerialization.jsonObject(with: linha)) as? [String: Any],
              (obj["state"] as? String) == "blocked", let t = obj["text"] as? String else { return nil }
        var texto = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // O rótulo que a sessão põe no começo ("needs input:", "waiting:") já é o destaque da tela.
        for rotulo in ["needs input:", "waiting:"] where texto.lowercased().hasPrefix(rotulo) {
            texto = String(texto.dropFirst(rotulo.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return texto.isEmpty ? nil : Mascara.segredos(texto, limite: limiteContexto)
    }

    /// As que esperam a sua resposta (sem `situacao`).
    static func esperando(_ sessoes: [Sessao]) -> [Sessao] { sessoes.filter { $0.situacao == nil } }
    /// As outras, em ordem: trabalhando, paradas, concluídas.
    static func outras(_ sessoes: [Sessao]) -> [Sessao] { sessoes.filter { $0.situacao != nil } }

    /// Mais recente primeiro. Quem não tem data legível vai para o fim.
    static func ordenar(_ sessoes: [Sessao]) -> [Sessao] {
        sessoes.sorted { a, b in
            let da = Datas.ler(a.desde), db = Datas.ler(b.desde)
            switch (da, db) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            default: return false
            }
        }
    }

    /// As que esperam (mais recente primeiro) e depois as outras (trabalhando, paradas, concluídas, cada grupo do mais recente ao mais antigo).
    static func ler(raiz: URL, agora: Date = Date()) -> Leitura<[Sessao]> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: raiz.path) else { return Leitura(valor: [], aviso: nil) }
        guard let pastas = try? fm.contentsOfDirectory(atPath: raiz.path) else {
            return Leitura(valor: [], aviso: Aviso(fonte: "sessoes", texto: "Não consegui ler as sessões do Claude Code neste Mac."))
        }
        var achadas: [Sessao] = [], outras: [Sessao] = []
        for p in pastas {
            let arquivo = raiz.appendingPathComponent(p).appendingPathComponent("state.json")
            guard let dados = try? Data(contentsOf: arquivo) else { continue }
            if let o = parseOutra(dados, pasta: p, agora: agora) { outras.append(o); continue }
            let contexto = contexto(timeline: raiz.appendingPathComponent(p).appendingPathComponent("timeline.jsonl"))
            guard let s = parse(dados, pasta: p, contexto: contexto) else { continue }
            achadas.append(s)
        }
        // Um grupo por vez: o `ordenar` já põe o mais recente primeiro dentro dele.
        let outrasOrdenadas = ["trabalhando", "parada", "concluida"].flatMap { g in ordenar(outras.filter { $0.situacao == g }) }
        return Leitura(valor: ordenar(achadas) + outrasOrdenadas, aviso: nil)
    }
}

/// Tira do texto o que parece segredo antes de ele ir para o iPhone, e corta no limite.
enum Mascara {
    static let oculto = "[oculto]"

    private static let padroes: [(NSRegularExpression, String)] = {
        let lista: [(String, String)] = [
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#, oculto),
            (#"\b(sk|pk|rk)[-_][A-Za-z0-9_\-]{16,}"#, oculto),
            (#"\bgh[pousr]_[A-Za-z0-9]{20,}"#, oculto),
            (#"\bgithub_pat_[A-Za-z0-9_]{20,}"#, oculto),
            (#"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#, oculto),
            (#"\bAKIA[0-9A-Z]{16}\b"#, oculto),
            (#"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, oculto),
            (#"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/\-]{16,}=*"#, "$1 " + oculto),
            (#"(?i)(\b[A-Za-z0-9_\-]*(token|secret|senha|password|passwd|api[_-]?key)[A-Za-z0-9_\-]*[\"']?\s*[:=]\s*)([\"'`]?)[^\s\"'`]{4,}"#, "$1$3" + oculto),
            (#"(?i)(\b[a-z][a-z0-9+.\-]*://[^\s/:@]+:)[^\s/@]+@"#, "$1" + oculto + "@"),
            // sequência longa com maiúscula, minúscula e número juntas: chave gerada, não palavra nem commit
            (#"\b(?=[A-Za-z0-9_\-]*\d)(?=[A-Za-z0-9_\-]*[a-z])(?=[A-Za-z0-9_\-]*[A-Z])[A-Za-z0-9_\-]{32,}\b"#, oculto),
        ]
        return lista.compactMap { (p, r) in (try? NSRegularExpression(pattern: p)).map { ($0, r) } }
    }()

    static func segredos(_ texto: String, limite: Int) -> String {
        var t = texto
        for (re, troca) in padroes {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: troca)
        }
        guard t.count > limite else { return t }
        return String(t.prefix(limite)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
