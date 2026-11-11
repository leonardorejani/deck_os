import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Bytes de um soquete POSIX atrás de um protocolo, para os testes trocarem por um par de soquetes.
// Compila no iPhone, no Mac e no Linux do CI. O espelho do lado do Mac é mac/Nucleo/Soquete.swift.

protocol FluxoBytes: AnyObject, Sendable {
    /// Bloqueia até chegar algo. nil quando a conexão acabou ou deu erro.
    func ler(maximo: Int) -> Data?
    /// Escreve tudo ou devolve false. Nunca derruba o processo com SIGPIPE.
    func escrever(_ dados: Data) -> Bool
    /// Acorda quem está lendo e impede novas escritas. O descritor só fecha quando o objeto some.
    func fechar()
}

extension FluxoBytes {
    func lerExato(_ n: Int) -> Data? {
        var saida = Data()
        while saida.count < n {
            guard let parte = ler(maximo: n - saida.count), !parte.isEmpty else { return nil }
            saida.append(parte)
        }
        return saida
    }
}

final class Soquete: FluxoBytes, @unchecked Sendable {
    private let fd: Int32

    init(fd: Int32) {
        self.fd = fd
        #if canImport(Darwin)
        var um: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &um, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    deinit { _ = close(fd) }

    func ler(maximo: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: maximo)
        while true {
            let n = read(fd, &buffer, maximo)
            if n > 0 { return Data(buffer[0..<n]) }
            if n < 0 && errno == EINTR { continue }
            return nil
        }
    }

    func escrever(_ dados: Data) -> Bool {
        #if canImport(Glibc)
        let bandeiras = Int32(MSG_NOSIGNAL)
        #else
        let bandeiras: Int32 = 0
        #endif
        return dados.withUnsafeBytes { bruto -> Bool in
            guard let base = bruto.baseAddress else { return true }
            var enviado = 0
            while enviado < bruto.count {
                let n = send(fd, base + enviado, bruto.count - enviado, bandeiras)
                if n > 0 { enviado += n; continue }
                if n < 0 && errno == EINTR { continue }
                return false
            }
            return true
        }
    }

    func fechar() { _ = shutdown(fd, Int32(SHUT_RDWR)) }

    static var tipoStream: Int32 {
        #if canImport(Glibc)
        return Int32(SOCK_STREAM.rawValue)
        #else
        return SOCK_STREAM
        #endif
    }
}

/// Escuta TCP só no loopback (127.0.0.1) do aparelho. Ninguém da rede alcança: quem chega aqui veio
/// pelo usbmuxd, ou seja, pelo cabo.
final class Ouvinte: @unchecked Sendable {
    private let fd: Int32
    let porta: UInt16

    /// nil se a porta não abriu (já em uso, por exemplo).
    init?(porta: UInt16) {
        let fd = socket(AF_INET, Soquete.tipoStream, 0)
        guard fd >= 0 else { return nil }
        var sim: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &sim, socklen_t(MemoryLayout<Int32>.size))
        var fim = sockaddr_in()
        fim.sin_family = sa_family_t(AF_INET)
        fim.sin_port = porta.bigEndian
        fim.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let ok = withUnsafePointer(to: &fim) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0, listen(fd, 4) == 0 else { _ = close(fd); return nil }
        self.fd = fd
        self.porta = porta
    }

    /// Bloqueia até chegar uma conexão. nil quando o ouvinte foi fechado. Olha a cada 0,3 s se pediram
    /// para fechar: no Darwin, shutdown e close de outra thread não acordam um accept parado.
    func aceitar() -> Soquete? {
        while true {
            if estaFechado { return nil }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let n = poll(&p, 1, 300)
            if n == 0 || (n < 0 && errno == EINTR) { continue }
            if n < 0 || p.revents & Int16(POLLIN) == 0 { return nil }
            let c = accept(fd, nil, nil)
            if c >= 0 { return Soquete(fd: c) }
            if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { continue }
            return nil
        }
    }

    private let trava = NSLock()
    private var fechado = false
    private var estaFechado: Bool { trava.withLock { fechado } }

    /// Pede para o laço de `aceitar` terminar. O descritor fecha no deinit, quando a thread do laço soltar o objeto.
    func fechar() { trava.withLock { fechado = true } }

    deinit { _ = close(fd) }
}
