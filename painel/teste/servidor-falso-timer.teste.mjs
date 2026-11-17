// Varredura 16/11/2026: o timer do comando lento lia o cenário global na hora de disparar. Se o teste acabava antes do
// prazo e o /__reset entrava, o timer mexia em andamento e acesas do cenário do arquivo seguinte (teste intermitente).
export default async function (h) {
  await h.reset(); await h.cenario({ comFoco: true, acesas: [], comandoLento: 1500 });
  const cab = { 'X-Deck-Codigo': h.CODIGO };
  const r = await fetch(h.base + '/api/botao/foco', { method: 'POST', headers: cab, body: '{}' });
  h.ok(r.ok, 'o comando lento foi aceito pelo Mac de mentira');
  await h.reset(); // o próximo arquivo de teste começa aqui
  await h.dormir(1900);
  const e = await (await fetch(h.base + '/api/estado', { headers: cab })).json();
  h.ok(!e.andamento, `o timer de um cenário antigo não deixa "andamento" no cenário novo (${JSON.stringify(e.andamento)})`);
  h.ok(!(e.acesas || []).includes('foco'), `nem acende a tecla no cenário novo (${JSON.stringify(e.acesas)})`);
}
