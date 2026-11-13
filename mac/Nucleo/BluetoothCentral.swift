import Foundation
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// Sentido invertido do Bluetooth (12/11/2026): além de anunciar (Bluetooth.swift), o Mac procura o iPhone que anuncia o
// serviço invertido do Deck e conecta nele como central. Motivo, no log do bluetoothd: com o iPhone e o Mac na mesma conta
// do iCloud, toda conexão LE entre eles passa pelo FastLE, que falhava a cifragem com o Mac periférico ("Failed to encrypt
// connection", CBError 15 no iPhone) e passava com o Mac central ("localRole=Central encrypted:1"). O fio que sai daqui é
// atendido pela mesma PortaDoBluetooth: mesmo aperto de mão, mesmo pareamento, mesmos quadros. Só o transporte troca de
// mãos: o pedido do iPhone chega por notificação e a resposta do Mac vai por escrita.

/// Quando o Mac pode conectar de novo em cada iPhone que anuncia. Pura, para ter teste. Um iPhone por vez em cada id, e
/// quem acabou de cair (ou nem abriu a sessão) espera um pouco, cada vez mais, para o Mac não ficar conectando em laço
/// num iPhone que não fecha o aperto de mão (sem pareamento, outro Mac, o lado de cima já em uso).
struct AgendaDoMac {
    static let esperaMinima: TimeInterval = 2
    static let esperaMaxima: TimeInterval = 30
    /// Sessão que durou isso já foi uma conversa de verdade: a próxima tentativa volta para a espera mínima.
    static let sessaoBoa: TimeInterval = 20

    private var ocupados: Set<String> = []
    private var proxima: [String: Date] = [:]
    private var esperas: [String: TimeInterval] = [:]

    func podeConectar(_ id: String, agora: Date) -> Bool {
        !ocupados.contains(id) && (proxima[id] ?? .distantPast) <= agora
    }

    mutating func conectando(_ id: String) { ocupados.insert(id) }

    /// O enlace com `id` acabou. `duracao` é quanto a sessão durou, ou nil se ela nem abriu (falhou antes de assinar).
    mutating func terminou(_ id: String, duracao: TimeInterval?, agora: Date) {
        ocupados.remove(id)
        let espera: TimeInterval
        if let duracao, duracao >= Self.sessaoBoa {
            espera = Self.esperaMinima
        } else {
            espera = min((esperas[id] ?? Self.esperaMinima / 2) * 2, Self.esperaMaxima)
        }
        esperas[id] = espera
        proxima[id] = agora.addingTimeInterval(espera)
    }

    func espera(_ id: String) -> TimeInterval? { esperas[id] }
}

