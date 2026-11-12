// Frente iphone-bugs (12/11/2026): agenda só do mês na tela, mês arrastado sem passar por cima da lista,
// soltar a tecla fora da tela sem deixar rastro e puxar de cima para baixo para fechar as telas.
const iso = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aberta = (p, sel) => p.evaluate(s => document.querySelector(s).classList.contains('aberta'), sel);
const titulos = p => p.evaluate(() => [...document.querySelectorAll('#ca-lista .grupo-data h3')].map(x => x.textContent));
// toque de dedo de verdade (touchstart/move/end), com passos
async function dedo(p, ctx, de, para, { passos = 10, soltar = true, espera = 16 } = {}) {
  const c = await ctx.newCDPSession(p);
  await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [de] });
  for (let i = 1; i <= passos; i++) { await c.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: de.x + (para.x - de.x) * i / passos, y: de.y + (para.y - de.y) * i / passos }] }); await p.waitForTimeout(espera) }
  if (soltar) await c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  return c;
}

export default async function (h) {
  /* 1. agenda: o dia tocado mostra só o mês dele, e trocar de mês recarrega tudo daquele mês */
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]');
  await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0);
  const hoje = new Date(), diasDoMes = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0).getDate();
  const fimDoMes = new Date(hoje.getFullYear(), hoje.getMonth(), diasDoMes);
  // toca no primeiro dia depois de hoje, para a lista começar nele e cobrir só o resto do mês
  const dia = Math.min(hoje.getDate() + 1, diasDoMes), alvo = new Date(hoje.getFullYear(), hoje.getMonth(), dia);
  await p.click(`#ca-grade .sb-dia[data-dia="${iso(alvo)}"]`); await h.dormir(500);
  let c = await h.contadores();
  h.ok(c.agenda.at(-1) === `${iso(alvo)}|${diasDoMes - dia + 1}`, `tocar no dia pede só até o fim do mês (${c.agenda.at(-1)})`);
  let t = await titulos(p), meses = await p.evaluate(() => [...document.querySelectorAll('#ca-lista .grupo-data h3')].map(x => x.textContent));
  const nomeMes = hoje.toLocaleDateString('pt-BR', { month: 'long' });
  h.ok(t.length > 0 && t.every(x => x.endsWith(' de ' + nomeMes)), `a lista só tem dias de ${nomeMes} (${t.join(' | ')})`);
  // se o servidor devolvesse eventos do mês seguinte, a tela ainda assim não os mostra (defesa)
  await p.evaluate(() => { ag.lista = [...ag.lista, { titulo: 'De outro mês', inicio: new Date(ag.mes.getFullYear(), ag.mes.getMonth() + 1, 25, 10).toISOString(), diaTodo: false, calendario: 'X', cor: '#60A5FA' }]; pintarListaCal() });
  h.ok(!(await p.evaluate(() => document.querySelector('#ca-lista').textContent.includes('De outro mês'))), 'evento de outro mês nunca entra na lista');
  // trocar de mês: grade e lista recarregam, e a lista é do mês novo
  const n0 = (await h.contadores()).agenda.length;
  await p.click('#ca-prox'); await h.dormir(700);
  c = await h.contadores();
  const prox = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 1), diasProx = new Date(prox.getFullYear(), prox.getMonth() + 1, 0).getDate();
  h.ok(c.agenda.length === n0 + 2 && c.agenda.slice(n0).every(x => x === `${iso(prox)}|${diasProx}`), `trocar de mês recarrega grade e lista do mês novo (${c.agenda.slice(n0).join(' ')})`);
  t = await titulos(p); const nomeProx = prox.toLocaleDateString('pt-BR', { month: 'long' });
  h.ok(t.length > 0 && t.every(x => x.endsWith(' de ' + nomeProx)), `depois de trocar, a lista é toda de ${nomeProx} (${t.join(' | ')})`);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia.sel').length === 1), 'o dia escolhido acompanha o mês novo');

  /* 2. mês arrastado: fica dentro da coluna dele, a lista não é coberta */
  await p.click('#ca-ant'); await h.dormir(600);
  const cx = await p.locator('#ca-mes').boundingBox(), y = cx.y + cx.height / 2;
  await p.mouse.move(cx.x + cx.width - 20, y); await p.mouse.down(); await p.mouse.move(cx.x + 40, y, { steps: 8 });
  const m = await p.evaluate(() => { const j = document.querySelector('.mes-janela'), mes = document.querySelector('#ca-mes'), l = document.querySelector('#ca-lista').getBoundingClientRect(), jr = j.getBoundingClientRect(), mr = mes.getBoundingClientRect();
    return { clip: getComputedStyle(j).overflow, janelaDireita: Math.round(jr.right), listaEsq: Math.round(l.left), mesDireita: Math.round(mr.right), mesEsq: Math.round(mr.left), seguindo: getComputedStyle(mes).translate !== 'none' } });
  h.ok(m.seguindo && m.clip !== 'visible' && m.janelaDireita <= m.listaEsq, `a janela do mês recorta o arrasto e termina antes da lista (${JSON.stringify(m)})`);
  await h.foto(p, 'agenda-arrasto'); await p.mouse.up(); await h.dormir(500);

  /* 3. soltar a tecla fora da tela não deixa fantasma nem tecla apagada */
  await p.close();
  const ctxG = await h.novoContexto({ viewport: { width: 1200, height: 800 } });
  p = await h.pagina({ ctx: ctxG }); await pronta(h, p);
  const tb = await p.locator('.tecla[data-id="apagar"]').boundingBox();
  await p.mouse.move(tb.x + 20, tb.y + 20); await p.mouse.down(); await h.dormir(650);
  await p.mouse.move(tb.x + 80, tb.y + 60, { steps: 5 }); await p.mouse.move(5, 5, { steps: 8 }); await p.mouse.up(); await h.dormir(500);
  const rastro = await p.evaluate(() => ({ fantasma: document.querySelectorAll('.fantasma').length, apagadas: document.querySelectorAll('.tecla.arrastando').length }));
  h.ok(rastro.fantasma === 0 && rastro.apagadas === 0, `soltar fora da tela termina o arrasto sem rastro (${JSON.stringify(rastro)})`);
  await ctxG.close();

  /* 4. puxar de cima para baixo fecha a tela aberta, e soltar cedo devolve */
  const ctx = await h.novoContexto({ hasTouch: true });
  p = await h.pagina({ ctx }); await pronta(h, p);
  const folhas = [['.tecla[data-id="calendario"]', '#f-cal'], ['.tecla[data-id="whatsapp"]', '#f-whats'], ['.cartao.sessoes', '#f-sessoes']];
  for (const [tecla, sel] of folhas) {
    if (!(await p.locator(tecla).count())) { h.ok(false, `${tecla} existe na tela de teste`); continue }
    await p.click(tecla); await h.espera(p, s => document.querySelector(s).classList.contains('aberta'), sel); await h.dormir(500);
    const b = await p.locator(sel).boundingBox(), x = b.x + b.width / 2;
    // puxada curta e devagar: acompanha o dedo, solta e volta
    const c2 = await dedo(p, ctx, { x, y: b.y + 120 }, { x, y: b.y + 190 }, { espera: 30, soltar: false });
    const durante = await p.evaluate(s => getComputedStyle(document.querySelector(s)).translate, sel);
    h.ok(durante !== 'none' && parseFloat(durante.split(' ')[1]) > 40, `${sel}: durante a puxada a tela acompanha o dedo (${durante})`);
    await c2.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); await h.dormir(700);
    h.ok(await aberta(p, sel) && await p.evaluate(s => getComputedStyle(document.querySelector(s)).translate === '0px' || getComputedStyle(document.querySelector(s)).translate === 'none', sel), `${sel}: soltar cedo devolve a tela ao lugar`);
    // puxada longa fecha
    await dedo(p, ctx, { x, y: b.y + 60 }, { x, y: b.y + b.height * .7 }, { espera: 30 }); await h.dormir(800);
    h.ok(!(await aberta(p, sel)), `${sel}: puxar para baixo até longe fecha`);
    h.ok(await p.evaluate(() => document.querySelector('#f-cal, #f-whats, #f-sessoes') && !document.querySelector('#tela').classList.contains('com-folha')), `${sel}: o véu também sai`);
  }
  // o relógio
  await p.click('.relogio'); await h.dormir(600);
  h.ok(await aberta(p, '#f-relogio'), 'o relógio abre');
  const rb = await p.locator('#f-relogio').boundingBox();
  await dedo(p, ctx, { x: rb.x + rb.width / 2, y: rb.y + 80 }, { x: rb.x + rb.width / 2, y: rb.y + rb.height * .7 }, { espera: 30 }); await h.dormir(900);
  h.ok(!(await aberta(p, '#f-relogio')), 'o relógio fecha puxando para baixo');
  // lista rolada não é roubada: com a rolagem no meio, puxar rola a lista e não fecha
  await h.cenario({ whatsapp: 'muitas' }); await p.reload(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length > 8); await h.dormir(500);
  await p.evaluate(() => { document.querySelector('#wa-lista').scrollTop = 200 });
  const wb = await p.locator('#wa-lista').boundingBox();
  await dedo(p, ctx, { x: wb.x + wb.width / 2, y: wb.y + 40 }, { x: wb.x + wb.width / 2, y: wb.y + wb.height * .8 }, { espera: 30 }); await h.dormir(600);
  h.ok(await aberta(p, '#f-whats'), 'lista rolada: o gesto é da lista e a tela não fecha');
  await ctx.close();
}
