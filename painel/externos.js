/* O que chega de fora do Deck e o GitHub, no iPhone.
   - Avisos de fora (um script do Mac manda): aparecem uma vez como toast discreto, no mesmo aviso de sempre (avisar, em deck.js).
   - Valores de fora: a tecla Valores abre uma folha com um cartão por valor, até ele vencer.
   - GitHub: a tecla GitHub mostra a contagem no selo e abre uma folha com os PRs esperando a revisão e os com a CI falhando.
     Tocar num PR pede ao Mac para abrir no navegador dele, e só então. O endereço nunca vem para o iPhone: vai só o id.
   Usa as peças de deck.js (V, canal, avisar, abrirFolha, folhaAberta, tratarErro, semAcesso, offline) e util.js (SVG, esc). */

/* ---------- avisos de fora: toast, uma vez por id ---------- */
const TEMPO_TOAST = 3600;      // um toast e o próximo: dá tempo de ler e não empilha
const IDADE_MAX_AVISO = 30000; // na primeira vez que a página vê a lista, só o que chegou há pouco ainda interessa
const af = { visto: 0, fila: [], ocupado: false, primeira: true };

function processarAvisosDeFora(e) {
  const lista = Array.isArray(e?.avisosDeFora) ? e.avisosDeFora : [];
  const ref = Date.parse(e.agora) || Date.now();
  // O Mac reiniciou e a contagem dele voltou: se tudo o que ele manda é menor que o que já vi, recomeço do zero
  const ids = lista.filter(a => a && Number.isInteger(a.id)).map(a => a.id);
  if (ids.length && Math.max(...ids) < af.visto) af.visto = 0;
  const novos = lista.filter(a => a && Number.isInteger(a.id) && a.id > af.visto);
  if (!novos.length) { af.primeira = false; return }
  af.visto = Math.max(af.visto, ...novos.map(a => a.id));
  // Reabrir a página não repete o que ela já mostrou antes: o que é velho no primeiro olhar fica de fora
  for (const a of novos) if (!af.primeira || ref - Date.parse(a.em) <= IDADE_MAX_AVISO) af.fila.push(a);
  af.primeira = false;
  if (af.fila.length > 3) af.fila.splice(0, af.fila.length - 3); // rajada: só os 3 últimos, o resto já ficou velho
  tocarFila();
}
function tocarFila() {
  if (af.ocupado) return;
  if (!af.fila.length) return;
  // Já há um aviso na tela (o Desfazer de uma ação, um erro de verdade): o de fora espera a vez e não o cobre
  if ($('#aviso')?.classList.contains('visivel')) { af.ocupado = true; setTimeout(() => { af.ocupado = false; tocarFila() }, 500); return }
  const a = af.fila.shift();
  af.ocupado = true;
  avisar(a.texto ? `${a.titulo}. ${a.texto}` : a.titulo, { erro: a.nivel === 'erro' });
  setTimeout(() => { af.ocupado = false; tocarFila() }, TEMPO_TOAST);
}

/* ---------- valores de fora ---------- */
const vencePara = (ate, ref) => {
  const s = Math.round((Date.parse(ate) - ref) / 1000);
  if (!(s > 0)) return 'vencendo';
  if (s < 60) return 'vence em menos de 1 min';
  const m = Math.round(s / 60);
  return m < 60 ? `vence em ${m} min` : `vence em ${Math.round(m / 60)} h`;
};
const vl = { chave: '' };
function pintarValores() {
  const corpo = $('#vl-corpo'); if (!corpo || !V) return;
  const lista = Array.isArray(V.valoresDeFora) ? V.valoresDeFora : [];
  const html = lista.length
    ? `<div class="vl-grade">${lista.map(v => `<div class="mt-bloco" role="group" aria-label="${esc(v.chave)}: ${esc(v.valor)}"><span class="mt-topo"><span class="mt-ic" aria-hidden="true">${SVG.valores}</span><span class="mt-nome">${esc(v.chave)}</span></span><b class="mt-valor${v.valor.length > 12 ? ' longo' : ''}">${esc(v.valor)}</b><span class="mt-sub">${esc(vencePara(v.ate, V.ref))}</span></div>`).join('')}</div>`
    : '<div class="vazio-bloco" style="min-height:160px"><strong>Nenhum valor agora</strong><span>Um script do Mac manda o valor e ele fica aqui até vencer. A chave e o exemplo estão nos Ajustes do Deck, em Este Mac.</span></div>';
  if (html === vl.chave) return;
  vl.chave = html; manterRolagem(corpo, html);
}
function abrirValores() { vl.chave = ''; pintarValores(); abrirFolha('#f-valores') }

