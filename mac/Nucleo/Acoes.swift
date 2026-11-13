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
    /// Shell em que a tecla de comando roda (o de login do usuário, com o perfil dele carregado).
    let shellDoUsuario: @Sendable () -> String
    /// O que o Deck guardou das teclas liga e desliga sem comando de conferir.
    let memoria: MemoriaLigaDesliga
    /// A árvore de acessibilidade dos navegadores (o Meet). Nil: só o executor de verdade, no Mac, consulta o sistema.
    let ax: (any AcessibilidadeDoNavegador)?

    init(shell: Executor,
         temAcessibilidade: @escaping @Sendable () -> Bool = { AcoesSistema.temAcessibilidade() },
         enviarTecla: @escaping @Sendable (Combinacao) -> Void = { AcoesSistema.enviar($0) },
         limiteSegundos: Int = ExecutorAcoes.limitePadrao,
         whatsappWeb: (@Sendable () -> AberturaWhatsApp)? = nil,
         shellDoUsuario: @escaping @Sendable () -> String = { Shell.doUsuario() },
         memoria: MemoriaLigaDesliga = .compartilhada,
         ax: (any AcessibilidadeDoNavegador)? = nil) {
        self.ax = ax ?? AcessibilidadePadrao.para(shell)
        self.memoria = memoria
        self.shellDoUsuario = shellDoUsuario
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
        case "comando": return tecla.ligaEDesliga ? alternar(tecla, ligar: valor) : rodarComando(valor)
        case "atalho": return rodarAtalho(valor)
        // O contrato (Modelos.swift) chama o tipo de "tecla". "teclado" fica por compatibilidade.
        case "tecla", "teclado": return teclar(valor)
        default: return "Não sei executar esse tipo de tecla"
        }
    }

    // MARK: - Tipos

    private func abrirApp(_ nome: String) -> String? {
        // "Google Meet (navegador)" não é app instalado: sem ação, abre o Meet no navegador padrão.
        if nome == ControleDeReuniao.valorDoMeet {
            return shell.rodar("open \(Self.escapar("https://meet.google.com"))").status == 0 ? nil : "Não consegui abrir o Meet no navegador"
        }
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

    func rodarComando(_ linha: String) -> String? {
        let r = shell.rodar(Shell.limitadoNoPerfil(linha, segundos: limiteSegundos, shell: shellDoUsuario()))
        if r.status == 0 { return nil }
        if r.status == 127 { return Self.erroComandoInexistente(r.saida) }
        if r.status == Self.statusTempoEsgotado { return "O comando demorou mais de \(limiteSegundos) segundos e foi interrompido" }
        let ultima = Self.ultimaLinha(r.saida)
        return ultima.isEmpty ? "O comando falhou" : "O comando falhou: \(ultima)"
    }

    /// 127 é "comando não encontrado" em qualquer shell. Extrai o nome da mensagem do zsh/bash/fish.
    static func erroComandoInexistente(_ saida: String) -> String {
        let ultima = ultimaLinha(saida)
        let marca = "command not found"
        guard ultima.localizedCaseInsensitiveContains(marca) else {
            return ultima.isEmpty ? "O comando falhou" : "O comando falhou: \(ultima)"
        }
        // zsh: "zsh:1: command not found: mudar". bash: "bash: mudar: command not found". fish: "fish: Unknown command: mudar".
        var nome = ""
        if let r = ultima.range(of: marca + ":", options: .caseInsensitive) {
            nome = String(ultima[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let r = ultima.range(of: ": " + marca, options: .caseInsensitive) {
            nome = String(ultima[..<r.lowerBound]).split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        }
        return nome.isEmpty ? "Comando não encontrado" : "Comando não encontrado: \(nome)"
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
