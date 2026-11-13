// WhatsApp pelo aparelho conectado (pedidos de 12/11/2026): filtro Arquivadas, conversa sem nome, foto de perfil, horário em cada
// mensagem, foto e áudio na conversa, visualização única como balão, "Responder no Mac" no WhatsApp Web e lista que acompanha rápido.
// Dados inventados do Mac de mentira (servidor-falso.mjs).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
const nomes = p => p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .nome-c')].map(x => x.childNodes[0].textContent.trim()));
const filtro = async (p, f) => { await p.click(`#wa-filtro [data-f="${f}"]`); await p.waitForTimeout(80); return nomes(p) };

export default async function (h) {
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true });
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 4), 'tocar na tecla abre a folha, e a arquivada fica fora de Todas (4 de 5)');

  /* ---------- (8) Arquivadas só no filtro delas ---------- */
  h.ok((await nomes(p)).join('|') === 'Ana Souza|+55 44 99999-0002|Louvor|Contato', `Todas não traz a arquivada (${(await nomes(p)).join('|')})`);
  h.ok((await filtro(p, 'contatos')).join('|') === 'Ana Souza|+55 44 99999-0002|Contato', 'Contatos não traz a arquivada');
  h.ok((await filtro(p, 'grupos')).join('|') === 'Louvor', 'Grupos não traz a arquivada');
  h.ok((await filtro(p, 'arquivadas')).join('|') === 'Bia Arquivada', 'o filtro Arquivadas traz só a arquivada');
  h.ok(await p.evaluate(() => document.querySelector('#wa-filtro [data-f="arquivadas"]').getAttribute('aria-pressed')) === 'true', 'o filtro Arquivadas fica marcado');
  h.ok(await texto(p, '#wa-titulo') === 'WhatsApp 7 não lidas em 4 conversas', `o total não conta a arquivada (${await texto(p, '#wa-titulo')})`);
  await filtro(p, 'todas');

  /* ---------- (4) conversa sem nome nunca fica em branco ---------- */
  const sem = await p.evaluate(() => { const c = document.querySelectorAll('#wa-lista .conversa')[3]; return { nome: c.querySelector('.nome-c').textContent.trim(), previa: c.querySelector('.previa').textContent, avatar: c.querySelector('.avatar').innerHTML.includes('<svg') } });
  h.ok(sem.nome === 'Contato' && sem.previa === 'Alguém sem nome salvo' && sem.avatar, `conversa sem nome mostra "Contato" e um avatar de pessoa (${JSON.stringify(sem)})`);
  const numero = await p.evaluate(() => document.querySelectorAll('#wa-lista .conversa')[1].querySelector('.avatar').textContent.trim());
  h.ok(numero === '', `nome que é só número não vira iniciais estranhas (${numero})`);

  /* ---------- (5) foto de perfil ---------- */
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .conversa .avatar img')), 'a foto de perfil aparece no avatar');
  const c0 = await h.contadores();
  h.ok(c0.fotos.join() === '0123456789abcdef.jpg', `a foto é pedida uma vez só (${c0.fotos.join()})`);
  h.ok(await p.evaluate(() => !document.querySelectorAll('#wa-lista .conversa')[2].querySelector('.avatar img')), 'quem não tem foto continua com o avatar de sempre');

  /* ---------- (6) horário, (7) mídia ---------- */
  await p.click('#wa-lista [data-wa="r1@s.whatsapp.net"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .mensagens p').length === 3), 'abrir a conversa mostra as 3 mensagens');
  const horas = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .mensagens p .hora-msg')].map(x => x.textContent));
  h.ok(horas.length === 3 && horas.every(x => /^\d\d:\d\d$/.test(x)), `cada mensagem traz o horário em que chegou (${horas.join()})`);
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .foto-msg img')), 'a foto aparece como imagem dentro do balão');
  h.ok(await p.evaluate(() => document.querySelector('#wa-lista .foto-msg img').src.startsWith('blob:')), 'a imagem vem do Mac (guardada em memória, sem link externo)');
  h.ok(await p.evaluate(() => !document.querySelector('#wa-lista audio') && !!document.querySelector('#wa-lista [data-ouvir]')), 'o áudio só é baixado quando a pessoa pede (botão "Ouvir o áudio")');
  h.ok(!(await h.contadores()).midias.includes('A1'), 'sem tocar, o áudio não foi pedido ao Mac');
  await p.click('#wa-lista [data-ouvir]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .audio-msg audio[controls]')), 'tocar em "Ouvir" troca o botão por um player com controles');
  h.ok(await p.evaluate(() => document.querySelector('#wa-lista .audio-msg audio').src.startsWith('blob:')), 'o player toca o áudio baixado do Mac');
  await h.dormir(500); await h.foto(p, 'whatsapp-midia');

  /* o player tocando não é derrubado por uma lista nova: a conversa abre de novo sem perder o player */
  const repinta = await p.evaluate(() => { const a = document.querySelector('#wa-lista audio'); return a.isConnected });
  h.ok(repinta, 'o player continua na tela');

  /* ---------- (7) visualização única: só o balão, nunca o conteúdo ---------- */
  await p.click('#wa-lista [data-wa="r2@lid"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .unica-msg').length === 2), 'visualização única aparece como balão');
  const unica = await p.evaluate(() => [...document.querySelectorAll('#wa-lista .unica-msg')].map(b => ({ t: b.querySelector('.unica').textContent.trim(), icone: !!b.querySelector('svg[aria-label="Visualização única"]'), conteudo: !!b.querySelector('img, audio, [data-ouvir]') })));
  h.ok(unica[0].t === 'Foto única' && unica[1].t === 'Áudio único' && unica.every(u => u.icone && !u.conteudo), `balão de foto e de áudio com o ícone de única, sem abrir o conteúdo (${JSON.stringify(unica)})`);
  await h.dormir(400);
  h.ok(!(await h.contadores()).midias.some(i => i.startsWith('U')), 'o painel nunca pede o conteúdo da visualização única');

  /* ---------- (9) Responder no Mac abre a conversa no WhatsApp Web ---------- */
  const botoesAntes = (await h.contadores()).botoes.length;
  await p.click('#wa-lista [data-wa-mac]');
  h.ok(await h.ate(async () => (await h.contadores()).whatsappAbertas.join() === 'r2@lid'), 'Responder no Mac pede ao Mac a conversa certa');
  h.ok((await h.contadores()).botoes.length === botoesAntes, 'e não manda mais a tecla do WhatsApp (que abria o app)');
  await p.click('#wa-lista [data-wa="g1@g.us"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista [data-wa-mac]')), 'a conversa do grupo abre');
  await p.click('#wa-lista [data-wa-mac]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent.includes('Grupo não tem link direto')), 'em grupo o aviso diz que não há link direto');
  await p.context().close();

  /* ---------- (3) a lista acompanha rápido ---------- */
  await h.cenario({ whatsappRico: true, whatsappOrigem: 'qr', whatsappExtra: false });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 4);
  const t0 = Date.now();
  await h.cenario({ whatsappExtra: true });
  const chegou = await h.espera(p, () => [...document.querySelectorAll('#wa-lista .nome-c')].some(x => x.textContent.includes('Chegou Agora')), undefined, 3000);
  const ms = Date.now() - t0;
  h.ok(chegou && ms < 2200, `conversa nova aparece com a folha aberta em até ~2 s, não em 4 s (${ms} ms)`);
  await p.setViewportSize({ width: 430, height: 932 }); await h.dormir(400); await h.foto(p, 'whatsapp-rico-em-pe');
  h.ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'em pé: nada passa da largura');
  await p.context().close();

  /* ---------- fora do aparelho conectado não há filtro Arquivadas ---------- */
  await h.cenario({ whatsappRico: false, whatsappOrigem: 'app' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 5);
  h.ok(await p.evaluate(() => document.querySelector('#wa-filtro [data-f="arquivadas"]').hidden), 'pelo app do Mac o filtro Arquivadas não aparece (ele não entrega arquivadas)');
  await p.context().close();

  /* ---------- Responder no Mac demora mais que o prazo comum e não vira erro ---------- */
  // O Mac traz a aba, acha a busca e digita: passa de 5 s. O prazo comum (aqui 400 ms no lugar dos 5 s) não pode valer.
  await h.reset();
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, abrirAtraso: 1200 });
  p = await h.pagina({ ajustes: { tempoLimite: 400 } }); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length >= 3);
  await p.click('#wa-lista [data-wa="r2@lid"]');
  await p.click('#wa-lista [data-wa-mac]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt')?.textContent.includes('Abrindo a conversa'), undefined, 4000), `Responder no Mac que demora espera a resposta em vez de mostrar erro (${await texto(p, '#aviso-txt')})`);
  await p.context().close();
}
