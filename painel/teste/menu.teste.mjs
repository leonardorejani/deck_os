// Menu: a tecla isolada que substitui a "Nova" e o seletor de perfil (SPEC, seção 4, "Menu").
// Abre a folha, troca perfil e grava, "Nova tecla" abre o editor, toque fora fecha, A e B, deitado e em pé.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla.menu'));
const folha = p => p.evaluate(() => {
  const l = document.querySelector('#lista-perfis'), t = document.querySelector('#tela').getBoundingClientRect(), k = t.width / document.querySelector('#tela').offsetWidth;
  const r = l.getBoundingClientRect(), m = document.querySelector('.tecla.menu').getBoundingClientRect();
  const sobre = !(r.right <= m.left || r.left >= m.right || r.bottom <= m.top || r.top >= m.bottom);
  return {
    aberta: !l.hidden, papel: l.getAttribute('role'),
    dentro: (r.left - t.left) / k >= 7 && (r.right - t.left) / k <= t.width / k - 7 && (r.top - t.top) / k >= 7 && (r.bottom - t.top) / k <= t.height / k - 7,
    sobre, nova: [...l.querySelectorAll('[data-nova-tecla]')].map(b => b.textContent), rotulo: l.querySelector('.rotulo-lista')?.textContent,
    perfis: [...l.querySelectorAll('[role=option]')].map(o => o.dataset.perfil + (o.getAttribute('aria-selected') === 'true' ? '*' : '')), dica: !!l.querySelector('.dica-perfis'),
  };
});

