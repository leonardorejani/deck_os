import SwiftUI
import AppKit

// As ações novas do modelo do app para as contas de IA (só acrescenta, não mexe no que existe) e o
// estado da seção Uso das IAs: uso lido, aviso com Desfazer e a janela Adicionar conta.

@MainActor
extension ModeloApp {
    @discardableResult
    func adicionarConta(_ conta: ContaIA) -> Bool {
        gravar { if !$0.contas.contains(where: { $0.id == conta.id }) { $0.contas.append(conta) } }
        return config.contas.contains { $0.id == conta.id }
    }

    /// Tira a conta da config. Devolve onde ela estava, para o Desfazer.
    func removerConta(id: String) -> (conta: ContaIA, indice: Int)? {
        guard let i = config.contas.firstIndex(where: { $0.id == id }) else { return nil }
        let conta = config.contas[i]
        gravar { $0.contas.removeAll { $0.id == id } }
        return config.contas.contains { $0.id == id } ? nil : (conta, i)
    }

    func restaurarConta(_ conta: ContaIA, em indice: Int) {
        gravar { c in
            guard !c.contas.contains(where: { $0.id == conta.id }) else { return }
            c.contas.insert(conta, at: min(indice, c.contas.count))
        }
    }

    /// O nome que aparece no iPhone (campo `conta` da config).
    func renomearConta(id: String, para nome: String) {
        gravar { c in if let i = c.contas.firstIndex(where: { $0.id == id }) { c.contas[i].conta = nome } }
    }

    func mostrarConta(id: String, noIphone on: Bool) {
        gravar { c in if let i = c.contas.firstIndex(where: { $0.id == id }) { c.contas[i].mostrar = on } }
    }
}

/// O que a janela Adicionar conta guarda enquanto está aberta.
struct EstadoConta: Equatable {
    var servico = "Claude"
    var token = ""
    var nome = ""
    var mostrarToken = false
    var erro = ""
    var conferindo = false
    var esperando = false
}

struct AvisoUso: Equatable {
    var id = UUID()
    var texto: String
    var comDesfazer: Bool
}

@MainActor
final class PainelUso: ObservableObject {
    /// O painel que a seção usa. Nas fotos das telas é trocado por um de exemplo.
    static var atual = PainelUso()

    @Published var usos: [String: UsoConta] = [:]
    /// Por que uma conta ficou sem número (token ausente neste app, recusado, sem rede...). Só entra conta sem medição.
    @Published var motivos: [String: String] = [:]
    @Published var aviso: AvisoUso?
    @Published var conta: EstadoConta?
    @Published var achadas: [ContaEncontrada] = []
    /// Só nas fotos: cartão com o mouse em cima e campo com o foco do teclado.
    @Published var sobreFixo: String?
    @Published var focoFixo = false

    var agora: () -> Date
    let casa: URL
    let cofre: CofreDeToken
    let leitorToken: LeitorDeUsoPorToken
    private var desfazer: (() -> Void)?
    private var tarefaAviso: Task<Void, Never>?
    private var tarefaLogin: Task<Void, Never>?

    init(agora: @escaping () -> Date = Date.init, casa: URL = FileManager.default.homeDirectoryForCurrentUser,
         cofre: CofreDeToken = AmbienteDeTeste.ativo ? CofreEmMemoria() : Chaveiro(), leitorToken: LeitorDeUsoPorToken = LeitorComCache()) {
        self.agora = agora
        self.casa = casa
        self.cofre = cofre
        self.leitorToken = leitorToken
    }

    // MARK: Uso

    /// Lê o uso de todas as contas (as escondidas do iPhone também aparecem no Mac).
    func atualizar(_ contas: [ContaIA]) async {
        let casa = casa, cofre = cofre, leitor = leitorToken, agora = agora()
        let lido = await Self.lerUsoComMotivos(contas: contas, casa: casa, cofre: cofre, leitor: leitor, agora: agora)
        if lido.usos != usos { usos = lido.usos }
        if lido.motivos != motivos { motivos = lido.motivos }
    }

