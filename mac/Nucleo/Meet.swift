import Foundation

// A central do Google Meet no iPhone: entrar, microfone, câmera e sair da chamada, com o estado de cada um.
// O estado vem da Acessibilidade (MeetAcessibilidade.swift), com o JavaScript do navegador de reserva. Nenhum botão
// finge estado: sem reunião aberta, o iPhone mostra que não há reunião.

/// O que o iPhone mostra na tela do Meet.
struct EstadoMeet: Codable, Equatable, Sendable {
    /// Há uma reunião (ou a tela de entrada dela) aberta no navegador.
    var aberta: Bool
    /// Já dentro da chamada. Nil quando só se sabe que a reunião existe (leitura por JavaScript, ou sem leitura).
    var naChamada: Bool? = nil
    var microfone: EstadoDeReuniao
    var camera: EstadoDeReuniao
    /// O que a pessoa precisa fazer quando o Deck não conseguiu ler.
    var aviso: String? = nil

    static let semReuniao = EstadoMeet(aberta: false, microfone: .semReuniao, camera: .semReuniao)
}

enum AcaoMeet: String, Sendable, CaseIterable {
    case entrar, microfone, camera, sair
}

protocol MeetDoMac: Sendable {
    func estado() -> EstadoMeet
    /// Erro em texto para o iPhone mostrar, ou nil se deu certo.
    func agir(_ acao: AcaoMeet) -> String?
}

struct MeetReal: MeetDoMac {
    let executor: any Executor
    let acoes: ExecutorAcoes

    init(executor: any Executor, acoes: ExecutorAcoes? = nil) {
        self.executor = executor
        self.acoes = acoes ?? ExecutorAcoes(shell: executor)
    }

    static let endereco = "https://meet.google.com"
    static let semAcessibilidade = "O Deck precisa do acesso de Acessibilidade para controlar o Meet. Libere em Ajustes do Mac, Privacidade e Segurança, Acessibilidade."
    static let avisoSoAba = "A reunião está aberta em outra aba. Abra a janelinha flutuante do Meet ou deixe a aba na frente para o Deck ler o microfone e a câmera."
    static let naoAchouAChamada = "Não achei a chamada do Meet na frente do navegador. Deixe a aba da reunião na frente e tente de novo."

    private var leitor: LeitorDeReuniao {
        LeitorDeReuniao(executor: executor, acessibilidade: acoes.ax, temAcessibilidade: acoes.temAcessibilidade)
    }

    func estado() -> EstadoMeet {
        let l = leitor
        let sala = l.salaDoMeet(NavegadorWeb.todos)
        if let sala, !sala.somenteAba {
            return EstadoMeet(aberta: true, naChamada: sala.naChamada, microfone: sala.microfone, camera: sala.camera)
        }
        // A reunião existe (achada pelo título da aba) mas está atrás de outra aba e sem janela flutuante: se o JavaScript do
        // navegador deixar ler, melhor, senão fica "Reunião aberta" com o estado desconhecido, sem trazer nada para a frente.
        let soAba = EstadoMeet(aberta: true, naChamada: nil, microfone: .desconhecido, camera: .desconhecido, aviso: Self.avisoSoAba)
        // Reserva: a aba da sala por JavaScript. Também dá "?" quando a sala existe e não dá para ler. Sem a permissão de
        // Automação não se sabe se há sala: não é motivo para dizer "Reunião aberta" nem para avisar, a Acessibilidade é o caminho.
        var javascriptDesligado = false
        for n in NavegadorWeb.todos {
            switch LeituraDeMeet.ler(n, executor: executor) {
            case .sala(let r):
                guard r.microfone != .semReuniao || r.camera != .semReuniao else { continue }
                if sala != nil, r.microfone == .desconhecido, r.camera == .desconhecido { continue }
                return EstadoMeet(aberta: true, naChamada: nil, microfone: r.microfone, camera: r.camera, aviso: r.aviso?.texto)
            case .javascriptDesligado: javascriptDesligado = true
            case .fechado, .semSala, .falhou, .semPermissao: continue
            }
        }
        if sala != nil { return soAba }
        guard javascriptDesligado else { return .semReuniao }
        return EstadoMeet(aberta: true, naChamada: nil, microfone: .desconhecido, camera: .desconhecido, aviso: LeituraDeMeet.avisoJavascript.texto)
    }

    func agir(_ acao: AcaoMeet) -> String? {
        switch acao {
        case .entrar: return entrar()
        case .microfone: return acoes.controlarReuniao(Self.tecla, .microfone)
        case .camera: return acoes.controlarReuniao(Self.tecla, .camera)
        case .sair: return sair()
        }
    }

    /// Traz a aba da reunião para a frente, ou abre o Meet no navegador padrão quando não há reunião aberta.
    private func entrar() -> String? {
        if acoes.trazerSalaDoMeet() == nil { return nil }
        // Sem a Automação do navegador o AppleScript não acha a aba: a Acessibilidade acha pelo título e seleciona a aba, para
        // "Entrar no Meet" nunca abrir uma segunda aba por cima de uma reunião aberta.
        if let ax = acoes.ax, acoes.temAcessibilidade() {
            for n in NavegadorWeb.todos {
                guard case .sala(let sala) = LeitorDeMeetAX.ler(n, executor: executor, ax: ax, confiavel: true) else { continue }
                if !sala.somenteAba || LeitorDeMeetAX.trazerAba(sala, ax: ax) { return nil }
            }
        }
        return executor.rodar("open \(ExecutorAcoes.escapar(Self.endereco))").status == 0 ? nil : "Não consegui abrir o Meet no navegador"
    }

    private func sair() -> String? {
        guard acoes.temAcessibilidade() else { return Self.semAcessibilidade }
        if acoes.apertarNoMeet(.meetNoNavegador, .sair) { return nil }
        // A aba da reunião pode estar atrás de outra: traz para a frente e tenta de novo, como o microfone e a câmera fazem.
        if let erro = acoes.trazerSalaDoMeet() { return erro == ExecutorAcoes.erroSemSalaDoMeet ? Self.naoAchouAChamada : erro }
        _ = executor.rodar(ExecutorAcoes.esperaDoFoco)
        return acoes.apertarNoMeet(.meetNoNavegador, .sair) ? nil : Self.naoAchouAChamada
    }

    /// As ações de microfone e câmera usam a tecla do Meet em qualquer navegador.
    static let tecla = Tecla(id: "meet", nome: "Google Meet", tipo: "app", valor: ControleDeReuniao.valorDoMeet, estado: nil, icone: nil)
}
