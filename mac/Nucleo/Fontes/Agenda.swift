import Foundation
#if canImport(EventKit) && canImport(CoreGraphics)
import EventKit
import CoreGraphics
#endif

/// Evento já tirado do EventKit, sem tipo da Apple, para a conversão ser testável no Linux.
struct EventoBruto: Equatable, Sendable {
    var titulo: String
    var inicio: Date
    var fim: Date
    var diaTodo: Bool
    var calendario: String
    /// Componentes do calendário, de 0 a 1.
    var cor: (r: Double, g: Double, b: Double)
    var local: String?
    /// Link de reunião já achado no evento (endereço, local ou notas). Ver `Reuniao.achar`.
    var link: String? = nil

    static func == (a: EventoBruto, b: EventoBruto) -> Bool {
        a.titulo == b.titulo && a.inicio == b.inicio && a.fim == b.fim && a.diaTodo == b.diaTodo
            && a.calendario == b.calendario && a.cor == b.cor && a.local == b.local && a.link == b.link
    }
}

enum Agenda {
    static let diasAdiante = 30

    /// Lembrete do app Lembretes como item da agenda: entra no dia do prazo, com a hora quando tem. Sem prazo não entra.
    static func lembrete(titulo: String, prazo: DateComponents, lista: String,
                         cor: (r: Double, g: Double, b: Double), calendario: Calendar = .current) -> EventoBruto? {
        guard prazo.year != nil, prazo.month != nil, prazo.day != nil else { return nil }
        var c = prazo; c.calendar = calendario; c.timeZone = calendario.timeZone
        let diaTodo = prazo.hour == nil
        if diaTodo { c.hour = 0; c.minute = 0 } else if c.minute == nil { c.minute = 0 }
        guard let inicio = calendario.date(from: c) else { return nil }
        let fim = diaTodo ? inicio.addingTimeInterval(24 * 3600 - 1) : inicio
        return EventoBruto(titulo: titulo, inicio: inicio, fim: fim, diaTodo: diaTodo, calendario: lista, cor: cor, local: nil)
    }

    /// Eventos do Calendário e lembretes numa lista só, na ordem do início.
    static func juntar(_ eventos: [EventoBruto], _ lembretes: [EventoBruto]) -> [EventoBruto] {
        (eventos + lembretes).sorted { $0.inicio < $1.inicio }
    }

    static func converter(_ e: EventoBruto, fuso: TimeZone = .current) -> Evento {
        let local = e.local?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Evento(titulo: e.titulo, inicio: Datas.iso(e.inicio, fuso: fuso), diaTodo: e.diaTodo,
                      calendario: e.calendario, cor: Cor.hex(r: e.cor.r, g: e.cor.g, b: e.cor.b),
                      local: (local?.isEmpty ?? true) ? nil : local, link: e.link, fim: Datas.iso(e.fim, fuso: fuso))
    }

    /// O próximo é o primeiro que ainda não terminou, na ordem do início.
    static func proximo(_ eventos: [EventoBruto], agora: Date) -> EventoBruto? {
        eventos.filter { $0.fim > agora }.min { $0.inicio < $1.inicio }
    }

    static func resumo(permissao: Bool, eventos: [EventoBruto], agora: Date, fuso: TimeZone = .current) -> ResumoAgenda {
        guard permissao else { return ResumoAgenda(permissao: false, proximo: nil) }
        return ResumoAgenda(permissao: true, proximo: proximo(eventos, agora: agora).map { converter($0, fuso: fuso) })
    }
}

/// A leitura real, em cima do EventKit. Só no macOS. Nunca pede a permissão: quem pede é o app
/// (precisa do texto de uso no Info.plist, senão o macOS derruba o processo).
struct FonteAgenda: Sendable {
    var ler: @Sendable (Date) -> Leitura<ResumoAgenda?>
    /// Eventos de um intervalo, para GET /api/agenda.
    var eventos: @Sendable (Date, Int) -> [Evento]

