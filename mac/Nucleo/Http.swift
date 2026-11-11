import Foundation

struct HttpRequisicao {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let cabecalhos: [String: String]
    let corpo: Data
}

enum ResultadoLeitura {
    case incompleto
    case invalido
    case ok(HttpRequisicao)
}

enum Http {
    /// Lê uma requisição HTTP/1.1 do buffer acumulado. `.incompleto` pede mais bytes.
    static func ler(_ dados: Data) -> ResultadoLeitura {
        let bytes = [UInt8](dados)
        guard let fim = indiceFimCabecalho(bytes) else {
            return bytes.count > 64 * 1024 ? .invalido : .incompleto
        }
        guard let texto = String(bytes: bytes[0..<fim], encoding: .utf8) else { return .invalido }
        var linhas = texto.components(separatedBy: "\r\n")
        let primeira = linhas.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard primeira.count >= 2 else { return .invalido }

        var cabecalhos: [String: String] = [:]
        for linha in linhas {
            guard let i = linha.firstIndex(of: ":") else { continue }
            let chave = linha[..<i].trimmingCharacters(in: .whitespaces).lowercased()
            cabecalhos[chave] = linha[linha.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }

        let tamanho = Int(cabecalhos["content-length"] ?? "0") ?? -1
        guard tamanho >= 0, tamanho <= 1024 * 1024 else { return .invalido }
        let inicio = fim + 4
        guard bytes.count - inicio >= tamanho else { return .incompleto }

        let alvo = String(primeira[1])
        let (caminho, query) = separarAlvo(alvo)
        return .ok(HttpRequisicao(
            metodo: String(primeira[0]).uppercased(),
            caminho: caminho,
            query: query,
            cabecalhos: cabecalhos,
            corpo: Data(bytes[inicio..<(inicio + tamanho)])
        ))
    }

    static func separarAlvo(_ alvo: String) -> (String, [String: String]) {
        let partes = alvo.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let caminho = decodificar(String(partes[0]), maisEhEspaco: false)
        var query: [String: String] = [:]
        if partes.count > 1 {
            for par in partes[1].split(separator: "&") {
                let kv = par.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k = decodificar(String(kv[0]), maisEhEspaco: true)
                query[k] = kv.count > 1 ? decodificar(String(kv[1]), maisEhEspaco: true) : ""
            }
        }
        return (caminho, query)
    }

    static func decodificar(_ s: String, maisEhEspaco: Bool) -> String {
        let base = maisEhEspaco ? s.replacingOccurrences(of: "+", with: " ") : s
        return base.removingPercentEncoding ?? base
    }

    static func resposta(status: Int, tipo: String, corpo: Data, extras: [String: String] = [:]) -> Data {
        var cab = "HTTP/1.1 \(status) \(textoStatus(status))\r\n"
        cab += "Content-Type: \(tipo)\r\n"
        cab += "Content-Length: \(corpo.count)\r\n"
        cab += "Connection: close\r\n"
        for (k, v) in extras.sorted(by: { $0.key < $1.key }) { cab += "\(k): \(v)\r\n" }
        cab += "\r\n"
        var saida = Data(cab.utf8)
        saida.append(corpo)
        return saida
    }

    static func json(_ status: Int, _ valor: Any) -> Data {
        let corpo = (try? JSONSerialization.data(withJSONObject: valor, options: [])) ?? Data("{}".utf8)
        return resposta(status: status, tipo: "application/json; charset=utf-8", corpo: corpo,
                        extras: ["Cache-Control": "no-store"])
    }

    static func textoStatus(_ s: Int) -> String {
        switch s {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        default: return "Error"
        }
    }

    static func tipoConteudo(_ caminho: String) -> String {
        switch (caminho as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json", "webmanifest": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }

    private static func indiceFimCabecalho(_ b: [UInt8]) -> Int? {
        guard b.count >= 4 else { return nil }
        for i in 0...(b.count - 4) where b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 {
            return i
        }
        return nil
    }
}
