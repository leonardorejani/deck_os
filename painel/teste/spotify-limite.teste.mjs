// O Spotify bloqueou a chave do Deck (429): o player diz até quando, e tocar/pausar seguem funcionando (16/11/2026).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando', spotifyExtras: 'login', spotifyLimite: 3 * 3600 });
  const p = await h.pagina(); await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa');
  await h.espera(p, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
  await h.dormir(400);
  const aviso = await p.evaluate(() => document.querySelector('#f-player .pc-limite')?.textContent || '');
  h.ok(/^Lista volta às \d{2}:\d{2}$/.test(aviso), 'o player cheio diz só a hora em que a lista volta: ' + aviso);
  const preto = await p.evaluate(() => { const r = document.querySelector('#f-player .pc-limite').getBoundingClientRect(), f = document.querySelector('#f-player').getBoundingClientRect(); return r.right <= f.right && r.bottom <= f.bottom });
  h.ok(preto, 'o aviso cabe dentro do player');
  await p.click('#f-player [data-fila]'); await h.dormir(900);
  const lista = await p.evaluate(() => document.querySelector('#pc-lista-corpo').textContent);
  h.ok(/^\s*Lista volta às \d{2}:\d{2}\s*$/.test(lista) && !lista.includes('Tentar de novo') && !lista.includes('Não deu para ler'), 'a fila mostra só a linha com a hora, sem bloco de erro nem "Tentar de novo"');
  const disc = await p.evaluate(() => { const e = document.querySelector('#pc-lista-corpo .pc-limite-lista'); if (!e) return null; const c = getComputedStyle(e); return { px: parseFloat(c.fontSize), botoes: document.querySelectorAll('#pc-lista-corpo button, #pc-lista-corpo .vazio-bloco').length } });
  h.ok(disc && disc.px <= 13 && disc.botoes === 0, 'o aviso é texto pequeno, sem botão nem bloco: ' + JSON.stringify(disc));
  await h.cenario({ spotifyLimite: 0 }); await h.dormir(1500);
  const sumiu = await p.evaluate(() => !document.querySelector('#f-player .pc-limite'));
  h.ok(sumiu, 'passado o bloqueio o aviso some');
  await p.close();
}
