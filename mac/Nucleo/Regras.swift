import Foundation

// Regras automáticas "quando isto, então aquilo" (SPEC, seção 13, item 40). O Mac avalia as regras a cada pedido de
// estado (o painel pede de 1 em 1 s) e entrega no Estado só as que estão valendo agora (`Estado.regras`). Quem troca de
// tela, de composição ou de perfil é o painel do iPhone, depois de uma contagem regressiva de 3 s com "Ficar" e
// "Ir agora", e nunca enquanto a pessoa está tocando na tela. O Mac só decide quando e o quê.

// MARK: - Config

/// O que faz a regra disparar. `limite` só vale na fonte "uso" (percentual da semana).
struct Gatilho: Codable, Equatable, Sendable {
    var fonte: String
    var limite: Int? = nil

    /// Fontes que o Mac já lê hoje, na ordem em que o editor mostra.
    static let fontes = ["sessao", "meet", "spotify", "uso", "aviso", "horario"]

    static func rotulo(_ fonte: String) -> String {
        switch fonte {
        case "sessao": return "Uma sessão pede você"
        case "meet": return "O Meet está em chamada"
        case "spotify": return "O Spotify está tocando"
        case "uso": return "O uso das IAs passa de um limite"
        case "aviso": return "Chega uma mensagem nova"
        case "horario": return "Chega o horário"
        default: return fonte
        }
    }
}

/// O que a regra faz. `tipo` "tela" (alvo em `AcaoDeRegra.telas`), "composicao" (a, b ou c), "perfil" (id do perfil)
/// ou "aviso" (o alvo é o texto que o iPhone mostra).
struct AcaoDeRegra: Codable, Equatable, Sendable {
    var tipo: String
    var alvo: String

    static let tipos = ["tela", "composicao", "perfil", "aviso"]
    static let telas = ["sessoes", "meet", "whatsapp", "calendario", "controles", "monitor", "uso", "player", "inicio"]
    static let composicoes = ["a", "b", "c"]

    static func rotuloDoTipo(_ tipo: String) -> String {
        switch tipo {
        case "tela": return "Ir para uma tela"
        case "composicao": return "Trocar a composição"
        case "perfil": return "Trocar de perfil"
        case "aviso": return "Mostrar um aviso"
        default: return tipo
        }
    }

    /// O alvo com que o editor começa quando a pessoa troca o tipo da ação.
    static func alvoPadrao(tipo: String, perfis: [Perfil]) -> String {
        switch tipo {
        case "tela": return "sessoes"
        case "composicao": return "a"
        case "perfil": return perfis.first?.id ?? ""
        default: return ""
        }
    }

    static func nomeDaTela(_ tela: String) -> String {
        switch tela {
        case "sessoes": return "Sessões"
        case "meet": return "Meet"
        case "whatsapp": return "WhatsApp"
        case "calendario": return "Agenda"
        case "controles": return "Controles do Mac"
        case "monitor": return "Monitor"
        case "uso": return "Uso das IAs"
        case "player": return "Player"
        case "inicio": return "Início"
        default: return tela
        }
    }

    static func nomeDaComposicao(_ c: String) -> String {
        switch c {
        case "a": return "Relógio em cima"
        case "c": return "Relógio e mês"
        default: return "Deck 3 x 3"
        }
    }
}

