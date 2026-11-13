/* Controles do Mac: volume (com mudo), brilho da tela e brilho do teclado, numa folha cheia, um cartão por controle no estilo do Monitor (valor grande que conta, barra que é o controle). O Mac diz o que este aparelho
   oferece em GET /api/controles: o que não vem (sem tela interna, sem luz no teclado, Mac antigo sem a rota) não aparece, em
   vez de fingir. As barras respondem na hora (o valor que o dedo pôs vale até o Mac confirmar) e mandam o último valor,
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
/* Um cartão por controle, no estilo do Monitor: ícone e nome cinza em cima, valor grande, e a barra embaixo que é o próprio controle.
   O Mudo é um cartão que alterna (não um botão solto): ele só existe quando o Mac diz o estado do mudo. */
const cartaoCtl = c => `<div class="ctl-cartao" data-ctl="${c.id}" role="group" aria-label="${c.nome}">
  <span class="ctl-topo"><span class="ctl-ic" aria-hidden="true">${SVG[c.icone]}</span><span class="ctl-rot">${c.nome}</span></span>
  <b class="ctl-num"></b>
  <span class="trilho" role="slider" aria-label="${c.nome}" aria-valuemin="0" aria-valuemax="100"><i></i></span></div>`;
const cartaoMudo = () => `<button class="ctl-cartao ctl-mudo" data-mudo aria-pressed="false" aria-label="Mudo">
  <span class="ctl-topo"><span class="ctl-ic" aria-hidden="true">${SVG.mudo}</span><span class="ctl-rot">Mudo</span></span>
  <b class="ctl-num ctl-estado"></b>
  <span class="ctl-chave" aria-hidden="true"><i></i></span></button>`;
const esqueletoCtl = () => '<div class="ctl-grade" data-n="4" aria-hidden="true">' + '<div class="ctl-cartao esq"><i class="barra" style="width:40%"></i><i class="barra" style="width:70%"></i><i class="barra" style="width:100%"></i></div>'.repeat(4) + '</div>';

function pintarControles() {
  const corpo = $('#ct-corpo');
  if (!ct.dados) {
    corpo.setAttribute('aria-busy', String(!ct.erro));
    corpo.innerHTML = ct.erro ? `<div class="vazio-bloco" style="min-height:160px"><strong>Não deu para ler</strong><span>${esc(ct.erro)}</span><button class="btn secundario pequeno" data-ct-tentar style="justify-self:start">Tentar de novo</button></div>` : esqueletoCtl();
    ct.forma = ''; return;
  }
  corpo.setAttribute('aria-busy', 'false');
  const lista = oferecidos(), comMudo = typeof ct.dados.mudo === 'boolean', forma = JSON.stringify([lista.map(c => c.id), comMudo]);
  if (forma !== ct.forma) { // o que o Mac oferece mudou: refaz os cartões (senão só mexe nos valores, sem soltar o dedo da barra)
    ct.forma = forma;
    // ordem: Volume, Mudo, Brilho, Luz do teclado
    const cartoes = lista.map(cartaoCtl); if (comMudo) cartoes.splice(lista[0]?.id === 'volume' ? 1 : 0, 0, cartaoMudo());
    corpo.innerHTML = cartoes.length ? `<div class="ctl-grade" data-n="${cartoes.length}">${cartoes.join('')}</div>` : '<div class="vazio-bloco" style="min-height:160px"><strong>Nada para controlar</strong><span>Este Mac não oferece volume, brilho nem luz de teclado, ou as barras estão desligadas na tecla Controles do Mac, nos Ajustes do Deck.</span></div>';
  }
  for (const c of lista) {
    if (arrCtl?.id === c.id) continue; // o dedo manda na barra que ele está segurando
    pintarLinhaCtl(c.id, valorCtl(c.id), true);
  }
  const mudo = mudoCtl(), b = $('[data-mudo]', corpo);
  if (b) {
    b.setAttribute('aria-pressed', String(!!mudo)); b.classList.toggle('ligado', !!mudo);
    const t = $('.ctl-estado', b), txt = mudo ? 'Ligado' : 'Desligado'; if (t.textContent !== txt) t.textContent = txt;
    $('[data-ctl="volume"]', corpo)?.classList.toggle('mudo', !!mudo);
  }
}
/* `animar` é só para o que o Mac mudou (o número conta e a barra desliza). Com o dedo na barra tudo acompanha na hora */
function pintarLinhaCtl(id, v, animar = false) {
  const el = $(`#ct-corpo [data-ctl="${id}"]`); if (!el || !Number.isFinite(v)) return;
  $('.trilho i', el).style.transform = `scaleX(${v / 100})`; $('.trilho', el).setAttribute('aria-valuenow', v);
  mostrarNumero($('.ctl-num', el), v, pctCtl, animar);
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

function moverCtl(ev) {
  const r = arrCtl.tr.getBoundingClientRect(), v = Math.round(Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)) * 100);
  arrCtl.v = v; pintarLinhaCtl(arrCtl.id, v, false);
  if (performance.now() - arrCtl.ultimo > 250) { arrCtl.ultimo = performance.now(); enviarCtl(arrCtl.id, v) } // no máximo 4 por segundo enquanto o dedo anda
}
document.addEventListener('pointerdown', ev => {
  const tr = ev.target.closest('.ctl-cartao .trilho'); if (!tr) return;
  const el = tr.closest('.ctl-cartao'); arrCtl = { tr, el, id: el.dataset.ctl, v: 0, ultimo: 0 };
  el.classList.add('arrastando'); tr.setPointerCapture?.(ev.pointerId); moverCtl(ev); ev.preventDefault();
});
document.addEventListener('pointermove', ev => { if (arrCtl) moverCtl(ev) });
document.addEventListener('pointerup', () => {
  if (!arrCtl) return; const { el, id, v } = arrCtl; arrCtl = null; el.classList.remove('arrastando'); enviarCtl(id, v);
});
document.addEventListener('pointercancel', () => { if (!arrCtl) return; arrCtl.el.classList.remove('arrastando'); arrCtl = null; pintarControles() });
$('#f-controles').addEventListener('click', ev => {
  if (ev.target.closest('[data-mudo]')) return alternarMudo();
  if (ev.target.closest('[data-ct-tentar]')) { ct.erro = ''; ct.dados = null; pintarControles(); lerControles() }
});

/* aberta, a folha acompanha o Mac a cada 2 s (o volume e o brilho também mudam pelas teclas do próprio Mac) */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-controles' || arrCtl) return;
  lerControles();
}, 2000);
