import Foundation

// Processos do Mac para a tela do Monitor de Atividade no iPhone: os 5 que mais usam processador, os 5 que mais usam
// memória, e o botão de encerrar. Quem decide o que pode ser encerrado é o Mac (`podeEncerrar`), e ele confere de novo
// na hora de encerrar: o iPhone só obedece.

struct Processo: Codable, Equatable, Sendable {
    var pid: Int
    var nome: String
    /// Uso do processador em porcentagem de um núcleo (passa de 100 com vários núcleos), uma casa decimal.
    var cpu: Double
    /// Memória residente, em bytes.
    var memoria: Int
    /// Só processo do próprio usuário, fora os do sistema e o do Deck.
    var podeEncerrar: Bool
}

struct EstadoProcessos: Codable, Equatable, Sendable {
    var cpu: [Processo]
    var memoria: [Processo]
}

protocol ProcessosDoMac: Sendable {
    func maiores() -> EstadoProcessos
    /// Pede ao processo que feche (SIGTERM, ele pode salvar antes). `nome` é o que a tela mostrava: se o pid já é de outro
    /// programa, não encerra. Erro em texto, ou nil se deu certo.
    func encerrar(pid: Int, nome: String) -> String?
}

enum Processos {
    static let quantos = 5
    /// Fechar isso derruba a sessão ou o próprio Deck.
    static let protegidos: Set<String> = ["launchd", "kernel_task", "loginwindow", "WindowServer", "Deck", "Deck Bancada"]
    /// O comando que lista os processos. Sem cabeçalho (`=`), e o nome do programa por último porque pode ter espaço.
    static let comandoLista = "ps -axo pid=,pcpu=,rss=,user=,comm="

    struct Linha: Equatable {
        var pid: Int
        var cpu: Double
        var rssKB: Int
        var usuario: String
        var nome: String
    }

    /// "pid pcpu rss usuario comando". O comando vem com o caminho inteiro: o nome é o último pedaço dele.
    static func ler(_ saida: String) -> [Linha] {
        saida.split(whereSeparator: \.isNewline).compactMap { linha in
            var resto = Substring(linha)
            var campos: [Substring] = []
            for _ in 0..<4 {
                resto = resto.drop(while: { $0 == " " || $0 == "\t" })
                guard let fim = resto.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
                campos.append(resto[..<fim]); resto = resto[fim...]
            }
            let comando = resto.trimmingCharacters(in: .whitespaces)
            guard let pid = Int(campos[0]), let cpu = Double(campos[1].replacingOccurrences(of: ",", with: ".")), let rss = Int(campos[2]), !comando.isEmpty else { return nil }
            return Linha(pid: pid, cpu: cpu, rssKB: rss, usuario: String(campos[3]), nome: nome(deComando: comando))
        }
    }

    static func nome(deComando c: String) -> String {
        let ultimo = c.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? c
        return ultimo.isEmpty ? c : ultimo
    }

    static func podeEncerrar(_ l: Linha, usuario: String, eu: Int) -> Bool {
        l.pid > 1 && l.pid != eu && l.usuario == usuario && !protegidos.contains(l.nome)
    }

    static func maiores(_ linhas: [Linha], usuario: String, eu: Int, quantos n: Int = quantos) -> EstadoProcessos {
        // o `ps` que acabou de medir também aparece, e não é nada que a pessoa queira ver
        let validas = linhas.filter { $0.nome != "ps" && $0.pid != eu }
        func processo(_ l: Linha) -> Processo {
            Processo(pid: l.pid, nome: l.nome, cpu: (l.cpu * 10).rounded() / 10, memoria: l.rssKB * 1024, podeEncerrar: podeEncerrar(l, usuario: usuario, eu: eu))
        }
        let porCpu = validas.sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.pid < $1.pid }.prefix(n)
        let porMemoria = validas.sorted { $0.rssKB != $1.rssKB ? $0.rssKB > $1.rssKB : $0.pid < $1.pid }.prefix(n)
        return EstadoProcessos(cpu: porCpu.map(processo), memoria: porMemoria.map(processo))
    }
}

final class ProcessosReais: ProcessosDoMac, @unchecked Sendable {
    private let executor: any Executor
    private let usuario: String
    private let eu: Int
    private let matar: @Sendable (Int32) -> Int32

    /// `eu` é o pid do próprio app (nunca se encerra, e a lista nem o mostra). `matar` devolve 0 se o sinal foi entregue.
    init(executor: any Executor = ExecutorShell(), usuario: String = NSUserName(), eu: Int = Int(getpid()),
         matar: @escaping @Sendable (Int32) -> Int32 = { kill($0, SIGTERM) }) {
        self.executor = executor; self.usuario = usuario; self.eu = eu; self.matar = matar
    }

    func maiores() -> EstadoProcessos {
        let r = executor.rodar(Processos.comandoLista)
        guard r.status == 0 else { return EstadoProcessos(cpu: [], memoria: []) }
        return Processos.maiores(Processos.ler(r.saida), usuario: usuario, eu: eu)
    }

    func encerrar(pid: Int, nome: String) -> String? {
        guard pid > 1, pid != eu, pid <= Int(Int32.max) else { return "Esse processo não pode ser encerrado." }
        let r = executor.rodar("ps -p \(pid) -o pid=,pcpu=,rss=,user=,comm=")
        guard r.status == 0, let atual = Processos.ler(r.saida).first(where: { $0.pid == pid }) else { return "Esse processo já tinha fechado." }
        guard atual.nome == nome else { return "Esse número agora é de outro programa. Atualize a lista." }
        guard Processos.podeEncerrar(atual, usuario: usuario, eu: eu) else { return "Esse processo é do sistema ou do Deck e não pode ser encerrado." }
        return matar(Int32(pid)) == 0 ? nil : "Não consegui encerrar o \(nome)."
    }
}
