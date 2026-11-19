// Gráfico "Tokens por dia" da tela Uso das IAs (19/11/2026): tocar numa barra diz o dia e o valor, sem seleção o topo mostra hoje,
// duas linhas de grade com o valor, e cada barra com texto para o leitor de tela. Vale para Dia, Semana e Mês. Toque de verdade (CDP).
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

export default async function (h) {
  for (const [rotulo, forma] of [['deitado', { width: 932, height: 430 }], ['em pé', { width: 430, height: 932 }]]) {
    const ctx = await h.novoContexto({ hasTouch: true, viewport: forma });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.evaluate(() => abrirUso());
    await h.espera(p, () => !!document.querySelector('[data-c="mac.g.graf"]')); await h.dormir(900);
    const graf = '[data-c="mac.g.graf"] .us-grafico';
    /* Semana */
    h.ok(/^Hoje · \d/.test(await topo(p)), `${rotulo}: sem seleção o topo mostra hoje (${await topo(p)})`);
    h.ok(await p.evaluate(g => document.querySelectorAll(`${g} .us-gl`).length === 2 && [...document.querySelectorAll(`${g} .us-gl small`)].every(s => /\d/.test(s.textContent)), graf), `${rotulo}: duas linhas de grade com o valor`);
    h.ok(await p.evaluate(g => [...document.querySelectorAll(`${g} i`)].every(b => /^\S+ \d\d\/\d\d: .+/.test(b.getAttribute('aria-label') || '')), graf), `${rotulo}: cada barra tem o dia e o valor para o leitor de tela`);
    await toque(p, ctx, await centro(p, 2));
    const sel = await p.evaluate(g => ({ n: document.querySelectorAll(`${g} i.sel`).length, i: [...document.querySelectorAll(`${g} i`)].findIndex(b => b.classList.contains('sel')), tem: document.querySelector(g).classList.contains('tem-sel') }), graf);
    h.ok(sel.n === 1 && sel.i === 2 && sel.tem, `${rotulo}: tocar na 3a barra a seleciona e esmaece as outras`);
    h.ok(/^\S+ \d\d\/\d\d · \d/.test(await topo(p)), `${rotulo}: o topo troca para o dia e o valor da barra (${await topo(p)})`);
    await h.dormir(300);
    h.ok(await p.evaluate(g => parseFloat(getComputedStyle(document.querySelector(`${g} i:not(.sel):not(.vazia)`)).opacity) < .6, graf), `${rotulo}: as outras barras ficam esmaecidas`);
    const alta = await centro(p, 5); const r = await p.evaluate(g => document.querySelector(g).getBoundingClientRect().height, graf);
    await toque(p, ctx, { x: alta.x, y: alta.y - r / 2 + 3 }); // no alto da coluna, onde a barra baixa não chega
    h.ok(await p.evaluate(g => [...document.querySelectorAll(`${g} i`)].findIndex(b => b.classList.contains('sel')), graf) === 5, `${rotulo}: o toque vale a altura toda da coluna, também acima da barra`);
    await toque(p, ctx, await p.evaluate(() => { const e = document.querySelector('.us-aviso') || document.querySelector('#us-c3'); e.scrollIntoView({ block: 'center', behavior: 'instant' }); const r = e.getBoundingClientRect(); return { x: r.left + 8, y: r.top + r.height / 2 } }));
    h.ok(await p.evaluate(g => document.querySelectorAll(`${g} i.sel`).length === 0, graf) && /^Hoje ·/.test(await topo(p)), `${rotulo}: tocar fora solta a seleção e volta para hoje`);
    /* Dia e Mês */
    for (const [per, n] of [['dia', 24], ['mes', 30]]) {
      await p.click(`#us-filtro [data-p="${per}"]`);
      await h.espera(p, ([g, n]) => document.querySelectorAll(`${g} i`).length === n, [graf, n]); await h.dormir(700);
      await toque(p, ctx, await centro(p, 3));
      const aria = await p.evaluate(g => document.querySelectorAll(`${g} i`)[3].getAttribute('aria-label'), graf);
      h.ok(per === 'dia' ? /^3h: /.test(aria) && /^3h · /.test(await topo(p)) : /^\S+ \d\d\/\d\d: /.test(aria) && /^\S+ \d\d\/\d\d · /.test(await topo(p)), `${rotulo}, ${per}: a barra 4 diz "${aria}" e o topo acompanha (${await topo(p)})`);
    }
    await ctx.close();
  }
  /* mouse na janela larga: passar por cima faz o mesmo, sair volta */
  const ctx = await h.novoContexto({ viewport: { width: 1440, height: 900 } });
  const p = await h.pagina({ ctx }); await pronta(h, p);
  await p.evaluate(() => abrirUso()); await h.espera(p, () => !!document.querySelector('[data-c="mac.g.graf"]')); await h.dormir(900);
  const pt = await centro(p, 4); await p.mouse.move(pt.x, pt.y); await p.mouse.move(pt.x + 1, pt.y); await h.dormir(80);
  h.ok(await p.evaluate(() => [...document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i')].findIndex(b => b.classList.contains('sel'))) === 4 && !/^Hoje/.test(await topo(p)), `janela: passar o mouse seleciona a barra (${await topo(p)})`);
  await p.mouse.move(5, 5); await h.dormir(80);
  h.ok(await p.evaluate(() => document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i.sel').length) === 0 && /^Hoje ·/.test(await topo(p)), 'janela: tirar o mouse volta para hoje');
  await ctx.close();
}
