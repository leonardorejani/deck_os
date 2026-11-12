import Foundation

/// Quando o Deck roda como hospedeiro de teste (xcodebuild test), ele não pode tocar no que é do dono:
/// Chaveiro de login, config real, defaults reais. Um item do Chaveiro criado por outro build assinado
/// de outro jeito faz o macOS perguntar a senha na tela dele.
enum AmbienteDeTeste {
    static var ativo: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil || NSClassFromString("XCTestCase") != nil
    }

    /// Único prefixo de serviço do Chaveiro que um teste pode usar de verdade (item criado e apagado pelo próprio teste).
    static let prefixoDeServicoDeTeste = "com.leonardorejani.deck.teste-"

    /// Marca que o verificar.sh procura na saída do xcodebuild: se aparecer, algo tentou o Chaveiro real.
    static let marcaDeBloqueio = "DECK-CHAVEIRO-REAL-BLOQUEADO"

    nonisolated(unsafe) static var aoBloquear: (String) -> Void = { servico in
        FileHandle.standardError.write(Data("\(marcaDeBloqueio): \(servico)\n".utf8))
    }

    /// Pergunta antes de cada SecItem*: em teste só passa serviço de teste. Fora de teste, sempre passa.
    static func chaveiroPermitido(servico: String) -> Bool {
        guard ativo else { return true }
        if servico.hasPrefix(prefixoDeServicoDeTeste) { return true }
        aoBloquear(servico)
        return false
    }

    /// Preferências do hospedeiro de teste: o domínio padrão seria o do Deck de verdade.
    static func defaultsPadrao() -> UserDefaults {
        ativo ? (UserDefaults(suiteName: "deck-teste-hospedeiro") ?? .standard) : .standard
    }
}
