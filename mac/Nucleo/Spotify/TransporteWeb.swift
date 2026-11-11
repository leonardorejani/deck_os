import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequisicaoWeb: Equatable, Sendable {
    var metodo: String
    var url: String
    var cabecalhos: [String: String] = [:]
    var corpo: Data? = nil
}

struct RespostaWeb: Equatable, Sendable {
    var status: Int
    var corpo: Data
}

/// Tudo que sai para a internet passa por aqui, para os testes trocarem por respostas falsas da API.
/// nil: sem rede ou sem resposta a tempo.
protocol TransporteWeb: Sendable {
    func enviar(_ r: RequisicaoWeb) -> RespostaWeb?
}

struct TransporteUrlSession: TransporteWeb {
    private final class Caixa: @unchecked Sendable { var resposta: RespostaWeb? }

    func enviar(_ r: RequisicaoWeb) -> RespostaWeb? {
        guard let u = URL(string: r.url), u.scheme == "https" else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 8)
        req.httpMethod = r.metodo
        req.httpBody = r.corpo
        for (k, v) in r.cabecalhos { req.setValue(v, forHTTPHeaderField: k) }
        let caixa = Caixa()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            if let http = resp as? HTTPURLResponse { caixa.resposta = RespostaWeb(status: http.statusCode, corpo: d ?? Data()) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return caixa.resposta
    }
}
