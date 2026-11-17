// Cabeçalho do WhatsApp no app (pedido de 17/11/2026): só os filtros à esquerda e o X à direita. Sem título visível, sem subtítulo e
// sem "Abrir no Mac". Selo de número grande vira "999+". Três tamanhos de tela. Dados inventados.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const foto = (h, p, tam) => h.foto(p, `rodada5-whatsapp-cabecalho-${tam}`);

export default async function (h) {
  for (const [tam, w, al] of [['deitado', 932, 430], ['em-pe', 430, 932], ['janela', 1440, 900]]) {
    await h.cenario({ whatsappOrigem: 'qr', whatsappTudo: true, whatsappArqNaoLidas: 6838 });
    const p = await h.pagina({ ctx: await h.novoContexto({ viewport: { width: w, height: al } }) }); await pronta(h, p);
    await p.click('.tecla[data-id="whatsapp"]');
    h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length > 0), `${tam}: a folha abre`);
    await h.dormir(500);
    const r = await p.evaluate(() => {
      const cab = document.querySelector('#f-whats > header'), q = e => e.getBoundingClientRect(), vis = [...cab.children].filter(e => { const b = q(e); return b.width > 2 && b.height > 2 });
      const f = q(document.querySelector('#wa-filtro')), x = q(document.querySelector('#f-whats .fechar')), c = q(cab), tit = q(document.querySelector('#wa-titulo'));
      return { visiveis: vis.map(e => e.id || e.className).join(','), esq: f.left - c.left, dir: c.right - x.right, fim: f.right <= x.left, tit: tit.width, mac: !!document.querySelector('#wa-abrir') || [...cab.querySelectorAll('button')].some(b => /Abrir no Mac/.test(b.textContent)), larg: document.documentElement.scrollWidth <= innerWidth + 1, selo: document.querySelector('#wa-filtro [data-f=arquivadas] .selo-aba').textContent, cabe: f.right <= innerWidth && x.right <= innerWidth + 1 };
    });
    h.ok(r.visiveis === 'wa-filtro,fechar', `${tam}: o cabeçalho tem só o filtro e o X (${r.visiveis})`);
    h.ok(r.esq < 4 && r.dir < 4 && r.fim, `${tam}: filtro colado à esquerda e X colado à direita (${r.esq.toFixed(1)} / ${r.dir.toFixed(1)})`);
    h.ok(r.tit <= 2 && !r.mac, `${tam}: sem título visível e sem "Abrir no Mac" (${r.tit}px)`);
    h.ok(r.larg && r.cabe, `${tam}: nada passa da largura`);
    h.ok(r.selo === '999+', `${tam}: selo de 6838 vira "999+" (${r.selo})`);
    if (tam === 'em-pe') { // as 4 abas passam da largura em pé: tocar na última a traz inteira para a vista
      await p.click('#wa-filtro [data-f="arquivadas"]'); await h.dormir(700);
      h.ok(await p.evaluate(() => { const b = document.querySelector('#wa-filtro [data-f=arquivadas]').getBoundingClientRect(), f = document.querySelector('#wa-filtro').getBoundingClientRect(); return b.right <= f.right + 1 && b.left >= f.left - 1 }), 'em pé: a aba Arquivadas tocada fica inteira à vista');
    }
    await foto(h, p, tam);
    await p.context().close();
  }
  // 999 não vira 999+
  await h.cenario({ whatsappOrigem: 'qr', whatsappTudo: true, whatsappArqNaoLidas: 996 });
  const p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.dormir(500);
  h.ok(await p.evaluate(() => document.querySelector('#wa-filtro [data-f=arquivadas] .selo-aba').textContent) === '999', '999 continua 999');
  await p.context().close();
  // sem filtro (WhatsApp Web), o X fica sozinho à direita
  await h.cenario({ whatsappOrigem: 'web' });
  const w = await h.pagina(); await pronta(h, w);
  await w.click('.tecla[data-id="whatsapp"]'); await h.dormir(500);
  const d = await w.evaluate(() => { const c = document.querySelector('#f-whats > header').getBoundingClientRect(), x = document.querySelector('#f-whats .fechar').getBoundingClientRect(); return c.right - x.right });
  h.ok(d < 4, `WhatsApp Web: o X segue à direita (${d.toFixed(1)})`);
  await w.context().close();
}
