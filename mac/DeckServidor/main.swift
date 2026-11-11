#if os(macOS)
import Foundation
@testable import Nucleo

// Sobe o servidor do Deck neste Mac. Os tipos do núcleo são internos, por isso o @testable: este
// executável só roda em compilação de debug, como prova, não é o app.
//
// Uso: DeckServidor [--porta N] [--config arquivo.json] [--pagina pasta] [--falso] [--sem-cabo] [--porta-cabo N]
// Padrão: peças reais e a config de ~/Library/Application Support/Deck/config.json (criada se não
// existir, nunca sobrescrita). --falso usa dados de exemplo, sem tocar em nada deste Mac.
// O cabo (iPhone plugado, pelo usbmuxd) liga junto: --sem-cabo desliga e --porta-cabo muda a porta do app no iPhone.
// O Bluetooth (o Mac anuncia o serviço do Deck) também: --sem-bluetooth desliga, --bt-permitir aceita sozinho todo
// pareamento (só para prova: o normal é a pessoa conferir o código e digitar s ou n aqui) e --bt-vazao troca a sessão
// por uma medida de vazão do rádio, sem criptografia e sem painel.

func uso(_ erro: String) -> Never {
    FileHandle.standardError.write(Data("\(erro)\nUso: DeckServidor [--porta N] [--config arquivo.json] [--pagina pasta] [--falso] [--sem-cabo] [--porta-cabo N] [--sem-bluetooth] [--bt-permitir] [--bt-vazao]\n".utf8))
    exit(2)
}

var portaPedida: Int?
var arquivoConfig: String?
var pastaPagina: String?
var falso = false
var comCabo = true
var comBluetooth = true
var btPermitir = false
var btVazao = false
var portaDoCabo = Int(PortaDoCabo.portaDoAparelho)
var restante = CommandLine.arguments.dropFirst()
while let a = restante.popFirst() {
    switch a {
    case "--falso": falso = true
    case "--sem-cabo": comCabo = false
    case "--sem-bluetooth": comBluetooth = false
    case "--bt-permitir": btPermitir = true
    case "--bt-vazao": btVazao = true
    case "--porta-cabo":
        guard let v = restante.popFirst(), let n = Int(v), (1024...65535).contains(n) else { uso("--porta-cabo pede um número de 1024 a 65535.") }
        portaDoCabo = n
    case "--porta":
        guard let v = restante.popFirst(), let n = Int(v), (1024...65535).contains(n) else { uso("--porta pede um número de 1024 a 65535.") }
        portaPedida = n
    case "--config":
        guard let v = restante.popFirst() else { uso("--config pede o caminho do arquivo.") }
        arquivoConfig = v
    case "--pagina":
        guard let v = restante.popFirst() else { uso("--pagina pede o caminho da pasta.") }
        pastaPagina = v
    default: uso("Não conheço \"\(a)\".")
    }
}

/// painel/ na raiz do repo se existir, senão prototipo/. Procura a partir da pasta atual e do executável.
func pastaDaPagina() -> String {
    let fm = FileManager.default
    var pontos = [URL(fileURLWithPath: fm.currentDirectoryPath)]
    pontos.append(URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent())
    for nome in ["painel", "prototipo"] {
        for inicio in pontos {
            var dir = inicio
            for _ in 0..<8 {
                let candidata = dir.appendingPathComponent(nome)
                var ehPasta: ObjCBool = false
                if fm.fileExists(atPath: candidata.path, isDirectory: &ehPasta), ehPasta.boolValue,
                   fm.fileExists(atPath: dir.appendingPathComponent("SPEC.md").path) { return candidata.path }
                dir = dir.deletingLastPathComponent()
            }
        }
    }
    uso("Não achei a pasta painel/ nem prototipo/. Passe --pagina.")
}

nonisolated(unsafe) var retemRadio: AnyObject?

