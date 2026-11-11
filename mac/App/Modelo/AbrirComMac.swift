import Foundation
import ServiceManagement

/// O que o app precisa de um "item de login" (SMAppService.mainApp no app, um falso nos testes).
protocol ServicoDeLogin {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: ServicoDeLogin {}

/// "Abrir junto com o Mac". O estado de verdade é o do sistema: a pessoa pode desligar em Ajustes
/// do Sistema, então o app relê em vez de guardar uma cópia.
@MainActor
final class AbrirComMac: ObservableObject {
    @Published private(set) var ligado = false
    @Published private(set) var precisaAprovar = false
    @Published private(set) var erro: String?

    private let servico: ServicoDeLogin

    init(servico: ServicoDeLogin = SMAppService.mainApp) {
        self.servico = servico
        atualizar()
    }

    func atualizar() {
        ligado = servico.status == .enabled
        precisaAprovar = servico.status == .requiresApproval
    }

    func definir(_ ligar: Bool) {
        erro = nil
        do {
            if ligar { try servico.register() } else { try servico.unregister() }
        } catch {
            self.erro = ligar ? "Não consegui ligar a abertura junto com o Mac." : "Não consegui desligar a abertura junto com o Mac."
        }
        atualizar()
    }
}
