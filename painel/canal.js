/* O canal: a única camada da página que fala com o Mac. O resto do painel só chama estas funções.
   Hoje o canal é o HTTPS da mesma origem. Nas fases 5 a 7 o app nativo injeta window.DeckCanal
   (cabo e Bluetooth) com a mesma interface, e a página usa ele no lugar sem mudar mais nada:

     estado()                  -> Estado
     botao(id)                 -> {ok: true}
     spotify(acao, valor?)     -> {ok: true}     acao: tocar, pausar, anterior, proxima, posicao (segundos), repetir e aleatorio (true liga, false desliga)
     spotifyVolume(v, alvo)    -> {ok: true}     v de 0 a 100, alvo: spotify, mac ou aparelho
     aparelhos()               -> [Aparelho]     só com o Spotify conectado (senão 409)
     transferir(id)            -> {ok: true}     passa a música para o aparelho (só conectado)
     curtir(curtir)            -> {ok: true}     true curte, false tira a curtida (só conectado)
     fila()                    -> {atual, proximas}  só conectado
     repetirModo(modo)         -> {ok: true}     faixa (só a música), contexto (a lista) ou nao (só conectado)
     config()                  -> Config sem o codigoAcesso
     gravarConfig(config)      -> Config
     whatsapp()                -> [ConversaWhatsApp]
     agenda(de, dias)          -> [Evento]
     sessoes()                 -> [Sessao]
     abrirSessao(id)           -> {ok, como, app}  traz o terminal da sessão para a frente no Mac (como: "terminal" ou "pasta")
     entrarNaReuniao(link)     -> {ok: true}       abre no Mac o link de reunião do evento (Meet, Zoom ou Teams)
     capaUrl(capaId)           -> endereço da imagem da capa
     apps()                    -> [{nome, valor, bundle, navegador}]  os apps instalados no Mac (404 em Mac antigo)
     acoesDoApp(bundle)        -> {bundle, acoes: [Acao]}  o que o app oferece além de abrir (ler as contas do Mail pode levar uns 8 s)
     appIconeUrl(bundle)       -> endereço do ícone do app

   Erro: sempre um Error com .message em português para mostrar no iPhone, .status com o código HTTP
   (401 = código de acesso inválido) e .rede = true quando o Mac nem respondeu. */

/* tempoLimite: quanto um pedido espera o Mac. O estado do Mac chega em 150 a 400 ms, e até 2 s na primeira leitura depois
   que o Deck abre (o Mac espera as fontes até esse prazo), mais o trajeto do Bluetooth. 3 s derrubava pedido que ia chegar.
   falhasParaOffline e msParaOffline: a tela "Mac desconectado" só fecha quando o Mac sumiu de fato, com essas falhas
   seguidas E esse tempo desde a última resposta boa. Com o Mac pendurado (cada pedido espera o tempo limite inteiro),
   falhasTravado e msTravado fecham mais cedo, senão a tela ficaria uns 16 s com cara de ao vivo. Um tropeço (pedido lento, Mac reiniciando) não pisca a tela. */
const AJUSTES = Object.assign({ tempoLimite: 5000, intervalo: 1000, deslocamento: 180000, falhasParaOffline: 3, msParaOffline: 5000, falhasTravado: 2, msTravado: 10000 }, window.DECK_AJUSTES);

function erroDeCanal(mensagem, status = 0, rede = false) {
  return Object.assign(new Error(mensagem), { status, rede });
}

/* O código de acesso chega no QR (?codigo=) só na primeira abertura: guarda no aparelho e some da URL. */
function lerCodigo() {
  const url = new URL(location.href), vindo = url.searchParams.get('codigo');
  if (vindo) {
    guardar('deck-codigo', vindo);
    url.searchParams.delete('codigo');
    history.replaceState(null, '', url.pathname + url.search + url.hash);
    return vindo;
  }
  return lerGuardado('deck-codigo');
}

