import SwiftUI
import ServiceManagement

/// Cada tela do app que o renderizador fotografa, com os mesmos dados de exemplo do protótipo
/// (prototipo/dados.js e o estado de partida de prototipo/mac.js). A parte que preenche uma tela nova
/// acrescenta uma entrada aqui e a mesma tela em `prototipo-fotos.mjs`, com o mesmo nome.
struct TelaParaFoto {
    var nome: String
    var tamanho: CGSize?   // nil = o tamanho que a própria tela pede
    var vista: () -> AnyView
}

enum DadosDeExemplo {
    /// Perfis do protótipo (dados.js): Trabalho e Ensaio. Teclas ficam para as telas que as mostram.
    @MainActor static func config() -> Config {
        Config(perfis: perfis(),
               perfilAtivo: "trabalho", comp: "a", contas: [], blocos: Blocos(), nomeMac: "MacBook Pro de Exemplo",
               porta: 4777, codigoAcesso: "abcdefghjkmnpqrstuvw")
    }

    /// Perfis de exemplo (dados.js, PERFIS_LEO): Trabalho e Ensaio, cada um com as suas teclas.
    static func perfis() -> [Perfil] {
        let acordado = "pmset -g assertions | grep -q 'Vorssaint: keep the Mac awake'"
        return [
            Perfil(id: "trabalho", nome: "Trabalho", teclas: [
                Tecla(id: "acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k", estado: acordado, icone: "Vorssaint"),
                Tecla(id: "whatsapp", nome: "WhatsApp", tipo: "app", valor: "WhatsApp", estado: nil, icone: "WhatsApp"),
                Tecla(id: "calendario", nome: "Agenda", tipo: "app", valor: "Calendar", estado: nil, icone: "Calendar"),
                Tecla(id: "apagar", nome: "Apagar tela", tipo: "comando", valor: "pmset displaysleepnow", estado: nil, icone: "svg:tela"),
            ]),
            Perfil(id: "ensaio", nome: "Ensaio", teclas: [
                Tecla(id: "e-acordado", nome: "Manter acordado", tipo: "tecla", valor: "ctrl+opt+cmd+k", estado: acordado, icone: "Vorssaint"),
                Tecla(id: "e-spotify", nome: "Spotify", tipo: "app", valor: "Spotify", estado: nil, icone: "Spotify"),
                Tecla(id: "e-cifras", nome: "Cifras", tipo: "app", valor: "Notes", estado: nil, icone: "Notes"),
                Tecla(id: "e-agenda", nome: "Agenda", tipo: "app", valor: "Calendar", estado: nil, icone: "Calendar"),
                Tecla(id: "e-apagar", nome: "Apagar tela", tipo: "comando", valor: "pmset displaysleepnow", estado: nil, icone: "svg:tela"),
            ]),
        ]
    }

    /// Os apps de mentira do protótipo (dados.js, APPS e TODOS_APPS), com os mesmos ícones. 37 ao todo.
    @MainActor static var catalogo: CatalogoDeApps {
        let pasta = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("prototipo/icones").path
        let comIcone: [(String, String)] = [("Vorssaint", "vorssaint"), ("Spotify", "spotify"), ("WhatsApp", "whatsapp"), ("Calendar", "calendario"),
                                            ("Safari", "safari"), ("Notes", "notas"), ("Terminal", "terminal"), ("Finder", "finder")]
        let mais = comIcone.map { AppDoMac(nome: $0.0, valor: $0.0, caminhoDoIcone: "\(pasta)/\($0.1).png") }
        let outros = ["Ableton Live", "App Store", "Arc", "Atalhos", "Calculadora", "Contatos", "Discord", "FaceTime", "Figma", "Final Cut Pro", "Fotos",
                      "GarageBand", "Google Chrome", "Lembretes", "Logic Pro", "Mail", "Mapas", "Mensagens", "Música", "Notion", "OBS", "Obsidian",
                      "Prévia", "ProPresenter", "Slack", "Ajustes do Sistema", "Visual Studio Code", "Xcode", "Zoom"]
            .map { AppDoMac(nome: $0, valor: $0, caminhoDoIcone: nil) }
        let todos = (mais + outros).sorted { $0.nome.compare($1.nome, locale: Locale(identifier: "pt_BR")) == .orderedAscending }
        return CatalogoDeApps(apps: todos, maisUsados: mais,
                              atalhos: ["Hora do Dia", "Modo Ensaio", "Ligar Luzes", "Enviar Mensagem", "Iniciar Gravação", "Foco: Trabalho", "Converter Imagem", "Dividir Conta"])
    }

