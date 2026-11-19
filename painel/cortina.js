/* Cortina de controles rápidos (SPEC 13, item 8): da tela principal, deslizar para baixo a partir do topo abre uma cortina com volume, mudo,
   brilho e a mídia (anterior, tocar ou pausar, próxima). Deslizar para cima ou tocar fora fecha. A cortina acompanha o dedo e pode ser
   agarrada no meio da animação. Os cartões são os mesmos dos Controles do Mac (controles.js) e a mídia é a do player (data-midia, deck.js).
   Ideia de WinDock (MIT, docs/QUICK_CONTROLS.md): começa abaixo da borda do sistema, ignora o que rola ou arrasta e o clique que o gesto
   gera não aperta nada. Não briga com o fechar puxando para baixo das folhas (deck.js): este só vale sem folha aberta. */

const cx = { el: $('#cortina'), painel: $('#cx-painel'), fundo: $('#cx-fundo'), corpo: $('#cx-corpo'), aberta: false, vis: false, gesto: null, altura: 0, ger: 0, cliqueAte: 0 };
const CX_BORDA = 24;     // px da tela: acima disso é o sistema (Centro de Controle, notificações). O gesto só começa abaixo
const CX_FAIXA = 110;    // até onde, abaixo da borda, o dedo pode encostar para abrir
const CX_LONGE = .3, CX_RAPIDO = .5; // fração da altura e px por ms

const cortinaVisivel = () => cx.vis;
const cxK = () => { const t = $('#tela'); return t.getBoundingClientRect().width / t.offsetWidth || 1 };
const cxSeguroCima = () => parseFloat(getComputedStyle($('#tela')).getPropertyValue('--seguro-cima')) || 0;
const cxY = () => parseFloat(getComputedStyle(cx.painel).translate.split(' ')[1]) || 0; // onde o painel está agora (px da tela), no meio da animação também
const cxFundoOp = () => parseFloat(getComputedStyle(cx.fundo).opacity) || 0;

function cxPosicionar(y, animar) {
  const alt = cx.altura || 1, y1 = Math.min(0, Math.max(-alt, y));
  const t = animar ? `translate var(--mov-${animar === 'abre' ? 'padrao' : 'sai-padrao'}) var(--curva-${animar === 'abre' ? 'entra' : 'sai'})` : 'none';
  cx.painel.style.transition = t; cx.fundo.style.transition = animar ? t.replace('translate', 'opacity') : 'none';
  cx.painel.style.translate = `0 ${y1}px`; cx.fundo.style.opacity = String(1 + y1 / alt);
}
function cxPreparar() { // mede o painel com ele no lugar de fechado, já com os cartões (ou o esqueleto), senão a altura muda depois do gesto
  const novo = !cx.vis; cx.vis = true; cx.el.classList.add('visivel');
  if (novo) { pintarControles(); pintarCortinaMidia() }
  cx.altura = cx.painel.offsetHeight || 1;
}
function abrirCortina({ de } = {}) {
  if (cx.aberta && cx.vis && de == null) return;
  cx.ger++; cxPreparar();
  if (de == null) { cxPosicionar(-cx.altura, false); cx.el.offsetHeight } // parte de fechada, a menos que já esteja no meio
  cx.aberta = true; cx.el.setAttribute('aria-modal', 'true'); cx.el.removeAttribute('inert');
  cxPosicionar(0, 'abre');
  lerControles(); pintarCortinaMidia();
}
function fecharCortina() {
  if (!cx.vis) return; const g = ++cx.ger; cx.altura = cx.painel.offsetHeight || cx.altura; // o conteúdo pode ter mudado de altura desde que abriu
  cx.aberta = false; cxPosicionar(-cx.altura, 'fecha');
  const ms = msCss('--mov-sai-padrao') + 60;
  setTimeout(() => { if (g === cx.ger && !cx.aberta) { cx.vis = false; cx.el.classList.remove('visivel'); cx.el.setAttribute('inert', ''); cx.corpo.replaceChildren(); cx.corpo.dataset.forma = '' } }, ms);
}

/* a mídia só aparece com o Spotify na tela. Reaproveita o .midia e o pintarMidia do player */
function pintarCortinaMidia() {
  const raiz = $('#cx-midia'), s = typeof V !== 'undefined' ? V?.spotify : null;
  raiz.hidden = !s; cx.painel.classList.toggle('sem-midia', !s);
  if (!s) return;
  const t = !!s.tocando;
  if (!raiz.firstElementChild) raiz.innerHTML = `<div class="midia"><button aria-label="Anterior" data-midia="anterior">${SVG.anterior}</button><button class="tocar ${t ? '' : 'play'}" aria-label="${t ? 'Pausar' : 'Tocar'}" data-midia="tocar">${t ? SVG.pausar : SVG.tocar}</button><button aria-label="Próxima" data-midia="proxima">${SVG.proxima}</button></div><div class="cx-faixa"></div>`;
  pintarMidia($('.midia', raiz), s);
  const f = $('.cx-faixa', raiz), txt = s.faixa || ''; if (f.textContent !== txt) f.textContent = txt;
}

