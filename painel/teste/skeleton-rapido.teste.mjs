// Primeira abertura: as teclas pintam assim que o estado e a config chegam, sem esperar o esqueleto nem uma
// busca atrás da outra. Mede o tempo até a primeira tecla de verdade (fora do esqueleto) aparecer.
const marcador = () => {
  window.__t = {};
  const c = () => document.querySelector('#conteudo');
  new MutationObserver(() => {
    const e = c(), n = performance.now(); if (!e) return;
    const esq = e.classList.contains('carregando');
    if (esq && __t.esq == null) __t.esq = n;
    if (!esq && e.querySelector('.tecla') && __t.teclas == null) __t.teclas = n;
  }).observe(document, { subtree: true, childList: true, attributes: true });
};

export default async function (h) {
  // Mac de mentira com estado e config de 250 ms cada: em série seriam 500 ms, em paralelo 250 ms
  await h.cenario({ atraso: 250, atrasoConfig: 250 });
  let p = await h.pagina({ antes: marcador });
  h.ok(await h.espera(p, () => window.__t?.teclas != null, null, 4000), 'as teclas aparecem');
  let t = await p.evaluate(() => window.__t);
  console.log(`      teclas em ${Math.round(t.teclas)} ms (estado 250 + config 250)`);
  h.ok(t.teclas < 420, `estado e config pedidos juntos: teclas em ${Math.round(t.teclas)} ms (série daria 500 ou mais)`);
  await p.context().close();

  // O esqueleto some na hora em que o dado chega: nada de segurar 400 ms
  await h.cenario({ atraso: 300, atrasoConfig: 0 });
  p = await h.pagina({ antes: marcador });
  await h.espera(p, () => window.__t?.teclas != null, null, 4000);
  t = await p.evaluate(() => window.__t);
  h.ok(t.esq != null && t.teclas - t.esq < 250, `esqueleto some quando o dado chega (ficou ${Math.round(t.teclas - t.esq)} ms, antes eram 400 no mínimo)`);
  h.ok(t.teclas < 420, `teclas em ${Math.round(t.teclas)} ms com estado de 300 ms`);
  await p.context().close();
  await h.cenario({ atraso: 0, atrasoConfig: 0 });
}
