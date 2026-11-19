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
    /// Tecla liga e desliga sem comando de conferir acende pelo que o Deck guardou (`memoria`).
    static func ler(_ teclas: [Tecla], executor: any Executor, limite: TimeInterval = TeclasAcesas.limite,
                    memoria: MemoriaLigaDesliga = .compartilhada, shellDoUsuario: () -> String = { Shell.doUsuario() }) -> [String] {
        let guardadas = Set(teclas.filter { $0.ligaEDesliga && $0.comandoQueConfere == nil && memoria.ligada($0.id) }.map(\.id))
        // Tecla liga e desliga confere no shell de perfil (o mesmo que a faz ligar e desligar). As de sempre (Manter acordado) seguem cruas.
        let shell = shellDoUsuario()
        let segundos = max(1, Int(limite.rounded(.up)))
        let comEstado = teclas.compactMap { t -> (String, String)? in
            guard let e = t.comandoQueConfere else { return nil }
            return (t.id, t.ligaEDesliga ? Shell.limitadoNoPerfil(e, segundos: segundos, shell: shell) : e)
        }
        guard !comEstado.isEmpty else { return teclas.map(\.id).filter { guardadas.contains($0) } }
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
        return teclas.map(\.id).filter { acesas.contains($0) || guardadas.contains($0) }
    }
}
