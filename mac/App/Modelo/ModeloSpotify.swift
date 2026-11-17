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
    /// O Spotify mandou esperar (limite de leituras) e a espera ainda não passou. Relido em `atualizar()`.
    @Published private(set) var limitado = false
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

    /// `lerNaPartida: false` (o app de verdade): nada aqui toca no Chaveiro ao nascer. O que está guardado lá chega por
    /// `atualizar()`, em segundo plano, na primeira vez que uma tela precisa. Ler o Chaveiro na linha principal faz o macOS
    /// pedir a senha e o app inteiro espera a resposta.
    init(conta: ContaSpotify, lerNaPartida: Bool = true) {
        self.conta = conta
        if lerNaPartida {
            self.conectado = conta.conectado
            self.chave = conta.chavePropria ?? ""
            self.nome = conta.nome
            self.usaChavePropria = conta.chavePropria != nil
            self.carregado = true
        } else {
            self.conectado = false
            self.chave = ""
            self.nome = nil
            self.usaChavePropria = false
        }
    }

    private var carregado = false

    var chaveValida: Bool { ContaSpotify.chaveValida(chave.trimmingCharacters(in: .whitespacesAndNewlines)) }

    /// O Deck já traz a chave do app: a pessoa só entra na conta, sem colar nada.
    var temChaveEmbutida: Bool { conta.temChaveEmbutida }

    /// A pessoa colou a própria chave (que vale no lugar da do Deck).
    @Published private(set) var usaChavePropria = false

    /// Pronto para conectar: chave colada inteira, ou campo vazio com a chave do Deck.
    private var temChave: Bool {
        chaveValida || (temChaveEmbutida && chave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var situacao: SituacaoSpotify { SpotifyLogica.situacao(chaveValida: temChave, conectado: conectado, conectando: conectando) }

    /// O aviso de limite com a chave do Deck, com a sugestão da chave própria.
    var avisoDeLimite: Bool { SpotifyLogica.mostrarAvisoDeLimite(limitado: limitado, chaveDoDeckEmUso: temChaveEmbutida && !usaChavePropria) }
    /// O Spotify recusou esta conta na chave do Deck.
    var contaNaoLiberada: Bool { erro == SpotifyLogica.avisoDeCadastro }
    var nomeDaChaveEmUso: String { SpotifyLogica.nomeDaChave(propria: usaChavePropria) }

    func atualizar() {
        guard carregado else { carregarEmSegundoPlano(); return }
        limitado = conta.limiteRestante() != nil
        conectado = conta.conectado
        nome = conta.nome
        if conectado, nome == nil { buscarNome() }
        // O Spotify recusou esta conta na chave do Deck (numa chamada do player): mostra o passo a passo da chave própria.
        if conta.precisaChavePropria, !conectado { pedirChavePropria() }
    }

    private var carregando = false

    /// A primeira leitura do Chaveiro, fora da linha principal. As telas mostram "desconectado" até ela voltar.
    private func carregarEmSegundoPlano() {
        guard !carregando else { return }
        carregando = true
        let conta = self.conta
        Task {
            let lido = await Task.detached { (conta.conectado, conta.chavePropria, conta.nome) }.value
            carregando = false
            carregado = true
            conectado = lido.0
            usaChavePropria = lido.1 != nil
            if chave.isEmpty { chave = lido.1 ?? "" }
            nome = lido.2
            atualizar()
        }
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
        usaChavePropria = conta.chavePropria != nil
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
        usaChavePropria = false
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

    static let tituloDoBloco = "Usar a sua própria chave (recomendado se o Deck não é só seu)"
    static let resumoDoBloco = "A chave que vem no Deck está em modo de desenvolvimento do Spotify: só 5 contas cadastradas pelo dono do Deck conseguem entrar com ela, e o limite de leituras é dividido entre todo mundo que usa a mesma chave. Com a sua própria chave você tem o seu limite e não depende de cadastro. É grátis e leva poucos minutos."
    static let detalheDoBloco = "Conta que não foi cadastrada pelo dono do Deck é recusada no login com a chave do Deck, e aí só a sua chave resolve. Quando o Spotify limita as leituras, o painel do iPhone para de atualizar aparelhos e fila por um tempo, e a chave do Deck divide esse limite com todo mundo. Tocar, pausar, pular, volume e capa funcionam sem login. Para controlar a reprodução (aparelhos, curtir, fila e repetir a música) é preciso o Spotify Premium, também na conta que cria o app. A chave não é senha e fica guardada só neste Mac."
    static let apoioDoEndereco = "Em Redirect URIs, no app do Spotify, cole exatamente este endereço"

    static let nomeDaChaveDoDeck = "Chave do Deck"
    static let nomeDaChaveDaPessoa = "Sua chave"
    static func nomeDaChave(propria: Bool) -> String { propria ? nomeDaChaveDaPessoa : nomeDaChaveDoDeck }

    static let avisoDeCadastro = ErroSpotify.semCadastro.texto
    static let tituloDoLimite = "O Spotify limitou as leituras da chave do Deck"
    static let apoioDoLimite = "O limite é dividido entre todo mundo que usa essa chave e passa sozinho depois de um tempo. Com a sua própria chave o limite é só seu"

    /// A linha do limite só aparece com a chave do Deck: com chave própria o limite é da própria pessoa.
    static func mostrarAvisoDeLimite(limitado: Bool, chaveDoDeckEmUso: Bool) -> Bool { limitado && chaveDoDeckEmUso }

    /// O passo a passo, na ordem. O 1, o 4, o 6 e o 7 ganham botão ou campo na tela.
    static let passos: [(titulo: String, apoio: String?)] = [
        ("1. Abra o painel de desenvolvedor do Spotify", "Entre com a sua conta do Spotify. O painel abre no navegador só quando você clicar"),
        ("2. Crie um app", "Clique em Create app. Nome e descrição podem ser qualquer coisa"),
        ("3. Marque Web API", "Em Which API/SDKs are you planning to use, marque Web API"),
        ("4. Cole o endereço de retorno", "Em Redirect URIs, cole este endereço exato e clique em Add"),
        ("5. Salve", "Aceite os termos e clique em Save"),
        ("6. Copie o Client ID e cole aqui", "No app criado, abra Settings e copie o Client ID"),
        ("7. Toque em Conectar", nil),
    ]
}
