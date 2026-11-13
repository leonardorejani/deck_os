import Foundation
#if canImport(EventKit) && canImport(CoreGraphics)
import EventKit
import CoreGraphics
#endif

// Criar um compromisso pelo iPhone (POST /api/agenda/criar). O Mac grava no Calendário ou no app Lembretes,
// pelo EventKit, que aparece em todos os aparelhos da conta. A conversa com o EventKit fica atrás de
// `CriadorDeAgenda`: os testes usam um falso e a validação (tudo que vem do iPhone) é daqui, sem a Apple no meio.

/// Onde o compromisso vai: um calendário ou uma lista do app Lembretes.
struct DestinoAgenda: Codable, Equatable, Hashable, Sendable {
    /// "calendario" ou "lembretes".
    var tipo: String
    /// Identificador do calendário ou da lista no EventKit.
    var id: String

    static let tipos = ["calendario", "lembretes"]

    /// "O calendário padrão do Mac": o id é este texto em vez de um calendário. Vira o calendário de verdade na hora de
    /// salvar, então acompanha o que a pessoa escolher no app Calendário.
    static let idDoPadraoDoMac = "padrao-do-mac"
    static let padraoDoMac = DestinoAgenda(tipo: "calendario", id: idDoPadraoDoMac)
    var ehPadraoDoMac: Bool { tipo == "calendario" && id == Self.idDoPadraoDoMac }
}

struct OpcaoDeDestino: Codable, Equatable, Sendable {
    var id: String
    var nome: String
    /// "#rrggbb".
    var cor: String
    /// A conta de onde vem (iCloud, Google...), para duas listas com o mesmo nome não se confundirem.
    var conta: String?
}

/// O que o iPhone pode escolher em "Onde salvar", mais o padrão e o estado da permissão de cada app.
struct DestinosDaAgenda: Codable, Equatable, Sendable {
    var calendarios: [OpcaoDeDestino]
    var listas: [OpcaoDeDestino]
    /// "liberado", "pedir" (ainda não perguntado), "pedindo" (a janela do macOS está aberta no Mac) ou "recusado".
    var permissaoCalendario: String
    var permissaoLembretes: String
    var padrao: DestinoAgenda?
}

struct ErroAgenda: Error, Equatable, Sendable {
    var status: Int
    var texto: String
}

/// O compromisso já validado.
struct NovoCompromisso: Equatable, Sendable {
    var titulo: String
    /// AAAA-MM-DD.
    var dia: String
    /// HH:MM. Nil no dia todo.
    var inicio: String?
    /// HH:MM. Nil no dia todo.
    var fim: String?
    var diaTodo: Bool
    var destino: DestinoAgenda
    /// Minutos de antecedência do alerta. Nil: sem alerta. No dia todo conta a partir das 9h do dia.
    var alertaMin: Int?
    /// Guardar o destino como padrão (config `agendaPadrao`).
    var definirPadrao: Bool

