import Foundation

// Diário do Bluetooth do iPhone: cada passo do rádio e do aperto de mão, com horário (UTC, igual ao deck.log do Mac).
// Fica num anel de ~500 linhas na memória e num arquivo em Documents/bluetooth.log, para o Mac puxar pelo cabo:
//   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
//     --domain-identifier com.leonardorejani.deck.iphone --source Documents/bluetooth.log --destination <arquivo>
// Nunca recebe chave nem código de acesso: quem anota só passa identificador, nome, sinal e estado.

public final class DiarioBluetooth: @unchecked Sendable {
    public static let capacidadePadrao = 500

    private let arquivo: URL?
    private let capacidade: Int
    private let relogio: @Sendable () -> Date
    private let fila = DispatchQueue(label: "deck.bluetooth.diario")
    private var linhas: [String] = []
    private var desdeARegravacao = 0
    private let formato: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `arquivo` nil guarda só na memória (testes). O arquivo vira no máximo ~2x a capacidade antes de ser regravado só com o anel.
    public init(arquivo: URL?, capacidade: Int = DiarioBluetooth.capacidadePadrao, relogio: @escaping @Sendable () -> Date = { Date() }) {
        self.arquivo = arquivo
        self.capacidade = max(1, capacidade)
        self.relogio = relogio
        if let arquivo, let texto = try? String(contentsOf: arquivo, encoding: .utf8) {
            linhas = Array(texto.split(separator: "\n", omittingEmptySubsequences: true).suffix(self.capacidade).map(String.init))
        }
    }

    /// Documents/bluetooth.log do app.
    public static let padrao: DiarioBluetooth = {
        let pasta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return DiarioBluetooth(arquivo: pasta?.appendingPathComponent("bluetooth.log"))
    }()

    public func anotar(_ texto: String) {
        fila.sync {
            let linha = "\(formato.string(from: relogio())) \(texto.replacingOccurrences(of: "\n", with: " "))"
            linhas.append(linha)
            if linhas.count > capacidade { linhas.removeFirst(linhas.count - capacidade) }
            guard let arquivo else { return }
            desdeARegravacao += 1
            if desdeARegravacao >= capacidade || !FileManager.default.fileExists(atPath: arquivo.path) {
                desdeARegravacao = 0
                try? (linhas.joined(separator: "\n") + "\n").write(to: arquivo, atomically: true, encoding: .utf8)
            } else if let h = try? FileHandle(forWritingTo: arquivo) {
                h.seekToEndOfFile()
                h.write(Data((linha + "\n").utf8))
                try? h.close()
            }
        }
    }

    /// As linhas do anel, da mais antiga para a mais nova.
    public var recentes: [String] { fila.sync { linhas } }
}

/// Por que um anúncio visto no ar foi aceito ou descartado. Pura (sem CoreBluetooth), para ter teste.
enum AvaliacaoDeAnuncio {
    struct Resultado: Equatable {
        var aceito: Bool
        var motivo: String
    }

    /// `servicos` e `extras` são os UUIDs do pacote principal e da área extra do anúncio. `comFiltro` diz se o iOS já
    /// filtrou pelo serviço do Deck (varredura com filtro): aí tudo que chega vale, mesmo sem o UUID à vista.
    static func avaliar(servicos: [String], extras: [String], nome: String?, rssi: Int, uuidDoDeck: String,
                        nomesConhecidos: Set<String>, comFiltro: Bool) -> Resultado {
        let alvo = uuidDoDeck.uppercased()
        if rssi == 127 { return Resultado(aceito: false, motivo: "sinal 127 (sem leitura)") }
        if servicos.contains(where: { $0.uppercased() == alvo }) { return Resultado(aceito: true, motivo: "serviço do Deck no pacote principal") }
        if extras.contains(where: { $0.uppercased() == alvo }) { return Resultado(aceito: true, motivo: "serviço do Deck na área extra") }
        if comFiltro { return Resultado(aceito: true, motivo: "entregue pelo filtro do iOS (UUID não visível no pacote)") }
        if let nome, nomesConhecidos.contains(nome) { return Resultado(aceito: true, motivo: "nome do Mac pareado") }
        return Resultado(aceito: false, motivo: "sem o serviço do Deck e nome não é o do Mac pareado")
    }
}
