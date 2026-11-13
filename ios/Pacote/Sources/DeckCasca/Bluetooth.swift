import Foundation

#if canImport(CryptoKit)

// O canal pelo Bluetooth (fase 7). Igual ao cabo, só leva pedido e resposta, e o roteador do Mac não sabe a
// diferença. O que muda: o fio é aberto ao ar, então só vale depois do aperto de mão cifrado (EnlaceSeguro), e é
// lento (a vazão medida em docs/provas/fase-7-bluetooth.md), então o Mac manda a capa pequena. Duas entradas:
// pareamento (iPhone novo, com o código de 6 dígitos nas duas telas) e reconexão (iPhone já pareado, prova o
// código de acesso). Depois de pareado, o iPhone mantém o Bluetooth conectado mesmo com o cabo plugado, para a
// troca de canal ser instantânea quando o cabo sai.

/// Mantém a conexão Bluetooth com o Mac e conduz o pareamento principal.
public final class GerenteBluetooth: @unchecked Sendable {
    /// Espera entre tentativas de reconectar. Cresce até o teto e volta ao mínimo quando conecta.
    static let esperaMinima: TimeInterval = 1
    static let esperaMaxima: TimeInterval = 15
    /// Rejeitado pelo Mac (código de acesso que ele não reconhece): não adianta insistir a cada segundo.
    static let esperaSeNaoPareado: TimeInterval = 30
    /// Quantas vezes seguidas o Mac já conhecido pode recusar este iPhone antes de o pareamento valer como acabado.
    /// Uma só poderia ser um instante da troca do código de acesso: a segunda, logo em seguida, confirma.
    static let recusasParaEsquecer = 2
    /// Tempo para a conexão direta no Mac conhecido (pelo id guardado). O id vale para o endereço que o iPhone viu da
    /// última vez: se o Mac trocou de endereço ou parou de anunciar, o connect do iOS não falha, só fica esperando. Passado
    /// o prazo, o app larga o id e procura o serviço do Deck no ar.
    static let prazoDaConexaoDireta: TimeInterval = 6
    /// Quanto a procura pelo serviço espera algum Mac aparecer.
    static let prazoDaProcura: TimeInterval = 8
    /// Rodadas seguidas com a cifragem do enlace falhando (ErroCifragemBluetooth) antes de a tela trocar "procurando" pelo
    /// que a pessoa faz para resolver. Daí em diante o app tenta com calma, para voltar sozinho quando ela resolver.
    static let cifragensParaAvisar = 3
    static let esperaSeCifragemFalha: TimeInterval = 30
    /// Sentido invertido (12/11/2026, RadioPeriferico.swift): depois de a cifragem falhar no sentido antigo, o iPhone para de
    /// conectar no Mac por tanto tempo (a rodada) e fica só anunciando, esperando o Mac conectar nele.
    static let pausaDoSentidoAntigo: TimeInterval = 60
    /// Com o sentido invertido, o aviso de cifragem só aparece quando nenhum dos dois sentidos conectou por tanto tempo
    /// desde a primeira falha de cifragem.
    static let avisoDeCifragemApos: TimeInterval = 60
    /// No pareamento, quanto o iPhone espera o Mac conectar nele depois de o sentido antigo falhar.
    static let esperaDoMacNoPareamento: TimeInterval = 15
    static let textoEsperandoOMac = "Esperando o Mac conectar pelo Bluetooth."

    private struct Pendente {
        var pareando: EnlaceSeguro.Pareando
        var mac: MacEncontrado
    }

