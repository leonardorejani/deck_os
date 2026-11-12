import SwiftUI

/// O grupo "Monitor do Mac" de Este Mac: um bloco pequeno no iPhone com processador, memória, bateria e rede.
/// Nasce desligado, e cada item se liga ou desliga aqui, porque a tela do iPhone não tem muito espaço.
struct GrupoMonitor: View {
    @ObservedObject var modelo: ModeloApp

    var body: some View {
        let c = modelo.config
        GrupoDeAjuste(titulo: "Monitor do Mac", nota: c.blocos.monitor ? nil : "Um bloco pequeno no iPhone com o que o Mac está usando agora") {
            LinhasDeAjuste {
                LinhaDeAjuste(titulo: "Mostrar no iPhone", apoio: "Só aparece o que você deixar ligado abaixo") {
                    ChaveDeAjuste(rotulo: "Mostrar o monitor no iPhone", ligada: c.blocos.monitor) { v in modelo.gravar { $0.blocos.monitor = v } }
                }
                if c.blocos.monitor {
                    item("Processador", "Quanto do processador está em uso", c.monitor.cpu) { $0.monitor.cpu = $1 }
                    item("Memória", "Quanto da memória está em uso", c.monitor.memoria) { $0.monitor.memoria = $1 }
                    item("Bateria", "A carga e se está na tomada. Some em Mac sem bateria", c.monitor.bateria) { $0.monitor.bateria = $1 }
                    item("Rede", "A velocidade de download e de upload", c.monitor.rede) { $0.monitor.rede = $1 }
                }
            }
        }
    }

    private func item(_ titulo: String, _ apoio: String, _ ligado: Bool, _ mudar: @escaping (inout Config, Bool) -> Void) -> some View {
        LinhaDeAjuste(titulo: titulo, apoio: apoio, divisoria: true) {
            ChaveDeAjuste(rotulo: titulo, ligada: ligado) { v in modelo.gravar { mudar(&$0, v) } }
        }
    }
}
