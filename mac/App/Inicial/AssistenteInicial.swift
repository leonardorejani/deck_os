import Foundation
import SwiftUI
import AppKit
import Combine

/// O que a configuração inicial faz fora dela: fechar a janela, abrir o menu da barra e a janela
/// "Adicionar conta". No app vêm do sistema, nas fotos e nos testes ficam vazias.
struct AcoesDaInicial {
    var fechar: () -> Void = {}
    var abrirMenuDaBarra: () -> Void = {}
    /// Abre a janela "Adicionar conta" por cima. Quando a conta é conectada, chama `contaConectada`.
    var conectarOutraConta: (_ contaConectada: @escaping (ContaAchada) -> Void) -> Void = { _ in }
    var copiar: (String) -> Void = { texto in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
}

/// A lógica dos 7 passos (mac.js, abrirIni e TELAS_INI). A tela só lê daqui e chama os métodos.
@MainActor
final class AssistenteInicial: ObservableObject {
    @Published private(set) var passo: PassoInicial = .boas
    @Published var contasMarcadas: Set<String>
    @Published var teclasMarcadas: Set<String>
    @Published var comp: String
    @Published private(set) var achadas: [ContaAchada]
    @Published private(set) var sugestoes: [SugestaoDeTecla]
    @Published private(set) var acessos: [AcessoMac: EstadoDoAcesso] = [:]
    @Published private(set) var codigo: String
    @Published private(set) var aviso: String?
    /// O endereço que o iPhone abre. Fixo nas fotos, e vindo do sistema no app.
    @Published private(set) var endereco: String

    let modelo: ModeloApp
    let acoes: AcoesDaInicial
    private let pedidos: PedidosDeAcesso
    private let defaults: UserDefaults
    private var vigia: Task<Void, Never>?
    /// O código só existe enquanto o passo do iPhone está na tela (ver `comecarCodigo`).
    private let vivo = CodigoDePareamento()
    private let codigoFixo: String?
    private let enderecoFixo: String?
    private let hostLocal: String?
    private let intervaloDoCodigo: TimeInterval
    private var ouvinte: AnyCancellable?
    private var fimDoAviso: Task<Void, Never>?

    init(modelo: ModeloApp, achadas: [ContaAchada]? = nil, sugestoes: [SugestaoDeTecla]? = nil,
         pedidos: PedidosDeAcesso? = nil, acoes: AcoesDaInicial = AcoesDaInicial(),
         codigo: String? = nil, endereco: String? = nil, hostLocal: String? = nil,
         defaults: UserDefaults = .standard, intervaloDoCodigo: TimeInterval = 1) {
        self.modelo = modelo
        self.defaults = defaults
        self.acoes = acoes
        self.pedidos = pedidos ?? PedidosDoMac()
        let dasContas = achadas ?? ContasDeste.achar()
        self.achadas = dasContas
        self.contasMarcadas = Set(dasContas.map(\.id))
        let lista = sugestoes ?? Self.sugestoesDeste()
        self.sugestoes = lista
        self.teclasMarcadas = Set(lista.map(\.id)).intersection(SugestaoDeTecla.marcadasDePartida)
        self.comp = modelo.config.comp
        self.codigo = codigo ?? ""
        self.codigoFixo = codigo
        self.enderecoFixo = endereco
        self.hostLocal = hostLocal
        self.intervaloDoCodigo = intervaloDoCodigo
        self.endereco = endereco ?? EnderecoDoMac.url(nomeMac: modelo.config.nomeMac, porta: modelo.config.porta,
                                                       hostLocal: hostLocal ?? EnderecoDoMac.hostLocal())
        ouvinte = vivo.$codigo.dropFirst().sink { [weak self] novo in self?.codigo = novo }
        for a in OrdemDosAcessos.todos { if let e = self.pedidos.estado(a), e != .naoPedido { acessos[a] = e } }
    }

