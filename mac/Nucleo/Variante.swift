import Foundation

/// O Deck tem duas formas do mesmo app do Mac: o Deck de verdade e o Deck Bancada, a cópia que serve só para
/// testar as telas sem encostar no Deck instalado. Quem decide é o identificador do pacote: a bancada tem o dela.
/// Tudo que é "do dono" (config, certificados, log, Chaveiro, porta) tem um nome por variante, então a bancada nunca
/// lê nem grava o que é do Deck real (e por isso nunca faz o macOS pedir a senha do Chaveiro dele).
enum Variante: Equatable, Sendable {
    case deck
    case bancada

    static let idDaBancada = "com.leonardorejani.deck.bancada"
    static let portaDaBancada = 4791

    static let atual: Variante = Bundle.main.bundleIdentifier == idDaBancada ? .bancada : .deck

    /// Nome da pasta em Application Support e em Logs.
    var nomeDaPasta: String { self == .bancada ? "Deck Bancada" : "Deck" }

    /// Porta que a variante exige. O Deck de verdade usa a da config (4790 por padrão).
    var portaFixa: Int? { self == .bancada ? Self.portaDaBancada : nil }

    /// A bancada não tem iPhone: sem cabo, sem Bluetooth e sem renovar o app do iPhone.
    var ligaIphone: Bool { self == .deck }

    /// Bluetooth e Rede local só servem ao iPhone. Na bancada o macOS nunca pode perguntar por eles, nem pelos botões
    /// de pedir acesso: a lista de Acessos do Mac esconde os dois e o pedido é recusado sem tocar no sistema.
    var pedeBluetoothERedeLocal: Bool { ligaIphone }

    /// A bancada só escuta neste Mac (loopback), então não aparece para mais ninguém na rede.
    var somenteLocal: Bool { self == .bancada }

    /// Nome de serviço do Chaveiro. O do Deck real não muda (os itens já guardados continuam lá).
    func servicoDoChaveiro(_ nome: String) -> String {
        "com.leonardorejani.deck." + (self == .bancada ? "bancada." : "") + nome
    }

    func pastaDeDados(casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        casa.appendingPathComponent("Library/Application Support/\(nomeDaPasta)", isDirectory: true)
    }

    func pastaDeLog(casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        casa.appendingPathComponent("Library/Logs/\(nomeDaPasta)", isDirectory: true)
    }
}

/// Primeira abertura da bancada: parte de uma cópia da config do Deck real (que só é lida, nunca alterada).
enum PrimeiraAberturaDaBancada {
    enum Resultado: Equatable { case jaTinhaConfig, copiou, semOrigem, falhou }

    /// Copia só o config.json (teclas, perfis, blocos), com a porta da bancada. Os certificados ficam de fora: a bancada
    /// cria os dela. Se a bancada já tem config, não mexe em nada.
    @discardableResult
    static func preparar(origem: URL, destino: URL) -> Resultado {
        let fm = FileManager.default
        if fm.fileExists(atPath: destino.path) { return .jaTinhaConfig }
        guard let dados = try? Data(contentsOf: origem) else { return .semOrigem }
        guard var json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else { return .falhou }
        json["porta"] = Variante.portaDaBancada
        guard let novo = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return .falhou }
        do {
            try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: destino.path, contents: novo, attributes: [.posixPermissions: 0o600]) else { return .falhou }
            return .copiou
        } catch { return .falhou }
    }

    /// A config do Deck real, no lugar de sempre (só para ler).
    static var origemPadrao: URL { Variante.deck.pastaDeDados().appendingPathComponent("config.json") }
}
