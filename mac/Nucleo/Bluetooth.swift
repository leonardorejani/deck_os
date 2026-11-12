import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// Terceira porta de entrada do Deck: o Bluetooth LE. Igual ao HTTPS e ao cabo, só traduz o canal em
// HttpRequisicao e de volta, e quem responde é o mesmo Roteador. Aqui o Mac é o periférico: anuncia o
// serviço do Deck, o iPhone (central) conecta e assina a característica de resposta, e cada assinante vira
// uma sessão. O Bluetooth é lento e aberto ao ar, então a sessão só começa depois do aperto de mão cifrado
// (EnlaceSeguro) e o estado vai enxuto (capa pequena, ver CapaPequena).

/// A capa do Spotify pesa dezenas de KB e o Bluetooth leva poucas dezenas de KB por segundo, então neste
/// canal ela vai reduzida (ou não vai, sem ImageIO). O tamanho vem da vazão medida (docs/provas/fase-7-bluetooth.md).
enum CapaPequena {
    /// Lado maior, em pixels, da capa que segue pelo Bluetooth.
    static let lado = 200
    static let qualidade = 0.6

    /// JPEG reduzido, ou nil se não deu para reduzir.
    static func reduzir(_ dados: Data, lado: Int = CapaPequena.lado, qualidade: Double = CapaPequena.qualidade) -> Data? {
        #if canImport(ImageIO)
        guard let origem = CGImageSourceCreateWithData(dados as CFData, nil) else { return nil }
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
        ]
        guard let miniatura = CGImageSourceCreateThumbnailAtIndex(origem, 0, opcoes as CFDictionary) else { return nil }
        let saida = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(saida, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destino, miniatura, [kCGImageDestinationLossyCompressionQuality: qualidade] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return saida as Data
        #else
        return nil
        #endif
    }

    /// Troca a capa grande pela pequena nas respostas do Bluetooth. O resto passa como veio.
    static func ajustar(_ pedido: PedidoCabo, _ resposta: RespostaRota) -> RespostaRota {
        guard pedido.caminho == "/api/capa", resposta.status == 200 else { return resposta }
        guard let menor = reduzir(resposta.corpo) else { return .erro(404, "Sem capa neste canal.") }
        var nova = resposta
        nova.tipo = "image/jpeg"
        nova.corpo = menor
        return nova
    }
}

/// Garante que o Mac volte a anunciar o serviço depois de qualquer queda. O macOS pode parar o anúncio sem avisar
/// (conexão que acabou, suspensão, rádio que reiniciou) e, parado, nenhum iPhone acha o Mac nem conecta: o log
/// ficava mudo por horas. Quem usa chama `conferir` depois de cada queda e num relógio, e cada retomada vai para o log.
final class VigiaDoAnuncio: @unchecked Sendable {
    private let anunciando: () -> Bool
    private let iniciar: () -> Void
    private let log: @Sendable (String) -> Void
    private let trava = NSLock()
    private var _retomadas = 0

    init(anunciando: @escaping () -> Bool, iniciar: @escaping () -> Void, log: @escaping @Sendable (String) -> Void) {
        self.anunciando = anunciando
        self.iniciar = iniciar
        self.log = log
    }

    var retomadas: Int { trava.withLock { _retomadas } }

    /// Se o anúncio parou, anuncia de novo e registra o motivo. Devolve true quando precisou retomar.
    @discardableResult
    func conferir(_ motivo: String) -> Bool {
        guard !anunciando() else { return false }
        trava.withLock { _retomadas += 1 }
        log("bluetooth: o anúncio tinha parado (\(motivo)). Anunciando de novo.")
        iniciar()
        return true
    }
}

