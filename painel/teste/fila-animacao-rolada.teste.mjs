// Correções da verificação da frente spotify-animacao (13/11/2026): fila longa rolada, recusa com a fila rolada, alto da fila com mesmo
// título e outro artista, e a duração que não salta de 0:00 enquanto o Mac não confirma a troca.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const longa = n => ({ atual: { faixa: 'Faixa de Exemplo', artista: 'Artista Exemplo' }, contexto: 'Daily Mix 3', proximas: Array.from({ length: n }, (_, i) => ({ faixa: 'Longa ' + (i + 1), artista: 'Banda ' + (i + 1), uri: 'spotify:track:l' + (i + 1) })) });
async function abrir(h, p, n) {
  await p.route(/\/api\/spotify\/fila/, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(longa(n)) }));
  await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(500);
  await p.click('#f-player [data-fila]'); await h.dormir(900);
  await h.espera(p, n => document.querySelectorAll('#pc-lista-corpo [data-pular]').length === n, n, 2000);
}
// as faixas que o olho vê no corpo da lista (as linhas dentro da janela de rolagem)
const visiveis = p => p.evaluate(() => { const c = document.querySelector('#pc-lista-corpo').getBoundingClientRect(); return [...document.querySelectorAll('#pc-lista-corpo [data-pular] b')].filter(b => { const r = b.getBoundingClientRect(); return r.top >= c.top - 1 && r.bottom <= c.bottom + 1 }).map(b => b.textContent) });
const rolar = (p, y) => p.evaluate(y => { const c = document.querySelector('#pc-lista-corpo'); c.scrollTop = y; return c.scrollTop }, y);

export default async function (h) {
  // 1. fila longa rolada: tocar numa faixa leva a lista ao alto, com a nova logo abaixo de "Tocando agora"
  await h.reset(); await h.cenario({ atrasoAcao: 1500, spotify: 'tocando', spotifyExtras: 'login' });
  let p = await h.pagina({ w: 932, h: 430 }); await abrir(h, p, 30);
  const y0 = await rolar(p, 600); await h.dormir(200);
  const antes = await visiveis(p);
  h.ok(y0 > 300 && antes.length >= 3, `fila longa rolada (${y0}px), vistas: ${antes.join(', ')}`);
  await p.evaluate(nome => { [...document.querySelectorAll('#pc-lista-corpo [data-pular]')].find(b => b.querySelector('b').textContent === nome).click() }, antes[1]);
  await h.dormir(700);
  const depois = await p.evaluate(() => document.querySelector('#pc-lista-corpo').scrollTop);
  const vis = await visiveis(p);
  const n = +antes[1].replace('Longa ', '');
  h.ok(depois === 0 && vis[0] === 'Longa ' + (n + 1), `ao tocar numa faixa da fila rolada a lista volta ao alto (scrollTop ${depois}), a próxima fica logo abaixo (${vis[0]})`);
  await p.context().close();

  // 2. o Mac recusa com a fila rolada: a lista volta onde a pessoa estava
  await h.reset(); await h.cenario({ atrasoAcao: 800, spotify: 'tocando', spotifyExtras: 'login', filaRecusa: 'A fila mudou. Abra a fila de novo.' });
  p = await h.pagina({ w: 932, h: 430 }); await abrir(h, p, 20);
  const yR = await rolar(p, 500); await h.dormir(200);
  const vA = await visiveis(p);
  await p.evaluate(nome => { [...document.querySelectorAll('#pc-lista-corpo [data-pular]')].find(b => b.querySelector('b').textContent === nome).click() }, vA[1]);
  await h.espera(p, () => document.querySelector('#pc-lista-topo b')?.textContent === 'Faixa de Exemplo' && document.querySelectorAll('#pc-lista-corpo [data-pular]').length === 20, null, 4000);
  await h.dormir(500);
  const yD = await p.evaluate(() => document.querySelector('#pc-lista-corpo').scrollTop), vD = await visiveis(p);
  h.ok(yD === yR && vD.join() === vA.join(), `recusa: a rolagem volta (${yR} -> ${yD}) e as mesmas faixas aparecem (${vD.join(', ')})`);
  await p.context().close();

  // 3. mesmo título, outro artista: o alto da fila acompanha
  await h.reset(); await h.cenario({ spotify: 'tocando', spotifyExtras: 'login' });
  p = await h.pagina({ w: 932, h: 430 }); await abrir(h, p, 12);
  await h.cenario({ artista: 'Outro Artista Totalmente Diferente' });
  const ok3 = await h.espera(p, () => document.querySelector('#pc-lista-topo .tx small')?.textContent === 'Outro Artista Totalmente Diferente', null, 9000);
  h.ok(ok3, 'o alto da fila mostra o artista novo quando só o artista mudou (mesmo título)');
  await p.context().close();

  // 4. a duração não salta: sem total até o Mac responder, e a barra não busca em duração zero
  await h.reset(); await h.cenario({ atrasoAcao: 1500, spotify: 'tocando', spotifyExtras: 'login' });
  p = await h.pagina({ w: 932, h: 430 }); await abrir(h, p, 12);
  await p.evaluate(() => document.querySelector('#pc-lista-corpo [data-pular="1"]').click()); await h.dormir(300);
  const meio = await p.evaluate(() => ({ total: document.querySelector('#f-player .progresso .total').textContent, larg: document.querySelector('#f-player .progresso .trilho i').style.width }));
  h.ok(meio.total === '' && meio.larg === '0%', `antes do Mac responder não há total "0:00" (total "${meio.total}", barra ${meio.larg})`);
  const gasto = await h.contadores().then(c => c.spotify.length);
  const r = await p.evaluate(() => { const t = document.querySelector('#f-player .progresso .trilho').getBoundingClientRect(); return { x: t.left + t.width / 2, y: t.top + t.height / 2 } });
  await p.mouse.click(r.x, r.y); await h.dormir(150);
  h.ok((await h.contadores().then(c => c.spotify.filter(x => x.startsWith('posicao')).length)) === 0, 'tocar na barra sem duração conhecida não manda buscar posição');
  await h.espera(p, () => document.querySelector('#f-player .progresso .total')?.textContent === '3:41', null, 5000);
  h.ok(await p.evaluate(() => document.querySelector('#f-player .progresso .total').textContent) === '3:41', 'quando o Mac responde o total aparece');
  await p.context().close();
}
