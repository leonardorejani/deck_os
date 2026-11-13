import Foundation
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// Sentido invertido do Bluetooth (12/11/2026). Com o app aberto e sem conexão de dados pelo Bluetooth, o iPhone também
// anuncia um serviço do Deck e o Mac conecta nele como central (mac/Nucleo/BluetoothCentral.swift). Motivo, no log do
// bluetoothd do Mac: com os dois na mesma conta do iCloud, toda conexão LE passa pelo FastLE, que falhava a cifragem com o
// Mac periférico (CBError 15 aqui no iPhone) e passava com o Mac central. Só o transporte troca de mãos: o iPhone continua
// pedindo e o Mac respondendo, com o mesmo aperto de mão e os mesmos quadros. O pedido sai por notificação e a resposta
// entra por escrita. As características não pedem cifragem: o Deck já cifra por cima (EnlaceSeguro).

/// O iPhone como periférico. Do lado de cima (GerenteBluetooth) é só "anunciar sim ou não" e um fio por Mac que conecta.
protocol PerifericoBle: AnyObject, Sendable {
    /// Quem recebe cada Mac que conectou e assinou o pedido (um fio por Mac, com um rótulo para o diário). Chamado fora da
    /// fila do rádio, mas quem recebe não deve bloquear.
    func aoAbrir(_ f: @escaping @Sendable (FluxoBytes, String) -> Void)
    /// Liga ou desliga o anúncio. Ligar cria o rádio (e o pedido de permissão do iOS) na primeira vez. Pode ser chamado a
    /// toda hora: só age quando o pedido muda ou quando o anúncio parou sem ninguém mandar.
    func anunciar(_ ligado: Bool)
}

/// O que o rádio do iPhone (periférico) tem que fazer a seguir, decidido sem rádio para ter teste. Em 13/11/2026, no diário:
/// ao desligar e ligar o Bluetooth do iPhone, o serviço era publicado de novo sem tirar o anterior, que o iOS mantém no
/// gerenciador. O Mac então via o serviço duas vezes, assinava o do primeiro (que o app já não usava) e as notificações
/// nunca chegavam ("sem resposta do Mac" até o app ser fechado). Por isso publicar de novo sempre começa limpando.
struct PlanoDoPeriferico {
    enum Acao: Equatable {
        /// Tira do gerenciador todo serviço que o app já publicou antes de publicar o novo.
        case limparServicos
        case publicarServico
        case anunciar
    }

    /// Quanto um anúncio pedido que não confirmou espera até ser pedido de novo.
    static let prazoDoInicioDoAnuncio: TimeInterval = 5

    private(set) var servicosNoRadio = 0
    private(set) var montado = false
    private(set) var publicado = false
    var desejado = false
    private(set) var pedidoDeAnuncioEm: Date?

    /// O rádio mudou de estado. Fora do ar, o serviço precisa ser publicado de novo ao voltar, mas continua no gerenciador.
    mutating func aoMudarEstado(ligado: Bool) {
        guard !ligado else { return }
        montado = false
        publicado = false
        pedidoDeAnuncioEm = nil
    }

    /// A próxima coisa a fazer com o rádio no estado `ligado`, ou nil se não há nada. Quem chama executa e confirma com
    /// `aoPublicar`/`aoAnunciar`.
    mutating func proxima(ligado: Bool, anunciando: Bool, agora: Date) -> [Acao] {
        guard ligado else { return [] }
        if !montado {
            montado = true
            var acoes: [Acao] = []
            if servicosNoRadio > 0 { acoes.append(.limparServicos) }
            acoes.append(.publicarServico)
            return acoes
        }
        guard publicado, desejado, !anunciando else { return [] }
        if let em = pedidoDeAnuncioEm, agora.timeIntervalSince(em) < Self.prazoDoInicioDoAnuncio { return [] }
        pedidoDeAnuncioEm = agora
        return [.anunciar]
    }

    mutating func aoLimpar() { servicosNoRadio = 0 }

    /// O gerenciador respondeu à publicação. Com erro, o serviço pode não ter entrado: tenta de novo na próxima conferência.
    mutating func aoPublicar(erro: Bool) {
        if erro { montado = false; return }
        servicosNoRadio += 1
        publicado = true
    }

    mutating func aoAnunciar() { pedidoDeAnuncioEm = nil }
    mutating func aoDispensar() { pedidoDeAnuncioEm = nil }
}

#if canImport(CoreBluetooth)
final class RadioPerifericoIphone: NSObject, PerifericoBle, CBPeripheralManagerDelegate, @unchecked Sendable {
    private final class Sessao: @unchecked Sendable {
        let central: CBCentral
        var fluxo: FluxoEnlace!
        let portao = PortaoDoRadio()
        /// O Mac saiu da assinatura: não adianta mandar o aviso de fechar.
        var saiu = false
        var primeiraEscrita = true
        var filaCheiaNoLog = Date.distantPast
        init(_ c: CBCentral) { central = c }
    }

