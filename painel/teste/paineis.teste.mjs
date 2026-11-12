// Painéis de tela inteira (SPEC, seção 5): WhatsApp, Agenda e Sessões, com o Mac de mentira.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aberta = (p, id) => p.evaluate(i => document.querySelector(i).classList.contains('aberta'), id);
const aviso = p => p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, visivel: document.querySelector('#aviso').classList.contains('visivel'), erro: document.querySelector('#aviso').classList.contains('erro') }));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
// a lista rola, sem barra visível (largura da barra zero) e o conteúdo é maior que a folha
const rola = (p, sel) => p.evaluate(s => { const e = document.querySelector(s); return { passa: e.scrollHeight > e.clientHeight + 20, semBarra: e.offsetWidth - e.clientWidth - parseFloat(getComputedStyle(e).borderLeftWidth) - parseFloat(getComputedStyle(e).borderRightWidth) === 0 && getComputedStyle(e).scrollbarWidth === 'none', y: (e.scrollTop = 200, e.scrollTop) } }, sel);
const dias = a => ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'][a];
const iso = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const AVULSOS = [3, 10, 12, 15, 21, 27];

export default async function (h) {
  /* ---------- WhatsApp ---------- */
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => [...document.querySelectorAll('.folha')].every(f => getComputedStyle(f).pointerEvents === 'none')), 'folha fechada não pega toque (não cobre a que está aberta)');
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5), 'tocar na tecla do WhatsApp abre a folha com as 5 conversas');
  let c = await h.contadores();
  h.ok(await aberta(p, '#f-whats') && c.botoes.length === 0, `a tecla abre a lista no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  h.ok(await texto(p, '#wa-titulo') === 'WhatsApp 23 não lidas em 5 conversas', `título com o total (${await texto(p, '#wa-titulo')})`);
  await h.dormir(500); await h.foto(p, 'whatsapp-lista');
  const linha = await p.evaluate(() => { const c = document.querySelector('#wa-lista .conversa'); return { nome: c.querySelector('.nome-c').textContent, grupo: !!c.querySelector('.avatar svg'), previa: c.querySelector('.previa').textContent, qtd: c.querySelector('.qtd').textContent, inic: document.querySelectorAll('#wa-lista .conversa')[1].querySelector('.avatar').textContent } });
  h.ok(linha.nome === 'Ministério de Louvorgrupo' && linha.grupo && linha.previa === 'Carla: Quem leva o cabo P10?' && linha.qtd === '12' && linha.inic === 'M', `a linha mostra nome, ícone de grupo, quem mandou, última mensagem e quantidade (${JSON.stringify(linha)})`);
  h.ok(/^\d\d:\d\d$/.test(await p.evaluate(() => document.querySelector('#wa-lista .conversa .lado > span:first-child').textContent)), 'a hora da conversa de hoje é HH:MM');
  h.ok(await p.evaluate(() => document.querySelectorAll('#wa-lista .conversa .lado > span:first-child')[3].textContent) === 'ontem', 'a conversa de ontem diz "ontem"');
  // filtros
  const filtro = async f => { await p.click(`#wa-filtro [data-f="${f}"]`); return p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .nome-c')].map(x => x.textContent.replace('grupo', '')).join('|')) };
  h.ok(await filtro('contatos') === 'Mãe|Pastor João|Rafael', 'filtro Contatos mostra só as conversas diretas');
  h.ok(await filtro('grupos') === 'Ministério de Louvor|Equipe do app', 'filtro Grupos mostra só os grupos');
  h.ok((await filtro('todas')).split('|').length === 5 && await p.evaluate(() => document.querySelector('#wa-filtro [data-f="todas"]').getAttribute('aria-pressed')) === 'true', 'filtro Todas volta com as 5');
  // abrir uma conversa: mensagens com o nome de quem mandou, e abrir outra recolhe a anterior
  await p.click('#wa-lista [data-wa="w1"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .mensagens p').length === 3), 'tocar na conversa abre as 3 mensagens não lidas');
  const msgs = await p.evaluate(() => ({ de: [...document.querySelectorAll('#wa-lista .mensagens p small')].map(x => x.textContent).join(), exp: document.querySelector('[data-wa="w1"]').getAttribute('aria-expanded'), btn: document.querySelector('#wa-lista [data-wa-mac]')?.textContent, balao: document.querySelector('#wa-lista .mensagens p').getAnimations().length }));
  h.ok(msgs.de === 'Carla,Pedro,Carla' && msgs.exp === 'true' && msgs.btn === 'Responder no Mac', `em grupo, cada balão diz quem mandou e tem "Responder no Mac" (${JSON.stringify(msgs)})`);
  h.ok(msgs.balao > 0, 'os balões entram em cascata (animação em andamento)');
  await h.dormir(700); await h.foto(p, 'whatsapp-aberta');
  await p.click('#wa-lista [data-wa="w2"]');
  h.ok(await h.espera(p, () => document.querySelector('[data-wa="w2"]').getAttribute('aria-expanded') === 'true' && document.querySelectorAll('#wa-lista .mensagens').length === 1), 'abrir outra conversa recolhe a anterior');
  h.ok(await p.evaluate(() => document.querySelectorAll('#wa-lista .mensagens p small').length === 0), 'conversa direta: balões sem nome de quem mandou');
  await h.dormir(600);
  // os dois botões mandam a tecla do WhatsApp pelo Mac
  await p.click('#wa-lista [data-wa-mac]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Abrindo o WhatsApp no Mac'), 'Responder no Mac avisa que abre o WhatsApp no Mac');
  await p.click('#wa-abrir');
  await h.dormir(300); c = await h.contadores();
  h.ok(c.botoes.join() === 'whatsapp,whatsapp', `"Responder no Mac" e "Abrir no Mac" mandam a tecla do WhatsApp (${c.botoes.join()})`);
  // fechar
  await p.click('#f-whats [data-fechar]');
  h.ok(await h.espera(p, () => !document.querySelector('#f-whats').classList.contains('aberta') && !document.querySelector('#tela').classList.contains('com-folha')), 'o X fecha a folha');
  // reabrir começa do zero: filtro Todas, nenhuma conversa aberta
  await p.click('.tecla[data-id="whatsapp"]'); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelectorAll('#wa-lista .mensagens').length === 0 && document.querySelector('#wa-filtro [data-f="todas"]').getAttribute('aria-pressed') === 'true'), 'ao reabrir, filtro Todas e nenhuma conversa aberta');
  // em pé
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(400); await h.foto(p, 'whatsapp-em-pe');
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1 && document.querySelector('#wa-abrir').getBoundingClientRect().right <= innerWidth), 'em pé: nada passa da largura');
  await p.context().close();

  /* WhatsApp Web: o Mac só vê o total pelo título da aba, e a folha diz isso sem inventar conversas */
  await h.cenario({ whatsappOrigem: 'web' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelector('#wa-titulo').textContent.includes('23 não lidas') && !!document.querySelector('#wa-lista .vazio-bloco')), 'pelo WhatsApp Web a folha mostra o total das não lidas');
  const web = await p.evaluate(() => ({ conversas: document.querySelectorAll('#wa-lista .conversa').length, filtro: document.querySelector('#wa-filtro').hidden, txt: document.querySelector('#wa-lista .vazio-bloco').textContent.replace(/\s+/g, ' ').trim() }));
  h.ok(web.conversas === 0 && web.filtro === true, `sem lista por conversa e sem filtro (${JSON.stringify(web)})`);
  h.ok(web.txt === '23 não lidasPelo WhatsApp Web o Deck vê só o total. Para ver cada conversa, use o app do WhatsApp no Mac.', `texto curto e honesto sobre ver só o total (${web.txt})`);
  await h.dormir(400); await h.foto(p, 'whatsapp-web');
  const botoesAntes = (await h.contadores()).botoes.length;
  await p.click('#wa-abrir'); await h.dormir(300);
  h.ok((await h.contadores()).botoes.slice(botoesAntes).join() === 'whatsapp', '"Abrir no Mac" segue mandando a tecla do WhatsApp (o Mac abre o WhatsApp Web)');
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(400); await h.foto(p, 'whatsapp-web-em-pe');
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'WhatsApp Web em pé: nada passa da largura');
  await p.context().close();
  // sem aba aberta: avisa em vez de dizer "0 não lidas"
  await h.cenario({ whatsappOrigem: 'web-fechado' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .vazio-bloco')), 'WhatsApp Web sem aba: a folha abre');
  const fechadoTxt = await texto(p, '#wa-lista .vazio-bloco');
  h.ok(fechadoTxt.startsWith('WhatsApp Web fechadoO WhatsApp Web não está aberto no navegador (Arc). Abra web.whatsapp.com') && await texto(p, '#wa-titulo') === 'WhatsApp', `sem aba, diz que o WhatsApp Web está fechado e não "0 não lidas" (${fechadoTxt})`);
  await p.context().close();
  // aparelho conectado por QR: lista por conversa igual ao app, com a origem "qr"
  await h.cenario({ whatsappOrigem: 'qr' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5), 'WhatsApp por QR conectado: a lista por conversa aparece, como no app');
  h.ok(await p.evaluate(() => !document.querySelector('#wa-filtro').hidden), 'WhatsApp por QR conectado: o filtro de grupos fica');
  await p.context().close();
  // QR caído: o 0 não é medição, a folha manda abrir os Ajustes no Mac
  await h.cenario({ whatsappOrigem: 'qr-caido' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .vazio-bloco')), 'WhatsApp por QR caído: a folha abre');
  const qrTxt = await texto(p, '#wa-lista .vazio-bloco');
  h.ok(qrTxt.startsWith('WhatsApp por QR sem conexão') && qrTxt.includes('Ajustes do Deck no Mac') && await texto(p, '#wa-titulo') === 'WhatsApp', `QR caído diz que está sem conexão e não "0 não lidas" (${qrTxt})`);
  await p.context().close();
  await h.cenario({ whatsappOrigem: 'app' });

  /* lista maior que a folha rola sem barra, e a leitura de 4 s não puxa para o topo */
  await h.cenario({ whatsapp: 'muitas' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 30);
  let r = await rola(p, '#wa-lista');
  h.ok(r.passa && r.semBarra && r.y > 0, `30 conversas: a lista rola sem barra visível (${JSON.stringify(r)})`);
  await h.foto(p, 'whatsapp-muitas');
  await h.cenario({ whatsapp: 'muitas' }); await h.dormir(4600);
  h.ok(await p.evaluate(() => document.querySelector('#wa-lista').scrollTop) === 200, 'a leitura que se repete não muda a lista nem a rolagem');
  await p.context().close();

  /* vazio, erro e HTML malicioso */
  await h.cenario({ whatsapp: 'vazio' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.espera(p, () => document.querySelector('#wa-titulo').textContent.includes('0 não lidas'));
  h.ok(await texto(p, '#wa-lista') === 'Nada aquiSem não lidas nesse filtro.' && await texto(p, '#wa-titulo') === 'WhatsApp 0 não lidas em 0 conversas', 'sem conversas: "Nada aqui"');
  await h.foto(p, 'whatsapp-vazio');
  await p.context().close();
  await h.cenario({ whatsapp: 'erro' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista [data-tentar]')), 'o Mac falhando mostra o motivo e "Tentar de novo"');
  h.ok((await texto(p, '#wa-lista')).includes('O WhatsApp não respondeu no Mac.'), 'o motivo vem do Mac');
  await h.foto(p, 'whatsapp-erro');
  await h.cenario({ whatsapp: 'normal' }); await p.click('#wa-lista [data-tentar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5), '"Tentar de novo" lê outra vez e mostra a lista');
  await p.context().close();
  await h.cenario({ whatsapp: 'normal', xss: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5);
  await p.click('#wa-lista [data-wa="w1"]'); await h.dormir(700);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#wa-lista img').length === 0), 'texto do WhatsApp com HTML aparece como texto e não executa');
  // marcação que sobrava: cerca de código, link, itálico, __forte__ e citação
  const lim = await p.evaluate(() => limparContexto('Veja:\n```bash\nls -la | grep x\n# comentario do shell\n```\n\n- item *italico* e [link](https://x.com) e __forte__\n\n> citacao'));
  h.ok(lim === 'Veja:\nls -la | grep x\n# comentario do shell\n\n- item italico e link e forte\n\ncitacao', `contexto sem cerca de código, link, itálico nem citação, e o comando dentro da cerca fica intacto (${JSON.stringify(lim)})`);
  await p.context().close(); await h.cenario({ xss: false });

  /* ---------- Agenda ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const hoje = new Date(), mes0 = new Date(hoje.getFullYear(), hoje.getMonth(), 1), diasDoMes = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0).getDate();
  await p.click('.tecla[data-id="calendario"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ca-grade .sb-dia.tem').length > 0), 'tocar na tecla da Agenda abre o mês com pontos nos dias com evento');
  c = await h.contadores();
  h.ok(c.botoes.length === 0 && await aberta(p, '#f-cal'), 'a tecla abre a agenda no iPhone, sem mandar nada ao Mac');
  h.ok(c.agenda.includes(`${iso(mes0)}|${diasDoMes}`) && c.agenda.includes(`${iso(hoje)}|30`), `pede agenda(1º do mês, dias do mês) e agenda(hoje, 30) (${c.agenda.join(' ')})`);
  const esperados = new Set(); // dias com evento neste mês, pela mesma regra do Mac de mentira
  for (let d = 1; d <= diasDoMes; d++) { const dow = new Date(hoje.getFullYear(), hoje.getMonth(), d).getDay(); if (dow === 0 || dow === 2 || dow === 4 || AVULSOS.includes(d)) esperados.add(d) }
  const tem = await p.evaluate(() => [...document.querySelectorAll('#ca-grade .sb-dia.tem')].map(x => +x.textContent));
  h.ok(tem.join() === [...esperados].join(), `ponto só nos dias com evento (${tem.join()})`);
  const cab = await p.evaluate(() => ({ titulo: document.querySelector('#ca-titulo').textContent, hoje: document.querySelector('.sb-dia.hoje')?.textContent, vazios: document.querySelectorAll('#ca-grade > span').length, primeiro: getComputedStyle(document.querySelector('#ca-titulo')).textTransform }));
  h.ok(cab.titulo === hoje.toLocaleDateString('pt-BR', { month: 'long' }) && cab.primeiro === 'uppercase' && +cab.hoje === hoje.getDate() && cab.vazios === mes0.getDay(), `mês em caixa alta, hoje marcado e o 1º no dia da semana certo (${JSON.stringify(cab)})`);
  const grupo1 = await texto(p, '#ca-lista .grupo-data h3');
  h.ok(grupo1 !== null, `a lista por data começa no primeiro dia com evento (${grupo1})`);
  await h.dormir(500); await h.foto(p, 'agenda-mes');
  // trocar de mês pela seta
  const titulo0 = await texto(p, '#ca-titulo'); c = await h.contadores(); const n0 = c.agenda.length;
  await p.click('#ca-prox'); await h.dormir(500);
  const prox = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 1);
  c = await h.contadores();
  h.ok(await texto(p, '#ca-titulo') !== titulo0 && c.agenda.length === n0 + 1 && c.agenda[n0] === `${iso(prox)}|${new Date(prox.getFullYear(), prox.getMonth() + 1, 0).getDate()}`, `a seta troca o mês e pede só a agenda do mês novo (${c.agenda[n0]})`);
  h.ok(await p.evaluate(() => document.querySelector('.sb-dia.hoje') === null), 'em outro mês, o "hoje" não aparece');
  await p.click('#ca-ant'); await h.dormir(500);
  h.ok(await texto(p, '#ca-titulo') === titulo0, 'a seta de trás volta ao mês de hoje');
  // deslizar
  const caixa = await p.locator('#ca-mes').boundingBox(), y = caixa.y + caixa.height / 2;
  await p.mouse.move(caixa.x + caixa.width - 40, y); await p.mouse.down(); await p.mouse.move(caixa.x + caixa.width - 200, y, { steps: 6 }); await p.mouse.up(); await h.dormir(500);
  h.ok(await texto(p, '#ca-titulo') !== titulo0, 'deslizar para a esquerda vai para o mês seguinte');
  await p.mouse.move(caixa.x + 40, y); await p.mouse.down(); await p.mouse.move(caixa.x + 200, y, { steps: 6 }); await p.mouse.up(); await h.dormir(500);
  h.ok(await texto(p, '#ca-titulo') === titulo0, 'deslizar para a direita volta');
  await p.mouse.move(caixa.x + 40, y); await p.mouse.down(); await p.mouse.move(caixa.x + 70, y + 80, { steps: 6 }); await p.mouse.up(); await h.dormir(400);
  h.ok(await texto(p, '#ca-titulo') === titulo0, 'um arrasto curto ou na vertical não troca de mês');
  // tocar num dia: a lista recomeça nele (o primeiro dia depois de hoje com evento)
  const comEvento = (a, m) => { const l = []; for (let d = 1; d <= new Date(a, m + 1, 0).getDate(); d++) { const dow = new Date(a, m, d).getDay(); if (dow === 0 || dow === 2 || dow === 4 || AVULSOS.includes(d)) l.push(d) } return l };
  let alvoMes = hoje.getMonth(), alvoDia = comEvento(hoje.getFullYear(), alvoMes).find(d => d > hoje.getDate());
  if (!alvoDia) { await p.click('#ca-prox'); await h.dormir(500); alvoMes++; alvoDia = comEvento(hoje.getFullYear(), alvoMes)[0] }
  const alvo = new Date(hoje.getFullYear(), alvoMes, alvoDia);
  await p.click(`#ca-grade .sb-dia:nth-child(${alvo.getDate() + new Date(alvo.getFullYear(), alvo.getMonth(), 1).getDay()})`);
  const nomeEsperado = `${alvo.getDate()} de ${alvo.toLocaleDateString('pt-BR', { month: 'long' })}`;
  h.ok(await h.espera(p, n => document.querySelector('#ca-lista h3')?.textContent.endsWith(n), nomeEsperado, 3000), `tocar no dia ${nomeEsperado} pede a lista dele e ela começa nele (${await texto(p, '#ca-lista h3')})`);
  c = await h.contadores();
  h.ok(c.agenda.at(-1) === `${iso(alvo)}|30`, `pede agenda(dia tocado, 30) (${c.agenda.at(-1)})`);
  h.ok(await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia.sel').length === 1), 'o dia tocado fica marcado');
  // tocar no evento abre "Abrir no Calendário do Mac"
  await p.click('#ca-lista .ev-linha');
  h.ok(await h.espera(p, () => !!document.querySelector('#ca-lista [data-ev-mac]')), 'tocar no evento mostra "Abrir no Calendário do Mac"');
  await h.foto(p, 'agenda-evento');
  await p.click('#ca-lista [data-ev-mac]'); await h.dormir(300);
  c = await h.contadores();
  h.ok(c.botoes.join() === 'calendario' && (await aviso(p)).txt === 'Abrindo o Calendário no Mac', `manda a tecla da Agenda pelo Mac (${c.botoes.join()})`);
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(500); await h.foto(p, 'agenda-em-pe');
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1 && document.querySelector('#ca-lista').getBoundingClientRect().bottom <= innerHeight + 1), 'em pé: o mês em cima, a lista embaixo, nada passa da tela');
  await p.context().close();

  /* lista lotada rola sem barra */
  await h.cenario({ agenda: 'muitas' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 14);
  r = await rola(p, '#ca-lista');
  h.ok(r.passa && r.semBarra && r.y > 0, `agenda cheia: a lista rola sem barra visível (${JSON.stringify(r)})`);
  await h.foto(p, 'agenda-cheia');
  await p.context().close();

  /* agenda vazia, sem permissão e com erro */
  await h.cenario({ agenda: 'vazia' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]');
  h.ok(await h.espera(p, () => document.querySelector('#ca-lista')?.textContent.includes('Nada nos próximos 30 dias')), 'agenda vazia: "Nada nos próximos 30 dias"');
  h.ok(await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia.tem').length === 0 && document.querySelectorAll('#ca-grade .sb-dia').length >= 28), 'agenda vazia: o mês aparece sem pontos');
  await h.foto(p, 'agenda-vazia');
  await p.context().close();
  await h.cenario({ agenda: 'sem' });
  p = await h.pagina(); await pronta(h, p);
  await h.espera(p, () => document.querySelector('.tecla[data-id="calendario"] .selo')?.textContent === '!');
  const antes = (await h.contadores()).agenda.length;
  await p.click('.tecla[data-id="calendario"]'); await h.dormir(700);
  h.ok((await texto(p, '#ca-lista')) === 'Agenda sem permissãoNo Mac: Ajustes > Privacidade > Calendários, ligue o Deck.', `sem permissão: a folha explica onde liberar no Mac (${await texto(p, '#ca-lista')})`);
  c = await h.contadores();
  h.ok(c.agenda.length === antes && await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia.tem').length === 0), 'sem permissão: nem pede a agenda ao Mac');
  await h.foto(p, 'agenda-sem-permissao');
  await p.click('#ca-prox'); await h.dormir(500); c = await h.contadores();
  h.ok(c.agenda.length === antes, 'sem permissão: trocar de mês também não pede nada');
  await p.context().close();
  await h.cenario({ agenda: 'erro' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#ca-lista [data-tentar]')) && (await texto(p, '#ca-lista')).includes('O Calendário não respondeu no Mac.'), 'o Mac falhando na agenda mostra o motivo e "Tentar de novo"');
  await h.cenario({ agenda: 'normal' }); await p.click('#ca-lista [data-tentar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0 && document.querySelectorAll('#ca-grade .sb-dia.tem').length > 0), '"Tentar de novo" traz a lista e os pontos');
  await p.context().close();
  await h.cenario({ xss: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0); await p.click('#ca-lista .ev-linha'); await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#ca-lista img').length === 0), 'título de evento com HTML aparece como texto e não executa');
  await p.context().close(); await h.cenario({ xss: false });

  /* ---------- Sessões: um cartão por sessão, e a sessão aberta com a pergunta inteira ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const cartoes = () => p.evaluate(() => document.querySelectorAll('#se-lista .cartao-sessao').length);
  const abrirSessaoPor = id => p.click(`#se-lista [data-sessao="${id}"]`);
  await p.click('.sessoes');
  h.ok(await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5), 'tocar no bloco de sessões abre a tela com um cartão por sessão');
  c = await h.contadores();
  h.ok(await aberta(p, '#f-sessoes') && c.sessoes >= 1, `a lista vem de sessoes() (${c.sessoes} leitura)`);
  h.ok(await texto(p, '#se-titulo') === 'Sessões esperando 5 sessões', `título com a contagem (${await texto(p, '#se-titulo')})`);
  const it = await p.evaluate(() => [...document.querySelectorAll('#se-lista .cartao-sessao')].map(i => i.querySelector('b').textContent + '|' + i.querySelector('small').textContent));
  h.ok(it[0] === 'convite novos usuarios|app_web, há 5 min' && it[4] === 'podio ranking pontuação|app_web, há 4 dias', `cada cartão traz nome, projeto e há quanto tempo, o mais recente primeiro (${it[0]} ... ${it[4]})`);
  h.ok(await p.evaluate(() => document.querySelector('#se-lista .cartao-sessao p').textContent) === 'Salvar o TXT de verificação do domínio no DNS?', 'e o começo da pergunta');
  h.ok(await p.evaluate(() => !document.querySelector('#se-lista [data-dispensar], #se-lista .item-sessao') && getComputedStyle(document.querySelector('#se-lista .grade-sessoes')).gridTemplateColumns.split(' ').length === 2), 'deitado, os cartões ficam em duas colunas, sem os botões da lista antiga');
  await h.dormir(500); await h.foto(p, 'sessoes-cartoes');
  await p.click('#f-sessoes [data-fechar]'); await h.dormir(500);
  // tocar num cartão: a sessão aberta, com a pergunta inteira, Dispensar e Voltar
  await h.cenario({ sessoes: 12 });
  await h.espera(p, () => document.querySelector('.sessoes')?.getAttribute('aria-label') === 'Sessões esperando: 12');
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 12);
  const clamp = await p.evaluate(() => { const e = document.querySelector('#se-lista .cartao-sessao:nth-child(6) p'); return { linhas: Math.round(e.getBoundingClientRect().height / parseFloat(getComputedStyle(e).lineHeight)), cortada: e.scrollHeight > e.clientHeight + 1 } });
  h.ok(clamp.linhas <= 3 && clamp.cortada, `no cartão a pergunta longa mostra só o começo (${clamp.linhas} linhas, cortada ${clamp.cortada})`);
  r = await rola(p, '#se-lista');
  h.ok(r.passa && r.semBarra && r.y > 0, `12 sessões: a tela dos cartões rola sem barra visível (${JSON.stringify(r)})`);
  await abrirSessaoPor('s9'); await h.dormir(300);
  const yLista = await p.evaluate(() => se.y); // onde a lista estava quando o cartão foi tocado (o Playwright rola até ele antes)
  const aberto = await p.evaluate(() => { const e = document.querySelector('#se-lista .detalhe-sessao .pergunta'); return { txt: e?.textContent, cortada: !!e && e.scrollHeight > e.clientHeight + 1, cartoes: document.querySelectorAll('#se-lista .cartao-sessao').length, titulo: document.querySelector('#se-titulo').textContent.replace(/\s+/g, ' '), rodape: [...document.querySelectorAll('#se-rodape button')].map(b => b.textContent), rodapeVisivel: !document.querySelector('#se-rodape').hidden, y: document.querySelector('#se-lista').scrollTop } });
  h.ok(aberto.txt.startsWith('Pergunta longa da sessão extra 4,') && aberto.txt.length > 400 && !aberto.cortada, `tocar no cartão abre a sessão com a pergunta inteira (${aberto.txt.length} caracteres, nada cortado)`);
  h.ok(aberto.cartoes === 0 && aberto.titulo === 'sessão extra 4 projeto_4, há 8 dias' && aberto.rodape.join() === 'Dispensar,Voltar' && aberto.rodapeVisivel && aberto.y === 0, `a sessão aberta mostra o nome, o projeto, Dispensar e Voltar, no topo (${aberto.titulo} | ${aberto.rodape})`);
  await h.foto(p, 'sessoes-aberta');
  await p.click('#se-rodape [data-voltar]'); await h.dormir(200);
  const volta = await p.evaluate(() => ({ cartoes: document.querySelectorAll('#se-lista .cartao-sessao').length, y: document.querySelector('#se-lista').scrollTop, rodape: document.querySelector('#se-rodape').hidden, titulo: document.querySelector('#se-titulo').textContent.replace(/\s+/g, ' ') }));
  h.ok(volta.cartoes === 12 && volta.rodape && volta.titulo === 'Sessões esperando 12 sessões' && Math.abs(volta.y - yLista) <= 2, `Voltar mostra os cartões de novo, no mesmo ponto da rolagem (${volta.y} e antes ${yLista})`);
  await p.context().close();
  // pergunta de 40 linhas: a sessão aberta rola, sem barra, deitado e em pé
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    await h.reset(); await h.cenario({ perguntaGigante: true });
    p = await h.pagina({ w, h: alt }); await pronta(h, p);
    await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
    if (w === 430) { await h.dormir(400); await h.foto(p, 'sessoes-cartoes-430') }
    await abrirSessaoPor('s1'); await h.dormir(700); // a folha termina de subir
    r = await rola(p, '#se-lista');
    h.ok(r.passa && r.semBarra && r.y > 0, `${nome}: a pergunta de 40 linhas rola sem barra visível (${JSON.stringify(r)})`);
    h.ok(await p.evaluate(() => { const b = document.querySelector('#se-rodape').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return !document.querySelector('#se-rodape').hidden && b.bottom <= t.bottom + 1 && [...document.querySelectorAll('#se-rodape button')].every(x => x.getBoundingClientRect().height >= 44 * (t.width / document.querySelector('#tela').offsetWidth) - 1) }), `${nome}: Dispensar e Voltar ficam à vista, com área de toque de 44 px`);
    await p.evaluate(() => { document.querySelector('#se-lista').scrollTop = 0 }); await h.dormir(100);
    await h.foto(p, `sessoes-aberta-${w}`);
    await p.context().close();
  }

  /* Contexto da sessão aberta: o pedido em destaque, a resposta sugerida, Abrir no Mac e o contexto legível embaixo */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'em pé']]) {
    await h.reset();
    p = await h.pagina({ w, h: alt }); await pronta(h, p);
    await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
    await abrirSessaoPor('s2'); await h.dormir(700);
    const d = await p.evaluate(() => { const q = x => document.querySelector('#se-lista ' + x); const rot = [...document.querySelectorAll('#se-lista .rotulo')].map(e => e.textContent);
      return { pergunta: q('.pergunta')?.textContent, sugestao: q('.sugestao p')?.textContent, rotulos: rot, ctx: q('.texto-contexto')?.innerText, paras: document.querySelectorAll('#se-lista .texto-contexto p').length,
        ordem: ['.pede', '[data-sessao-mac]', '.contexto'].map(x => q(x)?.getBoundingClientRect().top), cru: /\*\*|`|^#|\|---/m.test(q('.texto-contexto')?.textContent || '') } });
    h.ok(d.pergunta.startsWith('Escolha: A reserva 2 das 4 vagas') && d.sugestao === 'A, e pode abrir o PR rascunho', `${nome}: o pedido inteiro (needs) aparece em destaque, com a resposta sugerida (${d.pergunta.slice(0, 30)})`);
    h.ok(d.rotulos.join() === 'Pede a sua resposta,Resposta sugerida pela sessão,Contexto', `${nome}: blocos por assunto com rótulo (${d.rotulos})`);
    h.ok(d.ctx.includes('Com A sobram 2 vagas') && d.ctx.includes('1080p · 4 vagas') && !d.cru && d.paras >= 3, `${nome}: o contexto vem legível, sem marcação solta e com a tabela em linhas (${d.paras} parágrafos)`);
    h.ok(d.ordem[0] < d.ordem[1] && d.ordem[1] < d.ordem[2], `${nome}: ordem pedido, Abrir no Mac, contexto`);
    await p.click('#se-lista [data-sessao-mac]'); await h.dormir(300);
    h.ok((await h.contadores()).sessoesAbertas.includes('s2'), `${nome}: Abrir no Mac continua abrindo a sessão`);
    await h.foto(p, `sessoes-contexto-${w}`);
    await p.context().close();
  }
  // sessão de Mac antigo (sem pedido, contexto nem sugestão) continua abrindo com a pergunta
  await h.reset(); p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await abrirSessaoPor('s3'); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('#se-lista .pergunta').textContent === 'Você aprova o plano do runner 02 (e2e do ci-1)?' && !document.querySelector('#se-lista .contexto, #se-lista .sugestao')), 'sessão sem contexto: mostra a pergunta e não abre bloco vazio');
  await p.context().close();
  // texto do contexto com HTML malicioso aparece como texto
  await h.reset(); await h.cenario({ xss: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await abrirSessaoPor('s2'); await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#se-lista .texto-contexto img').length === 0 && document.querySelector('#se-lista .texto-contexto').textContent.includes('<img')), 'contexto com HTML aparece como texto e não executa');
  await p.context().close(); await h.cenario({ xss: false });

  /* Dispensar (na sessão aberta): some da lista e do bloco, fica guardado, volta quando a sessão muda */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await abrirSessaoPor('s1'); await p.click('#se-rodape [data-dispensar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 4 && document.querySelector('#se-titulo').textContent.includes('4 sessões') && document.querySelector('#se-rodape').hidden), 'Dispensar tira a sessão, volta aos cartões e a contagem cai');
  h.ok((await aviso(p)).txt === 'Dispensada até ela mudar de novo', 'aviso "Dispensada até ela mudar de novo"');
  h.ok(await p.evaluate(() => document.querySelector('.sessoes').getAttribute('aria-label') === 'Sessões esperando: 4' && !document.querySelector('.sessoes').textContent.includes('convite novos usuarios')), 'o bloco da tela principal também deixa de mostrar a dispensada');
  const guardada = await p.evaluate(() => JSON.parse(localStorage.getItem('deck-dispensadas-v1')));
  h.ok(Object.keys(guardada).join() === 's1', `guardada no aparelho (${Object.keys(guardada)})`);
  await h.dormir(2200);
  h.ok(await cartoes() === 4, 'a leitura seguinte do Mac não traz a dispensada de volta');
  await p.reload(); await pronta(h, p); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('.sessoes').getAttribute('aria-label')) === 'Sessões esperando: 4', 'recarregar a página mantém a dispensada escondida');
  await h.cenario({ sessaoMuda: true });
  h.ok(await h.espera(p, () => document.querySelector('.sessoes').getAttribute('aria-label') === 'Sessões esperando: 5', null, 5000), 'quando a sessão muda (outra pergunta), ela volta');
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  h.ok((await texto(p, '#se-lista .cartao-sessao p')) === 'Agora pode salvar o TXT no DNS?', 'e volta com a pergunta nova');
  // a sessão aberta some do Mac (respondida lá): volta aos cartões e avisa
  await abrirSessaoPor('s2'); await h.dormir(200);
  await h.cenario({ sessoes: 1 });
  h.ok(await h.espera(p, () => document.querySelector('#se-rodape').hidden && document.querySelectorAll('#se-lista .cartao-sessao').length === 1, null, 6000), 'se a sessão aberta é respondida no Mac, a tela volta aos cartões');
  h.ok((await aviso(p)).txt === 'Essa sessão já foi respondida', 'e avisa que ela já foi respondida');
  await p.context().close();
  // dispensar todas: "Ninguém esperando"
  await h.cenario({ sessaoMuda: false, sessoes: 1 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 1);
  await abrirSessaoPor('s1'); await p.click('#se-rodape [data-dispensar]'); await h.dormir(400);
  h.ok((await texto(p, '#se-lista')) === 'Ninguém esperandoQuando uma sessão do Claude pedir resposta, ela aparece aqui.' && await texto(p, '#se-titulo') === 'Sessões esperando 0 sessões', 'sem nenhuma sessão: "Ninguém esperando"');
  await h.foto(p, 'sessoes-vazia');
  await p.context().close();
  // armazenamento do aparelho bloqueado: a lista funciona do mesmo jeito (some até a próxima leitura)
  await h.cenario({ sessoes: 5 });
  p = await h.pagina({ antes: () => { Storage.prototype.getItem = () => { throw new Error('bloqueado') }; Storage.prototype.setItem = () => { throw new Error('bloqueado') } } }); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  await abrirSessaoPor('s2'); await p.click('#se-rodape [data-dispensar]'); await h.dormir(300);
  h.ok(await cartoes() === 4, 'com o armazenamento bloqueado, Dispensar ainda tira da lista e nada quebra');
  await p.context().close();
  // lixo no armazenamento não derruba a tela
  p = await h.pagina({ antes: () => localStorage.setItem('deck-dispensadas-v1', '[1,2') }); await pronta(h, p);
  await p.click('.sessoes'); h.ok(await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5), 'guardado quebrado é ignorado');
  await p.context().close();
  // HTML malicioso e organizar
  await h.cenario({ xss: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#se-lista img').length === 0), 'texto dos cartões das sessões com HTML aparece como texto e não executa');
  await p.click('#se-lista [data-sessao="s1"]'); await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss && document.querySelectorAll('#se-lista img, #se-titulo img').length === 0 && document.querySelector('#se-lista .pergunta').textContent.includes('<img')), 'e na sessão aberta também: aparece como texto e não executa');
  await p.context().close(); await h.cenario({ xss: false });
  p = await h.pagina(); await pronta(h, p);
  const c0 = await p.locator('.tecla[data-id="apagar"]').boundingBox();
  await p.mouse.move(c0.x + c0.width / 2, c0.y + c0.height / 2); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
  await p.mouse.click(...await p.locator('.sessoes').boundingBox().then(b => [b.x + b.width / 2, b.y + b.height / 2]));
  await h.dormir(400);
  h.ok(!(await aberta(p, '#f-sessoes')), 'no modo organizar, tocar no bloco de sessões não abre a lista');
  await p.context().close();
}
