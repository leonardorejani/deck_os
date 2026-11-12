import Foundation
import AppKit

/// O login do Spotify nos Ajustes: guarda a chave do app, abre o navegador, espera o retorno local e
/// troca o código pelos tokens (que ficam no Chaveiro, nunca no config.json). A conta é a mesma que o
/// servidor usa para os aparelhos, a fila, curtir e repetir.
@MainActor
final class ModeloSpotify: ObservableObject {
    let conta: ContaSpotify
    @Published private(set) var conectado: Bool
    @Published private(set) var conectando = false
    /// O retorno do navegador já chegou e o Deck está confirmando o login com o Spotify.
    @Published private(set) var confirmando = false
    /// O nome da conta conectada, para a pessoa ver quem entrou.
    @Published private(set) var nome: String?
    /// O texto do campo da chave.
    @Published var chave: String
    /// O motivo do último login que não deu certo, na linha da seção.
    @Published private(set) var erro: String?
    /// "Avançado: usar a minha própria chave" aberto. Abre sozinho quando o Spotify recusa a conta na chave do Deck.
    @Published var avancadoAberto = false
    /// Quem mostra o aviso curto na janela (ModeloApp.avisar).
    var avisar: (String, Bool) -> Void = { _, _ in }
    /// Escreve no deck.log cada passo do login (nunca o código, o state nem os tokens).
    var registrar: @Sendable (String) -> Void = { _ in }
    /// Abre a página de login do Spotify no navegador (nos testes, simula quem clica em Permitir).
    var abrirNavegador: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    var portaDoRetorno: UInt16 = RetornoLocal.portaPadrao
    /// Quanto o Deck espera a pessoa autorizar no navegador.
    var esperaMaxima: TimeInterval = 180
    private var espera: EsperaDoRetorno?

    init(conta: ContaSpotify) {
        self.conta = conta
        self.conectado = conta.conectado
        self.chave = conta.chavePropria ?? ""
        self.nome = conta.nome
    }

    var chaveValida: Bool { ContaSpotify.chaveValida(chave.trimmingCharacters(in: .whitespacesAndNewlines)) }

    /// O Deck já traz a chave do app: a pessoa só entra na conta, sem colar nada.
    var temChaveEmbutida: Bool { conta.temChaveEmbutida }

    /// A pessoa colou a própria chave (que vale no lugar da do Deck).
    var usaChavePropria: Bool { conta.chavePropria != nil }

