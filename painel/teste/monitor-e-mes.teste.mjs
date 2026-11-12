// Composição C (relógio com as horas sobre os minutos e o mês) e o monitor do Mac (12/11/2026).
const SEGURA = { horizontal: { l: 59, r: 873, t: 0, b: 409 }, vertical: { l: 0, r: 430, t: 59, b: 898 } };
const VISTAS = { horizontal: [932, 430], vertical: [430, 932] };
// tudo que passa da área segura (pixels da tela, já descontada a escala)
const estouros = (p, pos) => p.evaluate(([S]) => {
  const tela = document.querySelector('#tela'), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth, ruins = [];
  for (const el of document.querySelectorAll('.relogio-linha, .data-linha, .cartao, .monitor-tira, .carrossel, .menu-area, .divisor, .pagina:first-child .tecla')) {
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
      const r = s => document.querySelector(s)?.getBoundingClientRect(), pl = [...document.querySelectorAll('.comp-c .placa')].map(e => e.getBoundingClientRect());
      const hoje = document.querySelector('.mes-c-dias .hoje'), agora = new Date();
      return { placas: pl.map(q => ({ l: q.left, t: q.top, b: q.bottom })), relogio: r('.comp-c .relogio-linha'), mes: r('.comp-c .mes-c'), teclas: r('.comp-c .teclas'),
        hoje: hoje?.textContent, diaDeHoje: String(agora.getDate()), dias: document.querySelectorAll('.mes-c-dias span:not(:empty)').length,
        diasNoMes: new Date(agora.getFullYear(), agora.getMonth() + 1, 0).getDate(), mesNome: document.querySelector('.mes-c-nome')?.textContent, player: !!document.querySelector('.player'), sessoes: !!document.querySelector('.sessoes') };
    });
    const [a, b2, c3, d] = g.placas; // horas: a e b2. minutos: c3 e d
    h.ok(certo && g.placas.length === 4 && Math.abs(a.t - b2.t) < 2 && Math.abs(c3.t - d.t) < 2 && c3.t >= a.b - 2 && Math.abs(a.l - c3.l) < 2, `C ${pos}: as horas ficam em cima e os minutos embaixo, alinhados`);
    h.ok(g.player === false && g.sessoes === false, `C ${pos}: sem player e sem sessões`);
    h.ok(pos === 'horizontal' ? g.mes.left > g.relogio.right - 1 : g.mes.top >= g.relogio.bottom - 1, `C ${pos}: o mês fica ${pos === 'horizontal' ? 'à direita' : 'abaixo'} do relógio`);
    h.ok(g.teclas.top >= g.mes.bottom - 1, `C ${pos}: a fileira de teclas fica embaixo do mês`);
    h.ok(g.hoje === g.diaDeHoje && g.dias === g.diasNoMes, `C ${pos}: o mês tem os ${g.diasNoMes} dias e hoje (${g.diaDeHoje}) está marcado (marcado ${g.hoje}, dias ${g.dias})`);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0, `C ${pos}: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
    await h.foto(p, `c-${pos}`);
  }
  /* 12 teclas e o mês também cabem */
  for (const pos of ['horizontal', 'vertical']) {
    await p.setViewportSize({ width: VISTAS[pos][0], height: VISTAS[pos][1] });
    await h.reset(); await h.cenario({ comp: 'c', teclas: 'muitas' }); await aberta(p, 'c', pos); await h.dormir(1200);
    const ruins = await estouros(p, pos);
    h.ok(ruins.length === 0, `C ${pos} com 12 teclas: nada passa da área segura${ruins.length ? ' (' + ruins.join('; ') + ')' : ''}`);
  }
  /* tocar no mês abre a agenda; as teclas continuam funcionando na C */
  await p.setViewportSize({ width: 932, height: 430 });
  await h.reset(); await h.cenario({ comp: 'c' }); await aberta(p, 'c', 'horizontal'); await h.dormir(800);
  await p.click('.comp-c .mes-c');
  h.ok(await h.espera(p, () => document.querySelector('#f-cal')?.classList.contains('aberta')), 'C: tocar no mês abre a agenda');
  await p.click('#f-cal [data-fechar]'); await h.dormir(500);
  await p.click('.pagina .tecla[data-id="acordado"]');
  h.ok(await h.ate(async () => (await h.contadores()).botoes.includes('acordado')), 'C: tocar numa tecla manda o Mac executar');

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
