import Foundation

// O cabo leva o mesmo pedido que o HTTPS leva, só que em quadros: 4 bytes com o tamanho (big endian)
// e depois um JSON. Quem pergunta é o iPhone e quem responde é o Mac, mas quem abre a conexão USB é o
// Mac (o usbmuxd só deixa esse sentido), então o mesmo fio carrega os dois papéis. Cada pedido tem um
// id e a resposta volta com o mesmo, para vários pedidos andarem juntos (estado, capa, tecla).
// O espelho disto no iPhone é ios/Pacote/Sources/DeckCasca/Quadros.swift: mudou aqui, muda lá.

struct PedidoCabo: Codable, Equatable, Sendable {
    var metodo: String
    var caminho: String
    var query: [String: String]
    var cabecalhos: [String: String]
    var corpo: Data
}

struct RespostaCabo: Codable, Equatable, Sendable {
    var status: Int
    var tipo: String
    var corpo: Data
    var cabecalhos: [String: String]
}

struct MensagemCabo: Codable, Equatable, Sendable {
    /// "ola" (o Mac se apresenta), "desafio" (o iPhone pede a prova), "pedido" (do iPhone), "resposta" (do Mac) e "ping" (o Mac, para o iPhone saber que o fio vive).
    var tipo: String
    var id: Int?
    /// Só no "ola": o nome do Mac e a versão do protocolo.
    var nome: String?
    var versao: Int?
    /// Segurança do cabo: o iPhone manda "desafio" (nonce e modo) e o Mac responde com um "ola" que repete
    /// nonce e modo e leva a prova (ProvaCabo). Sem prova no "ola" de modo "codigo" quer dizer: não há código de pareamento.
    var nonce: String?
    var modo: String?
    var prova: String?
    var pedido: PedidoCabo?
    var resposta: RespostaCabo?
}

enum Quadros {
    static let versao = 1
    /// Um quadro maior que isto derruba a conexão: a capa do Spotify é o maior corpo e fica bem abaixo.
    static let maximo = 4 * 1024 * 1024

    static func codificar(_ m: MensagemCabo) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let json = try? enc.encode(m), json.count <= maximo else { return nil }
        var saida = Data()
        withUnsafeBytes(of: UInt32(json.count).bigEndian) { saida.append(contentsOf: $0) }
        saida.append(json)
        return saida
    }

    /// Lê o próximo quadro. nil quando a conexão acabou, o tamanho é absurdo ou o JSON não é do protocolo.
    static func ler(de fluxo: FluxoBytes) -> MensagemCabo? {
        guard let cab = fluxo.lerExato(4) else { return nil }
        let n = [UInt8](cab).reduce(0) { $0 << 8 | Int($1) }
        guard n > 0, n <= maximo, let corpo = fluxo.lerExato(n) else { return nil }
        return try? JSONDecoder().decode(MensagemCabo.self, from: corpo)
    }
}
