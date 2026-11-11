import Foundation

// As telas de pareamento do protótipo (prototipo/nativo.html): primeira abertura, lista de Macs,
// confirmar código, segunda via pelo cabo com código digitado e pronto. Este fluxo é a fonte da
// verdade: a página só desenha o estado e manda as ações.

public enum Etapa: String, Codable, Equatable, Sendable {
    case vazio, procurando, confirmar, pronto, cabo, codigo
    /// Pareado: a página mostra o painel (ou "Mac desconectado" enquanto não há canal).
    case painel
}

public struct EstadoPareamento: Codable, Equatable, Sendable {
    public var etapa: Etapa = .vazio
    public var macs: [MacEncontrado] = []
    /// Código de conferência com espaço no meio ("483 291"), só na etapa confirmar.
    public var codigo = ""
    public var nomeMac = ""
    public var via: TipoCanal?
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
    public init(pareador: Pareador, cofre: Cofre, permanenciaNoCabo: TimeInterval = 2.2) {
        self.pareador = pareador
        self.cofre = cofre
        self.permanenciaNoCabo = permanenciaNoCabo
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
        guard !escolhendo, estado.etapa == .procurando, let mac = estado.macs.first(where: { $0.id == id }), mac.perto else { return nil }
        parar()
        let minha = geracao
        escolhendo = true
        defer { escolhendo = false }
        do {
            let codigo = try await pareador.iniciar(com: mac)
            guard minha == geracao else {
                // A pessoa saiu desta escolha (cabo, esquecer...) enquanto o Mac respondia: solta a conversa e não mexe na tela.
                _ = try? await pareador.concluir(aceito: false)
                return nil
            }
            macEscolhido = mac
            estado = EstadoPareamento(etapa: .confirmar, codigo: Self.formatar(codigo), nomeMac: mac.nome, via: .bluetooth)
            return nil
        } catch {
            guard minha == geracao else { return nil }
            procurarPorBluetooth()
            return Self.texto(error)
        }
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
        do {
            finalizar(try await pareador.concluir(aceito: true))
            return nil
        } catch {
            procurarPorBluetooth()
            return Self.texto(error)
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
        do {
            finalizar(try await pareador.parearComCodigo(mac, digitos))
            return nil
        } catch {
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
        (erro as? ErroPareamento)?.mensagem ?? "Não consegui parear. Tente de novo."
    }
}