    /// Pronto para conectar: chave colada inteira, ou campo vazio com a chave do Deck.
    private var temChave: Bool {
        chaveValida || (temChaveEmbutida && chave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var situacao: SituacaoSpotify { SpotifyLogica.situacao(chaveValida: temChave, conectado: conectado, conectando: conectando) }

    func atualizar() {
        conectado = conta.conectado
        nome = conta.nome
        if conectado, nome == nil { buscarNome() }
        // O Spotify recusou esta conta na chave do Deck (numa chamada do player): mostra o passo a passo da chave própria.
        if conta.precisaChavePropria, !conectado { pedirChavePropria() }
    }

    private func buscarNome() {
        let conta = self.conta
        Task {
            let n = await Task.detached { conta.atualizarNome() }.value
            if let n, n != nome { nome = n }
            resincronizar()
        }
    }

    private func pedirChavePropria() {
        erro = ErroSpotify.semCadastro.texto
        avancadoAberto = true
    }

    /// Guarda a chave assim que ela está inteira (32 letras e números), sem esperar o botão.
    func guardarChave() {
        let c = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContaSpotify.chaveValida(c), c != conta.clientId else { return }
        _ = conta.definirClientId(c)
        conectado = conta.conectado
    }

    func conectar() async {
        guard !conectando else { return }
        erro = nil
        let vazia = chave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !(vazia && temChaveEmbutida), let falha = conta.definirClientId(chave) { return falhar(falha) }
        conectando = true
        confirmando = false
        registrar("spotify: login iniciado (\(vazia ? "chave do Deck" : "chave própria"))")
        defer { conectando = false; confirmando = false; espera = nil }

        let espera = EsperaDoRetorno()
        self.espera = espera
        let servidor = RetornoLocal(porta: portaDoRetorno)
        let aberta = await Task.detached { Result { try servidor.iniciar { espera.entregar($0) } } }.value
        defer { servidor.parar() }
        let porta: UInt16
        switch aberta {
        case .success(let p): porta = p
        case .failure(let e):
            registrar("spotify: a porta do retorno não abriu")
            return falhar((e as? ErroServidor)?.description ?? "Não consegui abrir o retorno do login do Spotify.")
        }
        let pendente: LoginPendente
        switch conta.prepararLogin(redirecionamento: RetornoLocal.endereco(porta: porta)) {
        case .success(let p): pendente = p
        case .failure(let e): return falhar(e.texto)
        }
        let registrar = self.registrar
        espera.avisoDeIgnorado = { registrar("spotify: chegou um pedido na porta do retorno que não é deste login, ignorado") }
        espera.esperar(estado: pendente.estado)
        registrar("spotify: navegador aberto, esperando o retorno em \(RetornoLocal.endereco(porta: porta))")
        abrirNavegador(pendente.url)
        guard let retorno = await espera.aguardar(segundos: esperaMaxima) else {
            if espera.cancelado { registrar("spotify: cancelado pela pessoa"); return falhar("Login do Spotify cancelado.") }
            registrar("spotify: tempo esgotado, o navegador não voltou para o Deck")
            return falhar(Self.textoDeTempoEsgotado)
        }
        registrar("spotify: retorno recebido (\(retorno.erro.map { "erro \($0)" } ?? "com código"))")
        confirmando = true
        let conta = self.conta
        let resultado = await Task.detached { conta.concluirLogin(pendente, retorno: retorno) }.value
        if let falha = resultado { registrar("spotify: login não concluiu (\(falha))"); return falhar(falha) }
        conectado = conta.conectado
        registrar("spotify: conectado")
        avisar("Spotify conectado", false)
        NSApp.activate(ignoringOtherApps: true)
        // Já conectou: a tela não volta ao "Esperando" enquanto o nome da conta não chega (o /me pode demorar).
        conectando = false
        confirmando = false
        let nomeDaConta = await Task.detached { conta.atualizarNome() }.value
        nome = nomeDaConta
        resincronizar()
    }

    /// Relê a conta depois de uma chamada ao Spotify: se ela apagou o login (conta fora da lista), a tela acompanha.
    private func resincronizar() {
        conectado = conta.conectado
        if !conectado { nome = nil }
        if conta.precisaChavePropria, !conectado { pedirChavePropria() }
    }

    /// Clicar em Cancelar enquanto espera o navegador.
    func cancelar() { espera?.cancelar() }

    /// "Voltar para a chave do Deck": apaga a chave colada e o login que ela fez.
    func usarChaveDoDeck() {
        conta.usarChaveDoDeck()
        chave = ""
        nome = nil
        conectado = conta.conectado
        erro = nil
    }

    static let textoDeTempoEsgotado = "O login do Spotify demorou demais e o navegador não voltou para o Deck. Clique em Conectar para tentar de novo. Se a página do Spotify mostrou um erro, use o Avançado com a sua chave."

    func desconectar() {
        conta.desconectar()
        conectado = false
        nome = nil
        erro = nil
        avisar("Spotify desconectado", false)
    }

    private func falhar(_ texto: String) {
        erro = texto
        if texto == ErroSpotify.semCadastro.texto { avancadoAberto = true }
        avisar(texto, true)
    }
}

/// Espera o retorno do navegador, uma vez só, com limite de tempo ou cancelamento. O retorno pode chegar
/// antes de alguém estar esperando: fica guardado.
final class EsperaDoRetorno: @unchecked Sendable {
    private let trava = NSLock()
    private var continuacao: CheckedContinuation<RetornoLogin?, Never>?
    private var guardado: RetornoLogin?
    private var terminou = false
    private(set) var cancelado = false
    private var estadoEsperado: String?
    /// Chamado quando chega um retorno de outro login (state diferente) e a espera segue.
    var avisoDeIgnorado: @Sendable () -> Void = {}

    /// Só o retorno com este state vale. Pedido de outra aba ou programa local é ignorado e a espera segue.
    func esperar(estado: String) { trava.lock(); estadoEsperado = estado; trava.unlock() }

    func entregar(_ r: RetornoLogin?) {
        trava.lock()
        if let r, r.estado != estadoEsperado { trava.unlock(); avisoDeIgnorado(); return }
        if terminou { trava.unlock(); return }
        terminou = true
        if let c = continuacao { continuacao = nil; trava.unlock(); c.resume(returning: r) } else { guardado = r; trava.unlock() }
    }

    func cancelar() { trava.lock(); cancelado = true; trava.unlock(); entregar(nil) }

    func aguardar(segundos: TimeInterval) async -> RetornoLogin? {
        DispatchQueue.global().asyncAfter(deadline: .now() + segundos) { [self] in entregar(nil) }
        return await withCheckedContinuation { c in
            trava.lock()
            if terminou { let g = guardado; trava.unlock(); c.resume(returning: g) } else { continuacao = c; trava.unlock() }
        }
    }
}

enum SituacaoSpotify: Equatable {
    case semChave, pronto, conectando, conectado
}

/// Os textos e as regras da seção Spotify, sem tela, para testar.
enum SpotifyLogica {
    static func situacao(chaveValida: Bool, conectado: Bool, conectando: Bool) -> SituacaoSpotify {
        if conectando { return .conectando }
        if conectado { return .conectado }
        return chaveValida ? .pronto : .semChave
    }

    static let enderecoDoRetorno = RetornoLocal.endereco(porta: RetornoLocal.portaPadrao)
    static let siteDoSpotify = URL(string: "https://developer.spotify.com/dashboard")!

    static let apoioDoCampo = "Cole aqui a chave do app que você cria de graça no site do Spotify. Ela não é senha"

    static func apoioDoLogin(_ s: SituacaoSpotify, erro: String?, confirmando: Bool = false) -> String {
        if let erro, s != .conectando, s != .conectado { return erro }
        switch s {
        case .conectando where confirmando: return "O navegador voltou. Confirmando com o Spotify..."
        case .semChave: return "Falta colar a chave do app. O player do iPhone segue funcionando sem login"
        case .pronto: return "Abre o navegador para você permitir o acesso. Sem login o player segue funcionando"
        case .conectando: return "Esperando você permitir no navegador..."
        case .conectado: return "O player do iPhone mostra aparelhos, volume, curtir, fila e repetir a música"
        }
    }

    static let avancado = "Avançado: usar a minha própria chave do app"
    static let apoioDoAvancado = "O app do Deck no Spotify é de desenvolvimento: aceita só as contas que o dono adicionou, até 25. Quem não estiver na lista usa a própria chave, criada de graça no site do Spotify"
    static let apoioDoEndereco = "Em Redirect URIs, no app do Spotify, cole exatamente este endereço"

    static let passos = """
        Como criar a chave, uma vez só (leva uns 2 minutos):
        1. Entre em developer.spotify.com/dashboard com a sua conta do Spotify e clique em Create app.
        2. Dê qualquer nome e descrição. Em Redirect URIs, cole o endereço acima e clique em Add.
        3. Em Which API/SDKs are you planning to use, marque Web API. Aceite os termos e clique em Save.
        4. Abra Settings, copie o Client ID e cole no campo da chave. Depois clique em Conectar.
        Tocar, pausar, pular, volume e capa funcionam sem login. O login só libera aparelhos, curtir, fila e repetir a música, e isso pede o Spotify Premium (na conta que cria o app também).
        """
}