/* ---------- gesto ---------- */
// área que rola ou arrasta (ou é campo) não entrega o gesto à cortina
function cxRolante(el, topo) {
  for (; el && el !== topo; el = el.parentElement) {
    const c = getComputedStyle(el);
    if (/(auto|scroll)/.test(c.overflowX + c.overflowY) && (el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1)) return true;
  }
  return false;
}
function cxPodeAbrir(e) {
  const t = $('#tela'), alvo = e.target;
  if (cx.vis || typeof V === 'undefined' || !V || V.carregando || offline || semAcesso || organizando || telaAberta() || e.touches.length !== 1) return false;
  if (!$('#aprovacao').hidden || !$('#t-parear').hidden || !$('#lista-perfis').hidden || t.classList.contains('com-folha')) return false;
  if (alvo.closest('input, textarea, select, .progresso, .volume, .trilho, .seletor, .barra-organizar')) return false;
  return !cxRolante(alvo, t);
}
$('#tela').addEventListener('touchstart', e => {
  cx.gesto = null;
  if (e.touches.length !== 1) return;
  const t0 = e.touches[0], tela = $('#tela'), k = cxK(), yLocal = (t0.clientY - tela.getBoundingClientRect().top) / k;
  if (cx.vis) { // cortina na tela (aberta ou animando): agarra o que não é cartão nem botão
    if (!cx.el.contains(e.target) || e.target.closest('.ctl-cartao, button')) return;
    const y = cxY(), op = cxFundoOp(); cx.altura = cx.painel.offsetHeight || cx.altura;
    cx.painel.style.transition = 'none'; cx.fundo.style.transition = 'none'; cx.painel.style.translate = `0 ${y}px`; cx.fundo.style.opacity = String(op); // congela onde está
    cx.gesto = { x: t0.clientX, y: t0.clientY, t: e.timeStamp, y0: y, dy: 0, seguindo: false, p0: 1 + y / cx.altura, aberta: cx.aberta };
    return;
  }
  const min = Math.max(CX_BORDA, cxSeguroCima());
  if (yLocal < min || yLocal > min + CX_FAIXA || !cxPodeAbrir(e)) return;
  cx.gesto = { x: t0.clientX, y: t0.clientY, t: e.timeStamp, y0: null, dy: 0, seguindo: false, p0: 0, aberta: false };
}, { passive: true });
$('#tela').addEventListener('touchmove', e => {
  const g = cx.gesto; if (!g) return;
  const t0 = e.touches[0], dx = t0.clientX - g.x, dy = t0.clientY - g.y;
  if (!g.seguindo) {
    // abrindo: só para baixo e na vertical. Com a cortina na tela vale os dois sentidos
    if (Math.abs(dx) > 10 && Math.abs(dx) >= Math.abs(dy) || (g.y0 == null && dy < -10)) { cxSoltarSemMover(g); return }
    if (Math.abs(dy) > Math.abs(dx) && e.cancelable) e.preventDefault(); // no iPhone a rolagem nativa toma o gesto se não for cancelado já
    if (Math.abs(dy) < 10 || Math.abs(dy) < Math.abs(dx) * 1.5) return;
    g.seguindo = true; if (g.y0 == null) lerControles(); // os valores chegam enquanto o dedo desce
    if (g.y0 == null) { cxPreparar(); g.y0 = -cx.altura; cx.painel.style.transition = 'none'; cx.fundo.style.transition = 'none'; cxPosicionar(g.y0, false); cx.el.offsetHeight }
  }
  g.dy = dy; cxPosicionar(g.y0 + dy / cxK(), false);
  e.preventDefault();
}, { passive: false });
function cxSoltarSemMover(g) { // não era com a cortina: se ela estava no meio da animação, segue para onde ia
  cx.gesto = null;
  if (g.y0 != null && cx.vis) { g.aberta ? abrirCortina({ de: g.y0 }) : fecharCortina() }
}
function cxSoltar(e, cancelado) {
  const g = cx.gesto; cx.gesto = null; if (!g) return;
  if (!g.seguindo) return cxSoltarSemMover(g);
  cx.cliqueAte = e.timeStamp + 400;
  const alt = cx.altura, p = 1 + cxY() / alt, v = g.dy / Math.max(1, e.timeStamp - g.t) / cxK(); // px por ms, positivo = descendo
  let abrir;
  if (cancelado) abrir = g.aberta;
  else if (Math.abs(v) > CX_RAPIDO && Math.abs(g.dy) > 30) abrir = v > 0;
  else abrir = g.p0 < .5 ? p > CX_LONGE : p > 1 - CX_LONGE;
  abrir ? abrirCortina({ de: cxY() }) : fecharCortina();
}
$('#tela').addEventListener('touchend', e => cxSoltar(e, false));
$('#tela').addEventListener('touchcancel', e => cxSoltar(e, true));
// o toque que terminou o gesto não aperta o que estava embaixo do dedo
$('#tela').addEventListener('click', e => { if (performance.now() < cx.cliqueAte) { e.stopPropagation(); e.preventDefault() } }, true);
// tocar fora do painel (no fundo) fecha
cx.fundo.addEventListener('click', () => fecharCortina());
cx.el.addEventListener('click', e => { if (e.target === cx.el) fecharCortina() });
addEventListener('keydown', e => { if (e.key === 'Escape') fecharCortina() });
