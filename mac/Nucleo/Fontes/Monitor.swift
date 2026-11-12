import Foundation
#if os(macOS)
import Darwin
import IOKit.ps
#endif

// Monitor do Mac: processador, memória, bateria e rede. Só lê o que a pessoa deixou ligado nos Ajustes do Mac
// (ConfigMonitor), então item escondido nem chega a ser medido. Taxa (processador e rede) precisa de duas medidas:
// a primeira leitura devolve nil nesses itens e a seguinte já traz o valor.

/// O que o Mac sabe dizer de si. Só o macOS responde de verdade: no Linux do CI tudo vem nil, e os testes
/// trocam por uma sonda falsa.
protocol SondaDoMac: Sendable {
    /// Ticks do processador desde que ligou: o que esteve ocupado e o total.
    func cpu() -> (ocupado: UInt64, total: UInt64)?
    /// Memória em uso e memória total, em bytes.
    func memoria() -> (usada: UInt64, total: UInt64)?
    /// Carga da bateria interna (0 a 100) e se está na tomada. nil em Mac sem bateria.
    func bateria() -> (nivel: Int, naTomada: Bool)?
    /// Contadores de bytes das interfaces de rede (Wi-Fi, cabo). Contam 32 bits e voltam a zero.
    func rede() -> (entrada: UInt64, saida: UInt64)?
}

final class FonteMonitor: @unchecked Sendable {
    private let sonda: any SondaDoMac
    private let trava = NSLock()
    private var cpuAntes: (ocupado: UInt64, total: UInt64, quando: Date)?
    private var redeAntes: (entrada: UInt64, saida: UInt64, quando: Date)?
    private var ultimoCpu: Int?
    private var ultimaRede: (baixa: Int, sobe: Int)?

    /// Passou disso sem leitura (o bloco ficou desligado), a medida antiga não serve de base para taxa.
    static let esquecerDepoisDe: TimeInterval = 20
    /// Janela menor que isso dá taxa instável: devolve a última.
    static let janelaMinima: TimeInterval = 0.5

    init(sonda: any SondaDoMac = SondaReal()) { self.sonda = sonda }

    func ler(_ c: ConfigMonitor, agora: Date) -> EstadoMonitor {
        trava.lock(); defer { trava.unlock() }
        var e = EstadoMonitor(itens: c.itens)
        if c.cpu { e.cpu = lerCpu(agora) } else { cpuAntes = nil; ultimoCpu = nil }
        if c.memoria, let m = sonda.memoria(), m.total > 0 { e.memoria = Self.percentual(m.usada, de: m.total) }
        if c.bateria, let b = sonda.bateria() { e.bateria = max(0, min(100, b.nivel)); e.naTomada = b.naTomada }
        if c.rede {
            let r = lerRede(agora)
            e.baixa = r?.baixa; e.sobe = r?.sobe
        } else { redeAntes = nil; ultimaRede = nil }
        return e
    }

    private func lerCpu(_ agora: Date) -> Int? {
        guard let t = sonda.cpu() else { return nil }
        let antes = cpuAntes
        cpuAntes = (t.ocupado, t.total, agora)
        guard let antes, agora >= antes.quando, agora.timeIntervalSince(antes.quando) <= Self.esquecerDepoisDe else { return nil }
        guard t.total > antes.total, t.ocupado >= antes.ocupado else { return ultimoCpu }
        ultimoCpu = Self.percentual(t.ocupado - antes.ocupado, de: t.total - antes.total)
        return ultimoCpu
    }

    private func lerRede(_ agora: Date) -> (baixa: Int, sobe: Int)? {
        guard let r = sonda.rede() else { return nil }
        guard let antes = redeAntes, agora >= antes.quando, agora.timeIntervalSince(antes.quando) <= Self.esquecerDepoisDe else {
            redeAntes = (r.entrada, r.saida, agora)
            return nil
        }
        let janela = agora.timeIntervalSince(antes.quando)
        if janela < Self.janelaMinima { return ultimaRede }
        redeAntes = (r.entrada, r.saida, agora)
        func delta(_ novo: UInt64, _ velho: UInt64) -> UInt64 { (novo &- velho) & 0xFFFF_FFFF } // contador de 32 bits que volta a zero
        ultimaRede = (Int(Double(delta(r.entrada, antes.entrada)) / janela), Int(Double(delta(r.saida, antes.saida)) / janela))
        return ultimaRede
    }

    static func percentual(_ parte: UInt64, de total: UInt64) -> Int {
        guard total > 0 else { return 0 }
        return max(0, min(100, Int((Double(parte) / Double(total) * 100).rounded())))
    }
}

/// A sonda deste Mac.
struct SondaReal: SondaDoMac {
    init() {}

    #if os(macOS)
    func cpu() -> (ocupado: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var n = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &n) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let usuario = UInt64(t.0), sistema = UInt64(t.1), parado = UInt64(t.2), nice = UInt64(t.3)
        return (usuario + sistema + nice, usuario + sistema + nice + parado)
    }

    /// Ativa, fixa e comprimida: o que o Monitor de Atividade soma como "memória usada" (aproximado).
    func memoria() -> (usada: UInt64, total: UInt64)? {
        var v = vm_statistics64()
        var n = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &v) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let pagina = UInt64(getpagesize())
        return ((UInt64(v.active_count) + UInt64(v.wire_count) + UInt64(v.compressor_page_count)) * pagina, ProcessInfo.processInfo.physicalMemory)
    }

    func bateria() -> (nivel: Int, naTomada: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let fontes = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for f in fontes {
            guard let d = IOPSGetPowerSourceDescription(blob, f)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let atual = d[kIOPSCurrentCapacityKey] as? Int, let maxima = d[kIOPSMaxCapacityKey] as? Int, maxima > 0 else { continue }
            return (atual * 100 / maxima, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    func rede() -> (entrada: UInt64, saida: UInt64)? {
        var lista: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&lista) == 0, let primeiro = lista else { return nil }
        defer { freeifaddrs(lista) }
        var entrada: UInt64 = 0, saida: UInt64 = 0
        for p in sequence(first: primeiro, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let nome = i.ifa_name.map({ String(cString: $0) }), nome.hasPrefix("en"),
                  i.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let dados = i.ifa_data else { continue }
            let d = dados.assumingMemoryBound(to: if_data.self).pointee
            entrada += UInt64(d.ifi_ibytes); saida += UInt64(d.ifi_obytes)
        }
        return (entrada, saida)
    }
    #else
    func cpu() -> (ocupado: UInt64, total: UInt64)? { nil }
    func memoria() -> (usada: UInt64, total: UInt64)? { nil }
    func bateria() -> (nivel: Int, naTomada: Bool)? { nil }
    func rede() -> (entrada: UInt64, saida: UInt64)? { nil }
    #endif
}
