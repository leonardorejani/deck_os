import Foundation

/// A lógica pura da seção Uso das IAs e da janela Adicionar conta: o que o protótipo calcula em
/// mac.js (nivel, perto, renovaEm, adicionarToken). Sem tela, para testar.
enum NivelUso: Equatable {
    case normal, alto, cheio
}

enum UsoLogica {
    /// Amarela a partir de 70, vermelha a partir de 90 (SPEC 9a).
    static func nivel(_ percentual: Int) -> NivelUso {
        percentual >= 90 ? .cheio : percentual >= 70 ? .alto : .normal
    }

    /// "Mais perto do limite": a conta visível com o maior percentual da semana. Sem medição não entra.
    static func maisPerto(contas: [ContaIA], uso: [String: UsoConta]) -> (conta: ContaIA, semana: Int)? {
        var melhor: (ContaIA, Int)?
        for c in contas where c.mostrar != false {
            guard let s = uso[c.id]?.semana else { continue }
            if melhor == nil || s > melhor!.1 { melhor = (c, s) }
        }
        return melhor.map { (conta: $0.0, semana: $0.1) }
    }

    /// "em 3 dias", "amanhã" ou "hoje às 14h" (com minutos só quando não for hora cheia).
    static func renovaEm(_ renova: Date, agora: Date, calendario: Calendar = .current) -> String {
        let dias = calendario.dateComponents([.day], from: calendario.startOfDay(for: agora), to: calendario.startOfDay(for: renova)).day ?? 0
        if dias >= 2 { return "em \(dias) dias" }
        if dias == 1 { return "amanhã" }
        let h = calendario.component(.hour, from: renova), m = calendario.component(.minute, from: renova)
        return m == 0 ? "hoje às \(h)h" : "hoje às \(h)h\(String(format: "%02d", m))"
    }

    /// O dia exato, para o texto que aparece ao passar o mouse ("sex., 13 de nov. às 14h").
    static func dataExata(_ renova: Date, calendario: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.calendar = calendario
        f.timeZone = calendario.timeZone
        f.dateFormat = "EEE, d 'de' MMM"
        let h = calendario.component(.hour, from: renova), m = calendario.component(.minute, from: renova)
        let hora = m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
        return "\(f.string(from: renova)) às \(hora)"
    }

    /// O texto de baixo do cartão, já com o "Renova".
    static func textoRenova(_ iso: String?, agora: Date, calendario: Calendar = .current) -> (texto: String, exata: String)? {
        guard let iso, let d = Datas.ler(iso) else { return nil }
        return ("Renova \(renovaEm(d, agora: agora, calendario: calendario))", dataExata(d, calendario: calendario))
    }

    static func servico(_ conta: ContaIA) -> String { conta.nome == "Claude" ? "Claude Code" : conta.nome }
    static func subtitulo(_ conta: ContaIA) -> String { "\(servico(conta)), conta \(conta.perfil ?? conta.conta)" }
}

/// Token do Claude Code colado na janela Adicionar conta.
enum TokenClaude {
    static let prefixo = "sk-ant-oat01-"
    static let tamanhoMinimo = 100

    /// O Terminal quebra o token em linhas: tira espaço e quebra de linha ao colar.
    static func limpar(_ texto: String) -> String { texto.filter { !$0.isWhitespace } }

    /// nil quando o formato está certo. Os textos são os do protótipo.
    static func erroDeFormato(_ token: String) -> String? {
        if !token.hasPrefix(prefixo) { return "Isso não é um token do Claude Code. Ele começa com \(prefixo)" }
        if token.count < tamanhoMinimo { return "O token parece cortado. Copie de novo, ele é bem longo." }
        return nil
    }

    static let recusado = "O Claude recusou esse token. Gere outro com claude setup-token."
    static let semRede = "Não consegui falar com o Claude agora. Confira a internet e tente de novo."
    static let semGuardar = "Não consegui guardar o token no Chaveiro deste Mac."
}

/// Contas de IA que já existem neste Mac e ainda não estão no painel ("Achei neste Mac").
struct ContaEncontrada: Equatable, Identifiable {
    var conta: ContaIA
    var id: String { conta.id }
}

enum ContasAchadas {
    /// Mesma regra do núcleo (Config): só letras, números, "_", "-" e "." no meio.
    static func perfilValido(_ p: String) -> Bool {
        !p.isEmpty && !p.hasPrefix(".") && p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) }
    }

    /// Claude Code: cada perfil da troca de contas (`~/.config/claude-account/logins/<perfil>`).
    /// Codex: o login em `~/.codex/auth.json`, uma conta por vez.
    static func procurar(casa: URL, jaNoPainel: [ContaIA]) -> [ContaEncontrada] {
        let fm = FileManager.default
        var achadas: [ContaEncontrada] = []
        let logins = casa.appendingPathComponent(".config/claude-account/logins")
        let perfis = ((try? fm.contentsOfDirectory(atPath: logins.path)) ?? []).filter { perfilValido($0) }.sorted()
        for p in perfis {
            let jaTem = jaNoPainel.contains { $0.nome == "Claude" && ($0.perfil == p || $0.id == "claude-\(p)") }
            if !jaTem { achadas.append(ContaEncontrada(conta: ContaIA(id: "claude-\(p)", nome: "Claude", conta: p, perfil: p, mostrar: true))) }
        }
        if fm.fileExists(atPath: casa.appendingPathComponent(".codex/auth.json").path), !jaNoPainel.contains(where: { $0.id == "codex" }) {
            achadas.append(ContaEncontrada(conta: ContaIA(id: "codex", nome: "Codex", conta: "principal", perfil: nil, mostrar: true)))
        }
        return achadas
    }
}
