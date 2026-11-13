// A fila do Spotify nunca rola para o lado (13/11/2026: "spotify tá tendo scroll horizontal: nao pode"). As linhas com capa sangram
// uma folga para cada lado, e essa folga virava rolagem horizontal no corpo da lista, cortando "Próximas" e as capas.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  for (const [w, alt, nome] of [[932, 430, 'celular deitado'], [430, 932, 'celular em pé'], [2000, 967, 'janela larga do Chrome']]) {
    await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'login', filaContexto: 'Daily Mix 3' });
    const p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(400);
    await p.click('.player .capa');
    await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
    await h.dormir(500);
    await p.click('#f-player [data-fila]'); await h.dormir(900);
    const medir = () => p.evaluate(() => {
      const c = document.querySelector('#pc-lista-corpo'), l = document.querySelector('#pc-lista'), f = document.querySelector('#f-player');
      const raiz = document.scrollingElement;
      return { corpo: [c.scrollWidth, c.clientWidth], lista: [l.scrollWidth, l.clientWidth], folha: [f.scrollWidth, f.clientWidth], pagina: [raiz.scrollWidth, raiz.clientWidth] };
    });
    const m = await medir();
    for (const [onde, [sw, cw]] of Object.entries(m)) h.ok(sw <= cw, `${nome}: ${onde} sem rolagem lateral (scrollWidth ${sw} <= clientWidth ${cw})`);
    // empurrar para o lado não anda nada: o título "Próximas" continua colado na borda esquerda do corpo
    const antes = await p.evaluate(() => document.querySelector('#pc-lista-corpo h3').getBoundingClientRect().left);
    await p.evaluate(() => { document.querySelector('#pc-lista-corpo').scrollLeft = 80 }); await h.dormir(150);
    const depois = await p.evaluate(() => ({ x: document.querySelector('#pc-lista-corpo h3').getBoundingClientRect().left, sl: document.querySelector('#pc-lista-corpo').scrollLeft }));
    h.ok(depois.sl === 0 && depois.x === antes, `${nome}: tentar rolar para o lado não move a lista (scrollLeft ${depois.sl})`);
    // a capa da primeira linha fica inteira dentro do corpo
    const capa = await p.evaluate(() => { const i = document.querySelector('#pc-lista-corpo .capa-fila').getBoundingClientRect(), c = document.querySelector('#pc-lista-corpo').getBoundingClientRect(); return i.left >= c.left && i.right <= c.right });
    h.ok(capa, `${nome}: as capas não ficam cortadas`);
    // o alinhamento de antes segue: "Próximas" e a capa começam onde começa "Tocando agora"
    const alin = await p.evaluate(() => ({ topo: document.querySelector('#pc-lista-topo .rotulo').getBoundingClientRect().left, h3: document.querySelector('#pc-lista-corpo h3').getBoundingClientRect().left, capa: document.querySelector('#pc-lista-corpo .capa-fila').getBoundingClientRect().left }));
    h.ok(Math.abs(alin.h3 - alin.topo) <= 1 && Math.abs(alin.capa - alin.topo) <= 1, `${nome}: o título e as capas seguem alinhados com "Tocando agora" (${JSON.stringify(alin)})`);
    await h.foto(p, 'fila-sem-rolagem-' + w);
    await p.context().close();
  }
}