#if canImport(CryptoKit)
/// O que acontece com cada iPhone que conecta pelo Bluetooth: aperto de mão cifrado e, se passar, a sessão
/// de pedidos e respostas (a mesma do cabo, em cima do fio cifrado).
final class PortaDoBluetooth: @unchecked Sendable {
    private let roteador: Roteador
    private let nomeMac: @Sendable () -> String
    private let decidir: @Sendable (String, String) -> Bool
    private let desistiu: @Sendable (String) -> Void
    private let pareamentoAberto: @Sendable () -> Bool
    private let agora: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)?
    private let trava = NSLock()
    private var ativas = 0
    /// Um pareamento por vez: quem escuta o ar não pode encher a tela do Mac de pedidos.
    private var pareando = false
    /// Quando cada pedido de pareamento chegou à tela, para limitar a taxa.
    private var pedidos: [Date] = []
    static let limiteDeSessoes = 4
    /// No máximo tantos pedidos na tela do Mac por janela de tempo, vindos de quem estiver no ar.
    static let pedidosPorJanela = 3
    static let janelaDeTaxa: TimeInterval = 60

    /// `decidir(iphone, codigo)` mostra o código de 6 dígitos na tela do Mac e devolve a escolha da pessoa.
    /// `pareamentoAberto` diz se a pessoa pediu para parear um iPhone agora (Conectar iPhone): fora disso, quem
    /// pede para parear é recusado sem aparecer na tela. `desistiu(codigo)` avisa que o iPhone saiu antes da
    /// resposta, para a tela tirar o pedido.
    init(roteador: Roteador, nomeMac: @escaping @Sendable () -> String, decidir: @escaping @Sendable (String, String) -> Bool,
         pareamentoAberto: @escaping @Sendable () -> Bool = { false },
         desistiu: @escaping @Sendable (String) -> Void = { _ in },
         agora: @escaping @Sendable () -> Date = { Date() },
         log: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
         aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)? = nil) {
        self.aoAtender = aoAtender
        self.roteador = roteador
        self.nomeMac = nomeMac
        self.decidir = decidir
        self.pareamentoAberto = pareamentoAberto
        self.desistiu = desistiu
        self.agora = agora
        self.log = log
    }

    var sessoesAtivas: Int { trava.withLock { ativas } }

    /// Bloqueia até o iPhone sair. Chamar numa thread própria.
    func atender(_ fluxo: FluxoBytes, rotulo: String) {
        defer { fluxo.fechar() }
        guard reservar() else {
            log("bluetooth \(rotulo): sessões demais, recusei")
            return
        }
        defer { trava.withLock { ativas -= 1 } }

        let nome = nomeMac()
        let cfg = EnlaceSeguro.ConfigServidor(
            nomeMac: nome,
            chaves: { [roteador, agora] in Self.chavesVigentes(roteador.config.ler(), agora: agora()) },
            codigoAcesso: { [roteador] in roteador.config.ler().codigoAcesso },
            decidir: { [self] iphone, codigo in decidirUm(iphone, codigo, rotulo, fluxo) })
        let seguro: FluxoCifrado
        do { seguro = try EnlaceSeguro.servir(fluxo, cfg) } catch {
            log("bluetooth \(rotulo): aperto de mão não passou (\(error))")
            return
        }
        log("bluetooth \(rotulo): conexão cifrada")
        SessaoCabo(fluxo: seguro, roteador: roteador, nomeMac: nome, rotulo: "bluetooth/\(rotulo)", log: log, ajustar: CapaPequena.ajustar, aoAtender: aoAtender).rodar()
        log("bluetooth \(rotulo): caiu")
    }

    /// Os códigos que abrem o Bluetooth agora: o atual e, na folga de 10 min do rodízio, o anterior. Sem o anterior,
    /// um iPhone que ainda não recebeu o código novo é tratado como desconhecido e o app dele esquece o pareamento.
    static func chavesVigentes(_ c: Config, agora: Date) -> [String] {
        var chaves = [c.codigoAcesso]
        if let anterior = c.codigoAnterior, Int(agora.timeIntervalSince1970) < (c.anteriorValeAte ?? 0) { chaves.append(anterior) }
        return chaves
    }

    private func reservar() -> Bool {
        trava.withLock {
            if ativas >= Self.limiteDeSessoes { return false }
            ativas += 1
            return true
        }
    }

    private func iniciarPareamento() -> Bool {
        trava.withLock {
            if pareando { return false }
            pareando = true
            return true
        }
    }

    /// Conta o pedido na janela de tempo. Falso quando já chegaram demais.
    private func dentroDoLimite() -> Bool {
        trava.withLock {
            let t = agora()
            pedidos.removeAll { t.timeIntervalSince($0) >= Self.janelaDeTaxa }
            if pedidos.count >= Self.pedidosPorJanela { return false }
            pedidos.append(t)
            return true
        }
    }

    private func decidirUm(_ iphone: String, _ codigo: String, _ rotulo: String, _ fluxo: FluxoBytes) -> Bool {
        guard pareamentoAberto() else {
            log("bluetooth \(rotulo): pedido de pareamento fora da hora, recusei")
            return false
        }
        guard dentroDoLimite() else {
            log("bluetooth \(rotulo): pedidos de pareamento demais, recusei")
            return false
        }
        guard iniciarPareamento() else {
            log("bluetooth \(rotulo): já tem um pareamento em curso, recusei este")
            return false
        }
        defer { trava.withLock { pareando = false } }
        // O código aparece no log só no pareamento, que é quando a pessoa precisa dele na tela. Em uso normal nunca.
        log("bluetooth \(rotulo): \(iphone) quer parear, código \(codigo)")

        // A pergunta roda à parte para o fio poder ser vigiado: se o iPhone sai antes da resposta, a trava do
        // pareamento solta e o iPhone de verdade que chega depois não fica recusado.
        final class Resposta: @unchecked Sendable { var valor = false }
        let r = Resposta()
        let pronta = DispatchSemaphore(value: 0)
        let pergunta = decidir
        Thread { r.valor = pergunta(iphone, codigo); pronta.signal() }.start()
        while pronta.wait(timeout: .now() + 0.2) == .timedOut {
            if (fluxo as? FluxoEnlace)?.fila.estaFechada == true {
                log("bluetooth \(rotulo): o iPhone saiu antes da resposta, tirei o pedido")
                desistiu(codigo)
                return false
            }
        }
        return r.valor
    }
}
#endif

