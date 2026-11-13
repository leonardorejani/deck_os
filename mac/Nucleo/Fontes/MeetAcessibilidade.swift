import Foundation
#if os(macOS)
import ApplicationServices
#endif

// O Meet lido e comandado pela Acessibilidade do macOS (a que o Deck já pede), sem a pessoa ligar nada no navegador.
// A página do Meet aparece na árvore de acessibilidade do navegador como botões com nome: "Desativar microfone",
// "Ativar câmera", "Sair da chamada" (e os equivalentes em inglês e espanhol). O nome do botão diz o estado:
// "Desativar microfone" existe quando o microfone está LIGADO. A leitura não mexe no navegador e a ação aperta o
// botão (AXPress), sem trazer a janela para a frente. O caminho por JavaScript (EstadoReuniao.swift) fica de reserva.
// Só a aba que está na frente da sua janela mostra botões na árvore: aba de reunião escondida atrás de outra não tem
// botão para ler. Mas o título de cada aba aparece (AXTabButton) e o Meet em Picture-in-Picture é uma janela própria do
// navegador (sem barra de abas) com os botões de microfone, câmera e sair. Provado no Chrome em 13/11/2026 com uma janela
// de Document Picture-in-Picture: ela vem em AXWindows e os botões saem com o nome "Desativar microfone (ctrl + d)".
// Então: botões da janela flutuante ou da aba da frente dão o estado, e só o título da aba (ou da janela) diz "há reunião".

/// Um botão da página, com os textos que a Acessibilidade dá a ele (título, descrição e dica).
struct BotaoWeb: Equatable, Sendable {
    var rotulos: [String]
}

/// Uma janela do navegador e os botões da aba que está na frente nela.
struct JanelaDoNavegador: Equatable, Sendable {
    var titulo: String
    var botoes: [BotaoWeb]
    /// Os títulos das abas da janela (a barra de abas), as de fundo também.
    var abas: [String] = []
    /// Janela sem barra de abas: a do Picture-in-Picture (ou outro popup).
    var flutuante: Bool = false
}

/// A árvore de acessibilidade de um navegador. Só o macOS responde de verdade: nos testes entra um falso.
protocol AcessibilidadeDoNavegador: Sendable {
    /// Os botões de cada janela. Nil: não deu para olhar (sem acesso, ou o processo sumiu).
    func janelas(pid: Int32) -> [JanelaDoNavegador]?
    /// Aperta o primeiro botão da janela (a partir de 0) que tem esse texto. Devolve se apertou.
    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool
    /// Seleciona a aba da janela que tem esse título (traz a aba de fundo para a frente da janela dela). Devolve se apertou.
    func pressionarAba(pid: Int32, janela: Int, titulo: String) -> Bool
}

extension AcessibilidadeDoNavegador {
    func pressionarAba(pid: Int32, janela: Int, titulo: String) -> Bool { false }
}

/// O que um botão do Meet quer dizer, pelo nome dele.
enum BotaoDoMeet: Equatable, Sendable {
    case microfone(ligado: Bool)
    case camera(ligado: Bool)
    case sair

