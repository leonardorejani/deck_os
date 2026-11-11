// As duas composições, deitado e em pé: área segura (SPEC, seção 3), perfil, teclas acesas, selos e player.
const SEGURA = { horizontal: { l: 59, r: 873, t: 0, b: 409 }, vertical: { l: 0, r: 430, t: 59, b: 898 } };
// devolve tudo que passa da área segura (em pixels da tela, já descontada a escala)
const estouros = (p, pos) => p.evaluate(([pos, S]) => {
  const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth, ruins = [];
  const alvos = document.querySelectorAll('.relogio-linha, .data-linha, .cartao, .carrossel, .menu-area, .divisor, .pagina:first-child .tecla');
  for (const el of alvos) {
    const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
    const q = { l: (r.left - t.left) / k, r: (r.right - t.left) / k, t: (r.top - t.top) / k, b: (r.bottom - t.top) / k };
    if (q.l < S.l - 1 || q.r > S.r + 1 || q.t < S.t - 1 || q.b > S.b + 1) ruins.push(`${el.className.split(' ').slice(0, 2).join('.')} ${JSON.stringify(Object.fromEntries(Object.entries(q).map(([a, b]) => [a, Math.round(b)])))}`);
  }
  if (document.documentElement.scrollWidth > innerWidth + 1 || document.documentElement.scrollHeight > innerHeight + 1) ruins.push('a página rola');
  return ruins;
}, [pos, SEGURA[pos]]);

