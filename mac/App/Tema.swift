import SwiftUI
import AppKit

// Todos os valores visuais do app do Mac, num arquivo só. Espelha o design system tatile
// (prototipo/tatile/*.css) e o bloco de tokens do topo de prototipo/mac.css, com as trocas que
// o `.mesa` do protótipo faz para tela grande e mouse. Tela nenhuma escreve número solto: tudo
// vem daqui. Mudou um token no CSS, muda aqui junto.

enum Tema {

    // MARK: Cor (tatile/cor.css, claro e escuro)

    enum Cor {
        // Papéis da tatile: claro e escuro trocam só aqui.
        static let fundo = Color(claro: 0xF7F7F7, escuro: 0x1C1C1C)
        static let superficie = Color(claro: 0xFFFFFF, escuro: 0x242424)
        static let superficie2 = Color(claro: 0xEFEFEF, escuro: 0x2E2E2E)
        static let borda = Color(claro: 0xE2E2E2, escuro: 0x383838)
        static let texto = Color(claro: 0x161616, escuro: 0xEDEDED)
        static let texto2 = Color(claro: 0x5E5E5E, escuro: 0xA3A3A3)
        static let texto3 = Color(claro: 0x8A8A8A, escuro: 0x7A7A7A)
        static let destaque = Color(claro: 0x2563EB, escuro: 0x60A5FA)
        static let destaqueTexto = Color(claro: 0xFFFFFF, escuro: 0x0B1220)
        static let destaqueSuave = Color(claro: 0xE8EFFD, escuro: 0x1A2740)
        static let destaqueBloco = Color(claro: 0x2563EB, escuro: 0x1D4ED8)
        static let destaqueBlocoTexto = Color(claro: 0xFFFFFF, escuro: 0xFFFFFF)
        static let perigo = Color(claro: 0xB42318, escuro: 0xF09090)
        static let perigoSuave = Color(claro: 0xFDECEA, escuro: 0x3A1D1B)
        static let sucesso = Color(claro: 0x1F7A4D, escuro: 0x5FD49B)
        static let sucessoSuave = Color(claro: 0xE6F4EC, escuro: 0x16291F)
        /// Botão da estrela do GitHub: amarelo cheio nos dois temas, com texto escuro (contraste alto no claro e no escuro).
        static let estrela = Color(claro: 0xF5B800, escuro: 0xF5C518)
        static let estrelaTexto = Color(hex: 0x1A1400)
        static let aviso = Color(claro: 0xA15C00, escuro: 0xE8B95B)

        // Identidade do Deck (iguais a deck.css): o fundo quase preto é do produto, nos dois temas.
        static let telaFundo = Color(hex: 0x0E0E0E)
        static let molduraBorda = Color(hex: 0x2A2A2A)
        static let led = sucesso

        // Só do Mac (mac.css)
        static let branco = Color.white
        static let semaforo1 = Color(hex: 0xFF5F57)
        static let semaforo2 = Color(hex: 0xFEBC2E)
        static let semaforo3 = Color(hex: 0x28C840)
        static let rolagem = Color.white.opacity(0.22)
        static let veuSis = Color.black.opacity(0.35)
        static let veuModal = Color.black.opacity(0.42)

        /// Anel fino das sombras do tema escuro (tatile/forma.css: rgb(255 255 255 / .08)).
        static let anel = Color(claro: 0x000000, escuro: 0xFFFFFF, opacidadeClaro: 0.06, opacidadeEscuro: 0.08)
        static let anelForte = Color(claro: 0x000000, escuro: 0xFFFFFF, opacidadeClaro: 0.06, opacidadeEscuro: 0.10)
    }

    // MARK: Espaço (tatile/espaco.css na faixa de 1024 px, com o ajuste do .mesa)

    enum Espaco {
        static let margem: CGFloat = 28
        static let pad: CGFloat = 20
        static let secao: CGFloat = 28
        static let linha: CGFloat = 52
        static let icone: CGFloat = 12
        static let grade: CGFloat = 12
        static let item: CGFloat = 8
        static let fino: CGFloat = 2
        /// Fio de 1 px (borda de linha, anel).
        static let fio: CGFloat = 1
        static let micro: CGFloat = 4
        static let mini: CGFloat = 6
        static let alvo: CGFloat = 44
        static let alvoSm: CGFloat = 32
    }

    // MARK: Medidas do Mac (mac.css, bloco :root)

