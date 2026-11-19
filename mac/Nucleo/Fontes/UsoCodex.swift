import Foundation

/// Uso semanal do Codex, lido dos arquivos de sessão (`~/.codex/sessions/AAAA/MM/DD/*.jsonl`).
/// Cada evento `token_count` traz `rate_limits`. Só atualiza quando o Codex roda.
enum UsoCodex {
    struct Janela: Equatable, Sendable {
        var percentual: Int
        var renova: Date
    }

    static let minutosDaSemana = 10080

    /// Procura, de trás para frente, o último evento com a janela semanal. A janela semanal pode
    /// vir em `primary` ou em `secondary`, então vale a que tem `window_minutes` de 10080.
    static func parse(_ texto: String) -> Janela? {
        for linha in texto.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard linha.contains("rate_limits"),
                  let obj = (try? JSONSerialization.jsonObject(with: Data(linha.utf8))) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limites = payload["rate_limits"] as? [String: Any] else { continue }
            for chave in ["primary", "secondary"] {
                guard let j = limites[chave] as? [String: Any],
                      let janela = numero(j["window_minutes"]), janela == Double(minutosDaSemana),
                      let usado = numero(j["used_percent"]),
                      let reseta = numero(j["resets_at"]).flatMap(Numero.epoch) else { continue }
                return Janela(percentual: Numero.percentual(usado), renova: reseta)
            }
        }
        return nil
    }

    private static func numero(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    /// Os arquivos de sessão ficam enormes, e o evento mais novo está no fim: lê só a cauda.
    static let bytesDaCauda = 1_000_000

    static func cauda(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let tamanho = try? h.seekToEnd() else { return nil }
        let inicio = tamanho > UInt64(bytesDaCauda) ? tamanho - UInt64(bytesDaCauda) : 0
        guard (try? h.seek(toOffset: inicio)) != nil, let dados = try? h.readToEnd() else { return nil }
        return String(decoding: dados, as: UTF8.self)
    }

    /// Varre os arquivos do mais recente para o mais antigo até achar uma janela semanal.
    static func lerJanela(raiz: URL, maxArquivos: Int = 30) -> Janela? {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var arquivos: [(URL, Date)] = []
        for case let url as URL in it where url.pathExtension == "jsonl" {
            let data = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            arquivos.append((url, data))
        }
        for (url, _) in arquivos.sorted(by: { $0.1 > $1.1 }).prefix(maxArquivos) {
            if let t = cauda(url), let j = parse(t) { return j }
        }
        return nil
    }


    /// Uma janela de limite do Codex: a curta (5 horas) e a semanal vêm no mesmo evento, em `primary` e `secondary`.
    struct JanelaCodex: Equatable, Sendable {
        var minutos: Int
        var percentual: Int
        var renova: Date
        var medidoEm: Date?
    }

    /// As janelas do evento mais novo que traz `rate_limits`. A semanal aqui bate com a de `parse`.
    static func parseJanelas(_ texto: String) -> [JanelaCodex] {
        for linha in texto.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard linha.contains("rate_limits"),
                  let obj = (try? JSONSerialization.jsonObject(with: Data(linha.utf8))) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limites = payload["rate_limits"] as? [String: Any] else { continue }
            let medido = (obj["timestamp"] as? String).flatMap(Datas.ler)
            var saida: [JanelaCodex] = []
            for chave in ["primary", "secondary"] {
                guard let j = limites[chave] as? [String: Any], let min = numero(j["window_minutes"]), min > 0,
                      let usado = numero(j["used_percent"]), let reseta = numero(j["resets_at"]).flatMap(Numero.epoch) else { continue }
                saida.append(JanelaCodex(minutos: Int(min), percentual: Numero.percentual(usado), renova: reseta, medidoEm: medido))
            }
            if !saida.isEmpty { return saida.sorted { $0.minutos < $1.minutos } }
        }
        return []
    }

    /// Mesma varredura de `lerJanela`, devolvendo todas as janelas do evento mais novo.
    static func lerJanelas(raiz: URL, maxArquivos: Int = 30) -> [JanelaCodex] {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var arquivos: [(URL, Date)] = []
        for case let url as URL in it where url.pathExtension == "jsonl" {
            let data = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            arquivos.append((url, data))
        }
        for (url, _) in arquivos.sorted(by: { $0.1 > $1.1 }).prefix(maxArquivos) {
            if let t = cauda(url) { let j = parseJanelas(t); if !j.isEmpty { return j } }
        }
        return []
    }

    static func ler(raiz: URL, conta: ContaIA, agora: Date) -> Leitura<UsoConta> {
        let vazio = UsoConta(id: conta.id, nome: conta.nome, conta: conta.conta, semana: nil, renova: nil)
        guard let j = lerJanela(raiz: raiz) else {
            return Leitura(valor: vazio, aviso: Aviso(fonte: "uso", texto: "Ainda não há medição do Codex. Ela aparece depois que você usar o Codex neste Mac."))
        }
        // Janela que já renovou: o percentual guardado é da semana passada, então não vale.
        guard j.renova > agora else { return Leitura(valor: vazio, aviso: nil) }
        var uso = vazio
        uso.semana = max(0, min(100, j.percentual))
        uso.renova = Datas.iso(j.renova, fuso: TimeZone(identifier: "UTC")!)
        return Leitura(valor: uso, aviso: nil)
    }
}
