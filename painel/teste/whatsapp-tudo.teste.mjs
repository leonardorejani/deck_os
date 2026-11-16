// WhatsApp como o WhatsApp (pedido de 16/11/2026): Todas lista as conversas lidas e não lidas pela última mensagem, as arquivadas ficam
// separadas (linha "Arquivadas" no topo de Todas e filtro próprio) e o selo de não lidas só aparece quando há. Dados inventados.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
const nomes = p => p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .nome-c')].map(x => x.childNodes[0].textContent.trim()));
const filtro = async (p, f) => { await p.click(`#wa-filtro [data-f="${f}"]`); await p.waitForTimeout(80); return nomes(p) };

export default async function (h) {
  await h.cenario({ whatsappOrigem: 'qr', whatsappTudo: true });
  const p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5), 'Todas lista as 5 conversas não arquivadas, lidas e não lidas');

  /* Todas: fixada no topo, o resto pela última mensagem */
  h.ok((await nomes(p)).join('|') === 'Carla Dias|Ana Souza|Beto Lima|Equipe do Palco|Louvor', `Todas: fixada primeiro, depois por última mensagem (${(await nomes(p)).join('|')})`);
  h.ok((await texto(p, '#wa-titulo')) === 'WhatsApp 6 não lidas em 2 conversas', `o título conta só não arquivadas e só as com não lida (${await texto(p, '#wa-titulo')})`);

  /* prévia: autor em grupo, só texto em contato */
  const previas = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .previa')].map(x => x.textContent));
  h.ok(previas.join('|') === 'Foto|Consegue ver isso?|Valeu, até mais|Você: Passo no ensaio|Pedro: Quem leva o cabo?', `prévia da última mensagem, com o autor em grupo (${previas.join('|')})`);

  /* selo só quando há não lida; fixada e silenciada com marca */
  const selos = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa')].map(c => c.querySelector('.qtd')?.textContent ?? '-'));
  h.ok(selos.join(',') === '-,2,-,-,4', `selo de não lidas só nas que têm (${selos.join(',')})`);
  h.ok(await p.evaluate(() => document.querySelectorAll('#wa-lista .conversa')[0].querySelectorAll('.marca').length === 2 && document.querySelectorAll('#wa-lista .conversa')[1].querySelectorAll('.marca').length === 0), 'a fixada e silenciada mostra as duas marcas e as outras nenhuma');
  h.ok(await p.evaluate(() => document.querySelectorAll('#wa-lista .conversa .lado .nova').length === 2), 'a hora fica verde só nas não lidas');

  /* linha Arquivadas no topo de Todas, com o total de não lidas delas */
  const linha = await p.evaluate(() => { const l = document.querySelector('#wa-lista > .arquivadas-linha, #wa-lista .arquivadas-linha'); return l && { nome: l.querySelector('.nome-c').textContent, qtd: l.querySelector('.qtd')?.textContent, primeira: l === document.querySelector('#wa-lista').firstElementChild } });
  h.ok(linha && linha.nome === 'Arquivadas' && linha.qtd === '9' && linha.primeira, `a linha Arquivadas fica no topo com as 9 não lidas delas (${JSON.stringify(linha)})`);

  /* Contatos e Grupos: mesmo recorte por tipo, lidas e não lidas */
  h.ok((await filtro(p, 'contatos')).join('|') === 'Carla Dias|Ana Souza|Beto Lima', 'Contatos: não arquivados, lidos e não lidos');
  h.ok((await filtro(p, 'grupos')).join('|') === 'Equipe do Palco|Louvor', 'Grupos: não arquivados, lidos e não lidos');
  h.ok(await p.evaluate(() => !document.querySelector('#wa-lista .arquivadas-linha')), 'a linha Arquivadas só existe em Todas');

  /* Arquivadas: só as arquivadas, no mesmo formato, lidas e não lidas */
  await filtro(p, 'todas');
  await p.click('#wa-lista .arquivadas-linha'); await p.waitForTimeout(80);
  h.ok((await nomes(p)).join('|') === 'Bia Arquivada|Promo Arquivada|Sorteio Arquivado', `a linha leva às arquivadas (${(await nomes(p)).join('|')})`);
  h.ok(await p.evaluate(() => document.querySelector('#wa-filtro [data-f="arquivadas"]').getAttribute('aria-pressed')) === 'true', 'o filtro Arquivadas fica marcado');
  const selosArq = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa')].map(c => c.querySelector('.qtd')?.textContent ?? '-'));
  h.ok(selosArq.join(',') === '3,-,6', `nas arquivadas o selo também só aparece quando há (${selosArq.join(',')})`);
  h.ok((await texto(p, '#wa-titulo')) === 'WhatsApp 6 não lidas em 2 conversas', 'dentro das arquivadas o título segue sem contar as arquivadas');

  /* abrir a conversa continua mostrando as mensagens: a lida mostra a última, a não lida mostra as não lidas */
  await filtro(p, 'todas');
  await p.click('#wa-lista [data-wa="t1@s.whatsapp.net"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .mensagens p').length === 2), 'abrir uma conversa não lida mostra as não lidas');
  await p.click('#wa-lista [data-wa="t2@lid"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .mensagens p').length === 1), 'abrir uma lida mostra a última mensagem');
  await p.context().close(); // a folha aberta seguiria lendo a lista e contaria nos pedidos dos testes seguintes
}
