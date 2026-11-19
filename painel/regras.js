/* Regras automáticas (SPEC 13, item 40). O Mac decide quando uma regra vale e manda a lista em estado.regras. Aqui o iPhone
   mostra o cartão "Indo para Sessões em 3" (Ficar e Ir agora), troca de tela, composição ou perfil quando a contagem acaba e,
   nas regras "enquanto durar", desfaz quando a regra deixa de vir na lista. Nunca troca com a pessoa tocando na tela
   (últimos 10 s). Cartão inspirado no navCard do PhoneBox (MIT, Ersin Koç, github.com/ersinkoc/phonebox): anel que esvazia
   e dois botões. Usa as peças de deck.js e paineis.js (V, salvar, ativarPerfil, abrirPainel, abrirFolha, avisar). */

const RG = { tratadas: new Set(), atual: null, aplicadas: [], toque: -Infinity, timer: 0 };
const regrasCartao = () => $('#cartao-regra');

/* o toque na própria tela adia a troca. Os botões do cartão não contam: são a resposta dela */
function regrasToque(ev) { if (!ev.target.closest?.('#cartao-regra')) RG.toque = performance.now() }
['pointerdown', 'touchstart', 'keydown', 'wheel'].forEach(n => addEventListener(n, regrasToque, { capture: true, passive: true }));

/* tocando: nos últimos 10 s, organizando as teclas, editando uma, com a página escondida ou pareando */
const regrasOcupada = () => performance.now() - RG.toque < AJUSTES.semToqueMs || organizando || folhaAberta?.id === 'f-editor' || document.hidden || !!$('#t-parear:not([hidden])');

function regrasMostrar(r, n) {
  const c = regrasCartao();
  $('#cr-texto').textContent = `${r.texto} em ${n}`;
  if (!c.classList.contains('visivel')) {
    const v = $('#cr-volta'); v.style.animation = 'none'; void v.getBoundingClientRect(); v.style.animation = '';
    v.style.setProperty('--cr-dur', r.segundos + 's');
    c.classList.add('visivel'); c.setAttribute('aria-hidden', 'false'); $$('button', c).forEach(b => b.removeAttribute('tabindex'));
  }
}
function regrasEsconder() {
  const c = regrasCartao(); if (!c.classList.contains('visivel')) return;
  c.classList.remove('visivel'); c.setAttribute('aria-hidden', 'true'); $$('button', c).forEach(b => b.setAttribute('tabindex', '-1'));
  if (c.contains(document.activeElement)) document.activeElement.blur();
}

function regrasIrParaTela(alvo) {
  if ($('#f-relogio.aberta')) fecharRelogio();
  if (folhaAberta) fecharFolha();
  if (alvo === 'inicio') return;
  if (alvo === 'uso') return abrirUso();
  if (alvo === 'player') { if (V?.spotify) abrirPlayer(); return }
  abrirPainel(alvo);
}
function regrasExecutar(r) {
  RG.atual = null; regrasPararTique(); regrasEsconder();
  const a = { seq: r.seq, tipo: r.tipo, alvo: r.alvo, durar: r.durar };
  if (r.tipo === 'tela') { regrasIrParaTela(r.alvo); a.folha = folhaAberta }
  else if (r.tipo === 'composicao') { a.antes = V.comp; if (V.comp !== r.alvo) salvar(base => { base.comp = r.alvo; return base }) }
  else if (r.tipo === 'perfil') { a.antes = V.perfilAtivo; ativarPerfil(r.alvo) }
  if (r.durar) RG.aplicadas.push(a);
}
/* desfaz só o que a própria regra fez e que ainda está como ela deixou: se a pessoa mexeu depois, o gesto dela manda */
function regrasDesfazer(a) {
  if (a.tipo === 'tela') { if (a.folha && folhaAberta === a.folha) fecharFolha() }
  else if (a.tipo === 'composicao') { if (V.comp === a.alvo && a.antes && a.antes !== a.alvo) salvar(base => { base.comp = a.antes; return base }) }
  else if (a.tipo === 'perfil') { if (V.perfilAtivo === a.alvo && a.antes && V.perfis.some(p => p.id === a.antes)) ativarPerfil(a.antes) }
}

function regrasTique() {
  const r = RG.atual; if (!r) return regrasPararTique();
  const agora = performance.now();
  if (regrasOcupada()) { r.inicio = 0; regrasEsconder(); return }
  if (!r.inicio) r.inicio = agora;
  const resta = r.segundos - (agora - r.inicio) / 1000;
  if (resta <= 0) return regrasExecutar(r);
  regrasMostrar(r, Math.ceil(resta));
}
function regrasLigarTique() { if (!RG.timer) RG.timer = setInterval(regrasTique, 250) }
function regrasPararTique() { clearInterval(RG.timer); RG.timer = 0 }

/* chamado a cada estado novo do Mac (deck.js, passo) */
function regrasPasso(e) {
  const lista = Array.isArray(e.regras) ? e.regras : [], vivas = new Set(lista.map(r => r.seq));
  for (const s of RG.tratadas) if (!vivas.has(s)) RG.tratadas.delete(s);
  for (const a of RG.aplicadas.filter(x => !vivas.has(x.seq)).reverse()) { RG.aplicadas.splice(RG.aplicadas.indexOf(a), 1); regrasDesfazer(a) }
  if (RG.atual && !vivas.has(RG.atual.seq)) { RG.atual = null; regrasPararTique(); regrasEsconder() }
  if (!RG.atual) {
    const nova = lista.find(r => !RG.tratadas.has(r.seq));
    if (nova) {
      RG.tratadas.add(nova.seq);
      if (nova.tipo === 'aviso') avisar(nova.texto);
      else { RG.atual = { ...nova, inicio: 0 }; regrasLigarTique() }
    }
  }
  if (RG.atual) regrasTique();
}

$('#cr-ficar').addEventListener('click', () => { RG.atual = null; regrasPararTique(); regrasEsconder() });
$('#cr-ir').addEventListener('click', () => { if (RG.atual) regrasExecutar(RG.atual) });