    private let fila = DispatchQueue(label: "deck.bluetooth.periferico-iphone")
    private let log: @Sendable (String) -> Void
    private var gerente: CBPeripheralManager?
    private var pedido: CBMutableCharacteristic?
    private var plano = PlanoDoPeriferico()
    private var sessoes: [UUID: Sessao] = [:]
    /// Avisos de fechar que não couberam na fila de notificações: vão quando o rádio liberar.
    private var avisosPendentes: [UUID: CBCentral] = [:]
    private var receptor: (@Sendable (FluxoBytes, String) -> Void)?
    private var ultimoEstado: CBManagerState?
    private let uuidServico = CBUUID(string: EnlaceBle.servicoInvertido)
    private let uuidPedido = CBUUID(string: EnlaceBle.pedidoInvertido)
    private let uuidResposta = CBUUID(string: EnlaceBle.respostaInvertida)

    init(log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.log = log
        super.init()
    }

    func aoAbrir(_ f: @escaping @Sendable (FluxoBytes, String) -> Void) { fila.async { [self] in receptor = f } }

    func anunciar(_ ligado: Bool) {
        fila.async { [self] in
            if ligado != plano.desejado {
                plano.desejado = ligado
                log("bluetooth/periférico: anúncio \(ligado ? "pedido (esperando o Mac conectar)" : "dispensado")")
            }
            if ligado {
                garantir()
                conferir()
            } else if let g = gerente, g.isAdvertising || plano.pedidoDeAnuncioEm != nil {
                g.stopAdvertising()
                plano.aoDispensar()
                log("bluetooth/periférico: anúncio parado")
            }
        }
    }

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

