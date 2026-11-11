// Todos os estados da seção 6 da SPEC, a partir do estado que o Mac manda.
const caixa = (p, sel) => p.evaluate(s => { const e = document.querySelector(s); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height } }, sel);
const perto = (a, b, tol = 1.5) => a && b && ['x', 'y', 'w', 'h'].every(k => Math.abs(a[k] - b[k]) <= tol);
const marcador = () => { // anota quando o esqueleto e o painel real aparecem
  window.__t = {};
  const c = () => document.querySelector('#conteudo');
  new MutationObserver(() => {
    const e = c(), n = performance.now(); if (!e) return;
    if (e.children.length && __t.conteudo == null) __t.conteudo = n;
    const esq = e.classList.contains('carregando');
    if (esq && __t.esq == null) __t.esq = n;
    if (!esq && e.querySelector('.comp-a, .comp-b') && __t.esq != null && __t.fim == null) __t.fim = n;
  }).observe(document, { subtree: true, childList: true, attributes: true });
};

export default async function (h) {
  /* carregando: nada nos primeiros 200 ms, depois o esqueleto com a forma do bloco, no mínimo 400 ms */
  await h.cenario({ atraso: 1200 });
  let p = await h.pagina({ antes: marcador });
  h.ok(await h.espera(p, () => window.__t?.esq != null, null, 3000), 'resposta lenta: o esqueleto aparece');
  let t = await p.evaluate(() => window.__t);
  h.ok(t.conteudo >= 190, `nos primeiros 200 ms não aparece nada (primeiro conteúdo em ${Math.round(t.conteudo)} ms)`);
  const esq = await p.evaluate(() => ({ player: !!document.querySelector('.carregando .player'), uso: !!document.querySelector('.carregando .cartao.uso'), ses: document.querySelectorAll('.carregando .sessao').length, teclas: document.querySelectorAll('.carregando .pagina .tecla').length, relogio: document.querySelectorAll('.carregando .placa').length }));
  h.ok(esq.player && esq.uso && esq.ses === 3 && esq.teclas === 4 && esq.relogio === 4, `o esqueleto tem a forma padrão da primeira visita (${JSON.stringify(esq)})`);
  await h.foto(p, 'estado-carregando');
  h.ok(await h.espera(p, () => document.querySelector('.comp-a .faixa')?.textContent === 'Faixa de Exemplo', null, 5000), 'a resposta troca o esqueleto pelo painel');
  await p.context().close();

  /* a forma da última visita: o esqueleto cai no mesmo lugar do bloco real */
  await h.cenario({ atraso: 0 });
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.dormir(300);
  const real = { player: await caixa(p, '.player'), uso: await caixa(p, '.cartao.uso'), ses: await caixa(p, '.sessoes'), tecla: await caixa(p, '.tecla') };
  await h.cenario({ atraso: 1500 });
  await p.addInitScript(marcador); await p.reload();
  await h.espera(p, () => window.__t?.esq != null, null, 3000);
  await h.dormir(150);
  const no = { player: await caixa(p, '.player'), uso: await caixa(p, '.cartao.uso'), ses: await caixa(p, '.sessoes'), tecla: await caixa(p, '.tecla') };
  h.ok(Object.keys(real).every(k => perto(real[k], no[k])), `esqueleto na mesma posição e medida do bloco real (${JSON.stringify(no)} contra ${JSON.stringify(real)})`);
  h.ok(await p.evaluate(() => document.querySelectorAll('.carregando .sessao').length) === 5, 'o esqueleto lembra a quantidade de sessões da última visita (5)');
  await p.context().close();

  /* resposta rápida: o esqueleto nem aparece. Resposta logo depois dele: fica 400 ms */
  await h.cenario({ atraso: 0 });
  p = await h.pagina({ antes: marcador });
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa')); await h.dormir(700);
  h.ok(await p.evaluate(() => window.__t.esq == null), 'resposta rápida: o esqueleto nem pisca');
  await p.context().close();
  await h.cenario({ atraso: 450 });
  p = await h.pagina({ antes: marcador });
  await h.espera(p, () => window.__t?.fim != null, null, 4000);
  t = await p.evaluate(() => window.__t);
  h.ok(t.fim - t.esq >= 380, `o esqueleto, depois de aparecer, fica pelo menos 400 ms (ficou ${Math.round(t.fim - t.esq)} ms)`);
  await p.context().close();
  await h.cenario({ atraso: 0 });

  /* Mac fora do ar: a tela fecha, volta sozinha */
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.cenario({ mac: 'off' });
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 8000), 'Mac fora do ar: a tela fecha');
  await h.dormir(700);
  const off = await p.evaluate(() => { const o = document.querySelector('.tela-offline:not(.acesso)'); return { op: getComputedStyle(o).opacity, txt: o.textContent.replace(/\s+/g, ' ').trim(), nome: document.querySelector('#nome-mac').textContent, gira: getComputedStyle(document.querySelector('.girando')).animationName, pill: !!o.querySelector('.disp svg') } });
  h.ok(off.op === '1' && off.txt.includes('Mac desconectado') && off.txt.includes('Confira se ele está ligado e no mesmo Wi-Fi.'), `texto do Mac fora do ar: "${off.txt}"`);
  h.ok(off.nome === 'MacBook Pro de Teste' && off.gira === 'girar' && off.pill, `pílula com o nome do Mac, o ícone de notebook e o giro (${off.nome})`);
  await h.foto(p, 'estado-offline');
  await h.cenario({ mac: 'on' });
  h.ok(await h.espera(p, () => !document.querySelector('#tela').classList.contains('offline'), null, 5000), 'o Mac volta e a tela abre sozinha');
  await p.context().close();
  await h.cenario({ mac: 'off' });
  p = await h.pagina(); await h.dormir(1200);
  const ini = await p.evaluate(() => ({ off: document.querySelector('#tela').classList.contains('offline'), esq: !!document.querySelector('.carregando'), nome: document.querySelector('#nome-mac').textContent }));
  h.ok(ini.off && !ini.esq && ini.nome === 'Seu Mac', `Mac fora do ar já na primeira abertura: sem esqueleto, "${ini.nome}"`);
  await p.context().close(); await h.cenario({ mac: 'on' });

  /* Spotify fechado, pausado, e de volta */
  p = await h.pagina();
  await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  const ses0 = await caixa(p, '.sessoes');
  await h.cenario({ spotify: 'fechado' });
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a.sem-musica')), 'Spotify fechado: o player sai');
  await h.dormir(900);
  const ses1 = await caixa(p, '.sessoes');
  h.ok(await p.evaluate(() => getComputedStyle(document.querySelector('.player')).display) === 'none' && ses1.h > ses0.h + 40 && ses1.y < ses0.y, `as sessões crescem para o lugar dele (${Math.round(ses0.h)} para ${Math.round(ses1.h)} de altura)`);
  await h.foto(p, 'estado-spotify-fechado');
  await h.cenario({ spotify: 'pausado' });
  h.ok(await h.espera(p, () => !document.querySelector('.comp-a.sem-musica') && document.querySelector('.player.pausado')), 'Spotify de volta, pausado');
  await h.dormir(900);
  const pa = await p.evaluate(() => ({ op: getComputedStyle(document.querySelector('.capa')).opacity, play: !!document.querySelector('.tocar.play'), rot: document.querySelector('.tocar').getAttribute('aria-label') }));
  h.ok(pa.op === '0.5' && pa.play && pa.rot === 'Tocar', `pausado: capa a meia luz e botão de tocar (${JSON.stringify(pa)})`);
  const ses2 = await caixa(p, '.sessoes'); h.ok(Math.abs(ses2.h - ses0.h) < 2, 'as sessões voltam à altura de antes');
  await h.foto(p, 'estado-spotify-pausado');
  await h.cenario({ spotify: 'tocando' });
  h.ok(await h.espera(p, () => !document.querySelector('.player.pausado') && !!document.querySelector('.tocar:not(.play)')), 'tocando de novo');
  await p.context().close();

  /* nenhuma sessão, e com Spotify fechado também */
  await h.cenario({ sessoes: 0 });
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  let v = await p.evaluate(() => ({ t: document.querySelector('.sessoes .vazio-rico strong')?.textContent, d: document.querySelector('.sessoes .vazio-rico span')?.textContent, badge: !!document.querySelector('.sessoes .conta'), ic: !!document.querySelector('.sessoes .vazio-rico img') }));
  h.ok(v.t === 'Tudo respondido' && v.d === 'Nenhuma sessão do Claude esperando você.' && !v.badge && v.ic, `nenhuma sessão: "${v.t}" com o ícone do Claude`);
  await h.foto(p, 'estado-sem-sessoes');
  await h.cenario({ spotify: 'fechado' }); await h.dormir(1700);
  v = await p.evaluate(() => ({ t: document.querySelector('.sessoes .vazio-rico strong')?.textContent, sem: !!document.querySelector('.comp-a.sem-musica') }));
  h.ok(v.t === 'Tudo respondido' && v.sem, 'Spotify fechado e nenhuma sessão: as sessões ocupam o espaço com "Tudo respondido"');
  await p.context().close(); await h.reset();

  /* agenda: com evento, vazia, sem permissão */
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  const ev = new Date(Date.now() + 2 * 3600000), hh = String(ev.getHours()).padStart(2, '0') + ':' + String(ev.getMinutes()).padStart(2, '0');
  const esperado = ev.toDateString() === new Date().toDateString() ? hh : `amanhã ${hh}`;
  v = await p.evaluate(() => ({ hora: document.querySelector('.tecla[data-id="calendario"] .hora-tecla')?.textContent, selo: document.querySelector('.tecla[data-id="calendario"] .selo')?.textContent, wa: document.querySelector('.tecla[data-id="whatsapp"] .selo')?.textContent }));
  h.ok(v.hora === esperado && !v.selo, `agenda com evento: horário do próximo na tecla ("${v.hora}")`);
  h.ok(v.wa === '23', `WhatsApp: selo com as não lidas ("${v.wa}")`);
  await h.cenario({ agenda: 'sem' });
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="calendario"] .selo')?.textContent === '!'), 'agenda sem permissão: selo "!" na tecla');
  v = await p.evaluate(() => ({ hora: !!document.querySelector('.tecla[data-id="calendario"] .hora-tecla'), aria: document.querySelector('.tecla[data-id="calendario"] .selo').getAttribute('aria-label') }));
  h.ok(!v.hora && v.aria === 'Agenda sem permissão', 'sem permissão não mostra horário e o selo explica');
  await h.foto(p, 'estado-agenda-sem-permissao');
  await h.cenario({ agenda: 'vazia' });
  h.ok(await h.espera(p, () => !document.querySelector('.tecla[data-id="calendario"] .selo') && !document.querySelector('.tecla[data-id="calendario"] .hora-tecla')), 'agenda vazia: tecla limpa, sem horário e sem selo');
  await p.context().close(); await h.reset();

  /* uso sem medição */
  await h.cenario({ uso: 'sem-medicao' });
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  v = await p.evaluate(() => ({ b: [...document.querySelectorAll('.cartao.uso .medidor b')].map(x => x.textContent), larg: [...document.querySelectorAll('.cartao.uso .medidor i')].map(x => x.style.width), niv: document.querySelectorAll('.cartao.uso .medidor.alto, .cartao.uso .medidor.cheio').length, aria: document.querySelector('.cartao.uso .medidor').getAttribute('aria-label') }));
  h.ok(v.b.length === 3 && v.b.every(x => x === '-') && v.larg.every(x => x === '0%') && !v.niv, `uso sem medição: barra cinza com "-" (${v.b}) e "${v.aria}"`);
  await h.foto(p, 'estado-uso-sem-medicao');
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(300);
  v = await p.evaluate(() => [...document.querySelectorAll('.uso-tira b')].map(x => x.textContent));
  h.ok(v.length === 3 && v.every(x => x === '-'), `em pé a faixa de uso também mostra "-" (${v})`);
  await p.context().close(); await h.reset();

  /* uso com medição: faixas e textos de renovação */
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  v = await p.evaluate(() => ({ r: [...document.querySelectorAll('.cartao.uso .renova')].map(x => x.textContent), n: [...document.querySelectorAll('.cartao.uso .medidor')].map(x => x.className.replace('medidor', '').trim()), pct: [...document.querySelectorAll('.cartao.uso .medidor b')].map(x => x.textContent) }));
  h.ok(v.r.join('|') === '3 dias|amanhã|hoje 23h', `renovação a partir da data ISO (${v.r.join(', ')})`);
  h.ok(v.pct.join('|') === '61%|77%|4%' && v.n.join('|') === '|alto|', `amarelo a partir de 70% (${v.pct.join(', ')})`);
  await p.context().close();

  /* ação que falha: aviso de 4 s com o motivo que veio do Mac */
  await h.cenario({ falha: true });
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await p.click('.tecla[data-id="apagar"]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel') && document.querySelector('#aviso').classList.contains('erro'), null, 2000), 'ação que falha: aparece o aviso de erro');
  v = await p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, pisca: !!document.querySelector('.tecla.piscando') }));
  h.ok(v.txt.includes('Acessibilidade') && !v.pisca, `o aviso traz o motivo dado pelo Mac ("${v.txt}") e o LED não pisca`);
  await h.foto(p, 'estado-acao-falhou');
  await h.dormir(3300);
  h.ok(await p.evaluate(() => document.querySelector('#aviso').classList.contains('visivel')), 'aos 3,3 s o aviso ainda está na tela');
  await h.dormir(1100);
  h.ok(await p.evaluate(() => !document.querySelector('#aviso').classList.contains('visivel')), 'aos 4,4 s o aviso saiu (4 s)');
  h.ok(!(await h.contadores()).botoes.includes('apagar'), 'o Mac não registrou a tecla que falhou');
  await p.context().close(); await h.reset();

  /* ação que dá certo: LED pisca, e a tecla com estado liga e desliga pelo que o Mac devolve */
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await p.click('.tecla[data-id="apagar"]');
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="apagar"].piscando'), null, 1500), 'ação que deu certo: o LED pisca');
  h.ok(await h.espera(p, () => !document.querySelector('.tecla.piscando'), null, 1500), 'e o LED volta ao normal');
  h.ok((await h.contadores()).botoes.join() === 'apagar' && await p.evaluate(() => document.querySelector('#aviso-txt').textContent) === 'Apagar tela: feito', 'o Mac recebeu a tecla "apagar" e o aviso confirma');
  const lig0 = await p.evaluate(() => ({ acesa: document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa'), aria: document.querySelector('.tecla[data-id="acordado"]').getAttribute('aria-pressed') }));
  h.ok(lig0.acesa && lig0.aria === 'true', 'tecla ligada vem acesa (anel verde e aria-pressed)');
  await p.click('.tecla[data-id="acordado"]');
  h.ok(await h.espera(p, () => !document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa'), null, 2500), 'tocar na tecla ligada apaga, pelo estado que o Mac devolve');
  h.ok(await p.evaluate(() => document.querySelector('#aviso-txt').textContent) === 'Manter acordado: desligado', 'e o aviso diz "desligado"');
  await h.ate(async () => (await h.contadores()).botoes.length === 2); // a tela apagou no toque, o Mac recebe logo depois
  await h.dormir(400); // e a tela confirma com o estado dele, antes de ele mudar por fora
  await h.cenario({ acesas: ['acordado'] });
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="acordado"]').classList.contains('acesa'), null, 2500), 'ligar pelo Mac também aparece (estado a cada segundo)');
  await p.context().close(); await h.reset();

  /* blocos escondidos no Mac */
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  await h.cenario({ blocos: { sessoes: false } });
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a.sem-sessoes') && !document.querySelector('.sessoes')), 'sessões escondidas: o bloco sai e o player ocupa o espaço');
  await h.foto(p, 'estado-sem-bloco-sessoes');
  await h.cenario({ blocos: { sessoes: true, uso: false } });
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a.sem-uso') && !document.querySelector('.cartao.uso') && !!document.querySelector('.sessoes')), 'uso escondido: o cartão sai');
  await h.cenario({ blocos: { uso: true, spotify: false } });
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a.sem-musica') && !document.querySelector('.comp-a.sem-uso')), 'Spotify escondido: some como o Spotify fechado');
  await p.context().close(); await h.reset();

  /* muitas teclas: carrossel com pontinhos */
  await h.cenario({ teclas: 'muitas' });
  p = await h.pagina(); await h.espera(p, () => !!document.querySelector('.comp-a .faixa'));
  v = await p.evaluate(() => ({ pag: document.querySelectorAll('.pagina').length, pontos: document.querySelectorAll('.divisor.com-pontos .ponto').length, teclas: document.querySelectorAll('.pagina .tecla').length, menu: document.querySelectorAll('.menu-area .tecla.menu').length }));
  h.ok(v.pag === 3 && v.pontos === 3 && v.teclas === 12 && v.menu === 1, `12 teclas na A: 3 páginas, 3 pontinhos e o Menu à parte (${JSON.stringify(v)})`);
  await p.evaluate(() => { const g = document.querySelector('.paginas'); g.scrollTo({ left: g.clientWidth, behavior: 'instant' }) }); await h.dormir(400);
  v = await p.evaluate(() => parseFloat(document.querySelector('.divisor .indicador').style.top) > 0);
  h.ok(v, 'rolar o carrossel move o indicador dos pontinhos');
  await h.foto(p, 'estado-muitas-teclas');
  await p.context().close(); await h.reset();
}