#if canImport(CoreBluetooth)
/// O rádio do Mac como central: procura o serviço invertido, conecta, assina a notificação de pedido e entrega cada iPhone
/// como um FluxoEnlace (o mesmo `aoAbrir` do periférico).
final class RadioCentralMac: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private final class Enlace: @unchecked Sendable {
        let peripheral: CBPeripheral
        var pedido: CBCharacteristic?
        var resposta: CBCharacteristic?
        var fluxo: FluxoEnlace?
        let portao = PortaoDoRadio()
        var abriuEm: Date?
        var primeiraNotificacao = true
        init(_ p: CBPeripheral) { peripheral = p }
    }

    /// Tempo para conectar, descobrir e assinar. O connect do macOS não falha sozinho: sem isto, um iPhone que sumiu prende o id.
    static let prazoDeConexao: TimeInterval = 15
    /// Um anúncio visto do mesmo iPhone só volta ao log depois disso (o iPhone anuncia várias vezes por segundo).
    static let intervaloDoAnuncioNoLog: TimeInterval = 30

    private let fila = DispatchQueue(label: "deck.bluetooth.central-mac")
    private let aoAbrir: @Sendable (FluxoEnlace, String) -> Void
    private let log: @Sendable (String) -> Void
    private var central: CBCentralManager?
    private var enlaces: [String: Enlace] = [:]
    private var agenda = AgendaDoMac()
    private var anunciosNoLog: [String: Date] = [:]
    private var ultimoEstado: CBManagerState?
    private var relogio: DispatchSourceTimer?
    private let uuidServico = CBUUID(string: EnlaceBle.servicoInvertido)
    private let uuidPedido = CBUUID(string: EnlaceBle.pedidoInvertido)
    private let uuidResposta = CBUUID(string: EnlaceBle.respostaInvertida)

    /// `aoAbrir` roda numa thread própria a cada iPhone com a notificação assinada, e bloqueia até a sessão acabar.
    init(aoAbrir: @escaping @Sendable (FluxoEnlace, String) -> Void,
         log: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }) {
        self.aoAbrir = aoAbrir
        self.log = log
    }

    private static func rotulo(_ id: String) -> String { "inv-\(id.prefix(8))" }

    func iniciar() {
        fila.async { [self] in
            central = CBCentralManager(delegate: self, queue: fila, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            // A varredura pode parar sem aviso (rádio que reiniciou): confere de tempos em tempos.
            let t = DispatchSource.makeTimerSource(queue: fila)
            t.schedule(deadline: .now() + 15, repeating: 15)
            t.setEventHandler { [weak self] in self?.varrer("conferência periódica") }
            t.resume()
            relogio = t
        }
    }

    func parar() {
        fila.async { [self] in
            relogio?.cancel()
            relogio = nil
            central?.stopScan()
            for e in enlaces.values { fechar(e, "o Deck parou o Bluetooth") }
        }
    }

    // MARK: Varredura

    private func varrer(_ motivo: String) {
        guard let c = central, c.state == .poweredOn, !c.isScanning else { return }
        c.scanForPeripherals(withServices: [uuidServico], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("bluetooth/central: procurando iPhone que anuncia o serviço invertido \(uuidServico.uuidString) (\(motivo))")
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state != ultimoEstado { log("bluetooth/central: estado do rádio do Mac \(c.state.rawValue)"); ultimoEstado = c.state }
        if c.state == .poweredOn {
            varrer("rádio ligado")
        } else {
            for e in enlaces.values { fechar(e, "rádio do Mac fora (estado \(c.state.rawValue))") }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = p.identifier.uuidString
        let agora = Date()
        // O filtro do macOS já garante o serviço, mas confere: só conecta em quem anuncia o serviço invertido do Deck.
        let servicos = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let extras = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        guard servicos.contains(uuidServico) || extras.contains(uuidServico) else { return }
        if agora.timeIntervalSince(anunciosNoLog[id] ?? .distantPast) >= Self.intervaloDoAnuncioNoLog {
            anunciosNoLog[id] = agora
            log("bluetooth/central: anúncio visto de \(id.prefix(8)) rssi=\(RSSI.intValue) (conectado=\(enlaces[id] != nil))")
        }
        guard enlaces[id] == nil, agenda.podeConectar(id, agora: agora) else { return }
        let e = Enlace(p)
        enlaces[id] = e
        agenda.conectando(id)
        p.delegate = self
        log("bluetooth/central: connect() em \(id.prefix(8))")
        c.connect(p)
        fila.asyncAfter(deadline: .now() + Self.prazoDeConexao) { [weak self, weak e] in
            guard let self, let e, self.enlaces[id] === e, e.abriuEm == nil else { return }
            self.fechar(e, "TEMPO LIMITE de \(Int(Self.prazoDeConexao)) s sem abrir o enlace (estado do periférico \(e.peripheral.state.rawValue))")
        }
    }

    // MARK: Conexão

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("bluetooth/central: didConnect \(p.identifier.uuidString.prefix(8))")
        guard enlaces[p.identifier.uuidString] != nil else { c.cancelPeripheralConnection(p); return }
        p.discoverServices([uuidServico])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("bluetooth/central: didFailToConnect \(p.identifier.uuidString.prefix(8)) erro=\(error.map { "\($0)" } ?? "-")")
        if let e = enlaces[p.identifier.uuidString] { fechar(e, "não conectou") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("bluetooth/central: didDisconnect \(p.identifier.uuidString.prefix(8)) erro=\(error.map { "\($0)" } ?? "-")")
        if let e = enlaces[p.identifier.uuidString] { fechar(e, "o iPhone desconectou") }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        log("bluetooth/central: serviços de \(p.identifier.uuidString.prefix(8)): \(p.services?.map { $0.uuid.uuidString } ?? []) erro=\(error.map { "\($0)" } ?? "-")")
        guard let e = enlaces[p.identifier.uuidString] else { return }
        guard error == nil, let s = p.services?.first(where: { $0.uuid == uuidServico }) else { return fechar(e, "o iPhone não tem o serviço invertido") }
        p.discoverCharacteristics([uuidPedido, uuidResposta], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        log("bluetooth/central: características de \(p.identifier.uuidString.prefix(8)): \(s.characteristics?.map { $0.uuid.uuidString } ?? []) erro=\(error.map { "\($0)" } ?? "-")")
        guard let e = enlaces[p.identifier.uuidString] else { return }
        let pedido = s.characteristics?.first { $0.uuid == uuidPedido }
        let resposta = s.characteristics?.first { $0.uuid == uuidResposta }
        guard error == nil, let pedido, let resposta else { return fechar(e, "faltam as características do serviço invertido") }
        e.pedido = pedido
        e.resposta = resposta
        p.setNotifyValue(true, for: pedido)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        let id = p.identifier.uuidString
        guard let e = enlaces[id], c.uuid == uuidPedido else { return }
        log("bluetooth/central: assinatura do pedido de \(id.prefix(8)): notificando=\(c.isNotifying) erro=\(error.map { "\($0)" } ?? "-")")
        guard error == nil, c.isNotifying else { return fechar(e, "não consegui assinar o pedido") }
        guard e.fluxo == nil else { return }
        let rotulo = Self.rotulo(id)
        let fluxo = FluxoEnlace(
            escritor: { [weak self, weak e] dados in
                guard let self, let e else { return false }
                return escrever(dados, em: e)
            },
            aoFechar: { [weak self, weak e] in
                self?.fila.async { if let self, let e { self.fechar(e, "a sessão acabou") } }
            })
        e.fluxo = fluxo
        e.abriuEm = Date()
        log("bluetooth \(rotulo): enlace invertido aberto (pacote de até \(p.maximumWriteValueLength(for: .withoutResponse)) bytes)")
        let aoAbrir = aoAbrir
        let t = Thread { aoAbrir(fluxo, rotulo); fluxo.fechar() }
        t.name = "deck.bluetooth.\(rotulo)"
        t.start()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == uuidPedido, let e = enlaces[p.identifier.uuidString], let fluxo = e.fluxo else { return }
        if e.primeiraNotificacao {
            e.primeiraNotificacao = false
            log("bluetooth \(Self.rotulo(p.identifier.uuidString)): primeiro pedido chegou (\(c.value?.count ?? 0) bytes)")
        }
        if !EnlaceInvertido.receber(c.value, em: fluxo) {
            log("bluetooth \(Self.rotulo(p.identifier.uuidString)): o iPhone avisou que fechou o enlace")
        }
    }

    func peripheral(_ p: CBPeripheral, didModifyServices invalidados: [CBService]) {
        guard invalidados.contains(where: { $0.uuid == uuidServico }), let e = enlaces[p.identifier.uuidString] else { return }
        fechar(e, "o iPhone tirou o serviço invertido do ar")
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
        enlaces[p.identifier.uuidString]?.portao.liberar()
    }

    /// Roda na fila. Fecha o fio, solta a conexão e marca na agenda quando pode conectar de novo neste iPhone.
    private func fechar(_ e: Enlace, _ motivo: String) {
        let id = e.peripheral.identifier.uuidString
        guard enlaces[id] === e else { return }
        enlaces[id] = nil
        let duracao = e.abriuEm.map { Date().timeIntervalSince($0) }
        agenda.terminou(id, duracao: duracao, agora: Date())
        log("bluetooth/central: \(id.prefix(8)) caiu (\(motivo)), sessão de \(duracao.map { String(format: "%.0f s", $0) } ?? "nenhuma"), próxima tentativa em \(Int(agenda.espera(id) ?? 0)) s")
        e.portao.fechar()
        central?.cancelPeripheralConnection(e.peripheral)
        e.fluxo?.fechar()
    }

    /// Parte em pacotes do tamanho do MTU e espera o rádio liberar. Roda na thread de quem escreve, nunca na fila do rádio.
    private func escrever(_ dados: Data, em e: Enlace) -> Bool {
        guard let resposta = e.resposta else { return false }
        var tamanho = 20
        fila.sync { tamanho = max(20, e.peripheral.maximumWriteValueLength(for: .withoutResponse)) }
        return Pacotes.escrever(dados, tamanho: tamanho, enviar: { [self] parte in
            guard !e.portao.estaFechado else { return false }
            e.portao.armar()
            var enviou = false
            fila.sync {
                if e.peripheral.canSendWriteWithoutResponse {
                    e.peripheral.writeValue(parte, for: resposta, type: .withoutResponse)
                    enviou = true
                }
            }
            return enviou
        }, aguardar: { e.portao.esperar(5) })
    }
}
#endif
