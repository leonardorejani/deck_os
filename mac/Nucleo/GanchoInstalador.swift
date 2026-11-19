import Foundation

/// Instala e remove a entrada do gancho PermissionRequest no `settings.json` do Claude Code (o do dono, em `~/.claude`).
/// Só mexe no que é do Deck (o comando com a marca `/deck-gancho/`), guarda uma cópia do arquivo antes de gravar, grava de
/// forma atômica e recusa tudo se o formato que já está lá não for o esperado: o arquivo é do dono, e trocar o que ele
/// escreveu por outra forma perderia o que ele escreveu. Molde: ClaudeHook.cs do PhoneBox (MIT, Ersin KOÇ).
enum GanchoInstalador {
    enum Situacao: Equatable {
        case instalado
        case naoInstalado
        /// O arquivo existe mas não é o que o instalador sabe editar. O texto diz o que está estranho.
        case formatoInesperado(String)
    }

    /// O caminho do gancho no servidor local e a marca que identifica a entrada do Deck.
    static let caminho = "/deck-gancho/permissao"
    static let marca = "/deck-gancho/"

    static var arquivoPadrao: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    static func comando(porta: Int, cabecalho: URL, prazo: TimeInterval) -> String {
        // -H @arquivo: o segredo mora num arquivo só do dono e nunca no settings.json. Qualquer falha (Deck fechado, porta
        // fora do ar) termina em silêncio com saída 0, e o Claude Code pergunta no terminal como sempre.
        "curl -s --max-time \(Int(prazo) + 10) -X POST -H @\(aspas(cabecalho.path)) --data-binary @- http://127.0.0.1:\(porta)\(caminho) 2>/dev/null || true"
    }

