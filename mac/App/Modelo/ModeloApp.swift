import Foundation
import SwiftUI

enum EstadoServidor: Equatable {
    case parado
    case ligado(porta: Int)
    case falhou(String)
}

/// O estado do app do Mac. Lê e grava a config pelo ArmazemConfig (a fonte única, a mesma do
/// iPhone), sobe o servidor HTTPS do núcleo e reage quando o config.json muda no disco.
/// As telas só leem daqui e chamam os métodos: nenhuma toca em arquivo ou rede.
@MainActor
final class ModeloApp: ObservableObject {
    @Published private(set) var config: Config
    /// nil = nenhum iPhone pareado. Quem preenche é a seção Conectar iPhone.
    @Published var iphone: IphonePareado?
    /// O app nativo do iPhone falando com o Mac pelo cabo ou pelo Bluetooth. nil = nenhum falou ainda.
    @Published var nativo: AppNativo?
    /// Um iPhone pediu para parear por Bluetooth e espera Recusar ou Permitir (menu da barra e Conectar iPhone).
    @Published var pedidoBluetooth: PedidoDePareamento?
    @Published var renovacao: RenovacaoDoApp
    /// Como está cada acesso do macOS que o Deck usa (a seção Acessos do Mac). Vazio até a primeira leitura.
    @Published var acessos: [AcessoLido] = []
    /// Só os recusados: o selo da barra lateral e o aviso do menu leem daqui.
    @Published var acessosRecusados: [AcessoMac] = []
    @Published var secao: SecaoAjustes = .teclas
    /// O macOS escondeu o item do Deck na barra: os Ajustes mostram como liberar.
    @Published var iconeEscondido = false
    /// Reconfere o item da barra a cada poucos segundos enquanto o aviso está na tela (Modelo/ItemDaBarra.swift).
    var vigiaDoIcone: Task<Void, Never>?
    @Published var configuracaoInicialFeita: Bool
    @Published private(set) var servidor: EstadoServidor = .parado
    /// Texto pronto, em português, do último problema com a config (arquivo danificado, sem permissão).
    @Published private(set) var erro: String?
    /// O aviso curto que aparece na janela por alguns segundos (como o `#aviso` do protótipo).
    @Published private(set) var aviso: AvisoDeTela?
    private var tarefaDoAviso: Task<Void, Never>?
    /// Verdadeiro por 1,8 s depois de gravar: o cabeçalho dos Ajustes diz "Salvo" (mac.js, pintarSinc).
    @Published private(set) var salvoAgora = false
    private var tarefaDoSalvo: Task<Void, Never>?
    /// Sobe quando a config muda por fora (o iPhone gravou), para a tela avisar.
    @Published private(set) var mudancasDeFora = 0
    let defaults: UserDefaults

    let pareamento = Pareamento()
    /// O login do Spotify (Ajustes > Este Mac). A conta dele é a mesma que o servidor usa.
    let spotify: ModeloSpotify
    let abrirComMac: AbrirComMac
    /// Compartilhado com o roteador: a trava dele evita duas trocas do código ao mesmo tempo.
    let rodizio = Rodizio()
    private var tarefaDoRodizio: Task<Void, Never>?

    let decisao = PonteDeDecisao()
    let janelaDePareamento = JanelaDePareamento()
    /// Roda a reinstalação do app no iPhone (Modelo/ModeloRenovacao.swift). Sem ela, "Renovar agora" diz a verdade.
    var renovador: (@MainActor () async -> ResultadoDaRenovacao)?
    /// A renovação em andamento: o botão e a agenda não rodam duas ao mesmo tempo.
    var renovando = false
    /// A última falha desde a última renovação boa, para a agenda saber quando tentar de novo.
    var falhaDaRenovacao: FalhaDaRenovacao?
    /// Pergunta ao devicectl como está o iPhone (no cabo, bloqueado, liberado). Barato, sem compilar.
    var sondarIphone: (@MainActor () async -> SituacaoDoIphone)?
    var tarefaDaRenovacao: Task<Void, Never>?
    /// Onde o log do Deck escreve. Nos testes e nas fotos não escreve em lugar nenhum.
    var registrar: @Sendable (String) -> Void = { _ in }
    var pastaDoProjeto: String?
    var portaDoCabo: PortaDoCabo?
    var radio: RadioPeriferico?
    /// O nome que o iPhone deu ao pedir pareamento por Bluetooth, para o primeiro pedido dele já aparecer com nome.
    var nomeAprovado: String?
    /// Só as fotos: o relógio parado do protótipo (10/11/2026, 12h), para "vence em 2 dias" sair igual.
    var relogio: (() -> Date)?
    var agora: Date { relogio?() ?? Date() }

