import Foundation
import Security

/// Onde o token colado fica guardado. O token do Claude Code nunca vai para arquivo nem para log.
protocol CofreDeToken: Sendable {
    func guardar(_ token: String, conta: String) throws
    func ler(conta: String) -> String?
    func apagar(conta: String)
}

struct ErroChaveiro: Error, Equatable { var codigo: OSStatus }

/// O Chaveiro do Mac (Security, kSecClassGenericPassword). Um item por conta do Deck.
struct Chaveiro: CofreDeToken {
    var servico = "com.leonardorejani.deck.token-claude"

    private func consulta(_ conta: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico, kSecAttrAccount as String: conta]
    }

    func guardar(_ token: String, conta: String) throws {
        apagar(conta: conta)
        var item = consulta(conta)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Deck: token do Claude Code"
        let r = SecItemAdd(item as CFDictionary, nil)
        if r != errSecSuccess { throw ErroChaveiro(codigo: r) }
    }

    func ler(conta: String) -> String? {
        var q = consulta(conta)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var saida: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &saida) == errSecSuccess, let d = saida as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func apagar(conta: String) { SecItemDelete(consulta(conta) as CFDictionary) }
}
