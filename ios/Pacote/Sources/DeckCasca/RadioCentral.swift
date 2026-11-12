import Foundation
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// O rádio do iPhone no Bluetooth LE (fase 7). O iPhone é a central: procura o serviço do Deck que o Mac
// anuncia (mac/Nucleo/Bluetooth.swift), conecta, assina a característica de resposta e escreve os pedidos na
// de pedido. Do lado de cima (GerenteBluetooth) isto é só uma lista de Macs e um FluxoBytes por conexão.

/// Um Mac com Deck visto no ar.
public struct AnuncioBle: Equatable, Sendable {
    public var id: String
    public var nome: String
    public var rssi: Int

    public init(id: String, nome: String, rssi: Int) {
        self.id = id
        self.nome = nome
        self.rssi = rssi
    }

    /// Sinal forte o bastante para parear na lista. Mais fraco que isso, o Mac aparece como "Longe".
    public var perto: Bool { rssi >= AnuncioBle.sinalDePerto }
    public static let sinalDePerto = -75
}

protocol RadioBle: Sendable {
    /// Os Macs com Deck no ar, a cada mudança. Cancelar a tarefa para a procura.
    func procurar() -> AsyncStream<[AnuncioBle]>
    /// Conecta no Mac e devolve o fio (serviço achado e resposta assinada). O texto do erro é o que a pessoa lê.
    func conectar(id: String, prazo: TimeInterval) async throws -> FluxoBytes
    /// Por que o rádio não serve agora (desligado, sem permissão), ou nil.
    var indisponivel: String? { get }
    /// O rádio está ligado, liberado e pronto para procurar.
    var pronto: Bool { get }
    /// Nome do Mac pareado: na varredura sem filtro, um anúncio com esse nome vale mesmo sem o UUID do Deck à vista.
    func confiarNoNome(_ nome: String)
}

extension RadioBle {
    func confiarNoNome(_ nome: String) {}
    /// Tempo limite padrão para o Mac responder à conexão.
    static var prazoDeConexao: TimeInterval { 15 }
    func conectar(id: String) async throws -> FluxoBytes { try await conectar(id: id, prazo: Self.prazoDeConexao) }
}

