// 16/11/2026: "Quando clico na nova faixa pra tocar na lista ... deve ser instantaneo". O Mac só manda o play na hora se o painel
// disser de qual lista a fila vem: a fila traz a uri do contexto e o toque devolve ela junto da música.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'login', filaContexto: 'Daily Mix 3' });
  const p = await h.pagina({ w: 932, h: 430 }); await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(500);
  await p.click('#f-player [data-fila]'); await h.dormir(900);
  await p.click('#pc-lista-corpo [data-pular="1"]'); await h.dormir(900);
  const c = await h.contadores();
  h.ok(c.pularCtx?.at(-1) === 'spotify:playlist:37i9dQZF1EIXU3Q6t3bSoG', `tocar na fila manda a lista que toca junto (${JSON.stringify(c.pularCtx)})`);
  await p.context().close();

  // fila sem lista conhecida (Mac não soube dizer): nada de ctx, o Mac cai no caminho que confere
  await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'login', filaContexto: '' });
  const q = await h.pagina({ w: 932, h: 430 }); await pronta(h, q); await h.dormir(400);
  await q.click('.player .capa');
  await h.espera(q, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(500);
  await q.click('#f-player [data-fila]'); await h.dormir(900);
  await q.click('#pc-lista-corpo [data-pular="1"]'); await h.dormir(900);
  const d = await h.contadores();
  h.ok(d.pularCtx?.at(-1) === null, `sem lista conhecida, o pedido vai sem contexto (${JSON.stringify(d.pularCtx)})`);
  await q.context().close();
}
