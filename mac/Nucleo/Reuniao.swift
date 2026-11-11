import Foundation

/// Link de reunião de vídeo no evento da agenda (Meet, Zoom ou Teams) e a abertura dele no Mac.
enum Reuniao {
    enum Servico: String, Sendable { case meet, zoom, teams }

    /// Só endereço seguro (https) de um desses serviços. É isso que o Mac aceita abrir a pedido do iPhone:
    /// o iPhone nunca manda o Mac abrir um endereço qualquer.
    static func servico(de url: URL) -> Servico? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil else { return nil }
        if host == "meet.google.com" { return .meet }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") { return .zoom }
        if host == "teams.microsoft.com" || host == "teams.live.com" { return .teams }
        return nil
    }

    static func validar(_ texto: String) -> (url: URL, servico: Servico)? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, limpo.count <= 2000, let url = URL(string: limpo), let s = servico(de: url) else { return nil }
        return (url, s)
    }

    /// O primeiro link de reunião dentre os textos do evento (endereço do evento, local, notas), na ordem dada.
    static func achar(em textos: [String?]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https://[^\s<>"'\)\]]+"#) else { return nil }
        for texto in textos.compactMap({ $0 }) {
            let tudo = NSRange(texto.startIndex..., in: texto)
            for m in regex.matches(in: texto, range: tudo) {
                guard let r = Range(m.range, in: texto) else { continue }
                let candidato = String(texto[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                if validar(candidato) != nil { return candidato }
            }
        }
        return nil
    }

    /// O endereço que abre direto no app do Zoom: zoommtg://<servidor>/join?confno=<número>&pwd=<senha>.
    /// Só vale para link de sala numerada (/j/<número>). Outro formato abre no navegador.
    static func enderecoDoAppZoom(_ url: URL) -> String? {
        guard servico(de: url) == .zoom, let host = url.host else { return nil }
        let partes = url.path.split(separator: "/").map(String.init)
        guard partes.count >= 2, partes[0] == "j", (9...12).contains(partes[1].count), partes[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var fim = "confno=\(partes[1])"
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value,
           !pwd.isEmpty, pwd.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) {
            fim += "&pwd=\(pwd)"
        }
        return "zoommtg://\(host)/join?\(fim)"
    }
}

/// Quem abre a reunião no Mac. Devolve o texto do erro para mostrar no iPhone, ou nil se deu certo.
protocol ProvedorDeReuniao: Sendable {
    func entrar(_ link: String) -> String?
}

/// Meet e Teams abrem no navegador padrão do Mac. O Zoom abre no app do Zoom se ele estiver instalado
/// neste Mac e no navegador se não (decisão do Leonardo, 11/11/2026). Nada disso é fixo: vale o que o Mac de quem usa tem.
struct AbridorDeReuniao: ProvedorDeReuniao {
    let shell: Executor

    func entrar(_ link: String) -> String? {
        guard let (url, servico) = Reuniao.validar(link) else { return "Esse link não é de uma reunião do Meet, do Zoom ou do Teams." }
        if servico == .zoom, let app = Reuniao.enderecoDoAppZoom(url), zoomInstalado(),
           shell.rodar("open \(ExecutorAcoes.escapar(app))").status == 0 {
            return nil
        }
        let r = shell.rodar("open \(ExecutorAcoes.escapar(url.absoluteString))")
        return r.status == 0 ? nil : "O Mac não conseguiu abrir o link da reunião."
    }

    func zoomInstalado() -> Bool {
        let r = shell.rodar("mdfind \"kMDItemCFBundleIdentifier == 'us.zoom.xos'\"")
        return r.status == 0 && !r.saida.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
