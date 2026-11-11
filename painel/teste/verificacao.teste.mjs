// Defeitos achados pela verificação do PR dos painéis: esqueleto das listas, aviso repetido, texto sem espaço, "há X min" parado.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  // 1. esqueleto das listas enquanto o Mac lê
  await h.cenario({ atrasoListas: 2500 });
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.dormir(80);
  h.ok(await p.evaluate(() => (x => x ? getComputedStyle(x).opacity : 'sem esqueleto')(document.querySelector('#wa-lista .esq-lista'))) === '0', 'WhatsApp: nos primeiros 200 ms a lista não mostra nada');
  await h.dormir(1100);
  let e = await p.evaluate(() => ({ linhas: document.querySelectorAll('#wa-lista .esq-lista .conversa').length, op: (x => x ? getComputedStyle(x).opacity : 'sem esqueleto')(document.querySelector('#wa-lista .esq-lista')), busy: document.querySelector('#wa-lista').getAttribute('aria-busy') }));
  h.ok(e.linhas === 6 && e.op === '1' && e.busy === 'true', `WhatsApp: depois de 200 ms aparece o esqueleto com a forma das conversas (${JSON.stringify(e)})`);
  await h.foto(p, 'carregando-wa');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa:not(.esq)').length === 5 && !document.querySelector('#wa-lista .esq-lista'), null, 5000), 'WhatsApp: a lista chega e o esqueleto sai');
  await p.click('#f-whats [data-fechar]'); await h.dormir(500);
  await p.click('.tecla[data-id="calendario"]'); await h.dormir(1100);
  e = await p.evaluate(() => ({ linhas: document.querySelectorAll('#ca-lista .esq-lista .ev-linha').length, op: (x => x ? getComputedStyle(x).opacity : 'sem esqueleto')(document.querySelector('#ca-lista .esq-lista')) }));
  h.ok(e.linhas === 4 && e.op === '1', `Agenda: depois de 200 ms aparece o esqueleto com a forma dos eventos (${JSON.stringify(e)})`);
  await h.foto(p, 'carregando-ag');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha:not(.esq)').length > 0 && !document.querySelector('#ca-lista .esq-lista'), null, 5000), 'Agenda: os eventos chegam e o esqueleto sai');
  await p.context().close(); await h.cenario({ atrasoListas: 0 });

  // 2. leitura que falha com a lista na tela: aviso uma vez, e o filtro continua clicável
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5);
  await h.cenario({ whatsapp: 'erro' });
  await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel'), null, 6000);
  const amostra = await p.evaluate(async () => { const r = []; for (let i = 0; i < 20; i++) { r.push(document.querySelector('#aviso').classList.contains('visivel') ? 1 : 0); await new Promise(x => setTimeout(x, 500)) } return r.join('') });
  h.ok(!/1+0+1/.test(amostra) && /0$/.test(amostra), `WhatsApp: o aviso de erro aparece uma vez e some (${amostra})`);
  await p.click('#wa-filtro [data-f="contatos"]', { timeout: 2000 }).then(() => h.ok(true, 'WhatsApp: o filtro Contatos continua clicável com o Mac falhando'), () => h.ok(false, 'WhatsApp: o filtro Contatos ficou coberto'));
  await h.cenario({ whatsapp: 'normal' });
  h.ok(await h.espera(p, () => !document.querySelector('#wa-lista [data-tentar]'), null, 6000), 'WhatsApp: quando o Mac volta a lista segue normal');
  await h.cenario({ whatsapp: 'erro' }); await h.dormir(4500); await h.cenario({ whatsapp: 'normal' }); await h.dormir(4500); await h.cenario({ whatsapp: 'erro' });
  await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro') && document.querySelector('#aviso').classList.contains('visivel'), null, 6000);
  h.ok(true, 'WhatsApp: falha nova depois de uma leitura boa avisa de novo');
  await p.context().close(); await h.cenario({ whatsapp: 'normal' });

  // 3. texto sem espaço quebra linha e não passa da caixa
  await h.cenario({ xss: false, textoLongo: true });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]'); await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length > 0);
  await p.click('#wa-lista [data-wa="w1"]'); await h.dormir(900);
  let m = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .mensagens p')].map(x => x.scrollWidth - x.clientWidth));
  h.ok(m.length > 0 && m.every(d => d <= 0), `430x932: URL comprida na mensagem do WhatsApp quebra linha (sobra ${m})`);
  await h.foto(p, 'url-wa-430');
  await p.click('#f-whats [data-fechar]'); await h.dormir(500);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length > 0);
  m = await p.evaluate(() => [...document.querySelectorAll('#se-lista .cartao-sessao p')].map(x => x.scrollWidth - x.clientWidth));
  await p.click('#se-lista [data-sessao="s1"]'); await h.dormir(300);
  m = [...m, ...await p.evaluate(() => [...document.querySelectorAll('#se-lista .detalhe-sessao .pergunta')].map(x => x.scrollWidth - x.clientWidth))];
  h.ok(m.length > 1 && m.every(d => d <= 0), `430x932: caminho comprido na pergunta da sessão quebra linha, no cartão e na sessão aberta (sobra ${m})`);
  await h.foto(p, 'cam-se-430');
  await p.context().close(); await h.cenario({ textoLongo: false });

  // 4. o "há X min" anda com o relógio do Mac, com a folha aberta
  p = await h.pagina(); await pronta(h, p);
  await p.click('.sessoes'); await h.espera(p, () => document.querySelectorAll('#se-lista .cartao-sessao').length === 5);
  const quando = () => p.evaluate(() => document.querySelector('#se-lista .cartao-sessao small').textContent);
  h.ok(await quando() === 'app_web, há 5 min', `sessões: começa em "há 5 min" (${await quando()})`);
  await h.cenario({ relogioMs: 125000 });
  h.ok(await h.espera(p, () => document.querySelector('#se-lista .cartao-sessao small').textContent === 'app_web, há 7 min', null, 9000), `sessões: com o relógio do Mac 125 s adiante vira "há 7 min" (${await quando()})`);
  await p.context().close(); await h.cenario({ relogioMs: 0 });

  // 5. tecla de Calendário com ação vai pro Mac (POST /api/botao), em vez de abrir a lista no iPhone
  await h.reset(); await h.cenario({ comAcao: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="cal-dia"]'); await h.dormir(600);
  h.ok((await h.contadores()).botoes.join() === 'cal-dia', `tecla de Calendário com ação: o Mac recebeu o toque (${(await h.contadores()).botoes})`);
  h.ok(await p.evaluate(() => !document.querySelector('#f-calendario.aberta, #f-agenda.aberta, .folha.aberta')), 'e a lista da agenda não abriu no iPhone');
  await p.context().close(); await h.cenario({ comAcao: false });
}