    nonisolated static func lerUso(contas: [ContaIA], casa: URL, cofre: CofreDeToken, leitor: LeitorDeUsoPorToken, agora: Date,
                                 tokenDoPerfil: @Sendable (String, URL) -> String? = TokenDoPerfil.ler) async -> [String: UsoConta] {
        await lerUsoComMotivos(contas: contas, casa: casa, cofre: cofre, leitor: leitor, agora: agora, tokenDoPerfil: tokenDoPerfil).usos
    }

    /// O texto que explica uma conta sem número. O token nunca entra aqui.
    nonisolated static func motivo(_ r: ResultadoDoToken) -> String? {
        switch r {
        case .ok: return nil
        case .recusado: return "O Claude recusou o token. Gere outro com claude setup-token e adicione a conta de novo."
        case .semRede: return "Sem conexão com o Claude para medir. Confira a internet do Mac."
        case .inesperado: return "O Claude respondeu sem o uso da semana para este token."
        }
    }
    static let motivoSemToken = "O token desta conta não está guardado neste app. Remova a conta e adicione de novo."

    nonisolated static func lerUsoComMotivos(contas: [ContaIA], casa: URL, cofre: CofreDeToken, leitor: LeitorDeUsoPorToken, agora: Date,
                                 tokenDoPerfil: @Sendable (String, URL) -> String? = TokenDoPerfil.ler) async -> (usos: [String: UsoConta], motivos: [String: String]) {
        var saida: [String: UsoConta] = [:]
        var motivos: [String: String] = [:]
        var comuns: [ContaIA] = []
        for c in contas {
            if c.nome == "Claude", c.perfil == nil, let token = cofre.ler(conta: c.id) {
                var u = UsoConta(id: c.id, nome: c.nome, conta: c.conta, semana: nil, renova: nil)
                let r = await leitor.ler(token: token)
                if case .ok(let uso) = r {
                    u.semana = uso.semana
                    u.renova = uso.renova.flatMap { $0 > agora ? Datas.iso($0, fuso: TimeZone(identifier: "UTC")!) : nil }
                } else { motivos[c.id] = motivo(r) }
                saida[c.id] = u
            } else {
                var visivel = c
                visivel.mostrar = true
                comuns.append(visivel)
            }
        }
        let l = FonteUso.ler(contas: comuns, claude: casa.appendingPathComponent(".config/claude-account/measure.json"),
                             codex: casa.appendingPathComponent(".codex/sessions"), agora: agora)
        for u in l.valor { saida[u.id] = u }
        // Conta da troca de contas sem medição do autoswitch (ou velha): se ela tem token de setup-token, o Deck mede sozinho.
        for c in comuns where c.nome == "Claude" && saida[c.id]?.semana == nil {
            guard let perfil = c.perfil else { if cofre.ler(conta: c.id) == nil { motivos[c.id] = motivoSemToken }; continue }
            guard let token = tokenDoPerfil(perfil, casa) else { continue }
            let r = await leitor.ler(token: token)
            guard case .ok(let uso) = r else { motivos[c.id] = motivo(r); continue }
            saida[c.id] = UsoConta(id: c.id, nome: c.nome, conta: c.conta, semana: uso.semana,
                                   renova: uso.renova.flatMap { $0 > agora ? Datas.iso($0, fuso: TimeZone(identifier: "UTC")!) : nil })
        }
        return (saida, motivos)
    }

    // MARK: Aviso e Desfazer

    func avisar(_ texto: String, desfazer acao: (() -> Void)? = nil) {
        let novo = AvisoUso(texto: texto, comDesfazer: acao != nil)
        aviso = novo
        desfazer = acao
        tarefaAviso?.cancel()
        tarefaAviso = Task { [weak self] in
            try? await Task.sleep(nanoseconds: acao == nil ? 2_600_000_000 : 5_000_000_000)
            guard !Task.isCancelled, let self, self.aviso?.id == novo.id else { return }
            self.aviso = nil
            self.desfazer = nil
        }
    }

    var podeDesfazer: Bool { desfazer != nil }

    func desfazerUltimo() {
        guard let f = desfazer else { return }
        desfazer = nil
        f()
        avisar("Desfeito")
    }

    // MARK: Cartão