    static func viva() -> FonteAgenda {
        #if canImport(EventKit) && canImport(CoreGraphics)
        return FonteAgenda(
            ler: { agora in
                let loja = EKEventStore()
                guard temPermissao() else { return Leitura(valor: ResumoAgenda(permissao: false, proximo: nil), aviso: nil) }
                let brutos = buscar(loja, de: agora, dias: Agenda.diasAdiante)
                return Leitura(valor: Agenda.resumo(permissao: true, eventos: brutos, agora: agora), aviso: nil)
            },
            eventos: { de, dias in
                let loja = EKEventStore()
                let eventos = temPermissao() ? buscar(loja, de: de, dias: dias) : []
                let lembretes = temPermissaoLembretes() ? buscarLembretes(loja, de: de, dias: dias) : []
                return Agenda.juntar(eventos, lembretes).map { Agenda.converter($0) }
            }
        )
        #else
        return FonteAgenda(
            ler: { _ in Leitura(valor: nil, aviso: Aviso(fonte: "agenda", texto: "A agenda só funciona no Mac.")) },
            eventos: { _, _ in [] }
        )
        #endif
    }

    #if canImport(EventKit) && canImport(CoreGraphics)
    /// 3 é "autorizado" (acesso total no macOS 14 em diante). Pelo número para valer nos dois nomes.
    static func temPermissao() -> Bool {
        EKEventStore.authorizationStatus(for: .event).rawValue == 3
    }

    static func temPermissaoLembretes() -> Bool {
        EKEventStore.authorizationStatus(for: .reminder).rawValue == 3
    }

    /// Lembretes ainda não feitos com prazo no intervalo. A leitura do EventKit é assíncrona: espera até 5 s.
    static func buscarLembretes(_ loja: EKEventStore, de: Date, dias: Int) -> [EventoBruto] {
        let fim = Calendar.current.date(byAdding: .day, value: dias, to: de) ?? de
        let filtro = loja.predicateForIncompleteReminders(withDueDateStarting: de, ending: fim, calendars: nil)
        let achados = CaixaDeLembretes()
        let fila = DispatchSemaphore(value: 0)
        loja.fetchReminders(matching: filtro) { lista in
            achados.guardar(lista?.compactMap(brutoDeLembrete) ?? [])
            fila.signal()
        }
        guard fila.wait(timeout: .now() + 5) == .success else { return [] }
        return achados.todos()
    }

    static func brutoDeLembrete(_ r: EKReminder) -> EventoBruto? {
        var rgb: (r: Double, g: Double, b: Double) = (0.5, 0.5, 0.5)
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
           let c = r.calendar?.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
           let k = c.components, k.count >= 3 {
            rgb = (Double(k[0]), Double(k[1]), Double(k[2]))
        }
        guard let prazo = r.dueDateComponents else { return nil }
        return Agenda.lembrete(titulo: r.title ?? "", prazo: prazo, lista: r.calendar?.title ?? "Lembretes", cor: rgb)
    }

    static func buscar(_ loja: EKEventStore, de: Date, dias: Int) -> [EventoBruto] {
        let fim = Calendar.current.date(byAdding: .day, value: dias, to: de) ?? de
        let filtro = loja.predicateForEvents(withStart: de, end: fim, calendars: nil)
        return loja.events(matching: filtro).map(bruto)
    }

    static func bruto(_ e: EKEvent) -> EventoBruto {
        var rgb: (r: Double, g: Double, b: Double) = (0.5, 0.5, 0.5)
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
           let c = e.calendar?.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
           let k = c.components, k.count >= 3 {
            rgb = (Double(k[0]), Double(k[1]), Double(k[2]))
        }
        return EventoBruto(titulo: e.title ?? "", inicio: e.startDate, fim: e.endDate, diaTodo: e.isAllDay,
                           calendario: e.calendar?.title ?? "", cor: rgb, local: e.location,
                           link: Reuniao.achar(em: [e.url?.absoluteString, e.location, e.notes]))
    }
    #endif
}

#if canImport(EventKit) && canImport(CoreGraphics)
/// Guarda o que o EventKit devolveu em outra fila, com trava.
private final class CaixaDeLembretes: @unchecked Sendable {
    private let trava = NSLock()
    private var lista: [EventoBruto] = []
    func guardar(_ l: [EventoBruto]) { trava.lock(); lista = l; trava.unlock() }
    func todos() -> [EventoBruto] { trava.lock(); defer { trava.unlock() }; return lista }
}
#endif
