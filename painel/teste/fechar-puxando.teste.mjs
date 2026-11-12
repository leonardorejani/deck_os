// Frente agenda-fechar-uso (12/11/2026): "fechar puxando de cima para baixo" em TODAS as telas abertas, com toque de dedo
// de verdade (CDP touchStart/Move/End). No iPhone a rolagem nativa começa nos primeiros pixels e, depois dela, o touchmove
// deixa de ser cancelável: por isso o painel cancela o gesto já nos primeiros movimentos para baixo.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-apagar], .tecla[data-id="apagar"]'));
const aberta = (p, sel) => p.evaluate(s => document.querySelector(s).classList.contains('aberta'), sel);
async function dedo(p, ctx, de, para, { passos = 12, soltar = true, espera = 20 } = {}) {
  const c = await ctx.newCDPSession(p);
  await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [de] });
  for (let i = 1; i <= passos; i++) { await c.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: de.x + (para.x - de.x) * i / passos, y: de.y + (para.y - de.y) * i / passos }] }); await p.waitForTimeout(espera) }
  if (soltar) await c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  return c;
}
const TELAS = [
  ['#f-player', 'abrirPlayer()'], ['#f-relogio', 'abrirRelogio()'], ['#f-cal', 'abrirCal()'], ['#f-whats', 'abrirWhats()'], ['#f-sessoes', 'abrirSessoes()'],
  ['#f-monitor', 'abrirMonitor()'], ['#f-mail', 'abrirMail()'], ['#f-controles', 'abrirControles()'], ['#f-editor', "abrirEditor('apagar')"],
];

export default async function (h) {
  /* agenda: deslizar a lista do dia para a esquerda revela o formulário, rolar na vertical não, soltar cedo volta */
  {
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0); await h.dormir(600);
    const b = await p.locator('#ca-lista').boundingBox(), y = b.y + b.height / 2, x = b.x + b.width * .8;
    const c1 = await dedo(p, ctx, { x, y }, { x: x - 60, y }, { passos: 12, espera: 30, soltar: false });
    const seguiu = await p.evaluate(() => parseFloat(getComputedStyle(document.querySelector('#ca-lista')).translate) || 0);
    h.ok(seguiu < -30, `agenda: a lista acompanha o dedo para a esquerda (${seguiu}px)`);
    await c1.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); await h.dormir(600);
    h.ok(await p.evaluate(() => document.querySelector('#ca-form').hidden), 'agenda: soltar cedo volta a lista e não abre o formulário');
    await dedo(p, ctx, { x, y: y + 60 }, { x, y: y - 60 }, { espera: 30 }); await h.dormir(500);
    h.ok(await p.evaluate(() => document.querySelector('#ca-form').hidden), 'agenda: rolar na vertical não abre o formulário');
    await dedo(p, ctx, { x, y }, { x: x - b.width * .6, y }, { espera: 30 }); await h.dormir(800);
    h.ok(await p.evaluate(() => !document.querySelector('#ca-form').hidden && document.querySelector('#ca-lista').hidden), 'agenda: deslizar para a esquerda até longe abre o formulário');
    h.ok(await p.evaluate(() => !!document.querySelector('#nc-titulo') && !document.querySelector('#ca-lista .btn-novo')), 'agenda: sem botão grande por cima da lista');
    await ctx.close();
  }

  const ctx = await h.novoContexto({ hasTouch: true });
  const p = await h.pagina({ ctx }); await pronta(h, p);
  // registra, no documento (depois da tela), se cada touchmove chegou cancelado
  await p.evaluate(() => { window.__mov = []; document.addEventListener('touchstart', e => { window.__ini = e.touches[0].clientY }, { passive: true }); document.addEventListener('touchmove', e => window.__mov.push({ cancelavel: e.cancelable, cancelado: e.defaultPrevented, y: e.touches[0].clientY }), { passive: true }) });
  for (const [sel, abrir] of TELAS) {
    await p.evaluate(a => { eval(a) }, abrir); await h.dormir(700);
    if (!(await aberta(p, sel))) { h.ok(false, `${sel}: abre pelo teste`); continue }
    const b = await p.locator(sel).boundingBox(), x = b.x + b.width / 2, y0 = b.y + Math.min(90, b.height / 4);
    // movimento pequeno e vertical já nasce cancelado (no iOS o primeiro movimento é o último que dá para cancelar)
    const cedo = await p.evaluate(sel => {
      const alvo = document.querySelector(sel).querySelector('header, h2, .fechar, .corpo, *') || document.querySelector(sel);
      const r = alvo.getBoundingClientRect(), x = r.x + r.width / 2, y = r.y + r.height / 2;
      const toque = (yy) => new Touch({ identifier: 7, target: alvo, clientX: x, clientY: yy });
      const ev = (tipo, yy) => new TouchEvent(tipo, { bubbles: true, cancelable: true, touches: tipo === 'touchend' ? [] : [toque(yy)], targetTouches: [], changedTouches: [toque(yy)] });
      alvo.dispatchEvent(ev('touchstart', y)); const m = ev('touchmove', y + 4); alvo.dispatchEvent(m);
      const r1 = m.defaultPrevented; alvo.dispatchEvent(ev('touchend', y + 4)); return r1;
    }, sel);
    await h.dormir(500);
    h.ok(cedo, `${sel}: um movimento de 4 px para baixo já é cancelado`);
    // 1. puxada curta e devagar: acompanha o dedo e, ao soltar, volta
    await p.evaluate(() => { window.__mov = [] });
    const c2 = await dedo(p, ctx, { x, y: y0 }, { x, y: y0 + 80 }, { passos: 20, espera: 34, soltar: false });
    const dur = await p.evaluate(s => getComputedStyle(document.querySelector(s)).translate, sel);
    h.ok(dur !== 'none' && parseFloat(dur.split(' ')[1]) > 40, `${sel}: durante a puxada a tela acompanha o dedo (${dur})`);
    const mov = await p.evaluate(() => window.__mov.map(m => ({ ...m, dy: m.y - window.__ini }))), descendo = mov.filter(m => m.dy >= 3);
    h.ok(descendo.length > 2 && descendo.slice(0, 3).every(m => m.cancelado), `${sel}: os primeiros movimentos para baixo já chegam cancelados (a 3 px, antes de o iOS começar a rolar: ${JSON.stringify(descendo.slice(0, 3).map(m => m.cancelado))})`);
    await c2.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); await h.dormir(700);
    const volta = await p.evaluate(s => { const t = getComputedStyle(document.querySelector(s)).translate; return t === 'none' || t === '0px' }, sel);
    h.ok(await aberta(p, sel) && volta, `${sel}: soltar cedo devolve a tela ao lugar`);
    // 2. puxada longa fecha
    await dedo(p, ctx, { x, y: y0 }, { x, y: b.y + b.height * .75 }); await h.dormir(900);
    h.ok(!(await aberta(p, sel)), `${sel}: puxar para baixo até longe fecha`);
    await h.dormir(300);
  }
  await ctx.close();
}
