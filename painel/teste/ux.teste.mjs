// Ajustes de UX de 11/11/2026: resposta otimista em tudo, relógio que ocupa o espaço que sobra, relógio e player em tela cheia.
// Cada teste de resposta otimista deixa o Mac de mentira lento (atrasoAcao, atrasoGravar): a tela tem que mudar no toque,
// e o laço de 1 s não pode desfazer a mudança antes de o Mac confirmar.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aviso = p => p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, visivel: document.querySelector('#aviso').classList.contains('visivel'), erro: document.querySelector('#aviso').classList.contains('erro') }));
const centro = async (p, sel) => { const b = await p.locator(sel).boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 } };
const MAX_TOQUE = 500; // a tela muda em menos que isto, com o Mac levando 1,5 s ou mais

export default async function (h) {
  // quanto tempo a tela leva para mostrar o que o toque pediu (-1 se não mostrou)
  const ate = async (p, fn, arg, max = 3000) => { const t0 = Date.now(); return (await h.espera(p, fn, arg, max)) ? Date.now() - t0 : -1 };
  const pausado = () => !!document.querySelector('.player.pausado') && !!document.querySelector('.player .tocar.play');
  const tocando = () => !document.querySelector('.player.pausado') && !document.querySelector('.player .tocar.play');

  /* ---------- Spotify: tocar e pausar ---------- */
  await h.cenario({ atrasoAcao: 1500 });
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.player [data-midia="tocar"]');
  let ms = await ate(p, pausado, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `pausar: o player já mostra "pausado" ${ms} ms depois do toque, com o Mac levando 1500 ms`);
  await h.dormir(1300); // chega um estado do laço, ainda com o Mac tocando
  h.ok(await p.evaluate(pausado), 'o laço de 1 s não desfaz a pausa antes de o Mac confirmar');
  await h.dormir(1800);
  h.ok(await p.evaluate(pausado) && (await h.contadores()).spotify.join() === 'pausar', 'depois que o Mac confirma, segue pausado e ele recebeu "pausar"');
  await p.click('.player [data-midia="tocar"]');
  ms = await ate(p, tocando, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `tocar: o player volta a "tocando" ${ms} ms depois do toque`);
  await h.dormir(1300);
  h.ok(await p.evaluate(tocando), 'e o laço também não desfaz o tocar');
  await p.context().close();

  /* o Mac recusa: a tela volta e o aviso traz o motivo */
  await h.reset(); await h.cenario({ spotifyRecusa: 'O Spotify não deixou o Deck mexer nele.', atrasoAcao: 600 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player [data-midia="tocar"]');
  ms = await ate(p, pausado, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `Spotify recusado: a tela muda no toque (${ms} ms)`);
  h.ok(await h.espera(p, tocando, null, 3000), 'quando o Mac recusa, o player volta a "tocando"');
  let a = await aviso(p);
  h.ok(a.erro && a.txt === 'O Spotify não deixou o Deck mexer nele.', `e o aviso de erro traz o motivo dele ("${a.txt}")`);
  await p.context().close();

  /* próxima faixa e posição da barra */
  await h.reset(); await h.cenario({ atrasoAcao: 2500 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player [data-midia="proxima"]');
  ms = await ate(p, () => /^0:0\d$/.test(document.querySelector('.player .decorrido').textContent), null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `próxima: a barra já recomeça do zero ${ms} ms depois do toque`);
  await h.dormir(1400);
  h.ok(await p.evaluate(() => /^0:\d\d$/.test(document.querySelector('.player .decorrido').textContent)), 'e o laço não puxa a barra de volta para a faixa de antes enquanto o Mac não confirma');
  await p.context().close();
  await h.reset(); await h.cenario({ atrasoAcao: 2500 });
  p = await h.pagina(); await pronta(h, p);
  const tr = await p.locator('.player .progresso .trilho').boundingBox();
  await p.mouse.move(tr.x + tr.width * .1, tr.y + tr.height / 2); await p.mouse.down();
  await p.mouse.move(tr.x + tr.width * .5, tr.y + tr.height / 2, { steps: 5 }); await p.mouse.up();
  await h.dormir(2000); // passa o 1,5 s da trava antiga e chegam dois estados do laço, e o Mac ainda não aplicou
  const dec = await p.evaluate(() => document.querySelector('.player .decorrido').textContent);
  h.ok(/^1:[45]\d$|^1:5\d$/.test(dec), `posição: a barra segue onde o dedo soltou enquanto o Mac não confirma (${dec})`);
  await p.context().close();

  /* ---------- teclas: acende e apaga no toque ---------- */
  await h.reset(); await h.cenario({ atrasoAcao: 1500 });
  p = await h.pagina(); await pronta(h, p);
  const apagada = () => !document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa') && document.querySelector('.tecla[data-id="acordado"]').getAttribute('aria-pressed') === 'false';
  await p.click('.tecla[data-id="acordado"]');
  ms = await ate(p, apagada, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `tecla com estado: apaga ${ms} ms depois do toque, com o Mac levando 1500 ms`);
  h.ok((await aviso(p)).txt === 'Manter acordado: desligado', 'e o aviso já diz "desligado"');
  await h.dormir(1300);
  h.ok(await p.evaluate(apagada), 'o laço de 1 s não acende a tecla de volta antes de o Mac confirmar');
  await h.dormir(1800);
  h.ok(await p.evaluate(apagada) && (await h.contadores()).botoes.join() === 'acordado', 'depois que o Mac confirma, segue apagada e ele recebeu a tecla');
  await p.click('.tecla[data-id="apagar"]');
  h.ok(await ate(p, () => !!document.querySelector('.tecla[data-id="apagar"].piscando'), null, 600) >= 0 && (await aviso(p)).txt === 'Apagar tela: feito', 'tecla comum: o LED pisca e o aviso aparece no toque, antes de o Mac responder');
  await p.context().close();
  await h.reset(); await h.cenario({ falha: true, atrasoAcao: 600 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="acordado"]');
  ms = await ate(p, () => !document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa'), null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `tecla que o Mac vai recusar: apaga no toque (${ms} ms)`);
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa'), null, 3000), 'quando o Mac recusa, a tecla volta a acesa');
  a = await aviso(p);
  h.ok(a.erro && a.txt.includes('Acessibilidade'), `e o aviso de erro traz o motivo dele ("${a.txt}")`);
  await p.context().close();

  /* ---------- perfis ---------- */
  await h.reset(); await h.cenario({ perfis: 'dois', atrasoGravar: 1500 });
  p = await h.pagina(); await pronta(h, p);
  const emEnsaio = () => !!document.querySelector('.tecla[data-id="e-spotify"]') && !document.querySelector('.tecla[data-id="acordado"]');
  await p.click('.tecla.menu'); await p.click('#lista-perfis [data-perfil="ensaio"]');
  ms = await ate(p, emEnsaio, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `perfil: as teclas do Ensaio aparecem ${ms} ms depois do toque, com o Mac levando 1500 ms para gravar`);
  await h.dormir(1300);
  h.ok(await p.evaluate(emEnsaio), 'o laço de 1 s não devolve o perfil velho antes de o Mac gravar');
  await h.dormir(2200);
  h.ok(await p.evaluate(emEnsaio) && (await h.contadores()).configsGravadas.length === 1, 'depois que o Mac grava, segue no Ensaio');
  await p.context().close();
  await h.reset(); await h.cenario({ perfis: 'dois', atrasoGravar: 600, rejeitar: 'O Mac não aceitou trocar de perfil.' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla.menu'); await p.click('#lista-perfis [data-perfil="ensaio"]');
  ms = await ate(p, emEnsaio, null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `perfil que o Mac vai recusar: troca no toque (${ms} ms)`);
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="acordado"]') && !document.querySelector('.tecla[data-id="e-spotify"]'), null, 3000), 'quando o Mac recusa, volta ao perfil de antes');
  a = await aviso(p);
  h.ok(a.erro && a.txt === 'O Mac não aceitou trocar de perfil.', `e o aviso de erro traz o motivo dele ("${a.txt}")`);
  await p.context().close();

  /* ---------- blocos (modo organizar) ---------- */
  await h.reset(); await h.cenario({ atrasoGravar: 1500 });
  p = await h.pagina(); await pronta(h, p);
  const c0 = await centro(p, '.tecla[data-id="calendario"]');
  await p.mouse.move(c0.x, c0.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await p.waitForSelector('.cartao.uso [data-esconder="uso"]', { state: 'attached' });
  await p.evaluate(() => { // anota se o bloco reaparece depois de sumir (o piscar de 1 quadro que ninguém vê num screenshot)
    window.__sumiu = false; window.__voltou = false;
    const olhar = () => { const tem = !!document.querySelector('.cartao.uso'); if (!tem) window.__sumiu = true; else if (window.__sumiu) window.__voltou = true; requestAnimationFrame(olhar) };
    requestAnimationFrame(olhar);
  });
  const t0 = Date.now();
  await p.$eval('.cartao.uso [data-esconder="uso"]', el => el.click());
  ms = await ate(p, () => !document.querySelector('.cartao.uso'), null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `bloco: o "−" some com o bloco ${ms} ms depois do toque, com o Mac levando 1500 ms para gravar`);
  await h.dormir(3800 - (Date.now() - t0)); // passa a gravação do Mac e mais dois estados do laço
  const bl = await p.evaluate(() => ({ voltou: window.__voltou, sumido: !document.querySelector('.cartao.uso') }));
  h.ok(bl.sumido && !bl.voltou && (await h.contadores()).configsGravadas.length === 1, `o bloco nunca reaparece no caminho (voltou: ${bl.voltou})`);
  await p.context().close();
  await h.reset(); await h.cenario({ atrasoGravar: 600, rejeitar: 'O Mac não aceitou esconder o bloco.' });
  p = await h.pagina(); await pronta(h, p);
  const c1 = await centro(p, '.tecla[data-id="calendario"]');
  await p.mouse.move(c1.x, c1.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await p.waitForSelector('.cartao.uso [data-esconder="uso"]', { state: 'attached' });
  await p.$eval('.cartao.uso [data-esconder="uso"]', el => el.click());
  ms = await ate(p, () => !document.querySelector('.cartao.uso'), null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `bloco que o Mac vai recusar: some no toque (${ms} ms)`);
  h.ok(await h.espera(p, () => !!document.querySelector('.cartao.uso'), null, 3000), 'quando o Mac recusa, o bloco volta');
  a = await aviso(p);
  h.ok(a.erro && a.txt === 'O Mac não aceitou esconder o bloco.', `e o aviso de erro traz o motivo dele ("${a.txt}")`);
  await p.context().close();

  /* ---------- relógio que ocupa o espaço que sobra ---------- */
  // geometria do relógio: as 4 placas, a data e a coluna onde ele mora (em pixels da tela, já sem a escala)
  const medir = p => p.evaluate(() => {
    const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth;
    const r = el => { const b = el.getBoundingClientRect(); return { l: (b.left - t.left) / k, r: (b.right - t.left) / k, t: (b.top - t.top) / k, b: (b.bottom - t.top) / k } };
    const pl = [...document.querySelectorAll('#conteudo .placa')].map(r), data = r(document.querySelector('#conteudo .data-linha')), comp = document.querySelector('.comp-a, .comp-b');
    return { pl, data, grande: comp.classList.contains('relogio-grande'), maior: comp.classList.contains('relogio-maior'), pontos: getComputedStyle(document.querySelector('#conteudo .dois-pontos')).display };
  });
  const empilhado = m => Math.abs(m.pl[0].t - m.pl[1].t) < 1 && Math.abs(m.pl[2].t - m.pl[3].t) < 1 && m.pl[2].t > m.pl[0].b - 1 && m.pl[0].l < m.pl[1].l && m.data.b <= m.pl[0].t + 1 && m.pontos === 'none';
  const linha = m => m.pl.every(x => Math.abs(x.t - m.pl[0].t) < 1) && m.data.t >= m.pl[0].b - 1 && !m.grande;
  const VISTAS = { horizontal: [932, 430], vertical: [430, 932] };
  await h.reset(); await h.cenario({ blocos: { uso: false } });
  p = await h.pagina(); await pronta(h, p); await h.dormir(900);
  let m = await medir(p);
  // A deitado sem o bloco de uso (sem contas ou escondido): a coluna do relógio tem 336 px e vai de 16 até 285
  h.ok(m.grande && empilhado(m), `A deitado sem uso: a data em cima e as horas sobre os minutos (grande ${m.grande}, placas ${m.pl.map(x => Math.round(x.t)).join('/')})`);
  const alturaUsada = m.pl[3].b - m.data.t, colunaAlt = 269, larg = Math.max(...m.pl.map(x => x.r)) - Math.min(...m.pl.map(x => x.l));
  h.ok(alturaUsada >= colunaAlt * .9 && larg >= 336 * .95, `e ocupa a coluna inteira: ${Math.round(alturaUsada)} de ${colunaAlt} px de altura e ${Math.round(larg)} de 336 px de largura`);
  await h.foto(p, 'relogio-a-sem-uso');
  await p.context().close();
  await h.reset();
  p = await h.pagina(); await pronta(h, p); await h.dormir(900);
  m = await medir(p);
  h.ok(linha(m), 'A deitado com o uso: o relógio continua em uma linha só, com a data embaixo (nada mudou)');
  await p.context().close();
  // o mesmo buraco nas outras composições: cada caso que o deck.js trata como "relógio grande"
  const CASOS = [
    ['A deitado sem player e sem sessões', 'a', 'horizontal', { spotify: 'fechado', blocos: { sessoes: false } }, true],
    ['B deitado sem sessões e sem uso', 'b', 'horizontal', { blocos: { sessoes: false, uso: false } }, true],
    ['B deitado só com o relógio', 'b', 'horizontal', { spotify: 'fechado', blocos: { sessoes: false, uso: false } }, true],
    ['B deitado sem player e sem sessões', 'b', 'horizontal', { spotify: 'fechado', blocos: { sessoes: false } }, true],
    ['A em pé sem uso e sem sessões', 'a', 'vertical', { blocos: { sessoes: false, uso: false } }, true],
    ['B em pé sem player e sem sessões', 'b', 'vertical', { spotify: 'fechado', blocos: { sessoes: false } }, true],
    ['A em pé só com o relógio', 'a', 'vertical', { spotify: 'fechado', blocos: { sessoes: false, uso: false } }, true],
    ['A em pé com tudo', 'a', 'vertical', {}, false],
    ['B deitado com tudo', 'b', 'horizontal', {}, false],
  ];
  for (const [nome, comp, pos, patch, esperado] of CASOS) {
    await h.reset(); await h.cenario({ comp, ...patch });
    p = await h.pagina({ w: VISTAS[pos][0], h: VISTAS[pos][1] }); await pronta(h, p); await h.dormir(900);
    m = await medir(p);
    const seguro = pos === 'horizontal' ? { t: 0, b: 409, l: 59, r: 873 } : { t: 59, b: 898, l: 0, r: 430 };
    const dentro = m.pl.every(x => x.t >= seguro.t - 1 && x.b <= seguro.b + 1 && x.l >= seguro.l - 1 && x.r <= seguro.r + 1);
    h.ok(m.grande === esperado && (!esperado || empilhado(m) || (pos === 'vertical' && m.pl.length === 4)) && dentro, `${nome}: ${esperado ? 'relógio grande, data em cima e horas sobre minutos' : 'relógio como sempre'}, dentro da área segura (grande ${m.grande}, topo das placas ${m.pl.map(x => Math.round(x.t)).join('/')})`);
    await h.foto(p, `relogio-${comp}-${pos}-${esperado ? 'grande' : 'normal'}-${nome.replace(/[^a-z]+/gi, '-').toLowerCase()}`);
    await p.context().close();
  }
  // B deitado sem sessões mas com uso e player: as placas só crescem
  await h.reset(); await h.cenario({ comp: 'b', blocos: { sessoes: false } });
  p = await h.pagina(); await pronta(h, p); await h.dormir(900);
  m = await medir(p);
  h.ok(m.maior && !m.grande && m.pl[0].b - m.pl[0].t > 130 && linha({ ...m, grande: false }), `B deitado sem sessões: as placas crescem (${Math.round(m.pl[0].b - m.pl[0].t)} px de altura) e seguem em uma linha`);
  await h.foto(p, 'relogio-b-sem-sessoes-maior');
  await p.context().close();
  // o relógio vira "grande" e volta ao esconder e mostrar o bloco, sem refazer a página
  await h.reset();
  p = await h.pagina(); await pronta(h, p); await h.dormir(500);
  await h.cenario({ blocos: { uso: false } });
  h.ok(await h.espera(p, () => document.querySelector('.comp-a').classList.contains('relogio-grande'), null, 4000), 'escondendo o uso pelo Mac, o relógio passa a ocupar a coluna');
  await h.cenario({ blocos: { uso: true } });
  h.ok(await h.espera(p, () => !document.querySelector('.comp-a').classList.contains('relogio-grande') && !!document.querySelector('.cartao.uso'), null, 4000), 'e quando o uso volta, o relógio volta ao tamanho de antes');
  await h.cenario({ spotify: 'fechado', blocos: { sessoes: false } });
  h.ok(await h.espera(p, () => document.querySelector('.comp-a').classList.contains('relogio-grande'), null, 4000), 'sem player e sem sessões (Spotify fechou), também ocupa a coluna');
  await p.context().close();

  /* ---------- relógio em tela cheia ---------- */
  for (const [pos, [w, alt]] of Object.entries(VISTAS)) {
    await h.reset();
    p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(700);
    const cheio = () => p.evaluate(() => {
      const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth, f = document.querySelector('#f-relogio');
      const r = el => { const b = el.getBoundingClientRect(); return { l: (b.left - t.left) / k, r: (b.right - t.left) / k, t: (b.top - t.top) / k, b: (b.bottom - t.top) / k } };
      const hora = [...f.querySelectorAll('.placa')].map(x => x.dataset.d).join(''), agora = new Date(), hh = String(agora.getHours()).padStart(2, '0') + String(agora.getMinutes()).padStart(2, '0');
      return { aberta: f.classList.contains('aberta'), visivel: getComputedStyle(f).visibility, opac: getComputedStyle(f).opacity, fundo: getComputedStyle(f).backgroundColor, pl: [...f.querySelectorAll('.placa')].map(r), data: r(f.querySelector('.data')), txt: f.querySelector('.data').textContent, hora, hh };
    });
    let c = await cheio();
    h.ok(!c.aberta && c.visivel === 'hidden', `${pos}: o relógio de tela cheia começa fechado e escondido`);
    await p.click('#conteudo .relogio');
    h.ok(await h.espera(p, () => document.querySelector('#f-relogio').classList.contains('aberta') && getComputedStyle(document.querySelector('#f-relogio')).opacity === '1', null, 2000), `${pos}: tocar no relógio abre a tela cheia`);
    c = await cheio();
    const alturaPlaca = c.pl[0].b - c.pl[0].t, seguro = pos === 'horizontal' ? { t: 0, b: 409, l: 59, r: 873 } : { t: 59, b: 898, l: 0, r: 430 };
    const dentro = c.pl.every(x => x.t >= seguro.t - 1 && x.b <= seguro.b + 1 && x.l >= seguro.l - 1 && x.r <= seguro.r + 1) && c.data.b <= seguro.b + 1 && c.data.t >= seguro.t - 1;
    h.ok(c.fundo === 'rgb(0, 0, 0)' && c.pl.length === 4 && alturaPlaca >= 240 && dentro, `${pos}: fundo preto, quatro placas grandes (${Math.round(alturaPlaca)} px de altura), tudo dentro da área segura`);
    if (pos === 'horizontal') h.ok(c.pl.every(x => Math.abs(x.t - c.pl[0].t) < 1) && c.data.t >= c.pl[0].b - 1, 'deitado: as quatro placas em uma linha e a data embaixo');
    else h.ok(Math.abs(c.pl[0].t - c.pl[1].t) < 1 && c.pl[2].t > c.pl[0].b - 1 && c.data.b <= c.pl[0].t + 1, 'em pé: a data em cima e as horas sobre os minutos');
    h.ok(/^\w+-feira|^sábado|^domingo/.test(c.txt) && /^\d{4}$/.test(c.hora) && Math.abs(+c.hora - +c.hh) <= 1, `${pos}: a data por extenso (${c.txt}) e as placas com a hora (${c.hora})`);
    await h.dormir(600); await h.foto(p, `relogio-cheio-${pos}`);
    await p.click('#f-relogio');
    h.ok(await h.espera(p, () => !document.querySelector('#f-relogio').classList.contains('aberta') && getComputedStyle(document.querySelector('#f-relogio')).visibility === 'hidden', null, 2000), `${pos}: tocar em qualquer lugar fecha`);
    // a placa vira durante o toque: o clique ainda fecha
    await p.click('#conteudo .relogio'); await h.espera(p, () => document.querySelector('#f-relogio').classList.contains('aberta'));
    await p.keyboard.press('Escape');
    h.ok(await h.espera(p, () => !document.querySelector('#f-relogio').classList.contains('aberta'), null, 2000), `${pos}: Escape também fecha`);
    await p.context().close();
  }
  // no modo organizar o relógio não abre; o laço (render a cada mudança) não fecha a tela cheia aberta
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const cOrg = await centro(p, '.tecla[data-id="apagar"]');
  await p.mouse.move(cOrg.x, cOrg.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await p.mouse.click(...await p.locator('#conteudo .relogio').boundingBox().then(b => [b.x + b.width / 2, b.y + b.height / 2]));
  await h.dormir(400);
  h.ok(await p.evaluate(() => !document.querySelector('#f-relogio').classList.contains('aberta')), 'no modo organizar, tocar no relógio não abre a tela cheia');
  await p.context().close();
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('#conteudo .data-linha'); await h.espera(p, () => document.querySelector('#f-relogio').classList.contains('aberta'));
  await h.cenario({ blocos: { uso: false }, spotify: 'pausado' }); await h.dormir(2500); // o painel de trás é refeito
  h.ok(await p.evaluate(() => document.querySelector('#f-relogio').classList.contains('aberta')), 'tocar na data também abre, e a tela cheia continua aberta quando o painel de trás muda');
  await p.context().close();

  /* ---------- player: repetir e aleatório no pequeno e a tela cheia ---------- */
  await h.reset(); await h.cenario({ atrasoAcao: 1500 });
  p = await h.pagina(); await pronta(h, p);
  const modos = () => p.evaluate(() => [...document.querySelectorAll('.player .modo')].map(b => b.dataset.midia + '=' + b.getAttribute('aria-pressed')).join());
  h.ok(await modos() === 'aleatorio=false,repetir=false', `o player pequeno tem aleatório e repetir, desligados (${await modos()})`);
  await p.click('.player [data-midia="repetir"]');
  ms = await ate(p, () => document.querySelector('.player [data-midia="repetir"]').getAttribute('aria-pressed') === 'true', null, 1200);
  h.ok(ms >= 0 && ms < MAX_TOQUE, `repetir: liga ${ms} ms depois do toque, com o Mac levando 1500 ms`);
  await h.dormir(1300);
  h.ok(await modos() === 'aleatorio=false,repetir=true', 'o laço não desliga o repetir antes de o Mac confirmar');
  await p.click('.player [data-midia="aleatorio"]'); await h.dormir(2500);
  h.ok(await modos() === 'aleatorio=true,repetir=true' && (await h.contadores()).spotify.join() === 'repetir:1,aleatorio:1', `o Mac recebeu repetir:1 e aleatorio:1 (${(await h.contadores()).spotify})`);
  await p.click('.player [data-midia="repetir"]'); await h.dormir(2300);
  h.ok(await modos() === 'aleatorio=true,repetir=false' && (await h.contadores()).spotify.pop() === 'repetir:0', 'tocar de novo desliga, e o Mac recebe repetir:0');
  await h.cenario({ repetir: true }); // ligado no próprio Spotify do Mac
  h.ok(await h.espera(p, () => document.querySelector('.player [data-midia="repetir"]').getAttribute('aria-pressed') === 'true', null, 3000), 'ligar o repetir no Mac também aparece no player');
  await h.foto(p, 'player-modos');
  await p.context().close();

  for (const [pos, [w, alt]] of Object.entries(VISTAS)) {
    await h.reset(); await h.cenario({ atrasoAcao: 1200 });
    p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(500);
    await p.click('.player .capa');
    h.ok(await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000), `${pos}: tocar na capa abre o player em tela cheia`);
    await h.dormir(700);
    const g = await p.evaluate(() => {
      const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth, f = document.querySelector('#f-player');
      const r = el => { const b = el.getBoundingClientRect(); return { l: (b.left - t.left) / k, r: (b.right - t.left) / k, t: (b.top - t.top) / k, b: (b.bottom - t.top) / k } };
      const capa = f.querySelector('.capa-grande');
      return { capa: r(capa), carregou: capa.naturalWidth > 0, faixa: f.querySelector('.faixa').textContent, artista: f.querySelector('.artista').textContent, album: f.querySelector('.album')?.textContent, total: f.querySelector('.total').textContent, botoes: [...f.querySelectorAll('.midia button')].map(b => b.dataset.midia), alvos: [...f.querySelectorAll('.midia button')].every(b => b.getBoundingClientRect().height / k >= 43), todos: [...f.querySelectorAll('.midia button, .progresso, .pc-titulos, .capa-grande')].map(r), fundo: getComputedStyle(f).backgroundImage.includes('radial-gradient'), fila: !!f.querySelector('.fila, .proxima-faixa') };
    });
    const seguro = pos === 'horizontal' ? { t: 0, b: 409, l: 59, r: 873 } : { t: 59, b: 898, l: 0, r: 430 };
    h.ok(g.carregou && g.capa.r - g.capa.l >= 300 && g.todos.every(x => x.t >= seguro.t - 1 && x.b <= seguro.b + 1 && x.l >= seguro.l - 1 && x.r <= seguro.r + 1), `${pos}: capa grande (${Math.round(g.capa.r - g.capa.l)} px) carregada e tudo dentro da área segura`);
    h.ok(g.faixa === 'Faixa de Exemplo' && g.artista === 'Artista Exemplo' && g.album === 'Artista Exemplo (Deluxe)' && g.total === '3:41', `${pos}: faixa, artista, álbum e duração (${g.faixa}, ${g.artista}, ${g.album}, ${g.total})`);
    h.ok(g.botoes.join() === 'aleatorio,anterior,tocar,proxima,repetir' && g.alvos && g.fundo && !g.fila, `${pos}: aleatório, anterior, tocar, próxima e repetir, com a cor da capa no fundo, sem inventar fila`);
    await h.foto(p, `player-cheio-${pos}`);
    // botões da tela cheia: resposta no toque, o pequeno acompanha
    await p.click('#f-player [data-midia="tocar"]');
    ms = await ate(p, () => document.querySelector('#f-player .pc').classList.contains('pausado') && !!document.querySelector('#f-player .tocar.play'), null, 1000);
    h.ok(ms >= 0 && ms < MAX_TOQUE, `${pos}: tocar na tela cheia pausa ${ms} ms depois do toque`);
    await p.click('#f-player [data-midia="repetir"]'); await p.click('#f-player [data-midia="aleatorio"]');
    h.ok(await ate(p, () => ['repetir', 'aleatorio'].every(k => document.querySelector(`#f-player [data-midia="${k}"]`).getAttribute('aria-pressed') === 'true' && document.querySelector(`.player [data-midia="${k}"]`).getAttribute('aria-pressed') === 'true'), null, 1000) >= 0, `${pos}: repetir e aleatório ligam na hora, nos dois players`);
    await h.dormir(4200); // os comandos do Spotify seguem em fila, um de cada vez: 3 x 1,2 s
    h.ok((await h.contadores()).spotify.join() === 'pausar,repetir:1,aleatorio:1', `${pos}: o Mac recebeu pausar, repetir:1 e aleatorio:1 (${(await h.contadores()).spotify})`);
    // a barra da tela cheia também arrasta
    const tr2 = await p.locator('#f-player .progresso .trilho').boundingBox();
    await p.mouse.move(tr2.x + tr2.width * .1, tr2.y + tr2.height / 2); await p.mouse.down();
    await p.mouse.move(tr2.x + tr2.width * .5, tr2.y + tr2.height / 2, { steps: 5 }); await p.mouse.up(); await h.dormir(2300);
    h.ok((await h.contadores()).spotify.pop().startsWith('posicao:11'), `${pos}: arrastar a barra da tela cheia manda a posição ao Mac`);
    // muda a faixa no Mac: a tela cheia acompanha
    await h.cenario({ faixa: 'Outra Faixa', artista: 'Artista Exemplo' });
    h.ok(await h.espera(p, () => document.querySelector('#f-player .faixa').textContent === 'Outra Faixa', null, 3000), `${pos}: a faixa nova do Mac aparece na tela cheia`);
    await p.click('#f-player [data-fechar]');
    h.ok(await h.espera(p, () => !document.querySelector('#f-player').classList.contains('aberta'), null, 2000), `${pos}: o X fecha o player`);
    await p.context().close();
  }
  // Spotify fecha no Mac com o player aberto: a tela cheia fecha junto
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player .titulos'); await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta'));
  await h.cenario({ spotify: 'fechado' });
  h.ok(await h.espera(p, () => !document.querySelector('#f-player').classList.contains('aberta'), null, 4000), 'se o Spotify fecha no Mac, a tela cheia do player fecha (nada para mostrar)');
  await p.context().close();
  // no modo organizar a capa não abre o player
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const cO2 = await centro(p, '.tecla[data-id="apagar"]');
  await p.mouse.move(cO2.x, cO2.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await p.mouse.click(...await p.locator('.player .capa').boundingBox().then(b => [b.x + b.width / 2, b.y + b.height / 2]));
  await h.dormir(400);
  h.ok(await p.evaluate(() => !document.querySelector('#f-player').classList.contains('aberta')), 'no modo organizar, tocar na capa não abre o player');
  await p.context().close();
  // Mac antigo, sem repetir, aleatório nem álbum: só aparece o que existe
  await h.reset(); await h.cenario({ spotifyModos: 'sem' });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => document.querySelectorAll('.player .modo').length === 0), 'Mac sem repetir e aleatório: o player pequeno não inventa os botões');
  await p.click('.player .capa'); await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta'));
  h.ok(await p.evaluate(() => document.querySelectorAll('#f-player .modo').length === 0 && !document.querySelector('#f-player .album') && document.querySelectorAll('#f-player .midia button').length === 3), 'e a tela cheia também mostra só anterior, tocar e próxima, sem álbum');
  await p.context().close();
  // HTML malicioso no álbum e na faixa aparece como texto
  await h.reset(); await h.cenario({ xss: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player .capa'); await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta')); await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss && !document.querySelector('#f-player img[src="x"]') && document.querySelector('#f-player .album').textContent.includes('<img')), 'álbum com HTML aparece como texto na tela cheia e não executa');
  await p.context().close();
}