#if canImport(CoreBluetooth) && canImport(CryptoKit)
extension PortaDoBluetooth {
    /// Liga o Bluetooth do Mac: anuncia o serviço do Deck e atende cada iPhone que conecta. O app do Mac chama isto
    /// uma vez ao abrir e guarda o rádio para pará-lo (`parar()`) ao sair. `decidir` mostra o código de 6 dígitos
    /// na tela do Mac (menu da barra e Ajustes > Conectar iPhone) e devolve a escolha da pessoa, Permitir ou Recusar.
    static func ligar(roteador: Roteador, nomeMac: @escaping @Sendable () -> String, decidir: @escaping @Sendable (String, String) -> Bool,
                      pareamentoAberto: @escaping @Sendable () -> Bool, desistiu: @escaping @Sendable (String) -> Void = { _ in },
                      log: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
                      aoAtender: (@Sendable (_ rotulo: String, _ caminho: String, _ status: Int) -> Void)? = nil) -> RadioPeriferico {
        let porta = PortaDoBluetooth(roteador: roteador, nomeMac: nomeMac, decidir: decidir, pareamentoAberto: pareamentoAberto, desistiu: desistiu, log: log, aoAtender: aoAtender)
        let radio = RadioPeriferico(nome: nomeMac, aoAbrir: { fluxo, rotulo in porta.atender(fluxo, rotulo: rotulo) }, log: log)
        radio.iniciar()
        return radio
    }
}
#endif

