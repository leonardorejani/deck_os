import Foundation

/// WhatsApp por QR ("aparelho conectado"). Um ajudante separado (`helpers/whatsapp`, Go, biblioteca
/// whatsmeow) faz a conexão e entrega conversas por linhas de JSON no stdout. Só leitura: o ajudante nunca
/// envia nada e nunca marca como lido. Não é oficial e viola os termos do WhatsApp, por isso a opção
/// nasce desligada (`whatsapp.origem` só vira "qr" por escolha da pessoa).

enum FaseQR: String, Sendable, Equatable {
    case desligado, iniciando, conectado, desconectado, erro
    case aguardandoQR = "aguardando_qr"
    case qrExpirou = "qr_expirou"
}

struct EstadoQR: Equatable, Sendable {
    var fase: FaseQR = .desligado
    var detalhe: String = ""
    /// O texto que vira QR (só enquanto a fase é aguardandoQR).
    var qr: String?
    var conversas: [ConversaWhatsApp] = []

    /// Subindo ou caiu um instante: a whatsmeow volta sozinha, não é caso de ler QR.
    var reconectando: Bool { fase == .iniciando || fase == .desconectado }

    /// A tela do Mac e o aviso do iPhone usam o mesmo texto.
    var aviso: String? {
        switch fase {
        case .aguardandoQR: return "WhatsApp por QR sem conexão. Leia o QR nos Ajustes do Deck, no Mac."
        case .qrExpirou: return "O QR do WhatsApp expirou. Gere outro nos Ajustes do Deck, no Mac."
        case .erro: return detalhe.isEmpty ? "O WhatsApp por QR parou. Veja os Ajustes do Deck, no Mac." : detalhe
        default: return nil
        }
    }
}

/// Os textos da tela do Mac (Ajustes) para o WhatsApp por QR. Moram aqui para o teste do núcleo cobrar o aviso.
enum TextosWhatsAppQR {
    /// O aviso que acompanha a opção, sempre à vista, antes e depois de ligar.
    static let aviso = "Não é oficial e viola os termos do WhatsApp. Só lê, não envia. Ocupa uma das 4 conexões. Para sair, apague o aparelho em Aparelhos conectados."
    static let semAjudante = "Esta versão do Deck veio sem o WhatsApp por QR. O Deck segue lendo pela origem que você escolheu."
    static let naoSaiu = "Não consegui sair do aparelho. Confira a internet e tente apagar de novo."
    static let passos = "No celular, abra o WhatsApp, vá em Aparelhos conectados e toque em Conectar um aparelho. Depois aponte a câmera para o QR."

    static func situacao(_ e: EstadoQR) -> String {
        switch e.fase {
        case .desligado: return "Desligado"
        case .iniciando: return "Conectando..."
        case .aguardandoQR: return "Esperando você ler o QR"
        case .conectado: return "Conectado"
        case .desconectado: return "Reconectando..."
        case .qrExpirou: return "O QR expirou"
        case .erro: return e.detalhe.isEmpty ? "Parou" : e.detalhe
        }
    }
}

enum LinhaDoAjudante: Equatable {
    case fase(FaseQR, String)
    case qr(String)
    case conversas([ConversaWhatsApp])

    private struct Cru: Decodable {
        var t: String
        var fase: String?
        var detalhe: String?
        var codigo: String?
        var lista: [ConversaWhatsApp]?
    }

    /// Linha que não é JSON do ajudante (ou de um tipo que não conhecemos) é ignorada, nunca derruba a leitura.
    static func interpretar(_ linha: String) -> LinhaDoAjudante? {
        guard let c = try? JSONDecoder().decode(Cru.self, from: Data(linha.utf8)) else { return nil }
        switch c.t {
        case "fase":
            guard let f = c.fase.flatMap(FaseQR.init(rawValue:)) else { return nil }
            return .fase(f, c.detalhe ?? "")
        case "qr": return c.codigo.map(LinhaDoAjudante.qr)
        case "conversas": return c.lista.map(LinhaDoAjudante.conversas)
        default: return nil
        }
    }
}

final class PonteWhatsAppQR: @unchecked Sendable {
    private let executavel: URL?
    private let pasta: URL
    private let argumentosExtras: [String]
    private let trava = NSLock()
    private var estado = EstadoQR()
    private var processo: Process?
    private var entrada: FileHandle?
    private var geracao = 0
    private var encerrada = false
    /// Durante o "apagar": o erro que o ajudante mandar é a saída que falhou.
    private var apagando = false
    private var apagouComErro = false
    /// Avisa a tela do Mac quando algo muda (QR novo, conectou, caiu). Chamado fora da trava.
    var aoMudar: (@Sendable (EstadoQR) -> Void)?

