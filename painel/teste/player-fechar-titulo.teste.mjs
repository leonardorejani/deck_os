// 16/11/2026: "Esse X tá quebrando a UI". No player em tela cheia o botão de fechar (canto de cima à direita) ficava por cima do
// título comprido ("... from the series League of Legends"). O título tem de acabar antes do X, em qualquer tamanho de tela.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const LONGO = 'Arcane Season 2 Main Title Theme Medley Extended Orchestral Version Remastered - from the series League of Legends';

export default async function (h) {
  for (const [w, alt, nome] of [[932, 430, 'celular deitado'], [430, 932, 'celular em pé'], [2000, 967, 'janela larga do Chrome'], [667, 375, 'celular deitado pequeno']]) {
    for (const extras of ['nao', 'login']) {
      await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: extras, faixa: LONGO, artista: 'Artista com um nome também bem comprido para testar a linha', album: 'Um álbum de nome longo (Deluxe Edition)' });
      const p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(400);
      await p.click('.player .capa');
      await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
      await h.dormir(600);
      const m = await p.evaluate(() => {
        const x = document.querySelector('#f-player .fechar-cal').getBoundingClientRect();
        const caixas = [];
        for (const el of document.querySelectorAll('#f-player .pc-titulos > *')) {
          const r = document.createRange(); r.selectNodeContents(el);
          for (const c of r.getClientRects()) if (c.width > 0 && c.height > 0) caixas.push([c.left, c.top, c.right, c.bottom]);
        }
        const dentro = caixas.filter(([l, t, r, b]) => l < x.right && r > x.left && t < x.bottom && b > x.top);
        return { x: [x.left, x.top, x.right, x.bottom], n: caixas.length, sobrepoe: dentro.length, vp: [innerWidth, innerHeight] };
      });
      h.ok(m.n > 0 && m.sobrepoe === 0, `${nome} (${extras}): o texto do player não passa por baixo do X (${m.sobrepoe} de ${m.n} linhas sobrepõem, X ${m.x.map(Math.round)})`);
      await h.foto(p, `player-x-${w}-${extras}`);
      await p.context().close();
    }
  }
}
