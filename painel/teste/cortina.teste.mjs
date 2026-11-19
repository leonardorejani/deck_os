// Cortina de controles rápidos (SPEC 13, item 8): deslizar para baixo a partir do topo da tela principal abre uma cortina com volume, mudo,
// brilho e mídia. Acompanha o dedo, pode ser agarrada no meio da animação e fecha deslizando para cima ou tocando fora. Dedo de verdade
// (CDP touchStart/Move/End), sempre headless. Fotos em .teste/refinos/cortina-*.png do repo principal.
import fs from 'node:fs';
import path from 'node:path';

const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const visivel = p => p.evaluate(() => document.querySelector('#cortina').classList.contains('visivel'));
const yPainel = p => p.evaluate(() => parseFloat(getComputedStyle(document.querySelector('#cx-painel')).translate.split(' ')[1]) || 0);
const altPainel = p => p.evaluate(() => document.querySelector('#cx-painel').offsetHeight);
const caixaTela = p => p.evaluate(() => { const r = document.querySelector('#tela').getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height, k: r.width / document.querySelector('#tela').offsetWidth } });
async function dedo(p, ctx, de, para, { passos = 12, soltar = true, espera = 16, cdp } = {}) {
  const c = cdp || await ctx.newCDPSession(p);
  await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [de] });
  for (let i = 1; i <= passos; i++) { await c.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: de.x + (para.x - de.x) * i / passos, y: de.y + (para.y - de.y) * i / passos }] }); await new Promise(r => setTimeout(r, espera)) }
  if (soltar) await c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  return c;
}
const fim = c => c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
const cartoes = p => p.evaluate(() => [...document.querySelectorAll('#cx-corpo .ctl-cartao[data-ctl]')].map(c => c.dataset.ctl).join('|'));