    enum Medida {
        static let janelaLarg: CGFloat = 1040
        static let janelaAlt: CGFloat = 700
        static let lateral: CGFloat = 220
        static let popoverLarg: CGFloat = 320
        static let codigoTam: CGFloat = 48
        static let iniLarg: CGFloat = 880
        static let iniAlt: CGFloat = 660
        static let appBusca: CGFloat = 52
        static let appBuscaCol: CGFloat = 100
        static let modalLarg: CGFloat = 540
        static let teclaMac: CGFloat = 100
        static let icSec: CGFloat = 26
        static let qr: CGFloat = 152
        static let icConta: CGFloat = 28
        static let teclaIcone: CGFloat = 44
        static let selo: CGFloat = 22
        static let menusAlt: CGFloat = 28
        static let logo: CGFloat = 36
        static let logoGrande: CGFloat = 96
        static let navAlt: CGFloat = 40
        static let seloNavAlt: CGFloat = 20
        static let semaforo: CGFloat = 12
        static let ponto: CGFloat = 8
        /// Peças dos Ajustes (mac.css): chave de ligar, ícone dentro do botão e do item da barra, campo do nome.
        static let chaveLarg: CGFloat = 38
        static let chaveAlt: CGFloat = 22
        static let iconeBotao: CGFloat = 15
        static let iconeNav: CGFloat = 15
        /// Largura do campo "Nome deste Mac" (o `input` do protótipo, no tamanho padrão do navegador).
        static let campoNome: CGFloat = 170
        /// Largura do campo da chave do app do Spotify (32 letras e números).
        static let campoChave: CGFloat = 280
        /// Margem do quadro branco do QR (o `.qr` do protótipo tem padding de `item`, o desenho já traz a dele).
        static let qrMargem: CGFloat = 0
    }

    // MARK: Forma (tatile/forma.css)

    enum Raio {
        static let sm: CGFloat = 8
        static let normal: CGFloat = 12
        static let card: CGFloat = 20
        static let pilula: CGFloat = 9999
        static let fino: CGFloat = 2
        static let icP: CGFloat = 8
        static let icone: CGFloat = 10
    }

    // MARK: Texto (tatile/tipo.css na faixa de 1024 px)

    enum Texto {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 13
        static let base: CGFloat = 15
        static let md: CGFloat = 17
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let xl2: CGFloat = 36
        static let altura: CGFloat = 1.5
        static let alturaTitulo: CGFloat = 1.2
        /// `small` do navegador: um degrau abaixo do texto ao redor.
        static let menorDe: CGFloat = 1.2
        /// `letter-spacing: .14em` do código de pareamento.
        static let trackingCodigo: CGFloat = 0.14
        /// -0.02em dos títulos, em pontos para o tamanho dado.
        static func trackingTitulo(_ tamanho: CGFloat) -> CGFloat { -0.02 * tamanho }
    }

    // MARK: Estados dos controles

    enum Estado {
        /// Botão desligado (`:disabled`).
        static let opacidadeDesligado = 0.4
        /// Botão apertado (`:active`).
        static let escalaAperto: CGFloat = 0.97
    }

    // MARK: Aviso (mac.css, .aviso)

    enum Aviso {
        /// Quanto o aviso fica na tela: o comum (mac.js, avisar) e o de ação que falhou (SPEC, seção 6).
        static let segundos = 2.6
        static let segundosFalha = 4.0
        /// Quanto o cabeçalho diz "Salvo" depois de gravar (mac.js, pintarSinc).
        static let segundosSalvo = 1.8
        /// Largura máxima do texto do aviso.
        static let larguraMax: CGFloat = 520
    }

    // MARK: Sombra (anel + difusa)

    enum Sombra {
        /// Sombra 3: janela e popover. A difusa do CSS é `0 12px 32px -8px` (sem espalhamento no SwiftUI).
        static let difusaRaio: CGFloat = 16
        static let difusaY: CGFloat = 12
        static let difusaCor = Color.black.opacity(0.6)
        /// Brilho da tecla acesa: `0 0 10px -2px` na cor do LED.
        static let brilhoRaio: CGFloat = 5
    }

    // MARK: Movimento (tatile/movimento.css)

    enum Mov {
        static let rapido = 0.18
        static let padrao = 0.32
        static let lento = 0.48
        static let saiRapido = 0.13
        static let saiPadrao = 0.22
        static let saiLento = 0.34
        static let icone = 0.20
        static let contar = 0.60
        static let cascata = 0.08
        /// Quanto tempo o "Salvo" fica verde depois de cada edição (mac.js, pintarSinc).
        static let salvo = 1.8

        static var move: Animation { .timingCurve(0.65, 0, 0.35, 1, duration: rapido) }
        static var entra: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: padrao) }
        static var sai: Animation { .timingCurve(0.32, 0, 0.67, 0, duration: saiPadrao) }
        static var salto: Animation { .timingCurve(0.34, 1.56, 0.64, 1, duration: padrao) }
    }
}

