// Verificação da leva 2 (11/11/2026): o cartão do player da tela inicial não ganha a linha de volume/curtir/aparelhos/fila,
// que só existe no player grande. A tela inicial fica do tamanho da main e a última fileira de teclas cabe no rodapé.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const medir = p => p.evaluate(() => ({
  cartao: Math.round(document.querySelector('.cartao.player').getBoundingClientRect().height),
  extras: document.querySelectorAll('.cartao.player .pc-extras').length,
  fundo: Math.round(Math.max(...[...document.querySelectorAll('.tecla')].map(t => t.getBoundingClientRect().bottom))), alto: innerHeight,
}));

export default async function (h) {
  const base = {};
  for (const modo of ['nao', 'volume', 'dois', 'login']) {
    for (const [w, alt, nome] of [[430, 932, 'em pé'], [932, 430, 'deitado']]) {
      await h.reset(); await h.cenario({ spotifyExtras: modo });
      const p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(300);
      const m = await medir(p);
      if (modo === 'nao') base[nome] = m.cartao;
      h.ok(m.extras === 0, `${nome}, Spotify "${modo}": o cartão do player da tela inicial não tem a linha de extras`);
      h.ok(m.cartao === base[nome], `${nome}, Spotify "${modo}": o cartão tem ${m.cartao} pt, igual ao do Mac antigo (${base[nome]})`);
      if (nome === 'em pé') h.ok(m.fundo <= m.alto, `${nome}, Spotify "${modo}": a última fileira de teclas termina em ${m.fundo} numa tela de ${m.alto}`);
      await p.context().close();
    }
  }
}
