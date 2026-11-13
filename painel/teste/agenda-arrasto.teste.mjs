// Frente agenda-arrasto (13/11/2026): arrastar e segurar na Agenda nunca deixa uma coluna por cima da outra.
// Antes: a lista do dia, arrastada para a esquerda, passava por cima do mês (print do Chrome em janela larga).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="calendario"]'));
const caixa = (p, sel) => p.evaluate(s => { const b = document.querySelector(s).getBoundingClientRect(); return { l: b.left, r: b.right, t: b.top, b: b.bottom } }, sel);
const cruza = (a, b) => a.l < b.r - 1 && b.l < a.r - 1 && a.t < b.b - 1 && b.t < a.b - 1;
const estado = p => p.evaluate(() => ({ mes: getComputedStyle(document.querySelector('#ca-mes')).translate, lista: getComputedStyle(document.querySelector('#ca-lista')).translate, opM: getComputedStyle(document.querySelector('#ca-mes')).opacity, opL: getComputedStyle(document.querySelector('#ca-lista')).opacity }));
// o que a pessoa VÊ de cada coluna: a própria caixa recortada pela janela que a contém
const visivel = (p, janela, el) => p.evaluate(([j, e]) => { const a = document.querySelector(j).getBoundingClientRect(), b = document.querySelector(e).getBoundingClientRect();
  return { l: Math.max(a.left, b.left), r: Math.min(a.right, b.right), t: Math.max(a.top, b.top), b: Math.min(a.bottom, b.bottom) } }, [janela, el]);

