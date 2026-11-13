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
    static let naoAchouAChamada = "Não achei a chamada do Meet na frente do navegador. Deixe a aba da reunião na frente e tente de novo."

    private var leitor: LeitorDeReuniao {
        LeitorDeReuniao(executor: executor, acessibilidade: acoes.ax, temAcessibilidade: acoes.temAcessibilidade)
    }

    func estado() -> EstadoMeet {
        let l = leitor
        if let sala = l.salaDoMeet(NavegadorWeb.todos) {
            return EstadoMeet(aberta: true, naChamada: sala.naChamada, microfone: sala.microfone, camera: sala.camera)
        }
        // Reserva: a aba da sala por JavaScript. Também dá "?" quando a sala existe e não dá para ler.
        let r = l.lerMeet(NavegadorWeb.todos)
        guard r.microfone != .semReuniao || r.camera != .semReuniao else { return .semReuniao }
        return EstadoMeet(aberta: true, naChamada: nil, microfone: r.microfone, camera: r.camera, aviso: r.aviso?.texto)
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
        return executor.rodar("open \(ExecutorAcoes.escapar(Self.endereco))").status == 0 ? nil : "Não consegui abrir o Meet no navegador"
    }

    private func sair() -> String? {
        guard acoes.temAcessibilidade() else { return Self.semAcessibilidade }
        guard acoes.apertarNoMeet(.meetNoNavegador, .sair) else { return Self.naoAchouAChamada }
        return nil
    }

    /// As ações de microfone e câmera usam a tecla do Meet em qualquer navegador.
    static let tecla = Tecla(id: "meet", nome: "Google Meet", tipo: "app", valor: ControleDeReuniao.valorDoMeet, estado: nil, icone: nil)
}