// MARK: - Peças pequenas das telas de teclas (mac.css)

extension Tema {
    /// Lado dos desenhos pequenos dentro de botões, listas e cartões.
    enum Glifo {
        static let lapis: CGFloat = 12
        static let mais: CGFloat = 14
        static let atalho: CGFloat = 15
        static let tipo: CGFloat = 16
        static let busca: CGFloat = 16
        static let opcao: CGFloat = 18
    }

    /// Espessura do contorno: fino (campos), médio (abas, listas) e forte (o que está escolhido).
    enum Traco {
        static let fino: CGFloat = 1
        static let medio: CGFloat = 1.5
        static let forte: CGFloat = 2
        /// `border: 1px dashed`: o tracejado do gravador de combinação.
        static let tracejado: [CGFloat] = [3]
    }

    enum Opacidade {
        static let desligado = 0.4
        static let arrastando = 0.35
        static let brilho = 0.5
        /// Faixa escura embaixo da tecla de teclado (`<kbd>`).
        static let sombraDaTecla = 0.4
    }

    enum Escala {
        /// `:active { transform: scale(.97) }`
        static let apertado: CGFloat = 0.97
    }

}

extension Tema.Medida {
    /// O LED embaixo da tecla: apagado e aceso.
    static let ledLarg: CGFloat = 18
    static let ledAlt: CGFloat = 3
    static let ledAcesoLarg: CGFloat = 36
    static let ledAcesoAlt: CGFloat = 4
    /// O que o navegador soma por fora do texto de um campo: a borda de 1 px, e 2 px de padding padrão do `<input>`.
    static let bordaDoCampo: CGFloat = 1
    static let recuoDoInput: CGFloat = 2
    /// Margem que o campo de texto do AppKit já traz por dentro (o que o CSS põe de padding).
    static let editorMargem: CGFloat = 5
}

// MARK: - Cor com claro e escuro

extension Color {
    init(hex: UInt32, opacidade: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacidade)
    }

    /// Cor que troca sozinha com a aparência (claro ou escuro).
    init(claro: UInt32, escuro: UInt32, opacidadeClaro: Double = 1, opacidadeEscuro: Double = 1) {
        func ns(_ hex: UInt32, _ o: Double) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: o)
        }
        self.init(nsColor: NSColor(name: nil) { aparencia in
            aparencia.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(escuro, opacidadeEscuro) : ns(claro, opacidadeClaro)
        })
    }
}

// MARK: - Medidas do Uso das IAs e da janela Adicionar conta (mac.css, blocos "contas de IA" e "adicionar conta")

extension Tema {
    enum Uso {
        static let colunas = 3
        static let novaAltMin: CGFloat = 120
        static let novaAnel: CGFloat = 1.5
        static let novaIcone: CGFloat = 22
        static let chaveLarg: CGFloat = 38
        static let chaveAlt: CGFloat = 22
        static let trilhoAlt: CGFloat = 6
        static let opacidadeOculta = 0.55
        static let opacidadeDesligado = 0.4
        static let fecharIcone: CGFloat = 16
        static let focoLargura: CGFloat = 2
        static let focoRecuo: CGFloat = 1
        static let focoSimples: CGFloat = 1
        static let servAnel: CGFloat = 1.5
        static let alturaTextoPequeno: CGFloat = 1.4
        static let mono: CGFloat = Tema.Texto.sm
        static let avisoLargMax: CGFloat = 420
        static let botaoIcone: CGFloat = 15
        /// Altura natural de uma linha do texto do sistema, em múltiplos do tamanho (para chegar à altura de linha do protótipo).
        static let alturaNatural: CGFloat = 1.19
        /// `small` sem tamanho próprio no CSS: 0.83 do texto em volta (13), como o navegador desenha.
        static let pequeno: CGFloat = Tema.Texto.sm * 0.83
        static let girando: CGFloat = 14
        /// Altura de uma linha de ajuda de uma linha só no Chrome (16,1 px para 12 px de letra).
        static let alturaAjuda: CGFloat = 1.34
        /// Botão apertado encolhe um pouco (feedback de toque).
        static let botaoApertado: CGFloat = 0.97
        /// Volta do círculo "Esperando o login...": duração, ângulo final, arco visível e ponto de partida.
        static let girarDuracao = 0.9
        static let girarVolta = 360.0
        static let girarArco: CGFloat = 0.25
        static let girarInicio = -90.0
        /// Filete de 1 px do protótipo (borda da caixa, separador de linhas, anel do botão).
        static let filete: CGFloat = 1
        /// O "+" do botão de fechar vira "x" girando 45 graus.
        static let fecharGiro = 45.0
    }
}
