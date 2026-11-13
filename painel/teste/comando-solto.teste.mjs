// Frente comando-foco (13/11/2026): "mudar foco nao tá funcionando direto, faz metade, depois nao volta... e da erro de wifi com o mac".
// Comando lento (passa de 10 s): o Mac responde na hora, a tecla mostra "Ligando..." e vira ligada só quando o comando acaba.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const tecla = (p, id) => p.evaluate(i => { const t = document.querySelector(`.tecla[data-id="${i}"]`); return t && { acesa: t.classList.contains('acesa'), texto: t.querySelector('.estado-tecla')?.textContent || '', pressed: t.getAttribute('aria-pressed') } }, id);
const aviso = p => p.evaluate(() => ({ visivel: document.querySelector('#aviso').classList.contains('visivel'), txt: document.querySelector('#aviso-txt').textContent, erro: document.querySelector('#aviso').classList.contains('erro') }));

export default async function (h) {
  for (const [nome, w, alt] of [['celular deitado', 932, 430], ['celular em pe', 430, 932], ['janela larga de desktop', 2000, 1100]]) {
    await h.reset(); await h.cenario({ comFoco: true, acesas: [], comandoLento: 2500 });
    const p = await h.pagina({ w, h: alt }); await pronta(h, p);
    await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').scrollIntoView({ inline: 'center' }));
    await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click());
    h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="foco"] .estado-tecla.andando')?.textContent === 'Ligando...'), `${nome}: o toque mostra "Ligando..." na tecla`);
    const durante = await tecla(p, 'foco');
    h.ok(!durante.acesa, `${nome}: enquanto liga a tecla não finge estar ligada (${JSON.stringify(durante)})`);
    const a = await aviso(p);
    h.ok(!(a.visivel && a.erro), `${nome}: nenhum aviso de erro nem de Wi-Fi (${a.txt})`);
    if (w === 932) await h.foto(p, 'comando-solto-ligando');
    // tocar de novo no meio não dispara outro comando
    const antes = (await h.contadores()).botoes.filter(x => x === 'foco').length;
    await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click()); await h.dormir(300);
    h.ok((await h.contadores()).botoes.filter(x => x === 'foco').length === antes, `${nome}: tocar de novo no meio do comando não manda outro pedido ao Mac`);
    h.ok(/ainda ligando/.test((await aviso(p)).txt), `${nome}: e o aviso diz que ainda está ligando`);
    h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="foco"]').classList.contains('acesa') && !document.querySelector('.tecla[data-id="foco"] .estado-tecla.andando'), null, 8000), `${nome}: ao terminar a tecla vira ligada e o "Ligando..." some`);
    // desligar: "Desligando..." e volta
    await h.dormir(300);
    await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click());
    h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="foco"] .estado-tecla.andando')?.textContent === 'Desligando...'), `${nome}: o toque seguinte mostra "Desligando..."`);
    h.ok(await h.espera(p, () => !document.querySelector('.tecla[data-id="foco"]').classList.contains('acesa') && !document.querySelector('.tecla[data-id="foco"] .estado-tecla.andando'), null, 8000), `${nome}: ao terminar volta a desligada`);
    await p.context().close();
  }

  // comando que falha no fim: o motivo chega uma vez só, e a tecla não fica ligada
  await h.reset(); await h.cenario({ comFoco: true, acesas: [], comandoLento: 1200, comandoFalha: 'O comando falhou: Spotify nao fechou' });
  const p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click());
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent.includes('Spotify nao fechou') && document.querySelector('#aviso').classList.contains('erro'), null, 8000), 'falha do comando lento chega como aviso de erro com o motivo');
  h.ok(!(await tecla(p, 'foco')).acesa, 'e a tecla não fica ligada');
  await p.context().close();

  // tecla de comando comum e lenta (sem liga e desliga): "Rodando..."
  await h.reset(); await h.cenario({ acesas: [], comandoLento: 1500 });
  const q = await h.pagina(); await pronta(h, q);
  await q.evaluate(() => document.querySelector('.tecla[data-id="apagar"]').click());
  h.ok(await h.espera(q, () => document.querySelector('.tecla[data-id="apagar"] .estado-tecla.andando')?.textContent === 'Rodando...'), 'tecla de comando comum e lenta mostra "Rodando..."');
  h.ok(await h.espera(q, () => !document.querySelector('.tecla[data-id="apagar"] .estado-tecla.andando'), null, 8000), 'e o "Rodando..." some ao terminar');
  await q.context().close();
}
