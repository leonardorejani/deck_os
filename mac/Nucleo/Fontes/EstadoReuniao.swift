import Foundation

// O estado do microfone e da câmera da reunião, para a tecla mostrar "mutado" ou "ligado" como a tecla do Manter acordado
// mostra aceso (SPEC, seção 13, item 35). Só leitura, sempre via Executor e com tempo limite. Nada é pedido em lista de
// cara: a Automação do navegador e a do System Events são pedidas pelo macOS na hora da primeira leitura (invariante 12).
//
// - Meet no navegador: a Acessibilidade (MeetAcessibilidade.swift) lê os botões "Desativar microfone" e "Ativar câmera"
//   da aba que está na frente, sem a pessoa ligar nada no navegador. Reserva: JavaScript na aba da sala por AppleScript,
//   lendo o `data-is-muted`, que exige a opção Permitir JavaScript de Eventos da Apple no navegador. Sem nenhum dos dois, "?".
// - Zoom e Teams: os itens do menu do app ("Mute audio" / "Unmute audio", "Start video" / "Stop video"), lidos pelo System
//   Events com a Acessibilidade que o Deck já tem. O título do item diz o que o próximo toque faz, então dele sai o estado.

/// O que a tecla de microfone ou de câmera mostra.
enum EstadoDeReuniao: String, Codable, Equatable, Sendable {
    /// Microfone aberto, câmera ligada.
    case ligado
    /// Microfone mutado, câmera desligada.
    case desligado
    /// Há reunião, mas o Deck não conseguiu ler (opção do navegador desligada, sem permissão, app em outro idioma).
    case desconhecido
    /// Nenhuma reunião aberta: a tecla fica apagada.
    case semReuniao = "sem-reuniao"
}

struct LeituraDeReuniao: Equatable, Sendable {
    var microfone: EstadoDeReuniao
    var camera: EstadoDeReuniao
    var aviso: Aviso? = nil

    static let nenhuma = LeituraDeReuniao(microfone: .semReuniao, camera: .semReuniao)
    static func desconhecida(_ aviso: Aviso? = nil) -> LeituraDeReuniao { LeituraDeReuniao(microfone: .desconhecido, camera: .desconhecido, aviso: aviso) }

    func de(_ item: ControleDeReuniao.Item) -> EstadoDeReuniao { item == .microfone ? microfone : camera }
}

enum LeituraDeMeet {
    /// Sem aspas duplas nem barra invertida: vai dentro de uma string do AppleScript. `data-is-muted` é "true" com o
    /// microfone mutado (e com a câmera desligada). O rótulo do botão acha qual é qual, em inglês, português e espanhol.
    static let javascript = "(function(){var b=[].slice.call(document.querySelectorAll('button[data-is-muted]'));"
        + "var f=function(re,fim){for(var i=0;i<b.length;i++){var l=(b[i].getAttribute('aria-label')||'').toLowerCase();"
        + "if(re.test(l)||l.slice(-2)==fim){return b[i].getAttribute('data-is-muted')}}return '?'};"
        + "return 'mic='+f(/micro/,'d)')+';cam='+f(/c.mera|c.mara|cam.ra/,'e)')})()"

    /// Cada linha é "endereço<TAB>resultado" das abas do Meet. O resultado é "mic=false;cam=true" ou "erro:<motivo>".
    static func comando(_ n: NavegadorWeb) -> String {
        let executar = n.estilo == .safari
            ? #"set v to (do JavaScript "\#(javascript)" in t)"#
            : #"set v to (execute t javascript "\#(javascript)")"#
        let linhas = [
            "set sep to (ASCII character 9)",
            #"tell application id "\#(n.idBundle)""#,
            #"set r to """#,
            "repeat with i from 1 to count of windows",
            "repeat with j from 1 to count of tabs of window i",
            "try",
            "set t to tab j of window i",
            "set u to (URL of t as text)",
            #"if u starts with "https://meet.google.com/" then"#,
            "try",
            executar,
            "on error m",
            #"set v to "erro:" & m"#,
            "end try",
            "set r to r & u & sep & v & linefeed",
            "end if",
            "end try",
            "end repeat",
            "end repeat",
            "return r",
            "end tell",
        ]
        let osa = "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
        // `pgrep` primeiro: consultar um navegador fechado o abriria.
        return Shell.limitado("if pgrep -x \(Shell.aspas(n.processo)) >/dev/null; then \(osa); else echo fechado; fi", segundos: WhatsAppWeb.limiteSegundos)
    }

