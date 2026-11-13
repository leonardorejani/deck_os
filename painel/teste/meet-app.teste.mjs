// A central do Google Meet no iPhone (SPEC, seção 13, 13/11/2026): uma tecla só abre a tela, com entrar, microfone, câmera e
// sair. Microfone e câmera ficam verdes ligados e vermelhos desligados, e as teclas avulsas de microfone e câmera também.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const abrir = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="meet"]').click());
  const ok = await h.espera(p, () => document.querySelector('#f-meet').classList.contains('aberta') && !document.querySelector('#mt-corpo .esq-lista'));
  await h.dormir(450); // a folha ainda desliza para o lugar
  return ok;
};
const blocos = p => p.evaluate(() => Object.fromEntries([...document.querySelectorAll('#mt-corpo [data-mt]')].map(b => [b.dataset.mt, {
  classe: b.className.replace('mt-bloco', '').trim(), sub: b.querySelector('.mt-sub').textContent, desligado: b.disabled, pressed: b.getAttribute('aria-pressed'), cor: getComputedStyle(b).color }])));
const estado = p => p.evaluate(() => document.querySelector('.mt-estado')?.textContent.trim() || '');
// o rgb() que o navegador dá a uma cor do tema, para comparar com o que a tela pintou
const cor = (p, token) => p.evaluate(t => { const d = document.createElement('div'); d.style.color = `var(${t})`; document.querySelector('.tela').append(d); const c = getComputedStyle(d).color; d.remove(); return c }, token);

