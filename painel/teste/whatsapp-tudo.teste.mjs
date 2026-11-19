// WhatsApp como o WhatsApp (pedidos de 16/11/2026): 4 abas (Todas, Contatos, Grupos, Arquivadas) com a mesma regra, a conversa fica
// enquanto espera resposta dele e some quando a última mensagem é dele (volta quando o outro lado escreve). Cada aba tem o selo com o
// total de não lidas da sua categoria. Roda em três tamanhos de tela. Dados inventados.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
const nomes = p => p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .nome-c')].map(x => x.childNodes[0].textContent.trim()));
const selos = p => p.evaluate(() => Object.fromEntries([...document.querySelectorAll('#wa-filtro button')].map(b => { const s = b.querySelector('.selo-aba'); return [b.dataset.f, s.hidden ? '-' : s.textContent] })));
const aba = async (p, f) => { await p.click(`#wa-filtro [data-f="${f}"]`); await p.waitForTimeout(80); return (await nomes(p)).join('|') };
// o selo cabe dentro do botão e as 4 abas cabem no segmento, sem rolagem lateral
const cabe = p => p.evaluate(() => {
  const seg = document.querySelector('#wa-filtro'), r = seg.getBoundingClientRect(), rola = seg.scrollWidth > seg.clientWidth + 1; // em pé o filtro rola por dentro (cabeçalho só com filtro e X): lá só vale não quebrar o botão
  return [...seg.querySelectorAll('button')].every(b => { const q = b.getBoundingClientRect(), s = b.querySelector('.selo-aba'), t = s.getBoundingClientRect(); return b.scrollWidth <= b.clientWidth + 1 && (rola || (q.left >= r.left - 1 && q.right <= r.right + 1)) && (s.hidden || (t.left >= q.left - 1 && t.right <= q.right + 1)) }) && (rola ? getComputedStyle(seg).overflowX === 'auto' : true);
});

export default async function (h) {
  for (const [tam, w, al] of [['celular deitado', 932, 430], ['celular em pé', 430, 932], ['janela larga', 2000, 1100]]) {
    await h.cenario({ whatsappOrigem: 'qr', whatsappTudo: true, whatsappVolta: false });
    const ctx = await h.novoContexto({ viewport: { width: w, height: al } });
    const p = await h.pagina({ ctx }); await pronta(h, p);
    await p.click('.tecla[data-id="whatsapp"]');
    h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5), `${tam}: Todas lista as 5 conversas que esperam resposta`);

    /* abas: as 4, sem linha Arquivadas dentro de Todas */
    h.ok((await p.evaluate(() => [...document.querySelectorAll('#wa-filtro button:not([hidden])')].map(b => b.dataset.f).join(','))) === 'todas,contatos,grupos,arquivadas', `${tam}: abas Todas, Contatos, Grupos e Arquivadas`);
    h.ok(await p.evaluate(() => !document.querySelector('#wa-lista .arquivadas-linha')), `${tam}: sem linha Arquivadas dentro de Todas (virou aba)`);

    /* Todas: contatos e grupos não arquivados, fixada no topo, o resto pela última mensagem. Quem ele respondeu por último não está */
    const todas = (await nomes(p)).join('|');
    h.ok(todas === 'Carla Dias|Ana Souza|Beto Lima|Banda|Louvor', `${tam}: Todas sem as respondidas por ele (${todas})`);
    h.ok(!todas.includes('Dani Respondida') && !todas.includes('Equipe do Palco'), `${tam}: contato e grupo respondidos por ele ficam fora`);
    h.ok((await texto(p, '#wa-titulo')) === 'WhatsApp 6 não lidas em 2 conversas', `${tam}: título conta só não arquivadas (${await texto(p, '#wa-titulo')})`);
    const previas = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .previa')].map(x => x.textContent));
    h.ok(previas.join('|') === 'Foto|Consegue ver isso?|Valeu, até mais|Rui: Chego às 19h|Pedro: Quem leva o cabo?', `${tam}: prévia da última mensagem (${previas.join('|')})`);
    const sc = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa')].map(c => c.querySelector('.qtd')?.textContent ?? '-'));
    h.ok(sc.join(',') === '-,2,-,-,4', `${tam}: selo da conversa só nas que têm não lida (${sc.join(',')})`);

    /* selos das abas: total de não lidas de cada categoria, sem selo no zero */
    const s1 = await selos(p);
    h.ok(JSON.stringify(s1) === JSON.stringify({ todas: '6', contatos: '2', grupos: '4', arquivadas: '9' }), `${tam}: selos das abas (${JSON.stringify(s1)})`);
    h.ok(await cabe(p), `${tam}: abas e selos cabem sem quebrar o segmento`);

    /* mesma regra, só muda a categoria */
    const c = await aba(p, 'contatos'), g = await aba(p, 'grupos'), a = await aba(p, 'arquivadas');
    h.ok(c === 'Carla Dias|Ana Souza|Beto Lima', `${tam}: Contatos (${c})`);
    h.ok(g === 'Banda|Louvor', `${tam}: Grupos (${g})`);
    h.ok(a === 'Bia Arquivada|Promo Arquivada|Sorteio Arquivado', `${tam}: Arquivadas (${a})`);
    h.ok((await texto(p, '#wa-titulo')) === 'WhatsApp 6 não lidas em 2 conversas', `${tam}: dentro das arquivadas o título segue sem contar as arquivadas`);
    await aba(p, 'todas');

    /* abrir a conversa continua mostrando as mensagens */
    await p.click('#wa-lista [data-wa="t1@s.whatsapp.net"]');
    h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .mensagens p').length === 2), `${tam}: abrir uma não lida mostra as não lidas`);

    /* o contato respondido por ele escreve de novo: volta para Todas e Contatos, e os totais sobem */
    await h.cenario({ whatsappVolta: true });
    h.ok(await h.espera(p, () => [...document.querySelectorAll('#wa-lista .nome-c')].some(x => x.textContent.includes('Dani Respondida'))), `${tam}: mensagem nova do contato traz a conversa de volta`);
    await h.espera(p, () => document.querySelector('#wa-titulo .n-total')?.textContent === '9'); // o total conta até o valor novo
    h.ok((await texto(p, '#wa-titulo')) === 'WhatsApp 9 não lidas em 3 conversas', `${tam}: título soma a que voltou (${await texto(p, '#wa-titulo')})`);
    const s2 = await selos(p);
    h.ok(JSON.stringify(s2) === JSON.stringify({ todas: '9', contatos: '5', grupos: '4', arquivadas: '9' }), `${tam}: selos depois da volta (${JSON.stringify(s2)})`);
    h.ok((await aba(p, 'contatos')) === 'Carla Dias|Dani Respondida|Ana Souza|Beto Lima', `${tam}: Contatos com a que voltou`);
    await p.context().close(); // a folha aberta seguiria lendo a lista e contaria nos pedidos dos testes seguintes
  }
}
