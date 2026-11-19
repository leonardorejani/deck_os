// Tocar numa faixa da fila muda tudo na hora, sem esperar o Mac (13/11/2026: "assim que clica ele já substitui a música, muda tudo ali
// no front e faz uma animação das músicas acima desaparecendo enquanto a nova toma lugar ali"). O Mac de mentira demora 1,5 s para
// responder: a troca tem de aparecer em menos de 100 ms, as faixas de cima saem animadas, e a resposta do Mac não faz nada piscar nem pular.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const NOVA = 'Próxima música 4';

async function abrirFila(h, p) {
  await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(500);
  await p.click('#f-player [data-fila]'); await h.dormir(900);
  await h.espera(p, () => document.querySelectorAll('#pc-lista-corpo [data-pular]').length === 9, null, 2000);
}
// marca o instante do toque e, a cada mudança na tela, anota quando a faixa nova apareceu no alto da fila, no player grande e no pequeno
const armar = p => p.evaluate(nova => {
  const t = window.__t = { t0: 0, topo: 0, grande: 0, pequeno: 0, capaVazia: 0, larguras: [] };
  document.addEventListener('click', ev => { if (ev.target.closest('[data-pular]') && !t.t0) t.t0 = performance.now() }, true);
  const ver = () => {
    const agora = performance.now(); if (!t.t0) return;
    if (!t.topo && document.querySelector('#pc-lista-topo b')?.textContent === nova) t.topo = agora - t.t0;
    if (!t.grande && document.querySelector('#f-player .pc .faixa')?.textContent === nova) t.grande = agora - t.t0;
    if (!t.pequeno && document.querySelector('.player .faixa')?.textContent === nova) t.pequeno = agora - t.t0;
    const g = document.querySelector('#f-player .capa-grande'); if (t.grande && g && !g.getAttribute('src')) t.capaVazia++;
    const c = document.querySelector('#pc-lista-corpo'), l = document.querySelector('#pc-lista'), f = document.querySelector('#f-player'), r = document.scrollingElement;
    t.larguras.push([c.scrollWidth - c.clientWidth, l.scrollWidth - l.clientWidth, f.scrollWidth - f.clientWidth, r.scrollWidth - r.clientWidth]);
  };
  new MutationObserver(ver).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true });
  (function laco() { ver(); requestAnimationFrame(laco) })();
}, NOVA);

