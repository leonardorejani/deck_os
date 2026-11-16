// Primeira abertura: as teclas de verdade pintam assim que a config chega (ela não depende do estado, que no Mac
// espera a leitura do Spotify), e o esqueleto nunca pisca: aparece e fica o bastante, ou nem aparece.
const marcador = () => {
  window.__t = {};
  const c = () => document.querySelector('#conteudo');
  new MutationObserver(() => {
    const e = c(), n = performance.now(); if (!e) return;
    const esq = e.classList.contains('carregando');
    if (esq && __t.esq == null) __t.esq = n;
    const tec = [...e.querySelectorAll('.tecla:not(.menu) .nome')].some(x => x.textContent.trim());
    if (esq && tec && e.classList.contains('parcial') && __t.parcial == null) __t.parcial = n; // teclas reais ainda dentro do esqueleto
    if (!esq && e.querySelector('.tecla') && __t.teclas == null) __t.teclas = n;
  }).observe(document, { subtree: true, childList: true, attributes: true });
};

export default async function (h) {
  // Estado lento (o Mac espera o Spotify, 1 s): as teclas reais já estão na tela em ~100 ms, sem esperar por ele
  await h.cenario({ atraso: 1000, atrasoConfig: 0 });
  let p = await h.pagina({ antes: marcador });
  h.ok(await h.espera(p, () => window.__t?.parcial != null, null, 3000), 'com o estado lento, as teclas reais aparecem antes dele');
  let t = await p.evaluate(() => window.__t);
  console.log(`      teclas reais em ${Math.round(t.parcial)} ms (estado em 1000)`);
  h.ok(t.parcial < 400, `teclas reais em ${Math.round(t.parcial)} ms, sem esperar o estado de 1000 ms`);
  h.ok(await p.evaluate(() => document.querySelectorAll('#conteudo.parcial .sessao').length > 0), 'o resto segue em esqueleto até o estado chegar');
  h.ok(await h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.comp-a .faixa'), null, 4000), 'o estado chega e a tela fica real');
  await p.context().close();

  // Config lenta e estado rápido: as duas pedidas juntas (em série seriam 500 ms)
  await h.cenario({ atraso: 250, atrasoConfig: 250 });
  p = await h.pagina({ antes: marcador });
  h.ok(await h.espera(p, () => window.__t?.teclas != null, null, 4000), 'as teclas aparecem');
  t = await p.evaluate(() => window.__t);
  h.ok(t.teclas < 420, `estado e config pedidos juntos: teclas em ${Math.round(t.teclas)} ms (série daria 500 ou mais)`);
  await p.context().close();

  // O defeito achado na verificação: estado que chega logo depois do esqueleto piscava a tela (8 a 83 ms)
  for (const atraso of [105, 150, 210, 230, 285]) {
    await h.cenario({ atraso, atrasoConfig: 0 });
    p = await h.pagina({ antes: marcador });
    await h.espera(p, () => window.__t?.teclas != null || !!document.querySelector('.comp-a .faixa'), null, 4000);
    await h.dormir(400);
    t = await p.evaluate(() => window.__t);
    const ficou = t.esq == null ? 0 : (t.teclas ?? 0) - t.esq;
    h.ok(t.esq == null || ficou >= 180, `estado em ${atraso} ms: o esqueleto ${t.esq == null ? 'nem aparece' : `fica ${Math.round(ficou)} ms`}, sem piscar`);
    await p.context().close();
  }
  await h.cenario({ atraso: 0, atrasoConfig: 0 });
}
