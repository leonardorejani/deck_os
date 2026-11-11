// O laço de estado: a cada 1 s, esperando a resposta antes do próximo, com tempo limite.
export default async function (h) {
  /* cadência normal: cerca de um pedido por segundo */
  await h.reset();
  let p = await h.pagina();
  await h.dormir(5200);
  let c = await h.contadores();
  h.ok(c.estado >= 4 && c.estado <= 7, `cerca de 1 pedido por segundo (${c.estado} pedidos em 5,2 s)`);
  h.ok(c.maxSimultaneos === 1, `nunca dois pedidos de estado ao mesmo tempo (máximo ${c.maxSimultaneos})`);
  await p.context().close();

  /* Mac devagar: a resposta demora mais que o intervalo e os pedidos não empilham */
  await h.reset(); await h.cenario({ atraso: 1600 });
  p = await h.pagina();
  await h.dormir(7500);
  c = await h.contadores();
  h.ok(c.maxSimultaneos === 1, `Mac devagar (1,6 s por resposta): os pedidos não se sobrepõem (máximo ${c.maxSimultaneos} em ${c.estado})`);
  h.ok(c.estado >= 3 && c.estado <= 6, `e o laço espera cada resposta (${c.estado} pedidos em 7,5 s)`);
  // tocar numa tecla no meio de um pedido também não empilha
  await p.click('.tecla[data-id="apagar"]'); await p.click('.tecla[data-id="acordado"]'); await h.dormir(2500);
  c = await h.contadores();
  h.ok(c.maxSimultaneos === 1 && c.botoes.length === 2, `ações do usuário no meio do laço não geram pedido de estado em paralelo (máximo ${c.maxSimultaneos})`);
  await p.context().close();

  /* Mac que atende e nunca responde: tempo limite, tela de Mac desconectado, e volta quando responde */
  await h.reset(); await h.cenario({ pendurar: true });
  p = await h.pagina({ ajustes: { tempoLimite: 600, msParaOffline: 1500 } });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 6000), 'sem resposta, o tempo limite derruba o pedido e a tela mostra "Mac desconectado"');
  await h.dormir(2500);
  c = await h.contadores();
  h.ok(c.maxSimultaneos === 1, `pedido pendurado é cancelado antes do próximo (máximo ${c.maxSimultaneos} em ${c.estado})`);
  await h.cenario({ pendurar: false });
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a .faixa') && !document.querySelector('#tela').classList.contains('offline'), null, 5000), 'o Mac responde de novo e o painel abre sozinho');
  await p.context().close();

  /* uma falha só não fecha a tela: um pedido fica sem resposta e o seguinte volta */
  await h.reset();
  p = await h.pagina({ ajustes: { tempoLimite: 700 } });
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.cenario({ pendurar: true }); await h.dormir(450); await h.cenario({ pendurar: false });
  await h.dormir(2600);
  h.ok(await p.evaluate(() => !document.querySelector('#tela').classList.contains('offline')), 'uma única falha seguida de resposta não fecha a tela');
  await p.context().close();
  await h.reset();

  /* "Mac desconectado" só quando o Mac sumiu de fato: 3 falhas seguidas E mais de 5 s sem resposta boa. Antes eram 2 falhas
     (cerca de 2 s) e um pedido de 3 s já contava como queda. Palavras dele: "o celular apresenta o mac reconectando várias vezes" */
  const gravaFechamentos = () => { window.__off = []; new MutationObserver(() => { const t = document.querySelector('#tela'); if (t?.classList.contains('offline') && !window.__off.length) window.__off.push(Math.round(performance.now())) }).observe(document, { subtree: true, attributes: true, attributeFilter: ['class'] }) };
  const noAr = p => h.espera(p, () => !!document.querySelector('.comp-a .faixa'));

  // 1. um tropeço de 3,5 s (o Mac reiniciando, o Wi-Fi piscando) não fecha a tela
  await h.reset();
  p = await h.pagina({ antes: gravaFechamentos });
  await noAr(p);
  await h.cenario({ mac: 'off' }); await h.dormir(3500); await h.cenario({ mac: 'on' }); await h.dormir(2500);
  h.ok((await p.evaluate(() => window.__off)).length === 0, 'o Mac some por 3,5 s e volta: a tela nunca fecha');
  await p.context().close();

  // 2. o Mac devagar (estado em 3,5 s, mais que os 3 s de antes) responde dentro do tempo limite e a tela não fecha
  await h.reset(); await h.cenario({ atraso: 3500 });
  p = await h.pagina({ antes: gravaFechamentos });
  await noAr(p);
  await h.dormir(9000);
  const lento = await p.evaluate(() => window.__off.length);
  c = await h.contadores();
  h.ok(lento === 0 && c.estado >= 3, `estado em 3,5 s não é queda (fechou ${lento} vez, ${c.estado} respostas)`);
  await p.context().close(); await h.cenario({ atraso: 0 });

  // 3. o Mac some de verdade: a tela fecha depois de mais de 5 s, e abre sozinha quando ele volta
  await h.reset();
  p = await h.pagina({ antes: gravaFechamentos });
  await noAr(p);
  const t0 = await p.evaluate(() => Math.round(performance.now()));
  await h.cenario({ mac: 'off' });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 12000), 'o Mac some de verdade: a tela fecha');
  const quando = (await p.evaluate(() => window.__off))[0] - t0;
  h.ok(quando >= 4500, `e só fecha com mais de 5 s sem resposta (fechou ${quando} ms depois de o Mac sumir)`);
  await h.cenario({ mac: 'on' });
  h.ok(await h.espera(p, () => !document.querySelector('#tela').classList.contains('offline'), null, 5000), 'o Mac volta e a tela abre sozinha');
  await p.context().close();

  // 4. o Mac pendurado (aceita a conexão e nunca responde): cada pedido espera 5 s, então esperar 3 falhas deixava o painel
  // uns 16 s com cara de ao vivo. Com 2 falhas e mais de 10 s sem resposta boa a tela fecha (cerca de 11 s).
  await h.reset();
  p = await h.pagina({ antes: gravaFechamentos });
  await noAr(p);
  const t1 = await p.evaluate(() => Math.round(performance.now()));
  await h.cenario({ atraso: 60000 });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 20000), 'o Mac pendurado: a tela fecha');
  const pendurado = (await p.evaluate(() => window.__off))[0] - t1;
  h.ok(pendurado < 13000, `e fecha em menos de 13 s (fechou ${pendurado} ms depois de o Mac pendurar)`);
  await h.cenario({ atraso: 0 });
  await p.context().close();
  await h.reset();
}
