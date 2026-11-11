// Leva 2 do painel (11/11/2026): agenda com arrastar que segue o dedo, setas de 44 pt e "Entrar na reunião",
// e "Abrir no Mac" na sessão aberta. Cada item com foto deitado (932x430) e em pé (430x932).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aviso = p => p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, visivel: document.querySelector('#aviso').classList.contains('visivel'), erro: document.querySelector('#aviso').classList.contains('erro') }));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
// 44 pt da tatile, na escala em que a tela do painel é desenhada no aparelho
const alvo44 = (p, sel) => p.evaluate(s => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, b = document.querySelector(s).getBoundingClientRect(); return { l: Math.round(b.width / k), a: Math.round(b.height / k) } }, sel);

export default async function (h) {
  /* ---------- Agenda: setas com 44 pt ---------- */
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]');
  await h.espera(p, () => document.querySelectorAll('#ca-grade .sb-dia').length > 27);
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    await p.setViewportSize({ width: w, height: alt }); await h.dormir(400);
    for (const id of ['#ca-ant', '#ca-prox']) { const a = await alvo44(p, id); h.ok(a.l >= 44 && a.a >= 44, `${nome}: a seta ${id} tem alvo de toque de ${a.l}x${a.a} pt (mínimo 44)`) }
  }
  await p.setViewportSize({ width: 932, height: 430 }); await h.dormir(400);

  /* ---------- Agenda: o mês segue o dedo ---------- */
  const caixa = await p.locator('#ca-mes').boundingBox(), y = caixa.y + caixa.height / 2, xIni = caixa.x + caixa.width - 40;
  const mes = () => p.evaluate(() => ({ titulo: document.querySelector('#ca-titulo').textContent, t: getComputedStyle(document.querySelector('#ca-mes')).translate, o: +getComputedStyle(document.querySelector('#ca-mes')).opacity }));
  const titulo0 = await texto(p, '#ca-titulo');
  await p.mouse.move(xIni, y); await p.mouse.down(); await p.mouse.move(xIni - 40, y, { steps: 5 }); await h.dormir(80);
  let m = await mes();
  h.ok(m.titulo === titulo0 && parseFloat(m.t) <= -35 && parseFloat(m.t) >= -45 && m.o < 1, `arrastando 40 px, o mês anda 40 px com o dedo (${m.t}), mais claro (${m.o.toFixed(2)}), e ainda é ${m.titulo}`);
  await p.mouse.move(xIni - 90, y, { steps: 5 }); await h.dormir(80);
  m = await mes();
  h.ok(parseFloat(m.t) <= -85 && parseFloat(m.t) >= -95, `e continua indo com o dedo (${m.t})`);
  await p.mouse.move(xIni - 20, y, { steps: 5 }); await p.mouse.up(); await h.dormir(500);
  m = await mes();
  h.ok(m.titulo === titulo0 && (m.t === 'none' || parseFloat(m.t) === 0) && m.o === 1, `soltando perto (20 px), o mês volta para o lugar e não troca (${m.titulo}, ${m.t}, opacidade ${m.o})`);
  await p.mouse.move(xIni, y); await p.mouse.down(); await p.mouse.move(xIni - 70, y, { steps: 5 }); await p.mouse.up(); await h.dormir(500);
  h.ok((await mes()).titulo !== titulo0, 'soltando passado de 60 px para a esquerda, vai para o mês seguinte');
  const titulo1 = await texto(p, '#ca-titulo'), x0 = caixa.x + 40;
  await p.mouse.move(x0, y); await p.mouse.down(); await p.mouse.move(x0 + 80, y, { steps: 5 }); await p.mouse.up(); await h.dormir(500);
  h.ok((await mes()).titulo === titulo0 && titulo1 !== titulo0, 'e para a direita volta ao mês de antes');
  await p.mouse.move(x0, y); await p.mouse.down(); await p.mouse.move(x0 + 25, y + 90, { steps: 6 }); await p.mouse.up(); await h.dormir(400);
  m = await mes();
  h.ok(m.titulo === titulo0 && (m.t === 'none' || parseFloat(m.t) === 0), 'arrasto na vertical não mexe no mês');
  // um arrasto que começa em cima de um dia não escolhe esse dia
  const sel0 = await p.evaluate(() => document.querySelector('#ca-grade .sb-dia.sel')?.textContent ?? null);
  const dia = await p.locator('#ca-grade .sb-dia').nth(14).boundingBox();
  await p.mouse.move(dia.x + dia.width / 2, dia.y + dia.height / 2); await p.mouse.down(); await p.mouse.move(dia.x - 120, dia.y + dia.height / 2, { steps: 6 }); await p.mouse.up(); await h.dormir(600);
  const titulo2 = await texto(p, '#ca-titulo');
  await p.mouse.move(x0, y); await p.mouse.down(); await p.mouse.move(x0 + 90, y, { steps: 5 }); await p.mouse.up(); await h.dormir(500);
  h.ok(titulo2 !== titulo0 && await texto(p, '#ca-titulo') === titulo0 && await p.evaluate(() => document.querySelector('#ca-grade .sb-dia.sel')?.textContent ?? null) === sel0, 'um arrasto que começa em cima de um dia troca o mês e não escolhe aquele dia');
  // tocar num dia continua escolhendo o dia
  const dia2 = await p.locator('#ca-grade .sb-dia:not(.hoje)').nth(20);
  await dia2.click(); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia.sel').length === 1), 'tocar num dia (sem arrastar) ainda o escolhe');
  await p.context().close();

  /* ---------- Agenda: Entrar na reunião (Meet, Zoom, Teams) ---------- */
  await h.reset(); await h.cenario({ reunioes: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]');
  await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 3);
  const abrirEvento = async titulo => { await p.locator(`#ca-lista .ev-linha:has(b:text-is("${titulo}"))`).first().click(); await h.dormir(250) };
  const botao = '#ca-lista [data-ev-reuniao]';
  await abrirEvento('Reunião de produto');
  h.ok(await p.locator(botao).count() === 1 && await texto(p, botao) === 'Entrar na reunião', 'evento com link de Meet mostra o botão "Entrar na reunião"');
  const a44 = await alvo44(p, botao);
  h.ok(a44.a >= 44, `o botão tem ${a44.a} pt de altura (mínimo 44)`);
  h.ok(await p.evaluate(() => !!document.querySelector('#ca-lista [data-ev-mac]')), 'e o "Abrir no Calendário do Mac" continua ao lado');
  await p.locator(botao).scrollIntoViewIfNeeded(); await h.dormir(200); await h.foto(p, 'agenda-reuniao');
  await p.click(botao); await h.dormir(300);
  let c = await h.contadores();
  h.ok(c.reunioes.join() === 'https://meet.google.com/abc-defg-hij' && c.botoes.length === 0, `o toque manda o link do Meet ao Mac, sem acionar tecla (${c.reunioes.join()})`);
  h.ok((await aviso(p)).txt === 'Abrindo a reunião no Mac', 'e o aviso diz que abre no Mac');
  await abrirEvento('Revisão do projeto');
  h.ok(await texto(p, '#ca-lista .ev-linha[aria-expanded="true"] .tx span') === 'Trabalho, Zoom', `quando o "local" é o próprio link, a linha mostra o serviço e não o endereço (${await texto(p, '#ca-lista .ev-linha[aria-expanded="true"] .tx span')})`);
  await p.click(botao); await h.dormir(300);
  await abrirEvento('Gravação do podcast'); await p.click(botao); await h.dormir(300);
  c = await h.contadores();
  h.ok(c.reunioes.length === 3 && c.reunioes[1].startsWith('https://us02web.zoom.us/j/81234567890') && c.reunioes[2].startsWith('https://teams.microsoft.com/'), `Zoom e Teams também mandam o link (${c.reunioes.length} pedidos)`);
  await abrirEvento('Ensaio do louvor');
  h.ok(await p.locator(botao).count() === 0, 'evento sem link de reunião não mostra o botão');
  for (const [w, alt, nome] of [[430, 932, 'em pé']]) {
    await p.setViewportSize({ width: w, height: alt }); await h.dormir(400);
    await abrirEvento('Reunião de produto'); await h.dormir(300); await h.foto(p, 'agenda-reuniao-em-pe');
    h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1 && document.querySelector('#ca-lista [data-ev-reuniao]').getBoundingClientRect().right <= innerWidth), `${nome}: o botão cabe na tela`);
  }
  await p.context().close();

  /* o Mac recusa: o aviso traz o motivo */
  await h.reset(); await h.cenario({ reunioes: true, reuniaoRecusa: 'O Mac não conseguiu abrir o link da reunião.' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 3);
  await p.locator('#ca-lista .ev-linha:has(b:text-is("Reunião de produto"))').first().click(); await h.dormir(250);
  await p.click(botao); await h.dormir(400);
  let a = await aviso(p);
  h.ok(a.erro && a.txt === 'O Mac não conseguiu abrir o link da reunião.', `Mac que não abre: o aviso de erro traz o motivo (${a.txt})`);
  await p.context().close();

  /* Mac antigo (sem link no evento) e link que não é de reunião: nada de botão */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 3);
  await p.locator('#ca-lista .ev-linha:has(b:text-is("Reunião de produto"))').first().click(); await h.dormir(250);
  h.ok(await p.locator(botao).count() === 0, 'Mac que ainda não manda o link: o evento abre sem o botão e sem erro');
  const falso = await p.evaluate(() => ['https://golpe.com/meet.google.com/x', 'http://meet.google.com/abc', 'javascript:alert(1)', 'https://meet.google.com.golpe.com/abc', ''].map(l => reuniaoDe({ link: l })));
  h.ok(falso.every(r => r === null), 'link fora do Meet, do Zoom e do Teams (ou sem https) nunca vira botão');
  await p.context().close();

  /* ---------- Sessões: Abrir no Mac ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await p.click('#se-lista [data-sessao="s1"]'); await h.dormir(700);
  h.ok(await texto(p, '#se-lista [data-sessao-mac]') === 'Abrir no Mac', 'a sessão aberta tem o botão "Abrir no Mac"');
  const b44 = await alvo44(p, '#se-lista [data-sessao-mac]');
  h.ok(b44.a >= 44, `o botão tem ${b44.a} pt de altura (mínimo 44)`);
  await h.foto(p, 'sessoes-abrir-no-mac');
  await p.click('#se-lista [data-sessao-mac]'); await h.dormir(300);
  c = await h.contadores();
  h.ok(c.sessoesAbertas.join() === 's1' && c.botoes.length === 0, `o toque pede ao Mac para abrir a sessão s1 (${c.sessoesAbertas.join()})`);
  h.ok((await aviso(p)).txt === 'Abrindo a sessão no Mac', 'e o aviso diz que abre no Mac');
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(500); await h.foto(p, 'sessoes-abrir-no-mac-em-pe');
  h.ok(await p.evaluate(() => { const b = document.querySelector('#se-lista [data-sessao-mac]').getBoundingClientRect(), r = document.querySelector('#se-rodape').getBoundingClientRect(); return b.right <= innerWidth && b.bottom <= r.top + 1 && document.documentElement.scrollWidth <= innerWidth + 1 }), 'em pé: o botão cabe e fica acima de Dispensar e Voltar');
  await p.context().close();

  /* sem terminal da sessão: o Mac abriu o Terminal na pasta e o aviso conta isso */
  await h.reset(); await h.cenario({ sessaoAbre: 'pasta' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await p.click('#se-lista [data-sessao="s2"]'); await h.dormir(500);
  await p.click('#se-lista [data-sessao-mac]'); await h.dormir(500);
  h.ok((await aviso(p)).txt === 'Não achei o terminal da sessão. Abri o Terminal na pasta do projeto', `sem terminal: o aviso diz que abriu o Terminal na pasta (${(await aviso(p)).txt})`);
  await p.context().close();

  /* o Mac recusa, ou a sessão já foi embora */
  await h.reset(); await h.cenario({ sessaoAbreRecusa: 'Não achei o terminal nem a pasta dessa sessão neste Mac.' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await p.click('#se-lista [data-sessao="s1"]'); await h.dormir(500);
  await p.click('#se-lista [data-sessao-mac]'); await h.dormir(500);
  a = await aviso(p);
  h.ok(a.erro && a.txt === 'Não achei o terminal nem a pasta dessa sessão neste Mac.', `o Mac recusa: o aviso de erro traz o motivo (${a.txt})`);
  h.ok(await p.evaluate(() => !!document.querySelector('#se-lista [data-sessao-mac]')), 'e o botão continua lá para tentar de novo');
  await p.context().close();

  /* ---------- Player grande: volume, curtir, aparelhos, fila e repetir só a música ---------- */
  const abrirPlayer = async (cenario, vista = {}) => {
    await h.reset(); await h.cenario({ atrasoAcao: 0, ...cenario });
    const q = await h.pagina(vista); await pronta(h, q); await h.dormir(400);
    await q.click('.player .capa');
    await h.espera(q, () => document.querySelector('#f-player').classList.contains('aberta') && !!document.querySelector('#f-player .capa-grande'), null, 2000);
    await h.dormir(700);
    return q;
  };
  const spot = async () => (await h.contadores()).spotify;
  const arrastar = async (q, sel, de, ate) => { const b = await q.locator(sel).boundingBox(), y2 = b.y + b.height / 2; await q.mouse.move(b.x + b.width * de, y2); await q.mouse.down(); await q.mouse.move(b.x + b.width * ate, y2, { steps: 6 }); await q.mouse.up() };

  /* Mac antigo: nada de novo aparece */
  p = await abrirPlayer({ spotifyExtras: 'nao' });
  h.ok(await p.evaluate(() => !document.querySelector('#f-player .pc-extras')), 'Mac que não manda volume nem login: o player grande não ganha nada');
  await p.context().close();

  /* sem login: só o volume, e nada que dependa dele */
  p = await abrirPlayer({ spotifyExtras: 'volume' });
  h.ok(await p.evaluate(() => !!document.querySelector('#f-player .pc-extras .volume') && !document.querySelector('#f-player [data-curtir], #f-player [data-aparelhos], #f-player [data-fila], #f-player .vol-alvo')), 'sem o Spotify conectado: só o volume aparece, sem curtir, aparelhos, fila nem troca de alvo');
  h.ok(await p.evaluate(() => document.querySelector('#f-player .volume .vol-num').textContent === '60'), 'o volume mostra o que o Mac mandou (60)');
  h.ok(await p.evaluate(() => document.querySelector('#f-player [data-midia="repetir"]').dataset.modo === undefined), 'e o repetir segue o liga e desliga de antes');
  await arrastar(p, '#f-player .volume .trilho', .6, .2); await h.dormir(400);
  c = await spot();
  h.ok(c.at(-1) === 'volume:spotify:20' && await texto(p, '#f-player .volume .vol-num') === '20', `arrastar a barra manda o volume do Spotify ao Mac (${c.at(-1)}) e ela fica onde o dedo soltou`);
  h.ok(c.filter(x => x.startsWith('volume')).length <= 4, `sem inundar o Mac (${c.filter(x => x.startsWith('volume')).length} pedidos)`);
  h.ok(await p.evaluate(() => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, b = document.querySelector('#f-player .volume .trilho').getBoundingClientRect(); return (b.height + 2 * 24 * k) / k >= 44 }), 'a área de toque da barra tem 44 pt de altura ou mais');
  // conectar o login numa aberta: a lista de aparelhos explica em vez de quebrar
  await p.evaluate(() => abrirListaPlayer('aparelhos')); await h.dormir(500);
  h.ok((await texto(p, '#pc-lista-corpo')).includes('Spotify não conectado') && (await texto(p, '#pc-lista-corpo')).includes('Conecte nos Ajustes do Mac.'), 'se a lista de aparelhos for pedida sem login, o Mac diz o motivo (409) e a tela mostra');
  await p.context().close();

  /* Spotify e Mac: o botão ao lado troca de quem é o volume */
  p = await abrirPlayer({ spotifyExtras: 'dois' });
  h.ok(await texto(p, '#f-player .vol-alvo') === 'Spotify' && await texto(p, '#f-player .volume .vol-num') === '60', 'com os dois volumes, a barra diz de quem é (Spotify, 60)');
  await p.click('#f-player [data-vol-alvo]'); await h.dormir(300);
  h.ok(await texto(p, '#f-player .vol-alvo') === 'Mac' && await texto(p, '#f-player .volume .vol-num') === '40', 'tocar no botão passa a barra para o volume do Mac (40)');
  await arrastar(p, '#f-player .volume .trilho', .4, .9); await h.dormir(400);
  c = await spot();
  h.ok(c.at(-1) === 'volume:mac:90', `e arrastar manda o volume do Mac (${c.at(-1)})`);
  await p.reload(); await pronta(h, p); await h.dormir(400); await p.click('.player .capa'); await h.dormir(900); // a escolha fica guardada no aparelho
  h.ok(await texto(p, '#f-player .vol-alvo') === 'Mac' && await texto(p, '#f-player .volume .vol-num') === '90', 'a escolha do volume fica guardada na próxima vez que abre o painel');
  await p.context().close();

  /* com login: curtir, aparelhos, fila e repetir só a música */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    p = await abrirPlayer({ spotifyExtras: 'login' }, { w, h: alt });
    const ex = await p.evaluate(() => ({ botoes: ['[data-curtir]', '[data-aparelhos]', '[data-fila]'].map(s => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, b = document.querySelector('#f-player ' + s)?.getBoundingClientRect(); return b ? [Math.round(b.width / k), Math.round(b.height / k)] : null }), noLimite: (() => { const f = document.querySelector('#f-player .pc-extras').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return f.right <= t.right + 1 && f.bottom <= t.bottom + 1 })(), vol: !!document.querySelector('#f-player .volume') }));
    h.ok(ex.botoes.every(b => b && b[0] >= 44 && b[1] >= 44) && ex.noLimite && ex.vol, `${nome}: com login aparecem volume, curtir, aparelhos e fila (alvos ${JSON.stringify(ex.botoes)}), tudo dentro da tela`);
    await h.dormir(300); await h.foto(p, nome === 'deitado' ? 'player-extras' : 'player-extras-em-pe');
    await p.context().close();
  }
  await h.reset(); await h.cenario({ spotifyExtras: 'login', atrasoAcao: 1200 });
  p = await h.pagina(); await pronta(h, p); await h.dormir(400);
  await p.click('.player .capa'); await h.dormir(800);
  let t0 = Date.now();
  await p.click('#f-player [data-curtir]');
  h.ok(await h.espera(p, () => document.querySelector('#f-player [data-curtir]').getAttribute('aria-pressed') === 'true', null, 700) && Date.now() - t0 < 700, `curtir: o coração acende no toque, com o Mac levando 1,2 s (${Date.now() - t0} ms)`);
  h.ok((await aviso(p)).txt === 'Curtida', 'e o aviso diz Curtida');
  await h.dormir(1900);
  h.ok((await spot()).at(-1) === 'curtir:1' && await p.evaluate(() => document.querySelector('#f-player [data-curtir]').getAttribute('aria-pressed') === 'true'), 'o Mac recebeu curtir:1 e o coração segue aceso depois do estado dele');
  await p.click('#f-player [data-curtir]'); await h.dormir(2200);
  h.ok((await spot()).at(-1) === 'curtir:0' && await p.evaluate(() => document.querySelector('#f-player [data-curtir]').getAttribute('aria-pressed') === 'false'), 'tocar de novo tira a curtida');
  await p.context().close();
  await h.reset(); await h.cenario({ spotifyExtras: 'login', spotifyRecusa: 'O Spotify não deixou curtir.', atrasoAcao: 300 });
  p = await h.pagina(); await pronta(h, p); await h.dormir(400); await p.click('.player .capa'); await h.dormir(800);
  await p.click('#f-player [data-curtir]');
  h.ok(await h.espera(p, () => document.querySelector('#f-player [data-curtir]').getAttribute('aria-pressed') === 'false' && document.querySelector('#aviso').classList.contains('erro'), null, 3000), 'curtir recusado pelo Mac: o coração apaga e o aviso traz o motivo');
  await p.context().close();

  /* repetir: nada, a lista, só a música */
  p = await abrirPlayer({ spotifyExtras: 'login' });
  const rep = () => p.evaluate(() => { const b = document.querySelector('#f-player [data-midia="repetir"]'); return { modo: b.dataset.modo, pressed: b.getAttribute('aria-pressed'), rot: b.getAttribute('aria-label'), pequeno: document.querySelector('.player [data-midia="repetir"]')?.dataset.modo }; });
  let r = await rep();
  h.ok(r.modo === 'nao' && r.pressed === 'false', `repetir começa desligado (${r.modo})`);
  await p.click('#f-player [data-midia="repetir"]'); await h.dormir(500); r = await rep();
  h.ok(r.modo === 'contexto' && r.pressed === 'true' && r.rot === 'Repetir a lista ou o álbum' && r.pequeno === 'contexto', `1º toque: repete a lista (${r.modo}), nos dois players`);
  await p.click('#f-player [data-midia="repetir"]'); await h.dormir(500); r = await rep();
  h.ok(r.modo === 'faixa' && r.pressed === 'true' && r.rot === 'Repetir só a música' && (await aviso(p)).txt === 'Repetir só a música', `2º toque: repete só a música (${r.modo}) e o aviso diz isso`);
  await h.foto(p, 'player-repetir-faixa');
  await p.click('#f-player [data-midia="repetir"]'); await h.dormir(500); r = await rep();
  h.ok(r.modo === 'nao' && r.pressed === 'false', `3º toque: desliga (${r.modo})`);
  c = await spot();
  h.ok(c.filter(x => x.startsWith('repetir')).join() === 'repetir:modo=contexto,repetir:modo=faixa,repetir:modo=nao', `o Mac recebeu os três modos, na ordem (${c.filter(x => x.startsWith('repetir')).join()})`);
  await p.context().close();

  /* aparelhos */
  p = await abrirPlayer({ spotifyExtras: 'login' });
  await p.click('#f-player [data-aparelhos]'); await h.dormir(600);
  h.ok(await texto(p, '#pc-lista-titulo') === 'Tocar em' && await p.evaluate(() => document.querySelectorAll('#pc-lista-corpo [data-aparelho]').length) === 4, 'aparelhos: a lista do Spotify vem do Mac, com os 4 aparelhos');
  const ap = await p.evaluate(() => [...document.querySelectorAll('#pc-lista-corpo [data-aparelho]')].map(b => [b.querySelector('b').textContent, b.querySelector('small').textContent, b.disabled, b.getAttribute('aria-pressed'), !!b.querySelector('.tag')]));
  h.ok(ap[0][0] === 'MacBook Pro de Teste' && ap[0][1] === 'Computador' && ap[0][3] === 'true' && ap[0][4] && ap[1][1] === 'Caixa de som' && ap[2][2] === true && ap[2][1].includes('o Spotify não deixa controlar'), `cada aparelho traz nome e tipo em português, o que toca agora marcado e o restrito desligado (${JSON.stringify(ap.map(a => a.slice(0, 2)))})`);
  h.ok(await p.evaluate(() => document.querySelectorAll('#pc-lista-corpo .volume-aparelho').length) === 1, 'o aparelho que toca ganha a barra do volume dele');
  await h.foto(p, 'player-aparelhos');
  await arrastar(p, '#pc-lista-corpo .volume-aparelho .trilho', .35, .8); await h.dormir(400);
  h.ok((await spot()).at(-1) === 'volume:aparelho:80', `arrastar a barra do aparelho manda volume:aparelho (${(await spot()).at(-1)})`);
  await h.cenario({ atrasoAcao: 1200 });
  t0 = Date.now(); await p.click('#pc-lista-corpo [data-aparelho="d-sala"]');
  h.ok(await h.espera(p, () => document.querySelector('#pc-lista-corpo [data-aparelho="d-sala"]').getAttribute('aria-pressed') === 'true' && document.querySelector('#pc-lista-corpo [data-aparelho="d-mac"]').getAttribute('aria-pressed') === 'false', null, 700) && Date.now() - t0 < 700, `escolher a caixa marca ela no toque, com o Mac levando 1,2 s (${Date.now() - t0} ms)`);
  h.ok((await aviso(p)).txt === 'Tocando em Caixa da sala', 'e o aviso diz onde toca');
  await h.dormir(2400);
  h.ok((await spot()).at(-1) === 'dispositivo:d-sala', 'o Mac recebeu dispositivo:d-sala');
  await p.click('#pc-lista-corpo [data-aparelho="d-tv"]', { force: true }).catch(() => {}); await h.dormir(300);
  h.ok((await spot()).at(-1) === 'dispositivo:d-sala', 'o aparelho que o Spotify não deixa controlar não manda nada');
  await p.click('#pc-lista [data-pc-voltar]'); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('#pc-lista').hidden) && await p.evaluate(() => !!document.querySelector('#f-player .capa-grande')), 'Voltar fecha a lista e mostra o player');
  await p.context().close();

  /* aparelhos que falham: motivo e Tentar de novo */
  p = await abrirPlayer({ spotifyExtras: 'login', aparelhosErro: 'O Spotify não respondeu.' });
  await p.click('#f-player [data-aparelhos]'); await h.dormir(600);
  h.ok((await texto(p, '#pc-lista-corpo')).includes('O Spotify não respondeu.') && await p.locator('#pc-lista-corpo [data-tentar]').count() === 1, 'lista de aparelhos que falha: mostra o motivo e "Tentar de novo"');
  await h.cenario({ aparelhosErro: '' }); await p.click('#pc-lista-corpo [data-tentar]'); await h.dormir(600);
  h.ok(await p.evaluate(() => document.querySelectorAll('#pc-lista-corpo [data-aparelho]').length) === 4, '"Tentar de novo" traz a lista');
  await p.context().close();

  /* fila */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    p = await abrirPlayer({ spotifyExtras: 'login' }, { w, h: alt });
    await p.click('#f-player [data-fila]'); await h.dormir(600);
    const fl = await p.evaluate(() => ({ titulo: document.querySelector('#pc-lista-titulo').textContent, grupos: [...document.querySelectorAll('#pc-lista-corpo h3')].map(x => x.textContent), itens: document.querySelectorAll('#pc-lista-corpo .item-lista').length, primeira: document.querySelector('#pc-lista-corpo .item-lista b').textContent }));
    h.ok(fl.titulo === 'Na fila' && fl.grupos.join() === 'Tocando agora,Próximas' && fl.itens === 10 && fl.primeira === 'Faixa de Exemplo', `${nome}: a fila mostra o que toca agora e as 9 próximas (${fl.itens} itens)`);
    if (nome === 'deitado') {
      const rolagem = await p.evaluate(() => { const e = document.querySelector('#pc-lista-corpo'); return { passa: e.scrollHeight > e.clientHeight + 20, semBarra: getComputedStyle(e).scrollbarWidth === 'none' } });
      h.ok(rolagem.passa && rolagem.semBarra, 'a fila longa rola sem barra visível');
    }
    await h.foto(p, nome === 'deitado' ? 'player-fila' : 'player-fila-em-pe');
    await h.cenario({ faixa: 'Outra Faixa' }); await h.dormir(1800);
    h.ok(await p.evaluate(() => document.querySelector('#pc-lista-corpo .item-lista b')?.textContent) !== undefined && (await h.contadores()).filas >= 2, `${nome}: a fila é lida de novo quando a música muda (${(await h.contadores()).filas} leituras)`);
    await p.context().close();
  }
  await h.reset(); await h.cenario({ spotifyExtras: 'login', filaVazia: true });
  p = await h.pagina(); await pronta(h, p); await h.dormir(400); await p.click('.player .capa'); await h.dormir(800);
  await p.click('#f-player [data-fila]'); await h.dormir(600);
  h.ok((await texto(p, '#pc-lista-corpo')).includes('A fila está vazia'), 'fila sem próximas: "A fila está vazia"');
  await p.context().close();

  /* texto com HTML vindo do Spotify não executa */
  await h.reset(); await h.cenario({ spotifyExtras: 'login', xss: true });
  p = await h.pagina(); await pronta(h, p); await h.dormir(400); await p.click('.player .capa'); await h.dormir(800);
  await p.click('#f-player [data-fila]'); await h.dormir(500); await p.click('#pc-lista [data-pc-voltar]'); await p.click('#f-player [data-aparelhos]'); await h.dormir(500);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#pc-lista img').length === 0), 'nome de aparelho e de música com HTML aparece como texto e não executa');
  await p.context().close();

  /* ---------- Editor de tecla: os apps do Mac de quem usa, com busca, ícone e ações ---------- */
  const centro = async (q, sel) => { const b = await q.locator(sel).boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 } };
  const tocar = async (q, sel) => { const c2 = await centro(q, sel); await q.mouse.click(c2.x, c2.y) }; // as teclas tremem no modo organizar: toque pelo ponto
  const gravadas = async () => (await h.contadores()).configsGravadas;
  const novaTecla = async q => {
    if (!await q.evaluate(() => document.querySelector('#tela').classList.contains('organizando'))) { const c2 = await centro(q, '.tecla[data-id="calendario"]'); await q.mouse.move(c2.x, c2.y); await q.mouse.down(); await h.dormir(650); await q.mouse.up() }
    await tocar(q, '.tecla.menu'); await h.espera(q, () => document.querySelector('#f-editor').classList.contains('aberta') && document.querySelectorAll('#ed-lista-apps [data-app-bundle]').length > 0); await h.dormir(300);
  };
  const editorAberto = q => q.evaluate(() => document.querySelector('#f-editor').classList.contains('aberta'));
  const ultimaGravada = async () => (await gravadas()).at(-1);
  const salvar = async () => { await p.click('#ed-salvar'); await h.dormir(500) };
  const escolherApp = async (nome) => { await p.locator(`#ed-lista-apps button:has(span:text-is("${nome}"))`).click(); await h.dormir(400) };
  const marcada = (sel) => p.evaluate(s2 => document.querySelector(s2)?.getAttribute('aria-checked') === 'true', sel);

  /* Mac que ainda não tem as rotas: a lista curta de sempre, sem erro */
  await h.reset(); await h.cenario({ apps: 'antigo' });
  p = await h.pagina(); await pronta(h, p);
  const c0 = await centro(p, '.tecla[data-id="calendario"]'); await p.mouse.move(c0.x, c0.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await tocar(p, '.tecla.menu'); await h.dormir(500);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ed-acao [data-app]').length === 8 && !document.querySelector('#ed-busca')), 'Mac sem as rotas de apps: o editor mostra a lista curta de sempre, sem busca');
  await p.context().close();

  /* a lista do Mac */
  await h.reset(); await h.cenario({ apps: 'normal' });
  p = await h.pagina(); await pronta(h, p);
  await novaTecla(p);
  const lista = await p.evaluate(() => [...document.querySelectorAll('#ed-lista-apps [data-app-bundle]')].map(b => [b.querySelector('span:not(.svg)').textContent, b.dataset.appBundle, b.querySelector('img')?.getAttribute('src') || 'svg', b.querySelector('img')?.getAttribute('loading')]));
  h.ok(lista.length === 11 && lista[0][0] === 'Navegador padrão' && lista[0][2] === 'svg' && lista.slice(1).map(a => a[0]).join() === 'Calculadora,Calendário,Finder,Google Chrome,Mail,Notas,Safari,Spotify,Terminal,WhatsApp', `a lista vem do Mac, de A a Z, com o Navegador padrão no começo (${lista.map(a => a[0]).join(', ')})`);
  h.ok(lista.slice(1).every(a => /^\/api\/apps\/[A-Za-z0-9.]+\/icone\?codigo=/.test(a[2]) && a[3] === 'lazy'), 'cada app mostra o ícone que o Mac entrega (carregado só quando aparece)');
  await h.foto(p, 'editor-apps');
  await p.fill('#ed-busca', 'CALEND'); await h.dormir(150);
  h.ok(await p.evaluate(() => [...document.querySelectorAll('#ed-lista-apps [data-app-bundle] span')].map(x => x.textContent).join()) === 'Calendário', 'a busca acha sem ligar para caixa nem acento ("CALEND" acha Calendário)');
  await p.fill('#ed-busca', 'navega'); await h.dormir(150);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ed-lista-apps [data-app-bundle]').length) === 1, 'a busca também acha o Navegador padrão');
  await p.fill('#ed-busca', 'xyzxyz'); await h.dormir(150);
  h.ok((await texto(p, '#ed-lista-apps')) === 'Nenhum app com esse nome.', 'sem resultado: "Nenhum app com esse nome."');
  await p.fill('#ed-busca', ''); await h.dormir(150);

  /* as 3 teclas do Mail, cada uma numa conta */
  await h.cenario({ acoesAtraso: 1000 });
  await escolherApp('Mail');
  h.ok(await p.inputValue('#ed-nome') === 'Mail', 'escolher o app preenche o nome');
  h.ok((await texto(p, '#ed-acoes')).includes('Lendo o que o app oferece'), 'enquanto o Mac lê o que o Mail oferece, o editor avisa (e que o Mac pode pedir permissão)');
  await h.dormir(1300);
  const opcoes = await p.evaluate(() => [...document.querySelectorAll('#ed-acoes [data-acao-id]')].map(b => [b.textContent, b.getAttribute('aria-checked')]));
  h.ok(opcoes.map(o => o[0]).join() === 'Só abrir o app,Abrir a caixa de entrada de uma conta,Escrever um e-mail novo' && opcoes[0][1] === 'true', `o Mail oferece o que o Mac descobriu, com "Só abrir o app" marcado (${opcoes.map(o => o[0]).join(' | ')})`);
  await h.cenario({ acoesAtraso: 0 });
  await p.click('#ed-acoes [data-acao-id="mail-caixa"]'); await h.dormir(200);
  const contas = await p.evaluate(() => [...document.querySelectorAll('#ed-acoes [data-acao-valor]')].map(b => b.textContent));
  h.ok(contas.join() === 'iCloudmaria@icloud.com,Trabalhomaria@empresa.com.br,Pessoalmaria@gmail.com', `a ação mostra as contas do Mac (${contas.join(' | ')})`);
  await h.foto(p, 'editor-mail-contas');
  await salvar();
  h.ok((await gravadas()).length === 0 && await editorAberto(p) && (await aviso(p)).erro && (await aviso(p)).txt === 'Escolha: conta', `salvar sem escolher a conta não grava, e o aviso diz o que falta (${(await aviso(p)).txt})`);
  for (const [conta, nome, valor] of [['iCloud', 'Mail iCloud', 'conta-1'], ['Trabalho', 'Mail Trabalho', 'conta-2'], ['Pessoal', 'Mail Pessoal', 'conta-3']]) {
    if ((await gravadas()).length > 0) await novaTecla(p), await escolherApp('Mail'), await p.click('#ed-acoes [data-acao-id="mail-caixa"]'), await h.dormir(200);
    await p.locator(`#ed-acoes [data-acao-valor="${valor}"]`).click(); await h.dormir(150);
    h.ok(await p.inputValue('#ed-nome') === nome, `escolher a conta ${conta} ajusta o nome (${await p.inputValue('#ed-nome')})`);
    await salvar();
    const ult = (await ultimaGravada())?.perfis[0].teclas.at(-1);
    h.ok(ult?.nome === nome && ult.tipo === 'app' && ult.valor === 'Mail' && ult.acao?.id === 'mail-caixa' && ult.acao.valor === valor, `grava a tecla ${nome} com a ação e a conta (${JSON.stringify(ult)})`);
    await h.dormir(300);
  }
  const mails = (await ultimaGravada()).perfis[0].teclas.filter(t => t.valor === 'Mail');
  h.ok(mails.length === 3 && new Set(mails.map(t => t.acao.valor)).size === 3, '3 teclas do Mail, cada uma numa conta');
  h.ok(await h.espera(p, ids => ids.every(id => document.querySelector(`.tecla[data-id="${id}"] img[src*="/api/apps/com.apple.mail/icone"]`)), mails.map(t => t.id), 4000), 'e as 3 teclas mostram o ícone do Mail que o Mac entregou');
  await h.foto(p, 'teclas-do-mail');

  /* editar uma tecla com ação: volta direto ao que ela faz, e voltar a "só abrir" tira a ação */
  const idMail = mails[1].id;
  await p.evaluate(id => abrirEditor(id), idMail); await h.espera(p, () => document.querySelector('#f-editor').classList.contains('aberta')); await h.dormir(700); // as 7 teclas passam de uma página do carrossel: abre pelo id
  h.ok(await p.evaluate(() => !!document.querySelector('#ed-acao .app-escolhido') && document.querySelector('#ed-acao .app-escolhido b').textContent === 'Mail' && !document.querySelector('#ed-busca')), 'editar uma tecla de app abre no passo do que ela faz, com o app e "Trocar"');
  h.ok(await marcada('#ed-acoes [data-acao-id="mail-caixa"]') && await marcada('#ed-acoes [data-acao-valor="conta-2"]') && await p.inputValue('#ed-nome') === 'Mail Trabalho', 'a ação e a conta que estavam gravadas vêm marcadas, e o nome fica como estava');
  await p.click('#ed-acoes [data-acao-id=""]'); await h.dormir(150); await salvar();
  let ed = (await ultimaGravada()).perfis[0].teclas.find(t => t.id === idMail);
  h.ok(ed && !('acao' in ed) && ed.valor === 'Mail', `voltar a "Só abrir o app" tira a ação da tecla (${JSON.stringify(ed)})`);

  /* ação com texto (Safari: um endereço) e o navegador padrão */
  await h.dormir(300); await novaTecla(p); await escolherApp('Safari'); await h.dormir(300);
  await p.click('#ed-acoes [data-acao-id="link"]'); await h.dormir(150);
  h.ok(await p.getAttribute('#ed-acao-texto', 'placeholder') === 'https://github.com' && (await texto(p, '#ed-acoes')).includes('Endereço'), 'ação de endereço mostra o campo com o exemplo do Mac');
  await salvar();
  h.ok(await editorAberto(p) && (await aviso(p)).txt === 'Preencha: endereço', `endereço vazio não grava (${(await aviso(p)).txt})`);
  await p.fill('#ed-acao-texto', 'github.com'); await salvar();
  ed = (await ultimaGravada()).perfis[0].teclas.at(-1);
  h.ok(ed.valor === 'Safari' && ed.acao?.id === 'link' && ed.acao.valor === 'github.com', `grava o endereço digitado (${JSON.stringify(ed.acao)})`);
  await h.dormir(300); await novaTecla(p); await p.locator('#ed-lista-apps button:has(span:text-is("Navegador padrão"))').click(); await h.dormir(400);
  h.ok(await p.evaluate(() => [...document.querySelectorAll('#ed-acoes [data-acao-id]')].map(b => b.dataset.acaoId).join()) === ',link,gmail', 'o Navegador padrão oferece endereço e Gmail');
  await p.click('#ed-acoes [data-acao-id="gmail"]'); await p.fill('#ed-acao-texto', '1'); await salvar();
  ed = (await ultimaGravada()).perfis[0].teclas.at(-1);
  h.ok(ed.valor === 'navegador-padrao' && ed.acao?.id === 'gmail' && ed.acao.valor === '1' && ed.nome === 'Navegador padrão', `grava a tecla do navegador padrão (${JSON.stringify(ed)})`);
  await p.context().close();

  /* trocar o tipo de uma tecla com ação para outro tipo não leva a ação junto (o Mac recusaria) */
  await h.reset(); await h.cenario({ apps: 'normal' });
  p = await h.pagina(); await pronta(h, p);
  await novaTecla(p); await escolherApp('Safari'); await p.click('#ed-acoes [data-acao-id="link"]'); await p.fill('#ed-acao-texto', 'github.com');
  await p.click('#ed-tipo [data-tipo="comando"]'); await h.dormir(200);
  await p.fill('#ed-valor', 'echo oi'); await p.fill('#ed-nome', 'Oi'); await salvar();
  ed = (await ultimaGravada())?.perfis[0].teclas.at(-1);
  h.ok(ed?.tipo === 'comando' && ed.valor === 'echo oi' && !('acao' in ed), `a tecla de comando sai sem ação (${JSON.stringify(ed)})`);
  await p.context().close();

  /* o Mac não consegue ler as contas do Mail: o motivo aparece e nada quebra */
  await h.reset(); await h.cenario({ apps: 'normal', mailAviso: 'O Deck não tem permissão para controlar o Mail. Libere em Ajustes do Sistema > Privacidade e Segurança > Automação.' });
  p = await h.pagina(); await pronta(h, p);
  await novaTecla(p); await escolherApp('Mail'); await p.click('#ed-acoes [data-acao-id="mail-caixa"]'); await h.dormir(200);
  h.ok((await texto(p, '#ed-acoes')).includes('O Deck não tem permissão para controlar o Mail.') && await p.locator('#ed-acoes [data-acao-valor]').count() === 0, 'sem permissão no Mail: o aviso do Mac aparece no lugar das contas');
  await p.context().close();

  /* app que o Mac não conhece (a tecla ficou de outra época): o editor não quebra */
  await h.reset(); await h.cenario({ apps: 'normal' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => { rasc = { id: 'x', nome: 'Antigo', tipo: 'app', valor: 'AppQueSumiu', icone: 'AppQueSumiu' }; editando = 'x'; iniciarEditorApp(false); pintarTipo(); abrirFolha('#f-editor') });
  await h.dormir(700);
  h.ok((await texto(p, '#ed-acoes')).includes('Esse app não foi achado neste Mac') && await p.locator('#ed-acao .app-escolhido b').textContent() === 'AppQueSumiu', 'tecla de um app que não está mais no Mac: o editor avisa e deixa trocar');
  await p.context().close();

  /* a lista do Mac falha: lista curta, motivo e Tentar de novo */
  await h.reset(); await h.cenario({ apps: 'erro' });
  p = await h.pagina(); await pronta(h, p);
  const c1 = await centro(p, '.tecla[data-id="calendario"]'); await p.mouse.move(c1.x, c1.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await tocar(p, '.tecla.menu'); await h.dormir(700);
  h.ok((await texto(p, '#ed-acao')).includes('Não deu para ler os apps do Mac') && await p.locator('#ed-acao [data-app]').count() === 8 && await p.locator('[data-apps-tentar]').count() === 1, 'a lista do Mac falhando: aviso, a lista curta e "Tentar de novo"');
  await h.cenario({ apps: 'normal' }); await p.click('[data-apps-tentar]'); await h.dormir(700);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ed-lista-apps [data-app-bundle]').length) === 11, '"Tentar de novo" traz a lista do Mac');
  await p.context().close();

  /* muitos apps: a lista rola sem barra, e o editor cabe nas duas posições */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    await h.reset(); await h.cenario({ apps: 'muitos' });
    p = await h.pagina({ w, h: alt }); await pronta(h, p);
    await novaTecla(p); await h.dormir(700); // a folha termina de subir
    const rol = await p.evaluate(() => { const e = document.querySelector('#ed-lista-apps'), f = document.querySelector('#f-editor').getBoundingClientRect(); return { passa: e.scrollHeight > e.clientHeight + 20, semBarra: getComputedStyle(e).scrollbarWidth === 'none', dentro: f.left >= 0 && f.right <= innerWidth + 1 && f.top >= 0 && f.bottom <= innerHeight + 1 && e.getBoundingClientRect().bottom <= innerHeight, n: e.querySelectorAll('[data-app-bundle]').length }; });
    h.ok(rol.n === 141 && rol.passa && rol.semBarra && rol.dentro, `${nome}: 140 apps, a lista rola sem barra e o editor cabe (${JSON.stringify(rol)})`);
    await h.foto(p, nome === 'deitado' ? 'editor-apps-muitos' : 'editor-apps-em-pe');
    await escolherApp('Mail').catch(() => {});
    await p.fill('#ed-busca', 'mail').catch(() => {});
    await p.context().close();
  }
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    await h.reset(); await h.cenario({ apps: 'normal' });
    p = await h.pagina({ w, h: alt }); await pronta(h, p);
    await novaTecla(p); await escolherApp('Mail'); await p.click('#ed-acoes [data-acao-id="mail-caixa"]'); await h.dormir(300);
    await p.locator('#ed-acoes [data-acao-valor="conta-2"]').click(); await h.dormir(200);
    h.ok(await p.evaluate(() => { const f = document.querySelector('#f-editor').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return f.right <= t.right + 1 && f.bottom <= t.bottom + 1 && document.documentElement.scrollWidth <= innerWidth + 1 }), `${nome}: o editor com a ação do Mail cabe na tela`);
    await h.foto(p, nome === 'deitado' ? 'editor-mail-conta' : 'editor-mail-conta-em-pe');
    await p.context().close();
  }
}
