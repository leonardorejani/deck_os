import Foundation
#if os(macOS)
import ApplicationServices
#endif

// O Meet lido e comandado pela Acessibilidade do macOS (a que o Deck já pede), sem a pessoa ligar nada no navegador.
// A página do Meet aparece na árvore de acessibilidade do navegador como botões com nome: "Desativar microfone",
// "Ativar câmera", "Sair da chamada" (e os equivalentes em inglês e espanhol). O nome do botão diz o estado:
// "Desativar microfone" existe quando o microfone está LIGADO. A leitura não mexe no navegador e a ação aperta o
// botão (AXPress), sem trazer a janela para a frente. O caminho por JavaScript (EstadoReuniao.swift) fica de reserva.
// Só a aba que está na frente da sua janela aparece na árvore: aba de reunião escondida atrás de outra não é lida.

/// Um botão da página, com os textos que a Acessibilidade dá a ele (título, descrição e dica).
struct BotaoWeb: Equatable, Sendable {
    var rotulos: [String]
}

/// Uma janela do navegador e os botões da aba que está na frente nela.
struct JanelaDoNavegador: Equatable, Sendable {
    var titulo: String
    var botoes: [BotaoWeb]
}

/// A árvore de acessibilidade de um navegador. Só o macOS responde de verdade: nos testes entra um falso.
protocol AcessibilidadeDoNavegador: Sendable {
    /// Os botões de cada janela. Nil: não deu para olhar (sem acesso, ou o processo sumiu).
    func janelas(pid: Int32) -> [JanelaDoNavegador]?
    /// Aperta o primeiro botão da janela (a partir de 0) que tem esse texto. Devolve se apertou.
    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool
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

    /// O pid do navegador, sem acordá-lo: nil se ele está fechado.
    static func pid(_ n: NavegadorWeb, executor: any Executor) -> Int32? {
        let r = executor.rodar("pgrep -x \(Shell.aspas(n.processo))")
        guard r.status == 0 else { return nil }
        return r.saida.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.first
    }

    static func ler(_ n: NavegadorWeb, executor: any Executor, ax: any AcessibilidadeDoNavegador, confiavel: Bool) -> Resultado {
        guard confiavel else { return .semAcesso }
        guard let pid = pid(n, executor: executor) else { return .fechado }
        guard let janelas = ax.janelas(pid: pid) else { return .semSala }
        // Dentro da chamada vale mais que a tela de entrada, caso haja duas janelas do Meet.
        var melhor: SalaMeet?
        for (i, j) in janelas.enumerated() {
            guard let l = janela(j) else { continue }
            let sala = SalaMeet(navegador: n, janela: i, microfone: l.microfone, camera: l.camera, naChamada: l.naChamada)
            if melhor == nil || (sala.naChamada && melhor?.naChamada == false) { melhor = sala }
        }
        return melhor.map { .sala($0) } ?? .semSala
    }

    /// Aperta o botão do Meet que o pedido quer. Devolve se apertou.
    static func apertar(_ sala: SalaMeet, _ pedido: BotaoDoMeet.Pedido, executor: any Executor, ax: any AcessibilidadeDoNavegador) -> Bool {
        guard let pid = pid(sala.navegador, executor: executor), let janelas = ax.janelas(pid: pid),
              janelas.indices.contains(sala.janela) else { return false }
        for b in janelas[sala.janela].botoes {
            guard let c = BotaoDoMeet.classificar(b), pedido.serve(c), let rotulo = b.rotulos.first(where: { BotaoDoMeet.classificar($0) != nil }) else { continue }
            return ax.pressionar(pid: pid, janela: sala.janela, rotulo: rotulo)
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

    /// Os botões de uma janela, em profundidade, no máximo `limiteDeNos` nós e até o prazo.
    private func botoes(de janela: AXUIElement, prazo: Date) -> [(elemento: AXUIElement, botao: BotaoWeb)] {
        var achados: [(AXUIElement, BotaoWeb)] = []
        var pilha: [AXUIElement] = [janela]
        var vistos = 0
        while let el = pilha.popLast(), vistos < Self.limiteDeNos, Date() < prazo {
            vistos += 1
            if texto(el, "AXRole") == "AXButton" {
                let rotulos = ["AXTitle", "AXDescription", "AXHelp"].compactMap { texto(el, $0) }
                if !rotulos.isEmpty { achados.append((el, BotaoWeb(rotulos: rotulos))) }
                continue // botão não tem outro botão dentro
            }
            // Em ordem de tela: o que se empilha por último sai primeiro.
            pilha.append(contentsOf: filhos(el).reversed())
        }
        return achados
    }

    func janelas(pid: Int32) -> [JanelaDoNavegador]? {
        guard AXIsProcessTrusted() else { return nil }
        let app = aplicacao(pid)
        if liberar(app, pid: pid) { Thread.sleep(forTimeInterval: 0.4) } // a página leva um instante para montar a árvore
        let prazo = Date().addingTimeInterval(Self.limiteDeSegundos)
        return janelasDe(app).enumerated().map { (i, j) in
            let titulo = texto(j, "AXTitle") ?? ""
            let chave = "\(pid)|\(i)|\(titulo)"
            trava.lock(); let visto = semMeet[chave]; trava.unlock()
            if let visto, Date().timeIntervalSince(visto) < Self.validadeDoNegativo { return JanelaDoNavegador(titulo: titulo, botoes: []) }
            let achados = botoes(de: j, prazo: prazo).map(\.botao)
            let janela = JanelaDoNavegador(titulo: titulo, botoes: achados)
            trava.lock()
            if LeitorDeMeetAX.janela(janela) == nil { semMeet[chave] = Date() } else { semMeet[chave] = nil }
            if semMeet.count > 200 { semMeet = semMeet.filter { Date().timeIntervalSince($0.value) < Self.validadeDoNegativo } }
            trava.unlock()
            return janela
        }
    }

    func pressionar(pid: Int32, janela: Int, rotulo: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = aplicacao(pid)
        let todas = janelasDe(app)
        guard todas.indices.contains(janela) else { return false }
        let prazo = Date().addingTimeInterval(Self.limiteDeSegundos)
        guard let alvo = botoes(de: todas[janela], prazo: prazo).first(where: { $0.botao.rotulos.contains(rotulo) }) else { return false }
        return AXUIElementPerformAction(alvo.elemento, "AXPress" as CFString) == .success
    }
}
#endif
