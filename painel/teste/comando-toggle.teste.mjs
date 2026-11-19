// Frente comando-toggle (13/11/2026): "quando escrevo o comando e mudo o ícone da tecla ele apaga o comando".
// O editor da tecla refazia o campo do comando a cada ícone escolhido, a partir de um rascunho que só recebia o texto no Salvar.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));

export default async function (h) {
  await h.cenario({ apps: 'normal' });
  let p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => abrirEditor('nova'));
  await h.espera(p, () => document.querySelector('#f-editor').classList.contains('aberta'));
  await p.click('#ed-tipo [data-tipo="comando"]');
  await p.fill('#ed-valor', 'shortcuts run "Modo jogo"');
  await p.evaluate(() => document.querySelector('#ed-icones [data-ic="svg:raio"]').click());
  h.ok(await p.inputValue('#ed-valor') === 'shortcuts run "Modo jogo"', 'trocar o ícone não apaga o comando digitado (tecla nova)');
  h.ok(await p.evaluate(() => document.querySelector('#ed-icones [data-ic="svg:raio"]').getAttribute('aria-pressed') === 'true'), 'o ícone escolhido fica marcado');
  await p.evaluate(() => document.querySelector('#ed-icones [data-ic="svg:terminal"]').click());
  h.ok(await p.inputValue('#ed-valor') === 'shortcuts run "Modo jogo"', 'e continua ali na segunda troca de ícone');
  await p.fill('#ed-nome', 'Modo jogo'); await p.click('#ed-salvar'); await h.dormir(500);
  const gravada = (await h.contadores()).configsGravadas.at(-1)?.perfis[0].teclas.at(-1);
  h.ok(gravada?.valor === 'shortcuts run "Modo jogo"' && gravada.icone === 'svg:terminal', `salva o comando com o ícone novo (${JSON.stringify(gravada)})`);
  await p.context().close();

  // tecla que já existe: editar o comando e trocar o ícone
  await h.reset(); await h.cenario({ apps: 'normal' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => abrirEditor('apagar'));
  await p.fill('#ed-valor', 'pmset sleepnow');
  await p.evaluate(() => document.querySelector('#ed-icones [data-ic="svg:raio"]').click());
  h.ok(await p.inputValue('#ed-valor') === 'pmset sleepnow', 'trocar o ícone não apaga o comando editado (tecla que já existe)');
  await p.context().close();
}
