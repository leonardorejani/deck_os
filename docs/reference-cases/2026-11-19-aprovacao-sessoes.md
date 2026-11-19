# Aprovar pedidos do Claude Code no iPhone e sessões que não esperam (19/11/2026)

Camadas tocadas: C1 SPEC, C3 núcleo (`Aprovacoes.swift`, `GanchoInstalador.swift`, `ServidorDoGancho.swift`, `Sessoes.swift`, rotas),
C4 Mac (botão em Ajustes > Este Mac), C5 painel (`aprovacao.js`, bloco e folha de sessões), C6 ponte do app nativo (`aprovar`).
O protótipo (C2) não mudou: o visual novo segue sendo prototipado à parte.

Decisões:

- O gancho PermissionRequest do Claude Code fala com o Mac por um servidor só no loopback, em porta própria (4792, e 4793 na
  bancada), e não pela porta do painel. Motivo: a chamada fica aberta até 90 s esperando o iPhone, e o servidor do painel
  responde na hora.
- O segredo do gancho mora num arquivo 0600 na pasta de dados da variante e o `curl` o lê com `-H @arquivo`. O
  `settings.json` do dono nunca guarda o segredo.
- Falha aberta: qualquer problema termina em saída vazia e código 0, e o Claude Code pergunta no terminal como sempre.
- "iPhone recente" é ter pedido `/api/estado` autenticado nos últimos 12 s (o painel pede a cada segundo).
- Sessão que não espera resposta chega em `Estado.outrasSessoes`, e `Estado.sessoes` segue só com as que esperam.

Formato do gancho (doc oficial, code.claude.com/docs/en/hooks): entrada com `tool_name`, `tool_input`, `cwd`, `session_id`,
saída `hookSpecificOutput.decision.behavior` = allow ou deny (com `message` no deny). O gancho também roda em sessão sem
como perguntar (segundo plano), e ali, sem decisão do gancho, o Claude nega a ferramenta.

Ideia e molde: PhoneBox (MIT, Ersin KOÇ), `ClaudeHook.cs` e `ApprovalStore.cs`. Código próprio, só a ideia vem de lá.
