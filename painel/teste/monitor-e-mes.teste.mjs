// Composição C (relógio quadrado estilo Fliqo, linha cinza e o mês da Agenda, sem fileira de teclas) e o monitor do Mac (12/11/2026).
const SEGURA = { horizontal: { l: 59, r: 873, t: 0, b: 409 }, vertical: { l: 0, r: 430, t: 59, b: 898 } };
const VISTAS = { horizontal: [932, 430], vertical: [430, 932] };
// tudo que passa da área segura (pixels da tela, já descontada a escala)
const estouros = (p, pos) => p.evaluate(([S]) => {
  const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth, ruins = [];
  for (const el of document.querySelectorAll('.relogio-linha, .data-linha, .cartao, .comp-c .placa, .mes-c, .c-divisor, .monitor-tira, .carrossel, .menu-area, .divisor, .pagina:first-child .tecla')) {
    const r = el.getBoundingClientRect(); if (!r.width || !r.height) continue;
    const q = { l: (r.left - t.left) / k, r: (r.right - t.left) / k, t: (r.top - t.top) / k, b: (r.bottom - t.top) / k };
    if (q.l < S.l - 1 || q.r > S.r + 1 || q.t < S.t - 1 || q.b > S.b + 1) ruins.push(`${el.className.split(' ').slice(0, 2).join('.')} ${JSON.stringify(Object.fromEntries(Object.entries(q).map(([a, b]) => [a, Math.round(b)])))}`);
  }
  if (document.documentElement.scrollWidth > innerWidth + 1 || document.documentElement.scrollHeight > innerHeight + 1) ruins.push('a página rola');
  return ruins;
}, [SEGURA[pos]]);
const aberta = (p, c, pos) => p.waitForFunction(([c, pos]) => !!document.querySelector(`.comp-${c === 'c' ? 'c' : c}`) && document.querySelector('#moldura').classList.contains(pos) && document.querySelectorAll('.placa').length >= 4, [c, pos], { timeout: 5000 }).then(() => true, () => false);