    static func ler(_ n: NavegadorWeb, executor: any Executor) -> Resultado {
        let r = executor.rodar(comando(n))
        return interpretar(status: r.status, saida: r.saida, navegador: n)
    }

    enum Resultado: Equatable, Sendable {
        case fechado
        /// O navegador está aberto e não há sala do Meet nele.
        case semSala
        case sala(LeituraDeReuniao)
        /// O navegador não deixou ler: falta a permissão da Automação.
        case semPermissao
        /// A opção de JavaScript por Apple Events está desligada no navegador.
        case javascriptDesligado
        case falhou
    }

    static func interpretar(status: Int32, saida: String, navegador: NavegadorWeb) -> Resultado {
        let texto = saida.trimmingCharacters(in: .whitespacesAndNewlines)
        let baixo = texto.lowercased()
        if status != 0 {
            if baixo.contains("-1743") || baixo.contains("not authorized") || baixo.contains("not allowed") { return .semPermissao }
            return .falhou
        }
        if texto == "fechado" { return .fechado }
        var viuSala = false, jsDesligado = false, semPermissao = false
        for linha in saida.split(whereSeparator: \.isNewline) {
            let c = linha.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard c.count == 2, ControleDeReuniao.ehSalaDoMeet(String(c[0])) else { continue }
            viuSala = true
            let valor = String(c[1])
            if valor.hasPrefix("erro:") {
                let m = valor.lowercased()
                if m.contains("javascript") || m.contains("apple events") { jsDesligado = true }
                else if m.contains("-1743") || m.contains("not authorized") { semPermissao = true }
                continue
            }
            return .sala(lerEstados(valor))
        }
        if jsDesligado { return .javascriptDesligado }
        if semPermissao { return .semPermissao }
        return viuSala ? .sala(.desconhecida()) : .semSala
    }

    /// "mic=true;cam=false" -> microfone desligado (mutado), câmera ligada. "?" ou lixo: desconhecido.
    static func lerEstados(_ valor: String) -> LeituraDeReuniao {
        var mic = EstadoDeReuniao.desconhecido, cam = EstadoDeReuniao.desconhecido
        for par in valor.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ";") {
            let kv = par.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            // `data-is-muted` = "true" quer dizer que o aparelho está desligado.
            let e: EstadoDeReuniao = kv[1] == "true" ? .desligado : kv[1] == "false" ? .ligado : .desconhecido
            if kv[0] == "mic" { mic = e } else if kv[0] == "cam" { cam = e }
        }
        return LeituraDeReuniao(microfone: mic, camera: cam)
    }

    static let avisoJavascript = Aviso(fonte: "reuniao", texto: "Não consegui ler o microfone do Meet. Deixe a aba da reunião na frente do navegador e libere a Acessibilidade para o Deck. Sem isso a tecla mostra \"?\".")
    static func avisoPermissao(_ navegador: String) -> Aviso {
        Aviso(fonte: "reuniao", texto: "Não consegui olhar o \(navegador). Libere o controle dele para o Deck em Ajustes do Mac, Privacidade e Segurança, Automação.")
    }
}

/// O menu do Zoom e do Teams: o título de cada item diz o que o próximo toque faz.
enum LeituraDeMenu {
    /// O que um título de menu diz sobre o microfone ou a câmera: qual dos dois e se o aparelho está ligado agora.
    struct Item: Equatable, Sendable { var item: ControleDeReuniao.Item; var ligado: Bool }

    static func normalizar(_ titulo: String) -> String {
        var t = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let u = t.last, u == "." || u == "…" { t.removeLast() }
        return t
    }

    private static func tem(_ texto: String, _ padrao: String) -> Bool { texto.range(of: padrao, options: .regularExpression) != nil }

