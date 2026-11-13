/* Controles do Mac: volume (com mudo), brilho da tela e brilho do teclado, numa folha cheia, um cartão por controle, e o cartão inteiro é o slider vertical (o branco sobe de baixo, o texto troca de cor na linha). O Mac diz o que este aparelho
   oferece em GET /api/controles: o que não vem (sem tela interna, sem luz no teclado, Mac antigo sem a rota) não aparece, em
   vez de fingir. Os cartões respondem na hora (o valor que o dedo pôs vale até o Mac confirmar) e mandam o último valor,
   nunca dois pedidos ao mesmo tempo. Usa as peças de deck.js (V, canal, avisar, abrirFolha, tratarErro) e paineis.js (msgErro). */

const CONTROLES = [
  { id: 'volume', nome: 'Volume', icone: 'volume' },
  { id: 'brilho', nome: 'Brilho da tela', icone: 'sol' },
  { id: 'teclado', nome: 'Luz do teclado', icone: 'luzTeclado' },
];
const ct = { dados: null, erro: '', seq: 0, forma: '', mexendo: false };
const otmCtl = {}; // o que o dedo pôs, por controle: { v, ate }. Vale até o Mac confirmar ou a janela acabar
const envCtl = {};
let arrCtl = null;

const valorCtl = (id) => {
  const o = otmCtl[id], real = ct.dados?.[id];
  if (!o) return real;
  if (performance.now() > o.ate || real === o.v) { delete otmCtl[id]; return real }
  return o.v;
};
const mudoCtl = () => {
  const o = otmCtl.mudo, real = ct.dados?.mudo;
  if (!o) return real;
  if (performance.now() > o.ate || real === o.v) { delete otmCtl.mudo; return real }
  return o.v;
};
const oferecidos = () => CONTROLES.filter(c => Number.isInteger(ct.dados?.[c.id]));

function abrirControles() {
  ct.dados = null; ct.erro = ''; ct.forma = ''; ct.mexendo = false;
  pintarControles(); abrirFolha('#f-controles'); lerControles();
}
async function lerControles() {
  const n = ++ct.seq;
  try {
    const d = await canal.controles(); if (n !== ct.seq) return;
    ct.dados = d && typeof d === 'object' ? d : {}; ct.erro = '';
  } catch (e) {
    if (n !== ct.seq) return;
    if (e.status === 401) return tratarErro(e);
    ct.erro = e.status === 404 ? 'Este Mac ainda não tem os controles. Atualize o Deck no Mac.' : msgErro(e);
    if (ct.dados) { avisar(ct.erro, { erro: true }); ct.erro = ''; return } // com o que já estava na tela, só avisa
  }
  pintarControles();
}

const pctCtl = n => `${Math.round(n)}<small>%</small>`;
const SVG_MUDO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5 6 9H2v6h4l5 4zM16 9.5a4 4 0 0 1 .8 4.5M19.5 6.5a8.5 8.5 0 0 1 1 9M3 3l18 18"/></svg>';
/* Um cartão por controle e o cartão inteiro é o controle. Duas camadas com o mesmo conteúdo (a de cima é a branca, recortada de baixo até o nível),
   assim ícone, nome e número trocam de cor exatamente na linha do branco. O Mudo é um botão que alterna: só existe quando o Mac diz o estado. */
const camadaCtl = (c, cheio) => `<span class="ctl-cam${cheio ? ' ctl-cheio' : ''}" aria-hidden="true"><span class="ctl-topo"><span class="ctl-ic">${SVG[c.icone]}</span><span class="ctl-rot">${c.nome}</span></span><b class="ctl-num"></b></span>`;
const cartaoCtl = c => `<div class="ctl-cartao" data-ctl="${c.id}" role="slider" tabindex="0" aria-label="${c.nome}" aria-orientation="vertical" aria-valuemin="0" aria-valuemax="100">${camadaCtl(c, false)}${camadaCtl(c, true)}</div>`;
const cartaoMudo = () => `<button class="ctl-cartao ctl-mudo" data-mudo aria-pressed="false" aria-label="Mudo"><span class="ctl-mic" aria-hidden="true">${SVG.volume}</span><b class="ctl-estado">Som ligado</b></button>`;
const esqueletoCtl = () => '<div class="ctl-grade" data-n="4" aria-hidden="true">' + '<div class="ctl-cartao esq"><i class="barra" style="width:40%"></i><i class="barra" style="width:70%"></i></div>'.repeat(4) + '</div>';

