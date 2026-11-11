// Texto do Mac nunca vira HTML, a capa se recupera de uma falha e a config quebrada avisa.
export default async function (h) {
  /* XSS: texto do Mac, do WhatsApp e das sessões chega como HTML malicioso e nada executa */
  await h.reset(); await h.cenario({ xss: true });
  let p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.dormir(1500);
  let r = await p.evaluate(() => ({
    exec: window.__xss || 0,
    intrusas: document.querySelectorAll('img[src="x"], img[onerror]:not(.capa)').length,
    faixa: document.querySelector('.faixa')?.textContent || '',
    sessao: document.querySelector('.sessao b')?.textContent || '',
    mac: document.querySelector('#nome-mac')?.textContent || '',
    tecla: document.querySelector('.tecla .nome, .tecla')?.textContent || '',
  }));
  h.ok(r.exec === 0 && r.intrusas === 0, `HTML malicioso em todos os textos: nada executou (${r.exec}) e nenhum elemento intruso entrou (${r.intrusas})`);
  h.ok(r.faixa.includes('<img') && r.sessao.includes('<img') && r.mac.includes('<img') && r.tecla.includes('<img'), 'o texto do Mac aparece literal na tela, como texto');
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(800);
  await h.cenario({ comp: 'b' }); await h.dormir(1500);
  r = await p.evaluate(() => ({ exec: window.__xss || 0, intrusas: document.querySelectorAll('img[src="x"]').length }));
  h.ok(r.exec === 0 && r.intrusas === 0, 'o mesmo em pé e na composição B');
  await p.context().close();
  await h.reset();

  /* a capa que falhou uma vez é tentada de novo */
  let pedidos = 0;
  const navCtx = await h.novoContexto();
  await navCtx.route('**/api/capa**', rota => { pedidos++; return pedidos === 1 ? rota.fulfill({ status: 503, body: 'x' }) : rota.continue() });
  p = await h.pagina({ ctx: navCtx });
  await h.dormir(5000);
  const src = await p.evaluate(() => document.querySelector('.player .capa')?.getAttribute('src'));
  h.ok(pedidos >= 2 && !!src, `a capa que falhou uma vez volta sozinha (${pedidos} pedidos, src ${src ? 'presente' : 'vazio'})`);
  await navCtx.close();

  /* config que falha com erro do Mac: aviso na tela e o painel se recupera quando volta */
  await h.reset(); await h.cenario({ config500: true });
  p = await h.pagina();
  await h.dormir(3000);
  const aviso = await p.evaluate(() => { const a = document.querySelector('#aviso'); return a.classList.contains('visivel') && a.classList.contains('erro') ? document.querySelector('#aviso-txt').textContent : '' });
  h.ok(!!aviso, `config quebrada: a tela avisa em vez de ficar em silêncio ("${aviso}")`);
  await h.foto(p, 'config-quebrada');
  await h.cenario({ config500: false });
  h.ok(await h.espera(p, () => document.querySelectorAll('.tecla').length > 1, null, 4000), 'a config volta e as teclas do perfil aparecem');
  await p.context().close();
  await h.reset();
}