export default async function (h) {
  /* ---------- na chamada: microfone ligado e câmera desligada ---------- */
  await h.cenario({ comMeet: true });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'a tecla Google Meet abre a folha, sem esqueleto sobrando');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0, `a tecla abre a central no iPhone, sem mandar tecla ao Mac (botões: ${c.botoes.length})`);
  h.ok(await p.evaluate(() => document.querySelector('#mt-titulo').textContent) === 'Google Meet', 'título "Google Meet"');
  h.ok(await estado(p) === 'Reunião aberta', `diz que há reunião aberta (${await estado(p)})`);
  let b = await blocos(p);
  h.ok(Object.keys(b).join() === 'entrar,microfone,camera,sair', `os quatro botões, na ordem (${Object.keys(b)})`);
  h.ok(b.microfone.classe === 'ligado' && b.microfone.sub === 'Ligado' && b.microfone.pressed === 'true', `microfone ligado: verde e "Ligado" (${JSON.stringify(b.microfone)})`);
  h.ok(b.camera.classe === 'desligado' && b.camera.sub === 'Desligada' && b.camera.pressed === 'false', `câmera desligada: vermelha e "Desligada" (${JSON.stringify(b.camera)})`);
  h.ok(b.microfone.cor === await cor(p, '--sucesso') && b.camera.cor === await cor(p, '--perigo'), 'a cor de um é a do sucesso e a do outro é a do perigo');
  h.ok(!b.sair.desligado && !b.entrar.desligado && b.entrar.sub === 'Trazer a reunião para a frente', 'sair e entrar valem com a reunião aberta');
  await h.foto(p, 'meet-na-chamada');

  /* ---------- tocar no microfone: muda na hora e o Mac recebe ---------- */
  await h.cenario({ meetAtraso: 700 });
  await p.click('#mt-corpo [data-mt="microfone"]');
  b = await blocos(p);
  h.ok(b.microfone.classe.startsWith('desligado') && b.microfone.sub === 'Mutado', `o microfone vira vermelho e "Mutado" na hora, antes do Mac responder (${JSON.stringify(b.microfone)})`);
  h.ok(await h.ate(async () => (await h.contadores()).meetAcoes.includes('microfone')), 'o Mac recebe o pedido de microfone');
  await h.cenario({ meetAtraso: 0 });
  h.ok(await h.espera(p, () => document.querySelector('[data-mt="microfone"]').classList.contains('desligado') && !document.querySelector('[data-mt="microfone"]').disabled, undefined, 5000), 'depois de o Mac confirmar o microfone segue vermelho');
  await p.click('#mt-corpo [data-mt="camera"]');
  h.ok(await h.ate(async () => (await h.contadores()).meetAcoes.includes('camera')), 'o Mac recebe o pedido de câmera');
  h.ok(await h.espera(p, () => document.querySelector('[data-mt="camera"]').classList.contains('ligado'), undefined, 5000), 'a câmera fica verde e "Ligada"');

  /* ---------- entrar e sair ---------- */
  await p.click('#mt-corpo [data-mt="entrar"]');
  h.ok(await h.ate(async () => (await h.contadores()).meetAcoes.includes('entrar')), 'Entrar no Meet vai para o Mac');
  await h.espera(p, () => !document.querySelector('[data-mt="sair"]').disabled);
  await p.click('#mt-corpo [data-mt="sair"]');
  h.ok(await h.ate(async () => (await h.contadores()).meetAcoes.includes('sair')), 'Sair da chamada vai para o Mac');
  h.ok(await h.espera(p, () => document.querySelector('.mt-estado')?.textContent.trim() === 'Nenhuma reunião aberta', undefined, 5000), 'depois de sair, diz que não há reunião aberta');
  b = await blocos(p);
  h.ok(b.microfone.desligado && b.camera.desligado && b.sair.desligado && b.microfone.sub === 'Sem reunião', `sem reunião, microfone, câmera e sair ficam apagados e dizem isso (${JSON.stringify(b.microfone)})`);
  h.ok(!b.entrar.desligado && b.entrar.sub === 'Abrir meet.google.com', 'e Entrar no Meet abre o site');
  await h.foto(p, 'meet-sem-reuniao');
  await p.context().close();

  /* ---------- sem reunião desde o começo ---------- */
  await h.reset(); await h.cenario({ comMeet: true, meetEstado: { aberta: false, microfone: 'sem-reuniao', camera: 'sem-reuniao' } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  b = await blocos(p);
  h.ok(await estado(p) === 'Nenhuma reunião aberta' && b.microfone.classe === 'sem' && b.microfone.desligado, 'não finge estado: sem reunião o microfone fica apagado');
  await p.context().close();

  /* ---------- só na tela de entrada ---------- */
  await h.reset(); await h.cenario({ comMeet: true, meetEstado: { aberta: true, naChamada: false, microfone: 'desligado', camera: 'ligado' } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  b = await blocos(p);
  h.ok(await estado(p) === 'Você está na tela de entrada', `avisa que ainda não entrou (${await estado(p)})`);
  h.ok(b.sair.desligado && b.sair.sub === 'Você ainda não entrou' && !b.microfone.desligado, 'sair não vale antes de entrar, microfone e câmera valem');
  await p.context().close();

  /* ---------- reunião aberta mas o Deck não leu ---------- */
  await h.reset(); await h.cenario({ comMeet: true, meetEstado: { aberta: true, microfone: 'desconhecido', camera: 'desconhecido', aviso: 'Deixe a aba da reunião na frente do navegador.' } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  b = await blocos(p);
  h.ok(b.microfone.sub === 'Não consegui ler' && !b.microfone.desligado && b.microfone.classe === 'incerto', `mostra que não leu, sem verde nem vermelho (${JSON.stringify(b.microfone)})`);
  h.ok((await p.evaluate(() => document.querySelector('.mt-aviso').textContent)).includes('aba da reunião'), 'o aviso do Mac aparece');
  await p.context().close();

  /* ---------- o Mac recusa ---------- */
  await h.reset(); await h.cenario({ comMeet: true, meet: 'recusa' });
  p = await h.pagina(); await pronta(h, p);
  await abrir(h, p);
  await p.click('#mt-corpo [data-mt="sair"]');
  h.ok(await h.espera(p, () => /Não achei a chamada/.test(document.body.textContent), undefined, 4000), 'o erro do Mac aparece em português');
  await p.context().close();

  /* ---------- Mac antigo: sem a central, só abre o Meet nele ---------- */
  await h.reset(); await h.cenario({ comMeet: true, meet: 'antigo' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await h.espera(p, () => !!document.querySelector('[data-mt-mac]')), 'Mac sem a rota oferece abrir o Meet nele');
  await p.click('#mt-corpo [data-mt-mac]');
  h.ok(await h.ate(async () => (await h.contadores()).botoes.includes('meet')), 'a tecla antiga ainda abre o Meet no navegador do Mac');
  await p.context().close();

  /* ---------- as teclas avulsas: verde ligada, vermelha desligada ---------- */
  await h.reset(); await h.cenario({ comReuniao: true, reuniaoEstado: { mic: 'ligado', cam: 'desligado' } });
  p = await h.pagina(); await pronta(h, p);
  await p.waitForSelector('.tecla[data-id="cam"] .estado-tecla', { state: 'attached', timeout: 6000 }).catch(() => {});
  const led = id => p.evaluate(id => { const t = document.querySelector(`.tecla[data-id="${id}"]`); return { classe: t.className, led: getComputedStyle(t.querySelector('.led')).backgroundColor, fundo: getComputedStyle(t).backgroundColor } }, id);
  const mic = await led('mic'), cam = await led('cam');
  h.ok(mic.led === await cor(p, '--sucesso') && cam.led === await cor(p, '--perigo'), `tecla de microfone ligada com o led verde, a de câmera desligada com o led vermelho (${mic.led} e ${cam.led})`);
  h.ok(mic.fundo !== cam.fundo, 'os fundos são diferentes');
  await h.foto(p, 'meet-teclas');
  await p.context().close();
}
