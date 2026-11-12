import Foundation

// Tela de fábrica do Mail no iPhone (SPEC, seção 5): as últimas mensagens da caixa de entrada de uma conta, lidas e
// não lidas, com a troca de conta no topo. As contas são as que já estão no app Mail do Mac (sem login). Só leitura:
// o Deck nunca marca como lida, nunca apaga e nunca escreve. Nenhum texto vindo do iPhone entra no script: a conta e
// o limite vão como argumentos separados (`on run argv`), e a mensagem a abrir vira um endereço `message://` montado aqui.

struct ContaMail: Codable, Equatable, Sendable {
    /// O id da conta no Mail (o mesmo que a ação "caixa de entrada de uma conta" da tecla usa).
    var id: String
    var nome: String
    /// O primeiro endereço de e-mail da conta, quando o Mail informa.
    var email: String? = nil
}

struct MensagemMail: Codable, Equatable, Sendable {
    /// O cabeçalho Message-ID, sem os < >. Serve para abrir a mensagem no Mail.
    var id: String
    var remetente: String
    var assunto: String
    /// Começo do texto, em uma linha só.
    var previa: String
    /// ISO 8601 do recebimento.
    var data: String
    var lida: Bool
}

/// O corpo de GET /api/mail.
struct CaixaDeMail: Codable, Equatable, Sendable {
    /// "ok", "fechado" (o Mail não está aberto no Mac), "sem-permissao" (Automação negada) ou "erro".
    var estado: String
    /// Em português, quando o estado não é "ok".
    var aviso: String? = nil
    var contas: [ContaMail] = []
    /// O id da conta que está na lista. Vazio quando não há conta lida.
    var conta: String = ""
    /// As mais novas primeiro.
    var mensagens: [MensagemMail] = []
}

protocol ProvedorDeMail: Sendable {
    /// `conta` nil: a primeira conta do Mail. Nunca lança: falha vira estado e aviso.
    func caixa(conta: String?) -> CaixaDeMail
    /// Abre a mensagem no Mail do Mac. Devolve o erro em texto, ou nil se deu certo.
    func abrir(id: String) -> String?
}

extension AppleScript {
    /// Só a lista de contas, sem abrir caixa nenhuma: serve para a troca de conta continuar na tela quando a leitura falha.
    static let listaDeContasDoMail = [
        "set f to (ASCII character 31)",
        "set r to (ASCII character 30)",
        "set saida to \"\"",
        #"tell application id "com.apple.mail""#,
        "repeat with c in accounts",
        "set e to \"\"",
        "try",
        "set e to item 1 of (email addresses of c)",
        "end try",
        "set saida to saida & \"C\" & f & (id of c) & f & (name of c) & f & e & r",
        "end repeat",
        "end tell",
        "return saida",
    ]

    /// Separadores que não aparecem em e-mail: campo (US, 31) e registro (RS, 30). Assim assunto e prévia
    /// podem ter tab e quebra de linha sem estragar a leitura.
    static let campoMail = "\u{1F}"
    static let registroMail = "\u{1E}"

    /// argv: id da conta ("" é a primeira, e conta que não existe mais cai nela) e quantas mensagens ler.
    /// Escreve só texto de saída, nunca no Mail.
    static let caixaDeEntradaDoMail = [
        "on run argv",
        "set f to (ASCII character 31)",
        "set r to (ASCII character 30)",
        "set conta to item 1 of argv",
        "set limite to (item 2 of argv) as integer",
        "set saida to \"\"",
        #"tell application id "com.apple.mail""#,
        "set todas to accounts",
        "repeat with c in todas",
        "set e to \"\"",
        "try",
        "set e to item 1 of (email addresses of c)",
        "end try",
        "set saida to saida & \"C\" & f & (id of c) & f & (name of c) & f & e & r",
        "end repeat",
        "if (count of todas) is 0 then return saida",
        "set alvo to item 1 of todas",
        "if conta is not \"\" then",
        "try",
        "set alvo to account id conta",
        "end try",
        "end if",
        "set caixa to missing value",
        "try",
        #"set caixa to mailbox "INBOX" of alvo"#,
        "end try",
        "if caixa is missing value then",
        "try",
        #"set caixa to mailbox "Inbox" of alvo"#,
        "end try",
        "end if",
        "set saida to saida & \"A\" & f & (id of alvo) & r",
        "if caixa is missing value then return saida",
        "set n to count of messages of caixa",
        "if n > limite then set n to limite",
        "if n > 0 then",
        "set lista to messages 1 thru n of caixa",
        "repeat with m in lista",
        "try",
        "set d to date received of m",
        "set quando to (year of d as string) & \"-\" & ((month of d) as integer as string) & \"-\" & (day of d as string) & \" \" & (hours of d as string) & \":\" & (minutes of d as string) & \":\" & (seconds of d as string)",
        "set lida to \"0\"",
        "if read status of m then set lida to \"1\"",
        "set p to \"\"",
        "try",
        "set p to content of m",
        "if (length of p) > 300 then set p to text 1 thru 300 of p",
        "end try",
        "set saida to saida & \"M\" & f & (message id of m) & f & (sender of m) & f & (subject of m) & f & quando & f & lida & f & p & r",
        "end try",
        "end repeat",
        "end if",
        "end tell",
        "return saida",
        "end run",
    ]
}

