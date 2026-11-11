import Foundation

/// Sessões do Claude Code paradas esperando resposta: `~/.claude/jobs/<id>/state.json` com
/// `state` = "blocked". Só leitura, esses arquivos são do Claude Code.
enum FonteSessoes {
    /// Lê um state.json. Devolve nil se a sessão não está bloqueada ou o arquivo não faz sentido.
    static func parse(_ dados: Data, pasta: String) -> Sessao? {
        guard let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              (obj["state"] as? String) == "blocked" else { return nil }
        func texto(_ chave: String) -> String? {
            guard let t = obj[chave] as? String, !t.isEmpty else { return nil }
            return t
        }
        // A pasta do projeto: originCwd é a raiz mesmo quando a sessão roda numa worktree.
        let raiz = texto("originCwd") ?? texto("cwd") ?? ""
        let projeto = raiz.split(separator: "/").last.map(String.init) ?? ""
        return Sessao(
            id: pasta,
            nome: texto("name") ?? pasta,
            projeto: projeto,
            // `detail` é a pergunta. Algumas sessões só trazem `needs`.
            pergunta: texto("detail") ?? texto("needs") ?? "",
            desde: texto("updatedAt") ?? texto("createdAt") ?? ""
        )
    }

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

    static func ler(raiz: URL) -> Leitura<[Sessao]> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: raiz.path) else { return Leitura(valor: [], aviso: nil) }
        guard let pastas = try? fm.contentsOfDirectory(atPath: raiz.path) else {
            return Leitura(valor: [], aviso: Aviso(fonte: "sessoes", texto: "Não consegui ler as sessões do Claude Code neste Mac."))
        }
        var achadas: [Sessao] = []
        for p in pastas {
            let arquivo = raiz.appendingPathComponent(p).appendingPathComponent("state.json")
            guard let dados = try? Data(contentsOf: arquivo), let s = parse(dados, pasta: p) else { continue }
            achadas.append(s)
        }
        return Leitura(valor: ordenar(achadas), aviso: nil)
    }
}