    /// `executavel` nil: o ajudante não veio no app (build sem Go), e a opção diz isso.
    init(executavel: URL?, pasta: URL, argumentosExtras: [String] = []) {
        self.executavel = executavel
        self.pasta = pasta
        self.argumentosExtras = argumentosExtras
    }

    static let variavelDoAjudante = "DECK_WHATSAPP_AJUDANTE"

    /// Onde o app procura o ajudante: dentro do Deck.app (`Contents/Helpers`) e, para a prova de
    /// bancada, pela variável de ambiente.
    static func ajudanteEmbutido(ambiente: [String: String] = ProcessInfo.processInfo.environment,
                                 pacote: URL = Bundle.main.bundleURL) -> URL? {
        let fm = FileManager.default
        if let v = ambiente[variavelDoAjudante], fm.isExecutableFile(atPath: v) { return URL(fileURLWithPath: v) }
        let dentro = pacote.appendingPathComponent("Contents/Helpers/deck-whatsapp")
        return fm.isExecutableFile(atPath: dentro.path) ? dentro : nil
    }

    var disponivel: Bool { executavel != nil }

    var atual: EstadoQR {
        trava.lock(); defer { trava.unlock() }
        return estado
    }

    /// Há um ajudante rodando (ou subindo).
    var ligada: Bool {
        trava.lock(); defer { trava.unlock() }
        return processo != nil
    }

    // MARK: Ciclo de vida

    /// Liga só se estiver desligada. Fase de erro ou QR vencido espera a pessoa pedir outro (`reiniciar`),
    /// senão a leitura do estado (a cada segundo) ficaria relançando o ajudante.
    func garantirLigada() {
        trava.lock()
        let precisa = processo == nil && estado.fase == .desligado
        trava.unlock()
        if precisa { iniciar() }
    }

    /// Gera um QR novo (ou tenta de novo depois de um erro).
    func reiniciar() {
        parar(zerar: true)
        iniciar()
    }

    /// Desliga o ajudante sem apagar a sessão (volta a conectar sozinha na próxima vez).
    func desligar() {
        parar(zerar: true)
        notificar()
    }

