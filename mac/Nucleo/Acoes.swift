import Foundation

/// Executa a ação de uma tecla do painel. Devolve nil quando deu certo, ou o erro em português
/// para mostrar no iPhone. Todo comando passa pelo Executor injetado, para os testes usarem um falso.
struct ExecutorAcoes: Sendable {
    let shell: Executor
    /// Pergunta se o Deck tem o acesso de Acessibilidade (só o macOS responde de verdade).
    let temAcessibilidade: @Sendable () -> Bool
    /// Envia a combinação (keyDown e keyUp com as flags). Só o macOS faz de verdade.
    let enviarTecla: @Sendable (Combinacao) -> Void

    /// Tempo máximo padrão de um comando de shell antes de ser derrubado.
    static let limitePadrao = 10
    /// Status que o vigia devolve quando derrubou o comando por tempo (o mesmo do comando timeout).
    static let statusTempoEsgotado: Int32 = 142
    let limiteSegundos: Int
    /// Com a origem do WhatsApp em "web", a tecla do WhatsApp abre o WhatsApp Web em vez do app. Nil: sempre o app.
    let whatsappWeb: (@Sendable () -> AberturaWhatsApp)?

    init(shell: Executor,
         temAcessibilidade: @escaping @Sendable () -> Bool = { AcoesSistema.temAcessibilidade() },
         enviarTecla: @escaping @Sendable (Combinacao) -> Void = { AcoesSistema.enviar($0) },
         limiteSegundos: Int = ExecutorAcoes.limitePadrao,
         whatsappWeb: (@Sendable () -> AberturaWhatsApp)? = nil) {
        self.limiteSegundos = limiteSegundos
        self.whatsappWeb = whatsappWeb
        self.shell = shell
        self.temAcessibilidade = temAcessibilidade
        self.enviarTecla = enviarTecla
    }

    func executar(_ tecla: Tecla) -> String? {
        let valor = tecla.valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valor.isEmpty else { return "A tecla \"\(tecla.nome)\" está sem ação configurada" }
        switch tecla.tipo {
        case "app":
            if let acao = tecla.acao { return abrirComAcao(tecla, acao) }
            return abrirApp(valor)
        case "comando": return rodarComando(valor)
        case "atalho": return rodarAtalho(valor)
        // O contrato (Modelos.swift) chama o tipo de "tecla". "teclado" fica por compatibilidade.
        case "tecla", "teclado": return teclar(valor)
        default: return "Não sei executar esse tipo de tecla"
        }
    }

    // MARK: - Tipos

    private func abrirApp(_ nome: String) -> String? {
        if nome.lowercased() == "whatsapp", let web = whatsappWeb {
            switch web() {
            case .aberto: return nil
            case .falhou(let erro): return erro
            case .naoEWeb: break
            }
        }
        let r = shell.rodar("open -a \(Self.escapar(nome))")
        return r.status == 0 ? nil : "Não achei o app \(nome) neste Mac"
    }

    private func rodarComando(_ linha: String) -> String? {
        let r = shell.rodar(Shell.limitado(linha, segundos: limiteSegundos))
        if r.status == 0 { return nil }
        if r.status == Self.statusTempoEsgotado { return "O comando demorou mais de \(limiteSegundos) segundos e foi interrompido" }
        let ultima = Self.ultimaLinha(r.saida)
        return ultima.isEmpty ? "O comando falhou" : "O comando falhou: \(ultima)"
    }

    private func rodarAtalho(_ nome: String) -> String? {
        // O "--" impede que um nome começando com "-" seja lido como opção do shortcuts.
        let r = shell.rodar("shortcuts run -- \(Self.escapar(nome))")
        if r.status == 0 { return nil }
        let ultima = Self.ultimaLinha(r.saida)
        // O shortcuts responde no idioma do Mac: "find shortcut" (inglês) ou "encontrar o atalho" (português).
        if ultima.isEmpty || ultima.localizedCaseInsensitiveContains("find shortcut")
            || ultima.localizedCaseInsensitiveContains("not found")
            || ultima.localizedCaseInsensitiveContains("encontrar o atalho") {
            return "Não achei o Atalho \(nome) neste Mac"
        }
        return "O Atalho \(nome) falhou: \(ultima)"
    }

    private func teclar(_ texto: String) -> String? {
        guard let combinacao = Teclas.ler(texto) else { return "Não entendi a combinação de teclas \(texto)" }
        guard temAcessibilidade() else { return Self.erroAcessibilidade }
        enviarTecla(combinacao)
        return nil
    }

    static let erroAcessibilidade = "O Deck precisa do acesso de Acessibilidade para teclar"

    // MARK: - Texto seguro

    /// Aspas simples do shell: nada dentro é interpretado ($(), crase, ;, aspas, acento).
    static func escapar(_ texto: String) -> String {
        "'" + texto.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func ultimaLinha(_ saida: String) -> String {
        saida.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }
}
