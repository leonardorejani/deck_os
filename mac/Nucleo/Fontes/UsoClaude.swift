import Foundation

/// Uso semanal do Claude, lido da medição da troca de contas: `~/.config/claude-account/measure.json`,
/// gravada pelo `claude-account-autoswitch` a cada 5 minutos. Formato:
/// {"measured_at": "...Z", "profiles": {"leo": {"util_7d": 61, "reset_7d": 1794500000, ...}}}
/// `util_7d` já vem de 0 a 100 e `reset_7d` é epoch em segundos. Se o arquivo não existe, a semana
/// fica nil com aviso. Nunca chama API nem toca em token.
enum UsoClaude {
    struct Perfil: Equatable, Sendable {
        var semana: Int?
        var renova: Date?
    }

    struct Medicao: Equatable, Sendable {
        var medidoEm: Date?
        var perfis: [String: Perfil]
    }

    /// Medição mais velha que isso conta como "sem medição recente" (o autoswitch mede a cada 5 min).
    static let validade: TimeInterval = 30 * 60

    static func parse(_ dados: Data) -> Medicao? {
        guard let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let perfis = obj["profiles"] as? [String: Any] else { return nil }
        var saida: [String: Perfil] = [:]
        for (nome, v) in perfis {
            guard let p = v as? [String: Any] else { continue }
            let semana = ((p["util_7d"] as? Double) ?? (p["util_7d"] as? Int).map(Double.init)).map(Numero.percentual)
            let reset = (p["reset_7d"] as? Double) ?? (p["reset_7d"] as? Int).map(Double.init)
            saida[nome] = Perfil(semana: semana, renova: reset.flatMap(Numero.epoch))
        }
        let quando = (obj["measured_at"] as? String).flatMap(Datas.ler)
        return Medicao(medidoEm: quando, perfis: saida)
    }

    static func ler(contas: [ContaIA], arquivo: URL, agora: Date) -> Leitura<[UsoConta]> {
        func vazios() -> [UsoConta] {
            contas.map { UsoConta(id: $0.id, nome: $0.nome, conta: $0.conta, semana: nil, renova: nil) }
        }
        guard let dados = try? Data(contentsOf: arquivo) else {
            return Leitura(valor: vazios(), aviso: Aviso(fonte: "uso", texto: "A medição do Claude ainda não existe neste Mac."))
        }
        guard let m = parse(dados) else {
            return Leitura(valor: vazios(), aviso: Aviso(fonte: "uso", texto: "Não consegui entender a medição do Claude."))
        }
        guard let quando = m.medidoEm, agora.timeIntervalSince(quando) <= validade else {
            return Leitura(valor: vazios(), aviso: Aviso(fonte: "uso", texto: "A medição do Claude está desatualizada."))
        }
        let utc = TimeZone(identifier: "UTC")!
        let uso = contas.map { c -> UsoConta in
            var u = UsoConta(id: c.id, nome: c.nome, conta: c.conta, semana: nil, renova: nil)
            guard let perfil = c.perfil, let p = m.perfis[perfil] else { return u }
            u.semana = p.semana.map { max(0, min(100, $0)) }
            if let r = p.renova, r > agora { u.renova = Datas.iso(r, fuso: utc) }
            return u
        }
        return Leitura(valor: uso, aviso: nil)
    }
}

/// Junta o uso de todas as contas da config, na ordem dela, escondendo as que o Mac marcou como
/// "No iPhone" desligado.
enum FonteUso {
    static func ler(contas: [ContaIA], claude: URL, codex: URL, agora: Date) -> Leitura<[UsoConta]> {
        let visiveis = contas.filter { $0.mostrar != false }
        let deClaude = UsoClaude.ler(contas: visiveis.filter { $0.nome == "Claude" }, arquivo: claude, agora: agora)
        var avisos: [String] = []
        if let a = deClaude.aviso, visiveis.contains(where: { $0.nome == "Claude" }) { avisos.append(a.texto) }
        var codexFeito = false
        let uso = visiveis.map { c -> UsoConta in
            switch c.nome {
            case "Claude":
                return deClaude.valor.first { $0.id == c.id } ?? UsoConta(id: c.id, nome: c.nome, conta: c.conta, semana: nil, renova: nil)
            case "Codex":
                let r = UsoCodex.ler(raiz: codex, conta: c, agora: agora)
                if let a = r.aviso, !codexFeito { avisos.append(a.texto) }
                codexFeito = true
                return r.valor
            default:
                return UsoConta(id: c.id, nome: c.nome, conta: c.conta, semana: nil, renova: nil)
            }
        }
        return Leitura(valor: uso, aviso: avisos.isEmpty ? nil : Aviso(fonte: "uso", texto: avisos.joined(separator: " ")))
    }

    /// Soma ao uso lido dos arquivos o que o Mac mediu por token (contas adicionadas pelo Deck, ou perfis sem
    /// medição do autoswitch). Sem isso o iPhone mostrava só o nome da conta, porque o estado lia apenas
    /// o `measure.json`. Só troca a conta que veio sem número: medição de arquivo boa não é sobrescrita.
    /// Se todas as contas ficaram com número, o aviso de "sem medição" não tem mais motivo.
    static func mesclar(_ base: Leitura<[UsoConta]>, medidos: [String: UsoConta]) -> Leitura<[UsoConta]> {
        guard !medidos.isEmpty else { return base }
        let uso = base.valor.map { u -> UsoConta in
            guard u.semana == nil, let m = medidos[u.id], m.semana != nil else { return u }
            var novo = u
            novo.semana = m.semana
            novo.renova = m.renova
            return novo
        }
        let tudoMedido = uso.allSatisfy { $0.semana != nil }
        return Leitura(valor: uso, aviso: tudoMedido ? nil : base.aviso)
    }
}
