import Foundation

// Renovação do app nativo do iPhone (fase 8). O app instalado com a conta grátis da Apple vence em 7 dias: o Mac
// refaz a instalação a cada 5, pela mesma sequência provada em docs/provas/0.3-0.4-casca-e-renovacao.md (perfil com
// -allowProvisioningUpdates, compilar e reinstalar com devicectl). Aqui não há tela nem relógio de verdade: o
// executor de comandos e o relógio entram de fora, para os testes provarem a agenda e os motivos.

// MARK: - Executor

struct ResultadoDeComando: Equatable, Sendable {
    var status: Int32
    var saida: String
}

protocol ExecutorDeComandos: Sendable {
    /// Roda `executavel` (procurado no PATH) e devolve a saída de texto e o código de saída. Passou do `limite`, mata e devolve 124.
    func rodar(_ executavel: String, _ argumentos: [String], pasta: String?, limite: TimeInterval) async -> ResultadoDeComando
}

/// O executor de verdade. Um app aberto pelo Finder não herda o PATH do terminal, então o do Homebrew entra na frente.
struct ExecutorDeProcesso: ExecutorDeComandos {
    static let caminhosExtras = ["/opt/homebrew/bin", "/usr/local/bin"]

    func rodar(_ executavel: String, _ argumentos: [String], pasta: String?, limite: TimeInterval) async -> ResultadoDeComando {
        await withCheckedContinuation { continuacao in
            DispatchQueue.global(qos: .utility).async {
                continuacao.resume(returning: Self.rodarSincrono(executavel, argumentos, pasta: pasta, limite: limite))
            }
        }
    }

    private final class Acumulador: @unchecked Sendable {
        private let trava = NSLock()
        private var dados = Data()
        func juntar(_ d: Data) { trava.lock(); dados.append(d); trava.unlock() }
        var texto: String { trava.lock(); defer { trava.unlock() }; return String(decoding: dados, as: UTF8.self) }
    }