    private let radio: RadioBle
    /// O iPhone como periférico (sentido invertido). Sem ele, só o sentido antigo, como antes de 12/11/2026.
    private let periferico: PerifericoBle?
    private let pausaDoAntigo: TimeInterval
    private let avisoDeCifragem: TimeInterval
    private let esperaDoMacNoPareamento: TimeInterval
    private let cofre: Cofre
    private let nomeDoIphone: String
    private let esperaEntreTentativas: (TimeInterval) -> TimeInterval
    private let prazoDireto: TimeInterval
    private let prazoProcura: TimeInterval
    private let log: @Sendable (String) -> Void
    private let trava = NSLock()
    private var conexao: ConexaoCabo?
    private var macAtual: MacEncontrado?
    private var laco: Task<Void, Never>?
    private var pendente: Pendente?
    private var aoMudarBt: (@Sendable (MacEncontrado?) -> Void)?
    private var aoNaoReconhecidoBt: (@Sendable () -> Void)?
    private var aoMudarSituacaoBt: (@Sendable (String?) -> Void)?
    private var _situacao: String?
    /// Sobe a cada parar(): um laço antigo que ainda está terminando não mexe no novo.
    private var geracao = 0
    /// O sentido antigo está parado até esta hora (a cifragem falhou nele nesta rodada).
    private var antigoParadoAte: Date?
    /// Primeira falha de cifragem desde a última conexão: conta o tempo até o aviso.
    private var cifragemDesde: Date?
    /// O pareamento (iPhone novo) esperando o Mac conectar pelo sentido invertido.
    private var esperaInvertida: (@Sendable (FluxoBytes?) -> Void)?

    #if canImport(CoreBluetooth)
    /// Tudo que o Bluetooth anota vai também para o diário (Documents/bluetooth.log), além do `log` de quem criou.
    public convenience init(cofre: Cofre, nomeDoIphone: String, diario: DiarioBluetooth = .padrao, log: @escaping @Sendable (String) -> Void = { _ in }) {
        let dupla: @Sendable (String) -> Void = { log($0); diario.anotar($0) }
        dupla("bluetooth: app aberto, diário iniciado")
        self.init(radio: RadioCentral(log: dupla), periferico: RadioPerifericoIphone(log: dupla), cofre: cofre, nomeDoIphone: nomeDoIphone, log: dupla)
    }
    #endif

    init(radio: RadioBle, periferico: PerifericoBle? = nil, cofre: Cofre, nomeDoIphone: String, esperaEntreTentativas: @escaping (TimeInterval) -> TimeInterval = { $0 },
         prazoDaConexaoDireta: TimeInterval = GerenteBluetooth.prazoDaConexaoDireta, prazoDaProcura: TimeInterval = GerenteBluetooth.prazoDaProcura,
         pausaDoSentidoAntigo: TimeInterval = GerenteBluetooth.pausaDoSentidoAntigo, avisoDeCifragemApos: TimeInterval = GerenteBluetooth.avisoDeCifragemApos,
         esperaDoMacNoPareamento: TimeInterval = GerenteBluetooth.esperaDoMacNoPareamento,
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.prazoDireto = prazoDaConexaoDireta
        self.prazoProcura = prazoDaProcura
        self.radio = radio
        self.periferico = periferico
        self.pausaDoAntigo = pausaDoSentidoAntigo
        self.avisoDeCifragem = avisoDeCifragemApos
        self.esperaDoMacNoPareamento = esperaDoMacNoPareamento
        self.cofre = cofre
        self.nomeDoIphone = nomeDoIphone
        self.esperaEntreTentativas = esperaEntreTentativas
        self.log = log
        periferico?.aoAbrir { [weak self] fluxo, rotulo in self?.macConectou(fluxo, rotulo) }
    }

    /// Chamado quando o Mac se apresenta pelo Bluetooth (com ele) e quando o fio cai (com nil).
    public func aoMudar(_ f: @escaping @Sendable (MacEncontrado?) -> Void) {
        trava.withLock { aoMudarBt = f }
    }

    public func aoNaoReconhecido(_ f: @escaping @Sendable () -> Void) {
        trava.withLock { aoNaoReconhecidoBt = f }
    }

    public var mac: MacEncontrado? { trava.withLock { macAtual } }

    /// O que a tela de conexão mostra enquanto o Bluetooth não conecta ("Procurando o Mac... tentativa 3"), ou nil quando
    /// não há o que dizer (conectado). Chamado a cada tentativa.
    public func aoMudarSituacao(_ f: @escaping @Sendable (String?) -> Void) {
        trava.withLock { aoMudarSituacaoBt = f }
    }

    public var situacao: String? { trava.withLock { _situacao } }

    private func situar(_ texto: String?) {
        let aviso: (@Sendable (String?) -> Void)? = trava.withLock {
            guard _situacao != texto else { return nil }
            _situacao = texto
            return aoMudarSituacaoBt
        }
        aviso?(texto)
    }