do {
    let pagina = ArquivosPagina(raiz: URL(fileURLWithPath: pastaPagina ?? pastaDaPagina()))
    let pareamento = Pareamento()
    let rodizio = Rodizio()
    let roteador: Roteador
    let porta: Int

    if falso {
        porta = portaPedida ?? 4790
        let config = ConfigEmMemoria(Config(
            perfis: [Perfil(id: "geral", nome: "Geral", teclas: [
                Tecla(id: "acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k", estado: nil, icone: nil),
                Tecla(id: "quebrada", nome: "Quebrada", tipo: "comando", valor: "false", estado: nil, icone: nil),
            ])],
            perfilAtivo: "geral", nomeMac: "Mac de teste", porta: porta, codigoAcesso: "provaprovaprovaprova"))
        roteador = Roteador(paineis: PaineisDeExemplo(config: config), teclas: TeclasDeExemplo(), spotify: SpotifyDeExemplo(),
                            config: config, pareamento: pareamento, pagina: pagina, rodizio: rodizio)
        print("Modo falso: dados de exemplo. Código de acesso de teste: provaprovaprovaprova")
    } else {
        let alvo = arquivoConfig.map { URL(fileURLWithPath: $0) } ?? ArmazemConfig.urlPadrao
        let armazem = try ArmazemEmDisco(ArmazemConfig(url: alvo, nomeMac: Ligacao.nomeDoMac()))
        porta = portaPedida ?? armazem.ler().porta
        roteador = Ligacao.roteador(armazem: armazem, pareamento: pareamento, pagina: pagina, rodizio: rodizio)
        print("Config: \(alvo.path)")
    }

    let gerador = GeradorCertificado()
    let arquivos = try gerador.garantir()
    let identidade = try gerador.carregarIdentidade(arquivos)
    let rede = try gerador.lerRede()
    let servidor = ServidorHttps(roteador: roteador, identidade: identidade, porta: UInt16(porta))
    try servidor.iniciar()

    print("Página: \(pagina.raiz.path)")
    print("Endereço: https://\(rede.nome):\(porta)/" + (rede.ip.map { "  (ou https://\($0):\(porta)/)" } ?? ""))
    print("Código de pareamento: \(pareamento.gerar())")
    print("Certificado para instalar no iPhone: \(arquivos.ca.path)")
    if comCabo {
        let nome = roteador.config.ler().nomeMac
        PortaDoCabo(roteador: roteador, nomeMac: { nome }, porta: UInt16(portaDoCabo)).iniciar()
        print("Cabo: procurando iPhone no USB (app escutando na porta \(portaDoCabo) do aparelho)")
    }
    #if canImport(CoreBluetooth) && canImport(CryptoKit)
    if comBluetooth {
        let nome = roteador.config.ler().nomeMac
        let log: @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        if btVazao {
            let radio = RadioPeriferico(nome: { nome }, aoAbrir: { fluxo, rotulo in
                log("bluetooth \(rotulo): medindo vazão")
                VazaoBluetooth.servir(fluxo)
                log("bluetooth \(rotulo): medida terminou")
            }, log: log)
            radio.iniciar()
            retemRadio = radio
        } else {
            let permitirTodos = btPermitir
            // O servidor de teste abre a janela de pareamento por 10 minutos ao subir. No app do Mac ela abre
            // com "Parear outro iPhone" em Conectar iPhone.
            let janelaAte = Date().addingTimeInterval(600)
            retemRadio = PortaDoBluetooth.ligar(roteador: roteador, nomeMac: { nome }, decidir: { iphone, codigo in
                if permitirTodos { return true }
                print("Pareamento por Bluetooth: \(iphone) mostra o código \(codigo). Confere nas duas telas? (s/n)")
                fflush(stdout)
                return (readLine() ?? "n").lowercased().hasPrefix("s")
            }, pareamentoAberto: { Date() < janelaAte },
               desistiu: { codigo in print("O iPhone do código \(codigo) saiu. Pedido cancelado.") },
               log: log)
        }
        print("Bluetooth: anunciando como \"\(nome)\"" + (btVazao ? " (modo vazão)" : ""))
    }
    #endif
    fflush(stdout)
    dispatchMain()
} catch {
    FileHandle.standardError.write(Data("Não deu para subir o servidor: \(error)\n".utf8))
    exit(1)
}
#else
print("O DeckServidor só roda no macOS.")
#endif
