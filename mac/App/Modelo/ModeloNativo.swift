import Foundation

// O app nativo do iPhone no lado do Mac: o pedido de pareamento por Bluetooth (o mesmo código de 6 dígitos nas
// duas telas, Recusar e Permitir), o canal em uso e a renovação do app. Telas em Ajustes/ConectarIphoneNativo.swift
// e no menu da barra. Tudo aqui é lógica sem tela, para os testes e as fotos.

/// O iPhone que apareceu por Bluetooth querendo parear. `codigo` são os 6 dígitos que o iPhone mostra também.
struct PedidoDePareamento: Equatable {
    var iphone: String
    var codigo: String
}

extension CanalIphone {
    /// O rótulo da sessão no núcleo: "usbmux/<id>" é o cabo, "bluetooth/<id>" é o Bluetooth.
    init?(rotulo: String) {
        if rotulo.hasPrefix("usbmux/") { self = .cabo } else if rotulo.hasPrefix("bluetooth/") { self = .bluetooth } else { return nil }
    }
}

// MARK: - Renovação

/// O app instalado com conta grátis da Apple vence em 7 dias. O Deck renova a cada 5 (Modelo/ModeloRenovacao.swift).
/// Aqui se sabe quando foi a última (`renovadoEm`), por que a última tentativa falhou e se o prazo está apertando.
struct RenovacaoDoApp: Equatable {
    var instaladoEm: Date?
    var versao: String?
    /// A última vez que o app foi (re)instalado no iPhone. nil = o Deck ainda não sabe.
    var renovadoEm: Date?
    /// Por que a última tentativa falhou, em português. nil = a última deu certo (ou ainda não houve).
    var motivo: String?
    var tentouEm: Date?

    static let validade: TimeInterval = 7 * 86_400
    static let intervalo: TimeInterval = AgendaDeRenovacao.intervalo
    /// Passou da hora de renovar, o Deck tenta de novo sozinho (o iPhone pode só estar longe do cabo). Só depois
    /// disto sem renovar o prazo está apertando: cartão amarelo, selo e linha no menu.
    static let tolerancia: TimeInterval = 12 * 3_600

    enum Estado: Equatable {
        case semRegistro
        case emDia(proxima: Date)
        /// Passou da hora de renovar faz pouco: o Deck tenta de novo sozinho.
        case tentandoDeNovo(venceEm: Date)
        case apertando(venceEm: Date)
    }

    func estado(agora: Date = Date()) -> Estado {
        guard let renovadoEm else { return .semRegistro }
        let proxima = renovadoEm.addingTimeInterval(Self.intervalo)
        let vence = renovadoEm.addingTimeInterval(Self.validade)
        if agora < proxima { return .emDia(proxima: proxima) }
        return agora < proxima.addingTimeInterval(Self.tolerancia) ? .tentandoDeNovo(venceEm: vence) : .apertando(venceEm: vence)
    }

    private static let chaveInstalado = "appNativoInstaladoEm"
    private static let chaveVersao = "appNativoVersao"
    private static let chaveRenovado = "appNativoRenovadoEm"
    private static let chaveMotivo = "appNativoMotivoDaFalha"
    private static let chaveTentou = "appNativoTentouEm"

    static func ler(_ defaults: UserDefaults) -> RenovacaoDoApp {
        RenovacaoDoApp(instaladoEm: defaults.object(forKey: chaveInstalado) as? Date, versao: defaults.string(forKey: chaveVersao),
                       renovadoEm: defaults.object(forKey: chaveRenovado) as? Date, motivo: defaults.string(forKey: chaveMotivo),
                       tentouEm: defaults.object(forKey: chaveTentou) as? Date)
    }

    func gravar(_ defaults: UserDefaults) {
        for (chave, valor) in [(Self.chaveInstalado, instaladoEm as Any?), (Self.chaveVersao, versao), (Self.chaveRenovado, renovadoEm),
                                (Self.chaveMotivo, motivo), (Self.chaveTentou, tentouEm)] {
            if let valor { defaults.set(valor, forKey: chave) } else { defaults.removeObject(forKey: chave) }
        }
    }
}

