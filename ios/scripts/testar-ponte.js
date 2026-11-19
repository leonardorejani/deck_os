// Testa ios/Web/ponte.js em node, com um Mac de mentira que faz o rodízio do código de acesso.
// Uso: node ios/scripts/testar-ponte.js (sai com erro se algum cenário falhar)
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '../Web/ponte.js'), 'utf8');
const dorme = ms => new Promise(r => setTimeout(r, ms));

function montar(handler, ajustes) {
  const w = { DECK_NATIVO_INICIO: { codigo: 'ANTIGO' }, DECK_AJUSTES: ajustes,
    webkit: { messageHandlers: { deck: { postMessage: async m => JSON.stringify(await handler(m)) } } } };
  new Function('window', src)(w);
  return w;
}

/* Mac de mentira: o primeiro pedido com o código ANTIGO troca o esperado para NOVO e devolve codigoNovo
   depois de `atrasoDoRodizio` ms. Quem chega com código diferente do esperado recebe 401. O "Keychain" do
   Swift (guardado) já muda quando a resposta com o código novo sai. */
function mac(atrasoDoRodizio) {
  const e = { esperado: 'ANTIGO', guardado: 'ANTIGO', log: [], esqueceu: false };
  e.handler = async m => {
    if (m.op === 'codigo') return { codigo: e.guardado };
    if (m.op === 'acao') { e.log.push('esquecer'); e.esqueceu = true; return {}; }
    const cod = m.cabecalhos['X-Deck-Codigo'];
    e.log.push(m.caminho + ' ' + cod);
    if (cod !== e.esperado) { await dorme(60); return { status: 401, corpo: '{"erro":"codigo"}' }; }
    if (cod === 'ANTIGO') {
      e.esperado = 'NOVO'; e.guardado = 'NOVO';
      await dorme(atrasoDoRodizio);
      return { status: 200, corpo: '{}', codigoNovo: 'NOVO' };
    }
    return { status: 200, corpo: '{}' };
  };
  return e;
}