/// Uma regra da lista. `dias` vazio vale todos os dias (0 domingo a 6 sábado) e `de`/`ate` ("HH:mm") vazios valem o dia todo.
struct Regra: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    var ligada: Bool = false
    var quando: Gatilho
    var entao: AcaoDeRegra
    var dias: [Int] = []
    var de: String? = nil
    var ate: String? = nil
    /// Desfaz a ação quando a condição acaba (com folga de 4 s para não piscar).
    var enquantoDurar: Bool = false
    /// Minutos sem disparar de novo depois de disparar.
    var descanso: Int = 5
    /// Maior vence quando duas regras valem ao mesmo tempo.
    var prioridade: Int = 5

    static let descansoMaximo = 1440
    static let nomeMaximo = 60
    static let avisoMaximo = 120
    /// A contagem que o iPhone mostra antes de trocar sozinho.
    static let segundosDeAviso = 3
    /// Folga depois que a condição acaba, antes de desfazer.
    static let histerese: TimeInterval = 4

    /// As duas de exemplo, desligadas. Quem nunca mexeu nas regras começa com elas.
    static let exemplos: [Regra] = [
        Regra(id: "exemplo-sessao", nome: "Sessão pede você: ir para Sessões", ligada: false,
              quando: Gatilho(fonte: "sessao"), entao: AcaoDeRegra(tipo: "tela", alvo: "sessoes"), enquantoDurar: false, descanso: 5, prioridade: 5),
        Regra(id: "exemplo-meet", nome: "Meet em chamada: ir para o Meet", ligada: false,
              quando: Gatilho(fonte: "meet"), entao: AcaoDeRegra(tipo: "tela", alvo: "meet"), enquantoDurar: true, descanso: 5, prioridade: 5),
    ]

    /// Uma regra em branco para o editor, com id que não repete e a condição e a ação mais comuns.
    static func nova(entre existentes: [Regra]) -> Regra {
        let ids = Set(existentes.map(\.id))
        var n = existentes.count + 1
        while ids.contains("regra-\(n)") { n += 1 }
        return Regra(id: "regra-\(n)", nome: "Nova regra", ligada: false, quando: Gatilho(fonte: "sessao"), entao: AcaoDeRegra(tipo: "tela", alvo: "sessoes"))
    }

    /// O que o Mac diz ao apertar Testar.
    static func avisoDoTeste(iphoneAoVivo: Bool) -> String {
        iphoneAoVivo ? "Teste enviado ao iPhone" : "Nenhum iPhone ligado agora. O teste vale por \(Int(MotorDeRegras.duracaoDoTeste)) segundos"
    }

    /// Opções do descanso no editor, em minutos.
    static let opcoesDeDescanso = [0, 1, 5, 15, 30, 60, 120]

    static func rotuloDoDescanso(_ min: Int) -> String {
        if min == 0 { return "Sem descanso" }
        if min % 60 == 0 { return "\(min / 60) h" }
        return "\(min) min"
    }

    /// Inicial de cada dia, de domingo (0) a sábado (6), e o nome inteiro para a leitura de tela.
    static let diasCurtos = ["D", "S", "T", "Q", "Q", "S", "S"]
    static let diasPorExtenso = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    static func horaValida(_ s: String) -> Bool { minutos(s) != nil }

    /// "HH:mm" em minutos desde a meia-noite, ou nil se não for uma hora de verdade.
    static func minutos(_ s: String) -> Int? {
        let p = s.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, p[0].count == 2, p[1].count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Uma frase só, para a lista dos Ajustes: "Quando uma sessão pede você, ir para Sessões".
    func resumo(perfis: [Perfil] = []) -> String {
        var f = "Quando " + quandoEmFrase() + ", " + entaoEmFrase(perfis: perfis)
        if let j = janelaEmFrase() { f += " (" + j + ")" }
        return f
    }

    func quandoEmFrase() -> String {
        switch quando.fonte {
        case "sessao": return "uma sessão pede você"
        case "meet": return "o Meet estiver em chamada"
        case "spotify": return "o Spotify estiver tocando"
        case "uso": return "o uso das IAs passar de \(quando.limite ?? 90)%"
        case "aviso": return "chegar uma mensagem nova"
        case "horario": return "chegar o horário"
        default: return quando.fonte
        }
    }

    func entaoEmFrase(perfis: [Perfil] = []) -> String {
        switch entao.tipo {
        case "tela": return "ir para " + AcaoDeRegra.nomeDaTela(entao.alvo)
        case "composicao": return "trocar para " + AcaoDeRegra.nomeDaComposicao(entao.alvo)
        case "perfil": return "trocar para o perfil " + (perfis.first { $0.id == entao.alvo }?.nome ?? entao.alvo)
        case "aviso": return "avisar \"" + entao.alvo + "\""
        default: return entao.tipo
        }
    }

    func janelaEmFrase() -> String? {
        let nomes = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        var partes: [String] = []
        let dd = Set(dias).filter { (0...6).contains($0) }.sorted()
        if !dd.isEmpty && dd.count < 7 { partes.append(dd.map { nomes[$0] }.joined(separator: ", ")) }
        if let de, let ate { partes.append("\(de) às \(ate)") }
        return partes.isEmpty ? nil : partes.joined(separator: ", ")
    }

    /// A frase do cartão do iPhone, antes da contagem: "Indo para Sessões".
    func fraseDoCartao(perfis: [Perfil] = []) -> String {
        switch entao.tipo {
        case "tela": return "Indo para " + AcaoDeRegra.nomeDaTela(entao.alvo)
        case "composicao": return "Trocando para " + AcaoDeRegra.nomeDaComposicao(entao.alvo)
        case "perfil": return "Trocando para o perfil " + (perfis.first { $0.id == entao.alvo }?.nome ?? entao.alvo)
        default: return entao.alvo
        }
    }
}

