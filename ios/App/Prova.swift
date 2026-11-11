import UIKit
import DeckCasca

/// Modo de prova: o app abre já numa tela e tira uma foto da janela, para conferir com o protótipo
/// sem tocar no aparelho. Só liga com argumento de lançamento, nunca no uso normal:
///   -prova-tela vazio|procurando|confirmar|cabo|codigo|pronto|offline|painel|chip
///   -prova-foto nome.png               salva em Documents/ depois de a tela assentar
///   -prova-orientacao horizontal|vertical
///   -prova-cabo-codigo 123456          com o app de verdade (Keychain e cabo): pareia sozinho pelo cabo com esse código
///   -prova-esquecer                    apaga o pareamento do Keychain antes de abrir (para provar o pareamento do zero)
///   -prova-tecla id                    com o painel no ar, toca a tecla desse id (o mesmo clique do dedo na página)
///   -prova-fotos-a-cada 5              depois da primeira foto, tira uma a cada 5 s (seq-N.png), até 40
///   -prova-bt-parear                   com o app de verdade: pareia sozinho pelo Bluetooth (lista, toca no Mac mais perto e confirma o código)
///   -prova-sem-cabo                    o app não liga o canal do cabo (para provar o Bluetooth com o iPhone ainda plugado)
///   -prova-cabo-sai-em 20              20 s depois de abrir, derruba o cabo, como se fosse puxado
///   -prova-monitor 2                   a cada 2 s, até 60 vezes, registra o canal em uso, se a tela "Mac desconectado" está de pé e o aviso de canal
/// Nas telas de prova o pareador e o canal são de mentira, com os mesmos nomes e códigos do protótipo.
/// Sem -prova-tela (ou com "real") o app é o de verdade e só ganha o que os argumentos pedem.
struct Prova {
    let tela: String
    let foto: String?
    let orientacao: String?
    let codigo: String?
    let tecla: String?
    let fotosACada: Double?
    let btParear: Bool
    let monitorACada: Double?

    static let telaReal = "real"

    static func ler() -> Prova? {
        let a = ProcessInfo.processInfo.arguments
        func valor(_ nome: String) -> String? { a.firstIndex(of: nome).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        let tela = valor("-prova-tela")
        let codigo = valor("-prova-cabo-codigo")
        let btParear = a.contains("-prova-bt-parear")
        let monitor = valor("-prova-monitor").flatMap { Double($0) }
        guard tela != nil || codigo != nil || btParear || monitor != nil || a.contains("-prova-esquecer") || valor("-prova-tecla") != nil else { return nil }
        return Prova(tela: tela ?? telaReal, foto: valor("-prova-foto"), orientacao: valor("-prova-orientacao"), codigo: codigo,
                     tecla: valor("-prova-tecla"), fotosACada: valor("-prova-fotos-a-cada").flatMap { Double($0) },
                     btParear: btParear, monitorACada: monitor)
    }

    static let codigoDeProva = "PROVACODIGOAAAAAAAA"

    @MainActor
    func montar(vibrar: @escaping @Sendable () -> Void) -> Casca {
        let comMac = ["offline", "painel", "chip"].contains(tela)
        let cofre = CofreEmMemoria(comMac ? Pareado(codigoAcesso: Self.codigoDeProva, nomeMac: "MacBook Pro de Exemplo") : nil)
        let pareador = PareadorDeProva(achaNoCabo: tela != "cabo")
        let casca = Casca(pareador: pareador, cofre: cofre, vibrar: vibrar, permanenciaNoCabo: 0.3)
        if tela == "painel" || tela == "chip" { casca.usar(canal: CanalDeProva(.cabo)) }
        casca.iniciar()
        return casca
    }

    /// Depois da página carregar: leva o fluxo até a tela pedida, espera assentar e tira a foto.
    @MainActor
    func acompanhar(_ controlador: ControladorDoPainel) {
        controlador.aoCarregar = { [self] in
            controlador.aoCarregar = nil
            Task { @MainActor in await rodar(controlador) }
        }
        if let o = orientacao, let cena = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            cena.requestGeometryUpdate(.iOS(interfaceOrientations: o == "vertical" ? .portrait : .landscapeRight))
        }
    }