    private let armazem: ArmazemEmDisco?
    private let arquivoConfig: URL?
    private var vigia: VigiaConfig?
    private var servidorHttps: ServidorHttps?
    /// Quem relê os acessos recusados quando o app volta para a frente (Ajustes/AcessosVerificador.swift).
    var vigiaDeAcessos: AnyObject?

    private static let chaveInicial = "configuracaoInicialFeita"

    /// Com dados de exemplo e sem disco nem rede: as fotos das telas e os testes.
    init(config: Config, iphone: IphonePareado? = nil, acessosRecusados: [AcessoMac] = [],
         configuracaoInicialFeita: Bool = true, abrirComMac: AbrirComMac? = nil, servidor: EstadoServidor = .parado,
         nativo: AppNativo? = nil, pedidoBluetooth: PedidoDePareamento? = nil, renovacao: RenovacaoDoApp = RenovacaoDoApp(),
         defaults: UserDefaults = .standard) {
        self.nativo = nativo
        self.pedidoBluetooth = pedidoBluetooth
        self.renovacao = renovacao
        self.config = config
        self.servidor = servidor
        self.iphone = iphone
        self.acessosRecusados = acessosRecusados
        // Sem leitura de verdade (fotos e testes): o que foi dito recusado fica recusado, o resto liberado.
        self.acessos = OrdemDosAcessos.painel.map { AcessoLido(acesso: $0, situacao: acessosRecusados.contains($0) ? .recusado : .liberado) }
        self.configuracaoInicialFeita = configuracaoInicialFeita
        self.abrirComMac = abrirComMac ?? AbrirComMac()
        self.armazem = nil
        self.arquivoConfig = nil
        self.defaults = defaults
        // Sem Chaveiro nem internet: as fotos e os testes nunca tocam no login de verdade.
        self.spotify = ModeloSpotify(conta: ContaSpotify(armazem: ArmazemSpotifyMemoria(), transporte: TransporteUrlSession()))
        self.spotify.avisar = { [weak self] texto, falha in self?.avisar(texto, falha: falha) }
    }

    /// O app de verdade: a config em ~/Library/Application Support/Deck/config.json.
    init(arquivo: URL = ArmazemConfig.urlPadrao, defaults: UserDefaults = .standard, abrirComMac: AbrirComMac? = nil,
         nomeDoMac: String = Ligacao.nomeDoMac()) {
        let existia = FileManager.default.fileExists(atPath: arquivo.path)
        let base = ArmazemConfig(url: arquivo, nomeMac: nomeDoMac)
        var lido: ArmazemEmDisco?
        var aviso: String?
        do { lido = try ArmazemEmDisco(base) } catch { aviso = (error as? ErroConfig)?.mensagem ?? "Não consegui abrir a configuração do Deck." }
        self.armazem = lido
        self.arquivoConfig = arquivo
        self.config = lido?.ler() ?? Config.padrao(nomeMac: base.nomeMac)
        self.erro = aviso
        self.abrirComMac = abrirComMac ?? AbrirComMac()
        let guardado = defaults.object(forKey: Self.chaveInicial) as? Bool
        self.configuracaoInicialFeita = EstadoInicial.jaFeita(guardado: guardado, configExistia: existia)
        self.defaults = defaults
        self.spotify = ModeloSpotify(conta: ContaSpotify(armazem: ArmazemSpotifyChaveiro(), transporte: TransporteUrlSession()))
        self.renovacao = RenovacaoDoApp.ler(defaults)
        self.registrar = { LogDoDeck.padrao.escrever($0) }
        self.spotify.avisar = { [weak self] texto, falha in self?.avisar(texto, falha: falha) }
        ligarDecisao()
        // O núcleo só entrega o código: quem o recebeu é lembrado aqui, e vale enquanto o código for o mesmo.
        self.iphone = IphoneLembrado.ler(defaults, codigoAtual: config.codigoAcesso)
        pareamento.aoAceitar { [weak self] in Task { @MainActor in self?.iphonePareou() } }
    }

    // MARK: Ligar

    /// Começa a vigiar o config.json e sobe o servidor. Chamado uma vez, na abertura do app.
    func iniciar(comServidor: Bool = true, intervaloDoRodizio: TimeInterval = Rodizio.checagem) {
        guard let armazem, let arquivoConfig else { return }
        vigia = VigiaConfig(arquivo: arquivoConfig) { [weak self] in self?.recarregar() }
        vigiarAcessos()
        vigiarRodizio(cada: intervaloDoRodizio)
        if comServidor { subirServidor(armazem) }
    }