extension Regra {
    private enum Chave: String, CodingKey { case id, nome, ligada, quando, entao, dias, de, ate, enquantoDurar, descanso, prioridade }

    /// Leitura tolerante: o que falta volta para o padrão (desligada, 5 min de descanso, prioridade 5).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Chave.self)
        self.init(id: try c.decode(String.self, forKey: .id), nome: try c.decode(String.self, forKey: .nome),
                  ligada: (try? c.decodeIfPresent(Bool.self, forKey: .ligada)) ?? false,
                  quando: try c.decode(Gatilho.self, forKey: .quando), entao: try c.decode(AcaoDeRegra.self, forKey: .entao),
                  dias: (try? c.decodeIfPresent([Int].self, forKey: .dias)) ?? [],
                  de: (try? c.decodeIfPresent(String.self, forKey: .de)) ?? nil, ate: (try? c.decodeIfPresent(String.self, forKey: .ate)) ?? nil,
                  enquantoDurar: (try? c.decodeIfPresent(Bool.self, forKey: .enquantoDurar)) ?? false,
                  descanso: (try? c.decodeIfPresent(Int.self, forKey: .descanso)) ?? 5,
                  prioridade: (try? c.decodeIfPresent(Int.self, forKey: .prioridade)) ?? 5)
    }
}

/// Lê a lista de regras sem deixar uma regra quebrada (de uma versão futura) derrubar a config: ela só some da lista.
struct ListaDeRegras: Decodable {
    var regras: [Regra]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var r: [Regra] = []
        while !c.isAtEnd {
            if let uma = try? c.decode(Regra.self) { r.append(uma) } else { _ = try? c.decode(Pulo.self) }
        }
        regras = r
    }
    private struct Pulo: Decodable {}
}

extension Config {
    /// Texto em português para a regra inválida, ou nil. Perfil que não existe mais não é erro aqui: a regra só fica parada.
    static func validarRegras(_ regras: [Regra]) -> String? {
        var ids = Set<String>()
        for r in regras {
            let nome = r.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ids.insert(r.id).inserted { return "Há regras repetidas ou sem identificador." }
            if nome.isEmpty { return "Toda regra precisa de um nome." }
            if nome.count > Regra.nomeMaximo { return "O nome da regra \"\(nome.prefix(20))...\" é grande demais." }
            if !Gatilho.fontes.contains(r.quando.fonte) { return "A condição da regra \"\(nome)\" não é válida." }
            if r.quando.fonte == "uso", !(1...100).contains(r.quando.limite ?? 0) { return "O limite de uso da regra \"\(nome)\" precisa ficar entre 1 e 100." }
            switch r.entao.tipo {
            case "tela": if !AcaoDeRegra.telas.contains(r.entao.alvo) { return "A tela da regra \"\(nome)\" não existe." }
            case "composicao": if !AcaoDeRegra.composicoes.contains(r.entao.alvo) { return "A composição da regra \"\(nome)\" não existe." }
            case "perfil": if r.entao.alvo.isEmpty { return "A regra \"\(nome)\" está sem perfil." }
            case "aviso":
                let t = r.entao.alvo.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { return "A regra \"\(nome)\" está sem o texto do aviso." }
                if t.count > Regra.avisoMaximo { return "O aviso da regra \"\(nome)\" é grande demais." }
            default: return "A ação da regra \"\(nome)\" não é válida."
            }
            if r.dias.contains(where: { !(0...6).contains($0) }) { return "Os dias da regra \"\(nome)\" não são válidos." }
            if let de = r.de, !Regra.horaValida(de) { return "A hora de início da regra \"\(nome)\" não é válida." }
            if let ate = r.ate, !Regra.horaValida(ate) { return "A hora de fim da regra \"\(nome)\" não é válida." }
            if (r.de == nil) != (r.ate == nil) { return "A regra \"\(nome)\" precisa das duas horas, ou de nenhuma." }
            if r.quando.fonte == "horario", r.de == nil { return "A regra \"\(nome)\" precisa de um horário." }
            if !(0...Regra.descansoMaximo).contains(r.descanso) { return "O descanso da regra \"\(nome)\" não é válido." }
            if !(1...9).contains(r.prioridade) { return "A prioridade da regra \"\(nome)\" precisa ficar entre 1 e 9." }
        }
        return nil
    }
}

