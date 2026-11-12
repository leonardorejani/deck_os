// Player em tela cheia (SPEC, seção 13, item 39): o ícone de play no centro do círculo e a fila das próximas músicas, que desliza da
// direita para a esquerda, com a capa e o nome do que toca agora no alto e a lista embaixo.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const abrirPlayer = async (h, cenario, vista = {}) => {
  await h.reset(); await h.cenario({ atrasoAcao: 0, ...cenario });
  const q = await h.pagina(vista); await pronta(h, q); await h.dormir(400);
  await q.click('.player .capa');
  await h.espera(q, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(700);
  return q;
};
// quanto o triângulo do play está fora do centro do botão (px), e se sobrou algum deslocamento empurrado por CSS
const descentro = p => p.evaluate(() => [...document.querySelectorAll('.tocar')].filter(b => b.offsetParent).map(b => {
  const r = b.getBoundingClientRect(), t = b.querySelector('path').getBoundingClientRect(), k = document.querySelector('#tela').getBoundingClientRect().width / document.querySelector('#tela').offsetWidth;
  return { play: b.classList.contains('play'), dx: +((t.left + t.width / 2 - (r.left + r.width / 2)) / k).toFixed(2), dy: +((t.top + t.height / 2 - (r.top + r.height / 2)) / k).toFixed(2), deslocado: getComputedStyle(b.querySelector('svg')).translate };
}));