    /// As sugestões cujo app existe neste Mac (o comando de apagar a tela vale sempre).
    static func sugestoesDeste() -> [SugestaoDeTecla] {
        SugestaoDeTecla.todas.filter { s in
            guard let app = s.app else { return true }
            return ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices"]
                .contains { FileManager.default.fileExists(atPath: "\($0)/\(app).app") }
        }
    }

    // MARK: Iphone

    var iphone: IphonePareado? { modelo.iphone }
    var iphoneConectado: Bool { modelo.iphone != nil }
    var codigoEmGrupos: String { EnderecoDoMac.codigoEmGrupos(codigo) }

    /// O que o QR leva: endereço, código de pareamento e link do certificado.
    var textoDoQr: String { ParearIphone.textoDoQr(endereco: endereco, codigo: codigoFixo ?? codigo) }

    /// O código só vale enquanto o passo do iPhone está aberto. Entrou nele: gera e se renova sozinho. Saiu do passo
    /// ou fechou a janela: o código é apagado no núcleo.
    private func comecarCodigo() {
        if enderecoFixo == nil, case .ligado(let porta) = modelo.servidor {
            endereco = EnderecoDoMac.url(nomeMac: modelo.config.nomeMac, porta: porta, hostLocal: hostLocal ?? EnderecoDoMac.hostLocal())
        }
        vivo.iniciar(modelo.pareamento, fixo: codigoFixo, intervalo: intervaloDoCodigo)
    }

    /// A janela abriu (ou reabriu) já no passo do iPhone.
    func abriu() { if passo == .iphone { comecarCodigo() } }

    /// A janela fechou: sem tela, não fica código ativo.
    func fechou() { vivo.parar() }

    func copiarEndereco() {
        acoes.copiar(endereco)
        avisar("Endereço copiado")
    }

    // MARK: Passos

    var podeAvancar: Bool { !(passo == .iphone && !iphoneConectado) }
    var podePular: Bool { passo == .iphone && !iphoneConectado }
    var textoDoBotao: String { passo.primeiro ? "Começar" : passo.ultimo ? "Concluir" : "Continuar" }

    func avancar() {
        guard podeAvancar else { return }
        if passo.ultimo { concluir(); return }
        if let p = PassoInicial(rawValue: passo.rawValue + 1) { passo = p }
        aoMudarDePasso()
    }

    func pular() {
        guard podePular, let p = PassoInicial(rawValue: passo.rawValue + 1) else { return }
        passo = p
        aoMudarDePasso()
    }

    func voltar() {
        guard let p = PassoInicial(rawValue: passo.rawValue - 1) else { return }
        passo = p
        aoMudarDePasso()
    }

    func irPara(_ p: PassoInicial) { passo = p; aoMudarDePasso() }

    private func aoMudarDePasso() {
        if passo == .iphone { comecarCodigo() } else { vivo.parar() }
        if passo == .acessos { vigiarAcessos() } else { vigia?.cancel(); vigia = nil }
    }

    // MARK: Escolhas

    func alternarConta(_ id: String) {
        if contasMarcadas.contains(id) { contasMarcadas.remove(id) } else { contasMarcadas.insert(id) }
    }

    func alternarTecla(_ id: String) {
        if teclasMarcadas.contains(id) { teclasMarcadas.remove(id) } else { teclasMarcadas.insert(id) }
    }

    /// A janela "Adicionar conta" trouxe uma conta: entra na lista já marcada.
    func contaConectada(_ conta: ContaAchada) {
        if let i = achadas.firstIndex(where: { $0.id == conta.id }) { achadas[i] = conta } else { achadas.append(conta) }
        contasMarcadas.insert(conta.id)
        avisar("Conta conectada")
    }

    func conectarOutraConta() { acoes.conectarOutraConta { [weak self] in self?.contaConectada($0) } }

    // MARK: Acessos

    func estado(_ a: AcessoMac) -> EstadoDoAcesso { acessos[a] ?? .naoPedido }