    @MainActor
    private func rodar(_ controlador: ControladorDoPainel) async {
        let casca = controlador.casca
        let fluxo = casca.fluxo
        func espera(segundos: Double = 5, _ ok: () -> Bool) async {
            for _ in 0..<Int(segundos * 40) where !ok() { try? await Task.sleep(nanoseconds: 25_000_000) }
        }
        switch tela {
        case Prova.telaReal:
            // Pareia pelo cabo com o código que o Mac mostrou, sem ninguém tocar no iPhone. Já pareado, pula.
            if let codigo, fluxo.estado.etapa != .painel {
                _ = await fluxo.tratar(.cabo)
                await espera { fluxo.estado.etapa == .codigo }
                Prova.registrar("PROVA_CABO etapa \(fluxo.estado.etapa.rawValue) mac=\(fluxo.estado.nomeMac)")
                let erro = await fluxo.tratar(.digitos(codigo))
                Prova.registrar("PROVA_CABO parear \(erro ?? "ok") etapa=\(fluxo.estado.etapa.rawValue)")
                _ = await fluxo.tratar(.abrirPainel)
            }
            // Pareamento principal: lista os Macs por Bluetooth, toca no mais perto e confirma o código (o Mac confirma sozinho, --bt-permitir).
            if btParear, fluxo.estado.etapa != .painel {
                _ = await fluxo.tratar(.procurar)
                await espera(segundos: 60) { fluxo.estado.macs.contains { $0.perto } }
                Prova.registrar("PROVA_BT lista \(fluxo.estado.macs.map { "\($0.nome) perto=\($0.perto)" })")
                if let mac = fluxo.estado.macs.first(where: { $0.perto }) {
                    let erro = await fluxo.tratar(.escolher(mac.id))
                    await espera(segundos: 30) { fluxo.estado.etapa == .confirmar }
                    Prova.registrar("PROVA_BT codigo \(fluxo.estado.codigo) etapa=\(fluxo.estado.etapa.rawValue) mac=\(fluxo.estado.nomeMac) erro=\(erro ?? "-")")
                    let e2 = await fluxo.tratar(.confirmar(true))
                    Prova.registrar("PROVA_BT confirmar \(e2 ?? "ok") etapa=\(fluxo.estado.etapa.rawValue)")
                    _ = await fluxo.tratar(.abrirPainel)
                }
            }
        case "procurando": _ = await fluxo.tratar(.procurar)
        case "confirmar":
            _ = await fluxo.tratar(.procurar); await espera { fluxo.estado.macs.count == 2 }
            _ = await fluxo.tratar(.escolher("mac-1"))
        case "cabo": _ = await fluxo.tratar(.procurar); _ = await fluxo.tratar(.cabo)
        case "codigo":
            _ = await fluxo.tratar(.procurar); _ = await fluxo.tratar(.cabo); await espera { fluxo.estado.etapa == .codigo }
        case "pronto":
            _ = await fluxo.tratar(.procurar); await espera { fluxo.estado.macs.count == 2 }
            _ = await fluxo.tratar(.escolher("mac-1")); _ = await fluxo.tratar(.confirmar(true))
        default: break
        }
        Prova.registrar("PROVA_ETAPA \(fluxo.estado.etapa.rawValue)")
        if tela == "chip" {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            casca.usar(canal: CanalDeProva(.bluetooth))
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else {
            // o painel vivo precisa de uns segundos para pedir o estado, a config e a capa
            try? await Task.sleep(nanoseconds: ["painel", Prova.telaReal].contains(tela) ? 4_000_000_000 : 1_500_000_000)
        }
        Prova.registrar("PROVA_CANAL em uso: \(casca.canais.obter()?.tipo.rawValue ?? "nenhum")")
        if let cada = monitorACada { monitorar(controlador, cada: cada) }
        if let tecla {
            let js = "(function(){var t=document.querySelector('.tecla[data-id=\"\(tecla)\"]');if(!t)return 'sem-tecla';t.click();return 'clicou'})()"
            let r = try? await controlador.web.evaluateJavaScript(js)
            Prova.registrar("PROVA_TECLA \(tecla) \(r.map { "\($0)" } ?? "erro")")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if let nome = foto { tirarFoto(controlador, nome) }
        if let cada = fotosACada {
            for i in 1...40 {
                try? await Task.sleep(nanoseconds: UInt64(cada * 1_000_000_000))
                tirarFoto(controlador, "seq-\(i).png")
            }
        }
    }

    /// Registra de tempos em tempos o canal em uso e o que a página mostra: se a tela "Mac desconectado" está de pé e o aviso do canal.
    @MainActor
    private func monitorar(_ controlador: ControladorDoPainel, cada: Double) {
        Task { @MainActor in
            let js = "(function(){var t=document.getElementById('tela');var c=document.getElementById('canal-chip');return JSON.stringify({offline:!!(t&&t.classList.contains('offline')),chip:(c&&c.classList.contains('visivel'))?c.textContent:''})})()"
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: UInt64(cada * 1_000_000_000))
                let r = try? await controlador.web.evaluateJavaScript(js)
                Prova.registrar("PROVA_MONITOR canal=\(controlador.casca.canais.obter()?.tipo.rawValue ?? "nenhum") pagina=\(r.map { "\($0)" } ?? "erro")")
            }
        }
    }

