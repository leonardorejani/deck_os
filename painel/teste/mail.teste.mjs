// Tela do Mail (SPEC, seção 5): as últimas mensagens da caixa de entrada, lidas e não lidas, troca de conta e abrir no Mac.
// Dados inventados do Mac de mentira (servidor-falso.mjs).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aberta = (p, id) => p.evaluate(i => document.querySelector(i).classList.contains('aberta'), id);
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
const linhas = p => p.evaluate(() => [...document.querySelectorAll('#ma-lista .conversa.mail')].map(l => ({ de: l.querySelector('.nome-c').textContent, assunto: l.querySelector('.assunto-m').textContent, previa: l.querySelector('.previa').textContent, hora: l.querySelector('.lado > span').textContent, naoLida: l.classList.contains('nao-lida'), ponto: !l.querySelector('.ponto-nl').hidden, id: l.dataset.mail })));
const abrir = async (h, p) => { await p.click('.tecla[data-id="mail"]'); return h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail, #ma-lista .vazio-bloco').length > 0) };

export default async function (h) {
  await h.cenario({ mailTecla: true });
  let p = await h.pagina(); await pronta(h, p);

  /* ---------- a lista ---------- */
  h.ok(await abrir(h, p), 'tocar na tecla do Mail abre a folha com a lista');
  let c = await h.contadores();
  h.ok(await aberta(p, '#f-mail') && c.botoes.length === 0, `a tecla abre a lista no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  const l = await linhas(p);
  h.ok(l.length === 4, `a lista tem as 4 mensagens (${l.length})`);
  h.ok(l[0].de === 'Ana Souza' && l[0].assunto === 'Reunião de terça' && l[0].previa.startsWith('Oi, segue o resumo') && /^\d\d:\d\d$/.test(l[0].hora), `a linha mostra remetente, assunto, prévia e hora (${JSON.stringify(l[0])})`);
  h.ok(l[0].naoLida && l[0].ponto && l[1].naoLida && !l[2].naoLida && !l[2].ponto && !l[3].ponto, 'a marca de não lida aparece só nas não lidas, e as lidas ficam sem ela');
  h.ok(l[2].hora === 'ontem' && !/^\d\d:\d\d$/.test(l[3].hora), `hora de ontem diz "ontem" e a mais antiga diz o dia (${l[2].hora}, ${l[3].hora})`);
  h.ok(await texto(p, '#ma-titulo') === 'Mail 2 não lidas nas últimas 4', `título com as não lidas (${await texto(p, '#ma-titulo')})`);
  const peso = await p.evaluate(() => { const [a, , b] = document.querySelectorAll('#ma-lista .conversa.mail'); return [getComputedStyle(a.querySelector('.assunto-m')).fontWeight, getComputedStyle(b.querySelector('.assunto-m')).fontWeight] });
  h.ok(Number(peso[0]) > Number(peso[1]), `a não lida fica em negrito e a lida não (${peso.join(' x ')})`);
  await h.dormir(500); await h.foto(p, 'mail-lista');
  h.ok(await p.evaluate(() => document.querySelector('#ma-lista').getAttribute('aria-busy')) === 'false', 'a lista não fica marcada como carregando depois de chegar');

  /* ---------- troca de conta ---------- */
  const contas = await p.evaluate(() => [...document.querySelectorAll('#ma-contas button')].map(b => ({ nome: b.textContent, marcada: b.getAttribute('aria-pressed') })));
  h.ok(contas.map(x => x.nome).join() === 'iCloud,Trabalho,Gmail' && contas[0].marcada === 'true' && contas[1].marcada === 'false', `a troca de conta mostra as 3 contas do Mail do Mac, a primeira marcada (${JSON.stringify(contas)})`);
  await p.click('#ma-contas [data-conta="conta-2"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail').length === 2 && document.querySelector('#ma-contas [data-conta="conta-2"]').getAttribute('aria-pressed') === 'true'), 'trocar de conta mostra a caixa da outra conta');
  h.ok((await linhas(p))[0].de === 'Financeiro', 'a lista é a da conta escolhida');
  c = await h.contadores();
  h.ok(c.mail.includes('conta-2'), `o pedido leva a conta escolhida (${c.mail.join()})`);
  await p.click('#f-mail [data-fechar]');
  await h.espera(p, () => !document.querySelector('#f-mail').classList.contains('aberta'));
  await abrir(h, p);
  h.ok(await h.espera(p, () => document.querySelector('#ma-contas [data-conta="conta-2"]')?.getAttribute('aria-pressed') === 'true'), 'ao abrir de novo, a conta escolhida da última vez continua');

  /* ---------- abrir no Mac ---------- */
  await h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail').length === 2);
  await p.click('#ma-lista .conversa.mail');
  h.ok(await h.ate(async () => (await h.contadores()).mailAbertas.length === 1), 'tocar numa mensagem pede ao Mac para abrir ela no Mail');
  c = await h.contadores();
  h.ok(c.mailAbertas[0] === 'conta-2-m1@exemplo.com', `a mensagem certa vai ao Mac (${c.mailAbertas[0]})`);
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Abrindo a mensagem no Mail do Mac'), 'o aviso diz que a mensagem abre no Mail do Mac');
  h.ok(await aberta(p, '#f-mail') && c.botoes.length === 0, 'a lista continua aberta e nenhuma tecla foi apertada');
  await p.click('#ma-abrir');
  await h.ate(async () => (await h.contadores()).botoes.length === 1);
  c = await h.contadores();
  h.ok(c.botoes.join() === 'mail', `"Abrir no Mac" manda a tecla do Mail (${c.botoes.join()})`);

  /* ---------- a lista acompanha o Mac ---------- */
  await h.cenario({ mail: 'vazio' });
  h.ok(await h.espera(p, () => document.querySelector('#ma-lista .vazio-bloco strong')?.textContent === 'Caixa de entrada vazia', 7000), 'a lista aberta acompanha o Mac sozinha (caixa esvaziou)');
  await p.close();

  /* ---------- uma conta só: sem seletor ---------- */
  await h.cenario({ mail: 'uma-conta' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await p.evaluate(() => document.querySelector('#ma-contas').hidden), 'com uma conta só, a troca de conta não aparece');
  h.ok((await texto(p, '#ma-titulo')).endsWith(', iCloud'), `o título diz de qual conta é (${await texto(p, '#ma-titulo')})`);
  await p.close();

  /* ---------- estados ---------- */
  await h.cenario({ mail: 'fechado' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await texto(p, '#ma-lista .vazio-bloco strong') === 'Mail fechado' && (await texto(p, '#ma-lista .vazio-bloco')).includes('Abra o Mail no Mac'), 'Mail fechado diz "Abra o Mail no Mac"');
  const antes = (await h.contadores()).botoes.length;
  await p.click('#ma-lista [data-ma-mac]');
  await h.ate(async () => (await h.contadores()).botoes.length === antes + 1);
  h.ok((await h.contadores()).botoes.at(-1) === 'mail', 'o botão do aviso manda a tecla do Mail para o Mac abrir o app');
  await p.close();

  await h.cenario({ mail: 'sem-permissao' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await texto(p, '#ma-lista .vazio-bloco strong') === 'Mail sem permissão' && (await texto(p, '#ma-lista .vazio-bloco')).includes('Automação'), 'sem permissão da Automação, a tela diz onde liberar');
  await p.close();

  await h.cenario({ mail: 'vazio' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await texto(p, '#ma-lista .vazio-bloco strong') === 'Caixa de entrada vazia', 'caixa vazia não fica em branco');
  await p.close();

  await h.cenario({ mail: 'erro' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await h.espera(p, () => document.querySelector('#ma-lista [data-tentar]') !== null) && (await texto(p, '#ma-lista')).includes('O Mail não respondeu no Mac.'), 'erro da leitura mostra o motivo e "Tentar de novo"');
  await h.cenario({ mail: 'normal' });
  await p.click('#ma-lista [data-tentar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail').length === 4), '"Tentar de novo" traz a lista quando o Mac volta');
  await p.close();

  await h.cenario({ mail: 'antigo' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await h.espera(p, () => document.querySelector('#ma-lista')?.textContent.includes('Atualize o Deck no Mac')), 'Mac antigo, sem a rota do Mail, pede para atualizar o Deck');
  await p.close();

  await h.cenario({ mail: 'normal', atrasoMail: 900 });
  p = await h.pagina(); await pronta(h, p); await p.click('.tecla[data-id="mail"]');
  h.ok(await h.espera(p, () => document.querySelector('#ma-lista .esq-lista') !== null && document.querySelector('#ma-lista').getAttribute('aria-busy') === 'true', undefined, 1500), 'enquanto o Mac lê, aparece o esqueleto da lista');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail').length === 4), 'e a lista chega depois');
  await p.close();

  /* ---------- recusa ao abrir, tecla com ação, texto longo e HTML malicioso ---------- */
  await h.cenario({ atrasoMail: 0, mailAbreRecusa: 'Não consegui abrir a mensagem no Mail.' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await p.click('#ma-lista .conversa.mail');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro') && document.querySelector('#aviso-txt').textContent === 'Não consegui abrir a mensagem no Mail.'), 'o Mac recusar abrir a mensagem aparece como erro');
  await p.close();

  await h.cenario({ mailAbreRecusa: '' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="mail-caixa"]');
  await h.ate(async () => (await h.contadores()).botoes.includes('mail-caixa'));
  h.ok(!(await aberta(p, '#f-mail')) && (await h.contadores()).botoes.includes('mail-caixa'), 'tecla do Mail com ação (caixa de uma conta) vai para o Mac e não abre a lista do iPhone');
  await p.close();

  await h.cenario({ textoLongo: true, mail: 'muitas' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await h.espera(p, () => document.querySelectorAll('#ma-lista .conversa.mail').length === 20);
  const caixa = await p.evaluate(() => { const e = document.querySelector('#ma-lista'); return { n: document.querySelectorAll('#ma-lista .conversa.mail').length, estouro: [...document.querySelectorAll('#ma-lista .conversa.mail')].some(l => l.scrollWidth > l.clientWidth + 1) || e.scrollWidth > e.clientWidth + 1, rola: e.scrollHeight > e.clientHeight + 20 } });
  h.ok(caixa.n === 20 && !caixa.estouro && caixa.rola, `20 mensagens com texto comprido rolam sem estourar a largura (${JSON.stringify(caixa)})`);
  await h.foto(p, 'mail-muitas');
  await p.close();

  await h.cenario({ textoLongo: false, mail: 'normal', xss: true, mailTecla: true });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss), 'texto do Mail com HTML malicioso aparece como texto e não executa');
  await p.close();

  /* ---------- em pé ---------- */
  await h.cenario({ xss: false });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p); await abrir(h, p);
  const pe = await p.evaluate(() => { const h2 = document.querySelector('#f-mail > header'), r = h2.getBoundingClientRect(), tela = document.querySelector('#f-mail').getBoundingClientRect(); return { dentro: r.right <= tela.right + 1 && r.left >= tela.left - 1, contas: !document.querySelector('#ma-contas').hidden } });
  h.ok(pe.dentro && pe.contas, `em pé, o topo com a troca de conta cabe na tela (${JSON.stringify(pe)})`);
  await h.foto(p, 'mail-em-pe');
  await p.close();
}
