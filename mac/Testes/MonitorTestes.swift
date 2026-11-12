import XCTest
@testable import Nucleo

/// Sonda de mentira: cada leitura devolve o próximo valor da fila e conta quantas vezes foi chamada.
private final class SondaFalsa: SondaDoMac, @unchecked Sendable {
    var cpus: [(UInt64, UInt64)?] = []
    var memoriaValor: (UInt64, UInt64)? = (8, 16)
    var bateriaValor: (Int, Bool)? = (80, false)
    var redes: [(UInt64, UInt64)?] = []
    var chamadas = (cpu: 0, memoria: 0, bateria: 0, rede: 0)
    var gpuValor: Int? = 40
    var discoValor: (UInt64, UInt64)? = (250, 1000)
    var energiaValor: (Double, Bool)? = (12.34, false)
    var ventoinhasValor: ([Int], Int)? = ([1800, 2000], 6000)
    var usbValor: Int? = 3
    var chamadasNovas = 0

    func cpu() -> (ocupado: UInt64, total: UInt64)? { chamadas.cpu += 1; return cpus.isEmpty ? nil : cpus.removeFirst().map { (ocupado: $0.0, total: $0.1) } }
    func memoria() -> (usada: UInt64, total: UInt64)? { chamadas.memoria += 1; return memoriaValor.map { (usada: $0.0, total: $0.1) } }
    func bateria() -> (nivel: Int, naTomada: Bool)? { chamadas.bateria += 1; return bateriaValor.map { (nivel: $0.0, naTomada: $0.1) } }
    func gpu() -> Int? { chamadasNovas += 1; return gpuValor }
    func disco() -> (livre: UInt64, total: UInt64)? { chamadasNovas += 1; return discoValor.map { (livre: $0.0, total: $0.1) } }
    func energia() -> (watts: Double, carregando: Bool)? { chamadasNovas += 1; return energiaValor.map { (watts: $0.0, carregando: $0.1) } }
    func ventoinhas() -> (rpm: [Int], maximo: Int)? { chamadasNovas += 1; return ventoinhasValor.map { (rpm: $0.0, maximo: $0.1) } }
    func dispositivosUsb() -> Int? { chamadasNovas += 1; return usbValor }
    func rede() -> (entrada: UInt64, saida: UInt64)? { chamadas.rede += 1; return redes.isEmpty ? nil : redes.removeFirst().map { (entrada: $0.0, saida: $0.1) } }
}

private extension ConfigMonitor {
    /// Os quatro itens de antes ligados e os da tela do Monitor de Atividade (12/11/2026) desligados: o que estes testes cobrem é o que já existia.
    static func antigos(cpu: Bool = true, memoria: Bool = true, bateria: Bool = true, rede: Bool = true) -> ConfigMonitor {
        ConfigMonitor(cpu: cpu, memoria: memoria, bateria: bateria, rede: rede, gpu: false, disco: false, energia: false, ventoinhas: false, dispositivos: false)
    }
}