export default async function (h) {
  for (const [w, alt, nome] of [[932, 430, 'celular deitado'], [430, 932, 'celular em pé'], [2000, 967, 'janela larga do Chrome']]) {
    // 1. o Mac demora: a tela já mudou
    await h.reset(); await h.cenario({ atrasoAcao: 1500, spotify: 'tocando', spotifyExtras: 'login', filaContexto: 'Daily Mix 3' });
    let p = await h.pagina({ w, h: alt }); await abrirFila(h, p); await armar(p);
    await p.click('#pc-lista-corpo [data-pular="3"]');
    await h.dormir(80);
    const meio = await p.evaluate(() => ({
      fantasmas: document.querySelectorAll('.fila-saida > *').length,
      linhas: [...document.querySelectorAll('#pc-lista-corpo [data-pular]')].map(b => b.querySelector('b').textContent),
      animando: [...document.querySelectorAll('#pc-lista-corpo [data-pular]')].filter(b => b.getAnimations().length).length,
      capaGrande: document.querySelector('#f-player .capa-grande').getAttribute('src') || '',
      capaTopo: document.querySelector('#pc-lista-topo .capa-mini').getAttribute('src') || '',
      verde: getComputedStyle(document.querySelector('#pc-lista-topo b')).color,
    }));
    const t = await p.evaluate(() => window.__t);
    h.ok(t.topo > 0 && t.topo < 100, `${nome}: "Tocando agora" troca em ${Math.round(t.topo)} ms, antes de o Mac responder (menos de 100)`);
    h.ok(t.grande > 0 && t.grande < 100, `${nome}: o player cheio troca em ${Math.round(t.grande)} ms (menos de 100)`);
    h.ok(t.pequeno > 0 && t.pequeno < 100, `${nome}: o player pequeno troca em ${Math.round(t.pequeno)} ms (menos de 100)`);
    h.ok(meio.capaGrande.startsWith('data:') && meio.capaGrande === meio.capaTopo, `${nome}: a capa grande e a do alto já são a da faixa tocada`);
    h.ok(meio.linhas[0] === 'Próxima música 5' && meio.linhas.length === 5, `${nome}: as faixas de cima saíram da lista (${meio.linhas.length} linhas, a primeira é ${meio.linhas[0]})`);
    h.ok(meio.fantasmas >= 1, `${nome}: as faixas de cima aparecem saindo com animação (${meio.fantasmas} em saída)`);
    h.ok(meio.animando >= 1, `${nome}: a lista sobe animada para ocupar o lugar (${meio.animando} linhas em movimento)`);
    await h.foto(p, 'fila-animacao-meio-' + w);
    await h.dormir(700);
    // a troca já está feita: o que está na tela agora é o que tem de sobreviver à confirmação do Mac (que só chega depois de 1,5 s)
    await p.evaluate(() => { document.querySelector('#f-player .capa-grande').__marca = 1; document.querySelector('#pc-lista-topo .linha-agora').__marca = 1 });
    h.ok(await p.evaluate(() => document.querySelectorAll('.fila-saida').length === 0), `${nome}: a camada da saída some quando a animação acaba`);
    // 2. o Mac responde: nada pisca nem pula
    await h.espera(p, () => document.querySelector('#f-player .pc .faixa')?.textContent === 'Próxima música 4' && !!document.querySelector('#f-player .capa-grande'), null, 4000);
    await h.dormir(2200);
    const fim = await p.evaluate(() => ({
      capa: document.querySelector('#f-player .capa-grande').__marca === 1, topo: document.querySelector('#pc-lista-topo .linha-agora').__marca === 1,
      faixa: document.querySelector('#f-player .pc .faixa').textContent, topoTx: document.querySelector('#pc-lista-topo b').textContent,
      linhas: document.querySelector('#pc-lista-corpo [data-pular] b')?.textContent, n: document.querySelectorAll('#pc-lista-corpo [data-pular]').length, t: window.__t,
    }));
    h.ok(fim.capa && fim.topo, `${nome}: quando o Mac confirma, a capa e o alto da fila não são refeitos (sem piscar)`);
    h.ok(fim.t.capaVazia === 0, `${nome}: a capa grande nunca ficou em branco`);
    h.ok(fim.faixa === NOVA && fim.topoTx === NOVA && fim.linhas === 'Próxima música 5' && fim.n === 5, `${nome}: depois da confirmação segue tudo igual (${fim.faixa}, ${fim.n} linhas)`);
    const lar = fim.t.larguras;
    h.ok(lar.length > 5 && lar.every(x => x.every(n => n <= 0)), `${nome}: sem rolagem horizontal durante e depois da troca (${lar.length} medidas, pior ${JSON.stringify(lar.find(x => x.some(n => n > 0)) || 0)})`);
    await p.context().close();

    // 3. o Mac recusa: volta ao que era, com aviso
    await h.reset(); await h.cenario({ atrasoAcao: 600, spotify: 'tocando', spotifyExtras: 'login', filaContexto: 'Daily Mix 3', filaRecusa: 'A fila mudou. Abra a fila de novo.' });
    p = await h.pagina({ w, h: alt }); await abrirFila(h, p);
    await p.click('#pc-lista-corpo [data-pular="3"]'); await h.dormir(120);
    h.ok(await p.evaluate(() => document.querySelector('#pc-lista-topo b').textContent) === NOVA, `${nome}: com o Mac ainda calado a faixa nova já aparece`);
    await h.espera(p, () => document.querySelector('#pc-lista-topo b')?.textContent === 'Faixa de Exemplo' && document.querySelectorAll('#pc-lista-corpo [data-pular]').length === 9, null, 4000);
    await h.dormir(500);
    const volta = await p.evaluate(() => ({ topo: document.querySelector('#pc-lista-topo b').textContent, grande: document.querySelector('#f-player .pc .faixa').textContent, n: document.querySelectorAll('#pc-lista-corpo [data-pular]').length, aviso: document.querySelector('#aviso-txt').textContent, visivel: document.querySelector('#aviso').classList.contains('visivel') }));
    h.ok(volta.topo === 'Faixa de Exemplo' && volta.grande === 'Faixa de Exemplo' && volta.n === 9, `${nome}: o Mac recusou, tudo volta ao estado anterior (${volta.n} linhas)`);
    h.ok(volta.visivel && volta.aviso.includes('A fila mudou'), `${nome}: o aviso curto do erro aparece (${volta.aviso})`);
    await p.context().close();
  }
  // 4. quem pediu menos movimento: a troca é na hora e sem animação
  await h.reset(); await h.cenario({ atrasoAcao: 1500, spotify: 'tocando', spotifyExtras: 'login' });
  const ctx = await h.novoContexto({ reducedMotion: 'reduce' });
  const p = await h.pagina({ ctx }); await abrirFila(h, p);
  await p.click('#pc-lista-corpo [data-pular="3"]'); await h.dormir(60);
  const rm = await p.evaluate(() => ({ topo: document.querySelector('#pc-lista-topo b').textContent, fantasmas: document.querySelectorAll('.fila-saida > *').length, animando: [...document.querySelectorAll('#pc-lista-corpo [data-pular]')].filter(b => b.getAnimations().length).length, n: document.querySelectorAll('#pc-lista-corpo [data-pular]').length }));
  h.ok(rm.topo === NOVA && rm.n === 5 && rm.fantasmas === 0 && rm.animando === 0, `movimento reduzido: troca na hora, sem animação (${JSON.stringify(rm)})`);
  await ctx.close();
}