/// A leitura real, por AppleScript do Mail, com tempo limite e um cache curto. Nunca abre o Mail: fechado, devolve o
/// aviso "Abra o Mail no Mac" (abrir escondido a cada leitura do iPhone seria um app subindo sozinho a cada 4 s).
final class LeitorDeMail: ProvedorDeMail, @unchecked Sendable {
    static let limiteSegundos = 10
    static let quantas = 20
    static let validade: TimeInterval = 20
    static let avisoFechado = "Abra o Mail no Mac para ver as mensagens aqui."

    static let validadeFalha: TimeInterval = 10
    static let limiteContasSegundos = 3

    private let executor: any Executor
    private let agora: @Sendable () -> Date
    private let validade: TimeInterval
    private let validadeFalha: TimeInterval
    /// Guarda só o cache e as contas conhecidas, por um instante. Nunca fica presa durante o osascript.
    private let trava = NSLock()
    /// Uma leitura de cada vez: quem chega com outra já em andamento espera e, ao pegar a vez, acha o resultado no cache
    /// (inclusive o de falha) em vez de rodar o osascript de novo.
    private let leitura = NSLock()
    private var cache: [String: (em: Date, caixa: CaixaDeMail)] = [:]
    private var contasConhecidas: [ContaMail] = []

    init(executor: any Executor = ExecutorShell(), agora: @escaping @Sendable () -> Date = { Date() },
         validade: TimeInterval = LeitorDeMail.validade, validadeFalha: TimeInterval = LeitorDeMail.validadeFalha) {
        self.executor = executor
        self.agora = agora
        self.validade = validade
        self.validadeFalha = validadeFalha
    }

    private func guardado(_ chave: String) -> CaixaDeMail? {
        trava.lock(); defer { trava.unlock() }
        guard let c = cache[chave] else { return nil }
        let limite = c.caixa.estado == "ok" ? validade : validadeFalha
        return agora().timeIntervalSince(c.em) < limite ? c.caixa : nil
    }

    func caixa(conta: String?) -> CaixaDeMail {
        let chave = conta ?? ""
        if let c = guardado(chave) { return c }
        leitura.lock(); defer { leitura.unlock() }
        if let c = guardado(chave) { return c }
        let nova = ler(chave)
        trava.lock(); defer { trava.unlock() }
        if nova.estado == "ok" {
            cache[chave] = (agora(), nova)
            if !nova.contas.isEmpty { contasConhecidas = nova.contas }
        } else if nova.estado == "erro" { cache[chave] = (agora(), nova) } // o iPhone relê a cada 4 s: sem isso cada leitura lenta vira outra de 10 s
        else { cache[chave] = nil }
        return nova
    }

    /// Falha com a troca de conta junto: sem ela o iPhone esconde o seletor e a conta que falha vira beco sem saída.
    private func falha(_ estado: String, _ aviso: String, conta: String) -> CaixaDeMail {
        trava.lock(); var contas = contasConhecidas; trava.unlock()
        if contas.isEmpty, estado == "erro", let osa = AppleScript.comando(AppleScript.listaDeContasDoMail, argumentos: [], segundos: Self.limiteContasSegundos) {
            let r = executor.rodar(osa)
            if r.status == 0 { contas = Self.interpretar(r.saida).contas }
        }
        let alvo = contas.contains { $0.id == conta } ? conta : (contas.first?.id ?? "")
        return CaixaDeMail(estado: estado, aviso: aviso, contas: contas, conta: alvo)
    }

    private func ler(_ conta: String) -> CaixaDeMail {
        guard executor.rodar("pgrep -x 'Mail' >/dev/null").status == 0 else {
            return CaixaDeMail(estado: "fechado", aviso: Self.avisoFechado)
        }
        guard let osa = AppleScript.comando(AppleScript.caixaDeEntradaDoMail, argumentos: [conta, String(Self.quantas)],
                                            segundos: Self.limiteSegundos) else {
            return CaixaDeMail(estado: "erro", aviso: "Essa conta do Mail não é válida.")
        }
        let r = executor.rodar(osa)
        if r.status != 0 {
            let semPermissao = r.saida.contains("-1743")
            return falha(semPermissao ? "sem-permissao" : "erro", Self.motivo(r), conta: conta)
        }
        let lido = Self.interpretar(r.saida)
        guard !lido.contas.isEmpty else {
            return CaixaDeMail(estado: "ok", aviso: "Nenhuma conta configurada no Mail. Adicione uma conta no app Mail.")
        }
        return CaixaDeMail(estado: "ok", contas: lido.contas, conta: lido.conta, mensagens: lido.mensagens)
    }

