// Item 9: quando a conexão cai a tela diz a causa, e as novas tentativas se espaçam em 1, 2, 4, 8, 16 e 30 s (sem rajada).
export default async function (h) {
  /* 1. as peças puras: a causa de cada falha e a escala */
  const p0 = await h.pagina();
  const u = await p0.evaluate(() => ({
    rede: causaDaFalha({ status: 0, rede: true }), expirou: causaDaFalha({ status: 401 }), semCodigo: causaDaFalha({ status: 401, semCodigo: true }),
    pausado: causaDaFalha({ status: 429 }), escala: [1, 2, 3, 4, 5, 6, 7, 20].map(esperaOffline),
  }));
  h.ok(u.rede === 'macIndisponivel' && u.expirou === 'codigoExpirou' && u.semCodigo === 'naoPareado' && u.pausado === 'pareamentoPausado', `causa de cada falha: ${JSON.stringify(u)}`);
  h.ok(JSON.stringify(u.escala) === JSON.stringify([1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]), `escala 1, 2, 4, 8, 16, 30 s e fica em 30: ${u.escala}`);
  await p0.context().close();

  /* 2. Mac fora: a tela diz "Mac indisponível" e as tentativas se espaçam (escala em ms para o teste não demorar) */
  const gravar = () => { window.__t = []; const f = window.fetch; window.fetch = (u, o) => { if (String(u).includes('/api/estado')) window.__t.push(Math.round(performance.now())); return f(u, o) } };
  const ajustes = { intervalo: 100, msParaOffline: 300, esperasOffline: [200, 400, 800, 1600, 3200, 6000] };
  const p = await h.pagina({ antes: gravar, ajustes });
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.cenario({ mac: 'off' });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 8000), 'Mac fora do ar: a tela fecha');
  const txt = await p.evaluate(() => document.querySelector('.tela-offline:not(.acesso) .dica-off').textContent);
  h.ok(txt === 'Mac indisponível. Confira se ele está ligado e no mesmo Wi-Fi.', `a tela diz a causa: "${txt}"`);
  await h.espera(p, () => window.__t.length > 0 && performance.now() - window.__t[window.__t.length - 1] > 0, null, 100);
  await h.dormir(3800); // flip + 200 + 400 + 800 + 1600 ms de espera
  const ts = await p.evaluate(() => window.__t), gaps = ts.slice(1).map((t, i) => t - ts[i]);
  const apos = gaps.slice(-4); // as esperas depois de a tela fechar
  h.ok(apos.length === 4 && apos[1] >= apos[0] * 1.6 && apos[2] >= apos[1] * 1.6 && apos[3] >= apos[2] * 1.6, `as tentativas se espaçam em degraus (intervalos ${apos.join(', ')} ms)`);
  h.ok(Math.max(...gaps.slice(-4)) > 1000 && gaps.filter(g => g < 150).length <= 4, `sem rajada de pedidos (${gaps.length} intervalos, menores que 150 ms: ${gaps.filter(g => g < 150).length})`);

  /* 3. rede voltou (evento online): tenta já e recomeça do degrau de 1 s, mesmo no meio de uma espera longa */
  await h.cenario({ mac: 'on' });
  const antes = (await p.evaluate(() => window.__t)).length;
  await p.evaluate(() => dispatchEvent(new Event('online')));
  h.ok(await h.espera(p, () => !document.querySelector('#tela').classList.contains('offline'), null, 1500), 'a rede voltou: tenta na hora, sem esperar o degrau longo');
  h.ok((await p.evaluate(() => window.__t)).length > antes, 'e o evento gerou um pedido');
  await p.context().close();
  await h.cenario({ mac: 'on' });

  /* 4. código recusado pelo Mac: "Código expirou". Sem código nenhum continua "Deck não pareado" */
  const pe = await h.pagina({ codigo: 'ERRADOERRADOERRADO12' });
  h.ok(await h.espera(pe, () => document.querySelector('#tela').classList.contains('sem-acesso')), 'código recusado: tela de acesso');
  const t1 = await pe.evaluate(() => document.querySelector('#acesso-titulo').textContent);
  h.ok(t1 === 'Código expirou', `título quando o Mac recusa o código: "${t1}"`);
  await h.foto(pe, 'conexao-codigo-expirou');
  await pe.context().close();
  const ps = await h.pagina({ codigo: false });
  h.ok(await h.espera(ps, () => document.querySelector('#tela').classList.contains('sem-acesso')), 'sem código: tela de acesso');
  h.ok(await ps.evaluate(() => document.querySelector('#acesso-titulo').textContent) === 'Deck não pareado', 'sem código nenhum continua "Deck não pareado"');
  await ps.context().close();

  /* 5. pareamento pausado: depois de 5 erros o Mac para de aceitar, e a página diz isso */
  await h.reset();
  const pp = await h.pagina({ codigo: false });
  const msg = await pp.evaluate(async () => {
    let ultimo = null;
    for (let i = 0; i < 6; i++) { try { await canal.parear('000000') } catch (e) { ultimo = { m: e.message, s: e.status } } }
    return ultimo;
  });
  h.ok(msg?.s === 429 && msg.m === 'Pareamento pausado. Gere um código novo no Mac.', `pareamento pausado: ${JSON.stringify(msg)}`);
  await pp.context().close();
  await h.reset();
}