export default async function (h) {
  /* ---------- o play no centro do círculo ---------- */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    const p = await abrirPlayer(h, { spotify: 'pausado', spotifyExtras: 'login' }, { w, h: alt });
    const d = await descentro(p);
    h.ok(d.length === 2 && d.every(x => x.play), `${nome}: o player pequeno e o grande estão pausados, com o triângulo de play`);
    h.ok(d.every(x => Math.abs(x.dx) <= 1.5 && Math.abs(x.dy) <= .6), `${nome}: o triângulo de play fica no centro do círculo, no pequeno e no grande (desvio ${d.map(x => x.dx + 'px').join(' e ')})`);
    h.ok(d.every(x => x.deslocado === 'none'), `${nome}: e o ícone não é empurrado por CSS (${d.map(x => x.deslocado).join(', ')})`);
    if (nome === 'deitado') await h.foto(p, 'player-play');
    await p.context().close();
  }
  // tocando: o ícone de pausa também fica no centro
  {
    const p = await abrirPlayer(h, { spotify: 'tocando', spotifyExtras: 'login' });
    const d = await descentro(p);
    h.ok(d.length === 2 && d.every(x => !x.play && Math.abs(x.dx) <= .6), `tocando: a pausa também fica no centro (${d.map(x => x.dx).join(', ')})`);
    await p.context().close();
  }

  /* ---------- a fila desliza da direita para a esquerda ---------- */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    const p = await abrirPlayer(h, { spotifyExtras: 'login' }, { w, h: alt });
    h.ok(await p.evaluate(() => document.querySelector('#pc-lista').hidden), `${nome}: antes de tocar no botão a lista não está na tela`);
    // amostra a posição da lista, quadro a quadro, a partir do toque
    await p.evaluate(() => { window.__pos = []; const f = document.querySelector('#f-player').getBoundingClientRect(), t0 = performance.now(); const amostra = () => { const l = document.querySelector('#pc-lista'); window.__pos.push(l.hidden ? null : +(l.getBoundingClientRect().left - f.left).toFixed(1)); if (performance.now() - t0 < 1200) requestAnimationFrame(amostra) }; document.querySelector('#f-player [data-fila]').click(); requestAnimationFrame(amostra) });
    await h.dormir(1400);
    const entrada = (await p.evaluate(() => window.__pos)).filter(x => x != null);
    const largura = await p.evaluate(() => document.querySelector('#f-player').getBoundingClientRect().width);
    h.ok(entrada.length >= 6 && entrada[0] >= largura * .5, `${nome}: a lista começa fora da tela, à direita (primeira posição ${entrada[0]} de ${Math.round(largura)})`);
    h.ok(entrada.slice(1).every((x, i) => x <= entrada[i] + .01) && new Set(entrada.filter(x => x > 0 && x < largura * .5)).size >= 3, `${nome}: e anda para a esquerda, em vários quadros (${entrada.length} amostras)`);
    h.ok(entrada.at(-1) === 0, `${nome}: termina cobrindo o player, sem sobra (${entrada.at(-1)})`);
    const fl = await p.evaluate(() => {
      const topo = document.querySelector('#pc-lista-topo'), r = topo.getBoundingClientRect(), img = topo.querySelector('img'), corpo = document.querySelector('#pc-lista-corpo').getBoundingClientRect(), cab = document.querySelector('#pc-lista > header').getBoundingClientRect();
      return { nome: topo.querySelector('b').textContent, artista: topo.querySelector('small:not(.rotulo)').textContent, rotulo: topo.querySelector('.rotulo').textContent, img: !!img && /capa/.test(img.getAttribute('src') || ''), lado: Math.round(img.getBoundingClientRect().width),
        ordem: cab.bottom <= r.top + 1 && r.bottom <= corpo.top + 1, itens: [...document.querySelectorAll('#pc-lista-corpo .item-lista b')].map(x => x.textContent).slice(0, 2).join('|'), n: document.querySelectorAll('#pc-lista-corpo .item-lista').length };
    });
    h.ok(fl.nome === 'Faixa de Exemplo' && fl.artista === 'Artista Exemplo' && fl.rotulo === 'Tocando agora' && fl.img && fl.lado >= 56, `${nome}: no alto, a capa e o nome de quem toca agora (${fl.nome}, ${fl.artista}, capa ${fl.lado}px)`);
    h.ok(fl.ordem && fl.n === 9 && fl.itens === 'Próxima música 1|Próxima música 2', `${nome}: embaixo, a lista das próximas músicas (${fl.n} itens: ${fl.itens})`);
    if (nome === 'deitado') {
      // o alto fica parado enquanto a lista rola
      const antes = await p.evaluate(() => document.querySelector('#pc-lista-topo').getBoundingClientRect().top);
      await p.evaluate(() => { document.querySelector('#pc-lista-corpo').scrollTop = 200 }); await h.dormir(200);
      const depois = await p.evaluate(() => ({ topo: document.querySelector('#pc-lista-topo').getBoundingClientRect().top, rolou: document.querySelector('#pc-lista-corpo').scrollTop }));
      h.ok(depois.rolou > 0 && depois.topo === antes, `${nome}: a lista rola e o alto com a capa fica parado (rolou ${depois.rolou}px)`);
    }
    await h.foto(p, nome === 'deitado' ? 'player-fila-slide' : 'player-fila-slide-em-pe');
    // a música muda: o alto troca na hora
    await h.cenario({ faixa: 'Outra Faixa' });
    h.ok(await h.espera(p, () => document.querySelector('#pc-lista-topo b').textContent === 'Outra Faixa', null, 5000), `${nome}: quando a música muda, o nome no alto da fila acompanha`);
    // Voltar: sai deslizando de volta para a direita
    await p.evaluate(() => { window.__pos = []; const f = document.querySelector('#f-player').getBoundingClientRect(), t0 = performance.now(); const amostra = () => { const l = document.querySelector('#pc-lista'); window.__pos.push(l.hidden ? null : +(l.getBoundingClientRect().left - f.left).toFixed(1)); if (performance.now() - t0 < 900) requestAnimationFrame(amostra) }; document.querySelector('#pc-lista [data-pc-voltar]').click(); requestAnimationFrame(amostra) });
    await h.dormir(1100);
    const saida = (await p.evaluate(() => window.__pos));
    const vis = saida.filter(x => x != null);
    h.ok(vis.length >= 3 && vis.slice(1).every((x, i) => x >= vis[i] - .01) && vis.at(-1) > largura * .5, `${nome}: Voltar leva a lista de volta para a direita, deslizando (${vis.length} amostras, termina em ${vis.at(-1)})`);
    h.ok(saida.at(-1) === null && await p.evaluate(() => !!document.querySelector('#f-player .capa-grande') && document.querySelector('#pc-lista').hidden), `${nome}: e depois some, mostrando o player`);
    // abrir de novo desliza de novo
    await p.click('#f-player [data-fila]'); await h.dormir(700);
    h.ok(await p.evaluate(() => document.querySelector('#pc-lista').getBoundingClientRect().left - document.querySelector('#f-player').getBoundingClientRect().left) === 0, `${nome}: tocar de novo abre a fila outra vez`);
    await p.context().close();
  }

  /* ---------- a lista de aparelhos usa o mesmo deslizar, sem o alto da fila ---------- */
  {
    const p = await abrirPlayer(h, { spotifyExtras: 'login' });
    await p.click('#f-player [data-aparelhos]'); await h.dormir(700);
    h.ok(await p.evaluate(() => document.querySelector('#pc-lista').getBoundingClientRect().left - document.querySelector('#f-player').getBoundingClientRect().left) === 0 && await p.evaluate(() => document.querySelector('#pc-lista-topo').hidden), 'aparelhos: a lista também desliza, e o alto da fila não aparece');
    await p.context().close();
  }

  /* ---------- sem Spotify conectado o botão da fila continua não existindo ---------- */
  {
    const p = await abrirPlayer(h, { spotifyExtras: 'volume' });
    h.ok(await p.evaluate(() => !document.querySelector('#f-player [data-fila]')), 'sem login no Spotify o Mac não tem fila para mostrar: o botão não aparece (como antes)');
    await p.context().close();
  }
}