#if canImport(CoreBluetooth)
/// O rádio do Mac: anuncia o serviço do Deck e entrega cada iPhone que assina a resposta como um FluxoBytes.
final class RadioPeriferico: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private final class Sessao: @unchecked Sendable {
        let central: CBCentral
        var fluxo: FluxoEnlace!
        let espera = NSCondition()
        var pronto = true
        init(central: CBCentral) { self.central = central }
    }

    private let fila = DispatchQueue(label: "deck.bluetooth.periferico")
    private let nome: @Sendable () -> String
    private let aoAbrir: @Sendable (FluxoEnlace, String) -> Void
    private let log: @Sendable (String) -> Void
    private var gerente: CBPeripheralManager!
    private var resposta: CBMutableCharacteristic?
    private var sessoes: [UUID: Sessao] = [:]
    private var montado = false
    private var semSessao: Set<UUID> = []
    private var vigia: VigiaDoAnuncio!
    private var relogio: DispatchSourceTimer?
    private var ultimoEstado: CBManagerState?
    /// De quanto em quanto tempo se confere se o Mac ainda anuncia.
    static let intervaloDaVigia: TimeInterval = 15
    private let uuidServico = CBUUID(string: EnlaceBle.servico)
    private let uuidPedido = CBUUID(string: EnlaceBle.pedido)
    private let uuidResposta = CBUUID(string: EnlaceBle.resposta)

    /// `aoAbrir` roda numa thread própria a cada iPhone que assina, e bloqueia até ele sair.
    init(nome: @escaping @Sendable () -> String, aoAbrir: @escaping @Sendable (FluxoEnlace, String) -> Void,
         log: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }) {
        self.nome = nome
        self.aoAbrir = aoAbrir
        self.log = log
    }

    func iniciar() {
        fila.async { [self] in
            gerente = CBPeripheralManager(delegate: self, queue: fila, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
            vigia = VigiaDoAnuncio(anunciando: { [self] in gerente.isAdvertising }, iniciar: { [self] in anunciar() }, log: log)
            let t = DispatchSource.makeTimerSource(queue: fila)
            t.schedule(deadline: .now() + Self.intervaloDaVigia, repeating: Self.intervaloDaVigia)
            t.setEventHandler { [weak self] in self?.vigiar("conferência periódica") }
            t.resume()
            relogio = t
        }
    }

    func parar() {
        fila.async { [self] in
            relogio?.cancel()
            relogio = nil
            gerente?.stopAdvertising()
            for s in sessoes.values { s.fluxo.fechar() }
            sessoes = [:]
        }
    }

    // MARK: Estado e anúncio

    /// Anuncia o serviço do Deck. Só roda com o serviço publicado e o rádio ligado.
    private func anunciar() {
        guard montado, gerente.state == .poweredOn else { return }
        log("bluetooth: (re)iniciando o anúncio (isAdvertising=\(gerente.isAdvertising))")
        gerente.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [uuidServico], CBAdvertisementDataLocalNameKey: nome()])
    }

    /// Roda na fila: refaz o anúncio parado e, se o serviço não chegou a ser publicado, publica de novo.
    private func vigiar(_ motivo: String) {
        guard let gerente, gerente.state == .poweredOn else { return }
        if !montado {
            log("bluetooth: o serviço não estava publicado (\(motivo)). Publicando de novo.")
            montar(gerente)
            return
        }
        vigia.conferir(motivo)
    }

    private func montar(_ p: CBPeripheralManager) {
        montado = true
        let pedido = CBMutableCharacteristic(type: uuidPedido, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let resp = CBMutableCharacteristic(type: uuidResposta, properties: [.notify], value: nil, permissions: [.readable])
        resposta = resp
        let servico = CBMutableService(type: uuidServico, primary: true)
        servico.characteristics = [pedido, resp]
        p.add(servico)
    }

    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        if p.state != ultimoEstado { log("bluetooth: estado do rádio do Mac \(p.state.rawValue)"); ultimoEstado = p.state }
        switch p.state {
        case .poweredOn:
            guard !montado else { vigia.conferir("o rádio voltou a ligar"); return }
            montar(p)
        case .unauthorized:
            log("bluetooth: o Mac não deixou o Deck usar o Bluetooth. Libere em Ajustes do Sistema > Privacidade e Segurança > Bluetooth.")
        case .poweredOff:
            log("bluetooth: o Bluetooth do Mac está desligado")
            montado = false
            for s in sessoes.values { s.fluxo.fechar() }
            sessoes = [:]
        default:
            break
        }
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { log("bluetooth: não consegui publicar o serviço (\(error.localizedDescription))"); montado = false; return }
        log("bluetooth: serviço publicado, iniciando o anúncio")
        p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [uuidServico], CBAdvertisementDataLocalNameKey: nome()])
    }

    func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        if let error { log("bluetooth: não consegui anunciar (\(error.localizedDescription))") } else { log("bluetooth: anunciando o serviço do Deck como \"\(nome())\" (isAdvertising=\(p.isAdvertising))") }
    }

    // MARK: Sessões

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral, didSubscribeTo c: CBCharacteristic) {
        log("bluetooth \(String(central.identifier.uuidString.prefix(8))): central inscreveu em \(c.uuid.uuidString) (resposta=\(c.uuid == uuidResposta))")
        guard c.uuid == uuidResposta, resposta != nil else { return }
        let id = central.identifier
        if let velha = sessoes[id] { velha.fluxo.fechar() }
        let sessao = Sessao(central: central)
        sessao.fluxo = FluxoEnlace(
            escritor: { [weak self, weak sessao] dados in
                guard let self, let sessao else { return false }
                return escrever(dados, em: sessao)
            },
            aoFechar: { [weak self, weak sessao] in
                self?.fila.async { if let s = sessao, self?.sessoes[id] === s { self?.sessoes[id] = nil } }
            })
        sessoes[id] = sessao
        semSessao.remove(id)
        let rotulo = String(id.uuidString.prefix(8))
        log("bluetooth \(rotulo): iPhone assinou (pacote de até \(central.maximumUpdateValueLength) bytes)")
        let t = Thread { [aoAbrir, weak self] in
            aoAbrir(sessao.fluxo, rotulo)
            // A sessão acabou (o iPhone saiu ou o aperto de mão falhou): confere o anúncio, que o macOS pode ter parado.
            self?.fila.async { self?.vigiar("sessão \(rotulo) acabou") }
        }
        t.name = "deck.bluetooth.\(rotulo)"
        t.start()
    }

    func peripheralManager(_ p: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom c: CBCharacteristic) {
        log("bluetooth \(String(central.identifier.uuidString.prefix(8))): central saiu de \(c.uuid.uuidString)")
        guard c.uuid == uuidResposta else { return }
        log("bluetooth \(String(central.identifier.uuidString.prefix(8))): iPhone saiu")
        if let s = sessoes.removeValue(forKey: central.identifier) { s.fluxo.fechar() }
        vigiar("iPhone saiu")
    }

    /// A resposta só notifica, então leitura não era esperada. O macOS segura o pedido até alguém responder, então responde recusando.
    func peripheralManager(_ p: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        log("bluetooth \(String(request.central.identifier.uuidString.prefix(8))): leitura de \(request.characteristic.uuid.uuidString) (offset \(request.offset)), recusei")
        p.respond(to: request, withResult: .readNotPermitted)
    }

    func peripheralManager(_ p: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Com sessão aberta cada pedido do iPhone é uma escrita: só entra no log a escrita de quem não tem sessão.
        for r in requests where sessoes[r.central.identifier] == nil {
            log("bluetooth \(String(r.central.identifier.uuidString.prefix(8))): escrita em \(r.characteristic.uuid.uuidString) (\(r.value?.count ?? 0) bytes) sem sessão")
        }
        for r in requests where r.characteristic.uuid == uuidPedido {
            if let dados = r.value, let s = sessoes[r.central.identifier] { s.fluxo.fila.empurrar(dados) }
            else if sessoes[r.central.identifier] == nil, !semSessao.contains(r.central.identifier) {
                // Pedido de quem ainda está conectado mas cuja sessão acabou: o iPhone detecta o silêncio e refaz a conexão.
                semSessao.insert(r.central.identifier)
                log("bluetooth \(String(r.central.identifier.uuidString.prefix(8))): pedido de iPhone sem sessão aberta, ignorei")
            }
        }
        if let primeiro = requests.first { p.respond(to: primeiro, withResult: .success) }
    }

    /// O rádio esvaziou a fila de notificações: quem estava esperando pode mandar mais.
    func peripheralManagerIsReady(toUpdateSubscribers p: CBPeripheralManager) {
        for s in sessoes.values {
            s.espera.lock(); s.pronto = true; s.espera.broadcast(); s.espera.unlock()
        }
    }

    /// Parte em pacotes do tamanho do MTU e respeita a fila do rádio. Roda na thread de quem escreve, nunca na fila do rádio.
    private func escrever(_ dados: Data, em sessao: Sessao) -> Bool {
        guard let resp = resposta else { return false }
        let tamanho = max(20, sessao.central.maximumUpdateValueLength)
        var inicio = 0
        while inicio < dados.count {
            let fim = min(inicio + tamanho, dados.count)
            let parte = Data(dados[dados.startIndex + inicio ..< dados.startIndex + fim])
            while true {
                sessao.espera.lock(); sessao.pronto = false; sessao.espera.unlock()
                var enviou = false
                fila.sync { enviou = gerente.updateValue(parte, for: resp, onSubscribedCentrals: [sessao.central]) }
                if enviou { break }
                sessao.espera.lock()
                let limite = Date().addingTimeInterval(5)
                while !sessao.pronto {
                    if !sessao.espera.wait(until: limite) { sessao.espera.unlock(); return false }
                }
                sessao.espera.unlock()
            }
            inicio = fim
        }
        return true
    }
}
#endif
