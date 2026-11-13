import Foundation

/// O estado das teclas de comando com liga e desliga (`Tecla.desligar`) que não têm comando de conferir.
/// O Deck guarda só o que ele mesmo fez: apertou "ligar" e deu certo, a tecla fica ligada, e o próximo toque desliga.
/// Fica em arquivo para o estado sobreviver a fechar e abrir o Deck.
final class MemoriaLigaDesliga: @unchecked Sendable {
    private let trava = NSLock()
    private var ligadas: Set<String>
    private let arquivo: URL?

    /// `arquivo` nil: só na memória (testes).
    init(arquivo: URL? = nil) {
        self.arquivo = arquivo
        if let arquivo, let dados = try? Data(contentsOf: arquivo), let ids = try? JSONDecoder().decode([String].self, from: dados) {
            ligadas = Set(ids)
        } else {
            ligadas = []
        }
    }

    /// A do Deck: em teste ou fora do app nunca grava em disco (o arquivo é da pasta de dados da variante).
    static let compartilhada = MemoriaLigaDesliga(
        arquivo: AmbienteDeTeste.ativo ? nil : Variante.atual.pastaDeDados().appendingPathComponent("teclas-ligadas.json"))

    func ligada(_ id: String) -> Bool {
        trava.lock(); defer { trava.unlock() }
        return ligadas.contains(id)
    }

    func definir(_ id: String, ligada: Bool) {
        trava.lock(); defer { trava.unlock() }
        if ligada { ligadas.insert(id) } else { ligadas.remove(id) }
        guard let arquivo, let dados = try? JSONEncoder().encode(ligadas.sorted()) else { return }
        try? FileManager.default.createDirectory(at: arquivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? dados.write(to: arquivo, options: .atomic)
    }
}

extension Tecla {
    /// Tecla de comando com liga e desliga: tem comando para desligar.
    var ligaEDesliga: Bool {
        tipo == "comando" && !(desligar ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// O comando que confere se está ligado (sai 0 = ligado), se a pessoa deu um.
    var comandoQueConfere: String? {
        let e = (estado ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? nil : e
    }
}

extension ExecutorAcoes {
    /// O comando que confere roda no mesmo shell de perfil dos comandos de ligar e desligar (aliases e PATH do .zshrc).
    /// Rodar "cru" falhava para quem usa alias, e a tecla caía sempre em "desligada".
    func conferir(_ comando: String) -> Bool {
        shell.rodar(Shell.limitadoNoPerfil(comando, segundos: limiteSegundos, shell: shellDoUsuario())).status == 0
    }
}
