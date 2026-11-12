import Foundation
#if canImport(Security)
import Security
#endif

/// O que o Deck guarda do Spotify: a chave pública do app (Client ID) e, depois do login, os tokens.
/// Nada disso vai para o config.json nem para o iPhone (o config é lido pelo painel).
struct DadosSpotify: Codable, Equatable, Sendable {
    var clientId: String?
    var acesso: String?
    var renovacao: String?
    /// Quando o token de acesso vence (segundos desde 1970).
    var expiraEm: Double?
    /// O nome da conta conectada (só para a tela mostrar quem entrou).
    var nome: String?

    var logado: Bool { !(renovacao ?? "").isEmpty }
}

protocol ArmazemSpotify: Sendable {
    func ler() -> DadosSpotify
    /// Devolve false se não conseguiu gravar.
    @discardableResult func gravar(_ dados: DadosSpotify) -> Bool
    func apagar()
}

/// Na memória: testes, fotos e o Linux do CI.
final class ArmazemSpotifyMemoria: ArmazemSpotify, @unchecked Sendable {
    private let trava = NSLock()
    private var dados: DadosSpotify
    init(_ inicial: DadosSpotify = DadosSpotify()) { dados = inicial }
    func ler() -> DadosSpotify { trava.lock(); defer { trava.unlock() }; return dados }
    func gravar(_ d: DadosSpotify) -> Bool { trava.lock(); dados = d; trava.unlock(); return true }
    func apagar() { trava.lock(); dados = DadosSpotify(); trava.unlock() }
}

#if canImport(Security)
/// O Chaveiro do Mac: um item só, com o JSON dos dados. Acessível depois do primeiro desbloqueio,
/// porque o servidor do Deck renova o token com a tela bloqueada.
struct ArmazemSpotifyChaveiro: ArmazemSpotify {
    var servico = "com.leonardorejani.deck.spotify"
    private static let conta = "login"

    private func consulta() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico, kSecAttrAccount as String: Self.conta]
    }

    func ler() -> DadosSpotify {
        guard AmbienteDeTeste.chaveiroPermitido(servico: servico) else { return DadosSpotify() }
        var q = consulta()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var saida: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &saida) == errSecSuccess, let d = saida as? Data,
              let dados = try? JSONDecoder().decode(DadosSpotify.self, from: d) else { return DadosSpotify() }
        return dados
    }

    func gravar(_ dados: DadosSpotify) -> Bool {
        guard AmbienteDeTeste.chaveiroPermitido(servico: servico) else { return false }
        guard let json = try? JSONEncoder().encode(dados) else { return false }
        let atualizar = SecItemUpdate(consulta() as CFDictionary, [kSecValueData as String: json] as CFDictionary)
        if atualizar == errSecSuccess { return true }
        var item = consulta()
        item[kSecValueData as String] = json
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Deck: login do Spotify"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func apagar() {
        guard AmbienteDeTeste.chaveiroPermitido(servico: servico) else { return }
        SecItemDelete(consulta() as CFDictionary)
    }
}
#endif
