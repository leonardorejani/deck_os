// Ritmo do uso das IAs (19/11/2026): a barra ganha uma marca onde o uso deveria estar pelo tempo decorrido da semana, e o bloco e a tela de
// detalhe dizem "enche em X" (ou "dá até a renovação"). Só vale com pelo menos 5% da janela decorrida. Números do Mac de mentira.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.cartao.uso, .uso-tira'));
const txt = (p, sel) => p.evaluate(s => (document.querySelector(s)?.textContent || '').replace(/\s+/g, ' ').trim(), sel);

export default async function (h) {
  const ctx = await h.novoContexto({ hasTouch: true });
  let p = await h.pagina({ ctx }); await pronta(h, p);

  /* ---------- a conta, com horas fixas ---------- */
  const r = await p.evaluate(() => {
    const D = 864e5, ref = 1e12, f = (p, restaDias, rf = ref) => ritmoSemana(p, new Date(rf + restaDias * D).toISOString(), rf);
    return { meio80: f(80, 3.5), meio40: f(40, 3.5), cedo: f(90, 7 - 0.1), limite: f(90, 7 - 0.35), cheio: f(100, 3.5), zero: f(0, 3.5), semMedicao: f(null, 3.5), renovou: f(50, -1), semData: ritmoSemana(50, null, ref) };
  });
  h.ok(r.meio80.esperado === 50 && Math.abs(r.meio80.enche - (1e12 + 0.875 * 864e5)) < 1000, 'ritmoSemana: 80% na metade da semana enche em 0,875 d');
  h.ok(r.meio40.esperado === 50 && r.meio40.enche === null, 'ritmoSemana: 40% na metade da semana dá até a renovação');
  h.ok(r.cedo === null && r.limite?.esperado === 5 && r.limite.enche !== null, 'ritmoSemana: sem ritmo antes de 5% da janela, com ritmo a partir dele');
  h.ok(r.cheio.enche === null && r.zero.enche === null, 'ritmoSemana: já cheio ou parado não tem quando encher');
  h.ok(r.semMedicao === null && r.renovou === null && r.semData === null, 'ritmoSemana: sem medição, janela renovada ou sem data não tem ritmo');

  /* ---------- bloco na home ---------- */
  const linhas = () => p.evaluate(() => [...document.querySelectorAll('.cartao.uso .uso-linha')].map(l => ({
    nome: l.querySelector('.uso-nome').textContent.replace(/\s+/g, ' ').trim(), marca: l.querySelector('.trilho u')?.style.left ?? null,
    enche: l.querySelector('.renova-enche')?.textContent ?? null, renova: l.querySelector('.renova').textContent, aria: l.querySelector('.medidor').getAttribute('aria-label') })));
  let l = await linhas();
  h.ok(l.length === 3 && l.every(x => x.marca == null || /^\d+%$/.test(x.marca)), `o bloco tem uma linha por conta (${l.map(x => x.nome)})`);
  const leo = l[0];
  h.ok(/^\d+%$/.test(leo.marca) && parseInt(leo.marca) >= 45 && parseInt(leo.marca) <= 65 && /o esperado agora é \d+%/.test(leo.aria), `a barra tem a marca do esperado (${leo.marca})`);
  h.ok(/^enche \d+ (d|h|min)$/.test(leo.enche ?? ''), `61% com a semana pela metade diz quando enche (${leo.enche})`);
  h.ok(l[1].enche === null, 'quem chega na renovação com folga segue mostrando quando renova');
  h.ok(/^(\d+ dias|amanhã|hoje)/.test(l[1].renova), `a coluna renova segue como era para quem não enche (${l[1].renova})`)
  h.ok(await p.evaluate(() => { const c = document.querySelector('.cartao.uso').getBoundingClientRect(); return [...document.querySelectorAll('.cartao.uso .uso-linha')].every(x => x.getBoundingClientRect().bottom <= c.bottom) }), 'as três contas continuam inteiras dentro do cartão')
  await h.foto(p, 'uso-ritmo-bloco-deitado');

  /* ---------- tela de detalhe ---------- */
  await p.click('.cartao.uso');
  await h.espera(p, () => !!document.querySelector('#us-corpo .us-conta'));
  await h.dormir(900);
  const tudo = await txt(p, '[data-c="0.j0"]');
  h.ok(/No ritmo atual, enche em \d+ (d|h)/.test(tudo) && /Esperado agora: 55%/.test(tudo), `o detalhe diz quando enche e o esperado (${tudo})`);
  h.ok(/No ritmo atual, dá até a renovação/.test(await txt(p, '[data-c="2.j0"]')), 'o detalhe diz "dá até a renovação" quando cabe');
  h.ok(await p.evaluate(() => document.querySelector('[data-c="0.j0"] .us-barra u').style.left === '55%'), 'a marca do esperado segue na barra do detalhe');
  await h.foto(p, 'uso-ritmo-detalhe-deitado');
  await p.close();

  /* ---------- em pé e janela larga ---------- */
  p = await h.pagina({ w: 430, h: 932, ctx: await h.novoContexto({ hasTouch: true, viewport: { width: 430, height: 932 } }) }); await pronta(h, p);
  const tira = await p.evaluate(() => [...document.querySelectorAll('.uso-tira > span:not(.esconder-bloco)')].map(x => ({ marca: x.querySelector('.mini u')?.style.left ?? null, visivel: !!x.querySelector('.mini u') && getComputedStyle(x.querySelector('.mini u')).display !== 'none', aria: x.getAttribute('aria-label') })));
  h.ok(tira.length === 3 && /^\d+%$/.test(tira[0].marca) && tira[0].visivel, `em pé a faixa tem a marca do esperado na barra (${tira[0]?.marca})`);
  h.ok(/esperado agora \d+%, enche em \d+ (d|h)/.test(tira[0].aria) && !/enche/.test(tira[1].aria), 'em pé o leitor de tela ouve o esperado e quando enche');
  await h.foto(p, 'uso-ritmo-bloco-em-pe');
  await p.click('.cartao.uso, .uso-tira'); await h.espera(p, () => !!document.querySelector('#us-corpo .us-conta')); await h.dormir(900);
  await h.foto(p, 'uso-ritmo-detalhe-em-pe');
  await p.close();
  p = await h.pagina({ w: 1440, h: 900 }); await pronta(h, p);
  await h.foto(p, 'uso-ritmo-bloco-janela');
  await p.close();
  await ctx.close();
}
