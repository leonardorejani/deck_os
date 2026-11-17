// Consumo e toque do painel (16/11/2026): a config só é relida quando o Mac muda, a página escondida não pede estado,
// o alvo de toque chega a 44 pt já escalado, o relógio não refaz a data à toa e o mês da C não vira vazio com o Mac fora.
export default async function (h) {
  /* 1. config: o estado traz o carimbo e o painel só baixa a config de novo quando ele muda */
  await h.reset();
  let p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"]'));
  await h.dormir(1500);
  const base = (await h.contadores()).configs; // a abertura pode pedir a config mais de uma vez: isso não é o que se mede aqui
  await h.dormir(8000);
  let c = await h.contadores();
  h.ok(c.configs === base, `config parada: ${c.configs - base} GET /api/config em 8 s depois da abertura`);
  await h.cenario({ nomeApagar: 'Tela apagada' });
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="apagar"]')?.textContent.includes('Tela apagada'), null, 4000), 'tecla editada no Mac aparece em poucos segundos');
  c = await h.contadores();
  h.ok(c.configs - base === 1, `e custou uma releitura só (${c.configs - base})`);
  await p.context().close();

  /* Mac antigo, sem carimbo: relê bem mais raro que a cada 5 s */
  await h.reset(); await h.cenario({ semCarimbo: true });
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"]'));
  await h.dormir(1500);
  const base2 = (await h.contadores()).configs;
  await h.dormir(8000);
  c = await h.contadores();
  h.ok(c.configs === base2, `Mac sem carimbo: ${c.configs - base2} GET /api/config em 8 s depois da abertura`);
  await p.context().close();

  /* 2. página escondida: o laço de 1 s espera, e a volta à tela acorda na hora */
  await h.reset();
  p = await h.pagina({ antes: () => { window.__oculta = false; Object.defineProperty(document, 'hidden', { get: () => window.__oculta }) } });
  await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"]'));
  await p.evaluate(() => { window.__oculta = true; document.dispatchEvent(new Event('visibilitychange')) });
  await h.dormir(300);
  const n0 = (await h.contadores()).estado;
  await h.dormir(5000);
  const n1 = (await h.contadores()).estado;
  h.ok(n1 - n0 <= 1, `escondida: ${n1 - n0} pedidos de estado em 5 s (antes eram uns 5)`);
  await p.evaluate(() => { window.__oculta = false; document.dispatchEvent(new Event('visibilitychange')) });
  await h.dormir(1500);
  h.ok((await h.contadores()).estado - n1 >= 1, 'ao voltar à tela o estado é pedido de novo na hora');
  await p.context().close();

  /* 3. alvo de toque: no iPhone deitado (844x390) 36 px de desenho viram 32, e o toque cresce por fora até 44 */
  await h.reset();
  p = await h.pagina({ w: 844, h: 390 });
  await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"]'));
  await p.evaluate(() => document.querySelector('#f-whats').classList.add('aberta'));
  await h.dormir(900);
  for (const [sel, nome] of [['#f-whats .fechar', 'fechar'], ['#wa-filtro button[data-f="contatos"]', 'aba do WhatsApp']]) {
    const r = await p.evaluate(s => {
      const el = document.querySelector(s), b = el.getBoundingClientRect(), esc = parseFloat(document.querySelector('#moldura').style.getPropertyValue('--escala'));
      const topo = document.elementFromPoint(b.x + b.width / 2, b.y - 4.5), base = document.elementFromPoint(b.x + b.width / 2, b.y + b.height + 4.5);
      return { esc, h: b.height, topo: topo === el || el.contains(topo), base: base === el || el.contains(base) };
    }, sel);
    h.ok(r.topo && r.base, `${nome}: o toque alcança 4,5 px acima e abaixo do desenho (escala ${r.esc.toFixed(2)}, desenho de ${r.h.toFixed(1)} px)`);
    h.ok(Math.abs(r.h - 36 * r.esc) < 1, `${nome}: o desenho continua com 36 px de projeto (${r.h.toFixed(1)} na tela)`);
  }
  await p.context().close();

  /* 4. relógio: a data não é reescrita a cada segundo */
  await h.reset();
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.data'));
  await h.dormir(1500);
  const muda = await p.evaluate(() => new Promise(ok => {
    let n = 0; const o = new MutationObserver(ms => { n += ms.filter(m => m.target.classList?.contains('data')).length });
    o.observe(document.body, { childList: true, subtree: true });
    setTimeout(() => { o.disconnect(); ok({ n, datas: document.querySelectorAll('.data').length, txt: document.querySelector('.data').textContent }) }, 3500);
  }));
  h.ok(muda.datas > 0 && muda.n === 0 && muda.txt.length > 5, `a data (${muda.txt}) não foi reescrita em 3,5 s (${muda.n} mudanças)`);
  await p.context().close();

  /* 5. mês da C: pedido que falha por rede não vira mês vazio, e o Mac fora não gera pedido de agenda */
  await h.reset(); await h.cenario({ comp: 'c' });
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-c .mes-c'));
  await h.dormir(800);
  await p.route('**/api/agenda*', r => r.abort());
  await p.click('.comp-c [data-mes-c="1"]'); await h.dormir(900);
  h.ok(await p.evaluate(() => mesC.ev === null), 'rede fora: o mês não grava lista vazia (continua sem leitura)');
  await p.unroute('**/api/agenda*');
  h.ok(await h.espera(p, () => Array.isArray(mesC.ev), null, 7500), 'com a rede de volta o mês relê no próximo tique, sem esperar 30 s');
  await p.context().close();

  await h.reset(); await h.cenario({ comp: 'c', pendurar: false });
  p = await h.pagina({ ajustes: { tempoLimite: 600, msParaOffline: 1500 } });
  await h.espera(p, () => !!document.querySelector('.comp-c .mes-c'));
  await h.dormir(800);
  await h.cenario({ pendurar: true });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 6000), 'Mac fora: a tela marca desconectado');
  let pedidos = 0; p.on('request', r => { if (r.url().includes('/api/agenda')) pedidos++ });
  await p.evaluate(() => { mesC.lido = 0 }); // como se já tivessem passado os 30 s
  await h.dormir(6500);
  h.ok(pedidos === 0, `Mac fora: ${pedidos} pedidos de agenda do mês da C em 6,5 s`);
  await p.context().close();

  /* Correções da verificação (16/11/2026): falha não vira rajada */
  // a) config que falha com o carimbo mudado: não repete a cada laço de 1 s
  await h.reset();
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"]'));
  await h.dormir(1500);
  await h.cenario({ config500: true, nomeApagar: 'Mudou' });
  await h.dormir(1500);
  const b3 = (await h.contadores()).configs;
  await h.dormir(8000);
  c = await h.contadores();
  h.ok(c.configs - b3 <= 1, `config falhando: ${c.configs - b3} GET /api/config em 8 s (era um por segundo)`);
  await h.cenario({ config500: false });
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="apagar"]')?.textContent.includes('Mudou'), null, 20000), 'passada a espera, a config volta e a tecla aparece');
  await p.context().close();

  // b) agenda do mês da C pendurada até o tempo limite: espaçada, não a cada tique de 5 s
  await h.reset(); await h.cenario({ comp: 'c' });
  p = await h.pagina({ ajustes: { tempoLimite: 1000 } });
  await h.espera(p, () => !!document.querySelector('.comp-c .mes-c'));
  await h.dormir(800);
  await p.route('**/api/agenda*', async r => { await h.dormir(2500); r.abort().catch(() => {}) });
  await p.click('.comp-c [data-mes-c="1"]');
  let n4 = 0; p.on('request', r => { if (r.url().includes('/api/agenda')) n4++ });
  await h.dormir(16000);
  h.ok(n4 <= 1, `agenda pendurada: ${n4} pedidos em 16 s (antes um a cada tique de 5 s)`);
  await p.context().close();
}