    /// O iPhone do protótipo: "Conectado pelo Wi-Fi desde 09:12", iOS 26.
    static var iphoneDeExemplo: IphonePareado {
        IphonePareado(nome: "iPhone de Exemplo", desde: Calendar.current.date(bySettingHour: 9, minute: 12, second: 0, of: Date()), ios: "iOS 26")
    }

    /// Versão e data do protótipo (mac.js, TELAS.sobre).
    static var informacoesDoApp: InformacoesDoApp {
        InformacoesDoApp(versao: "0.1", compilacao: "1", atualizadoEm: DateComponents(calendar: .current, year: 2026, month: 11, day: 10).date!, macOS: "macOS 26")
    }

    /// O app nativo do protótipo (mac.js, natSecao): pareado por Bluetooth, "agora", instalado em 10/11/2026.
    static func nativoDeExemplo(canal: CanalIphone = .bluetooth) -> AppNativo {
        let agora = Self.agoraFixo
        return AppNativo(nome: "iPhone de Exemplo", canal: canal, desde: Calendar.current.date(bySettingHour: 9, minute: 12, second: 0, of: agora)!, visto: agora)
    }

    /// A renovação do protótipo: em dia (próxima em 3 dias), tentando de novo, ou o prazo apertando (vence em 2 dias).
    static func renovacaoDeExemplo(_ ren: String) -> RenovacaoDoApp {
        let dia = { (d: Int, h: Int) in Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }
        let instalado = dia(10, 9)
        switch ren {
        case "pendente": return RenovacaoDoApp(instaladoEm: instalado, versao: "0.1 (1)", renovadoEm: dia(5, 10))
        case "falhou": return RenovacaoDoApp(instaladoEm: instalado, versao: "0.1 (1)", renovadoEm: dia(4, 22))
        default: return RenovacaoDoApp(instaladoEm: instalado, versao: "0.1 (1)", renovadoEm: dia(8, 10))
        }
    }


    @MainActor static func modelo(iphone: Bool = true, recusados: [AcessoMac] = [.automacao, .discoTotal], inicialFeita: Bool = true,
                                  secao: SecaoAjustes = .teclas, contas: [ContaIA] = [], nativo: AppNativo? = nil,
                                  pedido: PedidoDePareamento? = nil, renovacao: RenovacaoDoApp = RenovacaoDoApp()) -> ModeloApp {
        // "Abrir junto com o Mac" ligado, como no protótipo (M.login = true).
        var c = config()
        c.contas = contas
        let m = ModeloApp(config: c, iphone: iphone ? iphoneDeExemplo : nil,
                          acessosRecusados: recusados, configuracaoInicialFeita: inicialFeita,
                          abrirComMac: AbrirComMac(servico: ServicoDeLoginLigado()),
                          nativo: nativo, pedidoBluetooth: pedido, renovacao: renovacao)
        m.relogio = { agoraFixo }
        m.secao = secao
        return m
    }
}

// Contas e uso de exemplo (prototipo/dados.js, USO). O relógio do protótipo é parado em 10/11/2026 12h.
extension DadosDeExemplo {
    static let claudeLeo = ContaIA(id: "claude-leo", nome: "Claude", conta: "leo", perfil: "leo", mostrar: nil)
    static let claudeEquipe = ContaIA(id: "claude-equipe", nome: "Claude", conta: "equipe", perfil: "equipe", mostrar: nil)
    static let codexPro = ContaIA(id: "codex", nome: "Codex", conta: "pro", perfil: nil, mostrar: nil)