    /// Por que o Bluetooth não pode ser usado agora (desligado, sem permissão), ou nil.
    var indisponivel: String? { radio.indisponivel }
    var radioPronto: Bool { radio.pronto }

    // MARK: Reconexão (iPhone já pareado)

    /// Liga a reconexão automática se já tem pareamento. Sem pareamento não faz nada (nem pede permissão de Bluetooth).
    public func iniciar() {
        guard cofre.ler() != nil else { return }
        let ja: Bool = trava.withLock {
            if laco != nil { return true }
            geracao += 1
            let g = geracao
            laco = Task { [self] in await manter(g) }
            return false
        }
        if ja { return }
        log("bluetooth: procurando o Mac pareado")
    }

    /// Pareou (ou esqueceu) agora: liga ou desliga a reconexão conforme o cofre.
    public func reavaliar() {
        if cofre.ler() != nil { iniciar() } else { parar() }
    }

    public func parar() {
        let (l, c): (Task<Void, Never>?, ConexaoCabo?) = trava.withLock {
            let r = (laco, conexao)
            laco = nil
            geracao += 1
            antigoParadoAte = nil
            cifragemDesde = nil
            return r
        }
        l?.cancel()
        c?.fechar()
        conferirAnuncio()
    }

    /// O app voltou ao primeiro plano: o iOS pode ter derrubado a conexão em segundo plano. Rodada nova: o sentido antigo
    /// volta a ser tentado, e o anúncio (que o iOS para em segundo plano) é conferido.
    public func retomar() {
        trava.withLock { antigoParadoAte = nil }
        iniciar()
        conferirAnuncio()
    }

    // MARK: Sentido invertido (o Mac conecta no iPhone)

    /// Anuncia enquanto há quem possa usar o Mac (pareado com a reconexão ligada, ou um pareamento esperando) e não há
    /// conexão de dados pelo Bluetooth.
    private func conferirAnuncio() {
        guard let periferico else { return }
        let pareado = cofre.ler() != nil
        let ligado = trava.withLock { conexao == nil && ((laco != nil && pareado) || esperaInvertida != nil) }
        periferico.anunciar(ligado)
    }

    /// Um Mac conectou no iPhone pelo sentido invertido. Com o pareamento esperando, o fio é dele. Pareado e sem conexão,
    /// aperta a mão com o código de acesso. Com o outro sentido já em uso, ou sem pareamento, fecha.
    private func macConectou(_ fluxo: FluxoBytes, _ rotulo: String) {
        log("bluetooth: o Mac \(rotulo) conectou no iPhone (sentido invertido)")
        if let espera = trava.withLock({ () -> (@Sendable (FluxoBytes?) -> Void)? in let e = esperaInvertida; esperaInvertida = nil; return e }) {
            espera(fluxo)
            return
        }
        guard let pareado = cofre.ler(), trava.withLock({ laco != nil }) else {
            log("bluetooth: \(rotulo) conectou sem pareamento em curso neste iPhone, fechei")
            return fluxo.fechar()
        }
        guard trava.withLock({ conexao == nil }) else {
            log("bluetooth: \(rotulo) conectou com o outro sentido já em uso, fechei")
            return fluxo.fechar()
        }
        Task.detached { [self] in
            do {
                let entrada = try EnlaceSeguro.entrar(fluxo, codigoAcesso: pareado.codigoAcesso)
                let nova = ConexaoCabo(fluxo: entrada.fluxo, segredo: { nil }, confiavel: true, nomeDoCanal: "O Bluetooth")
                if reivindicar(nova, id: rotulo, nome: entrada.nomeMac) {
                    log("bluetooth: Mac \"\(entrada.nomeMac)\" conectado (cifrado), pelo sentido invertido")
                } else {
                    log("bluetooth: aperto de mão invertido com \(rotulo) fechou, mas o outro sentido chegou antes: fechei este")
                    entrada.fluxo.fechar()
                }
            } catch {
                // Pode ser outro Mac com o Deck por perto: não conta como o Mac deste iPhone recusando.
                log("bluetooth: aperto de mão invertido com \(rotulo) não passou: \(error)")
                fluxo.fechar()
            }
        }
    }

