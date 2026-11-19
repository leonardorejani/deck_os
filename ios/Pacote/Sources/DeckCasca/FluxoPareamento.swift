import Foundation

// As telas de pareamento do protótipo (prototipo/nativo.html): primeira abertura, lista de Macs,
// confirmar código, segunda via pelo cabo com código digitado e pronto. Este fluxo é a fonte da
// verdade: a página só desenha o estado e manda as ações.

public enum Etapa: String, Codable, Equatable, Sendable {
    case vazio, procurando, confirmar, pronto, cabo, codigo
    /// Pareado: a página mostra o painel (ou "Mac desconectado" enquanto não há canal).
    case painel
}

/// O que o pareamento está fazendo agora, para a tela mostrar na hora que o toque valeu. São as etapas reais do núcleo:
/// falar com o Mac até sair o código (`procurandoMac`, na lista) e esperar o Mac permitir (`pareando`, depois do "São iguais").
public enum Progresso: String, Codable, Equatable, Sendable {
    case procurandoMac, pareando
}

public struct EstadoPareamento: Codable, Equatable, Sendable {
    public var etapa: Etapa = .vazio
    public var macs: [MacEncontrado] = []
    /// Código de conferência com espaço no meio ("483 291"), só na etapa confirmar.
    public var codigo = ""
    public var nomeMac = ""
    public var via: TipoCanal?
    /// Há um passo do pareamento em andamento: a tela desabilita os toques e mostra o indicador.
    public var progresso: Progresso?
    /// O Mac que a pessoa tocou na lista (o do progresso, ou o que falhou).
    public var alvoId: String?
    /// Por que o último pareamento não deu certo, em português. A tela mostra com "Tentar de novo".
    public var falha: String?
}

public enum AcaoPareamento: Equatable, Sendable {
    case procurar
    case escolher(String)
    case confirmar(Bool)
    case cabo
    case voltarParaBluetooth
    case voltar
    case digitos(String)
    case abrirPainel
    case esquecer
}

@MainActor
public final class FluxoPareamento {
    public private(set) var estado = EstadoPareamento() {
        didSet { if estado != oldValue { aoMudar?(estado) } }
    }
    public var aoMudar: ((EstadoPareamento) -> Void)?
    public var aoPareado: ((PareamentoFeito) -> Void)?

    private let pareador: Pareador
    private let cofre: Cofre
    private let permanenciaNoCabo: TimeInterval
    private let prazoParaAcharOMac: TimeInterval
    private let prazoParaOMacPermitir: TimeInterval
    private var busca: Task<Void, Never>?
    private var macEscolhido: MacEncontrado?
    private var macDoCabo: MacEncontrado?
    /// Sobe a cada mudança de etapa por ação da pessoa: resposta atrasada do pareador de uma etapa que
    /// já foi abandonada não pode sobrescrever a etapa atual.
    private var geracao = 0
    private var escolhendo = false
    private var confirmando = false

    /// `permanenciaNoCabo`: a tela "Procurando o Mac no cabo" fica pelo menos esse tempo antes de
    /// passar para o código (2,2 s no protótipo), para a troca de tela não piscar.
    /// `prazoParaAcharOMac`: quanto "Procurando o Mac..." pode durar (o Bluetooth tenta os dois sentidos, uns 30 s no pior caso).
    /// `prazoParaOMacPermitir`: quanto "Pareando..." espera o Mac permitir. O Mac desiste sozinho aos 120 s, então este vem logo depois.
    public init(pareador: Pareador, cofre: Cofre, permanenciaNoCabo: TimeInterval = 2.2,
                prazoParaAcharOMac: TimeInterval = 35, prazoParaOMacPermitir: TimeInterval = 125) {
        self.pareador = pareador
        self.cofre = cofre
        self.permanenciaNoCabo = permanenciaNoCabo
        self.prazoParaAcharOMac = prazoParaAcharOMac
        self.prazoParaOMacPermitir = prazoParaOMacPermitir
    }

    public func iniciar() {
        guard let guardado = cofre.ler() else {
            estado = EstadoPareamento()
            aoMudar?(estado)
            return
        }
        estado = EstadoPareamento(etapa: .painel, nomeMac: guardado.nomeMac)
        aoMudar?(estado)
    }