// MARK: - O que vai no Estado

/// Uma regra que está valendo agora. O iPhone trata cada `seq` uma vez só: mostra a contagem, troca ou fica, e some do
/// controle dele quando a regra deixa de vir na lista (a condição acabou, com 4 s de folga).
struct RegraAtiva: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    /// Muda a cada disparo novo da mesma regra.
    var seq: Int
    /// "tela", "composicao", "perfil" ou "aviso".
    var tipo: String
    var alvo: String
    /// A frase do cartão ("Indo para Sessões") ou, no aviso, o texto dele.
    var texto: String
    /// Desfaz quando a regra deixa de valer.
    var durar: Bool
    /// A contagem antes de trocar.
    var segundos: Int
}

// MARK: - O motor

/// O que o motor olha a cada avaliação.
struct EntradaDeRegras: Sendable {
    var agora: Date
    var sessoes: Int
    /// Já dentro de uma chamada do Meet. Quem monta a entrada só lê o Meet (custa) quando alguma regra ligada o usa.
    var meetEmChamada: Bool = false
    var spotifyTocando: Bool
    /// O maior percentual da semana entre as contas medidas. nil sem medição.
    var usoMaximo: Int?
    /// Total de não lidas do WhatsApp. nil sem leitura.
    var naoLidas: Int?
}

struct MotorDeRegras: Sendable {
    private struct Situacao {
        var ativa = false
        var cessouEm: Date?
        var suprimida = false
        var seq = 0
        var ultimoDisparo: Date?
    }

    private var situacoes: [String: Situacao] = [:]
    private var ultimaSeq = 0
    private var naoLidasAntes: Int?
    private var chegouEm: Date?
    private var testes: [String: Date] = [:]
    var calendario: Calendar

    /// Quanto tempo a mensagem nova vale como "chegou uma mensagem".
    static let validadeDoAviso: TimeInterval = 30
    /// Quanto tempo um teste dos Ajustes fica valendo no iPhone.
    static let duracaoDoTeste: TimeInterval = 15

    init(calendario: Calendar = .current) { self.calendario = calendario }

    /// Dispara a regra agora, sem olhar condição, horário, descanso nem a pausa (o botão Testar dos Ajustes).
    mutating func testar(_ id: String, agora: Date) {
        testes = testes.filter { $0.value > agora }
        testes[id] = agora.addingTimeInterval(Self.duracaoDoTeste)
    }

    mutating func avaliar(_ e: EntradaDeRegras, regras: [Regra], perfis: [Perfil], pausada: Bool) -> [RegraAtiva] {
        let ids = Set(regras.map(\.id))
        situacoes = situacoes.filter { ids.contains($0.key) }
        testes = testes.filter { $0.value > e.agora }

        // "Mensagem nova": o total de não lidas subiu desde a última olhada. Vale por 30 s.
        if let total = e.naoLidas {
            if let antes = naoLidasAntes, total > antes { chegouEm = e.agora }
            naoLidasAntes = total
        }
        let mensagemNova = chegouEm.map { e.agora.timeIntervalSince($0) < Self.validadeDoAviso } ?? false

        var valendo: [(indice: Int, regra: Regra, seq: Int)] = []
        for (i, r) in regras.enumerated() {
            var s = situacoes[r.id] ?? Situacao()
            let teste = testes[r.id] != nil
            let possivel = Self.acaoPossivel(r, perfis: perfis)
            var condicao = false
            if possivel, r.ligada, !pausada, dentroDaJanela(r, e.agora) {
                switch r.quando.fonte {
                case "sessao": condicao = e.sessoes > 0
                case "meet": condicao = e.meetEmChamada
                case "spotify": condicao = e.spotifyTocando
                case "uso": condicao = (e.usoMaximo ?? -1) >= (r.quando.limite ?? 101)
                case "aviso": condicao = mensagemNova
                case "horario": condicao = true
                default: condicao = false
                }
            }
            if (condicao && possivel) || teste {
                s.cessouEm = nil
                if !s.ativa {
                    s.ativa = true
                    let emDescanso = s.ultimoDisparo.map { e.agora.timeIntervalSince($0) < Double(r.descanso) * 60 } ?? false
                    s.suprimida = emDescanso && !teste
                    if !s.suprimida {
                        ultimaSeq = max(ultimaSeq + 1, Int(e.agora.timeIntervalSince1970 * 1000))
                        s.seq = ultimaSeq
                        s.ultimoDisparo = e.agora
                    }
                }
            } else if s.ativa {
                if s.cessouEm == nil { s.cessouEm = e.agora }
                if let c = s.cessouEm, e.agora.timeIntervalSince(c) >= Regra.histerese {
                    s.ativa = false; s.suprimida = false; s.cessouEm = nil
                }
            }
            situacoes[r.id] = s
            if s.ativa && !s.suprimida { valendo.append((i, r, s.seq)) }
        }
        valendo.sort { $0.regra.prioridade != $1.regra.prioridade ? $0.regra.prioridade > $1.regra.prioridade : $0.indice < $1.indice }
        return valendo.map { v in
            RegraAtiva(id: v.regra.id, nome: v.regra.nome, seq: v.seq, tipo: v.regra.entao.tipo, alvo: v.regra.entao.alvo,
                       texto: v.regra.fraseDoCartao(perfis: perfis), durar: v.regra.enquantoDurar, segundos: Regra.segundosDeAviso)
        }
    }