    static let alertasValidos: Set<Int> = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080]
    static let tamanhoMaximoDoTitulo = 200
    /// Hora do alerta de um compromisso de dia todo.
    static let horaDoAlertaDeDiaTodo = 9

    /// Lê o corpo do POST. Sem `destino` vale o padrão da config, e sem os dois é erro.
    static func ler(corpo: Data, padrao: DestinoAgenda?) -> Result<NovoCompromisso, ErroAgenda> {
        func erro(_ t: String) -> Result<NovoCompromisso, ErroAgenda> { .failure(ErroAgenda(status: 400, texto: t)) }
        guard let obj = (try? JSONSerialization.jsonObject(with: corpo)) as? [String: Any] else {
            return erro("Não entendi o compromisso enviado.")
        }
        let titulo = (obj["titulo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if titulo.isEmpty { return erro("Dê um título ao compromisso.") }
        if titulo.count > tamanhoMaximoDoTitulo { return erro("O título pode ter até \(tamanhoMaximoDoTitulo) letras.") }
        if titulo.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return erro("O título tem um caractere que não pode.")
        }
        guard let dia = obj["dia"] as? String, Roteador.dataValida(dia), (2000...2100).contains(Int(dia.prefix(4)) ?? 0) else {
            return erro("Informe o dia no formato AAAA-MM-DD.")
        }
        var diaTodo = false
        if let v = obj["diaTodo"] {
            guard let b = v as? Bool else { return erro("O campo dia todo deve ser verdadeiro ou falso.") }
            diaTodo = b
        }
        var inicio: String?, fim: String?
        if !diaTodo {
            guard let i = obj["inicio"] as? String, let mi = minutos(i) else { return erro("Informe a hora de início, por exemplo 14:30.") }
            inicio = i
            if let f = obj["fim"] as? String, !f.isEmpty {
                guard let mf = minutos(f) else { return erro("Informe a hora do fim, por exemplo 15:30.") }
                if mf <= mi { return erro("O fim precisa ser depois do início.") }
                fim = f
            }
        }
        var alerta: Int?
        if let v = obj["alertaMin"], !(v is NSNull) {
            guard let n = v as? Int, alertasValidos.contains(n) else {
                return erro("Esse alerta não existe.")
            }
            alerta = n
        }
        var destino = padrao
        if let d = obj["destino"] as? [String: Any] {
            guard let tipo = d["tipo"] as? String, DestinoAgenda.tipos.contains(tipo),
                  let id = d["id"] as? String, !id.isEmpty, id.count <= 200,
                  !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                return erro("Escolha um calendário ou uma lista dos Lembretes.")
            }
            destino = DestinoAgenda(tipo: tipo, id: id)
        }
        guard let destino else { return erro("Escolha onde salvar: um calendário ou uma lista dos Lembretes.") }
        var padraoPedido = false
        if let v = obj["padrao"] {
            guard let b = v as? Bool else { return erro("O campo padrão deve ser verdadeiro ou falso.") }
            padraoPedido = b
        }
        return .success(NovoCompromisso(titulo: titulo, dia: dia, inicio: inicio, fim: fim, diaTodo: diaTodo,
                                        destino: destino, alertaMin: alerta, definirPadrao: padraoPedido))
    }

    /// "HH:MM" (24 h, dois dígitos) em minutos desde a meia-noite.
    static func minutos(_ texto: String) -> Int? {
        let p = texto.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, p[0].count == 2, p[1].count == 2, p.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
              let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    private static func calendario(_ fuso: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = fuso
        return c
    }

    private func data(hora: Int, minuto: Int, _ c: Calendar) -> Date? {
        let p = dia.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return c.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hora, minute: minuto))
    }

    /// Início e fim reais. Dia todo: da meia-noite até 23:59:59 do mesmo dia (como o app Calendário grava).
    /// Sem fim, dura uma hora. Nil se a hora não existe no fuso (a hora pulada pelo horário de verão).
    func datas(fuso: TimeZone = .current) -> (inicio: Date, fim: Date)? {
        let c = Self.calendario(fuso)
        if diaTodo {
            guard let i = data(hora: 0, minuto: 0, c) else { return nil }
            return (i, i.addingTimeInterval(24 * 3600 - 1))
        }
        guard let mi = inicio.flatMap(Self.minutos), let i = data(hora: mi / 60, minuto: mi % 60, c) else { return nil }
        // A hora tem de ser a mesma depois de montada: no salto do horário de verão o Calendar empurra para a frente.
        guard c.component(.hour, from: i) == mi / 60 else { return nil }
        if let mf = fim.flatMap(Self.minutos) {
            guard let f = data(hora: mf / 60, minuto: mf % 60, c), c.component(.hour, from: f) == mf / 60 else { return nil }
            return (i, f)
        }
        return (i, i.addingTimeInterval(3600))
    }

    /// Quando o alerta toca, como data. Vale para o lembrete, que não tem alarme relativo.
    func dataDoAlerta(fuso: TimeZone = .current) -> Date? {
        guard let alertaMin, let d = datas(fuso: fuso) else { return nil }
        if diaTodo {
            let c = Self.calendario(fuso)
            guard let nove = c.date(byAdding: .hour, value: Self.horaDoAlertaDeDiaTodo, to: d.inicio) else { return nil }
            return nove.addingTimeInterval(-Double(alertaMin) * 60)
        }
        return d.inicio.addingTimeInterval(-Double(alertaMin) * 60)
    }

    /// O mesmo alerta, em segundos a partir do início do evento (negativo = antes). No evento o Calendário
    /// mostra "15 minutos antes" e o alerta acompanha o horário se a pessoa mudar o evento depois.
    func deslocamentoDoAlerta(fuso: TimeZone = .current) -> TimeInterval? {
        guard let a = dataDoAlerta(fuso: fuso), let d = datas(fuso: fuso) else { return nil }
        return a.timeIntervalSince(d.inicio)
    }
}

/// Quem grava no Calendário e nos Lembretes.
protocol CriadorDeAgenda: Sendable {
    /// Os calendários e listas que aceitam gravar. `pedirPermissao`: se o acesso aos Lembretes ainda não foi
    /// perguntado, abre a janela do macOS no Mac (o iPhone só pede quando a pessoa escolhe Lembretes).
    func destinos(pedirPermissao: Bool) -> DestinosDaAgenda
    func criar(_ novo: NovoCompromisso) -> Result<Void, ErroAgenda>
    /// O id do calendário padrão do Mac (o que o app Calendário usa para evento novo). Nil sem acesso ou sem calendário.
    func idDoCalendarioPadrao() -> String?
}

extension CriadorDeAgenda {
    func idDoCalendarioPadrao() -> String? { nil }
}

#if canImport(EventKit) && canImport(CoreGraphics)
/// O EventKit de verdade. Só no macOS.
struct CriadorEventKit: CriadorDeAgenda {
    /// A loja que pergunta a permissão fica viva até a pessoa responder.
    private nonisolated(unsafe) static let lojaDosPedidos = EKEventStore()