    /// Devolve o texto de erro para a página mostrar, ou nil se deu certo.
    public func tratar(_ acao: AcaoPareamento) async -> String? {
        switch acao {
        case .procurar, .voltarParaBluetooth:
            procurarPorBluetooth()
            // A lista já está na tela. Se o rádio não pode procurar, a pessoa lê o motivo no aviso de 4 segundos.
            let minha = geracao
            let aviso = await pareador.avisoDaProcura()
            return minha == geracao ? aviso : nil
        case .escolher(let id):
            return await escolher(id)
        case .confirmar(let ok):
            return await confirmar(ok)
        case .cabo, .voltar:
            procurarNoCabo()
            return nil
        case .digitos(let d):
            return await digitar(d)
        case .abrirPainel:
            if estado.etapa == .pronto { estado.etapa = .painel }
            return nil
        case .esquecer:
            parar()
            cofre.apagar()
            macEscolhido = nil
            macDoCabo = nil
            estado = EstadoPareamento()
            return nil
        }
    }

    // MARK: Bluetooth

    private func procurarPorBluetooth() {
        parar()
        estado = EstadoPareamento(etapa: .procurando, macs: estado.macs)
        busca = Task { [pareador] in
            for await lista in pareador.procurarPorBluetooth() {
                if Task.isCancelled { return }
                if estado.etapa == .procurando { estado.macs = lista }
            }
        }
    }

    private func escolher(_ id: String) async -> String? {
        guard !escolhendo, estado.etapa == .procurando, estado.progresso == nil, let mac = estado.macs.first(where: { $0.id == id }), mac.perto else { return nil }
        parar()
        let minha = geracao
        escolhendo = true
        defer { escolhendo = false }
        // O toque vale na hora: a tela já mostra "Procurando o Mac..." enquanto o núcleo fala com ele.
        estado.progresso = .procurandoMac
        estado.alvoId = id
        estado.falha = nil
        do {
            let pareador = self.pareador
            guard let codigo = try await Prazo.correr(prazoParaAcharOMac, { try await pareador.iniciar(com: mac) }, tarde: { _ in
                // Chegou depois de a tela desistir: solta a conversa para o Mac não ficar com um pedido pendurado.
                Task { _ = try? await pareador.concluir(aceito: false) }
            }) else { throw ErroPareamento.recusado("O Mac não respondeu a tempo. Confira se o Deck está aberto nele e tente de novo.") }
            guard minha == geracao else {
                // A pessoa saiu desta escolha (cabo, esquecer...) enquanto o Mac respondia: solta a conversa e não mexe na tela.
                _ = try? await pareador.concluir(aceito: false)
                return nil
            }
            macEscolhido = mac
            estado = EstadoPareamento(etapa: .confirmar, codigo: Self.formatar(codigo), nomeMac: mac.nome, via: .bluetooth, alvoId: id)
            return nil
        } catch {
            guard minha == geracao else { return nil }
            return falhar(error, alvo: id)
        }
    }

    /// Volta para a lista com o motivo na tela (e "Tentar de novo"). Devolve o mesmo texto para o aviso de 4 segundos.
    private func falhar(_ erro: Error, alvo: String?) -> String {
        let texto = Self.texto(erro)
        procurarPorBluetooth()
        estado.alvoId = alvo
        estado.falha = texto
        return texto
    }

    private func confirmar(_ ok: Bool) async -> String? {
        // Segundo toque em "São iguais" enquanto o primeiro ainda conclui: ignora, senão a falha do segundo desfaz o pareamento.
        guard estado.etapa == .confirmar, !confirmando else { return nil }
        confirmando = true
        defer { confirmando = false }
        if !ok {
            _ = try? await pareador.concluir(aceito: false)
            macEscolhido = nil
            estado = EstadoPareamento()
            return nil
        }
        let minha = geracao
        let alvo = macEscolhido?.id
        estado.progresso = .pareando
        do {
            let pareador = self.pareador
            guard let feito = try await Prazo.correr(prazoParaOMacPermitir, { try await pareador.concluir(aceito: true) }, tarde: { _ in })
            else { throw ErroPareamento.recusado("O Mac não permitiu a tempo. Toque em Permitir no Mac e tente de novo.") }
            guard minha == geracao else { return nil }
            finalizar(feito)
            return nil
        } catch {
            guard minha == geracao else { return nil }
            return falhar(error, alvo: alvo)
        }
    }

