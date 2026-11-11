/* Extras do player em tela cheia: volume, curtir, aparelhos, fila e repetir só a música. Usa as peças de deck.js (V, canal,
   avisar, otimistaSpotify, enfileirarSpotify...) e é carregado antes dele, então só toca nelas quando a pessoa age.
   O que aparece vem do que o Mac de quem usa manda: sem o Spotify conectado nos Ajustes do Mac (conectado !== true) só
   o volume existe, e um Mac antigo, que não manda os campos novos, não mostra nada a mais. */

const CHAVE_ALVO_VOLUME = 'deck-alvo-volume';
const conectado = s => s?.conectado === true;
/* De quem é o volume que a barra mexe: do Spotify ou do Mac. Só há escolha quando o Mac manda os dois, e a pessoa escolhe no botão ao lado */
function alvoDoVolume(s) {
  const tem = { spotify: s.volume != null, mac: s.volumeMac != null }, pref = lerGuardado(CHAVE_ALVO_VOLUME);
  return tem[pref] ? pref : tem.spotify ? 'spotify' : tem.mac ? 'mac' : null;
}
const volumeDe = (s, alvo) => alvo === 'mac' ? s.volumeMac : s.volume;
const chaveExtras = s => JSON.stringify([alvoDoVolume(s), s.volume != null && s.volumeMac != null, conectado(s)]); // o que muda a forma da linha (o valor da barra não)

/* ---------- repetir: com o Spotify conectado são três jeitos (nada, a lista, só a música) ---------- */
const modoRepetir = s => conectado(s) ? (s.repetirFaixa ? 'faixa' : s.repetir ? 'contexto' : 'nao') : (s.repetir ? 'contexto' : 'nao');
const ROTULO_REPETIR = { nao: 'Repetir: desligado', contexto: 'Repetir a lista ou o álbum', faixa: 'Repetir só a música' };
const PROXIMO_REPETIR = { nao: 'contexto', contexto: 'faixa', faixa: 'nao' };
function repetirCiclo() {
  const s = V.spotify; if (!s || V.carregando) return;
  const novo = PROXIMO_REPETIR[modoRepetir(s)];
  otimistaSpotify(novo === 'faixa' ? { repetirFaixa: true } : { repetir: novo === 'contexto', repetirFaixa: false });
  V = vistaReal(); atualizar(); avisar(ROTULO_REPETIR[novo]);
  return enfileirarSpotify(async () => { try { await canal.repetirModo(novo); await atualizarJa() } catch (e) { desfazerSpotify(); tratarErro(e) } });
}
function curtir() {
  const s = V.spotify; if (!s || V.carregando || !conectado(s)) return;
  const quer = !s.curtida;
  otimistaSpotify({ curtida: quer }); V = vistaReal(); atualizar(); avisar(quer ? 'Curtida' : 'Curtida removida');
  return enfileirarSpotify(async () => { try { await canal.curtir(quer); await atualizarJa() } catch (e) { desfazerSpotify(); tratarErro(e) } });
}

/* ---------- a linha de extras do player grande ---------- */
function extrasPlayerHTML(s) {
  const alvo = alvoDoVolume(s), login = conectado(s);
  if (!alvo && !login) return '';
  const dois = s.volume != null && s.volumeMac != null, v = Math.round(volumeMostrado(s, alvo) ?? 0), rot = alvo === 'mac' ? 'Volume do Mac' : 'Volume do Spotify';
  const vol = alvo ? `<div class="volume" data-alvo="${alvo}">
      ${dois ? `<button class="vol-alvo" data-vol-alvo aria-label="${rot}. Toque para mexer no volume do ${alvo === 'mac' ? 'Spotify' : 'Mac'}">${SVG.volume}<small>${alvo === 'mac' ? 'Mac' : 'Spotify'}</small></button>` : `<span class="vol-icone" aria-hidden="true">${SVG.volume}</span>`}
      <span class="trilho" role="slider" aria-label="${rot}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${v}"><i style="width:${v}%"></i></span><span class="vol-num">${v}</span></div>` : '';
  const botoes = login ? `<button class="extra" data-curtir aria-label="Curtir" aria-pressed="${!!s.curtida}">${SVG.curtir}</button><button class="extra" data-aparelhos aria-label="Tocar em outro aparelho">${SVG.aparelhos}</button><button class="extra" data-fila aria-label="Fila">${SVG.fila}</button>` : '';
  return `<div class="pc-extras">${vol}${botoes}</div>`;
}
/* o valor que a barra mostra: o que o dedo pôs, até o Mac confirmar (ou desistir, depois de JANELA_OTM) */
const otmVol = {};
function volumeMostrado(s, alvo) {
  const o = otmVol[alvo], real = volumeDe(s, alvo);
  if (!o) return real;
  if (performance.now() > o.ate || real === o.v) { delete otmVol[alvo]; return real }
  return o.v;
}
function pintarExtras(s) {
  const raiz = $('#f-player .pc-extras'); if (!raiz) return;
  const alvo = $('.volume', raiz)?.dataset.alvo;
  if (alvo && !arrVol) pintarVolume($('.volume', raiz), Math.round(volumeMostrado(s, alvo) ?? 0));
  $('[data-curtir]', raiz)?.setAttribute('aria-pressed', String(!!s.curtida));
}
function pintarVolume(el, v) {
  $('i', el).style.width = v + '%'; $('.vol-num', el).textContent = v; $('.trilho', el).setAttribute('aria-valuenow', v);
}

