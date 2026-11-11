import Foundation

/// O que "Abrir no Mac" fez numa sessão do Claude Code.
struct SessaoAberta: Codable, Equatable, Sendable {
    var ok: Bool = true
    /// "terminal": trouxe para a frente o terminal onde a sessão está. "pasta": não achou o terminal e abriu o Terminal na pasta do projeto.
    var como: String
    /// Nome do app que veio para a frente (Orca, Terminal, iTerm...).
    var app: String?
}

struct ErroAbrirSessao: Error, Equatable, Sendable {
    var status: Int
    var texto: String
}

protocol AbridorDeSessao: Sendable {
    func abrir(id: String) -> Result<SessaoAberta, ErroAbrirSessao>
}

/// Traz para a frente o terminal de uma sessão do Claude Code. O `state.json` do job não guarda em que app a sessão
/// está aberta, então o Mac descobre pelo processo: a sessão em segundo plano é acompanhada por um `claude attach <nome>`
/// rodando num terminal, e o app dono desse terminal é o primeiro `.app` entre os pais do processo. Se nenhum terminal
/// está acompanhando, abre o Terminal na pasta do projeto. Só lê `state.json` e a lista de processos.
struct AbridorDeSessaoNoMac: AbridorDeSessao {
    let raiz: URL
    let shell: Executor

    func abrir(id: String) -> Result<SessaoAberta, ErroAbrirSessao> {
        guard !id.isEmpty, !id.contains("/"), !id.contains(".."),
              let dados = try? Data(contentsOf: raiz.appendingPathComponent(id).appendingPathComponent("state.json")),
              let obj = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else {
            return .failure(ErroAbrirSessao(status: 404, texto: "Essa sessão não existe mais neste Mac."))
        }
        func texto(_ k: String) -> String? { (obj[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let chamados = [texto("name"), id, texto("sessionId")].compactMap { $0 }
        if let achado = Self.terminalDe(processos: shell.rodar("ps -axo pid=,ppid=,tty=,command=").saida, chamados: chamados) {
            return trazer(achado)
        }
        let pasta = texto("originCwd") ?? texto("cwd") ?? ""
        var ehPasta: ObjCBool = false
        guard !pasta.isEmpty, FileManager.default.fileExists(atPath: pasta, isDirectory: &ehPasta), ehPasta.boolValue else {
            return .failure(ErroAbrirSessao(status: 422, texto: "Não achei o terminal nem a pasta dessa sessão neste Mac."))
        }
        let r = shell.rodar("open -a Terminal \(ExecutorAcoes.escapar(pasta))")
        guard r.status == 0 else { return .failure(ErroAbrirSessao(status: 422, texto: "Não consegui abrir o Terminal neste Mac.")) }
        return .success(SessaoAberta(como: "pasta", app: "Terminal"))
    }

    private func trazer(_ t: TerminalDaSessao) -> Result<SessaoAberta, ErroAbrirSessao> {
        // O Terminal da Apple deixa escolher a aba pelo terminal (tty), então a aba certa vem para a frente. Nos outros
        // apps vem o app. O macOS pede a permissão de controlar o Terminal na primeira vez, na hora do uso.
        if t.nomeDoApp == "Terminal", let tty = t.tty {
            let script = """
            tell application "Terminal"
              activate
              repeat with j in windows
                repeat with a in tabs of j
                  if tty of a is "/dev/\(tty)" then
                    set selected tab of j to a
                    set index of j to 1
                  end if
                end repeat
              end repeat
            end tell
            """
            if shell.rodar("osascript -e \(ExecutorAcoes.escapar(script))").status == 0 {
                return .success(SessaoAberta(como: "terminal", app: t.nomeDoApp))
            }
        }
        let r = shell.rodar("open \(ExecutorAcoes.escapar(t.caminhoDoApp))")
        guard r.status == 0 else { return .failure(ErroAbrirSessao(status: 422, texto: "Não consegui trazer o \(t.nomeDoApp) para a frente.")) }
        return .success(SessaoAberta(como: "terminal", app: t.nomeDoApp))
    }

    struct TerminalDaSessao: Equatable {
        var caminhoDoApp: String
        var nomeDoApp: String
        var tty: String?
    }

    /// Acha, na saída de `ps -axo pid=,ppid=,tty=,command=`, o `claude attach <nome>` da sessão e sobe pelos pais até o
    /// primeiro app (`.../X.app/Contents/...`). Nil se ninguém está acompanhando a sessão.
    static func terminalDe(processos saida: String, chamados: [String]) -> TerminalDaSessao? {
        struct P { var ppid: Int; var tty: String; var comando: String }
        var tabela: [Int: P] = [:]
        for linha in saida.split(whereSeparator: \.isNewline) {
            let partes = linha.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard partes.count == 4, let pid = Int(partes[0]), let ppid = Int(partes[1]) else { continue }
            tabela[pid] = P(ppid: ppid, tty: String(partes[2]), comando: partes[3].trimmingCharacters(in: .whitespaces))
        }
        func acompanha(_ comando: String) -> Bool {
            guard let r = comando.range(of: " attach ") else { return false }
            let programa = comando[..<r.lowerBound].split(separator: "/").last.map(String.init) ?? ""
            guard programa == "claude" || programa.hasPrefix("claude.") else { return false }
            let resto = comando[r.upperBound...].trimmingCharacters(in: .whitespaces)
            return chamados.contains { resto == $0 || resto.hasPrefix($0 + " ") }
        }
        guard let (pid, proc) = tabela.sorted(by: { $0.key < $1.key }).first(where: { acompanha($0.value.comando) }) else { return nil }
        let tty = proc.tty == "??" || proc.tty.isEmpty ? nil : proc.tty
        var atual = pid, passos = 0
        while let p = tabela[atual], passos < 40 {
            if let fim = p.comando.range(of: ".app/") ?? p.comando.range(of: ".app", options: [.backwards, .anchored]) {
                let caminho = String(p.comando[..<fim.lowerBound]) + ".app"
                let nome = URL(fileURLWithPath: caminho).deletingPathExtension().lastPathComponent
                return TerminalDaSessao(caminhoDoApp: caminho, nomeDoApp: nome, tty: tty)
            }
            atual = p.ppid; passos += 1
        }
        return nil
    }
}
