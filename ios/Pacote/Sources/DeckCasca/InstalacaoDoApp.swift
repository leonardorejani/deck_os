import Foundation

// O app diz ao Mac quem o instalou e até quando ele vale, lido do próprio perfil de provisionamento
// (embedded.mobileprovision). O Mac usa isto para não renovar por cima de uma cópia que outro app (SideStore)
// instalou e renova. O espelho é mac/Nucleo/InstalacaoDoApp.swift: mudou aqui, muda lá.

public struct InstalacaoDoApp: Codable, Equatable, Sendable {
    public var versao: String?
    public var bundleId: String?
    public var equipe: String?
    public var venceEm: Date?

    public init(versao: String? = nil, bundleId: String? = nil, equipe: String? = nil, venceEm: Date? = nil) {
        self.versao = versao
        self.bundleId = bundleId
        self.equipe = equipe
        self.venceEm = venceEm
    }

    /// O corpo do POST /api/app/instalacao (datas em ISO 8601).
    public func corpo() -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)) ?? Data("{}".utf8)
    }
}

public enum PerfilDeProvisionamento {
    public struct Lido: Equatable, Sendable {
        public var venceEm: Date?
        public var equipe: String?
        /// O application-identifier sem o prefixo da equipe, ou seja, o id do pacote que o perfil cobre.
        public var pacote: String?
    }

    /// Lê o embedded.mobileprovision: um envelope CMS assinado com o plist em texto no meio. Sem decifrar nada,
    /// o plist é o trecho entre `<?xml` e `</plist>`. nil quando o arquivo não tem plist legível.
    public static func ler(_ dados: Data) -> Lido? {
        guard let ini = dados.range(of: Data("<?xml".utf8)), let fim = dados.range(of: Data("</plist>".utf8), in: ini.lowerBound..<dados.endIndex),
              let obj = try? PropertyListSerialization.propertyList(from: dados[ini.lowerBound..<fim.upperBound], options: [], format: nil) as? [String: Any]
        else { return nil }
        let equipe = (obj["TeamIdentifier"] as? [String])?.first
        var pacote: String?
        if let app = (obj["Entitlements"] as? [String: Any])?["application-identifier"] as? String {
            pacote = equipe.flatMap { app.hasPrefix($0 + ".") ? String(app.dropFirst($0.count + 1)) : nil } ?? app
        }
        return Lido(venceEm: obj["ExpirationDate"] as? Date, equipe: equipe, pacote: pacote)
    }

    /// O que o app informa: a versão e o pacote vêm do próprio app (o pacote instalado pode ter sufixo posto pelo SideStore),
    /// o vencimento e a equipe, do perfil. Sem perfil (simulador, build de loja) vai só o que o app sabe de si.
    public static func instalacao(perfil dados: Data?, versao: String?, bundleId: String?) -> InstalacaoDoApp {
        let lido = dados.flatMap { ler($0) }
        return InstalacaoDoApp(versao: versao, bundleId: bundleId ?? lido?.pacote, equipe: lido?.equipe, venceEm: lido?.venceEm)
    }
}
