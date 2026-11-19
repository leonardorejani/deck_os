// Gráfico "Tokens por dia" da tela Uso das IAs (19/11/2026): todas as barras acesas na cor cheia, sem seleção por toque nem por mouse
// (no celular não há hover), o topo mostra o período atual, duas linhas de grade com o valor e cada barra com texto para o leitor de tela.
// Vale para Dia, Semana e Mês. Toque de verdade (CDP) para provar que tocar não apaga nem seleciona nada.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.cartao.uso, .uso-tira'));
const topo = p => p.evaluate(() => document.querySelector('[data-c="mac.g.graf"] [data-t$=".pico"]').textContent.trim());
const centro = async (p, i) => { await p.evaluate(() => document.querySelector('[data-c="mac.g.graf"]').scrollIntoView({ block: 'center', behavior: 'instant' })); await h_dormir(150); return p.evaluate(i => { const b = document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i')[i].getBoundingClientRect(), g = document.querySelector('[data-c="mac.g.graf"] .us-grafico').getBoundingClientRect(); return { x: b.left + b.width / 2, y: g.top + g.height / 2 } }, i) };
async function toque(p, ctx, pt) {
  const c = await ctx.newCDPSession(p);
  await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [pt] });
  await c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await h_dormir(60);
}
const h_dormir = ms => new Promise(r => setTimeout(r, ms));
// todas com opacidade cheia e a mesma cor, menos a atual (que só ganha brilho)
const acesas = (p, g) => p.evaluate(g => { const bs = [...document.querySelectorAll(`${g} i:not(.vazia)`)]; const cor = getComputedStyle(bs[0]).backgroundColor; return bs.length > 0 && bs.every(b => parseFloat(getComputedStyle(b).opacity) === 1 && getComputedStyle(b).backgroundColor === cor) && !document.querySelector(g).classList.contains('tem-sel') && !document.querySelector(`${g} i.sel`) }, g);

export default async function (h) {
  for (const [rotulo, forma] of [['deitado', { width: 932, height: 430 }], ['em pé', { width: 430, height: 932 }]]) {
    const ctx = await h.novoContexto({ hasTouch: true, viewport: forma });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.evaluate(() => abrirUso());
    await h.espera(p, () => !!document.querySelector('[data-c="mac.g.graf"]')); await h.dormir(900);
    const graf = '[data-c="mac.g.graf"] .us-grafico';
    /* Semana */
    h.ok(/^Hoje · \d/.test(await topo(p)), `${rotulo}: o topo mostra hoje (${await topo(p)})`);
    h.ok(await acesas(p, graf), `${rotulo}: todas as barras acesas, na cor cheia`);
    h.ok(await p.evaluate(g => document.querySelectorAll(`${g} .us-gl`).length === 2 && [...document.querySelectorAll(`${g} .us-gl small`)].every(s => /\d/.test(s.textContent)), graf), `${rotulo}: duas linhas de grade com o valor`);
    h.ok(await p.evaluate(g => [...document.querySelectorAll(`${g} i`)].every(b => /^\S+ \d\d\/\d\d: .+/.test(b.getAttribute('aria-label') || '')), graf), `${rotulo}: cada barra tem o dia e o valor para o leitor de tela`);
    await toque(p, ctx, await centro(p, 2)); await h.dormir(300);
    h.ok(await acesas(p, graf) && /^Hoje · \d/.test(await topo(p)), `${rotulo}: tocar numa barra não seleciona nem esmaece nada, o topo segue em hoje (${await topo(p)})`);
    await centro(p, 0); await h.foto(p, `grafico-aceso-${rotulo === 'deitado' ? 'deitado' : 'em-pe'}`);
    /* Dia e Mês */
    for (const [per, n, ini] of [['dia', 24, /^Agora · /], ['mes', 30, /^Hoje · /]]) {
      await p.click(`#us-filtro [data-p="${per}"]`);
      await h.espera(p, ([g, n]) => document.querySelectorAll(`${g} i`).length === n, [graf, n]); await h.dormir(700);
      await toque(p, ctx, await centro(p, 3)); await h.dormir(300);
      const aria = await p.evaluate(g => document.querySelectorAll(`${g} i`)[3].getAttribute('aria-label'), graf);
      h.ok(per === 'dia' ? /^3h: /.test(aria) : /^\S+ \d\d\/\d\d: /.test(aria), `${rotulo}, ${per}: a barra 4 diz "${aria}"`);
      h.ok(ini.test(await topo(p)) && await acesas(p, graf), `${rotulo}, ${per}: topo "${await topo(p)}" e todas as barras acesas depois do toque`);
    }
    await ctx.close();
  }
  /* mouse na janela larga: passar por cima não muda nada */
  const ctx = await h.novoContexto({ viewport: { width: 1440, height: 900 } });
  const p = await h.pagina({ ctx }); await pronta(h, p);
  await p.evaluate(() => abrirUso()); await h.espera(p, () => !!document.querySelector('[data-c="mac.g.graf"]')); await h.dormir(900);
  const pt = await centro(p, 4); await p.mouse.move(pt.x, pt.y); await p.mouse.move(pt.x + 1, pt.y); await h.dormir(300);
  h.ok(await acesas(p, '[data-c="mac.g.graf"] .us-grafico') && /^Hoje · \d/.test(await topo(p)), `janela: passar o mouse não muda nada (${await topo(p)})`);
  await ctx.close();
}
