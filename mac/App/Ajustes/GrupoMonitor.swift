import SwiftUI

/// O grupo "Monitor do Mac" de Este Mac: um bloco pequeno no iPhone com processador, memória, bateria e rede, e a tela do
/// Monitor de Atividade, que ainda mostra GPU, disco, energia, ventoinhas e dispositivos (só o que este Mac conseguir ler).
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
                    item("GPU", "Quanto da placa de vídeo está em uso. Na tela do Monitor de Atividade", c.monitor.gpu) { $0.monitor.gpu = $1 }
                    item("Disco", "O espaço livre. Na tela do Monitor de Atividade", c.monitor.disco) { $0.monitor.disco = $1 }
                    item("Energia", "Os watts que o Mac usa agora. Na tela do Monitor de Atividade", c.monitor.energia) { $0.monitor.energia = $1 }
                    item("Ventoinhas", "A rotação em RPM. Some em Mac sem ventoinha. Na tela do Monitor de Atividade", c.monitor.ventoinhas) { $0.monitor.ventoinhas = $1 }
                    item("Dispositivos", "Quantos dispositivos USB estão conectados. Na tela do Monitor de Atividade", c.monitor.dispositivos) { $0.monitor.dispositivos = $1 }
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
