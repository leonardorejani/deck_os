// Defeitos achados na verificação do PR de UX (11/11/2026): cada um tem um teste que falhava antes do conserto.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const centro = async (p, sel) => { const b = await p.locator(sel).first().boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 } };
const tocar = async (p, sel) => { const c = await centro(p, sel); await p.mouse.click(c.x, c.y) };
async function entrar(h, p, id = 'calendario') {
  const c = await centro(p, `.tecla[data-id="${id}"]`);
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
}
// amostra uma condição da página a cada 100 ms durante `ms`
const amostrar = (p, fn, ms) => p.evaluate(async ([f, ms]) => { const g = new Function('return (' + f + ')()'); const r = []; for (let t = 0; t < ms; t += 100) { r.push(g() ? 1 : 0); await new Promise(x => setTimeout(x, 100)) } return r.join('') }, [fn.toString(), ms]);

export default async function (h) {
  /* 1. player em tela cheia, em pé: artista longo não estoura a largura nem tira o ícone da tela */
  await h.cenario({ faixa: 'Uma faixa com um título extremamente longo que não cabe em lugar nenhum da tela', artista: 'Artista com nome muito grande feat. Outro Artista Também Grande', album: 'Um álbum com nome gigantesco (Deluxe Edition Remastered 2024)' });
  let p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p);
  await p.click('.player .capa'); await h.dormir(900);
  const g = await p.evaluate(() => { const r = s => { const b = document.querySelector(s).getBoundingClientRect(); return [Math.round(b.left), Math.round(b.right)] }; const t = document.querySelector('#f-player .texto-artista'); return { artista: r('#f-player .artista'), ic: r('#f-player .ic-mini'), cortado: t ? t.scrollWidth > t.clientWidth && getComputedStyle(t).textOverflow === 'ellipsis' : false } });
  h.ok(g.artista[0] >= 0 && g.artista[1] <= 430 && g.ic[0] >= 0 && g.ic[1] <= 430, `em pé: artista longo e ícone do Spotify ficam dentro da tela (${JSON.stringify(g)})`);
  h.ok(g.cortado, 'em pé: o artista longo termina em reticências');
  await h.foto(p, 'player-cheio-artista-longo');
  await p.context().close();

  /* 2. play/pausa e repetir ligados e desligados em sequência com o Mac lento: a tela nunca mostra o estado do meio */
  await h.reset(); await h.cenario({ atrasoAcao: 1500 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player [data-midia="tocar"]'); await h.dormir(150); await p.click('.player [data-midia="tocar"]');
  const am = await amostrar(p, () => !!document.querySelector('.player.pausado') && !!document.querySelector('.player .tocar.play'), 4500);
  h.ok(!am.slice(2).includes('1'), `play, pausa, play seguidos: a tela fica "tocando" depois do 2º toque (amostra, 1 = pausado: ${am})`);
  h.ok((await h.contadores()).spotify.join() === 'pausar,tocar', `e o Mac recebeu pausar e tocar, na ordem (${(await h.contadores()).spotify})`);
  await p.click('.player [data-midia="repetir"]'); await h.dormir(150); await p.click('.player [data-midia="repetir"]');
  const am2 = await amostrar(p, () => document.querySelector('.player [data-midia="repetir"]').getAttribute('aria-pressed') === 'true', 4500);
  h.ok(!am2.slice(2).includes('1'), `repetir ligado e desligado em seguida: a tela fica desligada (amostra, 1 = ligado: ${am2})`);
  await p.context().close();

  /* 3. modo organizar: Salvar e Excluir tecla são otimistas, com o Mac levando 2,5 s para gravar */
  await h.reset(); await h.cenario({ atrasoGravar: 2500 });
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p); await tocar(p, '.tecla[data-id="apagar"]'); await h.dormir(500);
  await p.fill('#ed-nome', 'Nome novo');
  let t0 = Date.now(); await p.click('#ed-salvar');
  let ok = await h.espera(p, () => !document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('.tecla[data-id="apagar"] .nome').textContent === 'Nome novo', null, 4000), ms = Date.now() - t0;
  h.ok(ok && ms < 700, `Salvar tecla: o editor fecha e o nome novo aparece no toque (${ms} ms, com o Mac levando 2500 ms)`);
  await h.dormir(3500); // o Mac aceita, e a tecla segue com o nome novo
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="apagar"] .nome').textContent) === 'Nome novo' && (await h.contadores()).configsGravadas.length === 1, 'depois que o Mac aceita, a tecla segue com o nome novo e ele recebeu uma gravação');
  await tocar(p, '.tecla[data-id="whatsapp"]'); await h.dormir(500);
  t0 = Date.now(); await p.click('#ed-excluir');
  ok = await h.espera(p, () => !document.querySelector('#f-editor').classList.contains('aberta') && !document.querySelector('.tecla[data-id="whatsapp"]'), null, 4000); ms = Date.now() - t0;
  h.ok(ok && ms < 700, `Excluir tecla: o editor fecha e a tecla some no toque (${ms} ms)`);
  await h.dormir(3500);
  h.ok(!(await p.evaluate(() => !!document.querySelector('.tecla[data-id="whatsapp"]'))) && (await h.contadores()).configsGravadas.length === 2, 'e a tecla não volta quando o Mac aceita');
  await p.context().close();

  /* 4. barra arrastada na tela cheia: o player pequeno atrás já mostra a posição nova */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await p.click('.player .capa'); await h.dormir(700);
  const tr = await p.locator('#f-player .progresso .trilho').boundingBox();
  await p.mouse.move(tr.x + tr.width * .1, tr.y + tr.height / 2); await p.mouse.down();
  await p.mouse.move(tr.x + tr.width * .5, tr.y + tr.height / 2, { steps: 5 }); await p.mouse.up(); await h.dormir(200);
  const pos = await p.evaluate(() => ({ cheio: document.querySelector('#f-player .decorrido').textContent, pequeno: document.querySelector('.player .decorrido').textContent, w: parseFloat(document.querySelector('.player .trilho i').style.width) }));
  h.ok(pos.cheio === pos.pequeno && Math.abs(pos.w - 50) < 3, `arrastar a barra da tela cheia: o player pequeno mostra a mesma posição (${JSON.stringify(pos)})`);
  await p.context().close();
}