    /// Roda na fila. Cria o gerenciador no primeiro anúncio pedido, nunca antes (é ele que faz o iOS pedir a permissão).
    private func garantir() {
        guard gerente == nil else { return }
        log("bluetooth/periférico: criando o CBPeripheralManager")
        gerente = CBPeripheralManager(delegate: self, queue: fila, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
    }

    /// Roda na fila: publica o serviço se falta e anuncia se o anúncio foi pedido e não está no ar.
    private func conferir() {
        guard let g = gerente else { return }
        for acao in plano.proxima(ligado: g.state == .poweredOn, anunciando: g.isAdvertising, agora: Date()) {
            switch acao {
            case .limparServicos:
                log("bluetooth/periférico: tirando o serviço publicado antes (o iOS o guarda quando o rádio reinicia)")
                g.removeAllServices()
                pedido = nil
                plano.aoLimpar()
            case .publicarServico:
                montar(g)
            case .anunciar:
                log("bluetooth/periférico: iniciando o anúncio do serviço \(uuidServico.uuidString)")
                g.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [uuidServico]])
            }
        }
    }

    private func montar(_ g: CBPeripheralManager) {
        let pedido = CBMutableCharacteristic(type: uuidPedido, properties: [.notify], value: nil, permissions: [.readable])
        let resposta = CBMutableCharacteristic(type: uuidResposta, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        self.pedido = pedido
        let servico = CBMutableService(type: uuidServico, primary: true)
        servico.characteristics = [pedido, resposta]
        log("bluetooth/periférico: publicando o serviço invertido")
        g.add(servico)
    }

    private func fecharTodas(_ motivo: String) {
        guard !sessoes.isEmpty else { return }
        log("bluetooth/periférico: fechando \(sessoes.count) enlace(s): \(motivo)")
        for s in sessoes.values { s.saiu = true; s.portao.fechar(); s.fluxo.fechar() }
        sessoes = [:]
        avisosPendentes = [:]
    }

    // MARK: Estado e anúncio

    func peripheralManagerDidUpdateState(_ g: CBPeripheralManager) {
        if g.state != ultimoEstado {
            log("bluetooth/periférico: estado do rádio \(g.state.rawValue) (\(Self.texto(g.state)))")
            ultimoEstado = g.state
        }
        if g.state == .poweredOn {
            conferir()
        } else {
            // Desligado ou reiniciando: o serviço sai do ar, então publica de novo quando voltar (limpando o antigo antes).
            plano.aoMudarEstado(ligado: false)
            fecharTodas("rádio fora (\(Self.texto(g.state)))")
        }
    }

    func peripheralManager(_ g: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log("bluetooth/periférico: não consegui publicar o serviço (\(error.localizedDescription))")
            plano.aoPublicar(erro: true)
            return
        }
        log("bluetooth/periférico: serviço publicado")
        plano.aoPublicar(erro: false)
        conferir()
    }

    func peripheralManagerDidStartAdvertising(_ g: CBPeripheralManager, error: Error?) {
        plano.aoAnunciar()
        if let error {
            log("bluetooth/periférico: não consegui anunciar (\(error.localizedDescription))")
        } else {
            log("bluetooth/periférico: anunciando (isAdvertising=\(g.isAdvertising))")
        }
        // O pedido pode ter sido dispensado enquanto o anúncio subia.
        if !plano.desejado, g.isAdvertising { g.stopAdvertising(); log("bluetooth/periférico: anúncio parado") }
    }

    // MARK: Enlaces

    func peripheralManager(_ g: CBPeripheralManager, central: CBCentral, didSubscribeTo c: CBCharacteristic) {
        let id = central.identifier
        let rotulo = "inv-\(id.uuidString.prefix(8))"
        log("bluetooth/periférico: o Mac \(rotulo) assinou \(c.uuid.uuidString) (pacote de até \(central.maximumUpdateValueLength) bytes)")
        guard c.uuid == uuidPedido else { return }
        if let velha = sessoes.removeValue(forKey: id) { velha.saiu = true; velha.portao.fechar(); velha.fluxo.fechar() }
        let s = Sessao(central)
        s.fluxo = FluxoEnlace(
            escritor: { [weak self, weak s] dados in
                guard let self, let s else { return false }
                return escrever(dados, em: s)
            },
            aoFechar: { [weak self, weak s] in
                self?.fila.async {
                    guard let self, let s else { return }
                    s.portao.fechar()
                    if self.sessoes[id] === s { self.sessoes[id] = nil }
                    guard !s.saiu, let car = self.pedido else { return }
                    // O periférico não derruba a central: avisa o Mac com uma notificação vazia (EnlaceInvertido).
                    let foi = self.gerente?.updateValue(EnlaceInvertido.avisoDeFechar, for: car, onSubscribedCentrals: [s.central]) ?? false
                    if !foi { self.avisosPendentes[id] = s.central }
                    self.log("bluetooth/periférico: fechei o enlace com \(rotulo) e avisei o Mac (\(foi ? "enviado" : "fila cheia, vai quando o rádio liberar"))")
                }
            })
        sessoes[id] = s
        if let receptor {
            let fluxo: FluxoBytes = s.fluxo
            DispatchQueue.global().async { receptor(fluxo, rotulo) }
        } else {
            log("bluetooth/periférico: ninguém para receber o enlace de \(rotulo), fechei")
            s.fluxo.fechar()
        }
    }

    func peripheralManager(_ g: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom c: CBCharacteristic) {
        log("bluetooth/periférico: o Mac inv-\(central.identifier.uuidString.prefix(8)) saiu de \(c.uuid.uuidString)")
        if c.uuid == uuidPedido { avisosPendentes[central.identifier] = nil }
        guard c.uuid == uuidPedido, let s = sessoes.removeValue(forKey: central.identifier) else { return }
        s.saiu = true
        s.portao.fechar()
        s.fluxo.fechar()
    }

    func peripheralManager(_ g: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        log("bluetooth/periférico: leitura de \(request.characteristic.uuid.uuidString), recusei")
        g.respond(to: request, withResult: .readNotPermitted)
    }

    func peripheralManager(_ g: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests where r.characteristic.uuid == uuidResposta {
            let rotulo = "inv-\(r.central.identifier.uuidString.prefix(8))"
            guard let s = sessoes[r.central.identifier] else {
                log("bluetooth/periférico: escrita de \(rotulo) (\(r.value?.count ?? 0) bytes) sem enlace aberto, ignorei")
                continue
            }
            // Cada resposta do Mac são várias escritas: só a primeira de cada enlace entra no diário.
            if s.primeiraEscrita {
                s.primeiraEscrita = false
                log("bluetooth/periférico: primeira escrita recebida de \(rotulo) (\(r.value?.count ?? 0) bytes)")
            }
            if let v = r.value { s.fluxo.fila.empurrar(v) }
        }
        if let primeiro = requests.first { g.respond(to: primeiro, withResult: .success) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers g: CBPeripheralManager) {
        if let car = pedido {
            for (id, central) in avisosPendentes where g.updateValue(EnlaceInvertido.avisoDeFechar, for: car, onSubscribedCentrals: [central]) {
                avisosPendentes[id] = nil
                log("bluetooth/periférico: aviso de fechar enviado a inv-\(id.uuidString.prefix(8))")
            }
        }
        for s in sessoes.values { s.portao.liberar() }
    }

    /// Parte em pacotes do tamanho do MTU e respeita a fila de notificações. Roda na thread de quem escreve, nunca na fila do rádio.
    private func escrever(_ dados: Data, em s: Sessao) -> Bool {
        guard let car = pedido else { return false }
        var tamanho = 20
        fila.sync { tamanho = max(20, s.central.maximumUpdateValueLength) }
        return Pacotes.escrever(dados, tamanho: tamanho, enviar: { [self] parte in
            guard !s.portao.estaFechado else { return false }
            s.portao.armar()
            var enviou = false
            fila.sync {
                enviou = gerente?.updateValue(parte, for: car, onSubscribedCentrals: [s.central]) ?? false
                if !enviou, Date().timeIntervalSince(s.filaCheiaNoLog) >= 5 {
                    s.filaCheiaNoLog = Date()
                    log("bluetooth/periférico: fila de notificações cheia, esperando o rádio liberar")
                }
            }
            return enviou
        }, aguardar: { s.portao.esperar(5) })
    }
}
#endif
