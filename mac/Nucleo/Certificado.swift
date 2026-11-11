import Foundation
#if canImport(Security)
import Security
#endif

// Certificado do servidor. O iPhone só confia em HTTPS local se o certificado tiver o nome ou o IP
// do Mac no SAN, for "serverAuth" e durar no máximo 397 dias. O Deck cria um CA próprio uma vez
// (o iPhone instala e confia nele) e assina um certificado de servidor que se refaz sozinho.
// Todo comando de openssl passa pelo Executor, então a lógica é testada sem rodar nada de verdade.

struct DadosRede: Equatable, Sendable {
    /// Nome .local do Mac (`scutil --get LocalHostName` + ".local").
    var nome: String
    var ip: String?
}

struct MetaCertificado: Codable, Equatable, Sendable {
    var nome: String
    var ip: String?
    var vence: Date
}

enum CertificadoRegra {
    static let validadeDias = 397
    static let folgaDias = 30

    static func precisaRefazer(meta: MetaCertificado?, rede: DadosRede, agora: Date) -> Bool {
        guard let meta else { return true }
        if meta.nome != rede.nome || meta.ip != rede.ip { return true }
        return meta.vence.timeIntervalSince(agora) < Double(folgaDias) * 86_400
    }

    /// Arquivo de extensões do certificado de servidor.
    static func extensoes(_ rede: DadosRede) -> String {
        var san = "DNS:\(rede.nome)"
        if let ip = rede.ip { san += ",IP:\(ip)" }
        return """
        subjectAltName=\(san)
        extendedKeyUsage=serverAuth
        keyUsage=critical,digitalSignature,keyEncipherment
        basicConstraints=CA:FALSE

        """
    }

    /// Entre aspas simples para o zsh, mesmo com espaço ou aspa no caminho.
    static func aspas(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct ArquivosCertificado: Equatable, Sendable {
    var pasta: URL
    var ca: URL { pasta.appendingPathComponent("ca.crt") }
    var caChave: URL { pasta.appendingPathComponent("ca.key") }
    var servidor: URL { pasta.appendingPathComponent("servidor.crt") }
    var servidorChave: URL { pasta.appendingPathComponent("servidor.key") }
    var meta: URL { pasta.appendingPathComponent("servidor.json") }
    var extensoes: URL { pasta.appendingPathComponent("servidor.ext") }
}

struct ErroCertificado: Error, CustomStringConvertible, Equatable {
    var description: String
}

struct GeradorCertificado: Sendable {
    let pasta: URL
    let executor: Executor
    let agora: @Sendable () -> Date

    init(pasta: URL = GeradorCertificado.pastaPadrao(), executor: Executor = ExecutorShell(),
         agora: @escaping @Sendable () -> Date = { Date() }) {
        self.pasta = pasta
        self.executor = executor
        self.agora = agora
    }

    static func pastaPadrao() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Deck/certificados", isDirectory: true)
    }

    var arquivos: ArquivosCertificado { ArquivosCertificado(pasta: pasta) }

    func lerRede() throws -> DadosRede {
        let n = executor.rodar("scutil --get LocalHostName")
        let nome = n.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.status == 0, !nome.isEmpty else {
            throw ErroCertificado(description: "Não consegui descobrir o nome deste Mac na rede.")
        }
        let i = executor.rodar("ipconfig getifaddr en0 || ipconfig getifaddr en1")
        let ip = i.saida.trimmingCharacters(in: .whitespacesAndNewlines)
        return DadosRede(nome: nome + ".local", ip: i.status == 0 && !ip.isEmpty ? ip : nil)
    }

    /// Cria o que falta e refaz o certificado do servidor quando precisa. Devolve os arquivos prontos.
    @discardableResult
    func garantir() throws -> ArquivosCertificado {
        let a = arquivos
        let fm = FileManager.default
        try fm.createDirectory(at: pasta, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)

        let rede = try lerRede()
        let caExiste = fm.fileExists(atPath: a.ca.path) && fm.fileExists(atPath: a.caChave.path)
        if !caExiste { try criarCA(a) }

        let meta = (try? Self.decodificador.decode(MetaCertificado.self, from: Data(contentsOf: a.meta)))
        let completo = fm.fileExists(atPath: a.servidor.path) && fm.fileExists(atPath: a.servidorChave.path)
        if !caExiste || !completo || CertificadoRegra.precisaRefazer(meta: meta, rede: rede, agora: agora()) {
            try criarServidor(a, rede)
        }
        return a
    }

    private func rodar(_ comando: String, falha: String) throws {
        let r = executor.rodar(comando)
        guard r.status == 0 else {
            throw ErroCertificado(description: "\(falha) (\(r.saida.trimmingCharacters(in: .whitespacesAndNewlines)))")
        }
    }

    private func criarCA(_ a: ArquivosCertificado) throws {
        let q = CertificadoRegra.aspas
        try rodar("openssl req -x509 -newkey rsa:2048 -nodes -keyout \(q(a.caChave.path)) -out \(q(a.ca.path)) -days 3650 "
                  + "-subj '/CN=Deck' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'",
                  falha: "Não consegui criar o certificado de confiança do Deck")
        try Self.restringir(a.caChave)
    }

    private func criarServidor(_ a: ArquivosCertificado, _ rede: DadosRede) throws {
        let q = CertificadoRegra.aspas
        let csr = pasta.appendingPathComponent("servidor.csr")
        try Data(CertificadoRegra.extensoes(rede).utf8).write(to: a.extensoes)
        try rodar("openssl req -newkey rsa:2048 -nodes -keyout \(q(a.servidorChave.path)) -out \(q(csr.path)) "
                  + "-subj \(q("/CN=" + rede.nome))",
                  falha: "Não consegui criar a chave do servidor")
        try Self.restringir(a.servidorChave)
        try rodar("openssl x509 -req -in \(q(csr.path)) -CA \(q(a.ca.path)) -CAkey \(q(a.caChave.path)) -CAcreateserial "
                  + "-out \(q(a.servidor.path)) -days \(CertificadoRegra.validadeDias) -extfile \(q(a.extensoes.path))",
                  falha: "Não consegui assinar o certificado do servidor")
        try? FileManager.default.removeItem(at: csr)
        let vence = agora().addingTimeInterval(Double(CertificadoRegra.validadeDias) * 86_400)
        try Self.codificador.encode(MetaCertificado(nome: rede.nome, ip: rede.ip, vence: vence)).write(to: a.meta)
    }

    private static func restringir(_ arquivo: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arquivo.path)
    }