#if canImport(CoreBluetooth)
final class RadioCentral: NSObject, RadioBle, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private struct Visto {
        var peripheral: CBPeripheral
        var nome: String
        var rssi: Int
        var quando: Date
    }

    private final class Conexao: @unchecked Sendable {
        let peripheral: CBPeripheral
        var continuacao: CheckedContinuation<FluxoBytes, Error>?
        var pedido: CBCharacteristic?
        var resposta: CBCharacteristic?
        var fluxo: FluxoEnlace?
        let espera = NSCondition()
        var pronto = true
        var fechada = false
        init(_ p: CBPeripheral) { peripheral = p }
    }

    /// Um Mac que sumiu do ar há mais que isso sai da lista.
    static let validadeDoAnuncio: TimeInterval = 6

    private let fila = DispatchQueue(label: "deck.bluetooth.central")
    private let log: @Sendable (String) -> Void
    private var central: CBCentralManager?
    private var vistos: [String: Visto] = [:]
    private var ouvintes: [UUID: AsyncStream<[AnuncioBle]>.Continuation] = [:]
    private var conexoes: [String: Conexao] = [:]
    private var ultimaLista: [AnuncioBle] = []
    /// O Mac não anuncia o nome no ar: o iOS só o conhece depois de conectar. Na primeira vez que aparece um Mac
    /// sem nome, o rádio conecta um instante só para ler o nome e solta (um de cada vez).
    private var sondando: Set<String> = []
    private var sondados: Set<String> = []
    private var limpeza: DispatchSourceTimer?
    private let uuidServico = CBUUID(string: EnlaceBle.servico)
    private let uuidPedido = CBUUID(string: EnlaceBle.pedido)
    private let uuidResposta = CBUUID(string: EnlaceBle.resposta)
    /// A varredura com filtro de serviço não viu nada por um tempo: passa a varrer sem filtro e conferir o anúncio aqui.
    private var semFiltro = false
    private var viuNestaVarredura = false
    private var inicioDaVarredura = Date()
    private var nomesConhecidos: Set<String> = []
    private var ultimoRegistro: [String: (quando: Date, resumo: String, repetidos: Int)] = [:]
    /// Sem anúncio do Deck por tanto tempo, a varredura troca o filtro de serviço pela conferência no app.
    static let esperaParaVarrerSemFiltro: TimeInterval = 3
    /// Um mesmo anúncio repetido só entra de novo no diário depois disso (o Mac anuncia várias vezes por segundo).
    static let intervaloDoRegistroRepetido: TimeInterval = 5

    init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
        super.init()
    }

    var pronto: Bool { fila.sync { central?.state == .poweredOn } }

    func confiarNoNome(_ nome: String) { fila.async { [self] in nomesConhecidos.insert(nome) } }

    private static func texto(_ e: CBManagerState) -> String {
        switch e {
        case .unknown: return "desconhecido"
        case .resetting: return "reiniciando"
        case .unsupported: return "sem suporte"
        case .unauthorized: return "sem permissão"
        case .poweredOff: return "desligado"
        case .poweredOn: return "ligado"
        @unknown default: return "?"
        }
    }

    private static func texto(_ e: CBManagerAuthorization) -> String {
        switch e {
        case .notDetermined: return "não decidida"
        case .restricted: return "restrita"
        case .denied: return "negada"
        case .allowedAlways: return "liberada"
        @unknown default: return "?"
        }
    }

    var indisponivel: String? {
        fila.sync {
            switch central?.state {
            case .poweredOff: return "O Bluetooth do iPhone está desligado. Ligue no Centro de Controle."
            case .unauthorized: return "O Deck não tem permissão de Bluetooth. Libere em Ajustes > Deck."
            case .unsupported: return "Este aparelho não tem Bluetooth LE."
            default: return nil
            }
        }
    }

    /// O gerenciador só nasce no primeiro uso: o pedido de permissão do iOS aparece quando a pessoa toca em
    /// "Procurar por perto" (ou quando já pareada o app abre), não antes. Roda na fila.
    private func garantir() -> CBCentralManager {
        if let c = central { return c }
        log("bluetooth: criando o CBCentralManager (autorização \(Self.texto(CBCentralManager.authorization)))")
        let c = CBCentralManager(delegate: self, queue: fila, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        central = c
        return c
    }

    // MARK: Procura

    func procurar() -> AsyncStream<[AnuncioBle]> {
        AsyncStream { continuacao in
            let id = UUID()
            fila.async { [self] in
                ouvintes[id] = continuacao
                log("bluetooth: procura pedida (\(ouvintes.count) ouvinte(s))")
                continuacao.yield(listaAtual())
                iniciarVarredura()
            }
            continuacao.onTermination = { [weak self] _ in
                self?.fila.async {
                    guard let self else { return }
                    self.ouvintes[id] = nil
                    self.log("bluetooth: procura encerrada (\(self.ouvintes.count) ouvinte(s) restantes)")
                    if self.ouvintes.isEmpty { self.pararVarredura() }
                }
            }
        }
    }

    private func iniciarVarredura() {
        let c = garantir()
        guard c.state == .poweredOn, !c.isScanning else {
            log("bluetooth: varredura não iniciada (estado \(Self.texto(c.state)), varrendo=\(c.isScanning))")
            return
        }
        semFiltro = false
        viuNestaVarredura = false
        inicioDaVarredura = Date()
        c.scanForPeripherals(withServices: [uuidServico], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("bluetooth: varredura iniciada com filtro do serviço \(uuidServico.uuidString)")
        let t = DispatchSource.makeTimerSource(queue: fila)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.passoDaVarredura() }
        t.resume()
        limpeza = t
    }

    /// A cada segundo: atualiza a lista e, se o filtro de serviço do iOS não trouxe nenhum Mac, varre sem filtro.
    private func passoDaVarredura() {
        publicar()
        guard !semFiltro, !viuNestaVarredura, let c = central, c.isScanning,
              Date().timeIntervalSince(inicioDaVarredura) >= Self.esperaParaVarrerSemFiltro else { return }
        c.stopScan()
        semFiltro = true
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("bluetooth: o filtro de serviço não trouxe nenhum anúncio em \(Int(Self.esperaParaVarrerSemFiltro)) s, varrendo SEM filtro e conferindo o anúncio no app")
    }

    private func pararVarredura() {
        log("bluetooth: varredura parada (viu anúncio do Deck=\(viuNestaVarredura), sem filtro=\(semFiltro))")
        central?.stopScan()
        limpeza?.cancel()
        limpeza = nil
        semFiltro = false
    }

    private func listaAtual() -> [AnuncioBle] {
        let limite = Date().addingTimeInterval(-Self.validadeDoAnuncio)
        return vistos.filter { $0.value.quando > limite }
            .map { AnuncioBle(id: $0.key, nome: $0.value.nome, rssi: $0.value.rssi) }
            .sorted { ($0.rssi, $1.nome) > ($1.rssi, $0.nome) }
    }

    /// Só avisa quem escuta quando a lista mudou de verdade (o sinal oscila a cada anúncio).
    private func publicar() {
        let lista = listaAtual()
        let resumo = lista.map { ($0.id, $0.nome, $0.perto) }
        let antes = ultimaLista.map { ($0.id, $0.nome, $0.perto) }
        guard resumo.count != antes.count || zip(resumo, antes).contains(where: { $0 != $1 }) else { return }
        ultimaLista = lista
        for o in ouvintes.values { o.yield(lista) }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log("bluetooth: estado do rádio \(c.state.rawValue) (\(Self.texto(c.state))), autorização \(Self.texto(CBCentralManager.authorization))")
        if c.state == .poweredOn, !ouvintes.isEmpty { iniciarVarredura() }
        if c.state != .poweredOn {
            for conexao in conexoes.values { falhar(conexao, "O Bluetooth do iPhone foi desligado.") }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = p.identifier.uuidString
        let rssi = RSSI.intValue
        let nomeNoAr = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let servicos = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let extras = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let av = AvaliacaoDeAnuncio.avaliar(servicos: servicos, extras: extras, nome: nomeNoAr ?? p.name, rssi: rssi, uuidDoDeck: uuidServico.uuidString,
                                            nomesConhecidos: nomesConhecidos, comFiltro: !semFiltro)
        registrarAnuncio(id: id, p: p, nomeNoAr: nomeNoAr, servicos: servicos, extras: extras, chaves: advertisementData.keys.sorted(), rssi: rssi, av: av)
        guard av.aceito else { return }
        viuNestaVarredura = true
        // O nome pode vir só no pacote de resposta da procura: guarda o último que apareceu.
        let nome = nomeNoAr ?? p.name ?? vistos[id]?.nome ?? "Mac"
        vistos[id] = Visto(peripheral: p, nome: nome, rssi: rssi, quando: Date())
        if nome == "Mac", !sondados.contains(id), sondando.isEmpty, conexoes[id] == nil { sondar(p) }
        publicar()
    }

    /// Um anúncio por linha, mas o mesmo anúncio repetido (o Mac manda vários por segundo) só a cada alguns segundos.
    private func registrarAnuncio(id: String, p: CBPeripheral, nomeNoAr: String?, servicos: [String], extras: [String], chaves: [String], rssi: Int, av: AvaliacaoDeAnuncio.Resultado) {
        let resumo = "\(av.aceito ? "ACEITO" : "DESCARTADO") nome=\(nomeNoAr ?? "-") nomeIOS=\(p.name ?? "-") servicos=\(servicos) extras=\(extras) chaves=\(chaves) (\(av.motivo))"
        let agora = Date()
        if var antes = ultimoRegistro[id], antes.resumo == resumo, agora.timeIntervalSince(antes.quando) < Self.intervaloDoRegistroRepetido {
            antes.repetidos += 1
            ultimoRegistro[id] = antes
            return
        }
        let repetidos = ultimoRegistro[id]?.repetidos ?? 0
        ultimoRegistro[id] = (agora, resumo, 0)
        log("bluetooth: anúncio \(id.prefix(8)) rssi=\(rssi) \(resumo)\(repetidos > 0 ? " (+\(repetidos) iguais antes)" : "")")
    }

    private func sondar(_ p: CBPeripheral) {
        let id = p.identifier.uuidString
        sondados.insert(id)
        sondando.insert(id)
        log("bluetooth: sonda para ler o nome de \(id.prefix(8)) (connect)")
        p.delegate = self
        central?.connect(p)
        fila.asyncAfter(deadline: .now() + 8) { [weak self] in self?.terminarSonda(p) }
    }

    /// Lê o nome que o iOS pegou na conexão e solta o Mac.
    private func terminarSonda(_ p: CBPeripheral) {
        let id = p.identifier.uuidString
        guard sondando.remove(id) != nil else { return }
        log("bluetooth: sonda de \(id.prefix(8)) terminou, nome=\(p.name ?? "-")")
        if let nome = p.name, !nome.isEmpty, var v = vistos[id] {
            v.nome = nome
            vistos[id] = v
        }
        if conexoes[id] == nil { central?.cancelPeripheralConnection(p) }
        publicar()
    }

    // MARK: Conexão

    func conectar(id: String, prazo: TimeInterval) async throws -> FluxoBytes {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<FluxoBytes, Error>) in
            fila.async { [self] in abrir(id, prazo, c) }
        }
    }

    private func abrir(_ id: String, _ prazo: TimeInterval, _ c: CheckedContinuation<FluxoBytes, Error>) {
        let gerente = garantir()
        log("bluetooth: conectar \(id.prefix(8)) (prazo \(Int(prazo)) s, estado \(Self.texto(gerente.state)))")
        if let motivo = motivoDeIndisponivel(gerente.state) { log("bluetooth: conectar recusado: \(motivo)"); return c.resume(throwing: ErroPareamento.recusado(motivo)) }
        let visto = vistos[id]?.peripheral
        guard let uuid = UUID(uuidString: id),
              let p = visto ?? gerente.retrievePeripherals(withIdentifiers: [uuid]).first else {
            log("bluetooth: conectar \(id.prefix(8)): o iOS não conhece esse identificador (retrievePeripherals vazio)")
            return c.resume(throwing: ErroPareamento.recusado("Não achei esse Mac. Abra o Deck nele e tente de novo."))
        }
        if let velha = conexoes[id] { falhar(velha, "Outra conexão abriu.") }
        let conexao = Conexao(p)
        conexao.continuacao = c
        conexoes[id] = conexao
        p.delegate = self
        log("bluetooth: connect() em \(id.prefix(8)) (\(visto != nil ? "visto na varredura" : "recuperado pelo id guardado"), estado do periférico \(p.state.rawValue))")
        gerente.connect(p)
        fila.asyncAfter(deadline: .now() + prazo) { [weak self, weak conexao] in
            guard let self, let conexao, conexao.continuacao != nil else { return }
            log("bluetooth: TEMPO LIMITE de \(Int(prazo)) s na conexão com \(id.prefix(8)) (estado do periférico \(conexao.peripheral.state.rawValue))")
            falhar(conexao, "O Mac não respondeu. Confira se ele está perto e com o Deck aberto.")
        }
    }

    private func motivoDeIndisponivel(_ e: CBManagerState) -> String? {
        switch e {
        case .poweredOff: return "O Bluetooth do iPhone está desligado. Ligue no Centro de Controle."
        case .unauthorized: return "O Deck não tem permissão de Bluetooth. Libere em Ajustes > Deck."
        case .unsupported: return "Este aparelho não tem Bluetooth LE."
        case .poweredOn: return nil
        default: return "O Bluetooth ainda está ligando. Tente de novo em um instante."
        }
    }

    /// Termina a conexão com erro (ainda esperando o fio) ou só a derruba (já com fio).
    private func falhar(_ conexao: Conexao, _ texto: String) {
        let c = conexao.continuacao
        conexao.continuacao = nil
        log("bluetooth: conexão com \(conexao.peripheral.identifier.uuidString.prefix(8)) falhou: \(texto)")
        c?.resume(throwing: ErroPareamento.recusado(texto))
        encerrar(conexao)
    }

    private func encerrar(_ conexao: Conexao) {
        conexao.espera.lock(); conexao.fechada = true; conexao.espera.broadcast(); conexao.espera.unlock()
        let id = conexao.peripheral.identifier.uuidString
        if conexoes[id] === conexao { conexoes[id] = nil }
        central?.cancelPeripheralConnection(conexao.peripheral)
        conexao.fluxo?.fechar()
    }

    private func conexao(de p: CBPeripheral) -> Conexao? { conexoes[p.identifier.uuidString] }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        let id = p.identifier.uuidString
        log("bluetooth: didConnect \(id.prefix(8)) (sonda=\(sondando.contains(id)), conexão=\(conexoes[id] != nil))")
        // Com uma conexão de verdade pedida para este Mac, o didConnect é dela: tratar como sonda deixava a conexão parada
        // sem descobrir o serviço até o tempo limite.
        if sondando.contains(id), conexoes[id] == nil {
            // O nome chega junto com a conexão, mas dá uma folga de 1 s se ainda não chegou.
            if p.name != nil { terminarSonda(p) } else { fila.asyncAfter(deadline: .now() + 1) { [weak self] in self?.terminarSonda(p) } }
            return
        }
        p.discoverServices([uuidServico])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        sondando.remove(p.identifier.uuidString)
        log("bluetooth: didFailToConnect \(p.identifier.uuidString.prefix(8)) erro=\(error.map { "\($0)" } ?? "-")")
        if let x = conexao(de: p) { falhar(x, "Não consegui conectar no Mac.") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("bluetooth: didDisconnect \(p.identifier.uuidString.prefix(8)) erro=\(error.map { "\($0)" } ?? "-")")
        guard let x = conexao(de: p) else { return }
        log("bluetooth: Mac desconectou")
        falhar(x, "O Mac desconectou.")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        log("bluetooth: serviços de \(p.identifier.uuidString.prefix(8)): \(p.services?.map { $0.uuid.uuidString } ?? []) erro=\(error.map { "\($0)" } ?? "-")")
        guard let x = conexao(de: p) else { return }
        guard error == nil, let s = p.services?.first(where: { $0.uuid == uuidServico }) else { return falhar(x, "Esse Mac não tem o Deck aberto.") }
        p.discoverCharacteristics([uuidPedido, uuidResposta], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        log("bluetooth: características de \(p.identifier.uuidString.prefix(8)): \(s.characteristics?.map { $0.uuid.uuidString } ?? []) erro=\(error.map { "\($0)" } ?? "-")")
        guard let x = conexao(de: p) else { return }
        let pedido = s.characteristics?.first { $0.uuid == uuidPedido }
        let resposta = s.characteristics?.first { $0.uuid == uuidResposta }
        guard error == nil, let pedido, let resposta else { return falhar(x, "Esse Mac não tem o Deck aberto.") }
        x.pedido = pedido
        x.resposta = resposta
        p.setNotifyValue(true, for: resposta)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard let x = conexao(de: p), c.uuid == uuidResposta else { return }
        log("bluetooth: inscrição na resposta de \(p.identifier.uuidString.prefix(8)): notificando=\(c.isNotifying) erro=\(error.map { "\($0)" } ?? "-")")
        guard error == nil, c.isNotifying else { return falhar(x, "Não consegui abrir a conversa com o Mac.") }
        guard let cont = x.continuacao else { return }
        x.continuacao = nil
        let fluxo = FluxoEnlace(
            escritor: { [weak self, weak x] dados in
                guard let self, let x else { return false }
                return escrever(dados, em: x)
            },
            aoFechar: { [weak self, weak x] in
                self?.fila.async { if let x, let self { self.encerrar(x) } }
            })
        x.fluxo = fluxo
        log("bluetooth: conectado (pacote de até \(p.maximumWriteValueLength(for: .withoutResponse)) bytes)")
        cont.resume(returning: fluxo)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, c.uuid == uuidResposta, let v = c.value, let x = conexao(de: p) else { return }
        x.fluxo?.fila.empurrar(v)
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        guard let x = conexao(de: p) else { return }
        x.espera.lock(); x.pronto = true; x.espera.broadcast(); x.espera.unlock()
    }

    /// Parte em pacotes do tamanho do MTU e espera o rádio liberar. Roda na thread de quem escreve, nunca na fila do rádio.
    private func escrever(_ dados: Data, em x: Conexao) -> Bool {
        guard let pedido = x.pedido else { return false }
        var tamanho = 20
        fila.sync { tamanho = max(20, x.peripheral.maximumWriteValueLength(for: .withoutResponse)) }
        var inicio = 0
        while inicio < dados.count {
            let fim = min(inicio + tamanho, dados.count)
            let parte = Data(dados[dados.startIndex + inicio ..< dados.startIndex + fim])
            while true {
                x.espera.lock()
                if x.fechada { x.espera.unlock(); return false }
                x.pronto = false
                x.espera.unlock()
                var enviou = false
                fila.sync {
                    if x.peripheral.canSendWriteWithoutResponse {
                        x.peripheral.writeValue(parte, for: pedido, type: .withoutResponse)
                        enviou = true
                    }
                }
                if enviou { break }
                x.espera.lock()
                let limite = Date().addingTimeInterval(5)
                while !x.pronto && !x.fechada {
                    if !x.espera.wait(until: limite) { x.espera.unlock(); return false }
                }
                x.espera.unlock()
            }
            inicio = fim
        }
        return true
    }
}
#endif