export default async function (h) {
  /* A e B, deitado e em pé: a folha abre ancorada na tecla, inteira dentro da tela e sem cobrir o Menu */
  for (const comp of ['a', 'b']) for (const [pos, w, alt] of [['horizontal', 932, 430], ['vertical', 430, 932]]) {
    await h.reset(); await h.cenario({ comp, perfis: 'dois' });
    const p = await h.pagina({ w, h: alt }); await pronta(h, p);
    const nome = `${comp.toUpperCase()} ${pos}`;
    const pos0 = await p.evaluate(() => ({ chip: !!document.querySelector('.perfil-chip'), nova: !!document.querySelector('.tecla.nova'), rotulo: document.querySelector('.tecla.menu .nome')?.textContent, ultimaGrade: document.querySelector('.pagina:last-child .tecla:last-child')?.classList.contains('menu') }));
    h.ok(!pos0.chip && !pos0.nova && pos0.rotulo === 'Menu', `${nome}: sem chip de perfil e sem tecla Nova, só o Menu`);
    if (comp === 'b' && pos === 'horizontal') h.ok(pos0.ultimaGrade, `${nome}: o Menu é a última tecla da grade`);
    else h.ok(await p.evaluate(() => !!document.querySelector('.menu-area .tecla.menu') && !document.querySelector('.pagina .tecla.menu')), `${nome}: o Menu fica numa seção só dele`);
    await p.click('.tecla.menu'); await h.dormir(150);
    const f = await folha(p);
    h.ok(f.aberta && f.papel === 'dialog' && f.dentro && !f.sobre, `${nome}: a folha abre dentro da tela e sem cobrir o Menu (${JSON.stringify({ dentro: f.dentro, sobre: f.sobre })})`);
    h.ok(f.nova.join() === 'Nova tecla' && f.rotulo === 'Perfil' && f.perfis.join() === 'trabalho*,ensaio' && f.dica, `${nome}: Nova tecla, Perfil e a lista com o ativo marcado (${f.perfis.join()})`);
    if (comp === 'a' || pos === 'vertical') await h.foto(p, `menu-${comp}-${pos}`);
    await p.context().close();
  }

  /* trocar perfil grava, Nova tecla abre o editor, toque fora só fecha */
  await h.reset(); await h.cenario({ perfis: 'dois' });
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla.menu'); await p.click('#lista-perfis [data-perfil="ensaio"]');
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="e-spotify"]') && document.querySelector('#lista-perfis').hidden), 'trocar perfil pelo Menu mostra as teclas do outro perfil e fecha a folha');
  await h.ate(async () => (await h.contadores()).configsGravadas.length >= 1); // a tela muda no toque, o Mac recebe logo depois
  let g = (await h.contadores()).configsGravadas;
  h.ok(g.length === 1 && g[0].perfilAtivo === 'ensaio' && g[0].perfis.length === 2, 'e grava no Mac a config inteira com perfilAtivo "ensaio"');
  await p.click('.tecla.menu');
  h.ok((await folha(p)).perfis.join() === 'trabalho,ensaio*', 'reaberta, a folha marca o perfil novo');
  await p.click('#lista-perfis [data-perfil="ensaio"]'); await h.dormir(300);
  h.ok((await h.contadores()).configsGravadas.length === 1, 'tocar no perfil que já está ativo não grava de novo');
  await p.click('.tecla.menu'); await p.click('#lista-perfis [data-nova-tecla]'); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('#lista-perfis').hidden && document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('#ed-titulo').textContent === 'Nova tecla' && document.querySelector('#ed-excluir').hidden), 'Nova tecla fecha a folha e abre o editor vazio, sem Excluir');
  await p.click('#f-editor [data-fechar].btn'); await h.dormir(400);
  const antes = (await h.contadores()).botoes.length;
  await p.click('.tecla.menu'); await p.mouse.click(120, 215); await h.dormir(200);
  h.ok((await folha(p)).aberta === false, 'tocar fora fecha a folha');
  await p.click('.tecla.menu'); await p.click('.tecla[data-id="e-spotify"]'); await h.dormir(300);
  h.ok((await folha(p)).aberta === false && (await h.contadores()).botoes.length === antes, 'com a folha aberta, tocar numa tecla só fecha, sem executar');
  await p.click('.tecla.menu'); await p.click('.tecla.menu'); await h.dormir(150);
  h.ok((await folha(p)).aberta === false, 'tocar no Menu de novo fecha a folha');
  await p.context().close();

  /* um perfil só: a parte Perfil mostra só ele, sem a dica */
  await h.reset(); await h.cenario({ perfis: 'um' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla.menu');
  const um = await folha(p);
  h.ok(um.aberta && um.perfis.join() === 'trabalho*' && !um.dica && um.nova.join() === 'Nova tecla', `com um perfil só: Nova tecla e Perfil com ele marcado, sem dica (${um.perfis.join()})`);
  await p.context().close();

  /* modo organizar: o Menu fica parado, a folha fecha ao entrar e tocar nele abre o editor de tecla nova */
  await h.reset(); await h.cenario({ perfis: 'dois' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla.menu'); await h.dormir(100);
  const c = await p.locator('.tecla[data-id="apagar"]').boundingBox();
  await p.mouse.move(c.x + c.width / 2, c.y + c.height / 2); await p.mouse.down(); await h.dormir(650); await p.mouse.up(); await h.dormir(200);
  h.ok(await p.evaluate(() => document.querySelector('#tela').classList.contains('organizando') && document.querySelector('#lista-perfis').hidden), 'entrar no modo organizar fecha a folha do Menu');
  h.ok(await p.evaluate(() => getComputedStyle(document.querySelector('.tecla.menu')).animationName === 'none' && getComputedStyle(document.querySelector('.tecla[data-id="apagar"]')).animationName === 'tremer'), 'no organizar as teclas tremem e o Menu fica parado');
  const m = await p.locator('.tecla.menu').boundingBox();
  await p.mouse.click(m.x + m.width / 2, m.y + m.height / 2); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('#ed-titulo').textContent === 'Nova tecla' && document.querySelector('#lista-perfis').hidden), 'no organizar, tocar no Menu abre o editor de tecla nova (e não a folha)');
  await p.context().close();
}
