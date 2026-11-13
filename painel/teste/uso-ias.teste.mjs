// Tela "Uso das IAs" (13/11/2026): tocar no bloco de uso abre uma folha com uma seção por conta, o filtro Dia, Semana e Mês, o
// gasto de tokens com gráfico por dia, divisão por modelo e custo estimado, e as janelas de limite com o ritmo e quando renova.
// Todos os números vêm do Mac de mentira (servidor-falso.mjs, rota /api/uso/detalhe), nada de dado real.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.cartao.uso, .uso-tira'));
const aberta = p => p.evaluate(() => document.querySelector('#f-uso').classList.contains('aberta'));
const cheia = (h, p) => h.espera(p, () => !!document.querySelector('#us-corpo .us-conta'));
const txt = (p, sel) => p.evaluate(s => (document.querySelector(s)?.textContent || '').replace(/\s+/g, ' ').trim(), sel);
async function dedo(p, ctx, de, para, { passos = 12, espera = 20 } = {}) {
  const c = await ctx.newCDPSession(p);
  await c.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [de] });
  for (let i = 1; i <= passos; i++) { await c.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: de.x + (para.x - de.x) * i / passos, y: de.y + (para.y - de.y) * i / passos }] }); await p.waitForTimeout(espera) }
  await c.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

