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

    static func converter(_ e: EventoBruto, fuso: TimeZone = .current) -> Evento {
        let local = e.local?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Evento(titulo: e.titulo, inicio: Datas.iso(e.inicio, fuso: fuso), diaTodo: e.diaTodo,
                      calendario: e.calendario, cor: Cor.hex(r: e.cor.r, g: e.cor.g, b: e.cor.b),
                      local: (local?.isEmpty ?? true) ? nil : local, link: e.link)
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
                guard temPermissao() else { return [] }
                return buscar(EKEventStore(), de: de, dias: dias).sorted { $0.inicio < $1.inicio }.map { Agenda.converter($0) }
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
