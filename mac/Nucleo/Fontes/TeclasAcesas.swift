import Foundation

/// Tecla acesa: roda o comando `estado` de cada tecla e acende quando o status é 0.
enum TeclasAcesas {
    /// Tempo máximo para o conjunto todo, para um comando lento não travar o estado de 1 s.
    static let limite: TimeInterval = 2

    private final class Resultados: @unchecked Sendable {
        private let trava = NSLock()
        private var acesas: Set<String> = []
        func acender(_ id: String) { trava.lock(); acesas.insert(id); trava.unlock() }
        func copia() -> Set<String> { trava.lock(); defer { trava.unlock() }; return acesas }
    }

    /// Ids das teclas acesas, na ordem das teclas. Roda tudo em paralelo. Quem passa do limite
    /// conta como apagada, e o comando dela é deixado terminar sozinho.
    static func ler(_ teclas: [Tecla], executor: any Executor, limite: TimeInterval = TeclasAcesas.limite) -> [String] {
        let comEstado = teclas.compactMap { t -> (String, String)? in
            guard let e = t.estado?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty else { return nil }
            return (t.id, e)
        }
        guard !comEstado.isEmpty else { return [] }
        let r = Resultados()
        let grupo = DispatchGroup()
        for (id, comando) in comEstado {
            grupo.enter()
            DispatchQueue.global().async {
                if executor.rodar(comando).status == 0 { r.acender(id) }
                grupo.leave()
            }
        }
        _ = grupo.wait(timeout: .now() + limite)
        let acesas = r.copia()
        return comEstado.map(\.0).filter { acesas.contains($0) }
    }
}
