import Foundation
@testable import Nucleo

/// Executor falso: devolve a resposta do primeiro trecho que aparece no comando e guarda o que rodou.
final class ExecutorFalso: Executor, @unchecked Sendable {
    private let trava = NSLock()
    private var _comandos: [String] = []
    private let respostas: [(trecho: String, saida: SaidaShell)]
    private let atraso: @Sendable (String) -> TimeInterval

    init(_ respostas: [(String, SaidaShell)], atraso: @escaping @Sendable (String) -> TimeInterval = { _ in 0 }) {
        self.respostas = respostas.map { (trecho: $0.0, saida: $0.1) }
        self.atraso = atraso
    }

    var comandos: [String] { trava.lock(); defer { trava.unlock() }; return _comandos }

    func rodar(_ comando: String) -> SaidaShell {
        trava.lock(); _comandos.append(comando); trava.unlock()
        let espera = atraso(comando)
        if espera > 0 { Thread.sleep(forTimeInterval: espera) }
        return respostas.first { comando.contains($0.trecho) }?.saida ?? SaidaShell(status: 127, saida: "comando desconhecido")
    }
}

func pastaTemporaria() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("deck-teste-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

let utc = TimeZone(identifier: "UTC")!

func config(perfil teclas: [Tecla], blocos: Blocos = Blocos(), contas: [ContaIA] = []) -> Config {
    Config(perfis: [Perfil(id: "p", nome: "P", teclas: teclas)], perfilAtivo: "p", contas: contas, blocos: blocos,
           nomeMac: "Mac de teste", codigoAcesso: "abcdefghjkmnpqrstuvw")
}
