import Foundation
@testable import Nucleo

final class Registro: @unchecked Sendable {
    private let trava = NSLock()
    private var itens: [String] = []
    func anotar(_ s: String) { trava.lock(); itens.append(s); trava.unlock() }
    var todos: [String] { trava.lock(); defer { trava.unlock() }; return itens }
}

func configDeTeste(codigo: String = "abcdefghjkmnpqrstuvw") -> Config {
    Config(perfis: [Perfil(id: "geral", nome: "Geral", teclas: [
        Tecla(id: "acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k", estado: nil, icone: nil),
        Tecla(id: "quebrada", nome: "Quebrada", tipo: "comando", valor: "false", estado: nil, icone: nil),
    ]), Perfil(id: "outro", nome: "Outro", teclas: [
        Tecla(id: "so-no-outro", nome: "Outro", tipo: "app", valor: "Notas", estado: nil, icone: nil),
    ])], perfilAtivo: "geral", nomeMac: "Mac", porta: 4777, codigoAcesso: codigo)
}

final class ArmazemFalso: ArmazemDeConfig, @unchecked Sendable {
    private let trava = NSLock()
    private var atual: Config
    var erroAoAplicar: String?
    init(_ c: Config) { atual = c }
    func ler() -> Config { trava.lock(); defer { trava.unlock() }; return atual }
    func aplicar(_ nova: Config) -> String? {
        if let e = erroAoAplicar { return e }
        trava.lock(); atual = nova; trava.unlock()
        return nil
    }
}

struct PaineisFalsos: ProvedorPaineis {
    let registro: Registro
    var temCapa = true
    func estado() -> Estado {
        Estado(agora: "2026-11-10T10:00:00Z", nomeMac: "Mac", perfilAtivo: "geral", comp: "a", blocos: Blocos(),
               spotify: nil, uso: [], sessoes: [], whatsapp: nil, agenda: nil, acesas: ["acordado"], selos: [:], avisos: [])
    }
    func whatsapp() -> [ConversaWhatsApp] {
        [ConversaWhatsApp(id: "c1", nome: "Louvor", grupo: true, naoLidas: 2, ultima: "2026-11-10T09:00:00Z", mensagens: [])]
    }
    func agenda(de: String, dias: Int) -> [Evento] {
        registro.anotar("agenda \(de) \(dias)")
        return [Evento(titulo: "Ensaio", inicio: "\(de)T19:00:00Z", diaTodo: false, calendario: "Igreja", cor: "#000000", local: nil)]
    }
    func sessoes() -> [Sessao] { [Sessao(id: "s1", nome: "A", projeto: "deck", pergunta: "Seguir?", desde: "2026-11-10T09:00:00Z")] }
    func capa() -> CapaAtual? { temCapa ? CapaAtual(tipo: "image/png", dados: Data([1, 2, 3])) : nil }
}

struct TeclasFalsas: ExecutorTeclas {
    let registro: Registro
    func executar(_ tecla: Tecla) -> String? {
        registro.anotar("tecla \(tecla.id)")
        return tecla.id == "quebrada" ? "A tecla falhou." : nil
    }
}

struct SpotifyFalso: ControleSpotify {
    let registro: Registro
    /// Sem login no Spotify, o que depende da API responde "não conectado".
    var conectado = true
    func acao(_ nome: String) -> String? { registro.anotar("spotify \(nome)"); return nil }
    func posicao(_ s: Double) -> String? { registro.anotar("posicao \(s)"); return nil }
    func definir(_ nome: String, ligado: Bool?) -> String? { registro.anotar("\(nome) \(ligado.map { $0 ? "1" : "0" } ?? "alterna")"); return nil }
    func volume(_ alvo: AlvoVolume, _ valor: Int) -> ErroSpotify? {
        registro.anotar("volume \(alvo.rawValue) \(valor)")
        return alvo == .aparelho && !conectado ? .naoConectado : nil
    }
    func dispositivos() -> Result<[DispositivoSpotify], ErroSpotify> {
        guard conectado else { return .failure(.naoConectado) }
        return .success([DispositivoSpotify(id: "d1", nome: "Caixa da sala", tipo: "speaker", ativo: true, volume: 30, restrito: false)])
    }
    func transferir(para id: String) -> ErroSpotify? {
        guard conectado else { return .naoConectado }
        registro.anotar("transferir \(id)")
        return id == "premium" ? .soPremium : nil
    }
    func curtir(_ curtir: Bool) -> ErroSpotify? {
        guard conectado else { return .naoConectado }
        registro.anotar("curtir \(curtir)"); return nil
    }
    func fila() -> Result<FilaSpotify, ErroSpotify> {
        guard conectado else { return .failure(.naoConectado) }
        return .success(FilaSpotify(atual: ItemDaFila(faixa: "Agora", artista: "Coral"), proximas: [ItemDaFila(faixa: "Depois", artista: "Ana")]))
    }
    func repetirModo(_ modo: String) -> ErroSpotify? {
        guard conectado else { return .naoConectado }
        registro.anotar("repetirModo \(modo)"); return nil
    }
}

