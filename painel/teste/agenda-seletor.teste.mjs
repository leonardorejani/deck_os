// Frente agenda-arrasto (13/11/2026): no Novo compromisso, tocar em Dia, Início e Fim abre o seletor nativo.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="calendario"]'));

export default async function (h) {
  for (const [nome, w, al] of [['celular deitado', 932, 430], ['celular em pé', 430, 932], ['janela larga', 2000, 1100]]) {
    const ctx = await h.novoContexto({ viewport: { width: w, height: al } });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0); await h.dormir(500);
    await p.evaluate(() => { window.__picker = []; HTMLInputElement.prototype.showPicker = function () { window.__picker.push(this.id) } });
    await p.click('#ca-puxa'); await h.espera(p, () => document.querySelector('#f-cal').classList.contains('novo')); await h.dormir(500);
    for (const id of ['nc-dia', 'nc-inicio', 'nc-fim']) {
      const centro = await p.evaluate(i => { const r = document.querySelector('#' + i).closest('.nc-data').getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] }, id);
      const topo = await p.evaluate(([x, y]) => { const e = document.elementFromPoint(x, y); return e && (e.id || e.className) }, centro);
      h.ok(topo === id, `${nome}: o centro do campo ${id} é o próprio input (${topo})`);
      await p.evaluate(() => { window.__picker.length = 0 });
      await p.mouse.click(centro[0], centro[1]);
      const abriu = await p.evaluate(() => window.__picker.slice());
      h.ok(abriu.length === 1 && abriu[0] === id, `${nome}: clicar no centro de ${id} abre o seletor (${JSON.stringify(abriu)})`);
    }
    // o valor escolhido aparece no texto do campo
    await p.fill('#nc-dia', '2026-12-25'); await p.fill('#nc-inicio', '09:30'); await p.fill('#nc-fim', '10:45');
    const txt = await p.evaluate(() => ['nc-dia', 'nc-inicio', 'nc-fim'].map(i => document.querySelector('#' + i).closest('.nc-data').querySelector('.nc-vis').textContent));
    h.ok(txt[1] === '09:30' && txt[2] === '10:45' && /25/.test(txt[0]) && /dez/i.test(txt[0]), `${nome}: o valor novo aparece no campo (${JSON.stringify(txt)})`);
    // dia todo desliga os horários: clicar neles não abre nada
    await p.check('#nc-todo'); await p.evaluate(() => { window.__picker.length = 0 });
    const c2 = await p.evaluate(() => { const r = document.querySelector('#nc-inicio').closest('.nc-data').getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] });
    await p.mouse.click(c2[0], c2[1]);
    h.ok((await p.evaluate(() => window.__picker.length)) === 0, `${nome}: com Dia todo o horário não abre seletor`);
    await ctx.close();
  }
}