    static let agoraFixo: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    static func dia(_ dia: Int, _ hora: Int) -> String {
        Datas.iso(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora))!)
    }

    /// Painel com o uso do protótipo: leo 61% (sex 14h), equipe 77% (dom 9h), pro 4% (qua 22h).
    @MainActor static func painelUso(equipe: Int = 77, conta: EstadoConta? = nil, achadas: [ContaEncontrada] = [],
                                     sobre: String? = nil, foco: Bool = false) -> PainelUso {
        let p = PainelUso(agora: { agoraFixo })
        p.usos = [
            "claude-leo": UsoConta(id: "claude-leo", nome: "Claude", conta: "leo", semana: 61, renova: dia(13, 14)),
            "claude-equipe": UsoConta(id: "claude-equipe", nome: "Claude", conta: "equipe", semana: equipe, renova: dia(15, 9)),
            "codex": UsoConta(id: "codex", nome: "Codex", conta: "pro", semana: 4, renova: dia(11, 22)),
        ]
        p.conta = conta
        p.achadas = achadas
        p.sobreFixo = sobre
        p.focoFixo = foco
        PainelUso.atual = p
        return p
    }

    /// Ajustes em Uso das IAs, com a janela Adicionar conta por cima quando `adicionar` vem preenchido.
    @MainActor static func usoDasIAs(contas: [ContaIA], equipe: Int = 77, adicionar: EstadoConta? = nil,
                                     achadas: [ContaEncontrada] = [], sobre: String? = nil, foco: Bool = false) -> AnyView {
        let modelo = DadosDeExemplo.modelo(secao: .uso, contas: contas)
        let painel = painelUso(equipe: equipe, conta: adicionar, achadas: achadas, sobre: sobre, foco: foco)
        return AnyView(QuadroDaJanela {
            JanelaAjustes(modelo: modelo, desenhaSemaforo: true)
                .overlay { if adicionar != nil { ContaModal(modelo: modelo, painel: painel) } }
        }.environment(\.emFoto, true))
    }
}

struct ServicoDeLoginLigado: ServicoDeLogin {
    var status: SMAppService.Status { .enabled }
    func register() throws {}
    func unregister() throws {}
}

/// A janela de Ajustes numa seção, com os dados fixos das fotos (código de pareamento, versão e data).
@MainActor
private func ajustes(_ secao: SecaoAjustes, iphone: Bool = true, recusados: [AcessoMac] = [.automacao, .discoTotal], nativo: AppNativo? = nil,
                     pedido: PedidoDePareamento? = nil, renovacao: RenovacaoDoApp = RenovacaoDoApp()) -> AnyView {
    AnyView(QuadroDaJanela { JanelaAjustes(modelo: DadosDeExemplo.modelo(iphone: iphone, recusados: recusados, secao: secao, nativo: nativo, pedido: pedido, renovacao: renovacao), desenhaSemaforo: true) }
        .environment(\.codigoDePareamentoFixo, "482913")
        .environment(\.informacoesDoAppFixas, DadosDeExemplo.informacoesDoApp))
}

/// Dados da configuração inicial (mac.js, trocarPerfil('novo')): "Usuário novo", MacBook Pro, nenhum acesso pedido.
extension DadosDeExemplo {
    @MainActor static func modeloNovo(iphone: Bool = false) -> ModeloApp {
        let c = Config(perfis: [Perfil(id: "principal", nome: "Principal", teclas: [])], perfilAtivo: "principal", comp: "a", contas: [],
                       blocos: Blocos(), nomeMac: "MacBook Pro", porta: 4777, codigoAcesso: "abcdefghjkmnpqrstuvw")
        return ModeloApp(config: c, iphone: iphone ? IphonePareado(nome: "iPhone") : nil, acessosRecusados: [], configuracaoInicialFeita: false)
    }

    static func achadasNovo() -> [ContaAchada] {
        [ContaAchada(id: "claude-pessoal", servico: "Claude", conta: "pessoal", semana: 23, renova: RenovaEm.proxima("seg 10h")),
         ContaAchada(id: "codex", servico: "Codex", conta: "plus", semana: 41, renova: RenovaEm.proxima("qui 8h"))]
    }

    /// O macOS de mentira: devolve o estado de cada acesso que a foto pede, sem abrir janela nenhuma.
    @MainActor struct PedidosDeExemplo: PedidosDeAcesso {
        var estados: [AcessoMac: EstadoDoAcesso] = [:]
        func estado(_ acesso: AcessoMac) -> EstadoDoAcesso? { estados[acesso] }
        func pedir(_ acesso: AcessoMac) async -> EstadoDoAcesso { estados[acesso] ?? .liberado }
        func abrirAjustes(_ acesso: AcessoMac) {}
    }

