// A tecla de microfone e de câmera da reunião mostra o estado que o Mac leu (SPEC, seção 13, item 39, 12/11/2026):
// ligado acende, desligado diz "Mutado" ou "Sem vídeo", desconhecido mostra "?" e sem reunião fica apagada.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="mic"]'));
const lerTecla = async (p, id) => { await p.waitForSelector(`.tecla[data-id="${id}"] .estado-tecla`, { state: 'attached', timeout: 6000 }).catch(() => {}); return p.evaluate(id => {
  const el = document.querySelector(`.tecla[data-id="${id}"]`), e = el.querySelector('.estado-tecla');
  return { acesa: el.classList.contains('acesa'), pressed: el.getAttribute('aria-pressed'), texto: e ? e.textContent : null, rotulo: e ? e.getAttribute('aria-label') : null,
    apagada: el.classList.contains('reuniao-sem-reuniao'), opacidade: getComputedStyle(el).opacity };
}, id); };

export default async function (h) {
  /* ---------- microfone aberto e câmera desligada ---------- */
  await h.cenario({ comReuniao: true, reuniaoEstado: { mic: 'ligado', cam: 'desligado' } });
  let p = await h.pagina(); await pronta(h, p);
  let mic = await lerTecla(p, 'mic'), cam = await lerTecla(p, 'cam');
  h.ok(mic.acesa && mic.pressed === 'true' && mic.texto === '', `microfone aberto: tecla acesa, sem texto (${JSON.stringify(mic)})`);
  h.ok(!cam.acesa && cam.pressed === 'false' && cam.texto === 'Sem vídeo' && cam.rotulo === 'Câmera: desligada', `câmera desligada: apagada e diz "Sem vídeo" (${JSON.stringify(cam)})`);
  await h.foto(p, 'reuniao-estado');

  /* ---------- tocar muda o estado: o Mac aperta o atalho e a leitura seguinte traz o novo ---------- */
  await p.evaluate(() => document.querySelector('.tecla[data-id="mic"]').click());
  h.ok(await h.espera(p, () => { const el = document.querySelector('.tecla[data-id="mic"]'); return el.querySelector('.estado-tecla')?.textContent === 'Mutado' && !el.classList.contains('acesa') }, undefined, 8000), 'depois do toque o microfone aparece "Mutado" e a tecla apaga');
  h.ok((await h.contadores()).botoes.includes('mic'), 'o toque foi para o Mac');
  mic = await lerTecla(p, 'mic');
  h.ok(mic.rotulo === 'Microfone: mutado', `leitor de tela ouve "Microfone: mutado" (${mic.rotulo})`);
  await p.context().close();

  /* ---------- sem reunião: apagada ---------- */
  await h.reset(); await h.cenario({ comReuniao: true, reuniaoEstado: { mic: 'sem-reuniao', cam: 'sem-reuniao' } });
  p = await h.pagina(); await pronta(h, p);
  mic = await lerTecla(p, 'mic');
  h.ok(mic.apagada && !mic.acesa && mic.texto === '' && mic.rotulo === 'Microfone: nenhuma reunião aberta' && Number(mic.opacidade) < 1, `sem reunião a tecla fica esmaecida e não finge estado (${JSON.stringify(mic)})`);
  await p.context().close();

  /* ---------- não deu para ler: "?" ---------- */
  await h.reset(); await h.cenario({ comReuniao: true, reuniaoEstado: { mic: 'desconhecido', cam: 'desconhecido' } });
  p = await h.pagina(); await pronta(h, p);
  mic = await lerTecla(p, 'mic');
  h.ok(!mic.acesa && mic.texto === '?' && mic.rotulo === 'Microfone: não consegui ler' && !mic.apagada, `reunião sem leitura mostra "?", não acesa nem esmaecida (${JSON.stringify(mic)})`);
  await p.context().close();

  /* ---------- valor estranho do Mac vira "?" ---------- */
  await h.reset(); await h.cenario({ comReuniao: true, reuniaoEstado: { mic: 'talvez', cam: 'ligado' } });
  p = await h.pagina(); await pronta(h, p);
  mic = await lerTecla(p, 'mic'); cam = await lerTecla(p, 'cam');
  h.ok(mic.texto === '?' && !mic.acesa, `estado que o painel não conhece não vira acesa (${JSON.stringify(mic)})`);
  h.ok(cam.acesa && cam.texto === '', 'a outra tecla segue com o estado dela');
  await p.context().close();

  /* ---------- Mac antigo: sem `reuniao`, a tecla é a de sempre ---------- */
  await h.reset(); await h.cenario({ comReuniao: true, reuniaoEstado: null });
  p = await h.pagina(); await pronta(h, p);
  mic = await lerTecla(p, 'mic');
  h.ok(!mic.acesa && mic.texto === null && !mic.apagada, `Mac que não manda o estado: tecla comum, sem selo (${JSON.stringify(mic)})`);
  await p.context().close();
}