    /// Sai do aparelho no WhatsApp e apaga a sessão guardada. Devolve false se não conseguiu sair (sem rede, por
    /// exemplo): aí a sessão fica, o estado vira erro com o motivo e a pessoa tenta de novo. Apagar só a pasta
    /// deixaria o aparelho ocupando uma das 4 conexões sem aviso.
    @discardableResult
    func apagarSessao() -> Bool {
        trava.lock()
        let tinha = processo != nil
        trava.unlock()
        // Ajudante parado mas com sessão guardada: sobe só para o logout.
        if !tinha, temSessao { iniciar() }
        trava.lock()
        let p = processo, e = entrada
        if p != nil { apagando = true; apagouComErro = false }
        trava.unlock()
        if let p, let e {
            try? e.write(contentsOf: Data("{\"c\":\"apagar\"}\n".utf8))
            let limite = Date().addingTimeInterval(25)
            while p.isRunning, Date() < limite {
                trava.lock(); let falhou = apagouComErro; trava.unlock()
                if falhou { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            trava.lock()
            let naoSaiu = apagouComErro || p.isRunning
            apagando = false
            trava.unlock()
            if naoSaiu { return falhouAoApagar() }
        } else if temSessao {
            return falhouAoApagar()
        }
        parar(zerar: true)
        try? FileManager.default.removeItem(at: pasta)
        notificar()
        return true
    }

    private func falhouAoApagar() -> Bool {
        parar(zerar: false)
        mudar { $0 = EstadoQR(fase: .erro, detalhe: TextosWhatsAppQR.naoSaiu) }
        return false
    }

    /// Tem um aparelho conectado guardado neste Mac (já pareou antes). É o arquivo "pareado" que o ajudante deixa:
    /// o `sessao.db` existe desde a primeira tentativa de QR, então não prova nada.
    var temSessao: Bool { FileManager.default.fileExists(atPath: pasta.appendingPathComponent("pareado").path) }

    private func iniciar() {
        guard let executavel else {
            mudar { $0.fase = .erro; $0.detalhe = "Esta versão do Deck veio sem o WhatsApp por QR." }
            return
        }
        let p = Process()
        p.executableURL = executavel
        p.arguments = ["--pasta", pasta.path] + argumentosExtras
        let saida = Pipe(), ent = Pipe()
        p.standardOutput = saida
        p.standardInput = ent
        p.standardError = FileHandle.nullDevice
        trava.lock()
        geracao += 1
        let minha = geracao
        estado = EstadoQR(fase: .iniciando)
        encerrada = false
        trava.unlock()

        let leitor = LeitorDeLinhas { [weak self] linha in self?.receber(linha, geracao: minha) }
        saida.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            leitor.alimentar(d)
        }
        p.terminationHandler = { [weak self] _ in
            // O que o ajudante imprimiu antes de sair ainda pode estar no cano: lê tudo antes de dar a queda por certa,
            // senão a última fase ("conectado") chegaria depois do erro e a tela mentiria.
            saida.fileHandleForReading.readabilityHandler = nil
            leitor.alimentar(saida.fileHandleForReading.readDataToEndOfFile())
            self?.terminou(geracao: minha)
        }
        do {
            try p.run()
        } catch {
            mudar { $0.fase = .erro; $0.detalhe = "Não consegui abrir o WhatsApp por QR." }
            return
        }
        trava.lock()
        processo = p
        entrada = ent.fileHandleForWriting
        trava.unlock()
        notificar()
    }

    private func parar(zerar: Bool) {
        trava.lock()
        let p = processo, e = entrada
        processo = nil
        entrada = nil
        geracao += 1
        if zerar { estado = EstadoQR() }
        trava.unlock()
        // Fechar o stdin é o aviso de "o Deck fechou": o ajudante salva e sai sozinho.
        try? e?.close()
        if let p, p.isRunning {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
        }
    }

    private func receber(_ linha: String, geracao g: Int) {
        guard let l = LinhaDoAjudante.interpretar(linha) else { return }
        trava.lock()
        guard g == geracao, !encerrada else { trava.unlock(); return }
        switch l {
        case .fase(let f, let d):
            estado.fase = f
            estado.detalhe = d
            if apagando, f == .erro { apagouComErro = true }
            if f != .aguardandoQR { estado.qr = nil }
        case .qr(let c):
            estado.fase = .aguardandoQR
            estado.qr = c
        case .conversas(let c):
            estado.conversas = c
        }
        trava.unlock()
        notificar()
    }

    private func terminou(geracao g: Int) {
        trava.lock()
        guard g == geracao else { trava.unlock(); return }
        processo = nil
        entrada = nil
        encerrada = true
        // O ajudante já avisou o motivo (QR vencido, saiu do aparelho). Sem aviso nenhum, foi queda.
        if estado.fase == .iniciando || estado.fase == .conectado || estado.fase == .desconectado || estado.fase == .aguardandoQR {
            estado.fase = .erro
            estado.detalhe = "O WhatsApp por QR parou. Gere o QR de novo nos Ajustes do Deck."
        }
        estado.qr = nil
        trava.unlock()
        notificar()
    }

    private func mudar(_ f: (inout EstadoQR) -> Void) {
        trava.lock(); f(&estado); trava.unlock()
        notificar()
    }

    private func notificar() { aoMudar?(atual) }

    // MARK: Leitura para o painel

    /// No mesmo formato da leitura do banco do app, com a origem "qr". `aberto` diz se a conexão está de pé
    /// (o total 0 de uma conexão caída não é medição).
    func ler() -> Leitura<WhatsAppDados?> {
        garantirLigada()
        let e = atual
        let conectado = e.fase == .conectado
        let total = e.conversas.reduce(0) { $0 + $1.naoLidas }
        // Reconectando (queda curta): a lista de antes continua à vista, o total volta a ser medição quando conectar.
        let resumo = ResumoWhatsApp(total: total, conversas: e.conversas.count, origem: "qr", navegador: nil, aberto: conectado,
                                    reconectando: e.reconectando ? true : nil)
        let aviso = e.aviso.map { Aviso(fonte: "whatsapp", texto: $0) }
        return Leitura(valor: WhatsAppDados(resumo: resumo, conversas: conectado || e.reconectando ? e.conversas : []), aviso: aviso)
    }
}

/// Junta pedaços de saída em linhas completas.
final class LeitorDeLinhas: @unchecked Sendable {
    private let trava = NSLock()
    private var resto = Data()
    private let aoLinha: @Sendable (String) -> Void

    init(_ aoLinha: @escaping @Sendable (String) -> Void) { self.aoLinha = aoLinha }

    func alimentar(_ d: Data) {
        trava.lock()
        resto.append(d)
        var linhas: [String] = []
        while let i = resto.firstIndex(of: 0x0A) {
            linhas.append(String(decoding: resto[resto.startIndex..<i], as: UTF8.self))
            resto = Data(resto[resto.index(after: i)...])
        }
        trava.unlock()
        for l in linhas where !l.isEmpty { aoLinha(l) }
    }
}
