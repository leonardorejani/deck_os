// 19/11/2026: "A imagem da capa da música quando deixa em tela cheia fica com qualidade baixa". No Bluetooth o Mac reduz toda
// capa a 200 px, e a tela cheia (320 a 350 pt, 3x no iPhone) esticava essa miniatura. A tela cheia pede a capa em tamanho
// grande (tam=grande), o mini player e a miniatura da fila seguem com a pequena, e cada tamanho tem a sua URL (cache por tamanho).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'nao' });
  const p = await h.pagina(); await pronta(h, p); await h.dormir(400);
  const mini = await p.evaluate(() => document.querySelector('.player .capa').getAttribute('src'));
  h.ok(mini.includes('/api/capa') && !mini.includes('tam='), `o mini player pede a capa pequena (${mini})`);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande[src]'), null, 3000);
  await h.dormir(500);
  const cheia = await p.evaluate(() => document.querySelector('#f-player .capa-grande').getAttribute('src'));
  h.ok(cheia.includes('/api/capa') && cheia.includes('tam=grande'), `a tela cheia pede a capa grande (${cheia})`);
  h.ok(cheia !== mini, 'cada tamanho tem a sua URL, então o cache não troca uma capa pela outra');
  const c = await h.contadores();
  h.ok(c.capasTam.includes('grande') && c.capasTam.includes('pequena'), `o Mac recebeu os dois pedidos (${JSON.stringify(c.capasTam)})`);
  await p.context().close();
}