export default async function (h) {
  /* ---------- deitado: o toque no cartão abre a folha, sem mandar nada ao Mac ---------- */
  const ctx = await h.novoContexto({ hasTouch: true });
  let p = await h.pagina({ ctx }); await pronta(h, p);
  h.ok(await p.evaluate(() => !!document.querySelector('.cartao.uso[data-abrir-uso][role="button"]')), 'o bloco de uso é um botão (cartão deitado)');
  h.ok(/Ver detalhes/.test(await p.evaluate(() => document.querySelector('.cartao.uso').getAttribute('aria-label'))), 'o botão diz o que faz e lê os números');
  await p.click('.cartao.uso');
  h.ok(await h.espera(p, () => document.querySelector('#f-uso').classList.contains('aberta')) && await cheia(h, p), 'tocar no bloco de uso abre a folha Uso das IAs');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0 && c.usoDetalhe[0] === 'semana', `abre na Semana e não manda tecla ao Mac (pedidos: ${c.usoDetalhe})`);
  h.ok(await txt(p, '#us-titulo') === 'Uso das IAs', 'título Uso das IAs');
  const secoes = await p.evaluate(() => [...document.querySelectorAll('#us-corpo .us-conta h3')].map(x => x.textContent.replace(/\s+/g, ' ').trim()));
  h.ok(secoes.join('|') === 'Claude leo|Claude equipe|Codex pro|Claude neste Mac', `uma seção por conta, e o Claude somado deste Mac (${secoes.join('|')})`);
  h.ok(await p.evaluate(() => [...document.querySelectorAll('#us-filtro button')].map(b => b.textContent + ':' + b.getAttribute('aria-pressed')).join(' ')) === 'Dia:false Semana:true Mês:false', 'filtro Dia, Semana e Mês, com a Semana marcada');
  h.ok(/O Claude não diz de qual conta/.test(await txt(p, '.us-aviso')), 'o cartão do Mac explica por que o Claude vem somado');
  await h.dormir(800);

  /* ---------- janelas de limite: número, ritmo, renova, medido ---------- */
  const leo = '[data-c="0.j0"]';
  h.ok(await txt(p, `${leo} .us-num`) === '61%', `Claude leo: 61% usados (${await txt(p, `${leo} .us-num`)})`);
  h.ok(await txt(p, `${leo} .mn-tag`) === 'usado' && /^Renova em /.test(await txt(p, `${leo} .us-renova`)), 'diz que é usado e quando renova (contagem regressiva)');
  h.ok(/Medido há \d+ min/.test(await txt(p, leo)), `diz há quanto tempo o Mac mediu (${await txt(p, leo)})`);
  h.ok(/Passa do limite antes de renovar/.test(await txt(p, '[data-c="1.j0"]')) && /Esperado agora: 50%/.test(await txt(p, '[data-c="1.j0"]')), 'o ritmo avisa quando vai estourar antes de renovar, com o esperado de agora');
  h.ok(/Vai sobrar/.test(await txt(p, '[data-c="2.j1"]')), 'o ritmo avisa quando vai sobrar');
  h.ok(await p.evaluate(() => document.querySelector('[data-c="1.j0"]').classList.contains('cheio') && document.querySelector('[data-c="0.j0"]').classList.contains('alto') === false), '94% fica vermelho, 61% não');
  h.ok(await p.evaluate(() => !!document.querySelector('[data-c="0.j0"] .us-barra u:not([hidden])') && document.querySelector('[data-c="0.j0"] .us-barra u').style.left === '55%'), 'a marca do ritmo fica no esperado de agora (55%)');
  h.ok(await txt(p, '[data-c="2.j0"] .mn-rot') === '5 horas' && await txt(p, '[data-c="2.j1"] .mn-rot') === 'Semana', 'o Codex mostra a janela de 5 horas e a semanal');
  // toque no número: usado vira resta, e o número conta até o novo
  await p.click(`${leo} [data-us-resta]`);
  await h.dormir(300);
  const meio = parseInt(await txt(p, `${leo} .us-num`));
  h.ok(meio > 39 && meio < 61, `o número anima do antigo ao novo, não pula (${meio})`);
  await h.dormir(700);
  h.ok(await txt(p, `${leo} .us-num`) === '39%' && await txt(p, `${leo} .mn-tag`) === 'resta', 'toque alterna para o que resta (39%)');
  h.ok(/39% restam/.test(await p.evaluate(s => document.querySelector(s).getAttribute('aria-label'), leo)), 'o rótulo de acessibilidade também fala em restam');
  await p.click(`${leo} [data-us-hora]`);
  h.ok(/^Renova \w+, \d\d\/\d\d, \d\d:\d\d$/.test(await txt(p, `${leo} .us-renova`)), `toque na renovação mostra a hora exata (${await txt(p, `${leo} .us-renova`)})`);
  await p.click(`${leo} [data-us-resta]`); await p.click(`${leo} [data-us-hora]`); await h.dormir(900);

  /* ---------- gasto de tokens: Codex tem por conta, o Claude vem somado ---------- */
  h.ok(await p.evaluate(() => ['0.g', '1.g'].every(k => !document.querySelector(`[data-c="${k}.tok"]`))) && await p.evaluate(() => !!document.querySelector('[data-c="2.g.tok"]') && !!document.querySelector('[data-c="mac.g.tok"]')), 'tokens só no Codex e no Claude deste Mac (o log do Claude não diz a conta)');
  const tokSemana = await txt(p, '[data-c="mac.g.tok"] .us-num');
  h.ok(/\d.*(mi|bi)$/.test(tokSemana), `o total de tokens vem compacto (${tokSemana})`);
  h.ok(/^US\$ [\d.,]+$/.test(await txt(p, '[data-c="mac.g.usd"] .us-num')) && /Estimado, falta preço/.test(await txt(p, '[data-c="mac.g.usd"]')), 'o custo diz que é estimado e que falta preço de um modelo');
  h.ok(/Entrada.*Saída.*Cache lido.*Cache escrito/.test(await txt(p, '[data-c="mac.g.tipos"]')), 'tokens por tipo: entrada, saída, cache lido e cache escrito');
  const g = await p.evaluate(() => { const b = [...document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i')]; return { n: b.length, rotulo: document.querySelector('[data-c="mac.g.graf"]').getAttribute('aria-label'), eixo: document.querySelector('[data-c="mac.g.graf"] .us-eixo').textContent, agora: b.filter(x => x.classList.contains('agora')).length } });
  h.ok(g.n === 7 && g.agora === 1 && /^[A-Z]{7}$/.test(g.eixo), `gráfico da semana: 7 barras, a de hoje destacada (${g.eixo})`);
  h.ok(/maior valor/.test(g.rotulo), 'o gráfico tem texto para o leitor de tela');
  const mods = await p.evaluate(() => [...document.querySelectorAll('[data-c="mac.g.modelos"] .us-modelo')].map(l => [...l.children].slice(0, 4).map(x => x.textContent).join(' ')));
  h.ok(mods.length === 3 && /^Opus 5\.5 60%/.test(mods[0]) && /^modelo-a 10% .* -$/.test(mods[2]), `divisão por modelo com parte e custo, sem dólar para modelo sem preço (${mods[2]})`);
  h.ok(/Gasto calculado há \d+ min/.test(await txt(p, '#us-rodape')) && /preço de API/.test(await txt(p, '#us-rodape')), 'o rodapé diz há quanto o gasto foi calculado e que o custo é estimativa');

  /* ---------- filtro Dia, Semana e Mês ---------- */
  await p.click('#us-filtro [data-p="dia"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i').length === 24 && document.querySelector('#us-filtro [data-p="dia"]').getAttribute('aria-pressed') === 'true'), 'Dia: gráfico por hora com 24 barras');
  h.ok(/0h.*12h.*23h/.test(await txt(p, '[data-c="mac.g.graf"] .us-eixo')), 'Dia: eixo em horas');
  await p.click('#us-filtro [data-p="mes"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('[data-c="mac.g.graf"] .us-grafico i').length === 30), 'Mês: gráfico com 30 barras');
  h.ok(/^\d\d\/\d\d.*\d\d\/\d\d.*\d\d\/\d\d$/.test(await txt(p, '[data-c="mac.g.graf"] .us-eixo')), 'Mês: eixo com datas');
  c = await h.contadores();
  h.ok(['dia', 'mes'].every(x => c.usoDetalhe.includes(x)), `cada filtro pede o seu período ao Mac (${c.usoDetalhe})`);
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('#us-corpo').scrollWidth <= document.querySelector('#us-corpo').clientWidth + 1), 'deitado, nada vaza para o lado');
  await h.foto(p, 'uso-ias-mes');
  await p.click('#f-uso .fechar'); await h.dormir(500);
  h.ok(!(await aberta(p)), 'o X fecha a folha');
  // a escolha fica no aparelho
  await p.click('.cartao.uso'); await cheia(h, p);
  h.ok(await p.evaluate(() => document.querySelector('#us-filtro [data-p="mes"]').getAttribute('aria-pressed')) === 'true', 'o período escolhido (Mês) volta na próxima vez que abrir');
  /* ---------- fechar puxando para baixo, como as outras telas ---------- */
  await h.dormir(800); // a folha termina de subir antes do dedo
  const b = await p.locator('#f-uso').boundingBox();
  await dedo(p, ctx, { x: b.x + b.width / 2, y: b.y + 120 }, { x: b.x + b.width / 2, y: b.y + 330 }, { espera: 30 }); await h.dormir(700);
  h.ok(!(await aberta(p)), 'puxar de cima para baixo fecha a folha');
  await p.close();

  /* ---------- em pé: a faixa de uso também abre, e nada vaza ---------- */
  await h.cenario({ usoDetalhe: 'normal' });
  const ctxP = await h.novoContexto({ hasTouch: true, viewport: { width: 430, height: 932 } });
  p = await h.pagina({ ctx: ctxP }); await pronta(h, p);
  h.ok(await p.evaluate(() => !!document.querySelector('.uso-tira[data-abrir-uso]')), 'em pé o bloco de uso é a faixa, e ela também é um botão');
  await p.click('.uso-tira'); await cheia(h, p); await h.dormir(900);
  h.ok(await aberta(p), 'em pé, tocar na faixa abre a folha');
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('#us-corpo').scrollWidth <= document.querySelector('#us-corpo').clientWidth + 1), 'em pé, nada vaza para o lado');
  const alvos = await p.evaluate(() => [...document.querySelectorAll('#us-filtro button, [data-us-resta], .fechar')].filter(e => e.closest('#f-uso')).map(e => Math.round(e.getBoundingClientRect().height)));
  h.ok(alvos.every(a => a >= 36), `os alvos de toque têm pelo menos 36 px (${[...new Set(alvos)]})`);
  await h.foto(p, 'uso-ias-em-pe');
  await p.close(); await ctxP.close();

  /* ---------- estados: calculando, vazio, erro, Mac antigo, sem medição ---------- */
  await h.cenario({ usoDetalhe: 'calculando' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso'); await cheia(h, p);
  h.ok(/Calculando o gasto de tokens/.test(await txt(p, '#us-rodape')), 'primeira varredura: avisa que está calculando');
  h.ok(await p.evaluate(() => /Nada neste período/.test(document.querySelector('[data-c="mac.g.tok"]').textContent)), 'sem gasto ainda, não inventa número');
  await p.close();
  await h.cenario({ usoDetalhe: 'vazio' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso'); await h.espera(p, () => /Nenhuma conta ligada/.test(document.querySelector('#us-corpo').textContent));
  h.ok(true, 'sem contas ligadas explica onde ligar'); await p.close();
  await h.cenario({ usoDetalhe: 'erro' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso');
  h.ok(await h.espera(p, () => /Não deu para ler|O Mac não conseguiu ler o uso/.test(document.querySelector('#us-corpo').textContent) && !!document.querySelector('#us-corpo [data-tentar]')), 'erro do Mac mostra o motivo e "Tentar de novo"');
  await h.cenario({ usoDetalhe: 'normal' }); await p.click('#us-corpo [data-tentar]');
  h.ok(await cheia(h, p), 'Tentar de novo traz a tela'); await p.close();
  await h.cenario({ usoDetalhe: 'antigo' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso');
  h.ok(await h.espera(p, () => /Este Mac ainda não tem o detalhe do uso/.test(document.querySelector('#us-corpo').textContent)), 'Mac antigo (404): pede para atualizar o Deck, sem erro estranho'); await p.close();
  await h.cenario({ usoDetalhe: 'normal', uso: 'sem-medicao' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso'); await cheia(h, p);
  h.ok(await p.evaluate(() => /Sem medição desta conta/.test(document.querySelector('[data-c="0.sem"]').textContent) && !document.querySelector('[data-c="0.j0"]')), 'conta sem medição diz isso, em vez de mostrar 0%'); await p.close();

  /* ---------- HTML vindo do Mac não executa ---------- */
  await h.cenario({ usoDetalhe: 'xss', uso: 'normal' });
  p = await h.pagina({ ctx }); await pronta(h, p); await p.click('.cartao.uso'); await cheia(h, p); await h.dormir(400);
  h.ok(await p.evaluate(() => window.__xss === undefined && !document.querySelector('#us-corpo img[onerror]')), 'nome de conta com HTML aparece como texto e não roda'); await p.close();

  /* ---------- organizando: o toque não abre a folha ---------- */
  await h.cenario({ usoDetalhe: 'normal' });
  p = await h.pagina({ ctx }); await pronta(h, p);
  await p.evaluate(() => entrarOrganizar()); await p.click('.cartao.uso', { force: true, position: { x: 200, y: 60 } }); await h.dormir(300);
  h.ok(!(await aberta(p)), 'no modo organizar, tocar no bloco de uso não abre a folha'); await p.close();

  /* ---------- a troca de período falha com dados na tela: nada fica apagado nem com o período errado ---------- */
  await h.cenario({ usoDetalhe: 'normal' });
  p = await h.pagina({ ctx }); await pronta(h, p);
  await p.click('.cartao.uso'); await cheia(h, p); await h.dormir(900);
  const antes = await p.evaluate(() => document.querySelector('#us-filtro button[aria-pressed="true"]').dataset.p), outro = antes === 'mes' ? 'dia' : 'mes';
  await h.cenario({ usoDetalhe: 'erro' });
  await p.click(`#us-filtro button[data-p="${outro}"]`);
  await h.dormir(900);
  h.ok(await p.evaluate(() => !document.querySelector('#us-corpo').classList.contains('us-carregando')), 'se a troca de período falha, os números não ficam apagados');
  h.ok(await p.evaluate(() => document.querySelector('#us-filtro button[aria-pressed="true"]')?.dataset.p) === antes, 'o filtro volta ao período dos números que seguem na tela');
  await h.cenario({ usoDetalhe: 'normal' }); await p.close();
  await ctx.close();
}
