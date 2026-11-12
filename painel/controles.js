/* Controles do Mac: volume (com mudo), brilho da tela e brilho do teclado, numa folha cheia. O Mac diz o que este aparelho
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

const linhaCtl = c => `<div class="ctl-linha" data-ctl="${c.id}"><span class="ctl-ic" aria-hidden="true">${SVG[c.icone]}</span>
  <span class="ctl-meio"><span class="ctl-topo"><span class="ctl-nome">${c.nome}</span>${c.id === 'volume' && typeof ct.dados.mudo === 'boolean' ? '<button class="btn secundario pequeno" data-mudo aria-pressed="false">Mudo</button>' : ''}</span><span class="trilho" role="slider" aria-label="${c.nome}" aria-valuemin="0" aria-valuemax="100"><i></i></span></span>
  <span class="ctl-num"></span></div>`;
const esqueletoCtl = () => '<div class="esq-lista" aria-hidden="true">' + '<div class="ctl-linha esq"><span class="ctl-ic"></span><span class="ctl-meio"><i class="barra" style="width:30%"></i><i class="barra" style="width:100%"></i></span></div>'.repeat(3) + '</div>';

function pintarControles() {
  const corpo = $('#ct-corpo');
  if (!ct.dados) {
    corpo.setAttribute('aria-busy', String(!ct.erro));
    corpo.innerHTML = ct.erro ? `<div class="vazio-bloco" style="min-height:160px"><strong>Não deu para ler</strong><span>${esc(ct.erro)}</span><button class="btn secundario pequeno" data-ct-tentar style="justify-self:start">Tentar de novo</button></div>` : esqueletoCtl();
    ct.forma = ''; return;
  }
  corpo.setAttribute('aria-busy', 'false');
  const lista = oferecidos(), forma = JSON.stringify([lista.map(c => c.id), typeof ct.dados.mudo === 'boolean']);
  if (forma !== ct.forma) { // o que o Mac oferece mudou: refaz as linhas (senão só mexe nos valores, sem soltar o dedo da barra)
    ct.forma = forma;
    corpo.innerHTML = lista.length ? lista.map(linhaCtl).join('') : '<div class="vazio-bloco" style="min-height:160px"><strong>Nada para controlar</strong><span>Este Mac não oferece volume, brilho nem luz de teclado, ou as barras estão desligadas na tecla Controles do Mac, nos Ajustes do Deck.</span></div>';
  }
  for (const c of lista) {
    if (arrCtl?.id === c.id) continue; // o dedo manda na barra que ele está segurando
    pintarLinhaCtl(c.id, valorCtl(c.id));
  }
  const mudo = mudoCtl(), b = $('[data-mudo]', corpo);
  if (b) { b.setAttribute('aria-pressed', String(!!mudo)); $('[data-ctl="volume"]', corpo)?.classList.toggle('mudo', !!mudo) }
}
function pintarLinhaCtl(id, v) {
  const el = $(`#ct-corpo [data-ctl="${id}"]`); if (!el || !Number.isFinite(v)) return;
  $('i', el).style.width = v + '%'; $('.ctl-num', el).textContent = v; $('.trilho', el).setAttribute('aria-valuenow', v);
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
  arrCtl.v = v; pintarLinhaCtl(arrCtl.id, v);
  if (performance.now() - arrCtl.ultimo > 250) { arrCtl.ultimo = performance.now(); enviarCtl(arrCtl.id, v) } // no máximo 4 por segundo enquanto o dedo anda
}
document.addEventListener('pointerdown', ev => {
  const tr = ev.target.closest('.ctl-linha .trilho'); if (!tr) return;
  const el = tr.closest('.ctl-linha'); arrCtl = { tr, el, id: el.dataset.ctl, v: 0, ultimo: 0 };
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
