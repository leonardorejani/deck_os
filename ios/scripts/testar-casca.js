// Prova as telas de pareamento do app (ios/Web/casca.js) sem navegador: um DOM mínimo de mentira e a ponte do Swift
// trocada por uma que a gente controla. O que se confere é o HTML que a tela monta em cada estado e o que o toque
// faz na hora (o progresso aparece antes de o Swift responder, e toque duplo não manda duas vezes).
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const codigo = fs.readFileSync(__dirname + '/../Web/casca.js', 'utf8');
const MACS = [{ id: 'mac-1', nome: 'MacBook de Exemplo', perto: true }, { id: 'mac-2', nome: 'Mac mini de Exemplo', perto: false }];

function montar() {
  const enviados = [];
  const pendentes = [];
  const ouvintes = {};
  const pareio = { firstElementChild: { innerHTML: '' }, addEventListener: (n, f) => { ouvintes[n] = f } };
  const chip = { classList: { add() {}, remove() {} }, set innerHTML(v) {} };
  const tela = { classList: { toggle() {} }, insertAdjacentHTML() {} };
  const document = {
    getElementById: id => (id === 'tela' ? tela : id === 'pareio' ? pareio : id === 'canal-chip' ? chip : null),
    querySelector: () => null,
  };
  const avisos = [];
  const janela = {
    DECK_NATIVO_INICIO: { estado: { etapa: 'procurando', macs: MACS } },
    webkit: { messageHandlers: { deck: { postMessage: msg => new Promise(ok => { enviados.push(msg); pendentes.push(r => ok(JSON.stringify(r))) }) } } },
    avisar: (t) => avisos.push(t),
  };
  janela.window = janela;
  vm.runInNewContext(codigo, { window: janela, document, setTimeout, clearTimeout, console, Promise, JSON });
  const html = () => pareio.firstElementChild.innerHTML;
  const alvo = attrs => ({ target: { closest: sel => { const k = sel.replace(/[\[\]]/g, ''); return k in attrs ? { dataset: attrs, ...attrs } : null } } });
  const tocar = attrs => ouvintes.click(alvo(attrs));
  return { janela, html, tocar, enviados, pendentes, avisos };
}
const uteis = fn => new Promise(r => setImmediate(r)).then(fn);

