import Foundation

// GitHub no iPhone: os PRs que esperam a revisão da pessoa e os PRs dela com a CI falhando. A leitura usa o `gh` que já
// está instalado e logado neste Mac (o Deck não guarda token nenhum) e só roda enquanto o iPhone está olhando: o estado
// pede e o cache segura por alguns minutos. Tocar num item abre o PR no navegador do Mac, e só quando a pessoa toca.

struct ItemGitHub: Codable, Equatable, Sendable {
    /// "dono/repo#12". É o que o iPhone devolve para abrir: o endereço fica no Mac.
    var id: String
    var titulo: String
    var repo: String
    var numero: Int
}

/// `estado`: "ok", "sem-gh" (o gh não está instalado), "sem-login" (instalado, mas sem conta) ou "erro" (rede, limite, outra falha).
struct ResumoGitHub: Codable, Equatable, Sendable {
    var estado: String
    /// PRs esperando a revisão da pessoa.
    var revisar: [ItemGitHub] = []
    /// PRs abertos da pessoa com a CI falhando.
    var falhando: [ItemGitHub] = []
    /// Quantos PRs a mais existem além dos que a lista leva (a lista é curta, a contagem é a verdadeira).
    var maisRevisar: Int = 0
    var maisFalhando: Int = 0
    /// Só quando o estado é "erro" ou "sem-login": o que fazer, em português.
    var aviso: String? = nil
    /// Quando foi lido, ISO 8601.
    var lidoEm: String? = nil

    var total: Int { revisar.count + maisRevisar + falhando.count + maisFalhando }
}

protocol ProvedorDeGitHub: Sendable {
    /// Abre o PR no navegador do Mac. `id` é um dos ids da última leitura. Erro em texto, ou nil se abriu.
    func abrir(id: String) -> String?
}

struct FonteGitHub: Sendable {
    let executor: any Executor
    /// Quantos itens cada lista leva para o iPhone (a tela é de olhar, não de trabalhar).
    static let maxPorLista = 5
    /// Quantos PRs cada busca traz só para contar (o selo mostra 99+ acima disso).
    static let maxBusca = 100
    static let segundos = 15
    /// O app do Mac não herda o PATH do terminal: o gh do Homebrew mora em /opt/homebrew/bin (ou /usr/local/bin no Mac Intel).
    static let caminho = "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
    static let semGh = "O gh (a ferramenta do GitHub) não está instalado neste Mac. Instale com brew install gh e entre com gh auth login."
    static let semLogin = "O gh não está logado. No Terminal do Mac, rode gh auth login."

    private let guardado = Guardado()

    init(executor: any Executor) { self.executor = executor }

    /// Os PRs que a última leitura mostrou: só deles o Mac abre o endereço.
    private final class Guardado: @unchecked Sendable {
        private let trava = NSLock()
        private var urls: [String: String] = [:]
        func trocar(_ novos: [String: String]) { trava.lock(); urls = novos; trava.unlock() }
        func url(_ id: String) -> String? { trava.lock(); defer { trava.unlock() }; return urls[id] }
    }

    func ler(agora: Date) -> ResumoGitHub {
        let carimbo = Datas.iso(agora)
        let versao = executor.rodar("\(Self.caminho) gh --version")
        guard versao.status == 0 else { return ResumoGitHub(estado: "sem-gh", aviso: Self.semGh, lidoEm: carimbo) }
        let login = executor.rodar(Shell.limitado("\(Self.caminho) gh auth status", segundos: Self.segundos))
        guard login.status == 0 else { return ResumoGitHub(estado: "sem-login", aviso: Self.semLogin, lidoEm: carimbo) }

        let campos = "--json number,title,url,repository --limit \(Self.maxBusca)"
        let pedir = executor.rodar(Shell.limitado("\(Self.caminho) gh search prs --review-requested=@me --state=open \(campos)", segundos: Self.segundos))
        let falhar = executor.rodar(Shell.limitado("\(Self.caminho) gh search prs --author=@me --state=open \(campos) -- status:failure", segundos: Self.segundos))
        guard pedir.status == 0, falhar.status == 0, let a = Self.itens(pedir.saida), let b = Self.itens(falhar.saida) else {
            return ResumoGitHub(estado: "erro", aviso: "Não consegui ler o GitHub agora. Confira a internet e o gh auth status.", lidoEm: carimbo)
        }
        var urls: [String: String] = [:]
        for i in a.prefix(Self.maxPorLista) + b.prefix(Self.maxPorLista) { urls[i.item.id] = i.url }
        guardado.trocar(urls)
        return ResumoGitHub(estado: "ok", revisar: a.prefix(Self.maxPorLista).map(\.item), falhando: b.prefix(Self.maxPorLista).map(\.item),
                             maisRevisar: max(0, a.count - Self.maxPorLista), maisFalhando: max(0, b.count - Self.maxPorLista), lidoEm: carimbo)
    }

    /// Um PR com o endereço dele (que nunca sai do Mac).
    struct Lido: Equatable, Sendable {
        var item: ItemGitHub
        var url: String
    }

    /// Lê o JSON do `gh search prs`. Nil: saída que não é a lista esperada. Item sem número, título ou endereço do GitHub é descartado.
    static func itens(_ saida: String) -> [Lido]? {
        guard let dados = saida.data(using: .utf8), let lista = (try? JSONSerialization.jsonObject(with: dados)) as? [[String: Any]] else { return nil }
        return lista.compactMap { o in
            guard let n = o["number"] as? Int, let titulo = o["title"] as? String, let url = o["url"] as? String, urlDoGitHub(url) != nil,
                  let r = o["repository"] as? [String: Any], let repo = r["nameWithOwner"] as? String, repoValido(repo) else { return nil }
            let limpo = titulo.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            var t = String(String.UnicodeScalarView(limpo)).trimmingCharacters(in: .whitespaces)
            if t.count > 90 { t = String(t.prefix(87)) + "..." }
            return Lido(item: ItemGitHub(id: "\(repo)#\(n)", titulo: t, repo: repo, numero: n), url: url)
        }
    }

    /// "dono/repo": letras, números, ponto, traço e sublinhado, nada de espaço nem barra a mais.
    static func repoValido(_ s: String) -> Bool {
        let p = s.split(separator: "/", omittingEmptySubsequences: false)
        return p.count == 2 && p.allSatisfy { !$0.isEmpty && $0.count <= 100 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) } }
    }

    /// Só endereço https do github.com, sem usuário nem porta.
    static func urlDoGitHub(_ s: String) -> URL? {
        guard let u = URL(string: s), u.scheme == "https", u.host == "github.com", u.user == nil, u.port == nil else { return nil }
        return u
    }

    func endereco(de id: String) -> String? { guardado.url(id) }
}

/// "Abrir no Mac": o iPhone manda o id, o Mac procura nos PRs que acabou de ler e abre no navegador padrão.
struct AbridorDeGitHub: ProvedorDeGitHub {
    let fonte: FonteGitHub
    let shell: any Executor

    func abrir(id: String) -> String? {
        guard let url = fonte.endereco(de: id), FonteGitHub.urlDoGitHub(url) != nil else { return "Não achei esse PR. Abra a lista de novo." }
        return shell.rodar("open \(ExecutorAcoes.escapar(url))").status == 0 ? nil : "O Mac não conseguiu abrir o PR no navegador."
    }
}
