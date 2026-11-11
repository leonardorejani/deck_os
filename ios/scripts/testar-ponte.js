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
  console.log('ponte.js: ok');
})().catch(e => { console.error(e); process.exit(1); });
