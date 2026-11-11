import Foundation

/// Lê o selo do Dock (número de não lidas) da saída de `lsappinfo info -only StatusLabel <app>`.
/// Ex.: "StatusLabel"={ "label"="3" }. Sem selo, o lsappinfo não imprime nada ou imprime label vazio.
enum Selo {
    static func ler(_ saida: String) -> String? {
        guard let r = saida.range(of: #""label"="([^"]*)""#, options: .regularExpression) else { return nil }
        let trecho = saida[r]
        let valor = trecho.dropFirst("\"label\"=\"".count).dropLast()
        return valor.isEmpty ? nil : String(valor)
    }
}

extension Selo {
    /// Total de não lidas pelo selo do Dock, para quando o banco do WhatsApp não abre. O Dock não
    /// separa mensagens de conversas, então quem usa isso trata o número só como total.
    static func total(executor: any Executor, app: String) -> Int? {
        let r = executor.rodar("lsappinfo info -only StatusLabel \(Shell.aspas(app))")
        guard r.status == 0, let selo = ler(r.saida) else { return nil }
        return Int(selo)
    }
}
