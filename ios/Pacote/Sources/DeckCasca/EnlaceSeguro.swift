#if canImport(CryptoKit)
import CryptoKit
import Foundation

// O Bluetooth não é um fio fechado como o cabo: qualquer aparelho por perto escuta o ar. Por isso, antes do
// primeiro pedido, os dois lados trocam chaves (Curve25519) e tudo dali em diante vai cifrado e autenticado
// (ChaChaPoly), inclusive o código de acesso, que viaja em todo pedido. Dois jeitos de entrar:
//
//  "acesso": o iPhone já pareado. Cada lado prova que conhece o código de acesso (HMAC sobre a transcrição),
//            então um Mac falso não entra e um iPhone sem o código não é atendido.
//  "parear": o iPhone novo. Os dois derivam os mesmos 6 dígitos (Sas), a pessoa confere nas duas telas e só
//            depois o Mac entrega o código de acesso, já pelo fio cifrado.
//
// O espelho disto no Mac é mac/Nucleo/EnlaceSeguro.swift: mudou aqui, muda lá.

enum ErroEnlace: Error, Equatable {
    case protocolo(String)
    /// O outro lado não reconhece este código de acesso (iPhone não pareado, ou Mac que não é o do pareamento).
    case naoPareado
    case recusado(String)
}

/// Mensagem do aperto de mão: um JSON com o tamanho na frente (2 bytes), no fio ainda aberto ou já cifrado.
struct MsgEnlace: Codable, Equatable {
    var t: String
    var m: String?
    var a: Data?
    var b: Data?
    var n: String?
}

enum QuadroEnlace {
    static let maximo = 4096

    static func escrever(_ fluxo: FluxoBytes, _ m: MsgEnlace) -> Bool {
        guard let json = try? JSONEncoder().encode(m), json.count <= maximo else { return false }
        var quadro = Data([UInt8(json.count >> 8 & 0xff), UInt8(json.count & 0xff)])
        quadro.append(json)
        return fluxo.escrever(quadro)
    }

    static func ler(_ fluxo: FluxoBytes) -> MsgEnlace? {
        guard let cab = fluxo.lerExato(2) else { return nil }
        let n = Int(cab[cab.startIndex]) << 8 | Int(cab[cab.startIndex + 1])
        guard n > 0, n <= maximo, let corpo = fluxo.lerExato(n) else { return nil }
        return try? JSONDecoder().decode(MsgEnlace.self, from: corpo)
    }
}

/// Fecha o fio se o outro lado não responder a tempo: a leitura do Bluetooth espera para sempre.
final class Vigia: @unchecked Sendable {
    private let trava = NSLock()
    private var ativo = true

    init(_ fluxo: FluxoBytes, _ segundos: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + segundos) { [self] in
            trava.lock(); let vale = ativo; trava.unlock()
            if vale { fluxo.fechar() }
        }
    }

    func cancelar() { trava.lock(); ativo = false; trava.unlock() }
}

/// O fio depois do aperto de mão: cada pedaço escrito vira um registro cifrado (2 bytes de tamanho, texto
/// cifrado e etiqueta). O nonce é um contador de cada direção, então registro repetido, fora de ordem ou
/// adulterado não abre e derruba a conexão.
final class FluxoCifrado: FluxoBytes, @unchecked Sendable {
    static let maximoDoRegistro = 4096
    private let interno: FluxoBytes
    private let chaveEnvio: SymmetricKey
    private let chaveRecebe: SymmetricKey
    private let escrita = NSLock()
    private var contadorEnvio: UInt64 = 0
    private var contadorRecebe: UInt64 = 0
    private var sobra = Data()

    init(interno: FluxoBytes, envio: SymmetricKey, recebe: SymmetricKey) {
        self.interno = interno
        chaveEnvio = envio
        chaveRecebe = recebe
    }

    private static func nonce(_ n: UInt64) throws -> ChaChaPoly.Nonce {
        var b = Data(repeating: 0, count: 4)
        for i in (0..<8).reversed() { b.append(UInt8(n >> UInt64(i * 8) & 0xff)) }
        return try ChaChaPoly.Nonce(data: b)
    }

    func ler(maximo: Int) -> Data? {
        while sobra.isEmpty {
            guard let registro = proximoRegistro() else { return nil }
            sobra = registro
        }
        let saida = Data(sobra.prefix(maximo))
        sobra = Data(sobra.dropFirst(saida.count))
        return saida
    }