final class MonitorTestes: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_794_400_000)

    func testProcessadorPrecisaDeDuasMedidasEDaOPercentualDoIntervalo() {
        let s = SondaFalsa(); s.cpus = [(100, 1000), (130, 1100)]
        let f = FonteMonitor(sonda: s)
        XCTAssertNil(f.ler(ConfigMonitor(), agora: t0).cpu, "primeira leitura não tem com o que comparar")
        // 30 de 100 ticks ocupados no intervalo
        XCTAssertEqual(f.ler(ConfigMonitor(), agora: t0 + 3).cpu, 30)
    }

    func testMemoriaBateriaEMacSemBateria() {
        let s = SondaFalsa(); s.memoriaValor = (12, 16)
        let f = FonteMonitor(sonda: s)
        var e = f.ler(ConfigMonitor(), agora: t0)
        XCTAssertEqual(e.memoria, 75)
        XCTAssertEqual(e.bateria, 80); XCTAssertEqual(e.naTomada, false)
        s.bateriaValor = nil
        e = f.ler(ConfigMonitor(), agora: t0 + 3)
        XCTAssertNil(e.bateria); XCTAssertNil(e.naTomada, "Mac de mesa: sem bateria, sem tomada")
    }

    func testBateriaForaDaFaixaFicaPresa() {
        let s = SondaFalsa(); s.bateriaValor = (140, true)
        XCTAssertEqual(FonteMonitor(sonda: s).ler(ConfigMonitor(), agora: t0).bateria, 100)
    }

    func testRedeEhBytesPorSegundoEOContadorDe32BitsQueVoltaAZeroNaoViraNegativo() {
        let s = SondaFalsa()
        s.redes = [(1000, 500), (11_000, 2_500), (0xFFFF_FF00, 2_500), (0x100, 2_500)]
        let f = FonteMonitor(sonda: s)
        var e = f.ler(ConfigMonitor(), agora: t0)
        XCTAssertNil(e.baixa); XCTAssertNil(e.sobe)
        e = f.ler(ConfigMonitor(), agora: t0 + 2)
        XCTAssertEqual(e.baixa, 5000); XCTAssertEqual(e.sobe, 1000)
        _ = f.ler(ConfigMonitor(), agora: t0 + 4)
        e = f.ler(ConfigMonitor(), agora: t0 + 6) // 0xFFFFFF00 -> 0x100 passou do limite: 0x200 bytes em 2 s
        XCTAssertEqual(e.baixa, 0x200 / 2)
    }

    func testItemEscondidoNemChegaASerMedido() {
        let s = SondaFalsa(); s.cpus = [(1, 2)]; s.redes = [(1, 1)]
        let f = FonteMonitor(sonda: s)
        let e = f.ler(ConfigMonitor.antigos(cpu: false, bateria: false, rede: false), agora: t0)
        XCTAssertEqual(s.chamadas.cpu, 0); XCTAssertEqual(s.chamadas.bateria, 0); XCTAssertEqual(s.chamadas.rede, 0)
        XCTAssertEqual(s.chamadas.memoria, 1)
        XCTAssertNil(e.cpu); XCTAssertNil(e.bateria); XCTAssertNil(e.baixa)
        XCTAssertEqual(e.itens, ["memoria"], "o painel desenha só o que a pessoa deixou ligado")
        XCTAssertEqual(e.memoria, 50)
    }

    // MARK: - Itens da tela do Monitor de Atividade: GPU, disco, energia, ventoinhas e dispositivos

    func testGpuDiscoEnergiaVentoinhasEDispositivosSaemDaSonda() {
        let e = FonteMonitor(sonda: SondaFalsa()).ler(ConfigMonitor(), agora: t0)
        XCTAssertEqual(e.gpu, 40)
        XCTAssertEqual(e.discoLivre, 250); XCTAssertEqual(e.discoTotal, 1000)
        XCTAssertEqual(e.watts, 12.3, "watts com uma casa"); XCTAssertEqual(e.carregando, false)
        XCTAssertEqual(e.ventoinhas, [1800, 2000]); XCTAssertEqual(e.ventoinhaMax, 6000)
        XCTAssertEqual(e.dispositivos, 3)
        XCTAssertEqual(e.itens, ["cpu", "memoria", "bateria", "rede", "gpu", "disco", "energia", "ventoinhas", "dispositivos"])
    }

    func testMedidaQueOMacNaoLeSomeSemInventarNada() {
        let s = SondaFalsa(); s.gpuValor = nil; s.discoValor = nil; s.energiaValor = nil; s.ventoinhasValor = nil; s.usbValor = nil
        let e = FonteMonitor(sonda: s).ler(ConfigMonitor(), agora: t0)
        XCTAssertNil(e.gpu); XCTAssertNil(e.discoLivre); XCTAssertNil(e.discoTotal); XCTAssertNil(e.watts); XCTAssertNil(e.carregando)
        XCTAssertNil(e.ventoinhas); XCTAssertNil(e.ventoinhaMax); XCTAssertNil(e.dispositivos)
        let sem = SondaFalsa(); sem.ventoinhasValor = ([], 0)
        XCTAssertNil(FonteMonitor(sonda: sem).ler(ConfigMonitor(), agora: t0).ventoinhas, "lista vazia é Mac sem ventoinha")
    }

    func testItemNovoDesligadoNaoEMedido() {
        let s = SondaFalsa()
        let e = FonteMonitor(sonda: s).ler(ConfigMonitor.antigos(), agora: t0)
        XCTAssertEqual(s.chamadasNovas, 0)
        XCTAssertNil(e.gpu); XCTAssertNil(e.dispositivos)
        XCTAssertEqual(e.itens, ["cpu", "memoria", "bateria", "rede"])
    }

    func testMedidasNovasFicamPresasNaFaixa() {
        let s = SondaFalsa(); s.gpuValor = 180; s.discoValor = (2000, 1000); s.energiaValor = (-5, true)
        let e = FonteMonitor(sonda: s).ler(ConfigMonitor(), agora: t0)
        XCTAssertEqual(e.gpu, 100); XCTAssertEqual(e.discoLivre, 1000); XCTAssertEqual(e.watts, 0)
    }

    func testConfigAntigaSemOsItensNovosLigaTodos() throws {
        let c = try JSONDecoder().decode(ConfigMonitor.self, from: Data(#"{"cpu":true,"memoria":false,"bateria":true,"rede":true}"#.utf8))
        XCTAssertTrue(c.gpu && c.disco && c.energia && c.ventoinhas && c.dispositivos)
        XCTAssertFalse(c.memoria)
        let desligado = try JSONDecoder().decode(ConfigMonitor.self, from: Data(#"{"gpu":false}"#.utf8))
        XCTAssertFalse(desligado.gpu); XCTAssertTrue(desligado.disco)
    }

    #if os(macOS)
    /// O SMC só aceita a chamada com o struct de 80 bytes (como em C). Com 76 (sem o preenchimento) as ventoinhas nunca eram lidas.
    func testStructDoSMCTemOsOitentaBytesDoC() {
        XCTAssertEqual(LeitorSMC.tamanhoDoStruct, 80)
    }

    /// A sonda de verdade deste Mac: o que ela devolver tem de estar na faixa, e o que não souber ler é nil (sem travar).
    func testSondaRealDesteMacDevolveValoresNaFaixa() {
        let s = SondaReal()
        if let g = s.gpu() { XCTAssertTrue((0...100).contains(g), "gpu \(g)") }
        if let d = s.disco() { XCTAssertTrue(d.total > 0 && d.livre <= d.total, "disco \(d)") }
        if let e = s.energia() { XCTAssertTrue(e.watts >= 0 && e.watts < 400, "watts \(e.watts)") }
        if let v = s.ventoinhas() { XCTAssertTrue(v.rpm.allSatisfy { $0 >= 0 && $0 < 20000 } && v.maximo >= 0, "ventoinhas \(v)") }
        if let n = s.dispositivosUsb() { XCTAssertTrue(n >= 0 && n < 500, "usb \(n)") }
    }
    #endif

    func testMedidaVelhaNaoServeDeBaseDepoisDoBlocoFicarDesligado() {
        let s = SondaFalsa(); s.cpus = [(100, 1000), (900, 1100)]
        let f = FonteMonitor(sonda: s)
        _ = f.ler(ConfigMonitor(), agora: t0)
        // 10 minutos depois: a média de 10 minutos não é o uso de agora
        XCTAssertNil(f.ler(ConfigMonitor(), agora: t0 + 600).cpu)
    }

    // MARK: - Config e estado

    func testMonitorNasceDesligadoEComTodosOsItensEConfigAntigaContinuaIgual() throws {
        let antiga = #"{"perfis":[{"id":"p","nome":"P","teclas":[]}],"perfilAtivo":"p","comp":"a","contas":[],"blocos":{"spotify":true},"nomeMac":"M","porta":4777,"codigoAcesso":"abcdefghjkmnpqrstuvw"}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(antiga.utf8))
        XCTAssertFalse(c.blocos.monitor, "quem já usa o Deck não ganha um bloco novo na tela")
        XCTAssertEqual(c.monitor, ConfigMonitor())
        XCTAssertTrue(c.monitor.cpu && c.monitor.memoria && c.monitor.bateria && c.monitor.rede)
        XCTAssertNil(Config.validar(c))
    }

    func testItemQueFaltaFicaLigadoEOQueFoiDesligadoVolta() throws {
        let c = try JSONDecoder().decode(ConfigMonitor.self, from: Data(#"{"rede":false}"#.utf8))
        XCTAssertEqual(c, ConfigMonitor(cpu: true, memoria: true, bateria: true, rede: false))
        let ida = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(ConfigMonitor.self, from: ida), c)
    }

    func testPutDePainelVelhoSemMonitorNaoApagaAEscolha() throws {
        var atual = config(perfil: [])
        atual.blocos.monitor = true
        atual.monitor = ConfigMonitor(cpu: false, memoria: true, bateria: false, rede: false)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(atual)) as! [String: Any]
        json.removeValue(forKey: "monitor")
        json.removeValue(forKey: "codigoAcesso")
        json["blocos"] = ["spotify": true, "agenda": true, "whatsapp": true, "sessoes": true, "uso": true]
        let corpo = try JSONSerialization.data(withJSONObject: json)
        guard case .success(let nova) = Config.receber(corpo: corpo, sobre: atual) else { return XCTFail("PUT recusado") }
        XCTAssertEqual(nova.monitor, atual.monitor)
    }

    func testComposicaoCValeEDDa() {
        var c = config(perfil: [])
        c.comp = "c"; XCTAssertNil(Config.validar(c))
        c.comp = "d"; XCTAssertEqual(Config.validar(c), "A composição da tela deve ser A, B ou C.")
    }

    private func fontesComMonitor(_ chamadas: Contador, valor: EstadoMonitor = EstadoMonitor(cpu: 12, memoria: 40, bateria: 90, naTomada: true, baixa: 100, sobe: 50)) -> Fontes {
        var f = Fontes(
            sessoes: { Leitura(valor: [], aviso: nil) }, uso: { _, _ in Leitura(valor: [], aviso: nil) },
            whatsapp: { Leitura(valor: nil, aviso: nil) }, seloWhatsApp: { nil },
            spotify: { _ in Leitura(valor: nil, aviso: nil) }, capa: { nil },
            agenda: { _ in Leitura(valor: nil, aviso: nil) }, acesas: { _ in [] })
        f.monitor = { _, _ in chamadas.somar(); return Leitura(valor: valor, aviso: nil) }
        return f
    }

    func testEstadoSoTrazOMonitorComOBlocoLigadoEAlgumItem() {
        let chamadas = Contador()
        let ag = Agregador(fontes: fontesComMonitor(chamadas))
        var c = config(perfil: [])
        XCTAssertNil(ag.estado(config: c, agora: t0).monitor, "padrão: desligado")
        c.blocos.monitor = true
        c.monitor = ConfigMonitor.antigos(cpu: false, memoria: false, bateria: false, rede: false)
        XCTAssertNil(ag.estado(config: c, agora: t0).monitor, "ligado sem nenhum item: nada a mostrar")
        XCTAssertEqual(chamadas.valor, 0, "e nada foi medido")
        c.monitor = ConfigMonitor()
        XCTAssertEqual(ag.estado(config: c, agora: t0).monitor?.cpu, 12)
        XCTAssertEqual(chamadas.valor, 1)
    }

    func testEstadoComMonitorVoltaIgualDepoisDeCodificar() throws {
        var c = config(perfil: [])
        c.blocos.monitor = true
        let e = Agregador(fontes: fontesComMonitor(Contador())).estado(config: c, agora: t0)
        let volta = try JSONDecoder().decode(Estado.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(volta.monitor, e.monitor)
        XCTAssertEqual(e.monitor?.baixa, 100)
    }
}
