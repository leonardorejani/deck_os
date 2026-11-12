import Foundation

/// O WhatsApp por QR nos Ajustes: entrega à tela o estado da ponte (QR, conectado, caiu) e os botões
/// de ligar, gerar outro QR e apagar a sessão. A conexão de verdade é do ajudante (`helpers/whatsapp`).
@MainActor
final class ModeloWhatsAppQR: ObservableObject {
    let ponte: PonteWhatsAppQR
    @Published private(set) var estado: EstadoQR
    /// Saindo do aparelho no WhatsApp: a tela mostra "Apagando..." e segura o botão.
    @Published private(set) var apagando = false

    init(ponte: PonteWhatsAppQR) {
        self.ponte = ponte
        self.estado = ponte.atual
        ponte.aoMudar = { [weak self] novo in Task { @MainActor in self?.estado = novo } }
    }

    /// A pasta da sessão fica ao lado da config de cada variante (o Deck e a bancada nunca dividem o aparelho).
    static func padrao(variante: Variante = .atual, ajudante: URL? = PonteWhatsAppQR.ajudanteEmbutido()) -> ModeloWhatsAppQR {
        let pasta = variante.pastaDeDados().appendingPathComponent("whatsapp-qr", isDirectory: true)
        return ModeloWhatsAppQR(ponte: PonteWhatsAppQR(executavel: ajudante, pasta: pasta))
    }

    /// Sem ajudante e sem disco: as fotos das telas e os testes.
    static func semAjudante() -> ModeloWhatsAppQR {
        ModeloWhatsAppQR(ponte: PonteWhatsAppQR(executavel: nil, pasta: FileManager.default.temporaryDirectory.appendingPathComponent("deck-sem-whatsapp-qr")))
    }

    var disponivel: Bool { ponte.disponivel }

    /// Liga (ou volta a ligar, se estava parada) e já mostra o QR, sem esperar o iPhone pedir o estado.
    func ligar() {
        ponte.garantirLigada()
        estado = ponte.atual
    }

    func gerarOutroQR() { ponte.reiniciar(); estado = ponte.atual }

    func desligar() { ponte.desligar(); estado = ponte.atual }

    /// Sai do aparelho e apaga a sessão guardada. Demora até uns 25 s, então roda fora da tela. Sem conseguir sair
    /// (sem rede), a sessão fica e o estado mostra o motivo.
    func apagarSessao() {
        guard !apagando else { return }
        apagando = true
        let p = ponte
        Task.detached { [weak self] in
            p.apagarSessao()
            await MainActor.run { self?.apagando = false; self?.estado = p.atual }
        }
    }
}