    /// Regra que aponta para um perfil que não existe mais fica parada, sem derrubar nada.
    private static func acaoPossivel(_ r: Regra, perfis: [Perfil]) -> Bool {
        r.entao.tipo != "perfil" || perfis.contains { $0.id == r.entao.alvo }
    }

    private func dentroDaJanela(_ r: Regra, _ agora: Date) -> Bool {
        if !r.dias.isEmpty, !r.dias.contains(calendario.component(.weekday, from: agora) - 1) { return false }
        guard let de = r.de.flatMap(Regra.minutos), let ate = r.ate.flatMap(Regra.minutos) else { return true }
        let c = calendario.dateComponents([.hour, .minute], from: agora)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if de == ate { return true }
        return de < ate ? (m >= de && m < ate) : (m >= de || m < ate)
    }
}

// MARK: - Quem usa o motor no servidor

/// O motor com trava, para o roteador (que atende pedidos de vários fios) e os Ajustes (o botão Testar) falarem com o mesmo.
final class VigiaDeRegras: @unchecked Sendable {
    private let trava = NSLock()
    private var motor: MotorDeRegras
    private var meetLido: (valor: Bool, em: Date)?

    /// A leitura do Meet custa (Acessibilidade): vale por 3 s.
    static let validadeDoMeet: TimeInterval = 3

    init(calendario: Calendar = .current) { motor = MotorDeRegras(calendario: calendario) }

    func testar(_ id: String, agora: Date = Date()) {
        trava.lock(); defer { trava.unlock() }
        motor.testar(id, agora: agora)
    }

    /// As regras valendo agora para este estado. Só lê o Meet se alguma regra ligada o usa, e fora da trava.
    func avaliar(estado: Estado, config: Config, agora: Date = Date(), meet: (any MeetDoMac)?) -> [RegraAtiva] {
        let usaMeet = !config.regrasPausadas && config.regras.contains { $0.ligada && $0.quando.fonte == "meet" }
        let emChamada = usaMeet ? lerMeet(meet, agora) : false
        let entrada = EntradaDeRegras(
            agora: agora, sessoes: estado.sessoes.count, meetEmChamada: emChamada, spotifyTocando: estado.spotify?.tocando ?? false,
            usoMaximo: estado.uso.compactMap(\.semana).max(), naoLidas: estado.whatsapp?.total)
        trava.lock(); defer { trava.unlock() }
        return motor.avaliar(entrada, regras: config.regras, perfis: config.perfis, pausada: config.regrasPausadas)
    }

    private func lerMeet(_ meet: (any MeetDoMac)?, _ agora: Date) -> Bool {
        trava.lock()
        if let l = meetLido, agora >= l.em, agora.timeIntervalSince(l.em) < Self.validadeDoMeet { trava.unlock(); return l.valor }
        trava.unlock()
        let v = meet?.estado().naChamada ?? false
        trava.lock(); meetLido = (v, agora); trava.unlock()
        return v
    }
}