// MARK: - Textos

enum TextosDoNativo {
    private static func formato(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "pt_BR")
        d.dateFormat = f
        return d
    }

    /// Dias inteiros até `data`, sem passar de zero. Faltou meio dia, conta um.
    static func dias(ate data: Date, agora: Date) -> Int { max(0, Int((data.timeIntervalSince(agora) / 86_400).rounded(.up))) }

    static func prazo(_ dias: Int) -> String {
        switch dias { case 0: return "hoje"; case 1: return "em 1 dia"; default: return "em \(dias) dias" }
    }

    /// "O app vence em 2 dias" (menu da barra).
    static func venceEm(_ venceEm: Date, agora: Date = Date()) -> String { "O app vence \(prazo(dias(ate: venceEm, agora: agora)))" }

    /// "Bluetooth, agora" (Último canal).
    static func ultimoCanal(_ n: AppNativo, agora: Date = Date()) -> String {
        let nome = n.canal == .bluetooth ? "Bluetooth" : "Cabo"
        let seg = agora.timeIntervalSince(n.visto)
        // "agora" tem a mesma janela do cabeçalho (30 s): passou disso, o iPhone não está falando.
        if seg <= IphonePareado.janelaAoVivo { return "\(nome), agora" }
        if seg < 3600 { return "\(nome), há \(max(1, Int(seg / 60))) min" }
        return "\(nome), às \(formato("HH:mm").string(from: n.visto))"
    }

    /// "Conectado pelo Wi-Fi" e "App nativo, por Bluetooth" (Aparelhos).
    static func aparelhoNativo(_ n: AppNativo) -> String {
        "App nativo, \(n.canal.texto) desde \(formato("HH:mm").string(from: n.desde))"
    }

    /// "Instalado pelo Xcode em 10 de novembro de 2026" (a data só quando se sabe).
    static func instalado(_ r: RenovacaoDoApp) -> String {
        guard let em = r.instaladoEm else { return "Instalado pelo Xcode" }
        return "Instalado pelo Xcode em \(formato("d 'de' MMMM 'de' yyyy").string(from: em))"
    }

    /// "próxima em 3 dias, seg 10h", "Tenta de novo sozinha", "Vence em 2 dias".
    static func renovacao(_ e: RenovacaoDoApp.Estado, agora: Date = Date()) -> String {
        switch e {
        case .semRegistro: return "Ainda não renovou"
        case .emDia(let proxima):
            let hora = Calendar.current.component(.minute, from: proxima) == 0 ? "H'h'" : "H'h'mm"
            return "próxima \(prazo(dias(ate: proxima, agora: agora))), \(formato("EEE " + hora).string(from: proxima).replacingOccurrences(of: ".", with: ""))"
        case .tentandoDeNovo: return "Tenta de novo sozinha"
        case .apertando(let vence): return "Vence \(prazo(dias(ate: vence, agora: agora)))"
        }
    }

    static func alertaDaRenovacao(_ vence: Date, agora: Date = Date()) -> String {
        "O app vence \(prazo(dias(ate: vence, agora: agora))) e a renovação não deu certo"
    }

    static let alertaApoio = "O Deck tenta de novo sozinho assim que o iPhone aparecer no cabo ou no Wi-Fi, ou for desbloqueado. Se puder, plugue e desbloqueie agora."
    static let renovacaoApoio = "O Deck renova sozinho a cada 5 dias, sem abrir nenhuma tela. A Apple faz o app vencer em 7. Se não der, tenta de novo quando o iPhone aparecer no cabo ou no Wi-Fi, ou for desbloqueado"
    static let renovacaoCondicoes = "Para renovar sozinho, o Mac precisa estar ligado com o Deck na barra, e o iPhone no cabo ou no mesmo Wi-Fi do Mac (pareado com o Xcode pela rede), com a conta da Apple entrada no Xcode e a pasta do projeto do Deck no Mac. O iPhone pode estar bloqueado, menos logo depois de ligar. Você só é avisado quando o prazo aperta."
    static let canalApoio = "O Deck usa o cabo quando ele está plugado e o Bluetooth quando não está"
    static let semRenovador = "A renovação automática ainda não está ligada nesta versão do Deck"

    static let vazioTitulo = "Abra o Deck no iPhone"
    static let vazioTexto = "Ele lista os Macs por perto. Toque neste."
    static let vazioRotulo = "Visível por Bluetooth"
    static let pedidoTexto = "Confira se o código é o mesmo do iPhone."
    static let caboRotulo = "Código do cabo"
    static let caboTexto = "Digite no iPhone, na tela do cabo. Vale por 10 minutos."
    static func pedidoRotulo(_ iphone: String) -> String { "\(iphone) quer parear" }
    static let notaDaVia = "Sem Bluetooth ou sem achar o Mac? Segunda via: plugue o iPhone no cabo e, na tela de procurar do app, toque em \"Conectar pelo cabo com código\". Digite o código do cartão acima."
}