    @MainActor static func inicial(passo: PassoInicial, iphone: Bool = false, comp: String = "a", sem: Set<String> = [],
                                   acessos: [AcessoMac: EstadoDoAcesso] = [:]) -> AnyView {
        let modelo = modeloNovo(iphone: iphone)
        let a = AssistenteInicial(modelo: modelo, achadas: achadasNovo(), sugestoes: SugestaoDeTecla.todas,
                                  pedidos: PedidosDeExemplo(estados: acessos), codigo: "K7P 2QX",
                                  endereco: EnderecoDoMac.url(nomeMac: "MacBook Pro", porta: 4777))
        a.irPara(passo)
        a.comp = comp
        a.contasMarcadas.subtract(sem)
        return AnyView(QuadroDaJanela { ConteudoDaInicial(modelo: modelo, assistente: a) })
    }
}

@MainActor
enum CatalogoDeFotos {
    static let telas: [TelaParaFoto] = [
        TelaParaFoto(nome: "aviso", tamanho: nil) {
            AnyView(AvisoPilula(aviso: AvisoDeTela(texto: "Endereço copiado")))
        },
        // Sem foto do protótipo (ele não tem esses estados): só para olhar. Ficam com o prefixo extra-.
        TelaParaFoto(nome: "extra-aviso-falha", tamanho: nil) {
            AnyView(AvisoPilula(aviso: AvisoDeTela(texto: "Não consegui salvar a configuração do Deck.", falha: true)).padding(Tema.Espaco.pad).background(Tema.Cor.telaFundo))
        },
        TelaParaFoto(nome: "extra-iphone-servidor-falhou", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            let m = ModeloApp(config: DadosDeExemplo.config(), acessosRecusados: [.automacao, .discoTotal], servidor: .falhou("Não achei uma porta livre para o Deck."))
            m.secao = .iphone
            return AnyView(QuadroDaJanela { JanelaAjustes(modelo: m, desenhaSemaforo: true) }
                .environment(\.codigoDePareamentoFixo, "482913"))
        },
        TelaParaFoto(nome: "extra-menu-servidor-falhou", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: ModeloApp(config: DadosDeExemplo.config(), servidor: .falhou("Não achei uma porta livre para o Deck."))) })
        },
        TelaParaFoto(nome: "menu", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: DadosDeExemplo.modelo()) })
        },
        TelaParaFoto(nome: "menu-sem-iphone", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: DadosDeExemplo.modelo(iphone: false)) })
        },
        TelaParaFoto(nome: "menu-novo", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: DadosDeExemplo.modelo(iphone: false, recusados: [], inicialFeita: false)) })
        },
        TelaParaFoto(nome: "ajustes-casca", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            AnyView(QuadroDaJanela { JanelaAjustes(modelo: DadosDeExemplo.modelo(), desenhaSemaforo: true) })
        },
        TelaParaFoto(nome: "ajustes-casca-sem-iphone", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            AnyView(QuadroDaJanela { JanelaAjustes(modelo: DadosDeExemplo.modelo(iphone: false, recusados: [], secao: .sobre), desenhaSemaforo: true) })
        },
        // Suas teclas: a seção inteira, sem rolagem (a janela do protótipo cresce para o conteúdo). O ImageRenderer não
        // desenha o ScrollView da janela, por isso não há foto da janela com a seção dentro.
        teclas("teclas-app") { $0.escolher("whatsapp") },
        teclas("teclas-app-busca") { $0.escolher("whatsapp"); $0.busca = "sa" },
        teclas("teclas-teclado") { _ in },
        teclas("teclas-comando") { $0.escolher("apagar") },
        teclas("teclas-atalho", extra: Tecla(id: "t-atalho", nome: "Modo Ensaio", tipo: "atalho", valor: "Modo Ensaio", estado: nil, icone: "svg:raio")) { $0.escolher("t-atalho") },
        teclas("teclas-gravando") { $0.ouvindo = true },
        teclas("teclas-paginas", extras: ["Safari", "Notes", "Terminal", "Finder"].enumerated().map {
            Tecla(id: "t-x\($0.offset + 1)", nome: $0.element == "Notes" ? "Notas" : $0.element, tipo: "app", valor: $0.element, estado: nil, icone: $0.element)
        }) { $0.escolher("t-x4"); $0.pagina = 1 },
        teclas("teclas-ensaio") { $0.editarPerfil("ensaio") },
        teclas("teclas-vazio", vazio: true) { _ in },
        // O aviso do pé da janela, sozinho: com "Desfazer" (excluir tecla ou perfil) e simples.
        TelaParaFoto(nome: "aviso-desfazer", tamanho: nil) {
            AnyView(AvisoView(aviso: AvisoDaJanela(texto: "\"Apagar tela\" excluída", temDesfazer: true), desfazer: {}).fixedSize().clipped().environment(\.fotografando, true))
        },
        TelaParaFoto(nome: "aviso-simples", tamanho: nil) {
            AnyView(AvisoView(aviso: AvisoDaJanela(texto: "Safari escolhido", temDesfazer: false), desfazer: {}).fixedSize().clipped().environment(\.fotografando, true))
        },
        TelaParaFoto(nome: "ajustes-uso", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.claudeEquipe, DadosDeExemplo.codexPro])
        },
        TelaParaFoto(nome: "ajustes-uso-limite", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            var codex = DadosDeExemplo.codexPro
            codex.mostrar = false
            return DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.claudeEquipe, codex], equipe: 93)
        },
        TelaParaFoto(nome: "ajustes-uso-hover", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.claudeEquipe, DadosDeExemplo.codexPro], sobre: "claude-equipe")
        },
        TelaParaFoto(nome: "adicionar-conta-claude", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.codexPro], adicionar: EstadoConta(),
                                     achadas: [ContaEncontrada(conta: DadosDeExemplo.claudeEquipe)], foco: true)
        },
        TelaParaFoto(nome: "adicionar-conta-codex", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.claudeEquipe, DadosDeExemplo.codexPro],
                                     adicionar: EstadoConta(servico: "Codex"))
        },
        TelaParaFoto(nome: "adicionar-conta-erro", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            var e = EstadoConta()
            e.token = "sk-ant-oat01-curto"
            e.nome = "Trabalho"
            e.erro = TokenClaude.erroDeFormato(e.token) ?? ""
            return DadosDeExemplo.usoDasIAs(contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.codexPro], adicionar: e,
                                            achadas: [ContaEncontrada(conta: DadosDeExemplo.claudeEquipe)], foco: true)
        },
        TelaParaFoto(nome: "uso-aviso-desfazer", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            let modelo = DadosDeExemplo.modelo(secao: .uso, contas: [DadosDeExemplo.claudeLeo, DadosDeExemplo.codexPro])
            let painel = DadosDeExemplo.painelUso()
            painel.aviso = AvisoUso(texto: "Conta equipe removida", comDesfazer: true)
            return AnyView(QuadroDaJanela {
                JanelaAjustes(modelo: modelo, desenhaSemaforo: true)
                    .overlay(alignment: .bottom) { AvisoDoUso(painel: painel).padding(.bottom, Tema.Espaco.pad) }
            }.environment(\.emFoto, true))
        },
        TelaParaFoto(nome: "ajustes-iphone", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.iphone) },
        TelaParaFoto(nome: "ajustes-iphone-sem-iphone", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.iphone, iphone: false, recusados: []) },
        // App nativo (fase 5): o que o Mac mostra em Conectar iPhone e no menu em cada momento do pareamento.
        TelaParaFoto(nome: "ajustes-iphone-nativo-vazio", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            ajustes(.iphone, iphone: false, recusados: [], nativo: nil)
        },
        TelaParaFoto(nome: "ajustes-iphone-nativo-confirmar", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            ajustes(.iphone, iphone: false, recusados: [], pedido: PedidoDePareamento(iphone: "iPhone de Exemplo", codigo: "483291"))
        },
        TelaParaFoto(nome: "ajustes-iphone-nativo-pronto", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            ajustes(.iphone, iphone: false, recusados: [], nativo: DadosDeExemplo.nativoDeExemplo(), renovacao: DadosDeExemplo.renovacaoDeExemplo("ok"))
        },
        TelaParaFoto(nome: "ajustes-iphone-nativo-pendente", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            ajustes(.iphone, iphone: false, recusados: [], nativo: DadosDeExemplo.nativoDeExemplo(), renovacao: DadosDeExemplo.renovacaoDeExemplo("pendente"))
        },
        TelaParaFoto(nome: "ajustes-iphone-nativo-aperta", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) {
            ajustes(.iphone, iphone: false, recusados: [], nativo: DadosDeExemplo.nativoDeExemplo(), renovacao: DadosDeExemplo.renovacaoDeExemplo("falhou"))
        },
        TelaParaFoto(nome: "menu-nativo-confirmar", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: DadosDeExemplo.modelo(iphone: false, recusados: [], pedido: PedidoDePareamento(iphone: "iPhone de Exemplo", codigo: "483291"))) })
        },
        TelaParaFoto(nome: "menu-nativo-aperta", tamanho: nil) {
            AnyView(QuadroDoPopover { MenuDaBarra(modelo: DadosDeExemplo.modelo(iphone: false, recusados: [], nativo: DadosDeExemplo.nativoDeExemplo(), renovacao: DadosDeExemplo.renovacaoDeExemplo("falhou"))) })
        },
        TelaParaFoto(nome: "ajustes-acessos", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.permissoes) },
        TelaParaFoto(nome: "ajustes-acessos-vazio", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.permissoes, recusados: []) },
        TelaParaFoto(nome: "ajustes-este-mac", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.geral) },
        TelaParaFoto(nome: "ajustes-sobre", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.sobre) },
        TelaParaFoto(nome: "ajustes-sobre-sem-iphone", tamanho: CGSize(width: Tema.Medida.janelaLarg, height: Tema.Medida.janelaAlt)) { ajustes(.sobre, iphone: false, recusados: []) },
        // Configuração inicial: os 7 passos e os estados que mudam o desenho.
        TelaParaFoto(nome: "inicial-boas", tamanho: nil) { DadosDeExemplo.inicial(passo: .boas) },
        TelaParaFoto(nome: "inicial-iphone", tamanho: nil) { DadosDeExemplo.inicial(passo: .iphone) },
        TelaParaFoto(nome: "inicial-iphone-conectado", tamanho: nil) { DadosDeExemplo.inicial(passo: .iphone, iphone: true) },
        TelaParaFoto(nome: "inicial-layout", tamanho: nil) { DadosDeExemplo.inicial(passo: .layout) },
        TelaParaFoto(nome: "inicial-layout-b", tamanho: nil) { DadosDeExemplo.inicial(passo: .layout, comp: "b") },
        TelaParaFoto(nome: "inicial-contas", tamanho: nil) { DadosDeExemplo.inicial(passo: .contas) },
        TelaParaFoto(nome: "inicial-contas-uma", tamanho: nil) { DadosDeExemplo.inicial(passo: .contas, sem: ["codex"]) },
        TelaParaFoto(nome: "inicial-teclas", tamanho: nil) { DadosDeExemplo.inicial(passo: .teclas) },
        TelaParaFoto(nome: "inicial-acessos", tamanho: nil) { DadosDeExemplo.inicial(passo: .acessos) },
        TelaParaFoto(nome: "inicial-acessos-depois", tamanho: nil) {
            DadosDeExemplo.inicial(passo: .acessos, acessos: [.calendarios: .liberado, .automacao: .recusado])
        },
        TelaParaFoto(nome: "inicial-pronto", tamanho: nil) { DadosDeExemplo.inicial(passo: .pronto) },
        TelaParaFoto(nome: "inicial-pronto-conectado", tamanho: nil) { DadosDeExemplo.inicial(passo: .pronto, iphone: true) },
    ]

    /// A seção "Suas teclas" inteira, na largura da área de conteúdo da janela, com a margem que a janela dá.
    private static func teclas(_ nome: String, extra: Tecla? = nil, extras: [Tecla] = [], vazio: Bool = false, preparar: @escaping (ModeloTeclas) -> Void) -> TelaParaFoto {
        TelaParaFoto(nome: nome, tamanho: nil) {
            let m = DadosDeExemplo.modelo()
            m.gravar { c in c.perfis[0].teclas = vazio ? [] : c.perfis[0].teclas + (extra.map { [$0] } ?? []) + extras }
            return AnyView(
                SuasTeclas(modelo: m, catalogo: DadosDeExemplo.catalogo, acesas: ["acordado", "e-acordado"], preparar: preparar)
                    .padding(.init(top: Tema.Espaco.item, leading: Tema.Espaco.margem, bottom: Tema.Espaco.margem, trailing: Tema.Espaco.margem))
                    .frame(width: Tema.Medida.janelaLarg - 2 - Tema.Medida.lateral)
                    .background(Tema.Cor.telaFundo)
                    .environment(\.fotografando, true))
        }
    }
}
