// 17/11/2026: "substitui o componente [o círculo cinza com X] por outro que converse mais na UI, isso pro deck inteiro". O fechar das
// folhas é uma pílula escrita "Fechar" (mesma família dos segmentos), igual em todas as folhas, com 44 pt de toque, Esc fecha.
// Fotos: DECK_FASE=antes|depois (nome da foto), em celular deitado, em pé e janela larga.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const FOLHAS = [['#f-whats', 'abrirWhats()', 'whatsapp'], ['#f-cal', 'abrirCal()', 'agenda'], ['#f-controles', 'abrirControles()', 'controles'], ['#f-meet', 'abrirMeet()', 'meet'],
  ['#f-monitor', 'abrirMonitor()', 'monitor'], ['#f-uso', 'abrirUso()', 'uso'], ['#f-player', 'abrirPlayer()', 'player'], ['#f-sessoes', 'abrirSessoes()', 'sessoes']];
const fase = process.env.DECK_FASE || 'depois';

export default async function (h) {
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'pe'], [1440, 900, 'janela']]) {
    await h.reset(); await h.cenario({ atrasoAcao: 0, spotify: 'tocando' });
    const ctx = await h.novoContexto({ hasTouch: true }); const p = await h.pagina({ w, h: alt, ctx }); await p.setViewportSize({ width: w, height: alt }); await pronta(h, p); await h.dormir(300);
    for (const [id, abre, rot] of FOLHAS) {
      await p.evaluate(a => eval(a), abre);
      await h.espera(p, i => document.querySelector(i).classList.contains('aberta'), id); await h.dormir(900);
      const m = await p.evaluate(i => {
        const b = document.querySelector(i + ' .fechar'), r = b.getBoundingClientRect(), c = getComputedStyle(b), esc = document.querySelector('.moldura').getBoundingClientRect().width / 932 || 1;
        const sai = (x, y) => document.elementFromPoint(x, y)?.closest('.fechar') === b;
        const cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
        return { txt: b.textContent.trim(), alt: r.height, larg: r.width, raio: parseFloat(c.borderRadius), vp: [innerWidth, innerHeight], r: [r.left, r.top, r.right, r.bottom],
          toqueV: sai(cx, cy - 22 + 1) && sai(cx, cy + 22 - 1), toqueH: sai(cx - 22 + 1, cy) && sai(cx + 22 - 1, cy), corta: [...document.querySelectorAll(i + ' > header h2')].some(e => e.scrollWidth > e.clientWidth + 1), dentro: r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight };
      }, id);
      h.ok(m.txt === 'Fechar' && m.raio >= m.alt / 2 - 1 && m.larg > m.alt, `${nome} ${rot}: o fechar é uma pílula escrita "Fechar" (texto "${m.txt}", ${Math.round(m.larg)}x${Math.round(m.alt)}, raio ${m.raio})`);
      h.ok(m.dentro, `${nome} ${rot}: o fechar cabe na tela (${m.r.map(Math.round)} em ${m.vp})`);
      h.ok(!m.corta, `${nome} ${rot}: o título do cabeçalho não é cortado pelo fechar (${m.larg}px de fechar)`);
      if (w !== 1440) h.ok(m.toqueV && m.toqueH, `${nome} ${rot}: o toque do fechar tem 44 pt (vertical ${m.toqueV}, horizontal ${m.toqueH})`);
      await h.foto(p, `fechar-${fase}-${rot}-${nome}`);
      await p.keyboard.press('Escape'); await h.dormir(500);
      h.ok(await p.evaluate(i => !document.querySelector(i).classList.contains('aberta'), id), `${nome} ${rot}: Esc fecha a folha`);
      await p.evaluate(a => eval(a), abre); await h.espera(p, i => document.querySelector(i).classList.contains('aberta'), id); await h.dormir(500);
      await p.click(id + ' .fechar'); await h.dormir(500);
      h.ok(await p.evaluate(i => !document.querySelector(i).classList.contains('aberta'), id), `${nome} ${rot}: tocar no fechar fecha a folha`);
    }
    await p.context().close();
  }
}
