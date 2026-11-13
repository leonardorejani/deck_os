import Foundation

/// Config sem o código de acesso: é o que o GET /api/config devolve ao iPhone.
struct ConfigPublica: Codable, Equatable, Sendable {
    var versao: Int
    var perfis: [Perfil]
    var perfilAtivo: String
    var comp: String
    var contas: [ContaIA]
    var blocos: Blocos
    var whatsapp: ConfigWhatsApp
    var monitor: ConfigMonitor
    var controles: ConfigControles
    var nomeMac: String
    var porta: Int
}

extension Config {
    var publica: ConfigPublica {
        ConfigPublica(versao: versao, perfis: perfis, perfilAtivo: perfilAtivo, comp: comp, contas: contas,
                      blocos: blocos, whatsapp: whatsapp, monitor: monitor, controles: controles, nomeMac: nomeMac, porta: porta)
    }

    /// Lê o corpo do PUT /api/config. Corpo sem alguma das chaves de uma config completa é recusado:
    /// o leitor tolerante preencheria o que falta com o padrão e apagaria a config do usuário.
    static func receber(corpo: Data, sobre atual: Config) -> Result<Config, ErroConfig> {
        guard let json = try? JSONSerialization.jsonObject(with: corpo) as? [String: Any] else {
            return .failure(ErroConfig(mensagem: "Não entendi a configuração enviada."))
        }
        if chavesObrigatoriasNoPut.contains(where: { json[$0] == nil }) {
            return .failure(ErroConfig(mensagem: "A configuração enviada está incompleta e nada foi alterado."))
        }
        let decodificador = JSONDecoder()
        decodificador.userInfo[chaveNomeMac] = atual.nomeMac
        guard let recebida = try? decodificador.decode(Config.self, from: corpo) else {
            return .failure(ErroConfig(mensagem: "Não entendi a configuração enviada."))
        }
        // Painel velho no cache do iPhone ainda não conhece o WhatsApp Web: o PUT dele não traz a chave e
        // o padrão não pode apagar o que o usuário escolheu.
        var completa = recebida
        if json["whatsapp"] == nil { completa.whatsapp = atual.whatsapp }
        // Mesmo caso do monitor (12/11/2026): painel velho não conhece a chave, e o padrão não apaga a escolha.
        if json["monitor"] == nil { completa.monitor = atual.monitor }
        // E para a chave do monitor dentro de `blocos`: painel velho manda o `false` antigo e não sabe da escolha.
        if (json["blocos"] as? [String: Any])?["monitorEscolhido"] == nil {
            completa.blocos.monitor = atual.blocos.monitor; completa.blocos.monitorEscolhido = atual.blocos.monitorEscolhido
        }
        // E para as barras dos Controles do Mac (12/11/2026).
        if json["controles"] == nil { completa.controles = atual.controles }
        // Idem para o lugar padrão da agenda: painel velho não manda a chave e não pode apagar a escolha.
        if json["agendaPadrao"] == nil { completa.agendaPadrao = atual.agendaPadrao }
        return aplicar(recebida: completa, sobre: atual)
    }

    /// PUT /api/config: o iPhone organiza perfis, teclas, contas e blocos, mas nunca troca o código de
    /// acesso nem a porta. Esses dois vêm sempre da config atual, valendo o que o iPhone mandou ou não.
    static func aplicar(recebida: Config, sobre atual: Config) -> Result<Config, ErroConfig> {
        var nova = recebida
        nova.versao = Config.versaoAtual
        nova.codigoAcesso = atual.codigoAcesso
        nova.codigoCriadoEm = atual.codigoCriadoEm
        nova.codigoAnterior = atual.codigoAnterior
        nova.anteriorValeAte = atual.anteriorValeAte
        nova.porta = atual.porta
        if !nova.perfis.contains(where: { $0.id == nova.perfilAtivo }), let primeiro = nova.perfis.first {
            nova.perfilAtivo = primeiro.id
        }
        if let erro = validar(nova) { return .failure(ErroConfig(mensagem: erro)) }
        return .success(nova)
    }
}