    static func aspas(_ texto: String) -> String {
        "'" + texto.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Ler

    static func situacao(arquivo: URL = arquivoPadrao) -> Situacao {
        switch carregar(arquivo) {
        case .failure(let e): return .formatoInesperado(e.texto)
        case .success(let raiz):
            let grupos = (raiz["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
            return grupos.contains { g in (g["hooks"] as? [[String: Any]] ?? []).contains(where: donoDoDeck) } ? .instalado : .naoInstalado
        }
    }

    // MARK: Gravar

    /// Instala (ou, com `instalar` falso, remove). Devolve o erro em português, ou nil se deu certo.
    static func aplicar(instalar: Bool, arquivo: URL = arquivoPadrao, porta: Int, cabecalho: URL, prazo: TimeInterval = Aprovacoes.prazoPadrao) -> String? {
        var raiz: [String: Any]
        var original: Data?
        switch carregar(arquivo) {
        case .failure(let e): return e.texto
        case .success(let r): raiz = r; original = try? Data(contentsOf: arquivo)
        }
        var hooks = raiz["hooks"] as? [String: Any] ?? [:]
        var grupos = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        // Tira as entradas do Deck (as de antes também) e os grupos que ficam vazios por isso.
        grupos = grupos.compactMap { g in
            guard let lista = g["hooks"] as? [[String: Any]] else { return g }
            let restantes = lista.filter { !donoDoDeck($0) }
            if restantes.count == lista.count { return g }
            if restantes.isEmpty { return nil }
            var novo = g
            novo["hooks"] = restantes
            return novo
        }
        if instalar {
            grupos.append(["matcher": "*", "hooks": [["type": "command", "command": comando(porta: porta, cabecalho: cabecalho, prazo: prazo),
                                                      "timeout": Int(prazo) + 15] as [String: Any]]])
        }
        if grupos.isEmpty { hooks["PermissionRequest"] = nil } else { hooks["PermissionRequest"] = grupos }
        if hooks.isEmpty { raiz["hooks"] = nil } else { raiz["hooks"] = hooks }

        guard let dados = try? JSONSerialization.data(withJSONObject: raiz, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return "Não consegui montar o arquivo de configuração do Claude Code."
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Remover o que não está lá não regrava o arquivo do dono (o JSONSerialization reordena as chaves).
            if !instalar, let original, let atual = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any],
               NSDictionary(dictionary: atual).isEqual(to: raiz) { return nil }
            if let original, !(String(data: original, encoding: .utf8) ?? "").contains(marca) {
                // A cópia do arquivo como o dono deixou, só do dono (o arquivo pode ter chaves no `env`). Só se grava
                // quando o arquivo ainda não tem nada do Deck: depois disso a cópia seria a versão já mexida.
                let copia = arquivo.deletingLastPathComponent().appendingPathComponent(arquivo.lastPathComponent + ".deck-copia")
                // Se a cópia que já existe diz o mesmo (só muda a formatação), ela fica: é a que tem o texto do dono, byte a byte.
                if !mesmoConteudo(copia, original) { try original.write(to: copia, options: .atomic) }
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copia.path)
            }
            let permissao = (try? fm.attributesOfItem(atPath: arquivo.path))?[.posixPermissions] as? NSNumber ?? NSNumber(value: 0o600)
            try dados.write(to: arquivo, options: .atomic)
            try? fm.setAttributes([.posixPermissions: permissao], ofItemAtPath: arquivo.path)
        } catch {
            return "Não consegui gravar o arquivo de configuração do Claude Code."
        }
        return nil
    }

    // MARK: Peças

    private static func mesmoConteudo(_ arquivo: URL, _ dados: Data) -> Bool {
        guard let a = try? Data(contentsOf: arquivo), let x = try? JSONSerialization.jsonObject(with: a),
              let y = try? JSONSerialization.jsonObject(with: dados) else { return false }
        return (x as? NSObject)?.isEqual(y) ?? false
    }

    private struct Recusa: Error { var texto: String }

    private static func donoDoDeck(_ h: [String: Any]) -> Bool {
        (h["command"] as? String)?.contains(marca) == true
    }

    /// Lê o arquivo (ou um objeto vazio se ele não existe) e confere que as partes que o instalador toca têm a forma esperada.
    private static func carregar(_ arquivo: URL) -> Result<[String: Any], Recusa> {
        guard FileManager.default.fileExists(atPath: arquivo.path) else { return .success([:]) }
        guard let dados = try? Data(contentsOf: arquivo) else { return .failure(Recusa(texto: "Não consegui ler o arquivo de configuração do Claude Code.")) }
        if dados.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return .success([:]) }
        guard let raiz = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else {
            return .failure(Recusa(texto: "O arquivo de configuração do Claude Code não está no formato esperado. Nada foi mudado."))
        }
        if let h = raiz["hooks"] {
            guard let hooks = h as? [String: Any] else { return .failure(Recusa(texto: "O campo \"hooks\" do Claude Code não está no formato esperado. Nada foi mudado.")) }
            if let p = hooks["PermissionRequest"] {
                guard let grupos = p as? [[String: Any]] else { return .failure(Recusa(texto: "O campo \"PermissionRequest\" do Claude Code não está no formato esperado. Nada foi mudado.")) }
                for g in grupos {
                    if let lista = g["hooks"], !(lista is [[String: Any]]) {
                        return .failure(Recusa(texto: "Um gancho do Claude Code não está no formato esperado. Nada foi mudado."))
                    }
                }
            }
        }
        return .success(raiz)
    }
}

/// O segredo do gancho: um arquivo só do dono, com a linha de cabeçalho que o `curl` do gancho manda (`-H @arquivo`).
enum SegredoDoGancho {
    static let nomeDoArquivo = "gancho-cabecalho"
    static let cabecalho = "X-Deck-Gancho"

    static func arquivo(pasta: URL) -> URL { pasta.appendingPathComponent(nomeDoArquivo) }

    /// Lê o segredo, criando o arquivo (0600) na primeira vez. Nil: não deu para gravar.
    static func garantir(pasta: URL) -> String? {
        let url = arquivo(pasta: pasta)
        if let texto = try? String(contentsOf: url, encoding: .utf8), let s = ler(texto) { return s }
        var bytes = [UInt8](repeating: 0, count: 24)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let segredo = bytes.map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: pasta, withIntermediateDirectories: true)
            guard fm.createFile(atPath: url.path, contents: Data("\(cabecalho): \(segredo)\n".utf8), attributes: [.posixPermissions: 0o600]) else { return nil }
        } catch { return nil }
        return segredo
    }

    static func ler(_ texto: String) -> String? {
        let linha = texto.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let prefixo = cabecalho + ": "
        guard linha.hasPrefix(prefixo) else { return nil }
        let s = String(linha.dropFirst(prefixo.count))
        return s.count >= 32 ? s : nil
    }
}
