import Foundation

// Lógica da config: leitura tolerante, migração do protótipo, padrão, validação e código de acesso.
// Os tipos (Config, Perfil, Tecla...) são o contrato e moram em Modelos.swift.

/// Erro com texto pronto para o iPhone ou para o Mac mostrar, em português e sem jargão.
struct ErroConfig: Error, Equatable, LocalizedError, Sendable {
    var mensagem: String
    var errorDescription: String? { mensagem }
}

private struct ChavesConfig: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ nome: String) { stringValue = nome }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Blocos {
    /// O Codable sintetizado ignora os valores padrão quando falta chave. Aqui falta = ligado.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ChavesConfig.self)
        func ler(_ nome: String, padrao: Bool = true) throws -> Bool { try c.decodeIfPresent(Bool.self, forKey: ChavesConfig(nome)) ?? padrao }
        self.init(spotify: try ler("spotify"), agenda: try ler("agenda"), whatsapp: try ler("whatsapp"),
                  sessoes: try ler("sessoes"), uso: try ler("uso"), monitor: try ler("monitor", padrao: false))
    }
}

extension ConfigMonitor {
    /// Item que falta fica ligado: quem liga o monitor começa vendo tudo e desliga o que não quer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ChavesConfig.self)
        func ler(_ nome: String) -> Bool { ((try? c.decodeIfPresent(Bool.self, forKey: ChavesConfig(nome))) ?? nil) ?? true }
        self.init(cpu: ler("cpu"), memoria: ler("memoria"), bateria: ler("bateria"), rede: ler("rede"))
    }
}

extension ConfigWhatsApp {
    static let origens = ["auto", "app", "web", "qr"]

    /// Leitura tolerante: chave faltando ou valor que o Deck não conhece volta para o padrão (auto, sem
    /// navegador fixo), em vez de derrubar a config inteira.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ChavesConfig.self)
        let origem = (try? c.decodeIfPresent(String.self, forKey: ChavesConfig("origem"))) ?? nil
        let navegador = (try? c.decodeIfPresent(String.self, forKey: ChavesConfig("navegador"))) ?? nil
        let antes = (try? c.decodeIfPresent(String.self, forKey: ChavesConfig("origemAntes"))) ?? nil
        self.init(origem: origem.flatMap { Self.origens.contains($0) ? $0 : nil } ?? "auto",
                  navegador: navegador.flatMap { n in NavegadorWeb.todos.contains { $0.nome == n } ? n : nil },
                  origemAntes: antes.flatMap { Self.origens.contains($0) && $0 != "qr" ? $0 : nil })
    }
}

extension Tecla {
    private enum Chave: String, CodingKey { case id, nome, tipo, valor, estado, icone, acao }

    /// Leitura tolerante da ação de app: `acao` malformada (de uma versão futura, por exemplo) vira nil e a
    /// tecla só abre o app, em vez de derrubar a config inteira. O resto é estrito como sempre foi.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Chave.self)
        self.init(id: try c.decode(String.self, forKey: .id), nome: try c.decode(String.self, forKey: .nome),
                  tipo: try c.decode(String.self, forKey: .tipo), valor: try c.decode(String.self, forKey: .valor),
                  estado: try c.decodeIfPresent(String.self, forKey: .estado),
                  icone: try c.decodeIfPresent(String.self, forKey: .icone),
                  acao: (try? c.decodeIfPresent(AcaoDeApp.self, forKey: .acao)) ?? nil)
    }

    /// A tecla "painel" do protótipo antigo virou "app" (igual normalizarTecla em prototipo/dados.js).
    /// Painel desconhecido não tem como abrir: devolve nil e a tecla some.
    static func normalizada(_ t: Tecla) -> Tecla? {
        guard t.tipo == "painel" else { return t }
        guard let app = ["whatsapp": "WhatsApp", "calendario": "Calendar"][t.valor] else { return nil }
        var nova = t
        nova.tipo = "app"
        nova.valor = app
        return nova
    }
}

extension Config {
    /// Lê tolerando chave faltando e a config antiga do protótipo (teclas na raiz, sem perfis).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: ChavesConfig.self)
        func chave(_ nome: String) -> ChavesConfig { ChavesConfig(nome) }
        func limpar(_ l: [Tecla]) -> [Tecla] { l.compactMap(Tecla.normalizada) }
        // O decoder não sabe o nome real do Mac: quem lê do disco passa o nome em userInfo.
        let nomePadrao = (decoder.userInfo[Config.chaveNomeMac] as? String) ?? "Mac"

