#if os(macOS)
import Foundation
@testable import Nucleo

// Provedores de exemplo só para provar o servidor de verdade. Nada aqui lê ou muda dado real.

final class ConfigEmMemoria: ArmazemDeConfig, @unchecked Sendable {
    private let trava = NSLock()
    private var atual: Config

    init(_ c: Config) { atual = c }

    func ler() -> Config { trava.lock(); defer { trava.unlock() }; return atual }

    func aplicar(_ nova: Config) -> String? {
        if let erro = Config.validar(nova) { return erro }
        trava.lock(); atual = nova; trava.unlock()
        return nil
    }
}

struct PaineisDeExemplo: ProvedorPaineis {
    let config: ArmazemDeConfig

    func estado() -> Estado {
        let c = config.ler()
        return Estado(
            agora: ISO8601DateFormatter().string(from: Date()), nomeMac: c.nomeMac, perfilAtivo: c.perfilAtivo,
            comp: c.comp, blocos: c.blocos,
            spotify: EstadoSpotify(tocando: true, faixa: "Faixa de exemplo", artista: "Artista", posicao: 42,
                                   duracao: 200, capaId: "exemplo", cores: ["#1d3557", "#e63946"],
                                   album: "Álbum de exemplo", repetir: false, aleatorio: true),
            uso: [UsoConta(id: "claude-leo", nome: "Claude", conta: "leo", semana: 37, renova: nil)],
            sessoes: sessoes(), whatsapp: ResumoWhatsApp(total: 3, conversas: 2),
            agenda: ResumoAgenda(permissao: true, proximo: eventos().first),
            acesas: ["acordado"], selos: ["whatsapp": "3"], avisos: [])
    }

    func whatsapp() -> [ConversaWhatsApp] {
        [ConversaWhatsApp(id: "c1", nome: "Louvor", grupo: true, naoLidas: 2, ultima: "2026-11-10T09:00:00-03:00",
                          mensagens: [MensagemWhatsApp(de: "Ana", texto: "Ensaio às 19h", hora: "2026-11-10T09:00:00-03:00")])]
    }

    private func eventos() -> [Evento] {
        [Evento(titulo: "Ensaio", inicio: "2026-11-10T19:00:00-03:00", diaTodo: false, calendario: "Igreja", cor: "#2a9d8f", local: nil)]
    }

    func agenda(de: String, dias: Int) -> [Evento] { eventos() }

    func sessoes() -> [Sessao] {
        [Sessao(id: "s1", nome: "DECK_SERVIDOR", projeto: "deck", pergunta: "Posso seguir?", desde: "2026-11-10T10:00:00-03:00")]
    }

    func capa() -> CapaAtual? {
        // PNG de 1x1 pixel.
        CapaAtual(tipo: "image/png", dados: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!)
    }
}

struct TeclasDeExemplo: ExecutorTeclas {
    func executar(_ tecla: Tecla) -> String? {
        tecla.id == "quebrada" ? "A tecla de exemplo está quebrada." : nil
    }
}

struct SpotifyDeExemplo: ControleSpotify {
    func acao(_ nome: String) -> String? { nil }
    func posicao(_ segundos: Double) -> String? { nil }
    func definir(_ nome: String, ligado: Bool?) -> String? { nil }
}
#endif
