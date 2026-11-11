import Foundation
import Security
import DeckCasca

/// O código de acesso do Mac fica no Keychain do aparelho, nunca em arquivo. Reinstalar o app pelo
/// Xcode (a renovação de 5 em 5 dias) mantém o Keychain, então o pareamento não se perde.
final class CofreKeychain: Cofre, @unchecked Sendable {
    private let servico = "com.leonardorejani.deck.iphone"
    private let conta = "pareado"

    private var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico, kSecAttrAccount as String: conta]
    }

    func ler() -> Pareado? {
        var busca = consulta
        busca[kSecReturnData as String] = true
        busca[kSecMatchLimit as String] = kSecMatchLimitOne
        var saida: CFTypeRef?
        guard SecItemCopyMatching(busca as CFDictionary, &saida) == errSecSuccess, let dados = saida as? Data else { return nil }
        return try? JSONDecoder().decode(Pareado.self, from: dados)
    }

    func gravar(_ pareado: Pareado) {
        guard let dados = try? JSONEncoder().encode(pareado) else { return }
        let atualizado = SecItemUpdate(consulta as CFDictionary, [kSecValueData as String: dados] as CFDictionary)
        if atualizado == errSecItemNotFound {
            var novo = consulta
            novo[kSecValueData as String] = dados
            // Só depois do primeiro desbloqueio e só neste aparelho: o app reabre sozinho com o iPhone bloqueado.
            novo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(novo as CFDictionary, nil)
        }
    }

    func apagar() {
        SecItemDelete(consulta as CFDictionary)
    }
}