    private static var codificador: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decodificador: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

#if canImport(Security)
extension GeradorCertificado {
    /// Junta chave e certificado num PKCS12 com senha aleatória (só na memória e num arquivo
    /// temporário apagado em seguida) e importa como SecIdentity para o TLS do servidor.
    func carregarIdentidade(_ a: ArquivosCertificado) throws -> SecIdentity {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("deck-p12-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: tmp) }

        let senha = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let arqSenha = tmp.appendingPathComponent("senha")
        let arqP12 = tmp.appendingPathComponent("servidor.p12")
        try Data(senha.utf8).write(to: arqSenha, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arqSenha.path)

        let q = CertificadoRegra.aspas
        let r = executor.rodar("openssl pkcs12 -export -inkey \(q(a.servidorChave.path)) -in \(q(a.servidor.path)) "
                               + "-certfile \(q(a.ca.path)) -name Deck -passout file:\(q(arqSenha.path)) -out \(q(arqP12.path))")
        guard r.status == 0 else {
            throw ErroCertificado(description: "Não consegui preparar o certificado para o servidor (\(r.saida))")
        }

        var opcoes: [String: Any] = [kSecImportExportPassphrase as String: senha]
        // Sem isso a chave iria parar no chaveiro de login a cada abertura do app.
        if #available(macOS 15.0, *) { opcoes[kSecImportToMemoryOnly as String] = true }
        var itens: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: arqP12) as CFData, opcoes as CFDictionary, &itens)
        guard status == errSecSuccess, let lista = itens as? [[String: Any]],
              let id = lista.first?[kSecImportItemIdentity as String] else {
            throw ErroCertificado(description: "O macOS recusou o certificado do servidor (código \(status)).")
        }
        return id as! SecIdentity
    }
}
#endif