#if canImport(CoreBluetooth)
/// Prova técnica do Bluetooth (fase 7): acha o Mac, conecta e mede ping, descida e subida em três tamanhos.
/// O Mac precisa estar rodando `DeckServidor --bt-vazao`. Devolve as linhas do relato.
public enum ProvaBluetooth {
    public static func vazao(tamanhos: [Int] = [4096, 32768, 131072], log: @escaping @Sendable (String) -> Void) async -> [String] {
        var linhas: [String] = []
        func anotar(_ t: String) { linhas.append(t); log(t) }
        let radio = RadioCentral(log: log)
        var alvo: AnuncioBle?
        let busca = Task { () -> AnuncioBle? in
            for await lista in radio.procurar() {
                if let primeiro = lista.first { return primeiro }
            }
            return nil
        }
        let prazo = Task { try? await Task.sleep(nanoseconds: 30_000_000_000); busca.cancel() }
        alvo = await busca.value
        prazo.cancel()
        guard let alvo else {
            anotar("VAZAO sem Mac no ar em 30 s. Motivo do rádio: \(radio.indisponivel ?? "nenhum anúncio do Deck visto")")
            return linhas
        }
        anotar("VAZAO achei \"\(alvo.nome)\" rssi=\(alvo.rssi) perto=\(alvo.perto)")
        let fluxo: FluxoBytes
        do { fluxo = try await radio.conectar(id: alvo.id) } catch {
            anotar("VAZAO não conectou: \((error as? ErroPareamento)?.mensagem ?? "\(error)")")
            return linhas
        }
        anotar("VAZAO conectado")
        for n in tamanhos {
            let r: VazaoBluetooth.Resultado? = await Task.detached { VazaoBluetooth.medir(fluxo, bytes: n) }.value
            guard let r else { anotar("VAZAO \(n) bytes: o fio caiu no meio"); break }
            anotar(String(format: "VAZAO %d bytes: ping medio %.0f ms (max %.0f ms), descida %.1f KB/s em %.2f s, subida %.1f KB/s em %.2f s",
                          n, r.pingMedioMs, r.pingMaximoMs, r.descidaKBs, r.descidaSegundos, r.subidaKBs, r.subidaSegundos))
        }
        fluxo.fechar()
        return linhas
    }
}
#endif