    /// Fica com a conexão só se nenhum outro sentido fechou o aperto de mão antes. Sem duas sessões ao mesmo tempo.
    private func reivindicar(_ nova: ConexaoCabo, id: String, nome: String) -> Bool {
        let ok: Bool = trava.withLock {
            guard conexao == nil, laco != nil else { return false }
            conexao = nova
            antigoParadoAte = nil
            cifragemDesde = nil
            return true
        }
        guard ok else { return false }
        situar(nil)
        conferirAnuncio()
        nova.iniciar(aoOla: { [self] c in apresentou(c, id: id, nome: nome) }, aoFechar: { [self] c in caiu(c) })
        return true
    }

    /// O que a tela diz enquanto o sentido antigo descansa: esperando o Mac, ou o aviso de cifragem se nada conectou por
    /// tempo demais desde a primeira falha.
    private func situarEspera() {
        let desde = trava.withLock { cifragemDesde }
        if let desde, Date().timeIntervalSince(desde) >= avisoDeCifragem {
            situar(ErroCifragemBluetooth.mensagem)
        } else {
            situar(Self.textoEsperandoOMac)
        }
    }

    /// Pareamento: anuncia e espera o Mac conectar no iPhone. nil no prazo.
    private func esperarMacNoIphone(_ prazo: TimeInterval) async -> FluxoBytes? {
        final class UmaVez: @unchecked Sendable {
            private let trava = NSLock()
            private var c: CheckedContinuation<FluxoBytes?, Never>?
            init(_ c: CheckedContinuation<FluxoBytes?, Never>) { self.c = c }
            /// false se já tinha sido entregue (o fio que chegou tarde precisa ser fechado por quem chamou).
            func entregar(_ f: FluxoBytes?) -> Bool {
                let x: CheckedContinuation<FluxoBytes?, Never>? = trava.withLock { let y = c; c = nil; return y }
                x?.resume(returning: f)
                return x != nil
            }
        }
        let resultado: FluxoBytes? = await withCheckedContinuation { (c: CheckedContinuation<FluxoBytes?, Never>) in
            let u = UmaVez(c)
            trava.withLock { esperaInvertida = { f in if !u.entregar(f) { f?.fechar() } } }
            conferirAnuncio()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(prazo * 1_000_000_000))
                _ = u.entregar(nil)
            }
        }
        trava.withLock { esperaInvertida = nil }
        conferirAnuncio()
        return resultado
    }

    private func manter(_ g: Int) async {
        var espera = Self.esperaMinima
        /// Macs que já disseram não conhecer este iPhone nesta rodada de procura (quando o id ainda não foi guardado).
        var recusados = Set<String>()
        var recusasSeguidas = 0
        var cifragensSeguidas = 0
        var tentativa = 0
        defer { trava.withLock { if geracao == g { laco = nil } } }
        while !Task.isCancelled, trava.withLock({ geracao == g }) {
            guard let pareado = cofre.ler() else { break }
            if trava.withLock({ conexao != nil }) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            // Sem conexão: anuncia para o Mac poder conectar no iPhone (sentido invertido), junto com o sentido antigo.
            conferirAnuncio()
            if let ate = trava.withLock({ antigoParadoAte }), Date() < ate {
                // A cifragem falhou no sentido antigo nesta rodada: só anuncia, e a tela diz que espera o Mac.
                situarEspera()
                try? await Task.sleep(nanoseconds: UInt64(min(0.5, max(0.05, ate.timeIntervalSinceNow)) * 1_000_000_000))
                continue
            }
            var alvoAtual: String?
            var viaProcura = false
            tentativa += 1
            radio.confiarNoNome(pareado.nomeMac)
            log("bluetooth: tentativa \(tentativa) (id guardado \(pareado.idBluetooth.map { String($0.prefix(8)) } ?? "nenhum"), Mac pareado \"\(pareado.nomeMac)\", recusados \(recusados.count), rádio pronto=\(radio.pronto))")
            if let motivo = radio.indisponivel { situar(motivo) } else { situar("Procurando o Mac pelo Bluetooth. Tentativa \(tentativa).") }
            do {
                let (id, fluxo, achadoPelaProcura) = try await conectarNoMac(pareado, excluindo: recusados)
                alvoAtual = id
                viaProcura = achadoPelaProcura
                let entrada: (fluxo: FluxoCifrado, nomeMac: String)
                do {
                    entrada = try await Task.detached { try EnlaceSeguro.entrar(fluxo, codigoAcesso: pareado.codigoAcesso) }.value
                } catch {
                    log("bluetooth: aperto de mão com \(id.prefix(8)) não passou: \(error)")
                    fluxo.fechar()
                    throw error
                }
                recusados = []
                recusasSeguidas = 0
                cifragensSeguidas = 0
                cofre.guardarBluetooth(id)
                tentativa = 0
                espera = Self.esperaMinima
                // O sentido invertido pode ter fechado o aperto de mão enquanto este conectava: o primeiro vale.
                guard reivindicar(ConexaoCabo(fluxo: entrada.fluxo, segredo: { nil }, confiavel: true, nomeDoCanal: "O Bluetooth"), id: id, nome: entrada.nomeMac) else {
                    log("bluetooth: aperto de mão com \(id.prefix(8)) fechou, mas o sentido invertido chegou antes: fechei este")
                    entrada.fluxo.fechar()
                    continue
                }
                log("bluetooth: Mac \"\(entrada.nomeMac)\" conectado (cifrado)\(viaProcura ? ", achado pela procura" : "")")
            } catch ErroEnlace.naoPareado {
                // Os dois lados não concordam no código de acesso (o Mac refez o pareamento, por exemplo).
                log("bluetooth: o Mac não reconhece este iPhone")
                if let id = alvoAtual, pareado.idBluetooth == nil || (viaProcura && id != pareado.idBluetooth) {
                    // Pareou pelo cabo e ainda não sabe qual é o Mac (ou o id guardado não respondeu e este veio da procura):
                    // pode ser outro com o Deck por perto. Tenta o próximo já.
                    recusados.insert(id)
                    espera = Self.esperaMinima
                } else {
                    // Mac já conhecido que não reconhece o código: o Mac desconectou este iPhone. Sem canal nenhum, a
                    // página nunca leva um 401 e ficaria em "Mac desconectado" para sempre. Confirma uma vez e avisa.
                    recusasSeguidas += 1
                    if recusasSeguidas >= Self.recusasParaEsquecer {
                        log("bluetooth: o Mac recusou este iPhone \(recusasSeguidas) vezes, o pareamento acabou")
                        let aviso = trava.withLock { aoNaoReconhecidoBt }
                        aviso?()
                        return
                    }
                    espera = Self.esperaMinima
                }
            } catch let erro as ErroCifragemBluetooth where periferico != nil {
                // Com o sentido invertido, a falha de cifragem no antigo não se repete nesta rodada: o iPhone fica só
                // anunciando e o Mac conecta nele. O aviso de cifragem só vem se nada conectar por tempo demais.
                let ate = Date().addingTimeInterval(pausaDoAntigo)
                trava.withLock {
                    antigoParadoAte = ate
                    if cifragemDesde == nil { cifragemDesde = Date() }
                }
                log("bluetooth: a cifragem do enlace falhou no sentido antigo (CBError \(erro.codigo)). Paro de conectar no Mac por \(Int(pausaDoAntigo)) s e fico só anunciando, esperando o Mac conectar no iPhone")
                situarEspera()
                espera = Self.esperaMinima
                continue
            } catch let erro as ErroCifragemBluetooth {
                cifragensSeguidas += 1
                if cifragensSeguidas >= Self.cifragensParaAvisar {
                    log("bluetooth: a cifragem do enlace falhou \(cifragensSeguidas) rodadas seguidas (CBError \(erro.codigo)): aviso na tela e nova tentativa só a cada \(Int(Self.esperaSeCifragemFalha)) s")
                    situar(erro.mensagem)
                    espera = Self.esperaSeCifragemFalha
                } else {
                    log("bluetooth: tentativa \(tentativa) falhou na cifragem do enlace (CBError \(erro.codigo)), \(cifragensSeguidas) de \(Self.cifragensParaAvisar) antes de avisar")
                    espera = min(espera * 2, Self.esperaMaxima)
                    situar("Não achei o Mac pelo Bluetooth. Tentando de novo. Tentativa \(tentativa).")
                }
            } catch ErroSemCandidato.todosRecusaram where pareado.idBluetooth != nil {
                // O Mac conhecido não respondeu no id guardado e só há outros Macs por perto, que não conhecem este iPhone.
                // Não é o Mac dele recusando: não conta para esquecer o pareamento.
                recusados = []
                espera = Self.esperaMinima
            } catch ErroSemCandidato.todosRecusaram {
                // Pareado só pelo cabo (id do Bluetooth ainda desconhecido): cada Mac por perto já recusou este iPhone nesta
                // rodada. Duas rodadas seguidas assim e o pareamento acabou, senão a tela fica presa em "Mac desconectado".
                recusasSeguidas += 1
                if recusasSeguidas >= Self.recusasParaEsquecer {
                    log("bluetooth: todos os Macs por perto recusaram este iPhone \(recusasSeguidas) vezes, o pareamento acabou")
                    let aviso = trava.withLock { aoNaoReconhecidoBt }
                    aviso?()
                    return
                }
                recusados = []
                espera = Self.esperaSeNaoPareado
            } catch {
                log("bluetooth: tentativa \(tentativa) falhou: \(error)")
                espera = min(espera * 2, Self.esperaMaxima)
                if let motivo = radio.indisponivel { situar(motivo) } else if !(error is CancellationError) {
                    situar("Não achei o Mac pelo Bluetooth. Tentando de novo. Tentativa \(tentativa).")
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(esperaEntreTentativas(espera) * 1_000_000_000))
        }
    }

    private enum ErroSemCandidato: Error { case todosRecusaram }

    /// Onde conectar: o Mac que já foi usado, ou um dos que o rádio achar com o Deck. O macOS não anuncia o nome
    /// do Deck (o iPhone lê o do sistema), então o nome só desempata e a ordem é o sinal, do mais forte ao mais fraco.
    /// `excluindo` são os que já recusaram este iPhone, para a reconexão chegar ao Mac certo quando há mais de um.
    private func conectarNoMac(_ pareado: Pareado, excluindo recusados: Set<String>) async throws -> (String, FluxoBytes, Bool) {
        /// O Mac em que a cifragem do enlace acabou de falhar: conectar de novo nele na mesma rodada falha igual.
        var cifragem: (id: String, erro: ErroCifragemBluetooth)?
        if let id = pareado.idBluetooth {
            do { return (id, try await conectarComPrazo(id), false) } catch {
                log("bluetooth: conexão direta no id guardado \(id.prefix(8)) falhou (\(error))")
                if let e = error as? ErroCifragemBluetooth { cifragem = (id, e) }
                // Sem o Mac no id guardado (endereço trocado, anúncio parado, fora de alcance): não fica esperando, procura o serviço.
                if let motivo = radio.indisponivel { throw ErroPareamento.recusado(motivo) }
                log("bluetooth: o Mac não respondeu no id guardado, procurando o serviço do Deck")
            }
        }
        let busca = Task { () -> [AnuncioBle] in
            for await lista in radio.procurar() where !lista.isEmpty { return lista }
            return []
        }
        let prazo = Task { try? await Task.sleep(nanoseconds: UInt64(prazoProcura * 1_000_000_000)); busca.cancel() }
        log("bluetooth: procurando o serviço do Deck por até \(Int(prazoProcura)) s")
        let achados = await busca.value
        prazo.cancel()
        log("bluetooth: a procura terminou com \(achados.count) Mac(s): \(achados.map { "\($0.id.prefix(8)) \"\($0.nome)\" rssi=\($0.rssi)" })")
        let candidatos = achados.filter { !recusados.contains($0.id) && $0.id != cifragem?.id }.sorted { $0.rssi > $1.rssi }
        if candidatos.isEmpty, let cifragem {
            log("bluetooth: a procura só achou \(cifragem.id.prefix(8)), em que a cifragem acabou de falhar: não conecto de novo nesta rodada")
            throw cifragem.erro
        }
        guard !achados.isEmpty else { throw ErroPareamento.recusado("Nenhum Mac com o Deck por perto.") }
        guard let alvo = candidatos.first(where: { $0.id == pareado.idBluetooth }) ?? candidatos.first(where: { $0.nome == pareado.nomeMac }) ?? candidatos.first else {
            throw ErroSemCandidato.todosRecusaram
        }
        log("bluetooth: escolhi \(alvo.id.prefix(8)) \"\(alvo.nome)\" para conectar")
        return (alvo.id, try await conectarComPrazo(alvo.id), true)
    }

    /// Conecta com tempo limite garantido aqui, mesmo que o rádio não cumpra o dele.
    private func conectarComPrazo(_ id: String) async throws -> FluxoBytes {
        let prazo = prazoDireto
        let radio = radio
        return try await withThrowingTaskGroup(of: FluxoBytes.self) { grupo in
            grupo.addTask { try await radio.conectar(id: id, prazo: prazo) }
            grupo.addTask {
                try await Task.sleep(nanoseconds: UInt64((prazo + 0.5) * 1_000_000_000))
                throw ErroPareamento.recusado("O Mac não respondeu.")
            }
            defer { grupo.cancelAll() }
            guard let primeiro = try await grupo.next() else { throw ErroPareamento.recusado("O Mac não respondeu.") }
            return primeiro
        }
    }

    /// Põe a conexão em uso. O Mac só conta como conectado quando se apresenta (o "ola" dele).
    private func ativar(_ nova: ConexaoCabo, id: String, nome: String) {
        let antiga: ConexaoCabo? = trava.withLock {
            let a = conexao
            conexao = nova
            return a
        }
        antiga?.fechar()
        conferirAnuncio()
        nova.iniciar(aoOla: { [self] c in apresentou(c, id: id, nome: nome) }, aoFechar: { [self] c in caiu(c) })
    }

    private func apresentou(_ c: ConexaoCabo, id: String, nome: String) {
        let mac = MacEncontrado(id: id, nome: nome, perto: true)
        let aviso: (@Sendable (MacEncontrado?) -> Void)?? = trava.withLock {
            guard conexao === c else { return nil }
            macAtual = mac
            return .some(aoMudarBt)
        }
        guard let aviso else { return }
        aviso?(mac)
    }

    private func caiu(_ c: ConexaoCabo) {
        let aviso: (@Sendable (MacEncontrado?) -> Void)?? = trava.withLock {
            guard conexao === c else { return nil }
            conexao = nil
            macAtual = nil
            return .some(aoMudarBt)
        }
        guard let aviso else { return }
        log("bluetooth: conexão com o Mac caiu")
        situar("Procurando o Mac pelo Bluetooth.")
        conferirAnuncio()
        aviso?(nil)
    }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal {
        guard let c = trava.withLock({ conexao }) else { throw ErroCanal.semCanal }
        return try await c.enviar(pedido)
    }

    // MARK: Pareamento (iPhone novo)

    /// Os Macs com Deck por perto, a cada mudança. Cancelar a tarefa para a procura.
    func listar() -> AsyncStream<[MacEncontrado]> {
        let origem = radio.procurar()
        return AsyncStream { saida in
            let t = Task {
                for await lista in origem {
                    saida.yield(lista.map { MacEncontrado(id: $0.id, nome: $0.nome, perto: $0.perto) })
                }
                saida.finish()
            }
            saida.onTermination = { _ in t.cancel() }
        }
    }

    /// A pessoa tocou no Mac da lista: conecta, troca as chaves e devolve o código de 6 dígitos que o Mac também mostra.
    func iniciarPareamento(com mac: MacEncontrado) async throws -> String {
        descartarPendente()
        let fluxo: FluxoBytes
        do {
            fluxo = try await radio.conectar(id: mac.id)
        } catch {
            // O sentido antigo falhou (a cifragem, quase sempre): anuncia e espera o Mac conectar no iPhone. O Mac só
            // aceita o pareamento com Conectar iPhone aberto, como no sentido antigo.
            guard periferico != nil, radio.indisponivel == nil else { throw error }
            log("bluetooth: pareamento pelo sentido antigo falhou (\(error)). Anunciando e esperando o Mac conectar no iPhone por até \(Int(esperaDoMacNoPareamento)) s")
            guard let invertido = await esperarMacNoIphone(esperaDoMacNoPareamento) else {
                log("bluetooth: nenhum Mac conectou no iPhone para o pareamento")
                throw error
            }
            fluxo = invertido
        }
        let nome = nomeDoIphone
        do {
            let p = try await Task.detached { try EnlaceSeguro.iniciarPareamento(fluxo, nomeDoIphone: nome) }.value
            trava.withLock { pendente = Pendente(pareando: p, mac: MacEncontrado(id: mac.id, nome: p.nomeMac, perto: true)) }
            return p.codigo
        } catch {
            fluxo.fechar()
            throw ErroPareamento.recusado(Self.texto(error))
        }
    }

    /// A pessoa respondeu no iPhone. Aceito: espera o Mac permitir também e recebe o código de acesso. O fio
    /// do pareamento já está cifrado e vira a conexão em uso, sem apertar a mão de novo.
    func concluirPareamento(aceito: Bool) async throws -> PareamentoFeito {
        guard let p = trava.withLock({ () -> Pendente? in let x = pendente; pendente = nil; return x }) else {
            throw ErroPareamento.recusado("Nenhum pareamento esperando. Procure o Mac de novo.")
        }
        let codigo: String
        do { codigo = try await Task.detached { try EnlaceSeguro.concluir(p.pareando, aceito: aceito) }.value } catch {
            p.pareando.fluxo.fechar()
            throw ErroPareamento.recusado(Self.texto(error))
        }
        log("bluetooth: pareado com \"\(p.mac.nome)\"")
        ativar(ConexaoCabo(fluxo: p.pareando.fluxo, segredo: { nil }, confiavel: true, nomeDoCanal: "O Bluetooth"), id: p.mac.id, nome: p.mac.nome)
        return PareamentoFeito(pareado: Pareado(codigoAcesso: codigo, nomeMac: p.mac.nome, idBluetooth: p.mac.id), canal: CanalBluetooth(self))
    }

    private func descartarPendente() {
        let p: Pendente? = trava.withLock { let x = pendente; pendente = nil; return x }
        p?.pareando.fluxo.fechar()
    }

    private static func texto(_ erro: Error) -> String {
        switch erro {
        case let e as ErroPareamento: return e.mensagem
        case let e as ErroCifragemBluetooth: return e.mensagem
        case ErroEnlace.recusado(let t): return t
        case ErroEnlace.naoPareado: return "O Mac não reconheceu este iPhone."
        case ErroEnlace.protocolo: return "A conversa com o Mac falhou. Tente de novo."
        default: return "Não consegui parear. Tente de novo."
        }
    }
}