    func encerrar() {
        tarefaDoRodizio?.cancel(); tarefaDoRodizio = nil
        tarefaDaRenovacao?.cancel(); tarefaDaRenovacao = nil
        vigiaDoIcone?.cancel(); vigiaDoIcone = nil
        vigia?.parar()
        servidorHttps?.parar()
        servidorHttps = nil
        portaDoCabo?.parar(); portaDoCabo = nil
        radio?.parar(); radio = nil
        servidor = .parado
    }

    /// Relê o config.json (o iPhone gravou, ou a pessoa editou à mão). Arquivo ilegível não derruba
    /// nada: fica a última config boa.
    func recarregar() {
        guard let armazem else { return }
        let nova = armazem.ler()
        if nova != config {
            acompanharRodizio(de: config, para: nova)
            config = nova
            mudancasDeFora += 1
        }
    }

    // MARK: Rodízio do código de acesso

    /// O código troca a cada 24 h. O iPhone fica com o novo pelo cabeçalho da resposta, então o Mac continua
    /// reconhecendo o aparelho: o registro dele é regravado com o código novo.
    private func acompanharRodizio(de antes: Config, para depois: Config) {
        guard depois.codigoAcesso != antes.codigoAcesso, depois.codigoAnterior == antes.codigoAcesso, let iphone else { return }
        IphoneLembrado.gravar(iphone, codigo: depois.codigoAcesso, defaults)
    }

    /// Troca o código se passou de 24 h (o app chama num cronômetro, sem depender de pedido do iPhone).
    /// Devolve true se trocou.
    @discardableResult
    func verificarRodizio() -> Bool {
        guard let armazem else { return false }
        let antes = config
        guard rodizio.gerarSeVencido(em: armazem) else { return false }
        let nova = armazem.ler()
        acompanharRodizio(de: antes, para: nova)
        config = nova
        return true
    }

    private func vigiarRodizio(cada intervalo: TimeInterval) {
        tarefaDoRodizio?.cancel()
        tarefaDoRodizio = Task { [weak self] in
            while !Task.isCancelled {
                self?.verificarRodizio()
                try? await Task.sleep(nanoseconds: UInt64(intervalo * 1_000_000_000))
            }
        }
    }

    /// Invalida o código atual e o anterior e gera um que nenhum iPhone tem. Devolve false se não gravou.
    func revogarCodigos() -> Bool {
        if let armazem {
            if let falha = rodizio.revogar(em: armazem) { erro = falha; avisar(falha, falha: true); return false }
            erro = nil
            config = armazem.ler()
        } else {
            gravar {
                $0.codigoAcesso = Config.novoCodigoAcesso()
                $0.codigoCriadoEm = Int(Date().timeIntervalSince1970)
                $0.codigoAnterior = nil
                $0.anteriorValeAte = nil
            }
        }
        iphone = nil
        nativo = nil
        nomeAprovado = nil
        IphoneLembrado.esquecer(defaults)
        return true
    }

    /// "Tentar de novo" quando o servidor falhou ao subir (certificado, porta, página).
    func tentarServidorDeNovo() {
        guard let armazem, case .falhou = servidor else { return }
        servidor = .parado
        subirServidor(armazem)
    }

    /// Um iPhone acertou o código de pareamento. O nome só o aparelho sabe e o núcleo não recebe:
    /// até ele mandar, vale "iPhone".
    func iphonePareou(agora: Date = Date()) {
        let novo = IphonePareado(nome: "iPhone", canal: .wifi, desde: agora)
        iphone = novo
        IphoneLembrado.gravar(novo, codigo: config.codigoAcesso, defaults)
        avisar("iPhone pareado")
    }