(async () => {
  // 1. a lista: "Parear" ativo no Mac de perto
  let t = montar();
  await uteis();
  t.pendentes.shift()?.({ estado: { etapa: 'procurando', macs: MACS } }); // resposta do "estado" inicial
  await uteis();
  assert.ok(t.html().includes('data-escolher="mac-1"'), 'o Mac de perto é tocável');
  assert.ok(t.html().includes('>Parear<'), 'o botão diz Parear');

  // 2. tocar em Parear: o progresso aparece ANTES de o Swift responder, e o segundo toque não manda nada
  const antes = t.enviados.length;
  t.tocar({ 'data-escolher': 'mac-1', escolher: 'mac-1' });
  assert.ok(t.html().includes('Procurando o Mac...'), 'o botão vira "Procurando o Mac..." na hora');
  assert.ok(t.html().includes('girando'), 'com o indicador girando');
  assert.ok(t.html().includes('aria-busy="true"'), 'e marcado como ocupado');
  assert.ok(!t.html().includes('data-escolher'), 'nenhuma linha aceita toque enquanto isso');
  t.tocar({ 'data-escolher': 'mac-1', escolher: 'mac-1' });
  assert.strictEqual(t.enviados.length - antes, 1, 'toque duplo manda uma ação só');
  assert.deepStrictEqual({ op: t.enviados.at(-1).op, acao: t.enviados.at(-1).acao, id: t.enviados.at(-1).id }, { op: 'acao', acao: 'escolher', id: 'mac-1' });

  // 3. o Swift empurra o código: sai o progresso, entra a conferência
  t.janela.DeckNativo.estado({ etapa: 'confirmar', macs: [], codigo: '483 291', nomeMac: 'MacBook de Exemplo', via: 'bluetooth', alvoId: 'mac-1' });
  t.pendentes.shift()({ estado: { etapa: 'confirmar', macs: [], codigo: '483 291', nomeMac: 'MacBook de Exemplo', via: 'bluetooth', alvoId: 'mac-1' } });
  await uteis();
  assert.ok(t.html().includes('Os códigos são iguais?') && t.html().includes('483 291'), 'conferindo o código');
  assert.ok(!t.html().includes('Pareando...'));

  // 4. "São iguais": vira "Pareando...", os dois botões travam
  const antes2 = t.enviados.length;
  t.tocar({ 'data-acao': 'confirmar', acao: 'confirmar' });
  assert.ok(t.html().includes('Pareando...'), '"São iguais" vira "Pareando..."');
  assert.strictEqual((t.html().match(/disabled/g) || []).length, 2, 'os dois botões travam');
  t.tocar({ 'data-acao': 'confirmar', acao: 'confirmar' });
  t.tocar({ 'data-acao': 'recusar', acao: 'recusar' });
  assert.strictEqual(t.enviados.length - antes2, 1, 'toque duplo e "Não são iguais" não passam enquanto pareia');

  // 5. sucesso
  t.pendentes.shift()({ estado: { etapa: 'pronto', macs: [], nomeMac: 'MacBook de Exemplo', via: 'bluetooth' } });
  await uteis();
  assert.ok(t.html().includes('Pareado') && t.html().includes('MacBook de Exemplo'), 'sucesso: Pareado com o nome do Mac');
  assert.ok(!t.html().includes('Pareando...'));

  // 6. falha: motivo claro, "Tentar de novo", sem aviso repetido
  t = montar(); await uteis(); t.pendentes.shift()?.({ estado: { etapa: 'procurando', macs: MACS } }); await uteis();
  t.tocar({ 'data-escolher': 'mac-1', escolher: 'mac-1' });
  const falhou = { etapa: 'procurando', macs: MACS, alvoId: 'mac-1', falha: 'O Mac não respondeu a tempo. Confira se o Deck está aberto nele e tente de novo.' };
  t.pendentes.shift()({ estado: falhou, erro: falhou.falha });
  await uteis();
  assert.ok(t.html().includes('Não consegui parear') && t.html().includes('O Mac não respondeu a tempo'), 'o motivo aparece na tela');
  assert.ok(t.html().includes('Tentar de novo'), 'com "Tentar de novo"');
  assert.strictEqual(t.avisos.length, 0, 'o aviso de 4 segundos não repete o mesmo texto');

  // 7. "Tentar de novo" pareia o mesmo Mac; se ele sumiu da lista, procura de novo
  const antes3 = t.enviados.length;
  t.tocar({ 'data-acao': 'tentarDeNovo', acao: 'tentarDeNovo' });
  assert.strictEqual(t.enviados[antes3].acao, 'escolher');
  assert.strictEqual(t.enviados[antes3].id, 'mac-1');
  assert.ok(t.html().includes('Procurando o Mac...'), 'a nova tentativa mostra o progresso na hora');
  t.janela.DeckNativo.estado({ etapa: 'procurando', macs: [MACS[1]], alvoId: 'mac-1', falha: 'x' });
  t.tocar({ 'data-acao': 'tentarDeNovo', acao: 'tentarDeNovo' });
  // (o progresso da tentativa anterior ainda não acabou: o toque espera)
  t.pendentes.splice(0).forEach(f => f({ estado: { etapa: 'procurando', macs: [MACS[1]], alvoId: 'mac-1', falha: 'x' } }));
  await uteis();
  const antes4 = t.enviados.length;
  t.tocar({ 'data-acao': 'tentarDeNovo', acao: 'tentarDeNovo' });
  assert.strictEqual(t.enviados[antes4].acao, 'procurar', 'Mac fora da lista: procura de novo');

  console.log('testar-casca: ok');
})().catch(e => { console.error(e); process.exit(1) });
