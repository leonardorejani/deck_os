import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Bytes de um soquete POSIX atrás de um protocolo, para o cabo e o usbmuxd compartilharem o código e
// os testes trocarem por um par de soquetes. Compila no Mac e no Linux do CI.

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

    /// Conecta num soquete unix (o usbmuxd do macOS).
    static func conectarUnix(_ caminho: String) -> Soquete? {
        let fd = socket(AF_UNIX, tipoStream, 0)
        guard fd >= 0 else { return nil }
        var fim = sockaddr_un()
        fim.sun_family = sa_family_t(AF_UNIX)
        let capacidade = MemoryLayout.size(ofValue: fim.sun_path)
        let bytes = Array(caminho.utf8)
        guard bytes.count < capacidade else { _ = close(fd); return nil }
        withUnsafeMutablePointer(to: &fim.sun_path) { p in
            p.withMemoryRebound(to: UInt8.self, capacity: capacidade) { d in
                for (i, b) in bytes.enumerated() { d[i] = b }
                d[bytes.count] = 0
            }
        }
        let ok = withUnsafePointer(to: &fim) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { _ = close(fd); return nil }
        return Soquete(fd: fd)
    }
}
