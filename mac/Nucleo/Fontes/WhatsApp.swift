import Foundation

struct WhatsAppDados: Equatable, Sendable {
    var resumo: ResumoWhatsApp
    var conversas: [ConversaWhatsApp]
}

/// Não lidas do WhatsApp, lidas do banco local do app do Mac (`ChatStorage.sqlite`) pelo `sqlite3`
/// em modo só leitura, sempre via Executor. O WhatsApp pode mudar o esquema numa atualização, então
/// qualquer coisa estranha vira Aviso e o resto do painel continua.
struct FonteWhatsApp: Sendable {
    var executor: any Executor
    var banco: String

    static func caminhoPadrao(casa: String) -> String {
        casa + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
    }

    /// Segundos entre 1970 (Unix) e 2001 (a data zero do Core Data, que o WhatsApp usa).
    static let epocaCoreData: TimeInterval = 978_307_200

    // Só conversa de contato (0), grupo (1) e grupo de comunidade (4). Fora ficam o Status (3,
    // 217 "não lidas" neste Mac que não são conversa) e os Canais (5). Arquivadas, escondidas e
    // removidas também ficam fora. ZUNREADCOUNT = -1 é "marcada como não lida" à mão.
    static let consultaConversas = """
    select Z_PK as id, ZPARTNERNAME as nome, ZSESSIONTYPE as tipo, ZUNREADCOUNT as nao, \
    ZLASTMESSAGEDATE as ultima, ZCONTACTJID as jid from ZWACHATSESSION \
    where ZUNREADCOUNT <> 0 and ZARCHIVED = 0 and ZHIDDEN = 0 and ZREMOVED = 0 \
    and ZSESSIONTYPE in (0, 1, 4) order by ZLASTMESSAGEDATE desc
    """

    /// As mensagens recebidas mais novas de cada conversa (até 50), sem as de sistema (tipo 6).
    /// O nome de quem mandou vem do membro do grupo, ou do nome que a pessoa se deu no WhatsApp.
    static func consultaMensagens(ids: [Int]) -> String {
        let lista = ids.map(String.init).joined(separator: ", ")
        return """
        select cid, d, t, ty, de from (select m.ZCHATSESSION as cid, m.ZMESSAGEDATE as d, m.ZTEXT as t, \
        m.ZMESSAGETYPE as ty, case when length(g.ZCONTACTNAME) > 0 then g.ZCONTACTNAME \
        when length(g.ZFIRSTNAME) > 0 then g.ZFIRSTNAME when length(m.ZPUSHNAME) > 0 then m.ZPUSHNAME end as de, \
        row_number() over (partition by m.ZCHATSESSION order by m.ZMESSAGEDATE desc) as rn \
        from ZWAMESSAGE m left join ZWAGROUPMEMBER g on g.Z_PK = m.ZGROUPMEMBER \
        where m.ZISFROMME = 0 and m.ZMESSAGETYPE <> 6 and m.ZCHATSESSION in (\(lista))) where rn <= 50 order by cid, d
        """
    }

    struct LinhaConversa: Decodable, Equatable {
        var id: Int
        var nome: String?
        var tipo: Int
        var nao: Int
        var ultima: Double?
        var jid: String?
    }

    struct LinhaMensagem: Decodable, Equatable {
        var cid: Int
        var d: Double?
        var t: String?
        var ty: Int?
        var de: String?
    }

    static func parseConversas(_ json: String) -> [LinhaConversa]? { decodificar(json) }
    static func parseMensagens(_ json: String) -> [LinhaMensagem]? { decodificar(json) }