        var perfis: [Perfil]
        if let lidos = try c.decodeIfPresent([Perfil].self, forKey: chave("perfis")), !lidos.isEmpty {
            perfis = lidos.map { Perfil(id: $0.id, nome: $0.nome, teclas: limpar($0.teclas)) }
        } else if let antigas = try c.decodeIfPresent([Tecla].self, forKey: chave("teclas")) {
            perfis = [Perfil(id: "principal", nome: "Principal", teclas: limpar(antigas))]
        } else {
            perfis = Config.padrao(nomeMac: nomePadrao).perfis
        }
        let ativo = try c.decodeIfPresent(String.self, forKey: chave("perfilAtivo"))
        self.init(
            versao: try c.decodeIfPresent(Int.self, forKey: chave("versao")) ?? Config.versaoAtual,
            perfis: perfis,
            perfilAtivo: perfis.contains { $0.id == ativo } ? ativo! : perfis[0].id,
            comp: try c.decodeIfPresent(String.self, forKey: chave("comp")) ?? "a",
            contas: try c.decodeIfPresent([ContaIA].self, forKey: chave("contas")) ?? [],
            blocos: try c.decodeIfPresent(Blocos.self, forKey: chave("blocos")) ?? Blocos(),
            whatsapp: (try? c.decodeIfPresent(ConfigWhatsApp.self, forKey: chave("whatsapp"))) ?? ConfigWhatsApp(),
            monitor: (try? c.decodeIfPresent(ConfigMonitor.self, forKey: chave("monitor"))) ?? ConfigMonitor(),
            nomeMac: try c.decodeIfPresent(String.self, forKey: chave("nomeMac")) ?? nomePadrao,
            porta: try c.decodeIfPresent(Int.self, forKey: chave("porta")) ?? 4777,
            codigoAcesso: try c.decodeIfPresent(String.self, forKey: chave("codigoAcesso")) ?? Config.novoCodigoAcesso(),
            // Config antiga sem data: o código que ela tem vira o atual, criado agora.
            codigoCriadoEm: try c.decodeIfPresent(Int.self, forKey: chave("codigoCriadoEm")) ?? Int(Date().timeIntervalSince1970),
            codigoAnterior: try c.decodeIfPresent(String.self, forKey: chave("codigoAnterior")),
            anteriorValeAte: try c.decodeIfPresent(Int.self, forKey: chave("anteriorValeAte")),
            agendaPadrao: (try? c.decodeIfPresent(DestinoAgenda.self, forKey: chave("agendaPadrao"))) ?? nil
        )
    }

    /// Chave do userInfo do JSONDecoder com o nome do Mac, usado quando o JSON não traz "nomeMac".
    static let chaveNomeMac = CodingUserInfoKey(rawValue: "deck.nomeMac")!

    /// Chaves que um PUT completo sempre traz (é o que o GET devolve). Corpo sem elas é parcial.
    static let chavesObrigatoriasNoPut = ["perfis", "perfilAtivo", "comp", "contas", "blocos", "nomeMac"]

    static let alfabetoCodigo = "abcdefghjkmnpqrstuvwxyz23456789"
    static let tamanhoCodigo = 20

    /// 20 letras sem as ambíguas (i, l, o, 0, 1), sorteadas pelo gerador seguro do sistema.
    static func novoCodigoAcesso() -> String {
        var gerador = SystemRandomNumberGenerator()
        let letras = Array(alfabetoCodigo)
        return String((0..<tamanhoCodigo).map { _ in letras.randomElement(using: &gerador)! })
    }

    static func padrao(nomeMac: String) -> Config {
        let teclas = [
            Tecla(id: "acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k",
                  estado: "pmset -g assertions | grep -q 'Vorssaint: keep the Mac awake'", icone: "Vorssaint"),
            Tecla(id: "whatsapp", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: "WhatsApp"),
            Tecla(id: "agenda", nome: "Agenda", tipo: "app", valor: "Calendar", estado: nil, icone: "Calendar"),
            Tecla(id: "apagar", nome: "Apagar tela", tipo: "comando", valor: "pmset displaysleepnow", estado: nil, icone: "svg:tela"),
        ]
        return Config(perfis: [Perfil(id: "trabalho", nome: "Trabalho", teclas: teclas)], perfilAtivo: "trabalho",
                      nomeMac: nomeMac, codigoAcesso: novoCodigoAcesso())
    }

    static let tiposDeTecla: Set<String> = ["app", "tecla", "comando", "atalho"]

    /// Texto em português para mostrar no iPhone, ou nil se a config é válida.
    static func validar(_ c: Config) -> String? {
        if c.perfis.isEmpty { return "É preciso ter pelo menos um perfil." }
        var idsPerfil = Set<String>()
        for p in c.perfis {
            if vazio(p.id) || !idsPerfil.insert(p.id).inserted { return "Há perfis com o mesmo identificador." }
            if vazio(p.nome) { return "Todo perfil precisa de um nome." }
            var idsTecla = Set<String>()
            for t in p.teclas {
                if vazio(t.id) || !idsTecla.insert(t.id).inserted { return "Há teclas repetidas no perfil \"\(p.nome)\"." }
                if vazio(t.nome) { return "Há uma tecla sem nome no perfil \"\(p.nome)\"." }
                if !tiposDeTecla.contains(t.tipo) { return "O tipo da tecla \"\(t.nome)\" não é válido." }
                if vazio(t.valor) { return "A tecla \"\(t.nome)\" está sem ação." }
                if t.tipo == "tecla", Teclas.ler(t.valor) == nil { return "A combinação da tecla \"\(t.nome)\" não foi reconhecida: \(t.valor)" }
                if let erro = validarAcao(t) { return erro }
            }
        }
        if vazio(c.nomeMac) { return "O nome do Mac não pode ficar vazio." }
        var idsConta = Set<String>()
        for conta in c.contas {
            if vazio(conta.id) || !idsConta.insert(conta.id).inserted { return "Há contas repetidas ou sem identificador." }
            if vazio(conta.nome) { return "Toda conta precisa de um serviço (Claude ou Codex)." }
            if vazio(conta.conta) { return "Toda conta precisa de um nome." }
            if let perfil = conta.perfil, !perfilDeContaValido(perfil) {
                return "O perfil da conta \"\(conta.conta)\" não é válido."
            }
        }
        if !ConfigWhatsApp.origens.contains(c.whatsapp.origem) { return "A origem do WhatsApp deve ser automática, app, web ou QR." }
        if let n = c.whatsapp.navegador, !NavegadorWeb.todos.contains(where: { $0.nome == n }) {
            return "O navegador do WhatsApp Web não é válido."
        }
        if let d = c.agendaPadrao, !DestinoAgenda.tipos.contains(d.tipo) || vazio(d.id) || d.id.count > 200 {
            return "O lugar padrão da agenda não é válido."
        }
        if !["a", "b", "c"].contains(c.comp) { return "A composição da tela deve ser A, B ou C." }
        if !(1024...65535).contains(c.porta) { return "A porta deve estar entre 1024 e 65535." }
        if c.codigoAcesso.count != tamanhoCodigo || !c.codigoAcesso.allSatisfy({ alfabetoCodigo.contains($0) }) {
            return "O código de acesso é inválido."
        }
        if let a = c.codigoAnterior, a.count != tamanhoCodigo || !a.allSatisfy({ alfabetoCodigo.contains($0) }) {
            return "O código de acesso anterior é inválido."
        }
        return nil
    }

    /// A ação de app só existe no tipo "app", com id do catálogo e a escolha no formato que a ação pede.
    private static func validarAcao(_ t: Tecla) -> String? {
        guard let a = t.acao else { return nil }
        if t.tipo != "app" { return "Só tecla de app pode ter ação (\"\(t.nome)\")." }
        if !IdsDeAcao.todos.contains(a.id) { return "A ação da tecla \"\(t.nome)\" não existe." }
        let escolha = (a.valor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch a.id {
        case IdsDeAcao.mailNovo, IdsDeAcao.calendarioHoje:
            return nil
        case IdsDeAcao.link where Enderecos.link(escolha) == nil:
            return "O endereço da tecla \"\(t.nome)\" não é válido."
        case IdsDeAcao.gmail where Enderecos.gmail(escolha) == nil:
            return "A conta do Gmail da tecla \"\(t.nome)\" não é válida."
        case IdsDeAcao.calendarioDia where !Roteador.dataValida(escolha):
            return "O dia da tecla \"\(t.nome)\" não é válido."
        case IdsDeAcao.abrirArquivo where Enderecos.caminho(escolha) == nil:
            return "O caminho da tecla \"\(t.nome)\" precisa começar com / ou ~."
        case IdsDeAcao.mailCaixa where escolha.isEmpty, IdsDeAcao.notasPasta where escolha.isEmpty:
            return "A tecla \"\(t.nome)\" está sem a escolha da ação."
        default:
            return nil
        }
    }

    /// O perfil vira nome de pasta em ~/.config/claude-account: só letras, números, "_", "-" e "."
    /// no meio, para nunca sair dessa pasta com "../".
    private static func perfilDeContaValido(_ p: String) -> Bool {
        guard !p.isEmpty, !p.hasPrefix(".") else { return false }
        return p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) }
    }

    private static func vazio(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