    /// "Mute audio" -> microfone ligado. "Unmute audio" -> microfone mutado. "Start video" -> câmera desligada.
    /// "Mute All" e afins (que valem para os outros) e títulos que não falam de microfone nem de câmera dão nil.
    static func classificar(_ titulo: String) -> Item? {
        let t = normalizar(titulo)
        if tem(t, #"(^| )(all|todos|todas|everyone|participants?|participantes?|others|outros)( |$)"#) { return nil }
        // O verbo do item é a ação: "ativar" liga, "desativar" desliga. O aparelho está no estado oposto ao da ação.
        let ligaAoTocar = tem(t, #"(^| )(unmute|turn( [a-z]+)? on|start|iniciar|ativar|reativar|ligar|activar|encender|dessilenciar)( |$)"#)
        let desligaAoTocar = tem(t, #"(^| )(mute|turn( [a-z]+)? off|stop|parar|desativar|desligar|silenciar|desactivar|apagar)( |$)"#)
        guard ligaAoTocar != desligaAoTocar else { return nil }
        let soMute = tem(t, #"^(un)?mute$|^(des)?silenciar$|^dessilenciar$"#)
        let item: ControleDeReuniao.Item
        if tem(t, #"(^| )(audio|microphone|microfone|microfono|mic|sonido)( |$)"#) || soMute { item = .microfone }
        else if tem(t, #"(^| )(video|camera|webcam|cam)( |$)"#) { item = .camera }
        else { return nil }
        return Item(item: item, ligado: desligaAoTocar)
    }

    /// Uma janela que parece de reunião (para saber que há reunião mesmo quando os itens do menu não são entendidos).
    static func janelaDeReuniao(_ nome: String) -> Bool {
        tem(normalizar(nome), #"meeting|reuniao|reunion|webinar|call|chamada|llamada"#)
    }

    /// Saída do script: os títulos dos itens de menu, uma linha "---" e os nomes das janelas.
    static func interpretar(_ saida: String) -> LeituraDeReuniao {
        var itens: [String] = [], janelas: [String] = []
        var naJanelas = false
        for linha in saida.split(whereSeparator: \.isNewline).map(String.init) {
            if linha == "---" { naJanelas = true; continue }
            if naJanelas { janelas.append(linha) } else { itens.append(linha) }
        }
        var mic: Bool?, cam: Bool?
        for titulo in itens {
            guard let c = classificar(titulo) else { continue }
            if c.item == .microfone, mic == nil { mic = c.ligado }
            if c.item == .camera, cam == nil { cam = c.ligado }
        }
        if mic == nil, cam == nil {
            // Menu sem os itens da reunião. Com janela de reunião aberta, o Deck não entendeu o app (outro idioma, versão nova).
            return janelas.contains(where: janelaDeReuniao) ? .desconhecida() : .nenhuma
        }
        func e(_ b: Bool?) -> EstadoDeReuniao { b.map { $0 ? .ligado : .desligado } ?? .desconhecido }
        return LeituraDeReuniao(microfone: e(mic), camera: e(cam))
    }

    /// Fixo: só o nome do processo (constante do Deck) entra no script.
    static func comando(processo: String) -> String {
        let linhas = [
            #"tell application "System Events""#,
            #"tell process "\#(processo)""#,
            "set itens to name of every menu item of every menu of menu bar 1",
            "set janelas to name of every window",
            "end tell",
            "end tell",
            #"set r to """#,
            "repeat with sub in itens",
            "repeat with n in sub",
            "set s to contents of n",
            "if s is not missing value then set r to r & s & linefeed",
            "end repeat",
            "end repeat",
            #"set r to r & "---" & linefeed"#,
            "repeat with n in janelas",
            "set s to contents of n",
            "if s is not missing value then set r to r & s & linefeed",
            "end repeat",
            "return r",
        ]
        let osa = "osascript " + linhas.map { "-e " + Shell.aspas($0) }.joined(separator: " ")
        return Shell.limitado(osa, segundos: WhatsAppWeb.limiteSegundos)
    }

    static let avisoPermissao = Aviso(fonte: "reuniao", texto: "Não consegui olhar o menu do app da reunião. Libere o Deck em Ajustes do Mac, Privacidade e Segurança, Acessibilidade e Automação (System Events).")
}

/// Lê o estado de uma reunião no Meet, no Zoom ou no Teams.
struct LeitorDeReuniao: Sendable {
    var executor: any Executor
    /// A árvore de acessibilidade dos navegadores, para ler o Meet sem a opção de JavaScript. Nil: só o Mac de verdade tem
    /// (com executor falso, de teste, não se consulta o sistema).
    var acessibilidade: (any AcessibilidadeDoNavegador)? = nil
    var temAcessibilidade: @Sendable () -> Bool = { AcoesSistema.temAcessibilidade() }

    private var ax: (any AcessibilidadeDoNavegador)? { acessibilidade ?? AcessibilidadePadrao.para(executor) }

    /// Nomes de processo de cada app (o Teams novo e o clássico).
    static func processos(_ alvo: ControleDeReuniao.Alvo) -> [String] {
        switch alvo {
        case .zoom: return ["zoom.us"]
        case .teams: return ["MSTeams", "Microsoft Teams"]
        case .meet, .meetNoNavegador: return []
        }
    }

    func ler(_ alvo: ControleDeReuniao.Alvo) -> LeituraDeReuniao {
        switch alvo {
        case .meet(let n): return lerMeet([n])
        case .meetNoNavegador: return lerMeet(NavegadorWeb.todos)
        case .zoom, .teams: return lerApp(Self.processos(alvo))
        }
    }

    /// O Meet como a Acessibilidade vê, no primeiro navegador que mostra uma sala na frente. Nil: não achou por aqui.
    func salaDoMeet(_ navegadores: [NavegadorWeb]) -> SalaMeet? {
        guard let ax else { return nil }
        for n in navegadores {
            if case .sala(let s) = LeitorDeMeetAX.ler(n, executor: executor, ax: ax, confiavel: temAcessibilidade()) { return s }
        }
        return nil
    }

    func lerMeet(_ navegadores: [NavegadorWeb]) -> LeituraDeReuniao {
        // Primeiro a Acessibilidade (não pede nada ao usuário). O JavaScript do navegador fica de reserva.
        if let sala = salaDoMeet(navegadores) { return sala.leitura }
        var problema: LeituraDeReuniao?
        for n in navegadores {
            switch LeituraDeMeet.ler(n, executor: executor) {
            case .fechado, .semSala, .falhou: continue
            case .sala(let l): return l
            case .javascriptDesligado: problema = problema ?? .desconhecida(LeituraDeMeet.avisoJavascript)
            case .semPermissao: problema = problema ?? .desconhecida(LeituraDeMeet.avisoPermissao(n.nome))
            }
        }
        return problema ?? .nenhuma
    }

    private func lerApp(_ processos: [String]) -> LeituraDeReuniao {
        for p in processos {
            guard executor.rodar("pgrep -x \(Shell.aspas(p)) >/dev/null").status == 0 else { continue }
            let r = executor.rodar(LeituraDeMenu.comando(processo: p))
            guard r.status == 0 else { return .desconhecida(LeituraDeMenu.avisoPermissao) }
            return LeituraDeMenu.interpretar(r.saida)
        }
        // App fechado: não há reunião nele.
        return .nenhuma
    }

    /// O estado de cada tecla de microfone ou de câmera da reunião. Lê uma vez por app, não por tecla.
    func ler(_ teclas: [Tecla]) -> Leitura<[String: EstadoDeReuniao]> {
        var lidas: [(alvo: ControleDeReuniao.Alvo, leitura: LeituraDeReuniao)] = []
        var estados: [String: EstadoDeReuniao] = [:]
        var aviso: Aviso?
        for t in teclas {
            guard let item = Self.item(da: t), let alvo = ControleDeReuniao.alvo(app: t.valor) else { continue }
            let l = lidas.first { $0.alvo == alvo }?.leitura ?? { let l = ler(alvo); lidas.append((alvo, l)); return l }()
            estados[t.id] = l.de(item)
            aviso = aviso ?? l.aviso
        }
        return Leitura(valor: estados, aviso: aviso)
    }

    /// A tecla é de microfone ou de câmera da reunião?
    static func item(da t: Tecla) -> ControleDeReuniao.Item? {
        guard t.tipo == "app" else { return nil }
        switch t.acao?.id {
        case IdsDeAcao.reuniaoMicrofone: return .microfone
        case IdsDeAcao.reuniaoCamera: return .camera
        default: return nil
        }
    }
}