export default async function (h) {
  const tamanhos = [['celular deitado', 932, 430], ['celular em pé', 430, 932], ['janela larga', 2000, 1100], ['janela média', 1000, 570]];
  for (const [nome, w, al] of tamanhos) {
    const ctx = await h.novoContexto({ viewport: { width: w, height: al } });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0); await h.dormir(500);
    const vert = w < al;
    const mj = await caixa(p, '.mes-janela'), lj = await caixa(p, '.lista-janela');
    h.ok(!cruza(mj, lj), `${nome}: no repouso mês e lista ocupam lugares separados`);

    // 1. segurar o mês arrastado para os dois lados: ele não passa para a coluna da lista
    const m = await p.locator('#ca-mes').boundingBox(), ym = m.y + m.height / 2;
    for (const [de, para] of [[m.x + m.width - 20, m.x + 30], [m.x + 30, m.x + m.width - 20]]) {
      await p.mouse.move(de, ym); await p.mouse.down(); await p.mouse.move(para, ym, { steps: 8 });
      const v = await visivel(p, '.mes-janela', '#ca-mes'), l = await visivel(p, '.lista-janela', '#ca-lista');
      h.ok(!cruza(v, l) && (await caixa(p, '.mes-janela')).r <= (await caixa(p, '.lista-janela')).l + 1 + (vert ? 9999 : 0), `${nome}: mês seguro no dedo fica na coluna dele (${JSON.stringify(v)})`);
      await p.mouse.up(); await h.dormir(700);
      const e = await estado(p); h.ok(e.mes === 'none' && e.opM === '1', `${nome}: mês solto volta ao lugar (${JSON.stringify(e)})`);
    }

    // 2. segurar a lista arrastada para a esquerda (abre o formulário): ela não passa por cima do mês
    const ls = await p.locator('#ca-lista').boundingBox(), yl = ls.y + Math.min(ls.height / 2, 120);
    await p.mouse.move(ls.x + ls.width - 40, yl); await p.mouse.down(); await p.mouse.move(ls.x + 20, yl, { steps: 8 });
    const e2 = await estado(p), mesVis = await visivel(p, '.mes-janela', '#ca-mes'), listaVis = await visivel(p, '.lista-janela', '#ca-lista');
    h.ok(e2.lista !== 'none', `${nome}: a lista seguiu o dedo (${e2.lista})`);
    h.ok(!cruza(mesVis, listaVis), `${nome}: lista segura no dedo não cobre o mês (${JSON.stringify(listaVis)} x ${JSON.stringify(mesVis)})`);
    // o que a pessoa vê de fato: nos pontos do mês, o elemento por cima nunca é a lista (vale com ou sem janela)
    const topo = await p.evaluate(() => { const m = document.querySelector('#ca-mes').getBoundingClientRect(), r = [];
      for (const fx of [.15, .5, .85]) for (const fy of [.2, .5, .8]) { const el = document.elementFromPoint(m.left + m.width * fx, m.top + m.height * fy); if (el && el.closest('#ca-lista')) r.push([fx, fy]) } return r });
    h.ok(topo.length === 0, `${nome}: segurando a lista, nenhum ponto do mês é coberto por ela (${JSON.stringify(topo)})`);
    await h.foto(p, `agenda-arrasto-lista-${w}x${al}`);
    // soltar no meio do caminho: volta, nada fica deslocado
    await p.mouse.move(ls.x + ls.width - 90, yl, { steps: 4 }); await p.mouse.up(); await h.dormir(600);
    const e3 = await estado(p); h.ok(e3.lista === 'none' && e3.opL === '1' && !(await p.evaluate(() => document.querySelector('#f-cal').classList.contains('novo'))), `${nome}: lista solta no meio volta ao lugar (${JSON.stringify(e3)})`);

    // 2b. arrasto curto da lista (o do print: a lista no meio do caminho, cobrindo parte do mês)
    await p.mouse.move(ls.x + ls.width - 40, yl); await p.mouse.down(); await p.mouse.move(ls.x + ls.width * .45, yl, { steps: 8 });
    const curto = await p.evaluate(() => { const m = document.querySelector('#ca-mes').getBoundingClientRect(), r = [];
      for (const fx of [.15, .5, .85, .98]) for (const fy of [.2, .5, .8]) { const el = document.elementFromPoint(m.left + m.width * fx, m.top + m.height * fy); if (el && el.closest('#ca-lista')) r.push([fx, fy]) } return r });
    h.ok(curto.length === 0, `${nome}: lista arrastada até a metade não cobre o mês (${JSON.stringify(curto)})`);
    await p.mouse.move(ls.x + ls.width - 60, yl, { steps: 3 }); await p.mouse.up(); await h.dormir(600);

    // 3. arrasto rápido do mês (flick) troca de mês e tudo termina no lugar, sem sobra
    const t0 = await p.evaluate(() => document.querySelector('#ca-titulo').textContent);
    await p.mouse.move(m.x + m.width - 20, ym); await p.mouse.down(); await p.mouse.move(m.x + m.width - 120, ym, { steps: 2 }); await p.mouse.up(); await h.dormir(900);
    const e4 = await estado(p), t1 = await p.evaluate(() => document.querySelector('#ca-titulo').textContent);
    h.ok(t1 !== t0 && e4.mes === 'none' && e4.opM === '1' && e4.lista === 'none', `${nome}: arrasto rápido troca o mês e nada fica deslocado (${t0} -> ${t1} ${JSON.stringify(e4)})`);
    const mj2 = await caixa(p, '.mes-janela'), lj2 = await caixa(p, '.lista-janela');
    h.ok(!cruza(mj2, lj2), `${nome}: depois da troca mês e lista continuam separados`);

    // 4. o dedo perde o arrasto no meio (janela perde o foco, gesto cancelado pelo sistema): nada fica preso
    await p.mouse.move(ls.x + ls.width - 40, yl); await p.mouse.down(); await p.mouse.move(ls.x + 20, yl, { steps: 6 });
    await p.evaluate(() => document.querySelector('#ca-lista').dispatchEvent(new PointerEvent('lostpointercapture', { pointerId: 1, isPrimary: true, bubbles: true })));
    await h.dormir(500);
    const e5 = await estado(p); h.ok(e5.lista === 'none' && e5.opL === '1', `${nome}: arrasto que perde o ponteiro não deixa a lista presa (${JSON.stringify(e5)})`);
    await p.mouse.up(); await ctx.close();
  }
}