    static func rodarSincrono(_ executavel: String, _ argumentos: [String], pasta: String?, limite: TimeInterval) -> ResultadoDeComando {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [executavel] + argumentos
        if let pasta { p.currentDirectoryURL = URL(fileURLWithPath: pasta) }
        var ambiente = ProcessInfo.processInfo.environment
        ambiente["PATH"] = (caminhosExtras + [ambiente["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        p.environment = ambiente
        let cano = Pipe()
        p.standardOutput = cano
        p.standardError = cano
        p.standardInput = FileHandle.nullDevice
        let acumulado = Acumulador()
        cano.fileHandleForReading.readabilityHandler = { acumulado.juntar($0.availableData) }
        let terminou = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in terminou.signal() }
        do { try p.run() } catch {
            cano.fileHandleForReading.readabilityHandler = nil
            return ResultadoDeComando(status: 127, saida: "não consegui abrir \(executavel): \(error.localizedDescription)")
        }
        var status: Int32
        if terminou.wait(timeout: .now() + limite) == .timedOut {
            p.terminate()
            _ = terminou.wait(timeout: .now() + 5)
            status = 124
        } else {
            status = p.terminationStatus
        }
        cano.fileHandleForReading.readabilityHandler = nil
        acumulado.juntar((try? cano.fileHandleForReading.readToEnd()) ?? Data())
        if status == 124 { acumulado.juntar(Data("\ntempo esgotado".utf8)) }
        return ResultadoDeComando(status: status, saida: acumulado.texto)
    }
}

// MARK: - Motivos

/// Por que a renovação não rodou ou não deu certo, em português para a pessoa. É isto que fica guardado.
enum MotivoDaRenovacao: Equatable, Sendable {
    case semProjeto(String?)
    case semXcode
    case iphoneForaDoCabo
    case iphoneBloqueado
    case sessaoDaApple
    case outro(String)

    var texto: String {
        switch self {
        case .semProjeto(nil): return "O Deck não sabe onde está o projeto do iPhone. Rode ./build.sh ou ./instalar-iphone.sh de novo"
        case .semProjeto(let p?): return "Não achei o projeto do iPhone em \(p)"
        case .semXcode: return "O Xcode não está instalado ou não está pronto neste Mac"
        case .iphoneForaDoCabo: return "O iPhone não está ao alcance do Mac (nem no cabo, nem no mesmo Wi-Fi)"
        case .iphoneBloqueado: return "O iPhone está bloqueado"
        case .sessaoDaApple: return "A sessão da Apple ID no Xcode venceu. Abra Xcode > Settings > Apple Accounts e entre de novo"
        case .outro(let t): return "A instalação falhou: \(t)"
        }
    }

    /// O iPhone é a causa: tentar de novo quando ele aparecer (cabo ou Wi-Fi) ou for desbloqueado.
    var dependeDoIphone: Bool { self == .iphoneForaDoCabo || self == .iphoneBloqueado }

    /// Lê a saída do xcodebuild ou do devicectl que falhou e devolve a causa mais provável.
    static func classificar(_ saida: String) -> MotivoDaRenovacao {
        let s = saida.lowercased()
        func tem(_ trechos: [String]) -> Bool { trechos.contains { s.contains($0) } }
        if tem(["devicelocked", "is locked", "device locked", "while the device is locked", "passcode"]) { return .iphoneBloqueado }
        if tem(["no accounts", "no account for team", "session has expired", "not signed in", "authentication failed", "sign in with your apple id"]) {
            return .sessaoDaApple
        }
        if tem(["not connected", "no devices", "no device found", "device is not available", "could not be found", "unable to find a device",
                "no matching device", "failed to connect", "devices that are not connected", "unavailable"]) {
            return .iphoneForaDoCabo
        }
        if tem(["unable to find utility", "xcode-select: error", "requires xcode", "xcodebuild: error: sdk"]) { return .semXcode }
        let linhas = saida.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ultima = linhas.last { $0.lowercased().contains("error") } ?? linhas.last ?? "sem detalhe"
        return .outro(String(ultima.prefix(140)))
    }
}

/// Por onde o Mac enxerga o iPhone para instalar: o cabo ou a rede (o iPhone pareado com o Xcode pelo Wi-Fi). É a
/// `transportType` do `devicectl`: "wired" e "localNetwork".
enum CaminhoDoIphone: Equatable, Sendable {
    case cabo
    case wifi

    init?(transporte: String) {
        switch transporte {
        case "wired": self = .cabo
        case "localNetwork": self = .wifi
        default: return nil
        }
    }

    var texto: String { self == .cabo ? "cabo" : "Wi-Fi" }
}

enum SituacaoDoIphone: Equatable, Sendable {
    case semIphone
    case bloqueado
    case liberado
    /// O aparelho está no cabo mas o Mac não soube dizer se está desbloqueado.
    case desconhecido
}

enum ResultadoDaRenovacao: Equatable, Sendable {
    /// `venceEm` é o vencimento do perfil que acabou de ser instalado (nil se o Mac não conseguiu ler).
    case renovado(em: Date, venceEm: Date?)
    case falhou(MotivoDaRenovacao)
}

// MARK: - Agenda

/// A última falha, para decidir quando tentar de novo.
struct FalhaDaRenovacao: Equatable, Sendable {
    var em: Date
    var motivo: MotivoDaRenovacao

    /// Como o iPhone estava quando falhou: é a partir dele que "voltou ao cabo" e "foi desbloqueado" fazem sentido.
    var iphoneNaHora: SituacaoDoIphone {
        switch motivo {
        case .iphoneForaDoCabo: return .semIphone
        case .iphoneBloqueado: return .bloqueado
        default: return .liberado
        }
    }
}

enum AgendaDeRenovacao {
    /// A cada 5 dias depois da última instalação boa. A Apple faz o app vencer em 7.
    static let intervalo: TimeInterval = 5 * 86_400
    /// De quanto em quanto tempo o Deck olha o iPhone enquanto a renovação está atrasada. Uma consulta curta, sem compilar.
    static let checagem: TimeInterval = 300
    /// Falha que não depende do iPhone (Xcode, conta, compilação) só se repete depois disto, para não ficar compilando à toa.
    static let esperaDeFalhaNaoDoIphone: TimeInterval = 3_600

    static func proxima(depoisDe renovadoEm: Date) -> Date { renovadoEm.addingTimeInterval(intervalo) }

    static func devida(renovadoEm: Date?, agora: Date) -> Bool {
        guard let renovadoEm else { return false }
        return agora >= proxima(depoisDe: renovadoEm)
    }

    /// `situacao` só importa quando já houve falha: sem falha, vencida a hora, tenta.
    static func deveTentar(renovadoEm: Date?, falha: FalhaDaRenovacao?, situacao: SituacaoDoIphone, agora: Date) -> Bool {
        guard devida(renovadoEm: renovadoEm, agora: agora) else { return false }
        guard let falha else { return true }
        let passou = agora.timeIntervalSince(falha.em) >= esperaDeFalhaNaoDoIphone
        guard falha.motivo.dependeDoIphone else { return passou }
        // O iPhone voltou ao cabo ou foi desbloqueado desde a falha. Desconhecido espera a hora, como os outros.
        if situacao == .liberado { return falha.iphoneNaHora != .liberado || passou }
        return situacao == .desconhecido && passou
    }
}

// MARK: - O motor

struct MotorDeRenovacao: Sendable {
    var executor: any ExecutorDeComandos
    var relogio: @Sendable () -> Date
    /// A pasta do repo (a que tem `ios/`). nil = o Deck não sabe.
    var pasta: @Sendable () -> String?
    var existe: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    /// Apaga o perfil que o Xcode guardou do app do iPhone. Sem isso o xcodebuild reaproveita o perfil velho (verificado
    /// em 10/11/2026) e a reinstalação não empurra o vencimento. Quem monta o motor decide (os testes não apagam nada).
    var limparPerfil: @Sendable () -> Void = {}

    /// Recebe uma linha do que o motor está fazendo (vai para o deck.log). Nada de tela.
    var anotar: @Sendable (String) -> Void = { _ in }

    static let limiteCurto: TimeInterval = 60
    static let limiteDaCompilacao: TimeInterval = 900

    /// O iPhone ao alcance do Mac (devicectl list devices), por cabo ou pelo Wi-Fi, e se está desbloqueado. Barato: não compila nada.
    func sondar() async -> (id: String?, situacao: SituacaoDoIphone, via: CaminhoDoIphone?) {
        let lista = await executor.rodar("xcrun", ["devicectl", "list", "devices"], pasta: nil, limite: Self.limiteCurto)
        let aoAlcance = lista.status == 0 ? Self.aparelhosAoAlcance(lista.saida) : []
        guard !aoAlcance.isEmpty else { return (nil, .semIphone, nil) }
        // A tabela diz quem responde. O JSON diz o que é (iPhone, iPad, Watch) e por onde chega. Sem JSON legível, vale o primeiro, como antes.
        let json = await executor.rodar("xcrun", ["devicectl", "list", "devices", "--quiet", "--json-output", "/dev/stdout"], pasta: nil, limite: Self.limiteCurto)
        let detalhes = json.status == 0 ? Self.detalhes(json.saida) : [:]
        let id: String
        var via: CaminhoDoIphone?
        if detalhes.isEmpty {
            id = aoAlcance[0]
        } else {
            guard let achado = aoAlcance.first(where: { detalhes[$0.uppercased()]?.tipo == "iPhone" }) else { return (nil, .semIphone, nil) }
            id = achado
            via = detalhes[achado.uppercased()]?.via
        }
        let trava = await executor.rodar("xcrun", ["devicectl", "device", "info", "lockState", "--device", id], pasta: nil, limite: Self.limiteCurto)
        guard trava.status == 0 else { return (id, .desconhecido, via) }
        let s = trava.saida.lowercased()
        if s.contains("passcoderequired: true") { return (id, .bloqueado, via) }
        return (id, s.contains("passcoderequired: false") ? .liberado : .desconhecido, via)
    }

    /// Os ids com estado "available" ou "connected" (e não "unavailable") na tabela do devicectl, na ordem em que aparecem.
    static func aparelhosAoAlcance(_ tabela: String) -> [String] {
        let id = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")
        let estado = try! NSRegularExpression(pattern: "(?<![A-Za-z])(available|connected)")
        var achados: [String] = []
        for linha in tabela.split(whereSeparator: \.isNewline).map(String.init) {
            let todo = NSRange(linha.startIndex..., in: linha)
            guard let achou = id.firstMatch(in: linha, range: todo), let r = Range(achou.range, in: linha) else { continue }
            let depois = NSRange(r.upperBound..., in: linha)
            if estado.firstMatch(in: linha, range: depois) != nil { achados.append(String(linha[r])) }
        }
        return achados
    }

    /// O id do primeiro aparelho ao alcance, seja o que for.
    static func aparelhoNoCabo(_ tabela: String) -> String? { aparelhosAoAlcance(tabela).first }

    /// De `devicectl list devices --quiet --json-output /dev/stdout`: o tipo ("iPhone") e o caminho de cada aparelho, pelo id.
    /// A saída do comando junta erro e saída, então pega do primeiro `{` ao último `}`.
    static func detalhes(_ saida: String) -> [String: (tipo: String?, via: CaminhoDoIphone?)] {
        guard let ini = saida.firstIndex(of: "{"), let fim = saida.lastIndex(of: "}"), ini < fim,
              let obj = try? JSONSerialization.jsonObject(with: Data(saida[ini...fim].utf8)) as? [String: Any],
              let aparelhos = (obj["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [:] }
        var mapa: [String: (tipo: String?, via: CaminhoDoIphone?)] = [:]
        for a in aparelhos {
            guard let id = a["identifier"] as? String else { continue }
            let tipo = (a["hardwareProperties"] as? [String: Any])?["deviceType"] as? String
            let via = ((a["connectionProperties"] as? [String: Any])?["transportType"] as? String).flatMap(CaminhoDoIphone.init(transporte:))
            mapa[id.uppercased()] = (tipo, via)
        }
        return mapa
    }

    func renovar() async -> ResultadoDaRenovacao {
        guard let raiz = pasta() else { return .falhou(.semProjeto(nil)) }
        let ios = raiz + "/ios"
        guard existe(ios + "/project.yml") else { return .falhou(.semProjeto(raiz)) }

        let xcode = await executor.rodar("xcrun", ["--find", "xcodebuild"], pasta: nil, limite: Self.limiteCurto)
        guard xcode.status == 0 else { return .falhou(.semXcode) }

        let aparelho = await sondar()
        guard let id = aparelho.id else { return .falhou(.iphoneForaDoCabo) }
        anotar("renovacao: iPhone achado \(aparelho.via.map { "pelo " + $0.texto } ?? "ao alcance")")

        let empacotar = await executor.rodar("bash", ["scripts/empacotar-painel.sh"], pasta: ios, limite: Self.limiteCurto)
        guard empacotar.status == 0 else { return .falhou(.classificar(empacotar.saida)) }

        let gerar = await executor.rodar("xcodegen", ["generate", "--spec", "project.yml", "--quiet"], pasta: ios, limite: Self.limiteCurto)
        guard gerar.status == 0 else {
            return .falhou(gerar.status == 127 ? .outro("o xcodegen não está instalado (brew install xcodegen)") : .classificar(gerar.saida))
        }

        limparPerfil()
        // O perfil da conta grátis nasce aqui: sem -allowProvisioningUpdates o xcodebuild não pede nada à Apple.
        let compilar = await executor.rodar(
            "xcodebuild", ["-project", "Deck.xcodeproj", "-scheme", "Deck", "-configuration", "Debug", "-destination", "generic/platform=iOS",
                           "-derivedDataPath", "build", "-allowProvisioningUpdates", "build"],
            pasta: ios, limite: Self.limiteDaCompilacao)
        guard compilar.status == 0, compilar.saida.contains("BUILD SUCCEEDED") else { return .falhou(.classificar(compilar.saida)) }

        let app = "build/Build/Products/Debug-iphoneos/Deck.app"
        let instalar = await executor.rodar("xcrun", ["devicectl", "device", "install", "app", "--device", id, app], pasta: ios, limite: Self.limiteDaCompilacao)
        guard instalar.status == 0, instalar.saida.contains("App installed") else { return .falhou(.classificar(instalar.saida)) }

        let perfil = await executor.rodar("security", ["cms", "-D", "-i", app + "/embedded.mobileprovision"], pasta: ios, limite: Self.limiteCurto)
        return .renovado(em: relogio(), venceEm: perfil.status == 0 ? Self.vencimento(doPerfil: perfil.saida) : nil)
    }

    static let idDoAppDoIphone = "com.leonardorejani.deck.iphone"

    static var pastaDosPerfis: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles")
    }

    /// Apaga de `pasta` os perfis do app do iPhone (o id do app aparece em texto dentro do arquivo). Devolve quantos apagou.
    @discardableResult
    static func apagarPerfisDoApp(em pasta: URL = pastaDosPerfis, id: String = idDoAppDoIphone) -> Int {
        let fm = FileManager.default
        let alvo = Data(id.utf8)
        var apagados = 0
        for nome in (try? fm.contentsOfDirectory(atPath: pasta.path)) ?? [] where nome.hasSuffix(".mobileprovision") {
            let url = pasta.appendingPathComponent(nome)
            guard let dados = try? Data(contentsOf: url), dados.range(of: alvo) != nil else { continue }
            if (try? fm.removeItem(at: url)) != nil { apagados += 1 }
        }
        return apagados
    }

    /// `ExpirationDate` do plist que `security cms -D` imprime.
    static func vencimento(doPerfil plist: String) -> Date? {
        guard let dados = plist.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: dados, options: [], format: nil) as? [String: Any] else { return nil }
        return obj["ExpirationDate"] as? Date
    }
}

// MARK: - O arquivo que os scripts preenchem

/// ~/Library/Application Support/Deck/renovacao.plist: onde está o repo e quando o app foi instalado pela última vez.
/// O `build.sh` e o `instalar-iphone.sh` escrevem (com `defaults write`), o Deck lê. Fica fora do config.json, que o iPhone também lê.
struct ArquivoDeInstalacao: Equatable, Sendable {
    var pasta: String?
    var instaladoEm: Date?

    static var urlPadrao: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Deck/renovacao.plist")
    }

    static func ler(_ url: URL = urlPadrao) -> ArquivoDeInstalacao {
        guard let dados = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: dados, options: [], format: nil) as? [String: Any] else {
            return ArquivoDeInstalacao()
        }
        let pasta = (obj["pasta"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ArquivoDeInstalacao(pasta: pasta, instaladoEm: obj["instaladoEm"] as? Date)
    }
}