(async () => {
  // 1. Duas chamadas em paralelo durante o rodízio: nenhuma apaga o pareamento.
  let m = mac(50), w = montar(m.handler);
  let r = await Promise.allSettled([w.DeckCanal.estado(), dorme(10).then(() => w.DeckCanal.config())]);
  assert.deepStrictEqual(r.map(x => x.status), ['fulfilled', 'fulfilled'], 'as duas chamadas terminam bem: ' + JSON.stringify(r));
  assert.strictEqual(m.esqueceu, false, 'não esquece o Mac no rodízio');

  // 2. Resposta do rodízio chega depois dos 3 s da página: o código novo vale mesmo assim.
  m = mac(150); w = montar(m.handler, { tempoLimite: 50 });
  await assert.rejects(w.DeckCanal.estado(), /demorou demais/);
  await dorme(200);
  await w.DeckCanal.estado();
  assert.strictEqual(m.esqueceu, false, 'não esquece o Mac depois do limite de tempo');
  assert.strictEqual(m.log[m.log.length - 1], '/api/estado NOVO');

  // 3. Código velho recusado e o Keychain também sem código novo: aí sim esquece.
  m = mac(0); m.esperado = 'OUTRO'; m.guardado = 'ANTIGO'; w = montar(m.handler);
  await assert.rejects(w.DeckCanal.estado(), e => e.status === 401);
  assert.strictEqual(m.esqueceu, true, 'Mac que não reconhece o iPhone apaga o pareamento');
  // 4. O Mac leva 3,5 s (a primeira leitura depois que o Deck abre, mais o trajeto do Bluetooth): o limite padrão (5 s) espera.
  // Com 3 s o pedido era derrubado e a página contava uma queda.
  m = mac(3500); w = montar(m.handler);
  await w.DeckCanal.estado();
  assert.strictEqual(m.esqueceu, false);
  // 5. Spotify: posicao leva s, repetir e aleatorio levam v (1 liga, 0 desliga, sem valor alterna), as outras não levam nada.
  const vistos = [];
  w = montar(async msg => { if (msg.op === 'requisitar') { vistos.push(msg.caminho + ' ' + JSON.stringify(msg.query)); return { status: 200, corpo: '{"ok":true}' } } return {} });
  await w.DeckCanal.spotify('posicao', 42); await w.DeckCanal.spotify('repetir', true); await w.DeckCanal.spotify('aleatorio', false);
  await w.DeckCanal.spotify('aleatorio'); await w.DeckCanal.spotify('proxima');
  assert.deepStrictEqual(vistos, ['/api/spotify/posicao {"s":"42"}', '/api/spotify/repetir {"v":"1"}', '/api/spotify/aleatorio {"v":"0"}', '/api/spotify/aleatorio {}', '/api/spotify/proxima {}'], 'query de cada ação do Spotify: ' + JSON.stringify(vistos));
  // 6. Pular na fila: a uri da lista (ctx) chega ao Mac, senão o pulo instantâneo nunca liga no app. Sem uri não leva ctx.
  vistos.length = 0;
  await w.DeckCanal.pularFila(2, 'u:b', 'spotify:playlist:p'); await w.DeckCanal.pularFila(3, 'u:c'); await w.DeckCanal.pularFila(1);
  assert.deepStrictEqual(vistos, ['/api/spotify/pular {"n":"2","uri":"u:b","ctx":"spotify:playlist:p"}', '/api/spotify/pular {"n":"3","uri":"u:c"}', '/api/spotify/pular {"n":"1"}'], 'query do pular: ' + JSON.stringify(vistos));
  // 7. Paridade com painel/canal.js: cada método pede ao Mac a mesma rota, query, corpo e tempo limite pelos dois canais.
  // O app nativo copia a rota mas não o tempo: o abrirConversa esperava 5 s na ponte e 30 s no canal (16/11/2026).
  const srcCanal = fs.readFileSync(path.join(__dirname, '../../painel/canal.js'), 'utf8');
  const chamadas = {
    estado: [], botao: ['b 1'], spotify: ['posicao', 42], spotifyVolume: [30, 'mac'], aparelhos: [], transferir: ['d/1'], curtir: [true],
    fila: [], recentes: [], pularFila: [2, 'u:b', 'spotify:playlist:p'], repetirModo: ['faixa'], config: [], gravarConfig: [{ a: 1 }],
    whatsapp: [7], whatsappFoto: ['f 1.jpg'], whatsappMidia: ['c@1', 'm 2'], abrirConversa: ['x@1'], agenda: ['2026-11-16', 3],
    sessoes: [], usoDetalhe: ['semana'], abrirSessao: ['s/1'], entrarNaReuniao: ['https://meet.google.com/abc'], controles: [],
    controle: ['volume', 40], meet: [], meetAcao: ['microfone'], agendaDestinos: [true], criarCompromisso: [{ titulo: 't' }], apps: [],
    acoesDoApp: ['com.apple.mail'], abrirGitHub: ['dono/app#12'],
  };
  const semPedido = new Set(['nativo', 'codigo', 'vibrar', 'capaUrl', 'appIconeUrl']);
  const crono = fn => { const atrasos = []; const st = (f, ms) => { atrasos.push(ms); return setTimeout(f, ms) }; return { atrasos, st, clear: clearTimeout, fn } };
  const norma = (metodo, caminho, query, corpo, atrasos) => JSON.stringify({ metodo, caminho, query: Object.entries(query).sort(), corpo: corpo ?? null, tempo: atrasos[0] });
  const tempos = crono();
  const aoCanal = [];
  const fetchFalso = async (url, init) => {
    const u = new URL(url, 'http://deck.local');
    aoCanal.push(norma(init.method, u.pathname, Object.fromEntries(u.searchParams), init.body ? JSON.parse(init.body) : null, tempos.atrasos));
    return { ok: true, headers: { get: () => null }, json: async () => ({}) };
  };
  const https = new Function('window', 'location', 'history', 'lerGuardado', 'guardar', 'fetch', 'setTimeout', 'clearTimeout', 'AbortController', srcCanal + '\nreturn criarCanalHttps();')(
    {}, { href: 'http://deck.local/', pathname: '/' }, { replaceState() {} }, () => 'COD', () => {}, fetchFalso, tempos.st, clearTimeout, AbortController);
  const aoNativo = [];
  const temposN = crono();
  const wn = { DECK_NATIVO_INICIO: { codigo: 'COD' }, webkit: { messageHandlers: { deck: { postMessage: async m => {
    aoNativo.push(norma(m.metodo, m.caminho, m.query, m.corpo ? JSON.parse(m.corpo) : null, temposN.atrasos));
    return JSON.stringify({ status: 200, corpo: '{}' });
  } } } } };
  new Function('window', 'setTimeout', 'clearTimeout', src)(wn, temposN.st, clearTimeout);
  const faltando = Object.keys(wn.DeckCanal).filter(k => typeof wn.DeckCanal[k] === 'function' && !semPedido.has(k) && !chamadas[k]);
  assert.deepStrictEqual(faltando, [], 'método novo na ponte sem linha na tabela de paridade: ' + faltando);
  const sobrando = Object.keys(chamadas).filter(k => typeof wn.DeckCanal[k] !== 'function' || typeof https[k] !== 'function');
  assert.deepStrictEqual(sobrando, [], 'método da tabela que falta na ponte ou no canal HTTPS: ' + sobrando);
  const soNoCanal = Object.keys(https).filter(k => typeof https[k] === 'function' && !semPedido.has(k) && k !== 'parear' && typeof wn.DeckCanal[k] !== 'function');
  assert.deepStrictEqual(soNoCanal, [], 'método do painel/canal.js que a ponte não tem: ' + soNoCanal);
  for (const [nome, args] of Object.entries(chamadas)) {
    tempos.atrasos.length = 0; temposN.atrasos.length = 0;
    await https[nome](...args); await wn.DeckCanal[nome](...args);
    assert.strictEqual(aoNativo[aoNativo.length - 1], aoCanal[aoCanal.length - 1], 'a ponte pede diferente do canal HTTPS em ' + nome);
  }
  console.log('ponte.js: ok');
})().catch(e => { console.error(e); process.exit(1); });
