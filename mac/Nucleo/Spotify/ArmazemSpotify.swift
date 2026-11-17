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

/// Até quando o Spotify mandou esperar (429 com Retry-After). Não é segredo: fica num arquivo comum, nunca no Chaveiro
/// (ler o Chaveiro na partida do app é o que faz o macOS pedir a senha e travar tudo).
protocol ArmazemDoLimite: Sendable {
    func ler() -> Date?
    func gravar(_ ate: Date?)
}

final class LimiteEmMemoria: ArmazemDoLimite, @unchecked Sendable {
    private let trava = NSLock()
    private var ate: Date?
    func ler() -> Date? { trava.lock(); defer { trava.unlock() }; return ate }
    func gravar(_ novo: Date?) { trava.lock(); ate = novo; trava.unlock() }
}

/// `spotify-limite.json` na pasta de dados da variante, com permissão 0600.
struct LimiteEmArquivo: ArmazemDoLimite {
    var url: URL

    static func padrao() -> LimiteEmArquivo {
        LimiteEmArquivo(url: Variante.atual.pastaDeDados().appendingPathComponent("spotify-limite.json"))
    }

    private struct Registro: Codable { var bloqueadoAte: Double }

    func ler() -> Date? {
        guard let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(Registro.self, from: d) else { return nil }
        return Date(timeIntervalSince1970: r.bloqueadoAte)
    }

    func gravar(_ ate: Date?) {
        guard let ate else { try? FileManager.default.removeItem(at: url); return }
        guard let json = try? JSONEncoder().encode(Registro(bloqueadoAte: ate.timeIntervalSince1970)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: json, attributes: [.posixPermissions: 0o600])
    }
}

/// Guarda na memória o que o armazém lento (Chaveiro) já respondeu: a primeira leitura vai ao Chaveiro, as outras não.
/// O Deck é o único que grava lá, então a cópia nunca fica velha. Quem chama é quem lê (nunca a linha principal).
final class ArmazemSpotifyEmCache: ArmazemSpotify, @unchecked Sendable {
    private let base: ArmazemSpotify
    private let trava = NSLock()
    private var guardado: DadosSpotify?
    init(_ base: ArmazemSpotify) { self.base = base }

    func ler() -> DadosSpotify {
        trava.lock(); defer { trava.unlock() }
        if let g = guardado { return g }
        let d = base.ler()
        guardado = d
        return d
    }

    func gravar(_ dados: DadosSpotify) -> Bool {
        trava.lock(); defer { trava.unlock() }
        let ok = base.gravar(dados)
        if ok { guardado = dados }
        return ok
    }

    func apagar() { trava.lock(); defer { trava.unlock() }; base.apagar(); guardado = DadosSpotify() }
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
    var servico = Variante.atual.servicoDoChaveiro("spotify")
    private static let conta = "login"

    /// Nunca abre a janela de senha do Chaveiro: item que este build não pode abrir responde com falha (e vira "desconectado"),
    /// em vez de travar o app esperando a pessoa. O item existente não é apagado nem trocado.
    private func consulta() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servico, kSecAttrAccount as String: Self.conta,
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
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
        item[kSecUseAuthenticationUI as String] = nil
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