function criarCanalHttps() {
  let codigo = lerCodigo();
  async function pedir(metodo, caminho, corpo, limite = AJUSTES.tempoLimite) {
    if (!codigo) throw erroDeCanal('Abra o Deck no Mac e leia o QR de novo.', 401);
    const ctl = new AbortController(), tempo = setTimeout(() => ctl.abort(), limite);
    try {
      let r;
      try {
        r = await fetch(caminho, {
          method: metodo, cache: 'no-store', signal: ctl.signal,
          headers: { 'X-Deck-Codigo': codigo, ...(corpo ? { 'Content-Type': 'application/json' } : {}) },
          body: corpo ? JSON.stringify(corpo) : undefined,
        });
      } catch { throw erroDeCanal('Não deu para falar com o Mac.', 0, true) }
      // rodízio: o Mac troca o código a cada 24 h e avisa em toda resposta que veio com o anterior (qualquer status).
      // A página passa a usar e a guardar o novo, e nunca precisa parear de novo.
      const novo = r.headers.get('X-Deck-Codigo-Novo');
      if (novo && novo !== codigo) { codigo = novo; guardar('deck-codigo', novo) }
      let dados = null;
      try { dados = await r.json() } catch (e) { if (ctl.signal.aborted) throw erroDeCanal('O Mac demorou demais para responder.', 0, true) }
      if (!r.ok) throw erroDeCanal(dados?.erro || 'O Mac não conseguiu fazer isso.', r.status);
      return dados;
    } finally { clearTimeout(tempo) }
  }
  return {
    estado: () => pedir('GET', '/api/estado'),
    botao: id => pedir('POST', '/api/botao/' + encodeURIComponent(id)),
    // repetir e aleatorio levam o valor que a tela já mostra (v=1 liga, v=0 desliga), para o pedido repetido não desfazer
    spotify: (acao, valor) => pedir('POST', '/api/spotify/' + encodeURIComponent(acao) + (acao === 'posicao' ? '?s=' + encodeURIComponent(valor) : (acao === 'repetir' || acao === 'aleatorio') && valor !== undefined ? '?v=' + (valor ? '1' : '0') : '')),
    spotifyVolume: (v, alvo) => pedir('POST', `/api/spotify/volume?v=${encodeURIComponent(v)}&alvo=${encodeURIComponent(alvo)}`),
    aparelhos: () => pedir('GET', '/api/spotify/dispositivos'),
    transferir: id => pedir('POST', '/api/spotify/dispositivo?id=' + encodeURIComponent(id)),
    curtir: curtir => pedir('POST', '/api/spotify/curtir?v=' + (curtir ? '1' : '0')),
    fila: () => pedir('GET', '/api/spotify/fila'),
    repetirModo: modo => pedir('POST', '/api/spotify/repetir?modo=' + encodeURIComponent(modo)),
    config: () => pedir('GET', '/api/config'),
    gravarConfig: config => pedir('PUT', '/api/config', config),
    whatsapp: () => pedir('GET', '/api/whatsapp'),
    agenda: (de, dias) => pedir('GET', `/api/agenda?de=${encodeURIComponent(de)}&dias=${encodeURIComponent(dias)}`),
    sessoes: () => pedir('GET', '/api/sessoes'),
    abrirSessao: id => pedir('POST', '/api/sessoes/' + encodeURIComponent(id) + '/abrir'),
    entrarNaReuniao: link => pedir('POST', '/api/reuniao/entrar', { link }),
    apps: () => pedir('GET', '/api/apps'),
    acoesDoApp: bundle => pedir('GET', `/api/apps/${encodeURIComponent(bundle)}/acoes`, undefined, 15000), // o Mac lê a lista de dentro do app, e o macOS pode pedir permissão no meio
    appIconeUrl: bundle => `/api/apps/${encodeURIComponent(bundle)}/icone?codigo=${encodeURIComponent(codigo || '')}`,
    // <img> não manda cabeçalho: a capa leva o código na URL, e o capaId faz o navegador trocar a imagem só quando ela muda
    capaUrl: capaId => `/api/capa?codigo=${encodeURIComponent(codigo || '')}&v=${encodeURIComponent(capaId || '')}`,
    // Só no HTTPS (o app nativo pareia por cabo e Bluetooth). Troca os 6 dígitos que o Mac mostra pelo código de acesso.
    // A rota não pede código (o iPhone ainda não tem um), por isso não passa pelo pedir().
    async parear(digitos) {
      const ctl = new AbortController(), tempo = setTimeout(() => ctl.abort(), AJUSTES.tempoLimite * 2);
      let r;
      try {
        r = await fetch('/api/parear', { method: 'POST', cache: 'no-store', signal: ctl.signal, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ codigo: String(digitos).replace(/\D/g, '') }) });
      } catch { throw erroDeCanal('Não deu para falar com o Mac.', 0, true) } finally { clearTimeout(tempo) }
      let dados = null;
      try { dados = await r.json() } catch {}
      if (!r.ok || !dados?.codigoAcesso) throw erroDeCanal(dados?.erro || 'O Mac não aceitou o código.', r.status);
      codigo = dados.codigoAcesso; guardar('deck-codigo', codigo);
    },
  };
}

const canal = window.DeckCanal || criarCanalHttps();
