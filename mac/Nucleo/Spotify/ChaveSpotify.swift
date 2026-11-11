import Foundation

/// O Client ID do app do Deck no Spotify, que vai dentro do Deck para ninguém precisar criar o próprio.
/// Com PKCE ele não é segredo, por isso pode ficar no repositório público.
/// PARA TROCAR: crie o app em developer.spotify.com/dashboard (redirect `http://127.0.0.1:4778/retorno`,
/// Web API) e cole o Client ID (32 letras e números) em `embutida`. Fork sem chave deixa `nil`.
enum ChaveSpotify {
    static let embutida: String? = "c0f9195abbda41e8a2edd002a0fe6d13"

    /// Valor que não tem 32 letras e números vale como ausente.
    static func valida(_ c: String?) -> String? {
        guard let c = c?.trimmingCharacters(in: .whitespacesAndNewlines), c.count == 32,
              c.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return c
    }
}
