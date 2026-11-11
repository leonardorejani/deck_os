import Foundation

/// Serve a página do painel a partir de uma pasta, sem nunca sair dela.
struct ArquivosPagina: Sendable {
    let raiz: URL

    func responder(_ caminho: String) -> RespostaRota {
        guard let arquivo = resolver(caminho), let dados = try? Data(contentsOf: arquivo) else {
            return .erro(404, "Página não encontrada.")
        }
        // Sem cache longo: a página muda quando o app do Mac atualiza e o iPhone tem que pegar a nova.
        return RespostaRota(status: 200, tipo: Http.tipoConteudo(arquivo.path), corpo: dados,
                            extras: ["Cache-Control": "no-cache"])
    }

    /// Caminho do arquivo dentro da raiz, ou nil se não existe ou tentou escapar dela.
    func resolver(_ caminho: String) -> URL? {
        guard !caminho.contains("\0"), !caminho.contains("\\") else { return nil }
        let partes = caminho.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Ponto na frente bloqueia "..", "." e também .git, .env e afins que não são página.
        if partes.contains(where: { $0.hasPrefix(".") }) { return nil }

        let base = raiz.resolvingSymlinksInPath().standardizedFileURL
        var alvo = partes.isEmpty ? base : base.appendingPathComponent(partes.joined(separator: "/"))
        var ehPasta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: alvo.path, isDirectory: &ehPasta) else { return nil }
        if ehPasta.boolValue { alvo = alvo.appendingPathComponent("index.html") }

        // Link simbólico que aponta para fora da pasta também não passa.
        let real = alvo.resolvingSymlinksInPath().standardizedFileURL
        guard real.path.hasPrefix(base.path + "/") else { return nil }
        var ehPasta2: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &ehPasta2), !ehPasta2.boolValue else { return nil }
        // O destino real também não pode ser oculto: link visível apontando para .env passaria pelo filtro de nomes.
        let relativo = real.path.dropFirst(base.path.count + 1).split(separator: "/")
        if relativo.contains(where: { $0.hasPrefix(".") }) { return nil }
        return real
    }
}