    private func proximoRegistro() -> Data? {
        guard let cab = interno.lerExato(2) else { return nil }
        let n = Int(cab[cab.startIndex]) << 8 | Int(cab[cab.startIndex + 1])
        guard n >= 16, n <= Self.maximoDoRegistro + 16, let corpo = interno.lerExato(n) else { interno.fechar(); return nil }
        do {
            let caixa = try ChaChaPoly.SealedBox(nonce: Self.nonce(contadorRecebe), ciphertext: corpo.dropLast(16), tag: corpo.suffix(16))
            let aberto = try ChaChaPoly.open(caixa, using: chaveRecebe)
            contadorRecebe += 1
            return aberto
        } catch {
            interno.fechar()
            return nil
        }
    }

    func escrever(_ dados: Data) -> Bool {
        escrita.lock(); defer { escrita.unlock() }
        var inicio = 0
        repeat {
            let fim = min(inicio + Self.maximoDoRegistro, dados.count)
            let parte = Data(dados[dados.startIndex + inicio ..< dados.startIndex + fim])
            guard let nonce = try? Self.nonce(contadorEnvio), let caixa = try? ChaChaPoly.seal(parte, using: chaveEnvio, nonce: nonce) else { return false }
            contadorEnvio += 1
            let tamanho = caixa.ciphertext.count + caixa.tag.count
            var registro = Data([UInt8(tamanho >> 8 & 0xff), UInt8(tamanho & 0xff)])
            registro.append(caixa.ciphertext)
            registro.append(caixa.tag)
            guard interno.escrever(registro) else { return false }
            inicio = fim
        } while inicio < dados.count
        return true
    }

    func fechar() { interno.fechar() }
}

enum EnlaceSeguro {
    static let modoAcesso = "acesso"
    static let modoParear = "parear"

    private static func sorteio(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    /// Prova de quem conhece o código de acesso, presa a esta conversa (a transcrição entra na conta).
    static func prova(codigo: String, papel: String, transcricao: Data) -> Data {
        let msg = Array("deck-ble-prova-v1|\(papel)|".utf8) + Array(transcricao)
        return Data(ProvaCabo.hmacSHA256(chave: Array(codigo.utf8), mensagem: msg))
    }

    private static func iguais(_ a: Data, _ b: Data) -> Bool { ProvaCabo.igual(ProvaCabo.hex([UInt8](a)), ProvaCabo.hex([UInt8](b))) }

    /// Duas chaves, uma por direção, amarradas à transcrição. No modo acesso o código também entra na conta.
    private static func chaves(_ z: SharedSecret, _ transcricao: Data, codigo: String?) -> (iphoneParaMac: SymmetricKey, macParaIphone: SymmetricKey) {
        func derivar(_ rotulo: String) -> SymmetricKey {
            z.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcricao, sharedInfo: Data("deck-ble-v1|\(rotulo)|\(codigo ?? "")".utf8), outputByteCount: 32)
        }
        return (derivar("iphone-para-mac"), derivar("mac-para-iphone"))
    }