    @MainActor
    private func tirarFoto(_ controlador: ControladorDoPainel, _ nome: String) {
        guard let janela = controlador.view.window else { return Prova.registrar("PROVA_FOTO_ERRO sem janela") }
        let imagem = UIGraphicsImageRenderer(bounds: janela.bounds).image { _ in
            janela.drawHierarchy(in: janela.bounds, afterScreenUpdates: true)
        }
        let pasta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destino = pasta.appendingPathComponent(nome)
        do {
            try imagem.pngData()?.write(to: destino)
            Prova.registrar("PROVA_FOTO \(nome) \(Int(janela.bounds.width))x\(Int(janela.bounds.height)) pt")
        } catch {
            Prova.registrar("PROVA_FOTO_ERRO \(error.localizedDescription)")
        }
    }

    /// Linha no console e em Documents/prova.log (o devicectl copia o arquivo de volta).
    static func registrar(_ linha: String) {
        print(linha)
        let pasta = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let arquivo = pasta.appendingPathComponent("prova.log")
        let texto = "\(Date()) \(linha)\n"
        if let h = try? FileHandle(forWritingTo: arquivo) {
            h.seekToEndOfFile(); h.write(Data(texto.utf8)); try? h.close()
        } else {
            try? texto.write(to: arquivo, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Pareador de mentira (os dois Macs e o código do protótipo)

struct PareadorDeProva: Pareador {
    let achaNoCabo: Bool
    static let perto = MacEncontrado(id: "mac-1", nome: "MacBook Pro de Exemplo", perto: true)
    static let longe = MacEncontrado(id: "mac-2", nome: "Mac mini do estúdio", perto: false)

    func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> { AsyncStream { $0.yield([Self.perto, Self.longe]) } }
    func iniciar(com mac: MacEncontrado) async throws -> String { "483291" }
    func concluir(aceito: Bool) async throws -> PareamentoFeito {
        PareamentoFeito(pareado: Pareado(codigoAcesso: Prova.codigoDeProva, nomeMac: Self.perto.nome), canal: CanalDeProva(.bluetooth))
    }
    func procurarNoCabo() -> AsyncStream<MacEncontrado> {
        AsyncStream { c in if achaNoCabo { c.yield(Self.perto) } }
    }
    func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        guard codigo == "483291" else { throw ErroPareamento.recusado("Código errado. Confira o que aparece no Mac.") }
        return PareamentoFeito(pareado: Pareado(codigoAcesso: Prova.codigoDeProva, nomeMac: mac.nome), canal: CanalDeProva(.cabo))
    }
}

// MARK: - Canal de mentira: um "Mac" que responde com dados do protótipo e troca o código no rodízio

final class CanalDeProva: Canal, @unchecked Sendable {
    let tipo: TipoCanal
    /// O "Mac" é um só: o código esperado e a contagem valem para todos os canais de prova.
    private static let trava = NSLock()
    nonisolated(unsafe) private static var esperado = Prova.codigoDeProva
    nonisolated(unsafe) private static var pedidos = 0

    init(_ tipo: TipoCanal) { self.tipo = tipo }

    func enviar(_ p: PedidoCanal) async throws -> RespostaCanal {
        let (n, recebido, esperadoAntes, novo): (Int, String, String, String?) = Self.trava.withLock {
            Self.pedidos += 1
            let recebido = p.cabecalhos["x-deck-codigo"] ?? p.query["codigo"] ?? ""
            let antes = Self.esperado
            var novo: String?
            // Do 5o pedido em diante, o primeiro com o código certo faz o Mac trocar o código (rodízio):
            // a resposta traz o novo e o Mac só aceita o novo daí em diante
            if Self.pedidos >= 5, recebido == antes, antes == Prova.codigoDeProva { novo = "ROTACAOCODIGOBBBBBB"; Self.esperado = novo! }
            return (Self.pedidos, recebido, antes, novo)
        }
        let ok = recebido == esperadoAntes
        Prova.registrar("PROVA_CANAL #\(n) \(tipo.rawValue) \(p.metodo) \(p.caminho) codigo=\(recebido.prefix(8)) \(ok ? "aceito" : "RECUSADO")\(novo != nil ? " trocou-para=\(novo!.prefix(8))" : "")")
        guard ok else { return Self.json(401, ["erro": "Código de acesso ausente ou incorreto."]) }
        var extras: [String: String] = [:]
        if let novo { extras["X-Deck-Codigo-Novo"] = novo }

        switch p.caminho {
        case "/api/estado": return Self.json(200, Self.estado(), extras)
        case "/api/config": return Self.json(200, Self.config(), extras)
        case "/api/botao/acordado", "/api/botao/whatsapp", "/api/botao/calendario", "/api/botao/apagar": return Self.json(200, ["ok": true], extras)
        case "/api/capa": return RespostaCanal(status: 200, tipo: "image/png", corpo: Self.capa(), cabecalhos: extras)
        case "/api/whatsapp", "/api/sessoes", "/api/agenda": return Self.json(200, [Any](), extras)
        default: return Self.json(404, ["erro": "Essa rota não existe."], extras)
        }
    }

    private static func json(_ status: Int, _ obj: Any, _ extras: [String: String] = [:]) -> RespostaCanal {
        let dados = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return RespostaCanal(status: status, tipo: "application/json; charset=utf-8", corpo: dados, cabecalhos: extras)
    }

    private static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private static func estado() -> [String: Any] {
        let agora = Date()
        return [
            "agora": iso(agora), "nomeMac": "MacBook Pro de Exemplo", "perfilAtivo": "p1", "comp": "a",
            "blocos": ["spotify": true, "agenda": true, "whatsapp": true, "sessoes": true, "uso": true],
            "spotify": ["tocando": true, "faixa": "Bom dia", "artista": "Banda de teste", "posicao": 42.0, "duracao": 210.0,
                        "capaId": "c1", "cores": ["#3ECF8E", "#1C1C1C"]],
            "uso": [["id": "claude-leo", "nome": "Claude", "conta": "leo", "semana": 61, "renova": iso(agora.addingTimeInterval(3 * 86400))],
                    ["id": "codex", "nome": "Codex", "conta": "pro", "semana": 4, "renova": iso(agora.addingTimeInterval(86400))]],
            "sessoes": [["id": "s1", "nome": "deck", "projeto": "deck", "pergunta": "Posso mexer na ponte?", "desde": iso(agora.addingTimeInterval(-600))]],
            "whatsapp": ["total": 5, "conversas": 2],
            "agenda": ["permissao": true, "proximo": ["titulo": "Ensaio", "inicio": iso(agora.addingTimeInterval(3600)), "diaTodo": false, "calendario": "Igreja", "cor": "#3B82F6"]],
            "acesas": ["acordado"], "selos": ["whatsapp": "5"], "avisos": [Any](),
        ]
    }

    private static func config() -> [String: Any] {
        [
            "versao": 1, "perfilAtivo": "p1", "comp": "a", "nomeMac": "MacBook Pro de Exemplo", "porta": 4777,
            "blocos": ["spotify": true, "agenda": true, "whatsapp": true, "sessoes": true, "uso": true],
            "contas": [["id": "claude-leo", "nome": "Claude", "conta": "leo"], ["id": "codex", "nome": "Codex", "conta": "pro"]],
            "perfis": [["id": "p1", "nome": "Principal", "teclas": [
                ["id": "acordado", "nome": "Manter acordado", "tipo": "tecla", "valor": "ctrl+opt+cmd+k", "estado": "true", "icone": "svg:raio"],
                ["id": "whatsapp", "nome": "WhatsApp", "tipo": "app", "valor": "WhatsApp", "icone": "WhatsApp"],
                ["id": "calendario", "nome": "Agenda", "tipo": "app", "valor": "Calendar", "icone": "Calendar"],
                ["id": "apagar", "nome": "Apagar tela", "tipo": "comando", "valor": "pmset displaysleepnow", "icone": "svg:tela"],
            ]]],
        ]
    }

    /// Uma capa de mentira: quadrado verde com degradê, para provar o deckcapa://.
    private static func capa() -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240))
        return r.pngData { c in
            let cores = [UIColor(red: 0.24, green: 0.81, blue: 0.56, alpha: 1).cgColor, UIColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1).cgColor]
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cores as CFArray, locations: [0, 1])!
            c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 240, y: 240), options: [])
        }
    }
}
