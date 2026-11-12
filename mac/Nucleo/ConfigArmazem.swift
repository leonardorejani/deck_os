import Foundation

/// Guarda a config em disco. O arquivo tem o código de acesso, então fica com permissão 600.
struct ArmazemConfig {
    var url: URL
    var nomeMac: String

    static var urlPadrao: URL {
        Variante.atual.pastaDeDados().appendingPathComponent("config.json")
    }

    init(url: URL = ArmazemConfig.urlPadrao, nomeMac: String = "Mac") {
        self.url = url
        self.nomeMac = nomeMac
    }

    /// Lê a config. Arquivo ausente: cria o padrão. Arquivo que não abre: não mexe nele, guarda uma
    /// cópia ao lado e avisa, para o dono nunca perder as teclas por um erro de vírgula.
    func ler() throws -> Config {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let padrao = Config.padrao(nomeMac: nomeMac)
            try gravar(padrao)
            return padrao
        }
        let dados: Data
        do { dados = try Data(contentsOf: url) } catch {
            throw ErroConfig(mensagem: "Não consegui abrir o arquivo de configuração do Deck.")
        }
        let config: Config
        let decodificador = JSONDecoder()
        decodificador.userInfo[Config.chaveNomeMac] = nomeMac
        do { config = try decodificador.decode(Config.self, from: dados) } catch {
            throw corrompido()
        }
        if let erro = Config.validar(config) {
            // Arquivo legível: não é cópia de arquivo danificado, e ler() roda em laço (painel a cada 1 s).
            throw ErroConfig(mensagem: "A configuração do Deck tem um problema: \(erro) O arquivo original foi mantido.")
        }
        // Config antiga ou incompleta: grava a versão completa, senão o código de acesso sorteado
        // na leitura mudaria a cada abertura.
        if let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
           ["versao", "perfis", "codigoAcesso", "codigoCriadoEm", "porta", "comp", "blocos", "contas", "nomeMac"].contains(where: { json[$0] == nil })
            || json["teclas"] != nil {
            try gravar(config)
        }
        // Arquivo criado à mão ou pelo protótipo pode estar legível por outros usuários.
        if let perm = (try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber, perm.intValue & 0o777 != 0o600 {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return config
    }

    func gravar(_ config: Config) throws {
        let fm = FileManager.default
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            var dados = try codificador.encode(config)
            // Campo que este app não conhece (uma versão futura do iPhone gravou) sobrevive à edição.
            if let antigo = try? Data(contentsOf: url), let mesclado = Self.preservandoDesconhecidos(novo: dados, antigo: antigo) { dados = mesclado }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Arquivo temporário já nasce 600 e depois troca o definitivo, então não há instante
            // com o código de acesso legível por outros nem arquivo pela metade.
            let temp = url.deletingLastPathComponent().appendingPathComponent(".config-\(UUID().uuidString).tmp")
            guard fm.createFile(atPath: temp.path, contents: dados, attributes: [.posixPermissions: 0o600]) else {
                throw ErroConfig(mensagem: "Sem permissão para gravar a configuração do Deck.")
            }
            // rename troca por cima de forma atômica no Mac e no Linux (replaceItemAt falha no Linux).
            if rename(temp.path, url.path) != 0 {
                try? fm.removeItem(at: temp)
                throw ErroConfig(mensagem: "Não consegui salvar a configuração do Deck.")
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch let e as ErroConfig {
            throw e
        } catch {
            throw ErroConfig(mensagem: "Não consegui salvar a configuração do Deck.")
        }
    }

    /// Chaves que o app conhece em cada nível. O resto, vindo do arquivo antigo, volta para o novo.
    private static let conhecidas: [String: Set<String>] = [
        "config": ["versao", "perfis", "perfilAtivo", "comp", "contas", "blocos", "monitor", "controles", "nomeMac", "porta", "codigoAcesso", "teclas"],
        "perfil": ["id", "nome", "teclas"],
        "tecla": ["id", "nome", "tipo", "valor", "estado", "icone", "desligar"],
        "conta": ["id", "nome", "conta", "perfil", "mostrar"],
    ]

    /// Junta ao JSON novo os campos desconhecidos do antigo (na raiz, nos perfis, nas teclas e nas contas).
    /// Devolve nil quando não há nada a preservar, e a gravação segue idêntica à de sempre.
    static func preservandoDesconhecidos(novo: Data, antigo: Data) -> Data? {
        guard var n = (try? JSONSerialization.jsonObject(with: novo)) as? [String: Any],
              let a = (try? JSONSerialization.jsonObject(with: antigo)) as? [String: Any] else { return nil }
        var achou = false
        func extras(_ de: [String: Any], _ nivel: String, em para: inout [String: Any]) {
            for (k, v) in de where !(conhecidas[nivel]!.contains(k)) && para[k] == nil { para[k] = v; achou = true }
        }
        func lista(_ chave: String, _ dic: [String: Any]) -> [[String: Any]] { dic[chave] as? [[String: Any]] ?? [] }
        func mesclarLista(_ chave: String, nivel: String, em dic: inout [String: Any], antigas: [[String: Any]],
                          filho: ((inout [String: Any], [String: Any]) -> Void)? = nil) {
            var novas = lista(chave, dic)
            for i in novas.indices {
                guard let velho = antigas.first(where: { ($0["id"] as? String) == (novas[i]["id"] as? String) }) else { continue }
                extras(velho, nivel, em: &novas[i])
                filho?(&novas[i], velho)
            }
            if dic[chave] != nil { dic[chave] = novas }
        }
        extras(a, "config", em: &n)
        mesclarLista("perfis", nivel: "perfil", em: &n, antigas: lista("perfis", a)) { perfil, velho in
            mesclarLista("teclas", nivel: "tecla", em: &perfil, antigas: lista("teclas", velho))
        }
        mesclarLista("contas", nivel: "conta", em: &n, antigas: lista("contas", a))
        guard achou else { return nil }
        return try? JSONSerialization.data(withJSONObject: n, options: [.prettyPrinted, .sortedKeys])
    }

    private func corrompido() -> ErroConfig {
        let copia = guardarCopia()
        let onde = copia.map { " Guardei uma cópia em \($0.lastPathComponent)." } ?? ""
        return ErroConfig(mensagem: "O arquivo de configuração do Deck está danificado e não foi alterado.\(onde)")
    }

    private func guardarCopia() -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let destino = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrompido-\(f.string(from: Date()))")
        do { try FileManager.default.copyItem(at: url, to: destino); return destino } catch { return nil }
    }
}
