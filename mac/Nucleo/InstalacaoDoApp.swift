import Foundation

// O app do iPhone diz ao Mac quem o instalou e até quando ele vale, lido do próprio perfil de provisionamento
// (embedded.mobileprovision). Com isso o Mac sabe se a cópia que está no aparelho é a do Deck ou a de outro app
// (SideStore, que renova por conta própria), e não tenta renovar nem avisa à toa. O espelho do que o iPhone manda
// é ios/Pacote/Sources/DeckCasca/InstalacaoDoApp.swift: mudou aqui, muda lá.

/// POST /api/app/instalacao. `venceEm` é a ExpirationDate do perfil, em ISO 8601.
struct InstalacaoDoApp: Codable, Equatable, Sendable {
    var versao: String?
    var bundleId: String?
    var equipe: String?
    var venceEm: Date?

    /// Corpo da rota. nil quando não é JSON do app ou algum texto passa do razoável.
    static func decodificar(_ corpo: Data) -> InstalacaoDoApp? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let i = try? dec.decode(InstalacaoDoApp.self, from: corpo) else { return nil }
        for texto in [i.versao, i.bundleId, i.equipe] { if (texto?.count ?? 0) > 100 { return nil } }
        return i
    }
}

enum MotivoDeInstalacaoExterna: Equatable, Sendable {
    case outroPacote
    case outraEquipe
    case vencimentoNaoBate
}

enum OrigemDaInstalacao: Equatable, Sendable {
    /// O iPhone ainda não informou nada (app antigo): vale o comportamento de sempre, o Deck cuida.
    case desconhecida
    case deck
    case externa(MotivoDeInstalacaoExterna)

    var externa: Bool { if case .externa = self { return true }; return false }
}

enum DeteccaoDaInstalacao {
    /// A Apple faz o perfil da conta grátis valer 7 dias.
    static let validade: TimeInterval = 7 * 86_400
    /// Quanto o vencimento real pode passar do esperado (instalação do Deck mais 7 dias) antes de dizer que outro app instalou depois.
    static let folga: TimeInterval = 86_400

    /// Quem instalou a cópia que está no iPhone.
    /// - `equipeDoDeck`: o DEVELOPMENT_TEAM do projeto do iPhone (nil quando o Mac não achou o projeto).
    /// - `instaladoEm`: a última instalação feita pelo Deck (renovação ou script).
    /// Só vale externa quando há sinal claro: pacote ou equipe diferentes, ou vencimento real bem DEPOIS do que a
    /// instalação do Deck daria. Vencimento mais cedo que o esperado não conta: é um perfil velho reaproveitado numa
    /// instalação do Deck, e aí a renovação do Deck é justamente o que precisa rodar.
    static func detectar(informada: InstalacaoDoApp?, pacoteDoDeck: String, equipeDoDeck: String?, instaladoEm: Date?) -> OrigemDaInstalacao {
        guard let i = informada, i.bundleId != nil || i.equipe != nil || i.venceEm != nil else { return .desconhecida }
        if let pacote = i.bundleId, pacote != pacoteDoDeck { return .externa(.outroPacote) }
        if let equipe = i.equipe, let esperada = equipeDoDeck, equipe != esperada { return .externa(.outraEquipe) }
        if let vence = i.venceEm, let feita = instaladoEm, vence > feita.addingTimeInterval(validade + folga) { return .externa(.vencimentoNaoBate) }
        return .deck
    }

    /// `DEVELOPMENT_TEAM` do project.yml do iPhone ("DEVELOPMENT_TEAM: ABC123" ou entre aspas).
    static func equipe(doProjeto yml: String) -> String? {
        for linha in yml.split(whereSeparator: \.isNewline) {
            let l = linha.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("DEVELOPMENT_TEAM:") else { continue }
            let valor = l.dropFirst("DEVELOPMENT_TEAM:".count).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            return valor.isEmpty ? nil : valor
        }
        return nil
    }
}

/// O cartão amarelo de Conexões, a linha do menu e o selo da barra lateral.
enum CartaoDaRenovacao: Equatable, Sendable {
    /// Instalado pelo Deck e a renovação dele não deu certo a tempo.
    case falhou(venceEm: Date)
    /// Instalado por outro app e o prazo real está perto: quem renova é ele.
    case externa(venceEm: Date)

    var venceEm: Date {
        switch self { case .falhou(let d), .externa(let d): return d }
    }

    /// Quanto falta (menos de 2 dias) para o cartão de instalação externa aparecer.
    static let antecedenciaDaExterna: TimeInterval = 2 * 86_400

    /// `venceEmDoDeck`: o vencimento quando a renovação do Deck está apertando (nil se não está).
    static func para(origem: OrigemDaInstalacao, venceEmDoDeck: Date?, venceReal: Date?, agora: Date) -> CartaoDaRenovacao? {
        if origem.externa {
            guard let v = venceReal, v.timeIntervalSince(agora) < antecedenciaDaExterna else { return nil }
            return .externa(venceEm: v)
        }
        return venceEmDoDeck.map { .falhou(venceEm: $0) }
    }
}
