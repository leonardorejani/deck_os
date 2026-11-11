import Foundation

// O usbmuxd é o serviço do macOS que fala com os iPhones plugados. Pelo soquete unix dele, o Mac pede
// a lista de aparelhos e abre uma conexão TCP até uma porta do aparelho, sem rede nenhuma (é assim que
// o PeerTalk e o iproxy funcionam). Depois do "Connect" aceito, o mesmo soquete vira o fio cru.
// Pacote: 16 bytes de cabeçalho em little endian (tamanho total, versão 1, tipo 8 = plist, tag) e o plist.

struct ErroUsbmux: Error, Equatable, CustomStringConvertible {
    var description: String
    /// Código do Result do usbmuxd: 3 = ninguém escuta nessa porta do aparelho.
    var codigo: Int?

    static let indisponivel = ErroUsbmux(description: "O serviço USB do macOS (usbmuxd) não respondeu.", codigo: nil)
    static let recusado = 3
}

/// O que a porta do cabo precisa do usbmuxd. Nos testes entra um falso.
protocol Mux: Sendable {
    /// Ids dos aparelhos plugados por USB agora (conexão por rede fica de fora: o cabo é o cabo).
    func aparelhosUSB() throws -> [Int]
    func conectar(aparelho: Int, porta: UInt16) throws -> FluxoBytes
}

struct UsbmuxReal: Mux {
    var caminho = "/var/run/usbmuxd"

    static func pacote(tag: UInt32, _ mensagem: [String: Any]) -> Data? {
        var base = mensagem
        base["ClientVersionString"] = "deck"
        base["ProgName"] = "deck"
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: base, format: .xml, options: 0) else { return nil }
        var saida = Data()
        for v in [UInt32(16 + plist.count), 1, 8, tag] { withUnsafeBytes(of: v.littleEndian) { saida.append(contentsOf: $0) } }
        saida.append(plist)
        return saida
    }

    static func lerPacote(_ fluxo: FluxoBytes) -> [String: Any]? {
        guard let cab = fluxo.lerExato(16) else { return nil }
        let b = [UInt8](cab)
        let total = (0..<4).reduce(0) { $0 | Int(b[$1]) << (8 * $1) }
        guard total >= 16, total <= 1 << 20, let corpo = fluxo.lerExato(total - 16) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: corpo, options: [], format: nil)) as? [String: Any]
    }

    private func abrir() throws -> Soquete {
        guard let s = Soquete.conectarUnix(caminho) else { throw ErroUsbmux.indisponivel }
        return s
    }

    func aparelhosUSB() throws -> [Int] {
        let s = try abrir()
        defer { s.fechar() }
        guard let p = Self.pacote(tag: 1, ["MessageType": "ListDevices"]), s.escrever(p),
              let r = Self.lerPacote(s), let lista = r["DeviceList"] as? [[String: Any]] else { throw ErroUsbmux.indisponivel }
        return lista.compactMap { d in
            let props = d["Properties"] as? [String: Any]
            guard (props?["ConnectionType"] as? String) == "USB" else { return nil }
            return (d["DeviceID"] as? NSNumber)?.intValue
        }
    }

    func conectar(aparelho: Int, porta: UInt16) throws -> FluxoBytes {
        let s = try abrir()
        // A porta vai em big endian dentro de um inteiro de 16 bits.
        let msg: [String: Any] = ["MessageType": "Connect", "DeviceID": aparelho, "PortNumber": Int(porta.bigEndian)]
        guard let p = Self.pacote(tag: 2, msg), s.escrever(p), let r = Self.lerPacote(s) else {
            s.fechar()
            throw ErroUsbmux.indisponivel
        }
        let numero = (r["Number"] as? NSNumber)?.intValue ?? -1
        guard numero == 0 else {
            s.fechar()
            throw ErroUsbmux(description: numero == ErroUsbmux.recusado ? "O app do Deck não está aberto no iPhone." : "O usbmuxd recusou a conexão (código \(numero)).", codigo: numero)
        }
        return s
    }
}
