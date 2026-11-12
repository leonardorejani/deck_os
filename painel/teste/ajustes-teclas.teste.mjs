// Frente mac-ajustes-teclas (12/11/2026): "Google Meet (navegador)" na lista de Nova tecla, com microfone e câmera sem app
// instalado, e a tecla de comando com liga e desliga que acende como a de Manter acordado (o Mac guarda o estado).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  /* ---------- Google Meet (navegador) na lista de apps ---------- */
  await h.cenario({ apps: 'normal' });
  let p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => abrirEditor('nova'));
  h.ok(await h.espera(p, () => !!document.querySelector('#ed-lista-apps button[data-app-bundle="deck-meet-navegador"]')), 'a lista de Nova tecla oferece "Google Meet (navegador)"');
  const itens = await p.evaluate(() => [...document.querySelectorAll('#ed-lista-apps button')].slice(0, 3).map(b => b.textContent.trim()));
  h.ok(itens[0] === 'Controles do Mac' && itens[1] === 'Google Meet (navegador)', `as teclas do Deck vêm na frente da lista (${JSON.stringify(itens)})`);
  await p.click('#ed-lista-apps button[data-app-bundle="deck-meet-navegador"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ed-acoes [data-acao-id]').length === 3), 'escolher o Meet oferece "Só abrir" e as duas ações da reunião');
  const textos = await p.evaluate(() => [...document.querySelectorAll('#ed-acoes [data-acao-id]')].map(b => b.textContent.trim()));
  h.ok(/microfone/i.test(textos[1]) && /câmera/i.test(textos[2]), `as ações são microfone e câmera (${JSON.stringify(textos)})`);
  await p.click('#ed-acoes [data-acao-id="reuniao-microfone"]');
  const r = await p.evaluate(() => ({ valor: rasc.valor, icone: rasc.icone, acao: rasc.acao, nome: document.querySelector('#ed-nome').value }));
  h.ok(r.valor === 'Google Meet' && r.icone === 'svg:video' && r.acao?.id === 'reuniao-microfone', `a tecla guarda o Meet sem app e a ação do microfone (${JSON.stringify(r)})`);
  h.ok(r.nome === 'Google Meet Mutar ou desmutar o microfone da reunião' || r.nome.startsWith('Google Meet'), `o nome começa por "Google Meet", sem o "(navegador)" (${r.nome})`);
  h.ok(await p.evaluate(() => iconeDaTecla({ tipo: 'app', valor: 'Google Meet', icone: 'svg:video' }).includes('<svg')), 'o ícone da tecla do Meet é o desenho, não uma imagem de app');
  await p.context().close();

  /* ---------- tecla de comando com liga e desliga ---------- */
  await h.reset(); await h.cenario({ comFoco: true, acesas: [] });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').getAttribute('aria-pressed') === 'false'), 'a tecla liga e desliga é uma tecla de estado (aria-pressed), começa apagada');
  await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click());
  h.ok(await h.espera(p, () => document.querySelector('.tecla[data-id="foco"]').classList.contains('acesa')), 'tocar acende na hora');
  h.ok(await h.ate(async () => (await h.contadores()).botoes.includes('foco')), 'o Mac recebeu o toque');
  await h.dormir(1500);
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').classList.contains('acesa')), 'o estado que o Mac guardou mantém a tecla acesa');
  await p.evaluate(() => document.querySelector('.tecla[data-id="foco"]').click());
  h.ok(await h.espera(p, () => !document.querySelector('.tecla[data-id="foco"]').classList.contains('acesa')), 'tocar de novo apaga (desliga)');
  await p.context().close();
}
