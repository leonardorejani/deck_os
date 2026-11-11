// O canal: textos de tempo, código de acesso, tela de pareamento e o canal nativo injetado.
export default async function (h) {
  /* textos de tempo, a partir de datas ISO 8601 */
  const p0 = await h.pagina();
  const t = await p0.evaluate(() => {
    const ref = new Date(2026, 10, 10, 12, 0).getTime(), iso = (d, hh, mm = 0) => new Date(2026, 10, d, hh, mm).toISOString();
    return {
      emDias: renovaEm(iso(13, 14), false, ref), emDiasCurto: renovaEm(iso(13, 14), true, ref),
      amanha: renovaEm(iso(11, 9), false, ref), hoje: renovaEm(iso(10, 22), false, ref), hojeCurto: renovaEm(iso(10, 22), true, ref),
      hojeMeia: renovaEm(iso(10, 14, 30), false, ref), semData: renovaEm(null, false, ref), torta: renovaEm('lixo', true, ref),
      min: haQuanto(new Date(ref - 5 * 60000).toISOString(), ref), horas: haQuanto(new Date(ref - 13 * 3600000).toISOString(), ref), dias: haQuanto(new Date(ref - 4 * 86400000).toISOString(), ref),
    };
  });
  h.ok(t.emDias === 'em 3 dias' && t.emDiasCurto === '3 dias', `renova daqui a 3 dias: "${t.emDias}" e "${t.emDiasCurto}"`);
  h.ok(t.amanha === 'amanhã', `renova amanhã: "${t.amanha}"`);
  h.ok(t.hoje === 'hoje às 22h' && t.hojeCurto === 'hoje 22h', `renova hoje: "${t.hoje}" e "${t.hojeCurto}"`);
  h.ok(t.hojeMeia === 'hoje às 14h30', `renova hoje com minutos: "${t.hojeMeia}"`);
  h.ok(t.semData === '-' && t.torta === '-', 'renova sem data ou torta vira "-"');
  h.ok(t.min.texto === '5 min' && !t.min.velha && t.horas.texto === '13 h' && t.horas.velha && t.dias.texto === '4 dias', `há quanto tempo a sessão espera: ${t.min.texto}, ${t.horas.texto}, ${t.dias.texto}`);
  await p0.context().close();

  /* código de acesso: vem em ?codigo=, fica no aparelho e sai da URL */
  const p1 = await h.pagina();
  h.ok(await h.espera(p1, () => !!document.querySelector('.comp-a')), 'abre com o código do QR e mostra o painel');
  h.ok(!p1.url().includes('codigo='), `o código sai da URL (${p1.url()})`);
  h.ok(await p1.evaluate(() => localStorage.getItem('deck-codigo')) === h.CODIGO, 'o código fica guardado no aparelho');
  await p1.goto(h.base + '/');
  h.ok(await h.espera(p1, () => !!document.querySelector('.comp-a')), 'reabre sem o código na URL e continua pareado');
  await p1.context().close();

  /* sem código ou com código errado: tela de pareamento */
  for (const [nome, codigo] of [['sem código', false], ['com código errado', 'ERRADOERRADOERRADO12']]) {
    const p = await h.pagina({ codigo });
    h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('sem-acesso')), `${nome}: mostra a tela de pareamento`);
    await h.dormir(700);
    const v = await p.evaluate(() => { const o = document.querySelector('.tela-offline.acesso'); return { op: getComputedStyle(o).opacity, txt: o.textContent.replace(/\s+/g, ' ').trim(), off: document.querySelector('#tela').classList.contains('offline'), conteudo: document.querySelector('#conteudo').children.length } });
    h.ok(v.op === '1' && v.txt.includes('Abra o Deck no Mac e leia o QR de novo'), `${nome}: texto "${v.txt}"`);
    h.ok(!v.off && v.conteudo === 0, `${nome}: não vira "Mac desconectado" e não desenha o painel`);
    if (codigo === false) await h.foto(p, 'sem-acesso');
    await p.context().close();
  }
  const c0 = (await h.contadores()).estado;
  const pz = await h.pagina({ codigo: false }); await h.dormir(2500); await pz.context().close();
  h.ok((await h.contadores()).estado === c0, 'sem código a página nem pede o estado ao Mac');

  /* canal nativo: window.DeckCanal vale no lugar do HTTPS */
  const antes = () => {
    window.__chamadas = [];
    const e = { agora: new Date().toISOString(), nomeMac: 'Mac do App', perfilAtivo: 'p', comp: 'a', blocos: { spotify: true, agenda: true, whatsapp: true, sessoes: true, uso: true }, spotify: { tocando: true, faixa: 'Faixa do app nativo', artista: 'Canal injetado', posicao: 10, duracao: 100, capaId: 'x', cores: [] }, uso: [], sessoes: [], acesas: [], selos: {}, avisos: [] };
    const cfg = { versao: 1, perfis: [{ id: 'p', nome: 'P', teclas: [{ id: 'k1', nome: 'Tecla nativa', tipo: 'comando', valor: 'x', icone: 'svg:raio' }] }], perfilAtivo: 'p', comp: 'a', contas: [], blocos: e.blocos, nomeMac: 'Mac do App' };
    window.DeckCanal = { estado: async () => e, config: async () => cfg, botao: async id => { __chamadas.push('botao:' + id); return { ok: true } }, spotify: async a => { __chamadas.push('spotify:' + a); return { ok: true } }, capaUrl: id => 'icones/deck.png?c=' + id, gravarConfig: async c => c, whatsapp: async () => [], agenda: async () => [], sessoes: async () => [] };
  };
  const c1 = (await h.contadores()).estado;
  const pn = await h.pagina({ antes, codigo: false });
  h.ok(await h.espera(pn, () => document.querySelector('.faixa')?.textContent === 'Faixa do app nativo'), 'com window.DeckCanal o painel mostra o que o app nativo entrega');
  await pn.click('.tecla[data-id="k1"]');
  h.ok(await h.espera(pn, () => __chamadas.includes('botao:k1')), 'o toque na tecla vai pelo canal nativo');
  h.ok((await h.contadores()).estado === c1, 'e nenhum pedido sai para o HTTPS');
  await pn.context().close();

  /* rodízio: o Mac troca o código e avisa em X-Deck-Codigo-Novo. A página passa a usar e a guardar o novo */
  await h.reset(); await h.cenario({ rodizio: 'trocar' });
  const pr = await h.pagina();
  h.ok(await h.espera(pr, () => !!document.querySelector('.comp-a .faixa')), 'rodízio: o painel abre normalmente com o código que a página tinha');
  h.ok(await h.espera(pr, n => localStorage.getItem('deck-codigo') === n, h.CODIGO_NOVO), 'rodízio: a página guarda o código novo que veio no cabeçalho');
  await h.dormir(2300); // alguns passos do laço depois da troca
  let usados = (await h.contadores()).codigos, primeiro = usados.indexOf(h.CODIGO_NOVO);
  h.ok(primeiro > 0 && usados.slice(primeiro).every(x => x === h.CODIGO_NOVO) && usados.slice(primeiro).length >= 3, `rodízio: depois da troca todo pedido vai com o código novo (${usados.length} pedidos, o novo desde o ${primeiro + 1}º)`);
  h.ok(await pr.evaluate(() => !document.querySelector('#tela').classList.contains('sem-acesso') && !document.querySelector('#tela').classList.contains('offline')), 'rodízio: nenhum aviso de código inválido ou de Mac fora');
  await pr.goto(h.base + '/'); // reabre sem código na URL: o guardado é o novo
  h.ok(await h.espera(pr, () => !!document.querySelector('.comp-a .faixa')), 'rodízio: reabrir a página sem QR continua pareado, com o código novo');
  await pr.context().close();
  // a resposta de erro também leva o código novo: o toque numa tecla que o Mac recusa já traz o cabeçalho
  await h.reset(); await h.cenario({ rodizio: 'botao', falha: true });
  const pe = await h.pagina();
  h.ok(await h.espera(pe, () => !!document.querySelector('.tecla[data-id="apagar"]') && !document.querySelector('#conteudo.carregando')), 'rodízio: painel pronto para o toque');
  await h.cenario({ pendurar: true }); // o laço não pede o estado: só o toque falho pode trazer o código novo
  await pe.click('.tecla[data-id="apagar"]');
  h.ok(await h.espera(pe, n => localStorage.getItem('deck-codigo') === n, h.CODIGO_NOVO, 3000), 'rodízio: a resposta de erro (500) também troca o código guardado');
  await pe.context().close();
}