    private func marcarSalvo() {
        tarefaDoSalvo?.cancel()
        salvoAgora = true
        tarefaDoSalvo = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tema.Aviso.segundosSalvo * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.salvoAgora = false
        }
    }

    // MARK: Aviso

    /// Mostra um aviso curto: 2,6 s o comum (como o protótipo), 4 s quando uma ação falhou (SPEC, seção 6).
    func avisar(_ texto: String, falha: Bool = false) {
        tarefaDoAviso?.cancel()
        let novo = AvisoDeTela(texto: texto, falha: falha)
        aviso = novo
        tarefaDoAviso = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((falha ? Tema.Aviso.segundosFalha : Tema.Aviso.segundos) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self?.aviso?.id == novo.id { self?.aviso = nil }
        }
    }

    private func subirServidor(_ armazem: ArmazemEmDisco) {
        guard let pasta = PastaDaPagina.daInstalacao() else {
            servidor = .falhou("Não achei a página do iPhone dentro do app.")
            avisar("Não achei a página do iPhone dentro do app.", falha: true)
            return
        }
        let roteador = Ligacao.roteador(armazem: armazem, pareamento: pareamento, pagina: ArquivosPagina(raiz: pasta),
                                        rodizio: rodizio, certificadoCA: GeradorCertificado().arquivos.ca, contaSpotify: spotify.conta)
        ligarNativo(roteador: roteador)
        let portaInicial = config.porta
        Task.detached(priority: .userInitiated) { [weak self] in
            let resultado = Result { try ModeloApp.abrirPorta(roteador: roteador, a: portaInicial) }
            await self?.servidorPronto(resultado)
        }
    }

    private func servidorPronto(_ r: Result<(ServidorHttps, Int), Error>) {
        switch r {
        case .success(let (s, porta)):
            servidorHttps = s
            // Porta ocupada: o Deck sobe numa vizinha para não ficar fora do ar, mas NÃO grava a nova na config.
            // O menu avisa, e o QR e o endereço levam a porta em uso.
            registrarPorta(porta)
        case .failure(let e):
            let motivo = (e as? ErroServidor)?.description ?? (e as? ErroCertificado)?.description ?? "Não consegui abrir o servidor do Deck."
            servidor = .falhou(motivo)
            avisar(motivo, falha: true)
        }
    }

    /// A porta em que o servidor subiu. Se não é a da config, `avisoDePorta` aparece no menu.
    func registrarPorta(_ porta: Int) { servidor = .ligado(porta: porta) }

    /// Texto do menu quando a porta pedida estava ocupada e o Deck subiu em outra.
    var avisoDePorta: String? {
        guard case .ligado(let usada) = servidor, usada != config.porta else { return nil }
        return TextosDoMenu.portaOcupada(preferida: config.porta, usada: usada)
    }

    /// Certificado e primeira porta livre a partir da pedida. Bloqueia: roda fora da tela.
    nonisolated private static func abrirPorta(roteador: Roteador, a partir: Int) throws -> (ServidorHttps, Int) {
        let gerador = GeradorCertificado()
        let identidade = try gerador.carregarIdentidade(try gerador.garantir())
        var ultimo: Error = ErroServidor(description: "Não achei uma porta livre para o Deck.")
        for porta in Portas.candidatas(a: partir) {
            let s = ServidorHttps(roteador: roteador, identidade: identidade, porta: UInt16(porta))
            do { try s.iniciar(); return (s, porta) } catch { ultimo = error }
        }
        throw ultimo
    }

    // MARK: Gravar

    /// Muda a config e grava. Sem armazém (fotos e testes) só muda na memória.
    func gravar(_ mudanca: (inout Config) -> Void) {
        // O iPhone pode ter gravado há instantes: parte do que está no disco, não de uma cópia velha.
        recarregar()
        var nova = config
        mudanca(&nova)
        guard nova != config else { return }
        if let armazem {
            if let falha = armazem.aplicar(nova) { erro = falha; avisar(falha, falha: true); return }
            erro = nil
        }
        config = nova
        marcarSalvo()
    }

    func usarComposicao(_ c: String) { gravar { $0.comp = c } }
    func usarPerfil(_ id: String) { gravar { $0.perfilAtivo = id } }

    func marcarConfiguracaoInicialFeita(_ feita: Bool = true, defaults: UserDefaults = .standard) {
        configuracaoInicialFeita = feita
        defaults.set(feita, forKey: Self.chaveInicial)
    }
}

/// Um aviso curto na janela. O `id` distingue um aviso do seguinte, para o antigo não apagar o novo.
struct AvisoDeTela: Equatable, Identifiable {
    let id = UUID()
    var texto: String
    var falha = false
}

/// O iPhone pareado fica guardado junto com o código de acesso de quando foi pareado: trocou o código
/// (Desconectar), o registro deixa de valer.
enum IphoneLembrado {
    private static let chaveDesde = "iphonePareadoDesde"
    private static let chaveCodigo = "iphonePareadoCodigo"
    private static let chaveNome = "iphonePareadoNome"

    static func gravar(_ iphone: IphonePareado, codigo: String, _ defaults: UserDefaults) {
        defaults.set(iphone.nome, forKey: chaveNome)
        defaults.set(iphone.desde, forKey: chaveDesde)
        defaults.set(codigo, forKey: chaveCodigo)
    }

    static func ler(_ defaults: UserDefaults, codigoAtual: String) -> IphonePareado? {
        guard defaults.string(forKey: chaveCodigo) == codigoAtual, let nome = defaults.string(forKey: chaveNome) else { return nil }
        return IphonePareado(nome: nome, canal: .wifi, desde: defaults.object(forKey: chaveDesde) as? Date)
    }

    static func esquecer(_ defaults: UserDefaults) {
        for c in [chaveNome, chaveDesde, chaveCodigo] { defaults.removeObject(forKey: c) }
    }
}
