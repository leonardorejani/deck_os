// Defeitos achados na verificação do modo organizar: cada um tem um teste que falhava antes do conserto.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const ordem = p => p.evaluate(() => [...document.querySelectorAll('.pagina .tecla:not(.menu)')].map(t => t.dataset.id).join());
const organizando = p => p.evaluate(() => document.querySelector('#tela').classList.contains('organizando'));
const aberta = p => p.evaluate(() => document.querySelector('#f-editor').classList.contains('aberta'));
const centro = async (p, sel) => { const b = await p.locator(sel).first().boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 } };
const tocar = async (p, sel) => { const c = await centro(p, sel); await p.mouse.click(c.x, c.y) };
async function entrar(h, p, id = 'apagar') {
  const c = await centro(p, `.tecla[data-id="${id}"]`);
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
}
async function arrastar(p, de, para) {
  const a = await centro(p, `.tecla[data-id="${de}"]`), b = await centro(p, `.tecla[data-id="${para}"]`);
  await p.mouse.move(a.x, a.y); await p.mouse.down();
  for (let i = 1; i <= 12; i++) { await p.mouse.move(a.x + (b.x - a.x) * i / 12, a.y + (b.y - a.y) * i / 12); await p.waitForTimeout(20) }
  await p.mouse.up();
}

export default async function (h) {
  /* 1. uma leitura de config que já estava a caminho não desfaz a ordem que o Mac acabou de aceitar */
  await h.reset();
  let c = await h.novoContexto(), p = await c.newPage();
  p.on('pageerror', e => console.log('ERRO na página: ' + e.message));
  await p.addInitScript(() => { window.DECK_AJUSTES = { intervalo: 300 } });
  let nGet = 0, preso = false;
  await p.route('**/api/config', async rota => {
    if (rota.request().method() === 'GET' && ++nGet === 2) { preso = true; const r = await rota.fetch(); await h.dormir(2500); return rota.fulfill({ response: r }) }
    return rota.continue();
  });
  await p.goto(`${h.base}/?codigo=${h.CODIGO}`); await pronta(h, p);
  for (let t = 0; !preso && t < 6000; t += 50) await h.dormir(50);
  h.ok(preso, 'a leitura de config do laço ficou presa no meio do caminho');
  await entrar(h, p); await arrastar(p, 'apagar', 'acordado');
  let vistas = new Set();
  for (let t = 0; t < 3500; t += 50) { vistas.add(await ordem(p)); await h.dormir(50) }
  h.ok([...vistas].join() === 'apagar,acordado,whatsapp,calendario', `a ordem nova nunca volta à antiga com a leitura atrasada chegando (${[...vistas].join(' | ')})`);
  await c.close();

  /* 2. Salvar, abrir outra tecla e digitar com a primeira gravação ainda a caminho: o fim da primeira gravação não fecha o segundo editor */
  await h.reset(); await h.cenario({ atrasoGravar: 1500 });
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await tocar(p, '.tecla[data-id="apagar"]'); await h.dormir(400);
  await p.fill('#ed-nome', 'Primeiro'); await p.click('#ed-salvar'); await h.dormir(650); // o editor já fechou (otimista), o Mac ainda grava
  await tocar(p, '.tecla[data-id="whatsapp"]'); await h.dormir(400);
  await p.fill('#ed-nome', 'Segundo digitado');
  await h.dormir(1700); // a primeira gravação termina agora
  h.ok(await aberta(p) && await p.inputValue('#ed-nome') === 'Segundo digitado', 'o segundo editor continua aberto com o que a pessoa digitou');
  await p.click('#ed-salvar');
  h.ok(await h.espera(p, () => !document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('.tecla[data-id="whatsapp"] .nome').textContent === 'Segundo digitado', null, 5000), 'Salvar do segundo editor grava e fecha');
  await h.ate(async () => (await h.contadores()).configsGravadas.length === 2, 5000); // o Mac leva 1,5 s para aceitar a segunda
  const g = await h.contadores();
  h.ok(g.configsGravadas.length === 2 && g.configsGravadas[1].perfis[0].teclas.find(t => t.id === 'whatsapp').nome === 'Segundo digitado' && g.configsGravadas[1].perfis[0].teclas.find(t => t.id === 'apagar').nome === 'Primeiro', 'as duas gravações chegaram ao Mac, na ordem, sem uma pisar na outra');
  await p.context().close();

  /* 3. Desfazer não tira a pessoa do modo organizar */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await tocar(p, '.tecla[data-id="whatsapp"]'); await p.click('#ed-excluir');
  await h.espera(p, () => !document.querySelector('.tecla[data-id="whatsapp"]'));
  await p.click('#aviso-acao');
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="whatsapp"]')), 'Desfazer devolve a tecla');
  h.ok(await organizando(p), 'e a pessoa continua no modo organizar');
  await p.context().close();

  /* 4. o editor fecha quando o Mac aceita a gravação, sem esperar uma releitura lenta do estado */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario'); await tocar(p, '.tecla[data-id="apagar"]'); await h.dormir(400);
  await h.cenario({ atraso: 2500 }); await h.dormir(1100); // o próximo pedido de estado já nasce lento
  await p.fill('#ed-nome', 'Novo nome');
  const t0 = Date.now(); await p.click('#ed-salvar');
  const fechou = await h.espera(p, () => !document.querySelector('#f-editor').classList.contains('aberta'), null, 6000), ms = Date.now() - t0;
  h.ok(fechou && ms < 1200, `com o estado lento, o editor fecha logo que o Mac aceita (${ms} ms)`);
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="apagar"] .nome').textContent) === 'Novo nome', 'e a tecla já mostra o nome novo');
  await p.context().close();
}