    private static func chavePublica(_ d: Data?) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let d, d.count == 32, let k = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: d) else { throw ErroEnlace.protocolo("chave inválida") }
        return k
    }

    private static func nonceValido(_ d: Data?) throws -> Data {
        guard let d, d.count == 16 else { throw ErroEnlace.protocolo("nonce inválido") }
        return d
    }

    // MARK: Mac

    struct ConfigServidor: Sendable {
        var nomeMac: String
        /// Os códigos de acesso que valem agora (o atual e, durante a folga do rodízio, o anterior).
        var chaves: @Sendable () -> [String]
        var codigoAcesso: @Sendable () -> String
        /// Pareamento: mostra o código na tela do Mac e devolve a decisão da pessoa. Pode esperar.
        var decidir: @Sendable (_ iphone: String, _ codigo: String) -> Bool
        var prazoDoAperto: TimeInterval = 10
        /// Quanto esperar o iPhone confirmar depois de o Mac permitir.
        var prazoDoIphone: TimeInterval = 120
    }

    /// O nome do iPhone chega pelo ar, então não é confiável: quebra de linha, ESC e marcas invisíveis ou de direção
    /// poderiam forjar o texto do pedido de pareamento na tela e no log do Mac. Fica só o que se lê, em até 60 caracteres.
    static func nomeLimpo(_ bruto: String?) -> String {
        var saida = String.UnicodeScalarView()
        var espacoPendente = false
        for u in (bruto ?? "").unicodeScalars {
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                espacoPendente = !saida.isEmpty
            case .spaceSeparator:
                espacoPendente = !saida.isEmpty
            default:
                if espacoPendente { saida.append(" "); espacoPendente = false }
                saida.append(u)
            }
        }
        let limpo = String(String(saida).prefix(60)).trimmingCharacters(in: .whitespaces)
        return limpo.isEmpty ? "iPhone" : limpo
    }

    /// Lado do Mac. Bloqueia até o fio estar cifrado e autenticado. Lança se o outro lado não prova quem é.
    static func servir(_ fluxo: FluxoBytes, _ cfg: ConfigServidor) throws -> FluxoCifrado {
        var vigia = Vigia(fluxo, cfg.prazoDoAperto)
        defer { vigia.cancelar() }
        guard let ola = QuadroEnlace.ler(fluxo), ola.t == "i" else { throw ErroEnlace.protocolo("sem abertura") }
        let privada = Curve25519.KeyAgreement.PrivateKey()
        let minhaChave = privada.publicKey.rawRepresentation
        let meuNonce = sorteio(16)

        if ola.m == modoAcesso {
            let chaveIphone = try chavePublica(ola.a), nonceIphone = try nonceValido(ola.b)
            guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "m", a: minhaChave, b: meuNonce, n: cfg.nomeMac)) else { throw ErroEnlace.protocolo("fio caiu") }
            let t = Sas.transcricao(modo: modoAcesso, chaveIphone: chaveIphone.rawRepresentation, nonceIphone: nonceIphone, chaveMac: minhaChave, nonceMac: meuNonce, nomeMac: cfg.nomeMac)
            guard let p = QuadroEnlace.ler(fluxo), p.t == "p", let prova = p.a else { throw ErroEnlace.protocolo("sem prova") }
            // Confere contra todos os códigos que valem, sem parar no primeiro que bate.
            var certo: String?
            for c in cfg.chaves() where iguais(prova, Self.prova(codigo: c, papel: "i", transcricao: t)) { certo = c }
            guard let codigo = certo else {
                _ = QuadroEnlace.escrever(fluxo, MsgEnlace(t: "x"))
                throw ErroEnlace.naoPareado
            }
            guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "q", a: Self.prova(codigo: codigo, papel: "m", transcricao: t))) else { throw ErroEnlace.protocolo("fio caiu") }
            let z = try privada.sharedSecretFromKeyAgreement(with: chaveIphone)
            let k = chaves(z, t, codigo: codigo)
            return FluxoCifrado(interno: fluxo, envio: k.macParaIphone, recebe: k.iphoneParaMac)
        }

        guard ola.m == modoParear else { throw ErroEnlace.protocolo("modo desconhecido") }
        // O Mac se compromete com a chave antes de ver a do iPhone.
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "c", a: Sas.compromisso(chavePublica: minhaChave, nonce: meuNonce), n: cfg.nomeMac)) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let k = QuadroEnlace.ler(fluxo), k.t == "k" else { throw ErroEnlace.protocolo("sem chave do iPhone") }
        let chaveIphone = try chavePublica(k.a), nonceIphone = try nonceValido(k.b)
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "m", a: minhaChave, b: meuNonce)) else { throw ErroEnlace.protocolo("fio caiu") }
        let t = Sas.transcricao(modo: modoParear, chaveIphone: chaveIphone.rawRepresentation, nonceIphone: nonceIphone, chaveMac: minhaChave, nonceMac: meuNonce, nomeMac: cfg.nomeMac)
        let z = try privada.sharedSecretFromKeyAgreement(with: chaveIphone)
        let ch = chaves(z, t, codigo: nil)
        let cifrado = FluxoCifrado(interno: fluxo, envio: ch.macParaIphone, recebe: ch.iphoneParaMac)

        // Daqui para a frente quem manda é a pessoa: o prazo do aperto de mão não vale para ela.
        vigia.cancelar()
        vigia = Vigia(fluxo, cfg.prazoDoIphone + 120)
        let nomeIphone = nomeLimpo(k.n)
        guard cfg.decidir(nomeIphone, Sas.digitos(t)) else {
            _ = QuadroEnlace.escrever(cifrado, MsgEnlace(t: "nao"))
            throw ErroEnlace.recusado("O pareamento foi recusado no Mac.")
        }
        guard let ok = QuadroEnlace.ler(cifrado), ok.t == "ok" else { throw ErroEnlace.recusado("O iPhone não confirmou o código.") }
        guard QuadroEnlace.escrever(cifrado, MsgEnlace(t: "acesso", n: cfg.codigoAcesso())) else { throw ErroEnlace.protocolo("fio caiu") }
        return cifrado
    }

    // MARK: iPhone

    /// Um pareamento esperando a conferência do código: o fio já está cifrado, e o código de acesso só vem
    /// depois de a pessoa confirmar nas duas telas.
    struct Pareando {
        var fluxo: FluxoCifrado
        var codigo: String
        var nomeMac: String
    }

    /// Lado do iPhone, iPhone já pareado. Devolve o fio cifrado e o nome do Mac.
    static func entrar(_ fluxo: FluxoBytes, codigoAcesso: String, prazo: TimeInterval = 10) throws -> (fluxo: FluxoCifrado, nomeMac: String) {
        let vigia = Vigia(fluxo, prazo)
        defer { vigia.cancelar() }
        let privada = Curve25519.KeyAgreement.PrivateKey()
        let minhaChave = privada.publicKey.rawRepresentation
        let meuNonce = sorteio(16)
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "i", m: modoAcesso, a: minhaChave, b: meuNonce)) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let r = QuadroEnlace.ler(fluxo), r.t == "m", let nome = r.n, !nome.isEmpty else { throw ErroEnlace.protocolo("sem resposta do Mac") }
        let chaveMac = try chavePublica(r.a), nonceMac = try nonceValido(r.b)
        let t = Sas.transcricao(modo: modoAcesso, chaveIphone: minhaChave, nonceIphone: meuNonce, chaveMac: chaveMac.rawRepresentation, nonceMac: nonceMac, nomeMac: nome)
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "p", a: prova(codigo: codigoAcesso, papel: "i", transcricao: t))) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let q = QuadroEnlace.ler(fluxo) else { throw ErroEnlace.protocolo("sem prova do Mac") }
        if q.t == "x" { throw ErroEnlace.naoPareado }
        guard q.t == "q", let provaMac = q.a, iguais(provaMac, prova(codigo: codigoAcesso, papel: "m", transcricao: t)) else {
            throw ErroEnlace.protocolo("o Mac não provou que conhece o código")
        }
        let z = try privada.sharedSecretFromKeyAgreement(with: chaveMac)
        let k = chaves(z, t, codigo: codigoAcesso)
        return (FluxoCifrado(interno: fluxo, envio: k.iphoneParaMac, recebe: k.macParaIphone), nome)
    }

    /// Lado do iPhone, iPhone novo: troca as chaves e devolve os 6 dígitos para a pessoa conferir.
    static func iniciarPareamento(_ fluxo: FluxoBytes, nomeDoIphone: String, prazo: TimeInterval = 10) throws -> Pareando {
        let vigia = Vigia(fluxo, prazo)
        defer { vigia.cancelar() }
        let privada = Curve25519.KeyAgreement.PrivateKey()
        let minhaChave = privada.publicKey.rawRepresentation
        let meuNonce = sorteio(16)
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "i", m: modoParear)) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let c = QuadroEnlace.ler(fluxo), c.t == "c", let compromisso = c.a, let nome = c.n, !nome.isEmpty else { throw ErroEnlace.protocolo("sem compromisso do Mac") }
        guard QuadroEnlace.escrever(fluxo, MsgEnlace(t: "k", a: minhaChave, b: meuNonce, n: nomeDoIphone)) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let m = QuadroEnlace.ler(fluxo), m.t == "m" else { throw ErroEnlace.protocolo("sem chave do Mac") }
        let chaveMac = try chavePublica(m.a), nonceMac = try nonceValido(m.b)
        // O Mac se comprometeu antes de ver a minha chave: se agora mostra outra, tem alguém no meio.
        guard iguais(compromisso, Sas.compromisso(chavePublica: chaveMac.rawRepresentation, nonce: nonceMac)) else {
            throw ErroEnlace.protocolo("o Mac mudou a chave depois de se comprometer")
        }
        let t = Sas.transcricao(modo: modoParear, chaveIphone: minhaChave, nonceIphone: meuNonce, chaveMac: chaveMac.rawRepresentation, nonceMac: nonceMac, nomeMac: nome)
        let z = try privada.sharedSecretFromKeyAgreement(with: chaveMac)
        let k = chaves(z, t, codigo: nil)
        return Pareando(fluxo: FluxoCifrado(interno: fluxo, envio: k.iphoneParaMac, recebe: k.macParaIphone), codigo: Sas.digitos(t), nomeMac: nome)
    }

    /// A pessoa respondeu no iPhone. Aceito: manda o ok e espera o Mac entregar o código de acesso.
    static func concluir(_ p: Pareando, aceito: Bool, prazo: TimeInterval = 120) throws -> String {
        guard aceito else {
            _ = QuadroEnlace.escrever(p.fluxo, MsgEnlace(t: "nao"))
            p.fluxo.fechar()
            throw ErroEnlace.recusado("Você recusou o pareamento.")
        }
        let vigia = Vigia(p.fluxo, prazo)
        defer { vigia.cancelar() }
        guard QuadroEnlace.escrever(p.fluxo, MsgEnlace(t: "ok")) else { throw ErroEnlace.protocolo("fio caiu") }
        guard let r = QuadroEnlace.ler(p.fluxo) else { throw ErroEnlace.protocolo("o Mac não respondeu") }
        if r.t == "nao" { throw ErroEnlace.recusado("O pareamento foi recusado no Mac.") }
        guard r.t == "acesso", let codigo = r.n, !codigo.isEmpty else { throw ErroEnlace.protocolo("resposta inesperada do Mac") }
        return codigo
    }
}
#endif