// MARK: - Pareamento por Bluetooth

/// Faz a ponte entre o núcleo, que pergunta numa thread própria e espera a resposta, e a tela, que responde
/// quando a pessoa toca em Recusar ou Permitir.
final class PonteDeDecisao: @unchecked Sendable {
    private let trava = NSCondition()
    private var resposta: Bool?
    /// Quanto o Mac espera pela pessoa. Passou disso, vale Recusar.
    let limite: TimeInterval
    /// Quem mostra o pedido (o modelo). Chamado na thread do núcleo.
    var aoPerguntar: (@Sendable (PedidoDePareamento) -> Void)?
    /// Chamado quando o pedido acaba sem resposta da pessoa (o tempo passou ou o iPhone saiu).
    var aoEncerrar: (@Sendable (String) -> Void)?

    init(limite: TimeInterval = 120) { self.limite = limite }

    func perguntar(iphone: String, codigo: String) -> Bool {
        trava.lock(); resposta = nil; trava.unlock()
        aoPerguntar?(PedidoDePareamento(iphone: iphone, codigo: codigo))
        trava.lock()
        let fim = Date().addingTimeInterval(limite)
        while resposta == nil, trava.wait(until: fim) {}
        let r = resposta
        resposta = nil
        trava.unlock()
        if r == nil { aoEncerrar?(codigo) }
        return r ?? false
    }

    func responder(_ permitir: Bool) {
        trava.lock(); resposta = permitir; trava.broadcast(); trava.unlock()
    }

    /// O iPhone saiu antes da resposta: solta quem espera.
    func desistir(codigo: String) {
        responder(false)
        aoEncerrar?(codigo)
    }
}

/// O núcleo só aceita pedido de pareamento por Bluetooth enquanto a pessoa está em Conectar iPhone. A tela
/// renova a janela a cada poucos segundos: sair da tela (ou fechar os Ajustes) fecha sozinha, sem depender de
/// um aviso de saída.
final class JanelaDePareamento: @unchecked Sendable {
    static let duracao: TimeInterval = 60
    private let trava = NSLock()
    private var ate = Date.distantPast
    private let agora: @Sendable () -> Date

    init(agora: @escaping @Sendable () -> Date = { Date() }) { self.agora = agora }

    func renovar() { trava.lock(); ate = agora().addingTimeInterval(Self.duracao); trava.unlock() }
    func fechar() { trava.lock(); ate = .distantPast; trava.unlock() }
    var aberta: Bool { trava.lock(); defer { trava.unlock() }; return agora() < ate }
}

// MARK: - Log

/// O log do Deck em ~/Library/Logs/Deck/deck.log (o app não tem terminal). Guarda só o que o núcleo escreve
/// sobre o cabo e o Bluetooth, que nunca leva código de acesso. Passou de 512 KB, o arquivo velho vira deck.log.1.
final class LogDoDeck: @unchecked Sendable {
    static let padrao = LogDoDeck(arquivo: Variante.atual.pastaDeLog().appendingPathComponent("deck.log"))

