import SwiftUI

// Valores da configuração inicial que só ela usa (mac.css, bloco `.ini`). O resto vem do Tema.swift.
// Mudou aqui, muda no CSS junto.

extension Tema {
    enum Inicial {
        static let borda: CGFloat = 1
        /// Largura útil do corpo: a janela menos a borda e a margem de cada lado.
        static let corpoLarg = Medida.iniLarg - borda * 2 - Espaco.secao * 2

        static let barraAlt: CGFloat = 4
        static let barraBrilho: CGFloat = 3
        static let botaoAlt: CGFloat = 36
        static let botaoPad = Espaco.pad
        static let linhaAcessoAlt: CGFloat = 64
        static let feito: CGFloat = 64
        static let feitoIcone: CGFloat = 30
        static let feitoBrilho: CGFloat = 20
        static let marcaIcone: CGFloat = 13
        static let conectarIcone: CGFloat = 22
        static let esperandoIcone: CGFloat = 16
        static let girando: CGFloat = 14
        static let girandoLinha: CGFloat = 2
        static let liberadoIcone: CGFloat = 14
        static let passoNumero: CGFloat = 22
        static let contornoPontilhado: CGFloat = 1.5
        static let contornoMarcado: CGFloat = 2
        static let brilhoComp: CGFloat = 7
        static let enderecoTexto: CGFloat = 12
        /// Fonte do endereço e do Copiar (mac.css pede `ui-monospace`, que o Chrome do protótipo não resolve).
        static let fonteDeCodigo = "Menlo-Regular"
        static let fonteDeCodigoNegrito = "Menlo-Bold"
        static let codigoSpacing: CGFloat = 0.14

        /// Esmaecimento do botão desligado (.btn:disabled) e do brilho das peças acesas.
        static let desligadoOpacidade = 0.4
        static let brilhoOpacidade = 0.5
        static let girandoReduzido = 0.5
        /// Uma volta do círculo "Esperando" (900 ms) e o trecho do arco (de 225 a 315 graus).
        static let girandoVolta = 0.9
        static let girandoDe = 0.625
        static let girandoAte = 0.875
        /// Sombra do logo grande das boas-vindas.
        static let logoSombraRaio: CGFloat = 15
        static let logoSombraY: CGFloat = 8
        /// "vale por 10 minutos" é a fonte pequena (small) abaixo do código.
        static let legendaCodigo = Texto.sm / 1.2
        static let esperandoAlt = Texto.xs * 1.4
        static let iconeDoTipo: CGFloat = 22
        /// Proporção da imagem de prévia do iPhone deitado (932 x 431).
        static let comporRazao: CGFloat = 932.0 / 431.0
        /// Brilho verde do topo: `radial-gradient(80% 60% at 50% 0%, ...transparent 70%)`.
        static let fundoLarg: CGFloat = 0.8
        static let fundoAlt: CGFloat = 0.6
        static let fundoFim: CGFloat = 0.7
        /// Largura do zero do SF em fração do tamanho, como o navegador do protótipo mede o `ch`.
        /// Folga em pontos ao decidir onde o texto quebra (ver MedirTexto.balanceada).
        static let folgaDeMedida: CGFloat = 2
        static let zeroCh: CGFloat = 0.6286
        /// Tempo de olhar os acessos de novo e de o aviso ficar na tela, em segundos.
        static let vigiaSegundos = 1.0
        static let avisoSegundos = 2.6

        /// Larguras de texto do CSS em `ch`.
        static let paragrafoCh: CGFloat = 56
        static let apresentacaoCh: CGFloat = 46
    }
}