    static func permissao(_ tipo: EKEntityType) -> String {
        // Pelo número, como em FonteAgenda.temPermissao: 3 é "autorizado" (acesso total no macOS 14 em diante).
        switch EKEventStore.authorizationStatus(for: tipo).rawValue {
        case 3: return "liberado"
        case 0: return "pedir"
        default: return "recusado"
        }
    }

    static func pedir(_ tipo: EKEntityType) {
        let loja = lojaDosPedidos
        if #available(macOS 14.0, *) {
            if tipo == .reminder { loja.requestFullAccessToReminders { _, _ in } } else { loja.requestFullAccessToEvents { _, _ in } }
        } else {
            loja.requestAccess(to: tipo) { _, _ in }
        }
    }

    static func opcao(_ c: EKCalendar) -> OpcaoDeDestino {
        var rgb: (r: Double, g: Double, b: Double) = (0.5, 0.5, 0.5)
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB), let k = c.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components, k.count >= 3 {
            rgb = (Double(k[0]), Double(k[1]), Double(k[2]))
        }
        return OpcaoDeDestino(id: c.calendarIdentifier, nome: c.title, cor: Cor.hex(r: rgb.r, g: rgb.g, b: rgb.b), conta: c.source?.title)
    }

    private static func gravaveis(_ loja: EKEventStore, _ tipo: EKEntityType) -> [OpcaoDeDestino] {
        loja.calendars(for: tipo)
            .filter { $0.allowsContentModifications && !$0.isImmutable }
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
            .map(opcao)
    }

    func destinos(pedirPermissao: Bool) -> DestinosDaAgenda {
        var cal = Self.permissao(.event), lem = Self.permissao(.reminder)
        if pedirPermissao {
            if cal == "pedir" { Self.pedir(.event); cal = "pedindo" }
            if lem == "pedir" { Self.pedir(.reminder); lem = "pedindo" }
        }
        let loja = EKEventStore()
        return DestinosDaAgenda(calendarios: cal == "liberado" ? Self.gravaveis(loja, .event) : [],
                                listas: lem == "liberado" ? Self.gravaveis(loja, .reminder) : [],
                                permissaoCalendario: cal, permissaoLembretes: lem, padrao: nil)
    }

    func idDoCalendarioPadrao() -> String? {
        guard Self.permissao(.event) == "liberado" else { return nil }
        return EKEventStore().defaultCalendarForNewEvents?.calendarIdentifier
    }

    func criar(_ novo: NovoCompromisso) -> Result<Void, ErroAgenda> {
        guard let datas = novo.datas(), !(novo.alertaMin != nil && novo.dataDoAlerta() == nil) else {
            return .failure(ErroAgenda(status: 400, texto: "Essa hora não existe nesse dia."))
        }
        let ehLembrete = novo.destino.tipo == "lembretes"
        let tipo: EKEntityType = ehLembrete ? .reminder : .event
        switch Self.permissao(tipo) {
        case "liberado": break
        case "pedir":
            Self.pedir(tipo)
            return .failure(ErroAgenda(status: 409, texto: "Libere \(ehLembrete ? "os Lembretes" : "o Calendário") na janela que abriu no Mac e tente de novo."))
        default:
            return .failure(ErroAgenda(status: 409, texto: "O Deck está sem acesso a\(ehLembrete ? "os Lembretes" : "o Calendário"). No Mac: Ajustes do Sistema > Privacidade."))
        }
        let loja = EKEventStore()
        guard let destino = loja.calendar(withIdentifier: novo.destino.id), destino.allowsContentModifications,
              destino.allowedEntityTypes.contains(ehLembrete ? .reminder : .event) else {
            return .failure(ErroAgenda(status: 422, texto: "Esse lugar não existe mais ou não aceita compromissos. Escolha outro."))
        }
        do {
            if ehLembrete {
                let r = EKReminder(eventStore: loja)
                r.title = novo.titulo
                r.calendar = destino
                let c = Calendar.current
                r.dueDateComponents = c.dateComponents(novo.diaTodo ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute], from: datas.inicio)
                if let a = novo.dataDoAlerta() { r.addAlarm(EKAlarm(absoluteDate: a)) }
                try loja.save(r, commit: true)
            } else {
                let e = EKEvent(eventStore: loja)
                e.title = novo.titulo
                e.calendar = destino
                e.isAllDay = novo.diaTodo
                e.startDate = datas.inicio
                e.endDate = datas.fim
                if let o = novo.deslocamentoDoAlerta() { e.addAlarm(EKAlarm(relativeOffset: o)) }
                try loja.save(e, span: .thisEvent, commit: true)
            }
            return .success(())
        } catch {
            return .failure(ErroAgenda(status: 422, texto: "O Mac não conseguiu salvar o compromisso."))
        }
    }
}
#endif
