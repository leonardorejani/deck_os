// O Spotify bloqueou a chave do Deck (429): o player diz até quando, e tocar/pausar seguem funcionando (16/11/2026).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'login', spotifyLimite: 3 * 3600 });
  const p = await h.pagina(); await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(400);
  const aviso = await p.evaluate(() => document.querySelector('#f-player .pc-limite')?.textContent || '');
  h.ok(/^O Spotify limitou as leituras até \d{2}:\d{2}\. Tocar, pausar e pular continuam funcionando\.$/.test(aviso), 'o player cheio diz até quando o Spotify limitou: ' + aviso);
  const preto = await p.evaluate(() => { const r = document.querySelector('#f-player .pc-limite').getBoundingClientRect(), f = document.querySelector('#f-player').getBoundingClientRect(); return r.right <= f.right && r.bottom <= f.bottom });
  h.ok(preto, 'o aviso cabe dentro do player');
  await p.click('#f-player [data-fila]'); await h.dormir(900);
  const lista = await p.evaluate(() => document.querySelector('#pc-lista-corpo').textContent);
  h.ok(lista.includes('Spotify limitou as leituras até') && !lista.includes('pediu para esperar'), 'a fila mostra o aviso com a hora, não "tente de novo"');
  await h.cenario({ spotifyLimite: 0 }); await h.dormir(1500);
  const sumiu = await p.evaluate(() => !document.querySelector('#f-player .pc-limite'));
  h.ok(sumiu, 'passado o bloqueio o aviso some');
  await p.close();
}
