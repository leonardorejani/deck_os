import Foundation

/// O que toda fonte devolve: o valor, ou o valor vazio mais um Aviso. Nenhuma fonte lança erro para
/// cima, para uma falha nunca derrubar o estado inteiro (SPEC seção 6).
struct Leitura<Valor: Sendable>: Sendable {
    var valor: Valor
    var aviso: Aviso?
}

enum Datas {
    /// ISO 8601 com o fuso dado. O padrão é o do Mac, para "meia-noite do dia" de um evento de dia
    /// todo continuar sendo meia-noite no relógio de quem olha. Os testes passam o fuso explícito.
    static func iso(_ data: Date, fuso: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = fuso
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: data)
    }

    /// Lê ISO 8601 com ou sem fração de segundo (os jobs do Claude gravam "...18:23:09.142Z").
    static func ler(_ texto: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: texto) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: texto)
    }
}

enum Cor {
    /// "#rrggbb" a partir de componentes de 0 a 255 (valores fora da faixa são presos nela).
    static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
        func p(_ v: Int) -> String {
            let n = String(max(0, min(255, v)), radix: 16)
            return n.count == 1 ? "0" + n : n
        }
        return "#" + p(r) + p(g) + p(b)
    }

    /// "#rrggbb" a partir de componentes de 0 a 1 (o formato do CGColor e do NSColor).
    static func hex(r: Double, g: Double, b: Double) -> String {
        hex(Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

enum Shell {
    /// Põe aspas simples em volta de um texto para ir inteiro como um argumento do shell.
    static func aspas(_ texto: String) -> String {
        "'" + texto.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension Shell {
    /// Vigia em perl: roda o zsh num grupo de processos próprio, com a saída num arquivo temporário.
    /// Passou do limite, derruba o grupo inteiro (filhos junto) e sai com o status 142. Como a saída
    /// não passa por pipe, filho largado em segundo plano não segura a tecla. O status do ExecutorShell
    /// para morte por sinal é o número do sinal, então o vigia é quem traduz o estouro de tempo.
    private static let vigia = """
        use File::Temp qw(tempfile); my $t = shift; my ($fh, $n) = tempfile("deck-XXXXXX", TMPDIR => 1);
        my $p = fork(); if (!$p) { setpgrp(0, 0); open(STDIN, "<", "/dev/null");
        open(STDOUT, ">&", $fh); open(STDERR, ">&", $fh); exec(@ARGV) or exit 127; }
        setpgrp($p, $p); my $estourou = 0; $SIG{ALRM} = sub { $estourou = 1; kill(9, -$p); };
        alarm($t); 1 while (waitpid($p, 0) == -1 && $!{EINTR}); alarm(0);
        open(my $r, "<", $n); print while <$r>; unlink($n);
        exit(142) if $estourou; exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
        """

    /// A linha de zsh dentro do vigia: passou de `segundos`, o grupo de processos inteiro cai e o status é 142.
    static func limitado(_ linha: String, segundos: Int) -> String {
        "perl -e \(aspas(vigia)) \(segundos) /bin/zsh -c \(aspas(linha))"
    }

    /// Igual ao `limitado`, mas no shell de login do usuário, lendo o perfil como o Terminal faz
    /// (aliases, funções e PATH do .zshrc/.zprofile). A linha segue como argumento do `-c`, nunca
    /// colada dentro de outra string de shell. O vigia deixa o stdin em /dev/null, então o shell
    /// interativo não espera tty.
    static func limitadoNoPerfil(_ linha: String, segundos: Int, shell: String) -> String {
        "perl -e \(aspas(vigia)) \(segundos) \(aspas(shell)) \(opcoesDePerfil(shell)) -c \(aspas(linha))"
    }

    /// zsh, bash e fish: `-l -i` (login e interativo, que é onde moram os aliases). Outro shell (sh, dash): só `-l`.
    static func opcoesDePerfil(_ shell: String) -> String {
        switch (shell as NSString).lastPathComponent {
        case "zsh", "bash", "fish": return "-l -i"
        default: return "-l"
        }
    }

    /// Shell de login do usuário pelo cadastro do sistema (getpwuid), não pela variável SHELL, que um
    /// processo pai pode ter trocado. Cai em /bin/zsh se não vier ou não for executável.
    static func doUsuario() -> String {
        if let pw = getpwuid(getuid()), let c = pw.pointee.pw_shell {
            let caminho = String(cString: c)
            if caminho.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: caminho) { return caminho }
        }
        return "/bin/zsh"
    }
}

enum Numero {
    /// Percentual de 0 a 100 a partir de um número de arquivo de outro app. Valor absurdo (ou NaN)
    /// é preso na faixa em vez de estourar a conversão para Int.
    static func percentual(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int(max(0, min(100, v)).rounded())
    }

    /// Epoch em segundos dentro do que um relógio de verdade aceita (até o ano 2100), senão nil.
    static func epoch(_ v: Double) -> Date? {
        guard v.isFinite, v >= 0, v <= 4_102_444_800 else { return nil }
        return Date(timeIntervalSince1970: v)
    }
}