/// Monta um roteador com tudo falso e uma pasta de página temporária.
struct Cenario {
    var roteador: Roteador
    let registro = Registro()
    let armazem: ArmazemFalso
    let pareamento: Pareamento
    let raiz: URL
    /// O ca.crt de mentira (e, ao lado, uma chave que nunca pode sair).
    let ca: URL
    static let conteudoCA = "-----BEGIN CERTIFICATE-----\nDECK\n-----END CERTIFICATE-----\n"
    static let codigo = "abcdefghjkmnpqrstuvw"

    init(codigoPareamento: String = "123456", agora: @escaping @Sendable () -> Date = { Date() },
         rodizio: Rodizio = Rodizio(), comCA: Bool = true, spotifyConectado: Bool = true) throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("deck-rotas-\(UUID().uuidString)")
        raiz = base.appendingPathComponent("pagina")
        try fm.createDirectory(at: raiz.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("<h1>deck</h1>".utf8).write(to: raiz.appendingPathComponent("index.html"))
        try Data("body{}".utf8).write(to: raiz.appendingPathComponent("deck.css"))
        try Data("{}".utf8).write(to: raiz.appendingPathComponent("app.webmanifest"))
        try Data("<p>sub</p>".utf8).write(to: raiz.appendingPathComponent("sub/index.html"))
        try Data("segredo".utf8).write(to: base.appendingPathComponent("fora.txt"))
        try Data("env".utf8).write(to: raiz.appendingPathComponent(".env"))
        try fm.createSymbolicLink(at: raiz.appendingPathComponent("escapa.txt"), withDestinationURL: base.appendingPathComponent("fora.txt"))

        ca = base.appendingPathComponent("certificados/ca.crt")
        try fm.createDirectory(at: ca.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.conteudoCA.utf8).write(to: ca)
        try Data("CHAVE-PRIVADA".utf8).write(to: base.appendingPathComponent("certificados/ca.key"))

        armazem = ArmazemFalso(configDeTeste())
        pareamento = Pareamento(agora: agora, sorteio: { codigoPareamento })
        pareamento.gerar()
        roteador = Roteador(paineis: PaineisFalsos(registro: registro), teclas: TeclasFalsas(registro: registro),
                            spotify: SpotifyFalso(registro: registro, conectado: spotifyConectado), config: armazem, pareamento: pareamento,
                            pagina: ArquivosPagina(raiz: raiz), rodizio: rodizio, certificadoCA: comCA ? ca : nil)
    }

    func pedir(_ metodo: String, _ alvo: String, corpo: String = "", codigo: String? = Cenario.codigo,
               viaQuery: Bool = false) -> RespostaRota {
        var cab: [String: String] = [:]
        var (caminho, query) = Http.separarAlvo(alvo)
        if let codigo {
            if viaQuery { query["codigo"] = codigo } else { cab["x-deck-codigo"] = codigo }
        }
        return roteador.responder(HttpRequisicao(metodo: metodo, caminho: caminho, query: query,
                                                 cabecalhos: cab, corpo: Data(corpo.utf8)))
    }
}

extension RespostaRota {
    var texto: String { String(decoding: corpo, as: UTF8.self) }
    var json: Any? { try? JSONSerialization.jsonObject(with: corpo) }
    var erroTexto: String? { (json as? [String: Any])?["erro"] as? String }
}