/* barra de volume arrastável. Manda enquanto o dedo anda (no máximo 4 vezes por segundo) e de novo ao soltar,
   e nunca dois pedidos ao mesmo tempo: o Mac recebe sempre o último valor, na ordem */
let arrVol = null;
const volEnv = {};
async function enviarVolume(alvo, v) {
  otmVol[alvo] = { v, ate: performance.now() + JANELA_OTM };
  if (alvo === 'aparelho' && Array.isArray(lp.dados)) for (const a of lp.dados) if (a.ativo) a.volume = v; // a lista de aparelhos guarda o que o dedo pôs
  const e = volEnv[alvo] ??= { quer: v, indo: false }; e.quer = v;
  if (e.indo) return; e.indo = true;
  let enviado = null;
  try { while (e.quer !== enviado) { enviado = e.quer; await canal.spotifyVolume(enviado, alvo) } }
  catch (err) { delete otmVol[alvo]; tratarErro(err); if (V) { V = vistaReal(); atualizar() } }
  finally { e.indo = false }
}
function moverVolume(ev) {
  const r = arrVol.tr.getBoundingClientRect(), v = Math.round(Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)) * 100);
  arrVol.v = v; pintarVolume(arrVol.el, v);
  if (performance.now() - arrVol.ultimo > 250) { arrVol.ultimo = performance.now(); enviarVolume(arrVol.alvo, v) }
}
document.addEventListener('pointerdown', ev => {
  const tr = ev.target.closest('.volume .trilho'); if (!tr) return;
  const el = tr.closest('.volume'); arrVol = { tr, el, alvo: el.dataset.alvo, v: 0, ultimo: 0 };
  el.classList.add('arrastando'); tr.setPointerCapture?.(ev.pointerId); moverVolume(ev); ev.preventDefault();
});
document.addEventListener('pointermove', ev => { if (arrVol) moverVolume(ev) });
document.addEventListener('pointerup', () => {
  if (!arrVol) return; const { el, alvo, v } = arrVol; arrVol = null; el.classList.remove('arrastando');
  enviarVolume(alvo, v);
});
document.addEventListener('pointercancel', () => { if (!arrVol) return; arrVol.el.classList.remove('arrastando'); arrVol = null; if (V?.spotify) pintarExtras(V.spotify) });