    /// `sqlite3 -json` não imprime nada quando não há linhas, e isso é uma lista vazia, não erro.
    private static func decodificar<T: Decodable>(_ json: String) -> [T]? {
        let t = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [] }
        return try? JSONDecoder().decode([T].self, from: Data(t.utf8))
    }

    /// Mensagem sem texto (foto, áudio...) aparece pelo tipo. Códigos do WhatsApp para Mac, do
    /// conhecimento do esquema e conferidos só pela contagem neste Mac, sem ler conteúdo.
    static func rotulo(tipo: Int?) -> String {
        switch tipo {
        case 1: return "Foto"
        case 2: return "Vídeo"
        case 3: return "Áudio"
        case 4: return "Contato"
        case 5: return "Localização"
        case 8: return "Documento"
        case 11: return "GIF"
        case 14: return "Mensagem apagada"
        case 15: return "Figurinha"
        default: return "Mensagem"
        }
    }

    static func montar(conversas: [LinhaConversa], mensagens: [LinhaMensagem]) -> WhatsAppDados {
        let porConversa = Dictionary(grouping: mensagens, by: { $0.cid })
        func hora(_ d: Double?) -> String {
            guard let d else { return "" }
            return Datas.iso(Date(timeIntervalSince1970: d + epocaCoreData), fuso: TimeZone(identifier: "UTC")!)
        }
        var total = 0
        let saida = conversas.map { c -> ConversaWhatsApp in
            let grupo = c.tipo != 0 || (c.jid ?? "").hasSuffix("@g.us")
            let naoLidas = max(1, c.nao)
            total += naoLidas
            // As mensagens vêm da mais antiga para a mais nova. As não lidas são as últimas.
            let recentes = (porConversa[c.id] ?? []).suffix(naoLidas)
            let msgs = recentes.map { m -> MensagemWhatsApp in
                let texto = (m.t ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return MensagemWhatsApp(
                    de: grupo ? (m.de ?? "") : "",
                    texto: texto.isEmpty ? rotulo(tipo: m.ty) : texto,
                    hora: hora(m.d)
                )
            }
            let nome = (c.nome ?? "").trimmingCharacters(in: .whitespaces)
            return ConversaWhatsApp(id: String(c.id), nome: nome.isEmpty ? (grupo ? "Grupo" : "Contato") : nome,
                                    grupo: grupo, naoLidas: naoLidas, ultima: hora(c.ultima), mensagens: msgs)
        }
        return WhatsAppDados(resumo: ResumoWhatsApp(total: total, conversas: saida.count), conversas: saida)
    }

    /// Texto do aviso para a falha do sqlite3. Sem Acesso Total ao Disco o macOS recusa a abertura.
    static func aviso(status: Int32, saida: String) -> Aviso {
        let s = saida.lowercased()
        if s.contains("authorization denied") || s.contains("not permitted") || s.contains("unable to open")
            || s.contains("permission denied") || s.contains("not authorized") {
            return Aviso(fonte: "whatsapp", texto: "Não consegui abrir o banco do WhatsApp. Libere o Acesso Total ao Disco para o Deck nos Ajustes do Mac e confira se o WhatsApp está instalado.")
        }
        return Aviso(fonte: "whatsapp", texto: "Não consegui ler as conversas do WhatsApp. Uma atualização do app pode ter mudado o formato.")
    }

    func ler() -> Leitura<WhatsAppDados?> {
        let base = "sqlite3 -readonly -json \(Shell.aspas(banco)) "
        let c = executor.rodar(base + Shell.aspas(Self.consultaConversas))
        guard c.status == 0 else { return Leitura(valor: nil, aviso: Self.aviso(status: c.status, saida: c.saida)) }
        guard let conversas = Self.parseConversas(c.saida) else {
            return Leitura(valor: nil, aviso: Self.aviso(status: 0, saida: ""))
        }
        if conversas.isEmpty {
            return Leitura(valor: WhatsAppDados(resumo: ResumoWhatsApp(total: 0, conversas: 0), conversas: []), aviso: nil)
        }
        let m = executor.rodar(base + Shell.aspas(Self.consultaMensagens(ids: conversas.map(\.id))))
        guard m.status == 0, let mensagens = Self.parseMensagens(m.saida) else {
            return Leitura(valor: nil, aviso: Self.aviso(status: m.status, saida: m.status == 0 ? "" : m.saida))
        }
        return Leitura(valor: Self.montar(conversas: conversas, mensagens: mensagens), aviso: nil)
    }
}