export default async function (h) {
  const fotos = path.join(path.resolve(new URL('.', import.meta.url).pathname, '../..').split('/.claude/worktrees/')[0], '.teste', 'refinos');
  fs.mkdirSync(fotos, { recursive: true });
  const foto = (p, n) => p.screenshot({ path: path.join(fotos, `cortina-${n}.png`) });

  for (const [w, alt, rot] of [[932, 430, 'deitado'], [430, 932, 'em-pe'], [1440, 900, 'janela']]) {
    await h.reset();
    const ctx = await h.novoContexto({ hasTouch: true, viewport: { width: w, height: alt } });
    const p = await h.pagina({ ctx, w, h: alt }); await pronta(h, p);
    const T = await caixaTela(p), x = T.x + T.w * .5, topo = rot === 'em-pe' ? 59 + 30 : 24 + 30; // dentro da faixa, abaixo da borda do sistema (em pé, abaixo do recorte)
    const R = `${rot} ${w}x${alt}`;
    h.ok(!(await visivel(p)), `${R}: a cortina começa fechada e fora do alcance (inert)`);
    h.ok(await p.evaluate(() => document.querySelector('#cortina').hasAttribute('inert')), `${R}: fechada, a cortina é inert`);

    // acompanha o dedo: no meio do gesto o painel já desceu e a posição é proporcional ao arrasto
    const c1 = await dedo(p, ctx, { x, y: T.y + topo * T.k }, { x, y: T.y + (topo + 40) * T.k }, { soltar: false });
    const meio = await yPainel(p), alt1 = await altPainel(p);
    h.ok(await visivel(p) && meio > -alt1 + 20 && meio < -alt1 + 70, `${R}: a cortina acompanha o dedo (${Math.round(meio)} de ${-alt1})`);
    await fim(c1); await h.dormir(500);
    h.ok(!(await visivel(p)), `${R}: soltar cedo volta e fecha`);

    // abre de verdade
    const c2 = await dedo(p, ctx, { x, y: T.y + topo * T.k }, { x, y: T.y + (topo + 150) * T.k }); await h.dormir(500);
    h.ok(await visivel(p) && Math.abs(await yPainel(p)) < 1, `${R}: deslizar para baixo abre a cortina`);
    h.ok(await p.evaluate(() => !document.querySelector('#cortina').hasAttribute('inert')), `${R}: aberta, não é inert`);
    await h.espera(p, () => document.querySelectorAll('#cx-corpo .ctl-cartao[data-ctl]').length >= 2);
    h.ok(await cartoes(p) === 'volume|brilho', `${R}: volume e brilho (sem luz do teclado): ${await cartoes(p)}`);
    h.ok(await p.evaluate(() => !!document.querySelector('#cx-corpo [data-mudo]')), `${R}: mudo na cortina`);
    h.ok(await p.evaluate(() => ['anterior', 'tocar', 'proxima'].every(a => !!document.querySelector(`#cx-midia [data-midia="${a}"]`))), `${R}: mídia com anterior, tocar e próxima`);
    const caixas = await p.evaluate(() => [...document.querySelectorAll('#cx-painel .ctl-cartao, #cx-painel .midia button')].map(e => { const r = e.getBoundingClientRect(); return [r.left, r.right, r.top, r.bottom, r.width, r.height] }));
    h.ok(caixas.every(([l, r, t, b]) => l >= 0 && r <= w && t >= 0 && b <= alt), `${R}: nada estoura a tela`);
    h.ok(caixas.every(([, , , , lw, lh]) => lw >= 44 && lh >= 44), `${R}: áreas de toque de 44px ou mais`);
    await foto(p, rot);

    // fecha deslizando para cima na alça
    const A = await p.evaluate(() => { const r = document.querySelector('.cx-alca').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 } });
    await dedo(p, ctx, { x: A.x, y: A.y }, { x: A.x, y: A.y - 220 * T.k }); await h.dormir(500);
    h.ok(!(await visivel(p)), `${R}: deslizar para cima fecha`);

    // abre de novo e fecha tocando fora (no fundo, abaixo do painel)
    await dedo(p, ctx, { x, y: T.y + topo * T.k }, { x, y: T.y + (topo + 150) * T.k }); await h.dormir(500);
    const fora = await p.evaluate(() => { const r = document.querySelector('#cx-painel').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.bottom + 20 } });
    await p.touchscreen.tap(fora.x, fora.y); await h.dormir(500);
    h.ok(!(await visivel(p)), `${R}: tocar fora fecha`);
    await ctx.close();
  }

  /* o que não pode abrir a cortina */
  {
    await h.reset();
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    const T = await caixaTela(p), x = T.x + T.w * .5;
    await dedo(p, ctx, { x, y: T.y + 6 }, { x, y: T.y + 200 }); await h.dormir(400);
    h.ok(!(await visivel(p)), 'começar na borda do sistema (acima de 24px) não abre');
    await dedo(p, ctx, { x, y: T.y + 220 }, { x, y: T.y + 400 }); await h.dormir(400);
    h.ok(!(await visivel(p)), 'começar longe do topo não abre');
    await dedo(p, ctx, { x, y: T.y + 60 }, { x: x + 120, y: T.y + 80 }); await h.dormir(400);
    h.ok(!(await visivel(p)), 'deslizar para o lado não abre');
    await dedo(p, ctx, { x, y: T.y + 90 }, { x, y: T.y + 50 }); await h.dormir(400);
    h.ok(!(await visivel(p)), 'deslizar para cima não abre');
    // área que rola: um bloco rolável na faixa do topo entrega o gesto a ele
    await p.evaluate(() => { const d = document.createElement('div'); d.id = 'rola'; d.style.cssText = 'position:absolute;left:300px;top:40px;width:200px;height:60px;overflow:auto;z-index:5;background:#333'; d.innerHTML = '<div style="height:400px">rola</div>'; document.querySelector('#tela').appendChild(d) });
    const r = await p.locator('#rola').boundingBox();
    await dedo(p, ctx, { x: r.x + 100, y: r.y + 10 }, { x: r.x + 100, y: r.y + 150 }); await h.dormir(400);
    h.ok(!(await visivel(p)), 'área que rola não abre a cortina');
    // barra do volume do player: arrasta o volume, não abre
    await p.evaluate(() => document.querySelector('#rola').remove());
    // o clique gerado pelo gesto não aperta o que estava embaixo (o relógio abriria em tela cheia)
    const relogio = await p.evaluate(() => { const r = document.querySelector('.relogio, .data-linha')?.getBoundingClientRect(); return r && { x: r.left + r.width / 2, y: r.top + r.height / 2 } });
    if (relogio) {
      const dentro = (relogio.y - T.y) / T.k;
      if (dentro > 24 && dentro < 24 + 110) {
        await dedo(p, ctx, { x: relogio.x, y: relogio.y }, { x: relogio.x, y: relogio.y + 150 * T.k }); await h.dormir(500);
        h.ok(await visivel(p) && !(await p.evaluate(() => document.querySelector('#f-relogio').classList.contains('aberta'))), 'o clique do gesto não abre o relógio embaixo do dedo');
      }
    }
    await ctx.close();
  }

  /* folha aberta: o fechar puxando para baixo é da folha, a cortina não abre. E a folha ainda fecha */
  {
    await h.reset(); await h.cenario({ comControles: true });
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.evaluate(() => abrirControles()); await h.dormir(700);
    const T = await caixaTela(p), x = T.x + T.w * .5;
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 330 }, { passos: 14, espera: 30 }); await h.dormir(700);
    h.ok(!(await visivel(p)), 'folha aberta: puxar para baixo não abre a cortina');
    h.ok(await p.evaluate(() => !document.querySelector('#f-controles').classList.contains('aberta')), 'folha aberta: puxar para baixo ainda fecha a folha');
    // fechada a folha, a cortina abre normalmente
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 200 }); await h.dormir(500);
    h.ok(await visivel(p), 'folha fechada: a cortina abre');
    await ctx.close();
  }

  /* interromper: agarrar no meio da animação para o painel onde está, e o dedo passa a mandar */
  {
    await h.reset();
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.evaluate(() => document.documentElement.style.setProperty('--mov-padrao', '1600ms')); // animação lenta: dá tempo de agarrar no meio
    const T = await caixaTela(p), x = T.x + T.w * .5;
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 200 }, { passos: 8, espera: 5 }); // solta rápido: a cortina começa a abrir
    await h.dormir(70);
    const c = await ctx.newCDPSession(p);
    const ao = await p.evaluate(() => document.querySelector('#cx-painel').getBoundingClientRect().bottom);
    const ya = await yPainel(p), alt1 = await altPainel(p);
    h.ok(ya < -2 && ya > -alt1 + 2, `interromper: a cortina está no meio da animação (${Math.round(ya)})`);
    await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: T.y + alt1 - 5 }] });
    const y1 = await yPainel(p); await h.dormir(200); const y2 = await yPainel(p);
    h.ok(Math.abs(y2 - y1) < 1.5, `interromper: tocar congela a cortina onde estava (${Math.round(y1)} e ${Math.round(y2)})`);
    for (let i = 1; i <= 10; i++) { await c.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: T.y + alt1 - 5 - i * 12 }] }); await h.dormir(16) }
    const y3 = await yPainel(p); h.ok(y3 < y2 - 60, `interromper: o dedo manda e a cortina sobe junto (${Math.round(y2)} para ${Math.round(y3)})`);
    await fim(c); await h.dormir(500);
    h.ok(!(await visivel(p)), 'interromper: soltar para cima termina de fechar');
    // tocar no meio da animação sem arrastar: segue para onde ia
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 200 }, { passos: 8, espera: 5 }); await h.dormir(60);
    const alt2 = await altPainel(p);
    await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: T.y + alt2 - 5 }] }); await h.dormir(50); await fim(c); await h.dormir(2000);
    h.ok(await visivel(p) && Math.abs(await yPainel(p)) < 1, 'interromper: tocar sem arrastar deixa a cortina terminar de abrir');
    await ctx.close();
  }

  /* os controles funcionam de dentro da cortina */
  {
    await h.reset();
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    const T = await caixaTela(p), x = T.x + T.w * .5;
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 200 }); await h.dormir(500);
    await h.espera(p, () => document.querySelectorAll('#cx-corpo .ctl-cartao[data-ctl]').length >= 2);
    const v = await p.evaluate(() => { const r = document.querySelector('#cx-corpo [data-ctl="volume"]').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, h: r.height } });
    await dedo(p, ctx, { x: v.x, y: v.y }, { x: v.x, y: v.y - v.h * .3 }, { passos: 8, espera: 30 }); await h.dormir(700);
    h.ok(await visivel(p), 'arrastar um cartão do volume não fecha a cortina');
    const gravados = (await h.contadores()).controles.filter(s => s.startsWith('volume='));
    h.ok(gravados.length > 0 && Number(gravados.at(-1).split('=')[1]) >= 55, `o volume sobe pelo cartão da cortina (${gravados.join(',')})`);
    await p.locator('#cx-corpo [data-mudo]').tap(); await h.dormir(500);
    h.ok((await h.contadores()).controles.includes('mudo=1'), 'o mudo alterna pela cortina');
    h.ok(await p.evaluate(() => document.querySelector('#cx-corpo [data-mudo]').getAttribute('aria-pressed') === 'true'), 'o mudo acende na cortina');
    await p.locator('#cx-midia [data-midia="proxima"]').tap(); await h.dormir(400);
    h.ok((await h.contadores()).spotify.some(a => String(a).includes('proxima')), 'a próxima faixa vai pelo Mac');
    await p.locator('#cx-midia [data-midia="tocar"]').tap(); await h.dormir(400);
    h.ok((await h.contadores()).spotify.some(a => String(a).includes('pausar')), 'tocar ou pausar vai pelo Mac (estava tocando: pausa)');
    h.ok(await visivel(p), 'usar os controles não fecha a cortina');
    await p.keyboard.press('Escape'); await h.dormir(500);
    h.ok(!(await visivel(p)), 'Escape fecha a cortina');
    await ctx.close();
  }

  /* sem Spotify a mídia some, e o Mac sem brilho só oferece o volume */
  {
    await h.reset(); await h.cenario({ spotify: 'fechado', controles: 'sem-brilho' });
    const ctx = await h.novoContexto({ hasTouch: true });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    const T = await caixaTela(p), x = T.x + T.w * .5;
    await dedo(p, ctx, { x, y: T.y + 60 }, { x, y: T.y + 200 }); await h.dormir(500);
    await h.espera(p, () => document.querySelectorAll('#cx-corpo .ctl-cartao[data-ctl]').length >= 1);
    h.ok(await p.evaluate(() => document.querySelector('#cx-midia').hidden), 'sem Spotify a mídia não aparece');
    h.ok(await cartoes(p) === 'volume', `sem brilho no Mac só o volume: ${await cartoes(p)}`);
    await ctx.close();
  }
}