extension GerenteBluetooth: ConexaoBluetooth {
    public func canal() -> any Canal { CanalBluetooth(self) }
}

/// O canal em uso quando o Mac está no Bluetooth. Sem conexão, o pedido falha com `semCanal`.
public struct CanalBluetooth: Canal {
    public let tipo: TipoCanal = .bluetooth
    let gerente: GerenteBluetooth

    public init(_ gerente: GerenteBluetooth) { self.gerente = gerente }

    public func enviar(_ pedido: PedidoCanal) async throws -> RespostaCanal { try await gerente.enviar(pedido) }
}

/// O pareador do app: o pareamento principal (Bluetooth, código igual nas duas telas) e a segunda via (cabo,
/// código digitado no iPhone).
public struct PareadorCompleto: Pareador {
    let cabo: PareadorCabo
    let bluetooth: GerenteBluetooth

    public init(cabo: GerenteDoCabo, bluetooth: GerenteBluetooth) {
        self.cabo = PareadorCabo(cabo)
        self.bluetooth = bluetooth
    }

    public func procurarPorBluetooth() -> AsyncStream<[MacEncontrado]> { bluetooth.listar() }
    public func iniciar(com mac: MacEncontrado) async throws -> String { try await bluetooth.iniciarPareamento(com: mac) }
    public func concluir(aceito: Bool) async throws -> PareamentoFeito { try await bluetooth.concluirPareamento(aceito: aceito) }
    public func procurarNoCabo() -> AsyncStream<MacEncontrado> { cabo.procurarNoCabo() }
    public func parearComCodigo(_ mac: MacEncontrado, _ codigo: String) async throws -> PareamentoFeito {
        try await cabo.parearComCodigo(mac, codigo)
    }

    /// O rádio leva um instante para dizer se está ligado e liberado: dá 1,5 s antes de avisar.
    public func avisoDaProcura() async -> String? {
        for _ in 0..<15 {
            if let motivo = bluetooth.indisponivel { return motivo }
            if bluetooth.radioPronto { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
}

#endif