function pintarControles() {
  const corpo = $('#ct-corpo');
  if (!ct.dados) {
    corpo.setAttribute('aria-busy', String(!ct.erro));
    corpo.innerHTML = ct.erro ? `<div class="vazio-bloco" style="min-height:160px"><strong>Não deu para ler</strong><span>${esc(ct.erro)}</span><button class="btn secundario pequeno" data-ct-tentar style="justify-self:start">Tentar de novo</button></div>` : esqueletoCtl();
    ct.forma = ''; return;
  }
  corpo.setAttribute('aria-busy', 'false');
  const lista = oferecidos(), comMudo = typeof ct.dados.mudo === 'boolean', forma = JSON.stringify([lista.map(c => c.id), comMudo]);
  if (forma !== ct.forma) { // o que o Mac oferece mudou: refaz os cartões (senão só mexe nos valores, sem soltar o dedo do cartão)
    ct.forma = forma;
    // ordem: Volume, Mudo, Brilho, Luz do teclado
    const cartoes = lista.map(cartaoCtl); if (comMudo) cartoes.splice(lista[0]?.id === 'volume' ? 1 : 0, 0, cartaoMudo());
    corpo.innerHTML = cartoes.length ? `<div class="ctl-grade" data-n="${cartoes.length}">${cartoes.join('')}</div>` : '<div class="vazio-bloco" style="min-height:160px"><strong>Nada para controlar</strong><span>Este Mac não oferece volume, brilho nem luz de teclado, ou as barras estão desligadas na tecla Controles do Mac, nos Ajustes do Deck.</span></div>';
  }
  for (const c of lista) {
    if (arrCtl?.id === c.id) continue; // o dedo manda no cartão que ele está segurando
    pintarLinhaCtl(c.id, valorCtl(c.id), true);
  }
  const mudo = mudoCtl(), b = $('[data-mudo]', corpo);
  if (b) {
    b.setAttribute('aria-pressed', String(!!mudo)); b.classList.toggle('ligado', !!mudo);
    const t = $('.ctl-estado', b), txt = mudo ? 'Mudo' : 'Som ligado';
    if (t.textContent !== txt) { t.textContent = txt; $('.ctl-mic', b).innerHTML = mudo ? SVG_MUDO : SVG.volume }
    $('[data-ctl="volume"]', corpo)?.classList.toggle('mudo', !!mudo);
  }
}
/* `animar` é para o que o Mac mudou e para o toque (o branco sobe e o número conta). Com o dedo arrastando tudo acompanha na hora */
function pintarLinhaCtl(id, v, animar = false) {
  const el = $(`#ct-corpo [data-ctl="${id}"]`); if (!el || !Number.isFinite(v)) return;
  el.style.setProperty('--nivel', v); el.setAttribute('aria-valuenow', v); el.setAttribute('aria-valuetext', v + '%');
  $$('.ctl-num', el).forEach(n => mostrarNumero(n, v, pctCtl, animar));
}

async function enviarCtl(id, v) {
  otmCtl[id] = { v, ate: performance.now() + JANELA_OTM };
  const e = envCtl[id] ??= { quer: v, indo: false }; e.quer = v;
  if (e.indo) return; e.indo = true;
  let enviado = null;
  try { while (e.quer !== enviado) { enviado = e.quer; await canal.controle(id, enviado) } }
  catch (err) { delete otmCtl[id]; tratarErro(err); lerControles() }
  finally { e.indo = false }
}
async function alternarMudo() {
  const quer = !mudoCtl(); otmCtl.mudo = { v: quer, ate: performance.now() + JANELA_OTM }; pintarControles();
  try { await canal.controle('mudo', quer ? 1 : 0) } catch (err) { delete otmCtl.mudo; tratarErro(err); lerControles() }
}

/* Arrasto relativo: o dedo sobe ou desce e o valor acompanha a distância (o cartão todo vale 100), sem pular para onde tocou. Toque sem arrastar
   põe o valor onde o dedo encostou. */
const limCtl = v => Math.min(100, Math.max(0, Math.round(v)));
function moverCtl(ev) {
  const a = arrCtl, dy = a.y0 - ev.clientY;
  if (!a.moveu) { if (Math.abs(dy) < 4 && Math.abs(ev.clientX - a.x0) < 4) return; a.moveu = true; a.el.classList.add('arrastando') }
  a.v = limCtl(a.v0 + dy / a.alt * 100); pintarLinhaCtl(a.id, a.v, false);
  if (performance.now() - a.ultimo > 250) { a.ultimo = performance.now(); enviarCtl(a.id, a.v) } // no máximo 4 por segundo enquanto o dedo anda
}
document.addEventListener('pointerdown', ev => {
  const el = ev.target.closest('.ctl-cartao[data-ctl]'); if (!el || arrCtl) return;
  const r = el.getBoundingClientRect(), id = el.dataset.ctl, v0 = valorCtl(id);
  arrCtl = { el, id, x0: ev.clientX, y0: ev.clientY, v0: Number.isFinite(v0) ? v0 : 0, v: v0, alt: r.height || 1, base: r.bottom, ultimo: 0, moveu: false };
  el.setPointerCapture?.(ev.pointerId);
});
document.addEventListener('pointermove', ev => { if (arrCtl) moverCtl(ev) });
document.addEventListener('pointerup', ev => {
  if (!arrCtl) return; const a = arrCtl; arrCtl = null; a.el.classList.remove('arrastando');
  const v = a.moveu ? a.v : limCtl((a.base - ev.clientY) / a.alt * 100);
  if (!a.moveu) pintarLinhaCtl(a.id, v, true);
  enviarCtl(a.id, v);
});
document.addEventListener('pointercancel', () => { if (!arrCtl) return; arrCtl.el.classList.remove('arrastando'); arrCtl = null; pintarControles() });
document.addEventListener('keydown', ev => {
  const el = ev.target.closest?.('.ctl-cartao[data-ctl]'); if (!el) return;
  const id = el.dataset.ctl, v = valorCtl(id), d = { ArrowUp: 5, ArrowRight: 5, ArrowDown: -5, ArrowLeft: -5 }[ev.key];
  const n = ev.key === 'Home' ? 0 : ev.key === 'End' ? 100 : d ? limCtl(v + d) : null;
  if (n == null || !Number.isFinite(v)) return; ev.preventDefault(); pintarLinhaCtl(id, n, true); enviarCtl(id, n);
});
$('#f-controles').addEventListener('click', ev => {
  if (ev.target.closest('[data-mudo]')) return alternarMudo();
  if (ev.target.closest('[data-ct-tentar]')) { ct.erro = ''; ct.dados = null; pintarControles(); lerControles() }
});

/* aberta, a folha acompanha o Mac a cada 2 s (o volume e o brilho também mudam pelas teclas do próprio Mac) */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-controles' || arrCtl) return;
  lerControles();
}, 2000);