    func remover(_ id: String, modelo: ModeloApp) {
        guard let (conta, indice) = modelo.removerConta(id: id) else { return }
        // O token sai do Chaveiro já. Fica só na memória, até o Desfazer valer, e depois some com ela.
        let token = cofre.ler(conta: id)
        cofre.apagar(conta: id)
        avisar("Conta \(conta.conta) removida") { [weak self] in
            modelo.restaurarConta(conta, em: indice)
            if let token { try? self?.cofre.guardar(token, conta: id) }
        }
    }

    // MARK: Adicionar conta

    func abrirConta(modelo: ModeloApp) {
        achadas = ContasAchadas.procurar(casa: casa, jaNoPainel: modelo.config.contas)
        conta = EstadoConta()
    }

    func fecharConta() {
        tarefaLogin?.cancel()
        conta = nil
    }

    func somar(_ achada: ContaEncontrada, modelo: ModeloApp) {
        guard modelo.adicionarConta(achada.conta) else { avisar("Não consegui adicionar a conta."); return }
        fecharConta()
        avisar("Conta adicionada. Já aparece no iPhone")
    }

    func adicionarToken(modelo: ModeloApp) async {
        guard let c = conta, c.servico == "Claude", !c.conferindo, !c.token.isEmpty else { return }
        if let e = TokenClaude.erroDeFormato(c.token) { conta?.erro = e; return }
        conta?.erro = ""
        conta?.conferindo = true
        let token = c.token, nome = c.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = await leitorToken.ler(token: token)
        guard conta?.conferindo == true else { return } // fechou enquanto conferia
        conta?.conferindo = false
        switch r {
        case .recusado: conta?.erro = TokenClaude.recusado
        case .semRede: conta?.erro = TokenClaude.semRede
        case .inesperado: conta?.erro = TokenClaude.inesperado
        case .ok(let uso):
            let id = "claude-token-" + UUID().uuidString.prefix(8).lowercased()
            do { try cofre.guardar(token, conta: id) } catch { conta?.erro = TokenClaude.semGuardar; return }
            let nova = ContaIA(id: id, nome: "Claude", conta: nome.isEmpty ? "nova conta" : nome, perfil: nil, mostrar: true)
            guard modelo.adicionarConta(nova) else {
                cofre.apagar(conta: id)
                conta?.erro = "Não consegui salvar a conta."
                return
            }
            usos[id] = UsoConta(id: id, nome: "Claude", conta: nova.conta, semana: uso.semana, renova: uso.renova.map { Datas.iso($0, fuso: TimeZone(identifier: "UTC")!) })
            fecharConta()
            avisar("Conta adicionada. Já aparece no iPhone")
        }
    }

    // MARK: Terminal

    func copiar(_ comando: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(comando, forType: .string)
        avisar("Comando copiado")
    }

    /// Abre o Terminal com o comando já digitado e rodando (um arquivo .command, que o Terminal abre
    /// sem pedir permissão de automação). Para o Codex, passa a esperar o login terminar.
    func abrirNoTerminal(_ comando: String, modelo: ModeloApp) {
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString).command")
        let texto = "#!/bin/zsh\n\(comando)\n"
        do {
            try texto.write(to: arquivo, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arquivo.path)
        } catch { avisar("Não consegui abrir o Terminal."); return }
        NSWorkspace.shared.open(arquivo)
        avisar("Terminal aberto com o comando pronto")
        Task { try? await Task.sleep(nanoseconds: 120_000_000_000); try? FileManager.default.removeItem(at: arquivo) }
        if conta?.servico == "Codex" { esperarLogin(modelo: modelo) }
    }

    /// O login do Codex termina fora do Deck: olha a cada 2 s se a conta apareceu neste Mac.
    private func esperarLogin(modelo: ModeloApp) {
        tarefaLogin?.cancel()
        conta?.esperando = true
        tarefaLogin = Task { [weak self] in
            for _ in 0..<150 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, self.conta != nil else { return }
                let achou = ContasAchadas.procurar(casa: self.casa, jaNoPainel: modelo.config.contas)
                if achou != self.achadas { self.achadas = achou }
                if achou.contains(where: { $0.conta.nome == "Codex" }) { self.conta?.esperando = false; return }
            }
            self?.conta?.esperando = false
        }
    }
}