    func permitir(_ a: AcessoMac) async {
        let r = await pedidos.pedir(a)
        acessos[a] = r
        if r == .recusado { avisar("\(a.nome): recusado. Dá para liberar depois em Acessos do Mac") }
        if r == .liberado { avisar("\(a.nome): liberado") }
    }

    func abrirAjustesDoSistema(_ a: AcessoMac) {
        pedidos.abrirAjustes(a)
        avisar("Ajustes do Sistema abertos. Ligue o Deck e volte")
    }

    /// Acessibilidade e Acesso Total ao Disco são ligados na mão nos Ajustes do Sistema: enquanto o
    /// passo está aberto, olha de novo a cada segundo e vira "Liberado" quando a pessoa liga.
    private func vigiarAcessos() {
        vigia?.cancel()
        vigia = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Tema.Inicial.vigiaSegundos * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.reler()
            }
        }
    }

    func reler() {
        for a in OrdemDosAcessos.todos where estado(a) != .liberado {
            if pedidos.estado(a) == .liberado { acessos[a] = .liberado }
        }
    }

    // MARK: Aviso

    func avisar(_ texto: String) {
        aviso = texto
        fimDoAviso?.cancel()
        fimDoAviso = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tema.Inicial.avisoSegundos * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.aviso = nil
        }
    }

    // MARK: Concluir

    func concluir() {
        vigia?.cancel()
        modelo.aplicarConfiguracaoInicial(
            teclas: sugestoes.filter { teclasMarcadas.contains($0.id) }.map(\.tecla),
            contas: achadas.filter { contasMarcadas.contains($0.id) }.map(\.contaIA),
            comp: comp,
            recusados: OrdemDosAcessos.todos.filter { estado($0) == .recusado }, defaults: defaults)
        acoes.fechar()
        acoes.abrirMenuDaBarra()
    }

    deinit { vigia?.cancel(); fimDoAviso?.cancel() }
}

extension ModeloApp {
    /// Grava o que a pessoa escolheu na configuração inicial e marca a configuração como feita.
    /// Primeira vez (teclas ainda as de fábrica): as escolhidas substituem as de fábrica, como no
    /// protótipo. Refazendo (a pessoa já mexeu nas teclas): só entram as que faltam, nada é apagado.
    func aplicarConfiguracaoInicial(teclas teclasEscolhidas: [Tecla], contas contasEscolhidas: [ContaIA], comp: String, recusados: [AcessoMac],
                                    defaults: UserDefaults = .standard) {
        let fabrica = Config.padrao(nomeMac: config.nomeMac).perfis.first?.teclas ?? []
        gravar { c in
            if let i = c.perfis.firstIndex(where: { $0.id == c.perfilAtivo }) {
                let atuais = c.perfis[i].teclas
                if atuais.isEmpty || atuais.map(\.valor) == fabrica.map(\.valor) {
                    c.perfis[i].teclas = Self.comIdsUnicos(teclasEscolhidas, existentes: [])
                } else {
                    let novas = teclasEscolhidas.filter { n in !atuais.contains { $0.tipo == n.tipo && $0.valor == n.valor } }
                    c.perfis[i].teclas = atuais + Self.comIdsUnicos(novas, existentes: atuais)
                }
            }
            for conta in contasEscolhidas where !c.contas.contains(where: { $0.id == conta.id }) { c.contas.append(conta) }
            c.comp = comp
        }
        acessosRecusados = recusados
        marcarConfiguracaoInicialFeita(defaults: defaults)
    }

    private static func comIdsUnicos(_ novas: [Tecla], existentes: [Tecla]) -> [Tecla] {
        var usados = Set(existentes.map(\.id))
        return novas.map { t in
            var t = t
            var id = t.id, n = 2
            while usados.contains(id) { id = "\(t.id)-\(n)"; n += 1 }
            t.id = id
            usados.insert(id)
            return t
        }
    }
}