export default async function (h) {
  const p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  const VISTAS = { horizontal: [932, 430], vertical: [430, 932] };
  const CASOS = [
    ['padrão', {}], ['12 teclas', { teclas: 'muitas' }], ['Spotify fechado, sem sessões', { spotify: 'fechado', sessoes: 0 }],
    ['sem uso e sem sessões', { blocos: { uso: false, sessoes: false } }], ['sessões e uso, sem Spotify', { blocos: { spotify: false } }],
  ];
  for (const comp of ['a', 'b']) for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    for (const [nome, patch] of CASOS) {
      await h.reset(); await h.cenario({ comp, ...patch });
      const certo = await h.espera(p, ([c, pos]) => !!document.querySelector(`.comp-${c}`) && document.querySelector('#moldura').classList.contains(pos), [comp, pos], 4000);
      await h.dormir(1400); // estado novo + animação de entrada
      const ruins = await estouros(p, pos);
      h.ok(certo && ruins.length === 0, `composição ${comp.toUpperCase()} ${pos}, ${nome}: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
      if (nome === 'padrão' || nome === '12 teclas') await h.foto(p, `${comp}-${pos}${nome === '12 teclas' ? '-12' : ''}`);
    }
  }
  /* o tamanho de outros iPhones: a tela escala sem estourar */
  await h.reset();
  for (const [w, alt] of [[844, 390], [390, 844], [1180, 820]]) {
    await p.setViewportSize({ width: w, height: alt }); await h.dormir(300);
    const r = await p.evaluate(() => { const t = document.querySelector('#tela').getBoundingClientRect(); return { l: t.left, r: t.right, t: t.top, b: t.bottom, w: innerWidth, h: innerHeight } });
    h.ok(r.l >= -1 && r.t >= -1 && r.r <= r.w + 1 && r.b <= r.h + 1, `viewport ${w} x ${alt}: a tela escala e cabe (${Math.round(r.r - r.l)} x ${Math.round(r.b - r.t)})`);
  }
  await p.close();

  /* teclas acesas, selos e perfil, deitado na A */
  await h.reset(); await h.cenario({ perfis: 'dois' });
  const q = await h.pagina();
  await h.espera(q, () => !!document.querySelector('.comp-a .faixa'));
  let v = await q.evaluate(() => ({ chip: !!document.querySelector('.perfil-chip'), menu: document.querySelector('.menu-area .tecla.menu .nome')?.textContent, n: document.querySelectorAll('.pagina .tecla').length }));
  h.ok(!v.chip && v.menu === 'Menu' && v.n === 4, `o chip de perfil saiu da data e a tecla é o Menu (chip ${v.chip}, "${v.menu}", ${v.n} teclas)`);
  await q.click('.tecla.menu');
  v = await q.evaluate(() => ({ aberta: !document.querySelector('#lista-perfis').hidden, op: [...document.querySelectorAll('#lista-perfis [role=option]')].map(o => o.textContent.replace(/\s+/g, ' ')), ativo: document.querySelector('#lista-perfis [aria-selected=true]')?.dataset.perfil }));
  h.ok(v.aberta && v.op.length === 2 && v.op[1] === 'Ensaio5 teclas' && v.ativo === 'trabalho', `tocar no Menu abre a folha com os perfis e o ativo marcado (${v.op.join(' | ')})`);
  await h.foto(q, 'menu-folha');
  await q.click('#lista-perfis [data-perfil="ensaio"]');
  h.ok(await h.espera(q, () => document.querySelector('#lista-perfis').hidden && document.querySelectorAll('.pagina .tecla').length === 5), 'trocar de perfil mostra as teclas do outro perfil');
  await h.ate(async () => (await h.contadores()).configsGravadas.length >= 1); // a tela muda no toque, o Mac recebe logo depois
  const gravadas = (await h.contadores()).configsGravadas;
  h.ok(gravadas.length === 1 && gravadas[0].perfilAtivo === 'ensaio' && gravadas[0].perfis.length === 2, 'a troca vai para o Mac pela config (perfilAtivo "ensaio")');
  h.ok(await q.evaluate(() => !!document.querySelector('.tecla[data-id="e-spotify"]') && !document.querySelector('.tecla[data-id="acordado"]')), 'as teclas do perfil Trabalho saem');
  await q.context().close();

  /* player: capa, cores da capa, botões e barra de tempo arrastável */
  await h.reset();
  const r = await h.pagina();
  await h.espera(r, () => !!document.querySelector('.comp-a .faixa'));
  v = await r.evaluate(() => { const pl = document.querySelector('.player'), cs = getComputedStyle(pl); return { src: document.querySelector('.capa').getAttribute('src'), c1: cs.getPropertyValue('--capa-1').trim(), c2: cs.getPropertyValue('--capa-2').trim(), faixa: document.querySelector('.faixa').textContent, artista: document.querySelector('.artista').textContent, total: document.querySelector('.progresso .total').textContent, carregou: document.querySelector('.capa').naturalWidth > 0 } });
  h.ok(v.src.startsWith('/api/capa?codigo=') && v.src.includes('v=capa-1') && v.carregou, `capa pelo capaUrl, com o código na URL e a imagem carregada (${v.src})`);
  h.ok(/^rgb\(150 48 48 \/ 0?\.55\)$/.test(v.c1) && /^rgb\(40 90 100 \/ 0?\.35\)$/.test(v.c2), `cores da capa no brilho do player (${v.c1} e ${v.c2})`);
  h.ok(v.faixa === 'Faixa de Exemplo' && v.artista === 'Artista Exemplo' && v.total === '3:41', 'faixa, artista e duração vêm do Mac');
  const t0 = await r.evaluate(() => document.querySelector('.progresso .decorrido').textContent);
  await h.dormir(2300);
  const t1 = await r.evaluate(() => document.querySelector('.progresso .decorrido').textContent);
  h.ok(t0 !== t1, `o tempo decorrido anda com o estado de cada segundo (${t0} para ${t1})`);
  await r.click('[data-midia="anterior"]'); await r.click('[data-midia="proxima"]');
  await r.click('[data-midia="tocar"]');
  h.ok(await h.espera(r, () => !!document.querySelector('.player.pausado') && !!document.querySelector('.tocar.play'), null, 3000), 'tocar com a música tocando pausa e o player fica a meia luz');
  await r.click('[data-midia="tocar"]');
  h.ok(await h.espera(r, () => !document.querySelector('.player.pausado'), null, 3000), 'tocar de novo volta a tocar');
  h.ok((await h.contadores()).spotify.join() === 'anterior,proxima,pausar,tocar', `o Mac recebeu anterior, proxima, pausar e tocar (${(await h.contadores()).spotify})`);
  // arrastar a barra de tempo
  const tr = await r.locator('.progresso .trilho').boundingBox();
  await r.mouse.move(tr.x + tr.width * .1, tr.y + tr.height / 2); await r.mouse.down();
  await r.mouse.move(tr.x + tr.width * .5, tr.y + tr.height / 2, { steps: 5 });
  v = await r.evaluate(() => ({ arrastando: document.querySelector('.progresso').classList.contains('arrastando'), t: document.querySelector('.progresso .decorrido').textContent }));
  h.ok(v.arrastando && /^1:5[01]$/.test(v.t), `arrastando a barra mostra o tempo do dedo ("${v.t}")`);
  await h.foto(r, 'player-arrastando');
  await r.mouse.up();
  await h.dormir(400);
  const pos = (await h.contadores()).spotify.filter(x => x.startsWith('posicao')).pop();
  h.ok(/^posicao:11[01]$/.test(pos), `soltar manda spotify('posicao', s) ao Mac (${pos})`);
  h.ok(await h.espera(r, () => /^1:5\d$|^1:4\d$|^1:[0-9]{2}$/.test(document.querySelector('.progresso .decorrido').textContent), null, 3000), 'depois de soltar, o tempo continua dali');
  await r.context().close();

  /* em pé, as duas composições também mostram selos, horário e teclas acesas */
  for (const comp of ['a', 'b']) {
    await h.reset(); await h.cenario({ comp });
    const s = await h.pagina({ w: 430, h: 932 });
    await h.espera(s, () => !!document.querySelector('.faixa'));
    v = await s.evaluate(() => ({ acesa: document.querySelectorAll('.tecla.acesa').length, selo: document.querySelector('.tecla[data-id="whatsapp"] .selo')?.textContent, hora: !!document.querySelector('.tecla[data-id="calendario"] .hora-tecla') }));
    h.ok(v.acesa === 1 && v.selo === '23' && v.hora, `${comp.toUpperCase()} em pé: tecla acesa, selo do WhatsApp e horário da Agenda`);
    await s.context().close();
  }
}
