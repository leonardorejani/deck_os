import AppKit
import CoreGraphics

/// Captura a tecla antes de qualquer atalho global de outro app (CleanShot, Raycast...), só enquanto o gravador
/// está ouvindo. O monitor local do AppKit só vê a tecla que sobrou para o Deck: o atalho de outro app dispara
/// antes e a combinação nunca chega. Um CGEventTap na sessão enxerga a tecla primeiro e a engole.
///
/// Precisa da Acessibilidade (a mesma que o Deck já pede para teclar). Sem ela `iniciar` devolve nil e o gravador
/// cai no monitor local. Como o tap engole teclado do sistema inteiro, ele sempre morre sozinho: ao parar, quando
/// o Deck deixa de ser o app da frente e depois de `limite` segundos.
final class CapturaDeTecla {
    struct Tecla { var codigo: UInt16; var controle: Bool; var opcao: Bool; var comando: Bool; var shift: Bool }

    private var porta: CFMachPort?
    private var fonte: CFRunLoopSource?
    private var saiuDaFrente: NSObjectProtocol?
    private var relogio: DispatchWorkItem?
    private let aoApertar: (Tecla) -> Void
    private let aoAcabar: () -> Void

    /// Tempo máximo de escuta: o tap não pode prender o teclado se a tela esquecer de parar.
    static let limite: TimeInterval = 30

    private init(aoApertar: @escaping (Tecla) -> Void, aoAcabar: @escaping () -> Void) {
        self.aoApertar = aoApertar
        self.aoAcabar = aoAcabar
    }

    /// Liga a captura. Nil quando o macOS não deixa criar o tap (sem Acessibilidade).
    static func iniciar(aoApertar: @escaping (Tecla) -> Void, aoAcabar: @escaping () -> Void) -> CapturaDeTecla? {
        guard AcoesSistema.temAcessibilidade() else { return nil }
        let c = CapturaDeTecla(aoApertar: aoApertar, aoAcabar: aoAcabar)
        let mascara = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let gancho: CGEventTapCallBack = { _, tipo, evento, contexto in
            guard let contexto else { return Unmanaged.passUnretained(evento) }
            return Unmanaged<CapturaDeTecla>.fromOpaque(contexto).takeUnretainedValue().receber(tipo, evento)
        }
        guard let porta = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: mascara, callback: gancho,
                                            userInfo: Unmanaged.passUnretained(c).toOpaque()) else { return nil }
        c.porta = porta
        c.fonte = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, porta, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), c.fonte, .commonModes)
        CGEvent.tapEnable(tap: porta, enable: true)
        c.saiuDaFrente = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak c] _ in c?.acabar() }
        let item = DispatchWorkItem { [weak c] in c?.acabar() }
        c.relogio = item
        DispatchQueue.main.asyncAfter(deadline: .now() + limite, execute: item)
        return c
    }

    /// Desliga o tap. Pode ser chamada mais de uma vez.
    func parar() {
        if let porta { CGEvent.tapEnable(tap: porta, enable: false); CFMachPortInvalidate(porta) }
        if let fonte { CFRunLoopRemoveSource(CFRunLoopGetMain(), fonte, .commonModes) }
        porta = nil; fonte = nil
        relogio?.cancel(); relogio = nil
        if let o = saiuDaFrente { NotificationCenter.default.removeObserver(o); saiuDaFrente = nil }
    }

    private func acabar() {
        guard porta != nil else { return }
        parar()
        aoAcabar()
    }

    /// Roda na thread principal (o tap está no run loop principal). Engole toda tecla enquanto escuta.
    private func receber(_ tipo: CGEventType, _ evento: CGEvent) -> Unmanaged<CGEvent>? {
        switch tipo {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let porta { CGEvent.tapEnable(tap: porta, enable: true) }
            return Unmanaged.passUnretained(evento)
        case .keyDown:
            let f = evento.flags
            let t = Tecla(codigo: UInt16(truncatingIfNeeded: evento.getIntegerValueField(.keyboardEventKeycode)),
                          controle: f.contains(.maskControl), opcao: f.contains(.maskAlternate),
                          comando: f.contains(.maskCommand), shift: f.contains(.maskShift))
            // Fora do ciclo do tap: quem recebe pode parar a captura e mexer na tela.
            DispatchQueue.main.async { [weak self] in if self?.porta != nil { self?.aoApertar(t) } }
            return nil
        default:
            return nil
        }
    }

    deinit { parar() }
}