    // MARK: Cabo com código

    private func procurarNoCabo() {
        parar()
        macDoCabo = nil
        estado = EstadoPareamento(etapa: .cabo, via: .cabo)
        let entrou = Date()
        busca = Task { [pareador, permanenciaNoCabo] in
            for await mac in pareador.procurarNoCabo() {
                if Task.isCancelled { return }
                let falta = permanenciaNoCabo - Date().timeIntervalSince(entrou)
                if falta > 0 { try? await Task.sleep(nanoseconds: UInt64(falta * 1_000_000_000)) }
                if Task.isCancelled || estado.etapa != .cabo { return }
                macDoCabo = mac
                estado = EstadoPareamento(etapa: .codigo, nomeMac: mac.nome, via: .cabo)
                return
            }
        }
    }

    private func digitar(_ digitos: String) async -> String? {
        guard estado.etapa == .codigo, let mac = macDoCabo else { return nil }
        guard digitos.count == 6, digitos.allSatisfy({ ("0"..."9").contains($0) }) else { return "O código tem 6 dígitos." }
        estado.progresso = .pareando
        do {
            finalizar(try await pareador.parearComCodigo(mac, digitos))
            return nil
        } catch {
            if estado.etapa == .codigo { estado.progresso = nil }
            return Self.texto(error)
        }
    }

    // MARK: Fim

    private func finalizar(_ feito: PareamentoFeito) {
        parar()
        cofre.gravar(feito.pareado)
        estado = EstadoPareamento(etapa: .pronto, nomeMac: feito.pareado.nomeMac, via: feito.canal.tipo)
        aoPareado?(feito)
    }

    private func parar() {
        geracao += 1
        busca?.cancel()
        busca = nil
    }

    static func formatar(_ codigo: String) -> String {
        guard codigo.count == 6 else { return codigo }
        return codigo.prefix(3) + " " + codigo.suffix(3)
    }

    private static func texto(_ erro: Error) -> String {
        (erro as? ErroPareamento)?.mensagem ?? (erro as? ErroCifragemBluetooth)?.mensagem ?? "Não consegui parear. Tente de novo."
    }
}

/// Corre uma operação contra o relógio. Passou do prazo, devolve nil na hora (a operação segue por baixo e, se terminar, `tarde`
/// recebe o resultado). Existe porque as operações do núcleo (rádio, aperto de mão) não obedecem a cancelamento.
enum Prazo {
    private final class Unico<T: Sendable>: @unchecked Sendable {
        private let trava = NSLock()
        private var feito = false
        private var continuacao: CheckedContinuation<T?, Error>?
        private var relogio: Task<Void, Never>?

        init(_ c: CheckedContinuation<T?, Error>) { continuacao = c }
        func armar(_ r: Task<Void, Never>) { trava.withLock { relogio = r } }

        /// true quando este foi o primeiro a resolver.
        func resolver(_ r: Result<T?, Error>) -> Bool {
            let (c, t): (CheckedContinuation<T?, Error>?, Task<Void, Never>?) = trava.withLock {
                guard !feito else { return (nil, nil) }
                feito = true
                return (continuacao, relogio)
            }
            guard let c else { return false }
            t?.cancel()
            c.resume(with: r)
            return true
        }
    }

    static func correr<T: Sendable>(_ segundos: TimeInterval, _ operacao: @escaping @Sendable () async throws -> T,
                                    tarde: @escaping @Sendable (T) -> Void) async throws -> T? {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T?, Error>) in
            let unico = Unico<T>(c)
            unico.armar(Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, segundos) * 1_000_000_000))
                _ = unico.resolver(.success(nil))
            })
            Task {
                do {
                    let v = try await operacao()
                    if !unico.resolver(.success(v)) { tarde(v) }
                } catch {
                    _ = unico.resolver(.failure(error))
                }
            }
        }
    }
}
