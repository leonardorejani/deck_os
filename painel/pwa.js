/* O painel como PWA: service worker, tela sempre acesa e deslocamento contra queima de tela (SPEC, seções 8 e 11).
   Nada aqui muda o que a página mostra. No app nativo (window.DeckCanal) a casca já cuida da tela acesa
   e do cache, então só o deslocamento roda. */

/* ---------- service worker: o painel abre na hora, mesmo com o Mac desligado ---------- */
// Só em contexto seguro (HTTPS com o certificado confiado, ou localhost). Sem ele o painel funciona igual, só não abre offline.
if (!window.DeckCanal && 'serviceWorker' in navigator && window.isSecureContext) {
  const registrar = () => navigator.serviceWorker.register('/sw.js').catch(() => {});
  if (document.readyState === 'complete') registrar(); else addEventListener('load', registrar, { once: true });
}

/* ---------- tela sempre acesa (Wake Lock) ---------- */
// O sistema solta a trava quando a página sai da tela, então ela é pedida de novo toda vez que a página volta.
if (!window.DeckCanal) {
  let trava = null, pedindo = false, avisou = false;
  const semTelaAcesa = () => {
    if (avisou) return;
    avisou = true;
    avisar('A tela pode apagar sozinha. Desligue o bloqueio automático do iPhone.', { erro: true });
  };
  async function travarTela() {
    if (document.hidden || trava || pedindo) return;
    if (!('wakeLock' in navigator)) return semTelaAcesa();
    pedindo = true;
    try {
      const nova = await navigator.wakeLock.request('screen');
      trava = nova;
      nova.addEventListener('release', () => { if (trava === nova) trava = null });
    } catch { trava = null; semTelaAcesa() } finally { pedindo = false }
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden) travarTela() });
  // alguns navegadores só aceitam o pedido depois de um toque: enquanto não há trava, o toque tenta de novo (sem repetir o aviso)
  addEventListener('pointerdown', () => { if (!trava) travarTela() }, { passive: true });
  travarTela();
}

/* ---------- queima de tela: tudo desloca 1 a 2 px a cada 3 min, como o StandBy ---------- */
{
  const PASSOS = [[0, 0], [2, 1], [-1, 2], [-2, -1], [1, -2]]; // px, sempre voltando perto do centro
  let i = 0;
  setInterval(() => {
    i = (i + 1) % PASSOS.length;
    const m = $('#moldura');
    m.style.setProperty('--dx', PASSOS[i][0] + 'px');
    m.style.setProperty('--dy', PASSOS[i][1] + 'px');
  }, AJUSTES.deslocamento);
}