export default async function (h) {
  const p = await h.pagina();
  await p.waitForSelector('.comp-a .faixa', { timeout: 6000 }).catch(() => {});

  /* ---- composição C ---- */
  for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    await h.reset(); await h.cenario({ comp: 'c' });
    const certo = await aberta(p, 'c', pos); await h.dormir(1400);
    const g = await p.evaluate(() => {
      const r = s => document.querySelector(s)?.getBoundingClientRect(), pl = [...document.querySelectorAll('.comp-c .relogio-q .placa')].map(e => ({ q: e.getBoundingClientRect(), txt: e.querySelector('.cima span')?.textContent }));
      const hoje = document.querySelector('.mes-c .sb-dia.hoje'), agora = new Date();
      return { placas: pl, relogio: r('.comp-c .c-relogio'), div: r('.comp-c .c-divisor'), mes: r('.comp-c .mes-c'), teclas: document.querySelectorAll('.comp-c .tecla, .comp-c .teclas, #teclas').length,
        hoje: hoje?.textContent, diaDeHoje: String(agora.getDate()), dias: document.querySelectorAll('.mes-c .sb-dia').length, diasNoMes: new Date(agora.getFullYear(), agora.getMonth() + 1, 0).getDate(),
        hh: String(agora.getHours()).padStart(2, '0'), mm: String(agora.getMinutes()).padStart(2, '0'), titulo: document.querySelector('.mes-c h2')?.textContent, setas: document.querySelectorAll('.mes-c .seta').length,
        comEvento: document.querySelectorAll('.mes-c .sb-dia.tem').length, divisor: !!document.querySelector('.comp-c .c-divisor'), player: !!document.querySelector('.player'), sessoes: !!document.querySelector('.sessoes'), aA: !!document.querySelector('.comp-a') };
    });
    const [a, b2] = g.placas.map(x => x.q); // horas em cima, minutos embaixo
    h.ok(certo && g.placas.length === 2 && b2.top >= a.bottom - 2 && Math.abs(a.left - b2.left) < 2, `C ${pos}: o relógio tem dois blocos, as horas em cima e os minutos embaixo, alinhados`);
    h.ok(g.placas.every(x => Math.abs(x.q.width - x.q.height) < 2) && a.width >= 130, `C ${pos}: os blocos são quadrados (${Math.round(a.width)} x ${Math.round(a.height)})`);
    h.ok(g.placas[0].txt === g.hh && g.placas[1].txt === g.mm, `C ${pos}: o bloco de cima mostra a hora (${g.placas[0].txt}) e o de baixo os minutos (${g.placas[1].txt})`);
    h.ok(g.teclas === 0, `C ${pos}: sem a fileira de teclas`);
    h.ok(g.player === false && g.sessoes === false && g.aA === false, `C ${pos}: sem player, sem sessões`);
    h.ok(g.divisor && (pos === 'horizontal' ? g.div.width <= 2 && g.div.height > 200 && g.relogio.right <= g.div.left && g.div.right <= g.mes.left : g.div.height <= 2 && g.div.width > 200 && g.relogio.bottom <= g.div.top && g.div.bottom <= g.mes.top), `C ${pos}: uma linha cinza ${pos === 'horizontal' ? 'vertical' : 'horizontal'} divide o relógio do calendário`);
    h.ok(pos === 'horizontal' ? g.mes.left > g.relogio.right - 1 : g.mes.top >= g.relogio.bottom - 1, `C ${pos}: o calendário fica ${pos === 'horizontal' ? 'à direita' : 'abaixo'} do relógio`);
    h.ok(g.hoje === g.diaDeHoje && g.dias === g.diasNoMes && g.setas === 2, `C ${pos}: o mês tem os ${g.diasNoMes} dias, as duas setas e hoje (${g.diaDeHoje}) está marcado (marcado ${g.hoje}, dias ${g.dias})`);
    h.ok(g.comEvento >= 1, `C ${pos}: os dias com evento ganham o pontinho (${g.comEvento} dias)`);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0, `C ${pos}: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
    await h.foto(p, `c-${pos}`);
  }
  /* o calendário da C é o da Agenda: mesmo nome grande em vermelho, mesmos números e mesma marca de hoje */
  await p.setViewportSize({ width: 932, height: 430 });
  await h.reset(); await h.cenario({ comp: 'c' }); await aberta(p, 'c', 'horizontal'); await h.dormir(900);
  const estilo = sel => p.evaluate(s => { const e = document.querySelector(s), c = getComputedStyle(e); return { cor: c.color, tam: c.fontSize, peso: c.fontWeight, caixa: c.textTransform, fundo: c.backgroundColor, raio: c.borderRadius, larg: Math.round(e.getBoundingClientRect().width) } }, sel);
  const cTitulo = await estilo('.mes-c h2'), cDia = await estilo('.mes-c .sb-dia:not(.hoje):not(.fds)'), cHoje = await estilo('.mes-c .sb-dia.hoje'), cSemana = await estilo('.mes-c .sb-semana');
  const nomeC = await p.evaluate(() => document.querySelector('.mes-c h2').textContent);
  await p.click('.comp-c .mes-c-corpo');
  h.ok(await h.espera(p, () => document.querySelector('#f-cal')?.classList.contains('aberta')), 'C: tocar no mês abre a agenda');
  await h.dormir(600);
  const aTitulo = await estilo('#ca-titulo'), aDia = await estilo('#ca-grade .sb-dia:not(.hoje):not(.fds)'), aHoje = await estilo('#ca-grade .sb-dia.hoje'), aSemana = await estilo('.mes-sb .sb-semana');
  h.ok(cTitulo.cor === aTitulo.cor && cTitulo.caixa === 'uppercase' && aTitulo.caixa === 'uppercase' && cTitulo.peso === aTitulo.peso, `C: o nome do mês é vermelho, grande e em maiúsculas como na Agenda (${cTitulo.cor}, ${cTitulo.caixa})`);
  h.ok(parseFloat(cTitulo.tam) >= parseFloat(aTitulo.tam) * .9, `C: o nome do mês tem o tamanho do da Agenda (${cTitulo.tam} contra ${aTitulo.tam})`);
  h.ok(cDia.cor === aDia.cor && cDia.peso === aDia.peso && parseFloat(cDia.tam) >= parseFloat(aDia.tam) * .9, `C: os números do mês são grandes como os da Agenda (${cDia.tam} contra ${aDia.tam})`);
  h.ok(cHoje.fundo === aHoje.fundo && cHoje.raio === aHoje.raio && cHoje.fundo !== 'rgba(0, 0, 0, 0)', `C: hoje fica num círculo vermelho como na Agenda (${cHoje.fundo})`);
  h.ok(cSemana.cor === aSemana.cor, 'C: a linha D S T Q Q S S tem a cor da Agenda');
  h.ok(nomeC.toUpperCase() === (await p.evaluate(() => document.querySelector('#ca-titulo').textContent)).toUpperCase(), `C: o mês é o mesmo da Agenda (${nomeC})`);
  await p.click('#f-cal [data-fechar]'); await h.dormir(500);
  /* as setas da C só mexem na C: a agenda não abre, e o mês anda para os dois lados */
  const titulo = () => p.evaluate(() => document.querySelector('.comp-c .mes-c h2').textContent);
  const inicial = await titulo();
  await p.click('.comp-c [data-mes-c="1"]'); await h.dormir(500);
  const seguinte = await titulo();
  h.ok(seguinte !== inicial && await p.evaluate(() => !document.querySelector('#f-cal').classList.contains('aberta') && !document.querySelector('.mes-c .sb-dia.hoje')), `C: a seta para a direita mostra o mês seguinte (${inicial} para ${seguinte}), sem abrir a agenda e sem marcar hoje`);
  await p.click('.comp-c [data-mes-c="-1"]'); await h.dormir(500);
  h.ok(await titulo() === inicial && await p.evaluate(() => !!document.querySelector('.mes-c .sb-dia.hoje')), 'C: a seta para a esquerda volta ao mês de hoje');
  /* o mês com 6 semanas (agosto de 2026 começa num sábado) cabe, com os pontinhos */
  for (let i = 0; i < 3; i++) { await p.click('.comp-c [data-mes-c="-1"]'); await h.dormir(250) }
  await h.dormir(600);
  const seis = await p.evaluate(() => { const g = document.querySelector('.mes-c .sb-grade'), ultimo = [...g.querySelectorAll('.sb-dia')].pop().getBoundingClientRect(); return { titulo: document.querySelector('.mes-c h2').textContent, linhas: getComputedStyle(g).gridTemplateRows.split(' ').length, fundo: ultimo.bottom, dias: g.querySelectorAll('.sb-dia').length } });
  h.ok(seis.linhas === 6 && seis.fundo <= 409, `C: um mês de 6 semanas cabe sem passar da área segura (${seis.titulo}, ${seis.linhas} linhas, o último dia termina em ${Math.round(seis.fundo)})`);
  h.ok((await estouros(p, 'horizontal')).length === 0, 'C: o mês de 6 semanas não passa da área segura');
  /* o relógio quadrado vira como as placas de um algarismo: a placa de dois algarismos tem a aba que gira */
  const vira = await p.evaluate(async () => {
    const el = document.querySelector('.comp-c .placa[data-i="m"]'); el.dataset.d = '88'; tique(false);
    await new Promise(r => setTimeout(r, 120));
    return { virando: el.classList.contains('virando'), abas: el.querySelectorAll('.aba-cima, .aba-baixo').length, velho: el.querySelector('.aba-cima span')?.textContent };
  });
  h.ok(vira.virando && vira.abas === 2 && vira.velho === '88', `C: a placa de minutos vira com a aba que gira (${JSON.stringify(vira)})`);
  /* 12 teclas no perfil: a C não tem fileira de teclas, então nada muda */
  for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    await h.reset(); await h.cenario({ comp: 'c', teclas: 'muitas' }); await aberta(p, 'c', pos); await h.dormir(1200);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0 && await p.evaluate(() => !document.querySelector('.comp-c .tecla')), `C ${pos} com 12 teclas no perfil: sem teclas e nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
  }
  /* tocar no relógio abre a tela cheia, como nas outras composições */
  await p.setViewportSize({ width: 932, height: 430 });
  await h.reset(); await h.cenario({ comp: 'c' }); await aberta(p, 'c', 'horizontal'); await h.dormir(800);
  await p.click('.comp-c .relogio-q');
  h.ok(await h.espera(p, () => document.querySelector('#f-relogio')?.classList.contains('aberta')), 'C: tocar no relógio abre o relógio em tela cheia');
  await p.click('#f-relogio'); await h.dormir(500);

  /* ---- monitor do Mac ---- */
  await p.setViewportSize({ width: 932, height: 430 });
  for (const comp of ['a', 'b', 'c']) {
    await h.reset(); await h.cenario({ comp });
    await aberta(p, comp, 'horizontal'); await h.dormir(900);
    h.ok(await p.evaluate(() => !document.querySelector('.monitor-tira')), `monitor ${comp.toUpperCase()}: desligado por padrão, nada novo na tela`);
  }
  for (const comp of ['a', 'b', 'c']) for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    await h.reset(); await h.cenario({ comp, blocos: { monitor: true } });
    await aberta(p, comp, pos); await h.dormir(1300);
    const v = await p.evaluate(() => ({ txt: document.querySelector('.monitor-tira')?.textContent.replace(/\s+/g, ' ').trim() }));
    h.ok(!!v.txt && /CPU.*12%/.test(v.txt) && /Mem.*63%/.test(v.txt) && /Bat.*81%/.test(v.txt) && /1,2 MB\/s/.test(v.txt) && /40 KB\/s/.test(v.txt), `monitor ${comp.toUpperCase()} ${pos}: mostra CPU, memória, bateria e rede (${v.txt})`);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0, `monitor ${comp.toUpperCase()} ${pos}: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
    await h.foto(p, `monitor-${comp}-${pos}`);
  }
  /* pior caso: na tomada (rótulo "Tomada 100%") e rede em gigabit. A linha tem overflow:hidden, então o corte é silencioso:
     o que vale é o texto caber inteiro (scrollWidth <= clientWidth), não só o retângulo estar na área segura */
  for (const comp of ['a', 'b', 'c']) for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    await h.reset(); await h.cenario({ comp, blocos: { monitor: true }, monitor: { cpu: 45, memoria: 85, bateria: 100, naTomada: true, baixa: 131072000, sobe: 5242880 } });
    await aberta(p, comp, pos); await h.dormir(1300);
    const v = await p.evaluate(() => { const t = document.querySelector('.monitor-tira'); return { sw: t?.scrollWidth, cw: t?.clientWidth, txt: t?.textContent.replace(/\s+/g, ' ').trim() } });
    h.ok(v.sw != null && v.sw <= v.cw, `monitor ${comp.toUpperCase()} ${pos} no pior caso: o texto cabe inteiro, sem corte (${v.sw} de ${v.cw}: ${v.txt})`);
    h.ok(/Tomada.*100%/.test(v.txt) && /125 MB\/s/.test(v.txt) && /5,0 MB\/s/.test(v.txt), `monitor ${comp.toUpperCase()} ${pos} no pior caso: mostra tomada e as duas velocidades (${v.txt})`);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0, `monitor ${comp.toUpperCase()} ${pos} no pior caso: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
  }
  /* na C não existe o player pequeno: quando o Spotify troca de faixa o laço de 1 s não pode tentar redesenhá-lo.
     O erro seria engolido pelo try do tique, mas ele aborta o resto do passo: o monitor (que vem depois) pararia de atualizar */
  await p.setViewportSize({ width: 932, height: 430 });
  await h.reset(); await h.cenario({ comp: 'c', blocos: { monitor: true, spotify: true }, spotify: 'tocando' });
  await aberta(p, 'c', 'horizontal'); await h.dormir(1300);
  await h.cenario({ faixa: 'Outra faixa da C', monitor: { memoria: 41 } });
  h.ok(await h.espera(p, () => /Mem.*41%/.test(document.querySelector('.monitor-tira')?.textContent || ''), null, 5000), 'C: o Spotify trocou de faixa e o monitor continua atualizando (o laço não quebra)');
  await h.cenario({ spotify: 'pausado', monitor: { memoria: 42 } });
  h.ok(await h.espera(p, () => /Mem.*42%/.test(document.querySelector('.monitor-tira')?.textContent || '') && !document.querySelector('.player'), null, 5000), 'C: o Spotify pausou e o monitor continua atualizando, sem player');
  /* a pessoa escolheu só alguns itens nos Ajustes do Mac */
  await p.setViewportSize({ width: 932, height: 430 });
  await h.reset(); await h.cenario({ comp: 'c', blocos: { monitor: true }, monitorItens: { cpu: false, memoria: true, bateria: false, rede: false } });
  await aberta(p, 'c', 'horizontal'); await h.dormir(1300);
  let t = await p.evaluate(() => document.querySelector('.monitor-tira')?.textContent.replace(/\s+/g, ' ').trim());
  h.ok(/Mem.*63%/.test(t) && !/CPU|Bat|MB\/s|KB\/s/.test(t), `só o item escolhido aparece (${t})`);
  await h.cenario({ monitorItens: { cpu: false, memoria: false, bateria: false, rede: false } });
  h.ok(await h.espera(p, () => !document.querySelector('.monitor-tira'), null, 5000), 'sem nenhum item escolhido o bloco some');
  /* Mac de mesa: sem bateria, o item some sozinho. Sem medida ainda (primeira leitura), fica "-" */
  await h.cenario({ monitorItens: { cpu: true, memoria: true, bateria: true, rede: true }, monitor: { memoria: 40 } });
  h.ok(await h.espera(p, () => /Mem.*40%/.test(document.querySelector('.monitor-tira')?.textContent || ''), null, 5000), 'o monitor acompanha o que o Mac mede');
  t = await p.evaluate(() => document.querySelector('.monitor-tira').textContent.replace(/\s+/g, ' ').trim());
  h.ok(!/Bat|Tomada/.test(t) && /CPU.*-/.test(t), `Mac sem bateria: o item some. CPU sem medida mostra "-" (${t})`);
  /* bateria baixa fica em aviso, na tomada não */
  await h.cenario({ monitor: { cpu: 5, memoria: 40, bateria: 8, naTomada: false, baixa: 0, sobe: 0 } });
  h.ok(await h.espera(p, () => !!document.querySelector('.monitor-tira .cheio'), null, 5000), 'bateria em 8% fora da tomada fica em vermelho');
  await h.cenario({ monitor: { cpu: 5, memoria: 40, bateria: 8, naTomada: true, baixa: 0, sobe: 0 } });
  h.ok(await h.espera(p, () => !document.querySelector('.monitor-tira .cheio') && /Tomada/.test(document.querySelector('.monitor-tira').textContent), null, 5000), 'na tomada a bateria baixa não alarma');
  await p.close();
}