    static func motivo(_ r: SaidaShell) -> String {
        if r.status == ExecutorAcoes.statusTempoEsgotado {
            return "O Mail demorou demais para responder. Tente de novo em instantes."
        }
        if r.saida.contains("-1743") {
            return "O Deck não tem permissão para controlar o Mail. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação."
        }
        return "Não consegui ler o Mail."
    }

    // MARK: Leitura da saída do script

    static func interpretar(_ saida: String, fuso: TimeZone = .current) -> (contas: [ContaMail], conta: String, mensagens: [MensagemMail]) {
        var contas: [ContaMail] = [], conta = "", mensagens: [MensagemMail] = []
        for registro in saida.components(separatedBy: AppleScript.registroMail) {
            let c = registro.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: AppleScript.campoMail)
            switch c.first {
            case "C" where c.count >= 3 && !c[1].isEmpty:
                let e = c.count > 3 ? c[3].trimmingCharacters(in: .whitespaces) : ""
                contas.append(ContaMail(id: c[1], nome: c[2].isEmpty ? (e.isEmpty ? "Conta" : e) : c[2], email: e.isEmpty ? nil : e))
            case "A" where c.count >= 2: conta = c[1]
            case "M" where c.count >= 7:
                guard let id = idLimpo(c[1]), let data = data(c[4], fuso: fuso) else { continue }
                mensagens.append(MensagemMail(id: id, remetente: remetente(c[2]), assunto: assunto(c[3]), previa: previa(c[6]),
                                              data: Datas.iso(data, fuso: fuso), lida: c[5] == "1"))
            default: break
            }
        }
        mensagens.sort { $0.data > $1.data } // texto ISO do mesmo fuso ordena como o tempo
        return (contas, conta, mensagens)
    }

    /// Tudo em uma linha, sem espaço sobrando.
    static func umaLinha(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "Ana Souza <ana@x.com>", "\"Ana\" <ana@x.com>" ou só "ana@x.com": fica o nome, ou o endereço sem nome.
    static func remetente(_ bruto: String) -> String {
        let t = umaLinha(bruto)
        var nome = t
        if let i = t.firstIndex(of: "<") { nome = String(t[..<i]) }
        nome = nome.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
        if !nome.isEmpty { return nome }
        let endereco = t.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        return endereco.isEmpty ? "Sem remetente" : endereco
    }

    static func assunto(_ bruto: String) -> String {
        let t = umaLinha(bruto)
        return t.isEmpty ? "(sem assunto)" : t
    }

    static func previa(_ bruto: String, maximo: Int = 140) -> String {
        let t = umaLinha(bruto)
        return t.count > maximo ? String(t.prefix(maximo)).trimmingCharacters(in: .whitespaces) + "..." : t
    }

    /// O Message-ID sem os < >. Vazio, comprido demais ou com caractere de controle: a mensagem é descartada.
    static func idLimpo(_ bruto: String) -> String? {
        let t = bruto.trimmingCharacters(in: CharacterSet(charactersIn: "<> ").union(.whitespacesAndNewlines))
        guard !t.isEmpty, t.count <= 400, !t.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return t
    }

    /// "2026-11-12 9:5:3" (ano, mês, dia, hora, minuto, segundo, no relógio do Mac).
    static func data(_ texto: String, fuso: TimeZone) -> Date? {
        let n = texto.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard n.count == 6 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = fuso
        return cal.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4], second: n[5]))
    }

    // MARK: Abrir no Mail

    /// O endereço que o Mail entende: message://%3C<Message-ID>%3E.
    static func enderecoDaMensagem(_ id: String) -> String? {
        guard let limpo = idLimpo(id) else { return nil }
        var ok = CharacterSet.alphanumerics
        ok.insert(charactersIn: "-._~")
        guard let cod = ("<" + limpo + ">").addingPercentEncoding(withAllowedCharacters: ok) else { return nil }
        return "message://" + cod
    }

    func abrir(id: String) -> String? {
        guard let url = Self.enderecoDaMensagem(id) else { return "Essa mensagem não é válida." }
        let r = executor.rodar("open -b 'com.apple.mail' " + Shell.aspas(url))
        return r.status == 0 ? nil : "Não consegui abrir a mensagem no Mail."
    }
}