    private let arquivo: URL
    private let limite: Int
    private let trava = NSLock()

    init(arquivo: URL, limite: Int = 512 * 1024) { self.arquivo = arquivo; self.limite = limite }

    func escrever(_ linha: String) {
        trava.lock(); defer { trava.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let tam = (try? fm.attributesOfItem(atPath: arquivo.path))?[.size] as? Int, tam > limite {
            let velho = arquivo.appendingPathExtension("1")
            try? fm.removeItem(at: velho)
            try? fm.moveItem(at: arquivo, to: velho)
        }
        if !fm.fileExists(atPath: arquivo.path) { fm.createFile(atPath: arquivo.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        guard let h = try? FileHandle(forWritingTo: arquivo) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        let hora = ISO8601DateFormatter().string(from: Date())
        try? h.write(contentsOf: Data("\(hora) \(linha)\n".utf8))
    }
}

// MARK: - O modelo

extension ModeloApp {
    /// O iPhone do topo do menu, do cabeçalho dos Ajustes, do Sobre e de Conexões: o app nativo tem a vez, depois o
    /// Safari pelo Wi-Fi. É a única fonte de "tem iPhone pareado". Se ele está falando agora é `iphoneAoVivo`.
    var iphoneAtivo: IphonePareado? {
        nativo.map { IphonePareado(nome: $0.nome, canal: $0.canal, desde: $0.desde, visto: $0.visto) } ?? iphone
    }

    /// O iPhone do `iphoneAtivo` falou com o Mac nos últimos 30 s.
    var iphoneAoVivo: Bool { iphoneAtivo?.aoVivo(agora: agora) ?? false }

    /// O núcleo respondeu a API pelo Wi-Fi: o iPhone está falando, mesmo que o Mac não tenha anotado o pareamento.
    func wifiAtendeu(caminho: String, status: Int, agora: Date = Date()) {
        guard let novo = Conexoes.aposRespostaDoWifi(atual: iphone, caminho: caminho, status: status, agora: agora) else { return }
        let nasceu = iphone == nil
        iphone = novo
        if nasceu { IphoneLembrado.gravar(novo, codigo: config.codigoAcesso, defaults) }
    }

    var estadoDaRenovacao: RenovacaoDoApp.Estado { renovacao.estado(agora: agora) }

    /// O prazo apertando com o app pareado: cartão amarelo, selo "1" na barra lateral e linha no menu.
    var renovacaoApertando: Bool {
        if nativo != nil, case .apertando = estadoDaRenovacao { return true }
        return false
    }

    /// Sobe o cabo (usbmux) e o Bluetooth ao lado do HTTPS. Os três respondem pelo mesmo roteador.
    func ligarNativo(roteador: Roteador) {
        let nome: @Sendable () -> String = { roteador.config.ler().nomeMac }
        let log: @Sendable (String) -> Void = { LogDoDeck.padrao.escrever($0) }
        let atendeu: @Sendable (String, String, Int) -> Void = { [weak self] rotulo, caminho, status in
            Task { @MainActor in self?.nativoAtendeu(rotulo: rotulo, caminho: caminho, status: status) }
        }
        let cabo = PortaDoCabo(roteador: roteador, nomeMac: nome, log: log, aoAtender: atendeu)
        cabo.iniciar()
        portaDoCabo = cabo
        let janela = janelaDePareamento
        let ponte = decisao
        #if DEBUG
        // Só para a prova com o Mac sem ninguém na frente: o build de Debug aceita `--bt-permitir`. Nunca existe no Release.
        let aceitarSozinho = CommandLine.arguments.contains("--bt-permitir")
        #else
        let aceitarSozinho = false
        #endif
        radio = PortaDoBluetooth.ligar(
            roteador: roteador, nomeMac: nome,
            decidir: { iphone, codigo in aceitarSozinho ? true : ponte.perguntar(iphone: iphone, codigo: codigo) },
            pareamentoAberto: { aceitarSozinho || janela.aberta },
            desistiu: { codigo in ponte.desistir(codigo: codigo) },
            log: log, aoAtender: atendeu)
        log("deck: cabo e Bluetooth ligados")
    }

    func ligarDecisao() {
        decisao.aoPerguntar = { [weak self] pedido in Task { @MainActor in self?.pedidoBluetooth = pedido } }
        decisao.aoEncerrar = { [weak self] codigo in
            Task { @MainActor in if self?.pedidoBluetooth?.codigo == codigo { self?.pedidoBluetooth = nil } }
        }
    }

    /// Recusar ou Permitir no pedido de pareamento por Bluetooth. O iPhone ainda confere o código do lado dele.
    func responderPedido(permitir: Bool) {
        guard let pedido = pedidoBluetooth else { return }
        pedidoBluetooth = nil
        nomeAprovado = permitir ? pedido.iphone : nil
        decisao.responder(permitir)
        avisar(permitir ? "iPhone pareado. O app já pode abrir o painel" : "Pareamento recusado")
    }

    /// O núcleo respondeu um pedido do app nativo. Resposta boa pelo cabo ou pelo Bluetooth quer dizer que o app
    /// está pareado e por onde fala: é assim que o Mac sabe o canal em uso, sem o iPhone avisar.
    func nativoAtendeu(rotulo: String, caminho: String, status: Int, agora: Date = Date()) {
        guard (200..<300).contains(status), let canal = CanalIphone(rotulo: rotulo) else { return }
        // O código do cabo passa pelo mesmo POST /api/parear do Wi-Fi, e o núcleo avisa "um iPhone pareou" sem
        // saber por onde: aqui o registro de Wi-Fi que ele acabou de criar é desfeito, porque foi o app nativo.
        if caminho == "/api/parear", let i = iphone, i.canal == .wifi, let d = i.desde, agora.timeIntervalSince(d) < 10 {
            iphone = nil
            IphoneLembrado.esquecer(defaults)
        }
        if var n = nativo {
            guard n.canal != canal || agora.timeIntervalSince(n.visto) >= 5 else { return }
            n.canal = canal
            n.visto = agora
            if let nome = nomeAprovado { n.nome = nome; nomeAprovado = nil }
            nativo = n
        } else {
            nativo = AppNativo(nome: nomeAprovado ?? "iPhone", canal: canal, desde: agora, visto: agora)
            nomeAprovado = nil
        }
    }

    /// Desconectar o app nativo: o código de acesso muda e ele volta a pedir pareamento (a API só conhece o código).
    func desconectarNativo() {
        guard revogarCodigos() else { return }
        avisar("App desconectado. Ele volta a pedir pareamento")
    }

    /// "Renovar agora". Sem renovador (testes e fotos) o Mac diz a verdade em vez de fingir.
    func renovarAppNativo() {
        guard renovador != nil else { avisar(TextosDoNativo.semRenovador, falha: true); return }
        guard !renovando else { return }
        avisar("Renovando o app no iPhone...")
        Task { await executarRenovacao(manual: true) }
    }

    /// Guarda a renovação que deu certo: a data, a versão e limpa o motivo da falha anterior.
    func registrarRenovacao(em data: Date, versao: String? = nil, instaladoEm: Date? = nil, avisando: Bool = true) {
        renovacao.renovadoEm = data
        renovacao.motivo = nil
        renovacao.tentouEm = nil
        falhaDaRenovacao = nil
        if let versao { renovacao.versao = versao }
        if let instaladoEm { renovacao.instaladoEm = instaladoEm } else if renovacao.instaladoEm == nil { renovacao.instaladoEm = data }
        renovacao.gravar(defaults)
        if avisando { avisar("App renovado. Vale por mais 7 dias") }
    }
}
