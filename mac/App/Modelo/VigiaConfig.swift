import Foundation

/// Avisa quando o config.json muda no disco (o iPhone grava pelo PUT). Vigia a pasta e não o
/// arquivo, porque a gravação do núcleo troca o arquivo por cima (rename) e o descritor de arquivo
/// aberto ficaria apontando para o antigo.
final class VigiaConfig {
    private var fonte: DispatchSourceFileSystemObject?
    private var pendente: DispatchWorkItem?

    init?(arquivo: URL, atraso: TimeInterval = 0.15, aoMudar: @escaping () -> Void) {
        let pasta = arquivo.deletingLastPathComponent()
        let fd = open(pasta.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let f = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        f.setEventHandler { [weak self] in
            // Várias escritas seguidas (arquivo temporário e troca) viram um aviso só.
            self?.pendente?.cancel()
            let item = DispatchWorkItem(block: aoMudar)
            self?.pendente = item
            DispatchQueue.main.asyncAfter(deadline: .now() + atraso, execute: item)
        }
        f.setCancelHandler { close(fd) }
        f.resume()
        fonte = f
    }

    func parar() {
        pendente?.cancel()
        fonte?.cancel()
        fonte = nil
    }

    deinit { parar() }
}
