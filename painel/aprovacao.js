/* Aprovar pedidos de permissão do Claude Code pelo iPhone, e o resumo das sessões que não esperam resposta.
   O Mac manda os pedidos em Estado.aprovacoes ({id, projeto, ferramenta, titulo, resumo, restante}) e recebe a resposta em
   POST /api/aprovacoes/<id> (canal.aprovar). Sem resposta no prazo, ou com o terminal respondendo antes, o pedido some daqui
   sozinho: o Mac simplesmente deixa de mandá-lo, e o terminal pergunta como sempre.
   Usa as peças de deck.js (V, tela, canal, avisar, tratarErro) e de util.js (esc, mmss). */

const ap = { lista: [], t0: 0, ids: '', respondidos: new Set(), vistos: new Set(), enviando: false };
const apCaixa = () => $('#aprovacao');

/* quanto falta de um pedido, contando do momento em que o estado chegou (o relógio do Mac e o do iPhone não precisam bater) */
const apRestante = p => Math.max(0, p.restante - (performance.now() - ap.t0) / 1000);

function apHTML(p, total) {
  return `<div class="ap-caixa"><span class="rotulo">Claude Code pede${total > 1 ? `<b class="ap-n">1 de ${total}</b>` : ''}</span>
    <h2 id="ap-titulo">${esc(p.titulo || 'Usar uma ferramenta')}</h2>
    ${p.projeto ? `<small class="ap-projeto">${esc(p.projeto)}</small>` : ''}
    ${p.resumo ? `<p class="ap-resumo">${esc(p.resumo)}</p>` : ''}
    <div class="ap-rodape"><time class="ap-tempo" aria-label="Tempo que resta"></time>
      <button class="btn secundario" data-ap="deny">Negar</button><button class="btn primario" data-ap="allow">Permitir</button></div></div>`;
}

/* chamado a cada estado novo (mostrarVista, em deck.js) */
function pintarAprovacoes() {
  const caixa = apCaixa(); if (!caixa) return;
  ap.lista = (V.aprovacoes || []).filter(p => p && p.id && !ap.respondidos.has(p.id));
  ap.t0 = performance.now();
  // o que o Mac já não manda mais (venceu ou o terminal respondeu) deixa de ser lembrado
  const ativos = new Set((V.aprovacoes || []).map(p => p.id));
  for (const id of ap.respondidos) if (!ativos.has(id)) ap.respondidos.delete(id);
  const chave = ap.lista.map(p => p.id).join('|') + '#' + ap.lista.length;
  if (chave !== ap.ids) {
    ap.ids = chave;
    if (ap.lista.length) caixa.innerHTML = apHTML(ap.lista[0], ap.lista.length);
    caixa.hidden = !ap.lista.length;
    if (ap.lista.some(p => !ap.vistos.has(p.id))) { try { canal.vibrar?.() } catch {} } // no app nativo o iPhone vibra: o pedido novo chama a atenção
    for (const p of ap.lista) ap.vistos.add(p.id);
  }
  apTempo();
}
function apTempo() {
  const p = ap.lista[0], el = $('.ap-tempo'); if (!p || !el) return;
  const r = apRestante(p);
  el.textContent = mmss(r);
  if (r <= 0) { ap.lista = ap.lista.slice(1); ap.ids = ''; if (!ap.lista.length) apCaixa().hidden = true }
}
setInterval(() => { if (ap.lista.length) apTempo() }, 500);

async function apResponder(decisao) {
  const p = ap.lista[0]; if (!p || ap.enviando) return;
  ap.enviando = true;
  ap.respondidos.add(p.id); ap.lista = ap.lista.slice(1); ap.ids = ''; // some na hora: a resposta otimista
  if (!ap.lista.length) apCaixa().hidden = true; else { apCaixa().innerHTML = apHTML(ap.lista[0], ap.lista.length); apTempo() }
  try { await canal.aprovar(p.id, decisao) }
  catch (e) {
    if (e.status === 404) avisar('Esse pedido já foi respondido ou venceu.');
    else { ap.respondidos.delete(p.id); tratarErro(e) } // não chegou ao Mac: o pedido volta no próximo estado
  } finally { ap.enviando = false }
}
document.addEventListener('click', e => {
  const b = e.target.closest('[data-ap]'); if (b) apResponder(b.dataset.ap);
});

/* ---------- sessões que não esperam resposta ---------- */
/* "3 trabalhando, 1 parada": o resumo do bloco. As que acabaram de terminar não entram na conta, só no aviso */
function resumoOutras(outras) {
  const t = (outras || []).filter(s => s.situacao === 'trabalhando').length, p = (outras || []).filter(s => s.situacao === 'parada').length;
  return [t ? `${t} trabalhando` : '', p ? `${p} ${p === 1 ? 'parada' : 'paradas'}` : ''].filter(Boolean).join(', ');
}
const sv = { antes: new Map(), pronto: false };
/* Aviso discreto quando uma sessão que estava trabalhando termina. Na primeira leitura não avisa de nada (não houve "antes") */
function notarSessoes() {
  const outras = V.outras || [];
  if (sv.pronto) {
    const acabaram = outras.filter(s => s.situacao === 'concluida' && sv.antes.get(s.id) === 'trabalhando');
    if (acabaram.length === 1) avisar(`${acabaram[0].nome} terminou`);
    else if (acabaram.length > 1) avisar(`${acabaram.length} sessões terminaram`);
  }
  sv.antes = new Map(outras.map(s => [s.id, s.situacao])); sv.pronto = true;
}
