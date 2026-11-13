/* O canal: a única camada da página que fala com o Mac. O resto do painel só chama estas funções.
   Hoje o canal é o HTTPS da mesma origem. Nas fases 5 a 7 o app nativo injeta window.DeckCanal
   (cabo e Bluetooth) com a mesma interface, e a página usa ele no lugar sem mudar mais nada:

     estado()                  -> Estado
     botao(id)                 -> {ok: true}
     spotify(acao, valor?)     -> {ok: true}     acao: tocar, pausar, anterior, proxima, posicao (segundos), repetir e aleatorio (true liga, false desliga)
     controles()               -> {volume?, mudo?, brilho?, teclado?}  o que o Mac oferece (0 a 100), campo que falta = não oferece
     controle(item, v)         -> {ok: true}     item: volume, mudo (v 0 ou 1), brilho ou teclado
     meet()                    -> {aberta, naChamada?, microfone, camera, aviso?}  a central do Google Meet (404 em Mac antigo). microfone e camera: ligado, desligado, desconhecido ou sem-reuniao
     meetAcao(acao)            -> {ok: true}     acao: entrar (abre o Meet ou traz a aba), microfone, camera ou sair
     spotifyVolume(v, alvo)    -> {ok: true}     v de 0 a 100, alvo: spotify, mac ou aparelho
     aparelhos()               -> [Aparelho]     só com o Spotify conectado (senão 409)
     transferir(id)            -> {ok: true}     passa a música para o aparelho (só conectado)
     curtir(curtir)            -> {ok: true}     true curte, false tira a curtida (só conectado)
     fila()                    -> {atual, proximas}  só conectado
     repetirModo(modo)         -> {ok: true}     faixa (só a música), contexto (a lista) ou nao (só conectado)
     config()                  -> Config sem o codigoAcesso
     gravarConfig(config)      -> Config
     whatsapp()                -> [ConversaWhatsApp]
     whatsappFoto(arquivo)     -> {tipo, dados}    a foto de perfil de uma conversa (dados em base64, 404 sem foto)
     whatsappMidia(chat, id)   -> {tipo, dados}    a foto ou o áudio de uma mensagem, baixado agora (só aparelho conectado, até 8 MB, nunca visualização única)
     abrirConversa(id)         -> {ok, aviso?}     "Responder no Mac": abre a conversa no WhatsApp Web do Mac (404 em Mac antigo)
     agenda(de, dias)          -> [Evento]
     sessoes()                 -> [Sessao]
     abrirSessao(id)           -> {ok, como, app}  traz o terminal da sessão para a frente no Mac (como: "terminal" ou "pasta")
     entrarNaReuniao(link)     -> {ok: true}       abre no Mac o link de reunião do evento (Meet, Zoom ou Teams)
     agendaDestinos(pedir?)    -> {calendarios, listas, permissaoCalendario, permissaoLembretes, padrao}  onde dá para salvar um compromisso (404 em Mac antigo). pedir=true abre no Mac o pedido de acesso aos Lembretes
     criarCompromisso(dados)   -> {ok, padraoSalvo}  cria no Calendário ou nos Lembretes do Mac: {titulo, dia, diaTodo, inicio, fim, destino: {tipo, id}, alertaMin, padrao}
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
    whatsappFoto: arquivo => pedir('GET', '/api/whatsapp/foto/' + encodeURIComponent(arquivo)),
    whatsappMidia: (chat, id) => pedir('GET', `/api/whatsapp/midia?chat=${encodeURIComponent(chat)}&id=${encodeURIComponent(id)}`, undefined, 45000), // o Mac baixa da internet antes de responder
    abrirConversa: id => pedir('POST', '/api/whatsapp/abrir', { id }),
    agenda: (de, dias) => pedir('GET', `/api/agenda?de=${encodeURIComponent(de)}&dias=${encodeURIComponent(dias)}`),
    sessoes: () => pedir('GET', '/api/sessoes'),
    abrirSessao: id => pedir('POST', '/api/sessoes/' + encodeURIComponent(id) + '/abrir'),
    entrarNaReuniao: link => pedir('POST', '/api/reuniao/entrar', { link }),
    controles: () => pedir('GET', '/api/controles'),
    controle: (item, v) => pedir('POST', `/api/controles/${encodeURIComponent(item)}?v=${encodeURIComponent(v)}`),
    meet: () => pedir('GET', '/api/meet'),
    meetAcao: acao => pedir('POST', '/api/meet/' + encodeURIComponent(acao), undefined, 20000), // trazer a aba ou abrir o Meet pode levar um instante
    agendaDestinos: pedirAcesso => pedir('GET', '/api/agenda/destinos' + (pedirAcesso ? '?pedir=1' : '')),
    criarCompromisso: dados => pedir('POST', '/api/agenda/criar', dados, 15000), // o Mac grava pelo EventKit, que pode demorar com a conta na nuvem
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
