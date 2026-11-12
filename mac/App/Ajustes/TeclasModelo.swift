import SwiftUI
import AppKit

/// Aviso que aparece embaixo da janela, com "Desfazer" por 5 segundos (e ⌘Z enquanto durar).
struct AvisoDaJanela: Equatable {
    var id = UUID()
    var texto: String
    var temDesfazer: Bool
}

/// O estado da tela "Suas teclas": que perfil o Mac edita (não muda o que o iPhone mostra), a página,
/// a tecla escolhida e o editor. Tudo grava pela config do ModeloApp (a fonte única).
@MainActor
final class ModeloTeclas: ObservableObject {
    let modelo: ModeloApp
    let catalogo: CatalogoDeApps

    @Published var editando: String
    @Published var sel: String?
    @Published var pagina = 0
    @Published var busca = ""
    @Published var ouvindo = false
    @Published var aviso: AvisoDaJanela?
    @Published var saidaDoTeste = ""
    @Published var arrastando: String?
    @Published var abaDeSoltar: Int?
    /// Ids das teclas acesas agora (lido pelo `estado` de cada tecla, igual ao iPhone).
    @Published var acesas: Set<String>
    /// Sobe quando a tela pede foco no nome (tecla nova, perfil novo).
    @Published var pedidoDeFocoNoNome = 0
    @Published var pedidoDeFocoNoPerfil = 0

    /// Tecla que ainda não tem ação (nova, ou de tipo trocado): o núcleo recusa gravar assim, então ela
    /// vive só aqui, na tela, e vai para a config no instante em que ganha uma ação.
    private struct Rascunho { var perfil: String; var tecla: Tecla; var nova: Bool }
    @Published private var rascunhos: [String: Rascunho] = [:]
    private var ordemDasNovas: [String] = []

    private var desfazer: (() -> Void)?
    private var relogioDoAviso: Task<Void, Never>?
    private var monitor: Any?
    private var captura: CapturaDeTecla?
    /// true quando a escuta pega a tecla antes dos atalhos de outros apps (a tela esconde o aviso de "se o atalho abrir outro app").
    @Published private(set) var capturaGlobal = false
    /// Combinações incompletas sendo montadas na tela, por id de tecla.
    @Published private var montagens: [String: MontagemDeCombinacao] = [:]
    private let pedirAcessibilidade: () -> Void
    private let executar: (Tecla) -> String?
    /// true enquanto o botão do mouse está apertado (trocado nos testes).
    private let mouseApertado: () -> Bool
    private var vigiaDoArrasto: Task<Void, Never>?