/* ---------- GitHub ---------- */
const gh = { chave: '', ocupado: false };
const grupoGh = (titulo, itens, classe, mais = 0) => `<section class="gh-grupo ${classe}" aria-label="${esc(titulo)}"><h3>${esc(titulo)}<small>${itens.length + mais}</small></h3>${itens.map(i =>
  `<button class="gh-linha" data-gh="${esc(i.id)}"><span class="gh-tx"><b>${esc(i.titulo)}</b><small>${esc(i.repo)} #${i.numero}</small></span><span class="gh-seta" aria-hidden="true">${SVG.dir}</span></button>`).join('')}${mais > 0 ? `<p class="gh-lido gh-mais">e mais ${mais} no GitHub</p>` : ''}</section>`;
function githubHTML() {
  const g = V?.github;
  if (!g) return '<div class="vazio-bloco" style="min-height:160px"><strong>Lendo o GitHub</strong><span>Um instante.</span></div>';
  if (g.estado === 'sem-gh' || g.estado === 'sem-login' || g.estado === 'erro') {
    const titulo = { 'sem-gh': 'O gh não está instalado', 'sem-login': 'O gh não está logado', erro: 'Não deu para ler o GitHub' }[g.estado];
    return `<div class="vazio-bloco" style="min-height:160px"><strong>${titulo}</strong><span>${esc(g.aviso || '')}</span></div>`;
  }
  const revisar = g.revisar || [], falhando = g.falhando || [];
  if (!revisar.length && !falhando.length) return '<div class="vazio-bloco" style="min-height:160px"><strong>Tudo em dia</strong><span>Nenhum PR esperando você e nenhum seu com a CI falhando.</span></div>';
  const lido = g.lidoEm ? new Date(g.lidoEm) : null;
  return `<div class="gh-grupos">${revisar.length ? grupoGh('Esperando sua revisão', revisar, 'revisar', g.maisRevisar | 0) : ''}${falhando.length ? grupoGh('CI falhando', falhando, 'falhando', g.maisFalhando | 0) : ''}</div>${lido && !isNaN(lido) ? `<p class="gh-lido">Lido às ${hhmm(lido)}</p>` : ''}`;
}
function pintarGitHub() {
  const corpo = $('#gh-corpo'); if (!corpo || !V) return;
  const html = githubHTML();
  if (html === gh.chave) return;
  gh.chave = html; manterRolagem(corpo, html);
}
function abrirGitHub() { gh.chave = ''; pintarGitHub(); abrirFolha('#f-github') }
$('#f-github')?.addEventListener('click', async ev => {
  const b = ev.target.closest('[data-gh]'); if (!b || gh.ocupado) return;
  gh.ocupado = true;
  try { await canal.abrirGitHub(b.dataset.gh); avisar('Abrindo o PR no navegador do Mac') } catch (e) { tratarErro(e) } finally { gh.ocupado = false }
});

/* abertas, as folhas acompanham o estado a cada segundo */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline) return;
  if (folhaAberta?.id === 'f-valores') pintarValores();
  else if (folhaAberta?.id === 'f-github') pintarGitHub();
}, 1000);