/* ---------- aparelhos e fila: uma lista por cima do player, lida do Spotify pelo Mac ---------- */
const lp = { qual: null, dados: null, erro: '', semLogin: false, seq: 0, faixa: '' };
const TIPOS_APARELHO = { computer: 'Computador', smartphone: 'Celular', tablet: 'Tablet', speaker: 'Caixa de som', tv: 'TV', castaudio: 'Caixa de som', castvideo: 'TV', audiodongle: 'Caixa de som', avr: 'Receiver', stb: 'Decodificador', gameconsole: 'Videogame', automobile: 'Carro' };
const esqueletoLinhas = () => '<div class="esq-lista" aria-hidden="true">' + '<div class="item-lista esq"><span class="tx"><i class="barra" style="width:50%"></i><i class="barra" style="width:30%"></i></span></div>'.repeat(4) + '</div>';
function abrirListaPlayer(qual) { lp.qual = qual; lp.dados = null; lp.erro = ''; lp.semLogin = false; lp.faixa = V.spotify?.faixa || ''; pintarListaPlayer(); lerListaPlayer() }
function fecharListaPlayer() { lp.qual = null; lp.seq++; $('#pc-lista').hidden = true }
async function lerListaPlayer() {
  const n = ++lp.seq, qual = lp.qual; if (!qual) return;
  try {
    const d = await (qual === 'fila' ? canal.fila() : canal.aparelhos());
    if (n !== lp.seq) return; lp.dados = d; lp.erro = ''; lp.semLogin = false;
  } catch (e) {
    if (n !== lp.seq) return;
    if (e.status === 401) { fecharListaPlayer(); return tratarErro(e) }
    lp.erro = e.rede ? 'Sem conexão com o Mac. Confira o Wi-Fi.' : e.message; lp.semLogin = e.status === 409;
  }
  pintarListaPlayer();
}
function pintarListaPlayer() {
  const el = $('#pc-lista'), corpo = $('#pc-lista-corpo'); if (!lp.qual) { el.hidden = true; return }
  el.hidden = false; $('#pc-lista-titulo').textContent = lp.qual === 'fila' ? 'Na fila' : 'Tocar em';
  corpo.setAttribute('aria-busy', String(!lp.dados && !lp.erro));
  if (lp.erro) { corpo.innerHTML = lp.semLogin ? `<div class="vazio-bloco"><strong>Spotify não conectado</strong><span>${esc(lp.erro)}</span></div>` : erroLista(lp.erro, 0); return }
  if (!lp.dados) { if (!corpo.querySelector('.esq-lista')) corpo.innerHTML = esqueletoLinhas(); return }
  const y = corpo.scrollTop;
  corpo.innerHTML = lp.qual === 'fila' ? filaHTML(lp.dados) : aparelhosHTML(lp.dados);
  corpo.scrollTop = y;
}
const linhaFila = i => `<div class="item-lista"><span class="tx"><b>${esc(i.faixa)}</b><small>${esc(i.artista || '')}</small></span></div>`;
function filaHTML(f) {
  const atual = f.atual ? `<section class="grupo-data"><h3>Tocando agora</h3>${linhaFila(f.atual)}</section>` : '';
  const prox = (f.proximas || []).length ? `<section class="grupo-data"><h3>Próximas</h3>${f.proximas.map(linhaFila).join('')}</section>` : '<div class="vazio-bloco" style="min-height:120px"><strong>A fila está vazia</strong><span>Quando você pôr músicas na fila, elas aparecem aqui.</span></div>';
  return atual + prox;
}
function aparelhosHTML(lista) {
  if (!lista.length) return '<div class="vazio-bloco"><strong>Nenhum aparelho achado</strong><span>Abra o Spotify no aparelho em que quer ouvir, e ele aparece aqui.</span></div>';
  return lista.map(a => {
    const tipo = TIPOS_APARELHO[a.tipo] && TIPOS_APARELHO[a.tipo].toLowerCase() !== String(a.nome).toLowerCase() ? TIPOS_APARELHO[a.tipo] : '', nota = a.restrito ? 'o Spotify não deixa controlar' : '';
    const volume = a.ativo && a.volume != null ? `<div class="volume volume-aparelho" data-alvo="aparelho"><span class="vol-icone" aria-hidden="true">${SVG.volume}</span><span class="trilho" role="slider" aria-label="Volume de ${esc(a.nome)}" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${a.volume}"><i style="width:${a.volume}%"></i></span><span class="vol-num">${a.volume}</span></div>` : '';
    return `<button class="item-lista" data-aparelho="${esc(a.id)}" aria-pressed="${!!a.ativo}" ${a.restrito || !a.id ? 'disabled' : ''}><span class="tx"><b>${esc(a.nome)}</b><small>${esc([tipo, nota].filter(Boolean).join(', '))}</small></span>${a.ativo ? '<span class="tag">Tocando aqui</span>' : ''}</button>${volume}`;
  }).join('');
}
/* passar a música para outro aparelho: a lista já marca o escolhido no toque, e volta se o Mac recusar */
async function trocarAparelho(id) {
  const lista = lp.dados; if (!Array.isArray(lista)) return;
  const novo = lista.find(a => a.id === id); if (!novo || novo.ativo) return;
  const antes = lista.map(a => ({ ...a }));
  lp.dados = lista.map(a => ({ ...a, ativo: a.id === id })); pintarListaPlayer(); avisar(`Tocando em ${novo.nome}`);
  try { await canal.transferir(id); atualizarJa(); setTimeout(() => { if (lp.qual === 'aparelhos') lerListaPlayer() }, 1200) }
  catch (e) { if (lp.qual === 'aparelhos') { lp.dados = antes; pintarListaPlayer() } tratarErro(e) }
}
$('#f-player').addEventListener('click', ev => {
  if (ev.target.closest('[data-curtir]')) return curtir();
  if (ev.target.closest('[data-aparelhos]')) return abrirListaPlayer('aparelhos');
  if (ev.target.closest('[data-fila]')) return abrirListaPlayer('fila');
  if (ev.target.closest('[data-pc-voltar]')) return fecharListaPlayer();
  if (ev.target.closest('[data-tentar]')) { lp.erro = ''; lp.dados = null; pintarListaPlayer(); return lerListaPlayer() }
  const a = ev.target.closest('[data-aparelho]'); if (a) return trocarAparelho(a.dataset.aparelho);
  if (ev.target.closest('[data-vol-alvo]')) {
    const s = V.spotify, novo = alvoDoVolume(s) === 'mac' ? 'spotify' : 'mac';
    guardar(CHAVE_ALVO_VOLUME, novo); cheioChave = ''; pintarPlayerCheio(); avisar(novo === 'mac' ? 'Volume do Mac' : 'Volume do Spotify');
  }
});