    init(modelo: ModeloApp, catalogo: CatalogoDeApps? = nil, acesas: Set<String> = [],
         pedirAcessibilidade: @escaping () -> Void = { if !AcoesSistema.temAcessibilidade() { AcoesSistema.pedirAcessibilidade() } },
         executar: @escaping (Tecla) -> String? = { ExecutorAcoes(shell: ExecutorShell()).executar($0) },
         mouseApertado: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }) {
        self.mouseApertado = mouseApertado
        self.modelo = modelo
        self.catalogo = catalogo ?? CatalogoDeApps()
        self.acesas = acesas
        self.pedirAcessibilidade = pedirAcessibilidade
        self.executar = executar
        let ativo = modelo.config.perfilAtivo
        let perfil = modelo.config.perfis.first { $0.id == ativo } ?? modelo.config.perfis.first
        self.editando = perfil?.id ?? ""
        self.sel = perfil?.teclas.first?.id
    }

    // MARK: Leitura

    var perfis: [Perfil] { modelo.config.perfis }
    var perfilAtivo: String { modelo.config.perfilAtivo }
    /// O perfil que o Mac edita. Se ele sumiu (o iPhone ou o arquivo mudou), volta para o ativo.
    var perfil: Perfil {
        modelo.config.perfis.first { $0.id == editando } ?? modelo.config.perfis.first { $0.id == perfilAtivo } ?? modelo.config.perfis.first
            ?? Perfil(id: "", nome: "", teclas: [])
    }
    /// As teclas do perfil como a tela mostra: as gravadas (com o rascunho por cima, se houver) e, no fim,
    /// as novas que ainda esperam uma ação.
    var teclas: [Tecla] {
        let p = perfil
        let gravadas = p.teclas.map { t in rascunhos[t.id].flatMap { $0.perfil == p.id ? $0.tecla : nil } ?? t }
        let novas = ordemDasNovas.compactMap { id in rascunhos[id].flatMap { $0.nova && $0.perfil == p.id ? $0.tecla : nil } }
        return gravadas + novas
    }
    /// Só as teclas já gravadas na config do perfil.
    private var gravadas: [Tecla] { perfil.teclas }
    var porPagina: Int { LogicaTeclas.porPagina(comp: modelo.config.comp) }
    var paginas: [[Tecla]] { LogicaTeclas.paginas(teclas, porPagina: porPagina) }
    var paginaAtual: Int { min(max(pagina, 0), paginas.count - 1) }
    var tecla: Tecla? { teclas.first { $0.id == sel } }
    var iphoneMostraEstePerfil: Bool { perfil.id == perfilAtivo }

    /// Chamado quando a config muda por fora: garante que perfil e tecla escolhidos ainda existem.
    func conferir() {
        // Rascunho cuja tecla ou perfil sumiu por fora (o iPhone apagou) não tem mais onde entrar.
        for (id, r) in rascunhos {
            guard let p = modelo.config.perfis.first(where: { $0.id == r.perfil }) else { rascunhos[id] = nil; continue }
            if !r.nova, !p.teclas.contains(where: { $0.id == id }) { rascunhos[id] = nil }
        }
        ordemDasNovas.removeAll { rascunhos[$0] == nil }
        if !perfis.contains(where: { $0.id == editando }) { editando = perfil.id }
        if tecla == nil { sel = teclas.first?.id }
    }

    // MARK: Gravar

    private func mudarPerfil(_ f: (inout Perfil) -> Void) {
        let id = perfil.id
        modelo.gravar { c in
            guard let i = c.perfis.firstIndex(where: { $0.id == id }) else { return }
            f(&c.perfis[i])
        }
    }

    private func mudarTecla(_ f: (inout Tecla) -> Void) {
        guard let id = sel, var t = teclas.first(where: { $0.id == id }) else { return }
        f(&t)
        definir(t)
    }

    private static func semAcao(_ t: Tecla) -> Bool { t.valor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Põe a tecla na config quando ela já tem ação. Sem ação, ou se a gravação for recusada, fica no
    /// rascunho (a tela mostra o que a pessoa fez, e o motivo da recusa aparece no aviso da seção).
    private func definir(_ t: Tecla) {
        let pid = perfil.id
        let existe = gravadas.contains { $0.id == t.id }
        if !Self.semAcao(t) {
            modelo.gravar { c in
                guard let i = c.perfis.firstIndex(where: { $0.id == pid }) else { return }
                if let k = c.perfis[i].teclas.firstIndex(where: { $0.id == t.id }) { c.perfis[i].teclas[k] = t } else { c.perfis[i].teclas.append(t) }
            }
            if gravadas.contains(t) { rascunhos[t.id] = nil; ordemDasNovas.removeAll { $0 == t.id }; return }
        }
        rascunhos[t.id] = Rascunho(perfil: pid, tecla: t, nova: !existe)
        if !existe, !ordemDasNovas.contains(t.id) { ordemDasNovas.append(t.id) }
    }

    /// Grava a ordem escolhida na tela: só as teclas já gravadas mudam de lugar, as novas ficam no fim.
    private func gravarOrdem(_ novas: [Tecla]) {
        let ids = novas.map(\.id)
        mudarPerfil { p in p.teclas.sort { (ids.firstIndex(of: $0.id) ?? .max) < (ids.firstIndex(of: $1.id) ?? .max) } }
    }

    // MARK: Avisos

    func avisar(_ texto: String, desfazer f: (() -> Void)? = nil) {
        desfazer = f
        let a = AvisoDaJanela(texto: texto, temDesfazer: f != nil)
        withAnimation(Tema.Mov.entra) { aviso = a }
        relogioDoAviso?.cancel()
        relogioDoAviso = Task { [weak self] in
            try? await Task.sleep(nanoseconds: f == nil ? 2_600_000_000 : 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.esconderAviso(a.id)
        }
    }

    private func esconderAviso(_ id: UUID) {
        guard aviso?.id == id else { return }
        withAnimation(Tema.Mov.sai) { aviso = nil }
        desfazer = nil
    }

    /// "Desfazer" no aviso ou ⌘Z.
    func desfazerAgora() {
        guard let f = desfazer else { return }
        desfazer = nil
        f()
        avisar("Desfeito")
    }

    var podeDesfazer: Bool { desfazer != nil }

    // MARK: Perfis

    func editarPerfil(_ id: String) {
        guard perfis.contains(where: { $0.id == id }) else { return }
        editando = id
        sel = teclas.first?.id
        pagina = 0
        busca = ""
        parar()
        atualizarAcesas()
    }

    func novoPerfil() {
        let id = LogicaTeclas.idNovo(prefixo: "p", existentes: perfis.map(\.id))
        modelo.gravar { $0.perfis.append(Perfil(id: id, nome: "Novo perfil", teclas: [])) }
        editarPerfil(id)
        pedidoDeFocoNoPerfil += 1
    }

    /// Nome vazio não grava (todo perfil precisa de um): o campo guarda o texto enquanto a pessoa digita.
    func renomearPerfil(_ nome: String) {
        guard !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mudarPerfil { $0.nome = nome }
    }

    func usarNoIphone() {
        let p = perfil
        modelo.usarPerfil(p.id)
        avisar("O iPhone agora mostra o perfil \(p.nome)")
    }

    func excluirPerfil() {
        guard perfis.count > 1, let i = perfis.firstIndex(where: { $0.id == editando }) else { return }
        let velho = perfis[i]
        let eraAtivo = perfilAtivo == velho.id
        modelo.gravar { c in
            c.perfis.remove(at: i)
            if eraAtivo { c.perfilAtivo = c.perfis[0].id }
        }
        editarPerfil(perfilAtivo)
        avisar("Perfil \(velho.nome) excluído") { [weak self] in
            self?.modelo.gravar { c in
                c.perfis.insert(velho, at: min(i, c.perfis.count))
                if eraAtivo { c.perfilAtivo = velho.id }
            }
            self?.editarPerfil(velho.id)
        }
    }

    // MARK: Teclas

    func escolher(_ id: String) {
        arrastando = nil
        guard sel != id else { return }
        sel = id
        busca = ""
        saidaDoTeste = ""
        parar()
    }

    func irParaPagina(_ i: Int) { pagina = i }

    func novaTecla() {
        let id = LogicaTeclas.idNovo(prefixo: "t", existentes: teclas.map(\.id))
        definir(Tecla(id: id, nome: LogicaTeclas.nomePadrao, tipo: "app", valor: "", estado: nil, icone: ""))
        sel = id
        pagina = LogicaTeclas.paginaDe(indice: teclas.count - 1, porPagina: porPagina)
        busca = ""
        parar()
        pedidoDeFocoNoNome += 1
    }

    /// Nome vazio não grava (a config exige nome): o campo guarda o texto enquanto a pessoa digita.
    func renomear(_ nome: String) {
        guard !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mudarTecla { $0.nome = nome }
    }

    func escolherTipo(_ tipo: TipoDeTecla) {
        guard let t = tecla else { return }
        if t.tipo != tipo.rawValue {
            montagens[t.id] = nil
            mudarTecla { $0.tipo = tipo.rawValue; $0.valor = "" }
            if tipo == .tecla { pedirAcessibilidade() }
        }
        parar()
        busca = ""
        saidaDoTeste = ""
    }

    func escolherApp(_ app: AppDoMac) {
        let nomes = Set(catalogo.apps.map(\.nome) + catalogo.apps.map(\.valor) + catalogo.maisUsados.map(\.nome))
        mudarTecla {
            $0.nome = LogicaTeclas.nomeAposEscolher(atual: $0.nome, escolhido: app.nome, nomesDeApps: nomes)
            $0.valor = app.valor
            $0.icone = app.valor
        }
        avisar("\(app.nome) escolhido")
    }

    func escolherAtalho(_ nome: String) {
        mudarTecla { $0.nome = LogicaTeclas.nomeAposEscolher(atual: $0.nome, escolhido: nome); $0.valor = nome }
    }

    func escolherCombinacao(_ valor: String) {
        if let id = sel { montagens[id] = nil }
        mudarTecla { $0.valor = valor }
    }

    /// Comando vazio vira rascunho: a tecla fica sem ação até a pessoa escrever um.
    func escolherComando(_ valor: String, nome: String? = nil) {
        mudarTecla {
            if let nome { $0.nome = LogicaTeclas.nomeAposEscolher(atual: $0.nome, escolhido: nome) }
            $0.valor = valor
        }
    }

    func escolherIcone(_ icone: String) { mudarTecla { $0.icone = icone } }

    func excluirTecla() {
        guard let i = teclas.firstIndex(where: { $0.id == sel }) else { return }
        let velha = teclas[i]
        let gravada = gravadas.first { $0.id == velha.id }
        let eraNova = gravada == nil
        if !eraNova { mudarPerfil { p in p.teclas.removeAll { $0.id == velha.id } } }
        rascunhos[velha.id] = nil
        ordemDasNovas.removeAll { $0 == velha.id }
        sel = LogicaTeclas.escolhidaApos(excluir: i, restantes: teclas)
        pagina = min(pagina, paginas.count - 1)
        let perfilId = perfil.id
        avisar("\"\(velha.nome)\" excluída") { [weak self] in
            guard let self else { return }
            self.editando = perfilId
            if let g = gravada {
                self.mudarPerfil { $0.teclas.insert(g, at: min(i, $0.teclas.count)) }
                if velha != g { self.definir(velha) }
            } else {
                self.definir(velha)
            }
            self.sel = velha.id
            self.pagina = LogicaTeclas.paginaDe(indice: i, porPagina: self.porPagina)
        }
    }

    // MARK: Arrastar

    func arrastar(_ id: String) {
        escolher(id)
        arrastando = id
        vigiarArrasto(id)
    }

    /// Soltar fora de qualquer tecla ou aba cancela o arrasto sem avisar ninguém. Quando o botão do mouse
    /// sobe e nenhum alvo cuidou, a tecla deixa de ficar apagada.
    private func vigiarArrasto(_ id: String) {
        vigiaDoArrasto?.cancel()
        vigiaDoArrasto = Task { [weak self] in
            while let self, !Task.isCancelled, self.arrastando == id {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !self.mouseApertado() {
                    // Dá a vez a quem recebeu o soltar, que limpa o estado por conta própria.
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if self.arrastando == id { self.terminouDeArrastar() }
                    return
                }
            }
        }
    }

    func moverArrastada(para alvo: String) {
        guard let id = arrastando else { return }
        guard gravadas.contains(where: { $0.id == id }) else { return }
        let novas = LogicaTeclas.mover(teclas, id: id, para: alvo)
        guard novas != teclas else { return }
        gravarOrdem(novas)
    }

    func soltarNaAba(_ i: Int) {
        defer { arrastando = nil; abaDeSoltar = nil }
        guard let id = arrastando, gravadas.contains(where: { $0.id == id }) else { return }
        let novas = LogicaTeclas.soltarNaPagina(teclas, id: id, pagina: i, porPagina: porPagina)
        gravarOrdem(novas)
        if let k = novas.firstIndex(where: { $0.id == id }) { pagina = LogicaTeclas.paginaDe(indice: k, porPagina: porPagina) }
        sel = id
    }

    func terminouDeArrastar() { arrastando = nil; abaDeSoltar = nil }

    // MARK: Gravar combinação

    func alternarGravacao() { ouvindo ? parar() : comecar() }

    /// Liga a escuta. Com Acessibilidade, captura antes dos atalhos de outros apps (CapturaDeTecla). Sem ela, ou se o
    /// sistema recusar, cai no monitor local, que só vê a tecla que chegou ao Deck.
    private func comecar() {
        ouvindo = true
        capturaGlobal = false
        if let c = CapturaDeTecla.iniciar(aoApertar: { [weak self] t in self?.receber(t.codigo, t.controle, t.opcao, t.comando, t.shift) },
                                          aoAcabar: { [weak self] in self?.terminouCaptura() }) {
            captura = c
            capturaGlobal = true
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.ouvindo else { return e }
            let f = e.modifierFlags
            self.receber(e.keyCode, f.contains(.control), f.contains(.option), f.contains(.command), f.contains(.shift))
            return nil
        }
    }

    private func receber(_ codigo: UInt16, _ controle: Bool, _ opcao: Bool, _ comando: Bool, _ shift: Bool) {
        guard ouvindo else { return }
        switch CombinacaoEmTexto.interpretar(codigo: codigo, controle: controle, opcao: opcao, comando: comando, shift: shift) {
        case .cancelou: parar()
        case .ignorar: break
        case .faltaControle: avisar("Use pelo menos uma tecla de controle (⌘, ⌥, ⌃ ou ⇧)")
        case .gravou(let v): parar(); escolherCombinacao(v); avisar("Combinação gravada")
        }
    }

    /// A captura se desligou sozinha (o Deck saiu da frente ou o tempo acabou).
    private func terminouCaptura() {
        captura = nil
        if ouvindo { parar(); avisar("Gravação cancelada. Se o atalho abrir outro app, monte a combinação escolhendo as teclas") }
    }

    func parar() {
        ouvindo = false
        capturaGlobal = false
        captura?.parar(); captura = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    // MARK: Montar combinação sem apertar

    /// A montagem da tecla escolhida: o que a pessoa está ligando na tela, ou a combinação já gravada.
    func montagem(de t: Tecla) -> MontagemDeCombinacao { montagens[t.id] ?? MontagemDeCombinacao(valor: t.valor) }

    func alternarModificador(_ m: Modificadores) {
        guard let t = tecla else { return }
        var mont = montagem(de: t)
        mont.alternar(m)
        aplicar(mont, em: t)
    }

    func escolherTeclaDaMontagem(_ nome: String) {
        guard let t = tecla else { return }
        var mont = montagem(de: t)
        mont.tecla = nome
        aplicar(mont, em: t)
    }

    /// Só grava na config quando a montagem está completa. Incompleta, ela vive na tela e a combinação que
    /// já estava gravada continua valendo no iPhone.
    private func aplicar(_ mont: MontagemDeCombinacao, em t: Tecla) {
        parar()
        if let v = mont.valor {
            montagens[t.id] = nil
            if v != t.valor { escolherCombinacao(v) }
        } else {
            montagens[t.id] = mont
        }
    }

    // MARK: Testar comando

    func testarComando() {
        guard let t = tecla else { return }
        saidaDoTeste = "Rodando..."
        let executar = self.executar
        Task.detached(priority: .userInitiated) { [weak self] in
            let inicio = Date()
            let erro = executar(t)
            let ms = Int(Date().timeIntervalSince(inicio) * 1000)
            await self?.mostrarTeste(erro ?? "Rodou sem erro em \(ms) ms")
        }
    }

    private func mostrarTeste(_ texto: String) { saidaDoTeste = texto }

    // MARK: Teclas acesas

    func atualizarAcesas() {
        let lista = teclas
        Task.detached(priority: .utility) { [weak self] in
            let ids = Set(TeclasAcesas.ler(lista, executor: ExecutorShell()))
            await self?.receberAcesas(ids)
        }
    }

    private func receberAcesas(_ ids: Set<String>) { acesas = ids }
}