    private static func normalizar(_ texto: String) -> String {
        var t = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // O Meet põe o atalho no fim do nome: "Desativar microfone (ctrl + d)".
        if let r = t.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) { t.removeSubrange(r) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func casa(_ t: String, _ padrao: String) -> Bool { t.range(of: padrao, options: .regularExpression) != nil }

    private static let artigo = #"(o |a |el |la |your |the )?"#
    private static let microfone = #"(microfone|microphone|microfono|mic)"#
    private static let camera = #"(camera|camara|cam)"#
    private static let desliga = #"(desativar|desligar|desactivar|apagar|turn off|disable)"#
    private static let liga = #"(ativar|ligar|activar|encender|turn on|enable)"#

    /// Só o botão da própria pessoa: "Silenciar o microfone de Ana" (que vale para outro participante) não entra.
    static func classificar(_ rotulo: String) -> BotaoDoMeet? {
        let t = normalizar(rotulo)
        if casa(t, "^\(desliga) \(artigo)\(microfone)$") { return .microfone(ligado: true) }
        if casa(t, "^\(liga) \(artigo)\(microfone)$") { return .microfone(ligado: false) }
        if casa(t, "^\(desliga) \(artigo)\(camera)$") { return .camera(ligado: true) }
        if casa(t, "^\(liga) \(artigo)\(camera)$") { return .camera(ligado: false) }
        if casa(t, #"^(sair da (chamada|reuniao)|leave (call|meeting)|salir de la (llamada|reunion)|end call)$"#) { return .sair }
        return nil
    }

    /// Os botões da tela "Você saiu da reunião": a aba continua com o título da sala, mas a chamada acabou.
    static func ehTelaDeSaida(_ botao: BotaoWeb) -> Bool {
        botao.rotulos.contains { casa(normalizar($0), #"^(entrar novamente|voltar a tela inicial|rejoin|return to home screen|volver a unirte|volver a la pantalla de inicio)$"#) }
    }

    static func classificar(_ botao: BotaoWeb) -> BotaoDoMeet? {
        for r in botao.rotulos { if let c = classificar(r) { return c } }
        return nil
    }
}

/// O que a Acessibilidade achou do Meet num navegador.
struct SalaMeet: Equatable, Sendable {
    var navegador: NavegadorWeb
    var janela: Int
    var microfone: EstadoDeReuniao
    var camera: EstadoDeReuniao
    /// Já dentro da chamada (o botão "Sair da chamada" existe). Sem ele a pessoa está na tela de entrada.
    var naChamada: Bool
    /// O processo do navegador (o Chrome pode ter mais de um com o mesmo nome).
    var pid: Int32 = 0
    /// A sala está numa janela de Picture-in-Picture.
    var flutuante: Bool = false
    /// Só se achou o título da aba (ou da janela) da reunião: ela está atrás de outra aba e sem botão para ler.
    /// `abaDaReuniao` é o título, para trazê-la para a frente quando a pessoa agir.
    var somenteAba: Bool = false
    var abaDaReuniao: String? = nil

    var leitura: LeituraDeReuniao { LeituraDeReuniao(microfone: microfone, camera: camera) }
}

enum LeitorDeMeetAX {
    enum Resultado: Equatable, Sendable {
        case fechado
        /// O Deck não tem o acesso de Acessibilidade: nem tenta.
        case semAcesso
        /// O navegador está aberto e nenhuma janela mostra o Meet na frente.
        case semSala
        case sala(SalaMeet)
    }

    static func janela(_ j: JanelaDoNavegador) -> (microfone: EstadoDeReuniao, camera: EstadoDeReuniao, naChamada: Bool)? {
        var mic: EstadoDeReuniao?, cam: EstadoDeReuniao?, sair = false
        for b in j.botoes {
            switch BotaoDoMeet.classificar(b) {
            case .microfone(let l)?: if mic == nil { mic = l ? .ligado : .desligado }
            case .camera(let l)?: if cam == nil { cam = l ? .ligado : .desligado }
            case .sair?: sair = true
            case nil: continue
            }
        }
        guard mic != nil || cam != nil || sair else { return nil }
        return (mic ?? .desconhecido, cam ?? .desconhecido, sair)
    }

    /// Os pids do navegador, sem acordá-lo: vazio se ele está fechado. Pode haver mais de um processo com o mesmo nome
    /// (outro perfil ou uma instância de automação): a reunião pode estar em qualquer um.
    static func pids(_ n: NavegadorWeb, executor: any Executor) -> [Int32] {
        let r = executor.rodar("pgrep -x \(Shell.aspas(n.processo))")
        guard r.status == 0 else { return [] }
        return r.saida.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Título de aba ou de janela de uma sala do Meet: "Meet: abc-defg-hij" ou "Meet - abc-defg-hij".
    static func ehTituloDeSala(_ titulo: String) -> Bool {
        titulo.range(of: #"(^|[\s:])meet\s*[-\u{2013}\u{2014}:]\s*[a-z]{3}-[a-z]{4}-[a-z]{3}\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// O título da aba (ou da janela) que é de uma sala do Meet.
    /// Na tela "Você saiu da reunião" a aba da frente ainda tem o título da sala, mas não é reunião: não conta.
    static func abaDeSala(_ j: JanelaDoNavegador) -> String? {
        let saiu = j.botoes.contains(where: BotaoDoMeet.ehTelaDeSaida)
        let abas = saiu ? j.abas.filter { !(ehTituloDeSala($0) && j.titulo.hasPrefix($0)) } : j.abas
        return abas.first(where: ehTituloDeSala) ?? (!saiu && ehTituloDeSala(j.titulo) ? j.titulo : nil)
    }

    static func ler(_ n: NavegadorWeb, executor: any Executor, ax: any AcessibilidadeDoNavegador, confiavel: Bool) -> Resultado {
        guard confiavel else { return .semAcesso }
        let todos = pids(n, executor: executor)
        guard !todos.isEmpty else { return .fechado }
        var comBotoes: [SalaMeet] = [], soAba: [SalaMeet] = []
        for pid in todos {
            guard let janelas = ax.janelas(pid: pid) else { continue }
            for (i, j) in janelas.enumerated() {
                if let l = janela(j) {
                    comBotoes.append(SalaMeet(navegador: n, janela: i, microfone: l.microfone, camera: l.camera, naChamada: l.naChamada,
                                              pid: pid, flutuante: j.flutuante))
                } else if let aba = abaDeSala(j) {
                    soAba.append(SalaMeet(navegador: n, janela: i, microfone: .desconhecido, camera: .desconhecido, naChamada: false,
                                          pid: pid, flutuante: j.flutuante, somenteAba: true, abaDaReuniao: aba))
                }
            }
        }
        // Dentro da chamada vale mais que a tela de entrada, e a janela flutuante vale mais que a aba (ela está sempre à vista).
        let melhor = comBotoes.max { a, b in peso(a) < peso(b) }
        if let melhor { return .sala(melhor) }
        // Sem botão nenhum para ler: o título da aba já diz que há reunião (a janela flutuante, quando houver, primeiro).
        if let aba = soAba.first(where: \.flutuante) ?? soAba.first { return .sala(aba) }
        return .semSala
    }

    /// Maior é melhor. Em empate `max(by:)` fica com o primeiro, a ordem da árvore.
    private static func peso(_ s: SalaMeet) -> Int { (s.naChamada ? 2 : 0) + (s.flutuante ? 1 : 0) }

    /// Aperta o botão do Meet que o pedido quer. Devolve se apertou.
    static func apertar(_ sala: SalaMeet, _ pedido: BotaoDoMeet.Pedido, executor: any Executor, ax: any AcessibilidadeDoNavegador) -> Bool {
        let pid = sala.pid != 0 ? sala.pid : (pids(sala.navegador, executor: executor).first ?? 0)
        guard pid != 0, let janelas = ax.janelas(pid: pid), janelas.indices.contains(sala.janela) else { return false }
        for b in janelas[sala.janela].botoes {
            guard let c = BotaoDoMeet.classificar(b), pedido.serve(c), let rotulo = b.rotulos.first(where: { BotaoDoMeet.classificar($0) != nil }) else { continue }
            return ax.pressionar(pid: pid, janela: sala.janela, rotulo: rotulo)
        }
        return false
    }

    /// A reunião só tem a aba (atrás de outra): seleciona a aba dela. Devolve se apertou.
    static func trazerAba(_ sala: SalaMeet, ax: any AcessibilidadeDoNavegador) -> Bool {
        guard sala.somenteAba, let titulo = sala.abaDaReuniao, sala.pid != 0 else { return false }
        return ax.pressionarAba(pid: sala.pid, janela: sala.janela, titulo: titulo)
    }

    /// A chamada está na janelinha flutuante: a aba da sala está numa janela com barra de abas do mesmo processo. Seleciona
    /// essa aba. Devolve se apertou (sem aba para trazer, quem chamou cai no resto).
    static func trazerAbaDaJanelaFlutuante(_ sala: SalaMeet, ax: any AcessibilidadeDoNavegador) -> Bool {
        guard sala.flutuante, sala.pid != 0, let janelas = ax.janelas(pid: sala.pid) else { return false }
        for (i, j) in janelas.enumerated() where !j.flutuante {
            if let aba = abaDeSala(j) { return ax.pressionarAba(pid: sala.pid, janela: i, titulo: aba) }
        }
        return false
    }
}

extension BotaoDoMeet {
    /// O que se quer apertar: qual botão, não em que estado ele está.
    enum Pedido: Sendable {
        case microfone, camera, sair

        func serve(_ b: BotaoDoMeet) -> Bool {
            switch (self, b) {
            case (.microfone, .microfone), (.camera, .camera), (.sair, .sair): return true
            default: return false
            }
        }
    }
}

/// Quem olha a árvore de acessibilidade: só o executor de verdade consulta o sistema, no macOS.
enum AcessibilidadePadrao {
    static func para(_ executor: any Executor) -> (any AcessibilidadeDoNavegador)? {
        #if os(macOS)
        return executor is ExecutorShell ? AcessibilidadeReal.compartilhada : nil
        #else
        return nil
        #endif
    }
}

// MARK: - O macOS de verdade

#if os(macOS)
/// A árvore de acessibilidade dos navegadores pelo ApplicationServices. Cada leitura tem tempo e número de nós limitados:
/// uma página enorme nunca prende o estado.
final class AcessibilidadeReal: AcessibilidadeDoNavegador, @unchecked Sendable {
    static let compartilhada = AcessibilidadeReal()

    /// Quantos nós de uma janela se olham, e quanto tempo a leitura de um navegador espera.
    static let limiteDeNos = 12000
    static let limiteDeSegundos = 2.5

    private let trava = NSLock()
    private var liberados: Set<Int32> = []
    /// Janela (pid, posição e título) em que nada do Meet apareceu, e quando se olhou. A página de outro site não se
    /// percorre de novo a cada leitura: com o título igual e há menos de 8 s, vale o que já se viu. Quem entra numa
    /// reunião muda o título, e o que tem botão do Meet nunca fica aqui.
    private var semMeet: [String: Date] = [:]
    static let validadeDoNegativo = 8.0

    func aplicacao(_ pid: Int32) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return app
    }

    /// Os navegadores de base Chromium só montam a árvore da página quando alguém de acessibilidade pede. No Chrome
    /// o pedido que vale é o AXEnhancedUserInterface (o AXManualAccessibility, dos apps Electron, ele recusa com
    /// "atributo não suportado", provado no Chrome em 13/11/2026). Se já está ligado, nada a fazer. O AXManualAccessibility
    /// fica de tentativa para quem o aceita, e o outro entra se ele falhar. Devolve se pediu agora (a página leva um instante).
    func liberarArvore(_ app: AXUIElement, pid: Int32) -> Bool { liberar(app, pid: pid) }

    private func liberar(_ app: AXUIElement, pid: Int32) -> Bool {
        trava.lock(); defer { trava.unlock() }
        if liberados.contains(pid) { return false }
        liberados.insert(pid)
        var atual: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &atual) == .success, (atual as? Bool) == true { return false }
        if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { return true }
        return AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success
    }

    func filhos(_ el: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &v) == .success, let lista = v as? [AnyObject] else { return [] }
        return lista.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { $0 as! AXUIElement }
    }

    func texto(_ el: AXUIElement, _ atributo: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, atributo as CFString, &v) == .success, let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    func janelasDe(_ app: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &v) == .success, let lista = v as? [AnyObject] else { return [] }
        return lista.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { $0 as! AXUIElement }
    }

    /// O que se achou numa janela: botões, abas (a barra de abas, as de fundo também) e se há barra de abas.
    private struct Varredura {
        var botoes: [(elemento: AXUIElement, botao: BotaoWeb)] = []
        var abas: [(elemento: AXUIElement, titulo: String)] = []
        var temBarraDeAbas = false
    }

    /// A janela em profundidade, no máximo `limiteDeNos` nós e até o prazo.
    private func varrer(_ janela: AXUIElement, prazo: Date) -> Varredura {
        var v = Varredura()
        var pilha: [AXUIElement] = [janela]
        var vistos = 0
        while let el = pilha.popLast(), vistos < Self.limiteDeNos, Date() < prazo {
            vistos += 1
            let papel = texto(el, "AXRole")
            if papel == "AXButton" {
                let rotulos = ["AXTitle", "AXDescription", "AXHelp"].compactMap { texto(el, $0) }
                if !rotulos.isEmpty { v.botoes.append((el, BotaoWeb(rotulos: rotulos))) }
                continue // botão não tem outro botão dentro
            }
            if papel == "AXTabGroup" { v.temBarraDeAbas = true }
            if papel == "AXRadioButton", texto(el, "AXSubrole") == "AXTabButton" {
                if let t = texto(el, "AXTitle") ?? texto(el, "AXDescription") { v.abas.append((el, t)) }
                continue // dentro da aba só há o botão de fechar
            }
            // Em ordem de tela: o que se empilha por último sai primeiro.
            pilha.append(contentsOf: filhos(el).reversed())
        }
        return v
    }

    /// Cada janela tem o seu prazo (uma página enorme não rouba a vez da janela flutuante do Meet) e a leitura toda tem um teto.
    static let limiteDeSegundosPorJanela = 1.2

    func janelas(pid: Int32) -> [JanelaDoNavegador]? {
        guard AXIsProcessTrusted() else { return nil }
        let app = aplicacao(pid)
        if liberar(app, pid: pid) { Thread.sleep(forTimeInterval: 0.4) } // a página leva um instante para montar a árvore
        let teto = Date().addingTimeInterval(Self.limiteDeSegundos * 2)
        return janelasDe(app).enumerated().map { (i, j) in
            let titulo = texto(j, "AXTitle") ?? ""
            let chave = "\(pid)|\(i)|\(titulo)"
            trava.lock(); let visto = semMeet[chave]; trava.unlock()
            if let visto, Date().timeIntervalSince(visto) < Self.validadeDoNegativo { return JanelaDoNavegador(titulo: titulo, botoes: []) }
            let prazo = min(teto, Date().addingTimeInterval(Self.limiteDeSegundosPorJanela))
            let v = varrer(j, prazo: prazo)
            let janela = JanelaDoNavegador(titulo: titulo, botoes: v.botoes.map(\.botao), abas: v.abas.map(\.titulo), flutuante: !v.temBarraDeAbas)
            trava.lock()
            if LeitorDeMeetAX.janela(janela) == nil, LeitorDeMeetAX.abaDeSala(janela) == nil { semMeet[chave] = Date() } else { semMeet[chave] = nil }
            if semMeet.count > 200 { semMeet = semMeet.filter { Date().timeIntervalSince($0.value) < Self.validadeDoNegativo } }
            trava.unlock()
            return janela
        }
    }

    func pressionarAba(pid: Int32, janela: Int, titulo: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let todas = janelasDe(aplicacao(pid))
        guard todas.indices.contains(janela) else { return false }
        let prazo = Date().addingTimeInterval(Self.limiteDeSegundosPorJanela)
        guard let alvo = varrer(todas[janela], prazo: prazo).abas.first(where: { $0.titulo == titulo }) else { return false }
        return AXUIElementPerformAction(alvo.elemento, "AXPress" as CFString) == .success
    }

    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = aplicacao(pid)
        let todas = janelasDe(app)
        guard todas.indices.contains(janela) else { return false }
        let prazo = Date().addingTimeInterval(Self.limiteDeSegundosPorJanela)
        guard let alvo = varrer(todas[janela], prazo: prazo).botoes.first(where: { $0.botao.rotulos.contains(rotulo) }) else { return false }
        return AXUIElementPerformAction(alvo.elemento, "AXPress" as CFString) == .success
    }
}
#endif
