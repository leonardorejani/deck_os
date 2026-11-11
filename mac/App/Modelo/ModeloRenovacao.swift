import Foundation

// A renovação automática do app nativo (fase 8): liga o motor do núcleo (Nucleo/Renovacao.swift) ao modelo, guarda o
// resultado e o motivo, e roda a agenda. Sem tela aqui. O botão "Renovar agora" e o cartão amarelo já existem em
// Ajustes/ConectarIphoneNativo.swift.

extension ModeloApp {
    /// Liga o renovador de verdade e começa a vigiar a agenda. Chamado só pelo app (nunca nos testes).
    func ligarRenovacao(arquivo: URL = ArquivoDeInstalacao.urlPadrao, executor: any ExecutorDeComandos = ExecutorDeProcesso(),
                        cada intervalo: TimeInterval = AgendaDeRenovacao.checagem) {
        func motor(_ pasta: String?) -> MotorDeRenovacao { MotorDeRenovacao(executor: executor, relogio: { Date() }, pasta: { pasta },
                                                                limparPerfil: { MotorDeRenovacao.apagarPerfisDoApp() },
                                                                anotar: { LogDoDeck.padrao.escrever($0) }) }
        renovador = { [weak self] in
            guard let self else { return .falhou(.outro("o Deck fechou")) }
            self.lerInstalacao(arquivo)
            return await motor(self.pastaDoProjeto).renovar()
        }
        sondarIphone = { await motor(nil).sondar().situacao }
        lerInstalacao(arquivo)
        tarefaDaRenovacao?.cancel()
        tarefaDaRenovacao = Task { [weak self] in
            while !Task.isCancelled {
                await self?.conferirRenovacao(arquivo: arquivo)
                try? await Task.sleep(nanoseconds: UInt64(intervalo * 1_000_000_000))
            }
        }
    }

    /// Lê o que o build.sh e o instalar-iphone.sh deixaram: onde está o repo e a última instalação feita por eles.
    func lerInstalacao(_ arquivo: URL = ArquivoDeInstalacao.urlPadrao) {
        let a = ArquivoDeInstalacao.ler(arquivo)
        pastaDoProjeto = a.pasta
        if let feita = a.instaladoEm, feita > (renovacao.renovadoEm ?? .distantPast) {
            registrarRenovacao(em: feita, instaladoEm: feita, avisando: false)
            registrar("renovacao: instalação de \(Self.iso(feita)) lida do arquivo de instalação")
        }
    }

    /// Um passo da agenda: passou da hora (5 dias) e, se já falhou, o iPhone voltou ao cabo ou foi desbloqueado
    /// (ou passou 1 hora, quando o motivo não é o iPhone). Só então reinstala.
    func conferirRenovacao(arquivo: URL = ArquivoDeInstalacao.urlPadrao) async {
        lerInstalacao(arquivo)
        guard !renovando, renovador != nil else { return }
        guard AgendaDeRenovacao.devida(renovadoEm: renovacao.renovadoEm, agora: agora) else { return }
        var situacao = SituacaoDoIphone.liberado
        if falhaDaRenovacao?.motivo.dependeDoIphone == true, let sondar = sondarIphone { situacao = await sondar() }
        guard AgendaDeRenovacao.deveTentar(renovadoEm: renovacao.renovadoEm, falha: falhaDaRenovacao, situacao: situacao, agora: agora) else { return }
        await executarRenovacao(manual: false)
    }

    /// Roda a reinstalação e guarda o resultado. `manual` é o botão da tela: só ele mostra aviso na janela.
    func executarRenovacao(manual: Bool) async {
        guard let renovador, !renovando else { return }
        renovando = true
        defer { renovando = false }
        registrar("renovacao: iniciada (\(manual ? "pedido na tela" : "agenda"))")
        switch await renovador() {
        case .renovado(let em, let venceEm):
            registrar("renovacao: ok. Instalado em \(Self.iso(em)). O perfil novo vence em \(venceEm.map(Self.iso) ?? "data desconhecida")")
            registrarRenovacao(em: em, avisando: manual)
        case .falhou(let motivo):
            let quando = agora
            falhaDaRenovacao = FalhaDaRenovacao(em: quando, motivo: motivo)
            renovacao.motivo = motivo.texto
            renovacao.tentouEm = quando
            renovacao.gravar(defaults)
            let proxima = motivo.dependeDoIphone ? "quando o iPhone aparecer no cabo ou no Wi-Fi, ou for desbloqueado (olho a cada \(Int(AgendaDeRenovacao.checagem / 60)) min)"
                : "daqui a \(Int(AgendaDeRenovacao.esperaDeFalhaNaoDoIphone / 60)) min"
            registrar("renovacao: falhou. \(motivo.texto). Nova tentativa \(proxima)")
            if manual { avisar("Não consegui renovar: \(motivo.texto). Tento de novo sozinho", falha: true) }
        }
    }

    nonisolated static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}
