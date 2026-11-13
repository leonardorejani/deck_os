/* Painéis de tela inteira (SPEC, seção 5): WhatsApp, Agenda, Sessões, Controles e Monitor. Mesmas folhas do protótipo,
   com a lista vindo do Mac pelo canal. Usa as peças de deck.js (V, canal, avisar, abrirFolha...). */

const iniciais = n => String(n).split(' ').filter(Boolean).slice(0, 2).map(p => p[0]).join('').toUpperCase();
const tokCss = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), msCss = n => parseFloat(tokCss(n)) || 0;
const pad2 = n => String(n).padStart(2, '0');
const hhmm = d => pad2(d.getHours()) + ':' + pad2(d.getMinutes());
const dataIso = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; // AAAA-MM-DD do dia local
const mesmoDia = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const reduzido = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

/* A tecla do app que abriu o painel manda o Mac abrir o app (WhatsApp, Calendário). Se ela sumiu, procura outra igual */
const teclaDoPainel = {};
function abrirPainel(qual, idTecla) {
  if (idTecla) teclaDoPainel[qual] = idTecla;
  if (qual === 'whatsapp') abrirWhats(); else if (qual === 'calendario') abrirCal(); else if (qual === 'sessoes') abrirSessoes(); else if (qual === 'controles') abrirControles(); else if (qual === 'monitor') abrirMonitor(); else if (qual === 'meet') abrirMeet();
}
async function abrirNoMac(qual, texto) {
  const id = V.teclas.some(t => t.id === teclaDoPainel[qual]) ? teclaDoPainel[qual] : V.teclas.find(t => painelDe(t) === qual)?.id;
  if (!id) return avisar('Não achei a tecla desse app no perfil de agora.', { erro: true });
  if (ocupadas.has(id)) return;
  ocupadas.add(id);
  try { await canal.botao(id); avisar(texto) } catch (e) { tratarErro(e) } finally { ocupadas.delete(id) }
}
// refaz o conteúdo de uma lista sem perder o ponto da rolagem (o laço de 4 s não pode puxar a pessoa para o topo)
function manterRolagem(el, html) { const y = el.scrollTop; el.innerHTML = html; el.scrollTop = y }
// mensagem de erro de uma leitura, no lugar da lista, com a saída "Tentar de novo"
const erroLista = (msg, min = 160) => `<div class="vazio-bloco" style="min-height:${min}px"><strong>Não deu para ler</strong><span>${esc(msg)}</span><button class="btn secundario pequeno" data-tentar style="justify-self:start">Tentar de novo</button></div>`;
/* esqueleto da lista enquanto o Mac lê (SPEC 6): invisível nos primeiros 200 ms, depois com a forma das linhas */
const esqueletoWa = () => '<div class="esq-lista" aria-hidden="true">' + '<div class="conversa esq"><span class="avatar"></span><span><i class="barra" style="width:50%"></i><i class="barra" style="width:80%"></i></span><i class="barra" style="width:32px"></i></div>'.repeat(6) + '</div>';
const esqueletoCal = () => '<div class="esq-lista" aria-hidden="true"><section class="grupo-data"><h3><i class="barra" style="width:40%"></i></h3>' + '<div class="ev-linha esq"><i class="barra" style="width:44px;align-self:center"></i><i style="background:var(--superficie-2)"></i><span class="tx"><i class="barra" style="width:60%"></i><i class="barra" style="width:35%"></i></span></div>'.repeat(4) + '</section></div>';
const msgErro = e => e.rede ? 'Sem conexão com o Mac. Confira o Wi-Fi.' : e.message;

/* ---------- WhatsApp ---------- */
const wa = { lista: null, json: '', filtro: 'todas', aberta: null, erro: '', mexendo: false, seq: 0, pendente: false, lendo: false, total: null, abrindo: false };
function horaConversa(iso) {
  const d = new Date(iso); if (isNaN(d)) return '';
  const dias = diasEntre(d, V?.ref || Date.now());
  return dias <= 0 ? hhmm(d) : dias === 1 ? 'ontem' : dias < 7 ? d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '') : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}
function abrirWhats() { wa.aberta = null; wa.filtro = 'todas'; wa.lista = null; wa.json = ''; wa.erro = ''; wa.pendente = false; wa.total = null; pintarWhats(); abrirFolha('#f-whats'); lerWhats() }
/* um player tocando não pode ser derrubado por uma mensagem nova: a lista repinta quando ele pausa ou acaba */
const waTocando = () => [...document.querySelectorAll('#wa-lista audio')].some(a => !a.paused && !a.ended);
async function lerWhats() {
  if (wa.lendo) return; wa.lendo = true;
  const n = ++wa.seq;
  try {
    const l = await canal.whatsapp(); if (n !== wa.seq) return;
    const lista = Array.isArray(l) ? l : [], j = JSON.stringify([lista, V?.whatsapp || null]); // o total e a origem vêm do estado, não da lista
    if (j !== wa.json || wa.erro) { wa.json = j; wa.lista = lista; wa.erro = ''; if (!wa.mexendo && !waTocando()) pintarWhats(); else wa.pendente = true }
  } catch (e) {
    if (n !== wa.seq) return;
    if (e.status === 401) return tratarErro(e);
    const era = wa.erro; wa.erro = msgErro(e); if (!wa.lista) { if (wa.erro !== era) pintarWhats() } else if (!era) avisar(wa.erro, { erro: true }); // o aviso dura 4 s uma vez, não a cada leitura. A lista de erro só repinta se o motivo mudou (o botão não pode sumir debaixo do dedo)
  } finally { wa.lendo = false }
}
/* Com a lista de pé a folha acompanha a cada 1 s (o Mac já empurra a mensagem nova na hora, o resto era a espera daqui). Em erro vale só a leitura de 4 s abaixo */
setInterval(() => { if (folhaAberta?.id === 'f-whats' && wa.lista && !wa.erro && !document.hidden && V && !V.carregando && !semAcesso && !offline) lerWhats() }, 1000);
$('#wa-lista').addEventListener('pause', () => { if (wa.pendente && !waTocando()) { wa.pendente = false; pintarWhats() } }, true);
$('#wa-lista').addEventListener('ended', () => { if (wa.pendente && !waTocando()) { wa.pendente = false; pintarWhats() } }, true);
/* Pelo WhatsApp Web o Mac só enxerga o total (o título da aba), sem lista por conversa: a folha diz isso em vez de inventar linhas */
function pintarWhatsWeb() {
  const w = V.whatsapp, n = w.total || 0, aberto = w.aberto !== false;
  $('#wa-titulo').innerHTML = aberto ? `WhatsApp <small>${n} ${n === 1 ? 'não lida' : 'não lidas'}</small>` : 'WhatsApp';
  const aviso = aberto ? '' : `<span>O WhatsApp Web não está aberto no navegador${w.navegador ? ` (${esc(w.navegador)})` : ''}. Abra web.whatsapp.com para o Deck contar as não lidas.</span>`;
  $('#wa-lista').setAttribute('aria-busy', 'false');
  manterRolagem($('#wa-lista'), `<div class="vazio-bloco"><strong>${aberto ? (n ? `${n} ${n === 1 ? 'não lida' : 'não lidas'}` : 'Nada novo') : 'WhatsApp Web fechado'}</strong>${aviso}<span>Pelo WhatsApp Web o Deck vê só o total. Para ver cada conversa, use o app do WhatsApp no Mac.</span></div>`);
}
/* Pelo QR (aparelho conectado) a conversa vem inteira, igual ao app. Com a conexão caída o 0 não é medição: a folha diz o que fazer */
function pintarWhatsQrCaido() {
  $('#wa-titulo').textContent = 'WhatsApp';
  $('#wa-lista').setAttribute('aria-busy', 'false');
  manterRolagem($('#wa-lista'), '<div class="vazio-bloco"><strong>WhatsApp por QR sem conexão</strong><span>Abra os Ajustes do Deck no Mac para ler o QR de novo.</span></div>');
}
function pintarWhats() {
  const w = V?.whatsapp;
  /* subindo ou caiu um instante: o Mac reconecta sozinho, não precisa ler QR. A lista de antes continua à vista */
  const reconectando = w?.origem === 'qr' && w.aberto === false && w.reconectando === true;
  const qr = w?.origem === 'qr'; $('#wa-filtro [data-f=arquivadas]').hidden = !qr; if (!qr && wa.filtro === 'arquivadas') wa.filtro = 'todas'; // só o aparelho conectado entrega as arquivadas
  $('#wa-filtro').hidden = w?.origem === 'web' || (w?.origem === 'qr' && w.aberto === false && !reconectando);
  if (w?.origem === 'web') return pintarWhatsWeb();
  if (w?.origem === 'qr' && w.aberto === false && !reconectando) return pintarWhatsQrCaido();
  const todas = wa.lista || [], contam = todas.filter(c => !c.arquivada), total = contam.reduce((s, c) => s + (c.naoLidas || 0), 0);
  /* Arquivadas aparecem só no filtro delas: somem de Todas, Contatos e Grupos */
  const lista = todas.filter(c => wa.filtro === 'arquivadas' ? !!c.arquivada : !c.arquivada && (wa.filtro === 'todas' || (wa.filtro === 'grupos') === !!c.grupo));
  $('#wa-titulo').innerHTML = wa.lista ? `WhatsApp <small><span class="n-total">${total}</span> não lidas em ${contam.length} ${contam.length === 1 ? 'conversa' : 'conversas'}</small>` : 'WhatsApp';
  if (wa.lista) animarTotal(total);
  $$('#wa-filtro button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.f === wa.filtro)));
  $('#wa-lista').setAttribute('aria-busy', String(!wa.lista && !wa.erro));
  const notaReconecta = reconectando ? '<div class="vazio-bloco" style="min-height:96px"><strong>Reconectando ao WhatsApp</strong><span>Volta sozinho em instantes. Não precisa ler o QR de novo.</span></div>' : '';
  if (reconectando && !todas.length) { manterRolagem($('#wa-lista'), notaReconecta); $('#wa-titulo').textContent = 'WhatsApp'; return }
  if (!wa.lista) { const el = $('#wa-lista'); if (wa.erro) el.innerHTML = erroLista(wa.erro); else if (!el.querySelector('.esq-lista')) el.innerHTML = esqueletoWa(); return }
  manterRolagem($('#wa-lista'), notaReconecta + lista.map(c => {
    const msgs = c.mensagens || [], ult = msgs[msgs.length - 1] || { de: '', texto: '' }, aberta = wa.aberta === c.id;
    const corpo = aberta ? `<div class="mensagens">${msgs.map(m => balaoWa(c, m)).join('')}<button class="btn secundario pequeno" data-wa-mac="${esc(c.id)}">Responder no Mac</button></div>` : '';
    return `<button class="conversa" data-wa="${esc(c.id)}" aria-expanded="${aberta}">${avatarWa(c)}
      <span style="min-width:0"><div class="nome-c">${esc(nomeWa(c))}${c.grupo ? '<small>grupo</small>' : ''}</div><div class="previa">${ult.de ? esc(ult.de) + ': ' : ''}${esc(ult.texto)}</div></span>
      <span class="lado"><span>${esc(horaConversa(c.ultima))}</span><span class="qtd">${esc(c.naoLidas)}</span></span></button>${corpo}`;
  }).join('') || `<div class="vazio-bloco" style="min-height:120px"><strong>Nada aqui</strong><span>${wa.filtro === 'arquivadas' ? 'Nenhuma arquivada com mensagem nova.' : 'Sem não lidas nesse filtro.'}</span></div>`);
  carregarMidiasWa();
}
/* O total de não lidas conta até o valor novo (tatile, movimento 9). Sem movimento reduzido, 600 ms com ease-out cúbico */
function animarTotal(para) {
  const antes = wa.total; wa.total = para;
  const el = $('#wa-titulo .n-total'); if (!el || antes === null || antes === para || reduzido()) return;
  const dur = msCss('--mov-contar') || 600, t0 = performance.now(), id = ++animarTotal.id;
  const passo = t => { if (id !== animarTotal.id || !el.isConnected) return; const k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 3); el.textContent = Math.round(antes + (para - antes) * e); if (k < 1) requestAnimationFrame(passo) };
  requestAnimationFrame(passo);
}
animarTotal.id = 0;
/* conversa sem nome nunca vira linha em branco: o Mac já manda o nome, o número ou "Contato", e aqui é a última guarda */
const nomeWa = c => String(c.nome || '').trim() || (c.grupo ? 'Grupo' : 'Contato');
const temLetra = n => /\p{L}/u.test(n);
/* foto de perfil: vem do Mac em base64 sob demanda e fica guardada (a mesma foto não é pedida de novo) */
const waBlobs = new Map();
function guardarBlob(chave, url) { waBlobs.set(chave, url); if (waBlobs.size > 60) { const [k, v] = waBlobs.entries().next().value; if (v) URL.revokeObjectURL(v); waBlobs.delete(k) } return url }
function blobDoMac(r) { const bin = atob(r.dados), u8 = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i); return URL.createObjectURL(new Blob([u8], { type: r.tipo })) }
function avatarWa(c) {
  const url = c.foto ? waBlobs.get('foto:' + c.foto) : null;
  const dentro = url ? `<img alt="" src="${esc(url)}">` : c.grupo ? SVG.grupo : temLetra(nomeWa(c)) && nomeWa(c) !== 'Contato' ? esc(iniciais(nomeWa(c))) : SVG.pessoa; // sem nome (ou só número): o avatar de pessoa, não iniciais inventadas
  return `<span class="avatar"${c.foto && !url ? ` data-foto="${esc(c.foto)}"` : ''}>${dentro}</span>`;
}
/* horário em que a mensagem chegou: hoje só a hora, antes dela o dia e a hora */
function horaMsg(iso) {
  const d = new Date(iso); if (isNaN(d)) return '';
  return mesmoDia(d, new Date(V?.ref || Date.now())) ? hhmm(d) : `${pad2(d.getDate())}/${pad2(d.getMonth() + 1)} ${hhmm(d)}`;
}
function balaoWa(c, m) {
  const quem = m.de ? `<small>${esc(m.de)}</small>` : '', hora = `<time class="hora-msg">${esc(horaMsg(m.hora))}</time>`, chave = esc(c.id) + '|' + esc(m.id || '');
  if (m.unica) return `<p class="unica-msg">${quem}<span class="unica">${m.tipo === 'audio' ? SVG.audio : SVG.foto}<span>${esc(m.texto)}</span>${SVG.unica}</span>${hora}</p>`;
  if (m.midia && m.tipo === 'foto') {
    const url = waBlobs.get('midia:' + c.id + '|' + m.id), legenda = m.texto && m.texto !== 'Foto' ? `<span>${esc(m.texto)}</span>` : '';
    return `<p class="midia-msg">${quem}<span class="foto-msg" data-foto-msg="${chave}">${url ? `<img alt="Foto" src="${esc(url)}">` : '<span class="foto-espera" aria-busy="true">Carregando a foto...</span>'}</span>${legenda}${hora}</p>`;
  }
  if (m.midia && m.tipo === 'audio') {
    const url = waBlobs.get('midia:' + c.id + '|' + m.id);
    return `<p class="midia-msg">${quem}<span class="audio-msg" data-audio-msg="${chave}">${url ? `<audio controls preload="metadata" src="${esc(url)}"></audio>` : `<button class="btn secundario pequeno" data-ouvir="${chave}">${SVG.play}Ouvir o áudio</button>`}</span>${hora}</p>`;
  }
  return `<p>${quem}${esc(m.texto)}${hora}</p>`;
}
const tipoMsg = (chat, id) => { const c = (wa.lista || []).find(x => x.id === chat); return { c, m: c?.mensagens?.find(x => x.id === id) } };
const baixando = new Set();
async function baixarMidiaWa(chat, id) {
  const chave = 'midia:' + chat + '|' + id;
  if (waBlobs.has(chave)) return waBlobs.get(chave);
  if (baixando.has(chave)) return null;
  baixando.add(chave);
  try { return guardarBlob(chave, blobDoMac(await canal.whatsappMidia(chat, id))) } finally { baixando.delete(chave) }
}
let lendoFotos = 0;
/* depois de pintar: as fotos de perfil que faltam e as fotos da conversa aberta (uma por vez, para não entupir o cabo nem o Bluetooth) */
async function carregarMidiasWa() {
  for (const el of $$('#wa-lista [data-foto]')) {
    const arq = el.dataset.foto; if (waBlobs.has('foto:' + arq) || baixando.has('foto:' + arq)) continue;
    baixando.add('foto:' + arq);
    canal.whatsappFoto(arq).then(r => guardarBlob('foto:' + arq, blobDoMac(r)), () => guardarBlob('foto:' + arq, null))
      .then(url => { if (url) $$('#wa-lista [data-foto]').forEach(a => { if (a.dataset.foto === arq) { a.innerHTML = `<img alt="" src="${esc(url)}">`; a.removeAttribute('data-foto') } }) })
      .finally(() => baixando.delete('foto:' + arq));
  }
  if (lendoFotos) return; lendoFotos = 1;
  try {
    for (const el of $$('#wa-lista [data-foto-msg]')) {
      const [chat, id] = el.dataset.fotoMsg.split('|'); if (!el.querySelector('.foto-espera')) continue;
      try {
        const url = await baixarMidiaWa(chat, id); if (!url) continue;
        $$('#wa-lista [data-foto-msg]').forEach(a => { if (a.dataset.fotoMsg === el.dataset.fotoMsg) a.innerHTML = `<img alt="Foto" src="${esc(url)}">` });
      } catch (e) { $$('#wa-lista [data-foto-msg]').forEach(a => { if (a.dataset.fotoMsg === el.dataset.fotoMsg) a.innerHTML = `<span class="foto-espera">${esc(e.message || 'Não deu para abrir a foto.')}</span>` }) }
    }
  } finally { lendoFotos = 0 }
}
async function ouvirAudioWa(botao) {
  const [chat, id] = botao.dataset.ouvir.split('|'); if (botao.disabled) return;
  botao.disabled = true; botao.classList.add('carregando');
  try {
    const url = await baixarMidiaWa(chat, id);
    const alvo = botao.closest('.audio-msg'); if (!url || !alvo) return;
    alvo.innerHTML = `<audio controls preload="metadata" src="${esc(url)}"></audio>`;
    const a = alvo.querySelector('audio');
    a.addEventListener('error', () => { alvo.innerHTML = '<span class="foto-espera">Este aparelho não toca esse áudio.</span>' }, { once: true });
    a.play().catch(() => {}); // se o iPhone barrar o início sozinho, é só tocar no play
  } catch (e) { botao.disabled = false; botao.classList.remove('carregando'); avisar(e.message || 'Não deu para baixar o áudio.', { erro: true }) }
}
/* "Responder no Mac" abre a conversa do contato no WhatsApp Web (grupo não tem link direto: o Mac abre o Web e avisa). Mac antigo cai no jeito de antes */
async function responderNoMac(id) {
  if (wa.abrindo) return; wa.abrindo = true;
  try { const r = await canal.abrirConversa(id); avisar(r?.aviso || 'Abrindo a conversa no WhatsApp Web') }
  catch (e) { if (e.status === 404) abrirNoMac('whatsapp', 'Abrindo o WhatsApp no Mac'); else if (e.status === 401) tratarErro(e); else avisar(msgErro(e), { erro: true }) }
  finally { wa.abrindo = false }
}
$('#wa-filtro').addEventListener('click', e => { const b = e.target.closest('button'); if (b) { wa.filtro = b.dataset.f; wa.aberta = null; pintarWhats() } });
$('#wa-lista').addEventListener('click', e => {
  if (e.target.closest('[data-tentar]')) { wa.erro = ''; pintarWhats(); return lerWhats() }
  const resp = e.target.closest('[data-wa-mac]'); if (resp) return responderNoMac(resp.dataset.waMac);
  const ou = e.target.closest('[data-ouvir]'); if (ou) return ouvirAudioWa(ou);
  const c = e.target.closest('[data-wa]'); if (c) alternarConversa(c.dataset.wa);
});
$('#wa-abrir').onclick = () => abrirNoMac('whatsapp', 'Abrindo o WhatsApp no Mac');
/* abrir e fechar a conversa com movimento: a que estava aberta recolhe, a nova se expande e os balões entram em
   cascata. Tempos e curvas vêm dos tokens (com movimento reduzido eles viram 0) */
async function alternarConversa(id) {
  if (wa.mexendo) return; wa.mexendo = true;
  try {
    const velha = $('#wa-lista .mensagens');
    if (velha) { velha.style.overflow = 'hidden';
      await velha.animate([{ height: velha.offsetHeight + 'px', opacity: 1 }, { height: '0px', opacity: 0, marginBottom: '0px' }], { duration: msCss('--mov-sai-padrao'), easing: tokCss('--curva-sai'), fill: 'forwards' }).finished }
    wa.aberta = wa.aberta === id ? null : id; pintarWhats();
    const nova = $('#wa-lista .mensagens');
    if (nova) {
      const h = nova.offsetHeight, mb = getComputedStyle(nova).marginBottom; nova.style.overflow = 'hidden';
      nova.animate([{ height: '0px', opacity: 0, marginBottom: '0px' }, { height: h + 'px', opacity: 1, marginBottom: mb }], { duration: msCss('--mov-padrao'), easing: tokCss('--curva-entra') }).finished.then(() => nova.style.overflow = '');
      [...nova.children].forEach((f, i) => f.animate([{ opacity: 0, transform: 'translateY(-8px)' }, { opacity: 1, transform: 'none' }], { duration: msCss('--mov-padrao'), delay: i * msCss('--mov-cascata'), easing: tokCss('--curva-entra'), fill: 'backwards' }));
      nova.previousElementSibling.scrollIntoView({ block: 'nearest', behavior: reduzido() ? 'auto' : 'smooth' });
    }
  } finally { wa.mexendo = false }
}

/* ---------- Sessões ---------- */
/* "Dispensar" esconde a sessão até ela mudar (outra pergunta, ou voltou a esperar). Fica guardado no aparelho */
const CHAVE_DISPENSADAS = 'deck-dispensadas-v1', VALIDADE_DISPENSA = 30 * 864e5;
const assinatura = s => `${s.desde}|${s.pergunta}`;
function lerDispensadas() { try { const d = JSON.parse(lerGuardado(CHAVE_DISPENSADAS)); return d && typeof d === 'object' && !Array.isArray(d) ? d : {} } catch { return {} } }
const dispensada = s => lerDispensadas()[s.id]?.a === assinatura(s);
function dispensar(s) {
  const d = lerDispensadas(), agora = Date.now();
  for (const k of Object.keys(d)) if (!(agora - d[k]?.t < VALIDADE_DISPENSA)) delete d[k]; // some o que já passou de um mês
  d[s.id] = { a: assinatura(s), t: agora };
  guardar(CHAVE_DISPENSADAS, JSON.stringify(d));
}
/* Tela de sessões: um cartão por sessão (nome, projeto, há quanto tempo, começo da pergunta). Tocar num cartão
   abre a sessão com a pergunta inteira, com Dispensar e Voltar. Ainda não há link para abrir a sessão no Claude do iPhone
   (SPEC 13, item 4), por isso quem responde faz isso na própria sessão. */
const se = { lista: [], aberta: null, y: 0, seq: 0, tempos: '' };
const temposSessoes = l => l.map(s => haQuanto(s.desde, V.ref).texto).join('|'); // o "há X min" anda sozinho com o relógio do Mac
const ordenarSessoes = l => [...l].sort((a, b) => Date.parse(b.desde) - Date.parse(a.desde));
function abrirSessoes() { se.aberta = null; se.lista = V.sessoes; pintarSessoes(); $('#se-lista').scrollTop = 0; abrirFolha('#f-sessoes'); lerSessoes() }
async function lerSessoes() {
  const n = ++se.seq;
  try {
    const l = await canal.sessoes(); if (n !== se.seq) return;
    const nova = ordenarSessoes((Array.isArray(l) ? l : []).filter(s => !dispensada(s)));
    if (JSON.stringify(nova) !== JSON.stringify(se.lista) || temposSessoes(nova) !== se.tempos) { se.lista = nova; pintarSessoes() }
  } catch (e) { if (n === se.seq && e.status === 401) tratarErro(e) } // sem a lista completa, fica a do estado
}
const cartaoSessao = s => `<button class="cartao-sessao ${haQuanto(s.desde, V.ref).velha ? 'velha' : ''}" data-sessao="${esc(s.id)}"><b>${esc(s.nome)}</b><small>${esc(s.projeto)}, há ${haQuanto(s.desde, V.ref).texto}</small><p>${esc(s.pergunta)}</p></button>`;
/* O contexto vem como a sessão escreveu (markdown solto). Aqui vira texto de leitura: sem #, ** e crases, tabela em linhas, parágrafos */
function limparContexto(t) {
  let dentro = false;
  const linhas = String(t || '').replace(/\r/g, '').split('\n').flatMap(l => {
    if (/^\s*(```|~~~)/.test(l)) { dentro = !dentro; return [] } // a cerca some, o comando fica como está
    if (dentro) return [l];
    if (/^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(l)) return [];
    return [(/^\s*\|.*\|\s*$/.test(l) ? l.trim().slice(1, -1).split('|').map(c => c.trim()).filter(Boolean).join(' · ') : l)
      .replace(/^#{1,6}\s+/, '').replace(/^\s*>\s?/, '').replace(/!?\[([^\]\n]+)\]\([^)\s]+\)/g, '$1')
      .replace(/\*\*([^*\n]+)\*\*/g, '$1').replace(/__([^_\n]+)__/g, '$1').replace(/(^|[\s(])\*([^*\s][^*\n]*)\*/g, '$1$2').replace(/`([^`\n]+)`/g, '$1')];
  });
  return linhas.join('\n').replace(/\n{3,}/g, '\n\n').trim();
}
const paragrafos = t => limparContexto(t).split(/\n\s*\n/).filter(Boolean).map(p => `<p>${esc(p.trim())}</p>`).join('');
/* A sessão aberta, de cima para baixo: o que ela pede (em destaque), a resposta que ela mesma sugere, Abrir no Mac, e o contexto. */
const detalheSessao = s => `<article class="detalhe-sessao">
  <section class="pede"><span class="rotulo">Pede a sua resposta</span><p class="pergunta">${esc(s.pedido || s.pergunta)}</p>${s.sugestao ? `<div class="sugestao"><span class="rotulo">Resposta sugerida pela sessão</span><p>${esc(s.sugestao)}</p></div>` : ''}</section>
  <button class="btn primario" data-sessao-mac>Abrir no Mac</button>
  ${s.contexto ? `<section class="contexto"><span class="rotulo">Contexto</span><div class="texto-contexto">${paragrafos(s.contexto)}</div></section>` : ''}
  <p class="nota-sessao">Responda direto na sessão, no Claude.</p></article>`;
function pintarSessoes() {
  se.tempos = temposSessoes(se.lista);
  const s0 = se.aberta && se.lista.find(x => x.id === se.aberta);
  if (se.aberta && !s0) { se.aberta = null; avisar('Essa sessão já foi respondida') }
  const s = se.aberta ? s0 : null; // sumiu da lista (respondida no Mac): volta aos cartões
  const n = se.lista.length;
  $('#se-titulo').innerHTML = s ? `${esc(s.nome)} <small>${esc(s.projeto)}, há ${haQuanto(s.desde, V.ref).texto}</small>` : `Sessões esperando <small>${n} ${n === 1 ? 'sessão' : 'sessões'}</small>`;
  $('#f-sessoes').classList.toggle('detalhe', !!s); $('#se-rodape').hidden = !s;
  manterRolagem($('#se-lista'), s ? detalheSessao(s)
    : n ? `<div class="grade-sessoes">${se.lista.map(cartaoSessao).join('')}</div>`
    : '<div class="vazio-bloco" style="min-height:160px"><strong>Ninguém esperando</strong><span>Quando uma sessão do Claude pedir resposta, ela aparece aqui.</span></div>');
}
function voltarSessoes() { se.aberta = null; pintarSessoes(); $('#se-lista').scrollTop = se.y }
/* "Abrir no Mac": o Mac acha o terminal onde a sessão está e o traz para a frente. Sem terminal, abre o Terminal na pasta do projeto */
let abrindoSessao = false;
async function abrirSessaoNoMac() {
  if (abrindoSessao || !se.aberta) return; abrindoSessao = true;
  avisar('Abrindo a sessão no Mac');
  try { const r = await canal.abrirSessao(se.aberta); if (r?.como === 'pasta') avisar('Não achei o terminal da sessão. Abri o Terminal na pasta do projeto') }
  catch (e) { tratarErro(e) } finally { abrindoSessao = false }
}
$('#se-lista').addEventListener('click', e => {
  if (e.target.closest('[data-sessao-mac]')) return abrirSessaoNoMac();
  const c = e.target.closest('[data-sessao]'); if (!c) return;
  se.y = $('#se-lista').scrollTop; se.aberta = c.dataset.sessao; pintarSessoes(); $('#se-lista').scrollTop = 0;
});
$('#se-rodape').addEventListener('click', e => {
  if (e.target.closest('[data-voltar]')) return voltarSessoes();
  if (!e.target.closest('[data-dispensar]')) return;
  const s = se.lista.find(x => x.id === se.aberta); if (!s) return;
  dispensar(s); se.lista = se.lista.filter(x => x.id !== s.id); voltarSessoes();
  V = vistaReal(); atualizar(); // o bloco da tela principal também deixa de mostrar
  avisar('Dispensada até ela mudar de novo');
});

/* ---------- Agenda ---------- */
const ag = { mes: new Date(), dia: new Date(), mesEv: null, lista: null, aberto: null, erro: '', seqMes: 0, seqLista: 0 };
// só repinta se a resposta é diferente da anterior (a leitura de 4 s não mexe na tela à toa)
const vistoAg = {};
function mudou(chave, dados) { const j = JSON.stringify(dados); const m = vistoAg[chave] !== j; vistoAg[chave] = j; return m }
const semPermissao = () => V.agenda?.permissao === false;
/* Link de reunião que o Mac achou no evento (Meet, Zoom ou Teams). Só https desses serviços vira botão */
function reuniaoDe(e) {
  let u; try { u = new URL(e.link) } catch { return null }
  const h = u.hostname.toLowerCase();
  const nome = h === 'meet.google.com' ? 'Google Meet' : h === 'zoom.us' || h.endsWith('.zoom.us') ? 'Zoom' : h === 'teams.microsoft.com' || h === 'teams.live.com' ? 'Teams' : '';
  return u.protocol === 'https:' && nome ? { url: u.href, nome } : null;
}
let entrandoNaReuniao = false;
async function entrarNaReuniao(url) {
  if (entrandoNaReuniao) return; entrandoNaReuniao = true;
  avisar('Abrindo a reunião no Mac');
  try { await canal.entrarNaReuniao(url) } catch (e) { tratarErro(e) } finally { entrandoNaReuniao = false }
}
function nomeDia(d) {
  const hoje = new Date(V?.ref || Date.now()), amanha = new Date(hoje); amanha.setDate(hoje.getDate() + 1);
  const longo = d.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  return mesmoDia(d, hoje) ? 'Hoje, ' + longo.split(', ')[1] : mesmoDia(d, amanha) ? 'Amanhã, ' + longo.split(', ')[1] : longo[0].toUpperCase() + longo.slice(1);
}
function abrirCal() {
  fecharFormNovo();
  const agora = new Date(V.ref); ag.mes = new Date(agora.getFullYear(), agora.getMonth(), 1); ag.dia = new Date(agora); ag.aberto = null; ag.mesEv = null; ag.lista = null; ag.erro = ''; vistoAg.mes = vistoAg.lista = '';
  pintarCal(); abrirFolha('#f-cal'); lerAgenda(true, true);
}
/* o mês pede agenda(1º do mês, dias do mês) e a lista pede agenda(dia tocado, dias que faltam até o fim do mês). A lista nunca
   passa para o mês seguinte: trocar de mês recarrega os dois. Sem permissão, nenhum dos dois é pedido */
const diasAteFimDoMes = d => new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate() - d.getDate() + 1;
async function lerAgenda(mes, lista, silencio) {
  if (semPermissao()) { ag.mesEv = []; ag.lista = []; ag.erro = ''; pintarCal(); return }
  const trabalhos = [];
  if (mes) {
    const n = ++ag.seqMes, ref = ag.mes, dias = new Date(ref.getFullYear(), ref.getMonth() + 1, 0).getDate();
    trabalhos.push(canal.agenda(dataIso(ref), dias).then(l => { if (n === ag.seqMes && ref === ag.mes) return mudou('mes', ag.mesEv = Array.isArray(l) ? l : []) }));
  }
  if (lista) {
    const n = ++ag.seqLista, de = ag.dia;
    trabalhos.push(canal.agenda(dataIso(de), diasAteFimDoMes(de)).then(l => { if (n === ag.seqLista && de === ag.dia) return mudou('lista', ag.lista = Array.isArray(l) ? l : []) }));
  }
  const falhou = !!ag.erro;
  try { const r = await Promise.all(trabalhos); ag.erro = ''; if (falhou || r.some(Boolean)) pintarCal() }
  catch (e) {
    if (e.status === 401) return tratarErro(e);
    ag.erro = msgErro(e); if (silencio && ag.lista) { if (!falhou) avisar(ag.erro, { erro: true }) } else pintarCal();
  }
}
/* O trecho de dias que o evento cobre. Sem fim (Mac antigo) é um dia só. O fim que cai à meia-noite pertence ao dia anterior */
const diaDe = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
function trechoDoEvento(e) {
  const i = new Date(e.inicio); if (isNaN(i)) return null;
  let f = e.fim ? new Date(e.fim) : i; if (isNaN(f) || f < i) f = i; if (f > i) f = new Date(f - 1000);
  return { i, a: diaDe(i), z: diaDe(f) };
}
/* Quantos eventos cada dia do mês tem (dia do mês -> quantidade). O evento de vários dias conta em cada dia do mês que ele cobre */
function diasComEvento(eventos, m) {
  const temEv = new Map(), dias = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate();
  const m1 = new Date(m.getFullYear(), m.getMonth(), 1), m2 = new Date(m.getFullYear(), m.getMonth(), dias);
  for (const e of eventos || []) {
    const t = trechoDoEvento(e); if (!t) continue;
    for (let d = new Date(Math.max(t.a, m1)); d <= Math.min(t.z, m2); d.setDate(d.getDate() + 1)) temEv.set(d.getDate(), (temEv.get(d.getDate()) || 0) + 1);
  }
  return temEv;
}
function pintarCal() {
  const hoje = new Date(V.ref), m = ag.mes;
  $('#ca-puxa').setAttribute('aria-label', 'Novo compromisso em ' + ag.dia.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' }));
  $('#ca-titulo').textContent = m.toLocaleDateString('pt-BR', { month: 'long' }) + (m.getFullYear() !== hoje.getFullYear() ? ' ' + m.getFullYear() : '');
  const dias = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate(), temEv = diasComEvento(ag.mesEv, m);
  let h = '<span></span>'.repeat(new Date(m.getFullYear(), m.getMonth(), 1).getDay());
  for (let n = 1; n <= dias; n++) {
    const d = new Date(m.getFullYear(), m.getMonth(), n), dow = d.getDay(), tem = temEv.get(n) || 0;
    h += `<button class="sb-dia ${dow === 0 || dow === 6 ? 'fds' : ''} ${mesmoDia(d, hoje) ? 'hoje' : ''} ${mesmoDia(d, ag.dia) && !mesmoDia(d, hoje) ? 'sel' : ''} ${tem ? 'tem' : ''}" data-dia="${dataIso(d)}" aria-label="${d.toLocaleDateString('pt-BR')}, ${tem} ${tem === 1 ? 'evento' : 'eventos'}">${n}</button>`;
  }
  $('#ca-grade').innerHTML = h;
  pintarListaCal();
}
function pintarListaCal() {
  const el = $('#ca-lista');
  if (semPermissao()) { el.innerHTML = '<div class="vazio-bloco"><strong>Agenda sem permissão</strong><span>No Mac: Ajustes > Privacidade > Calendários, ligue o Deck.</span></div>'; return }
  if (!ag.lista) { el.setAttribute('aria-busy', String(!ag.erro)); if (ag.erro) el.innerHTML = erroLista(ag.erro, 0); else if (!el.querySelector('.esq-lista')) el.innerHTML = esqueletoCal(); return }
  el.setAttribute('aria-busy', 'false');
  const agora = new Date(V.ref), grupos = new Map();
  const m1 = new Date(ag.mes.getFullYear(), ag.mes.getMonth(), 1), m2 = new Date(ag.mes.getFullYear(), ag.mes.getMonth() + 1, 0), dia0 = diaDe(ag.dia);
  for (const e of ag.lista) {
    const t = trechoDoEvento(e); if (!t) continue;
    // aparece no primeiro dia visível: o do início, ou o dia tocado/1º do mês quando o evento já vinha de antes. Nunca fora do mês na tela
    const primeiro = new Date(Math.max(t.a, dia0, m1)); if (primeiro > Math.min(t.z, m2)) continue;
    const continua = primeiro > t.a;
    if (!continua && mesmoDia(t.i, agora) && !e.diaTodo && t.i < agora) continue; // o que já passou hoje não entra
    const k = dataIso(primeiro); if (!grupos.has(k)) grupos.set(k, { d: primeiro, ev: [] }); grupos.get(k).ev.push({ ...e, d: t.i, continua });
  }
  let h = '';
  for (const [k, g] of [...grupos].sort((a, b) => a[0] < b[0] ? -1 : 1)) {
    g.ev.sort((a, b) => (b.diaTodo - a.diaTodo) || a.d - b.d);
    h += `<section class="grupo-data"><h3>${nomeDia(g.d)}</h3>` + g.ev.map((e, j) => {
      const id = k + '#' + j, aberto = ag.aberto === id, cor = /^#[0-9a-f]{6}$/i.test(e.cor || '') ? e.cor : 'var(--texto-3)';
      const reuniao = reuniaoDe(e), local = reuniao && e.local && e.local.includes(reuniao.url) ? reuniao.nome : e.local; // o endereço da sala não vira o "local" da linha
      return `<button class="ev-linha" data-ev="${esc(id)}" aria-expanded="${aberto}"><time>${e.diaTodo ? 'dia todo' : e.continua ? 'continua' : hhmm(e.d)}</time><i style="background:${cor}"></i><span class="tx"><b>${esc(e.titulo)}</b><span>${esc(e.calendario || '')}${local ? ', ' + esc(local) : ''}</span></span></button>`
        + (aberto ? `<div class="ev-detalhe">${reuniao ? `<button class="btn primario" data-ev-reuniao="${esc(reuniao.url)}" aria-label="Entrar na reunião (${esc(reuniao.nome)}), abre no Mac">Entrar na reunião</button>` : ''}<button class="btn secundario pequeno" data-ev-mac>Abrir no Calendário do Mac</button></div>` : '');
    }).join('') + '</section>';
  }
  manterRolagem(el, (h || '<div class="vazio-bloco"><strong>Nada neste mês a partir deste dia</strong><span>Os eventos do Calendário do Mac aparecem aqui.</span></div>'));
}
/* Troca o mês: o atual sai para um lado, o novo entra pelo outro. Vindo de um arrasto, parte de onde o dedo soltou */
function trocarMes(passo) {
  if (ag.trocando) return; ag.trocando = true;
  const g = $('#ca-mes');
  g.style.translate = ''; g.style.opacity = ''; // sai dali: de onde o dedo soltou, ou da posição normal
  g.classList.add(passo > 0 ? 'saindo-esq' : 'saindo-dir');
  setTimeout(() => {
    ag.mes = new Date(ag.mes.getFullYear(), ag.mes.getMonth() + passo, 1); ag.mesEv = null; vistoAg.mes = '';
    // o dia escolhido acompanha o mês: hoje, se o mês novo é o de hoje, senão o dia 1. A lista recarrega com o mês
    const hoje = new Date(V.ref); ag.dia = ag.mes.getFullYear() === hoje.getFullYear() && ag.mes.getMonth() === hoje.getMonth() ? hoje : new Date(ag.mes);
    ag.lista = null; vistoAg.lista = ''; ag.aberto = null; pintarCal(); lerAgenda(true, true);
    g.style.transition = 'none'; g.classList.remove('saindo-esq', 'saindo-dir'); g.style.translate = `${passo * 24}px 0`; g.style.opacity = 0;
    g.getBoundingClientRect(); // fixa o ponto de partida, sem animar o salto para o lado de onde o mês novo entra
    g.style.transition = '';
    requestAnimationFrame(() => { g.style.translate = ''; g.style.opacity = ''; ag.trocando = false });
  }, msCss('--mov-sai-rapido') + 10);
}
/* ---------- Mês da composição C: o mesmo mês da Agenda, em outro lugar da tela ---------- */
/* O mês que a C mostra é só dela (as setas dela não mexem na Agenda). Sem mexer nas setas por 30 s, ela volta para o mês de agora. */
const mesC = { mes: null, ev: null, seq: 0, lido: 0, volta: 0 };
const MESC_RELER = 30000;
function mesCAtual() { if (!mesC.mes) { const h = new Date(V.ref); mesC.mes = new Date(h.getFullYear(), h.getMonth(), 1) } return mesC.mes }
async function lerMesC(forcar) {
  if (!V || V.comp !== 'c' || (!forcar && mesC.ev && Date.now() - mesC.lido < MESC_RELER)) return;
  const ref = mesCAtual(), n = ++mesC.seq; mesC.lido = Date.now();
  if (semPermissao()) { mesC.ev = []; return }
  try {
    const l = await canal.agenda(dataIso(ref), new Date(ref.getFullYear(), ref.getMonth() + 1, 0).getDate());
    if (n !== mesC.seq) return;
    mesC.ev = Array.isArray(l) ? l : [];
  } catch (e) { if (n === mesC.seq && !mesC.ev) mesC.ev = []; if (e.status === 401) return tratarErro(e) } // sem agenda, o mês aparece sem pontinhos
  if (V.comp === 'c') atualizar();
}
function moverMesC(passo) {
  const m = mesCAtual(); mesC.mes = new Date(m.getFullYear(), m.getMonth() + passo, 1); mesC.ev = null; mesC.volta = Date.now() + 30000;
  atualizar(); lerMesC(true);
}
setInterval(() => {
  if (!V || V.comp !== 'c' || document.hidden) return;
  if (mesC.volta && Date.now() > mesC.volta) { mesC.mes = null; mesC.ev = null; mesC.volta = 0; atualizar() }
  lerMesC();
}, 5000);

$('#ca-ant').innerHTML = SVG.esq; $('#ca-prox').innerHTML = SVG.dir;
$('#ca-ant').onclick = () => trocarMes(-1); $('#ca-prox').onclick = () => trocarMes(1);
$('#ca-grade').addEventListener('click', e => {
  const d = e.target.closest('[data-dia]'); if (!d) return;
  const [a, m, di] = d.dataset.dia.split('-').map(Number); ag.dia = new Date(a, m - 1, di); ag.aberto = null; vistoAg.lista = ''; pintarCal(); lerAgenda(false, true);
});
$('#ca-lista').addEventListener('click', e => {
  if (e.target.closest('[data-tentar]')) { ag.erro = ''; pintarListaCal(); return lerAgenda(true, true) }
  if (e.target.closest('[data-ev-mac]')) return abrirNoMac('calendario', 'Abrindo o Calendário no Mac');
  const reu = e.target.closest('[data-ev-reuniao]'); if (reu) return entrarNaReuniao(reu.dataset.evReuniao);
  const b = e.target.closest('[data-ev]'); if (b) { ag.aberto = ag.aberto === b.dataset.ev ? null : b.dataset.ev; pintarListaCal() }
});
/* Arrastar o mês para os lados: ele segue o dedo e, ao soltar, troca se o dedo foi longe ou rápido, senão volta. */
let toqueCal = null;
const arrastoCal = () => $('#ca-mes');
function soltarMes(e, cancelado) {
  const t = toqueCal; toqueCal = null; if (!t?.seguindo) return;
  const g = arrastoCal(), dx = t.dx, rapido = !cancelado && Math.abs(dx) > 30 && Math.abs(dx) / Math.max(1, e.timeStamp - t.t) > .5;
  g.style.transition = ''; ag.arrastou = true; setTimeout(() => { ag.arrastou = false });
  if (!cancelado && (Math.abs(dx) > Math.max(60, g.offsetWidth / 4) || rapido)) return trocarMes(dx < 0 ? 1 : -1);
  g.style.translate = ''; g.style.opacity = ''; // não foi longe: volta para o lugar
}
arrastoCal().addEventListener('pointerdown', e => { if (!ag.trocando && e.isPrimary) toqueCal = { x: e.clientX, y: e.clientY, t: e.timeStamp, dx: 0, seguindo: false } });
arrastoCal().addEventListener('pointermove', e => {
  if (!toqueCal) return; const dx = e.clientX - toqueCal.x, dy = e.clientY - toqueCal.y, g = arrastoCal();
  if (!toqueCal.seguindo) {
    if (Math.abs(dy) > 10 && Math.abs(dy) >= Math.abs(dx)) { toqueCal = null; return } // é rolagem na vertical: não é do mês
    if (Math.abs(dx) < 10 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    toqueCal.seguindo = true; g.style.transition = 'none'; try { g.setPointerCapture(e.pointerId) } catch {}
  }
  toqueCal.dx = dx; g.style.translate = `${dx}px 0`; g.style.opacity = String(1 - Math.min(Math.abs(dx) / g.offsetWidth, 1) * .7);
});
arrastoCal().addEventListener('pointerup', e => soltarMes(e, false));
arrastoCal().addEventListener('pointercancel', e => soltarMes(e, true));
// o toque que terminou um arrasto não escolhe o dia nem aperta a seta que estava embaixo do dedo
arrastoCal().addEventListener('click', e => { if (ag.arrastou) { e.stopPropagation(); e.preventDefault() } }, true);

/* Deslizar a lista do dia para a esquerda revela o formulário de novo compromisso: a lista segue o dedo e, ao soltar, abre se o
   dedo foi longe ou rápido, senão volta. O puxador na borda (toque) faz o mesmo sem o gesto. Rolar na vertical continua da lista */
let toqueLista = null;
$('#ca-puxa').onclick = () => { if (!fo.aberto) abrirFormNovo() };
function soltarLista(e, cancelado) {
  const t = toqueLista; toqueLista = null; if (!t?.seguindo) return;
  const l = $('#ca-lista'), dx = -t.dx, rapido = !cancelado && dx > 30 && dx / Math.max(1, e.timeStamp - t.t) > .5;
  l.style.transition = ''; ag.arrastou = true; setTimeout(() => { ag.arrastou = false });
  l.style.translate = ''; l.style.opacity = '';
  if (!cancelado && (dx > Math.max(60, l.offsetWidth / 4) || rapido)) abrirFormNovo();
}
for (const el of [$('#ca-lista'), $('#ca-puxa')]) { // o puxador aceita o mesmo gesto
  el.addEventListener('pointerdown', e => { if (e.isPrimary && !fo.aberto) toqueLista = { x: e.clientX, y: e.clientY, t: e.timeStamp, dx: 0, seguindo: false } });
  el.addEventListener('pointermove', e => {
    if (!toqueLista) return; const dx = e.clientX - toqueLista.x, dy = e.clientY - toqueLista.y, l = $('#ca-lista');
    if (!toqueLista.seguindo) {
      if (Math.abs(dy) > 10 && Math.abs(dy) >= Math.abs(dx)) { toqueLista = null; return } // é rolagem na vertical: não é do formulário
      if (dx > -10 || Math.abs(dx) < Math.abs(dy) * 1.5) return; // só para a esquerda
      toqueLista.seguindo = true; l.style.transition = 'none'; try { el.setPointerCapture(e.pointerId) } catch {}
    }
    const d = Math.min(0, dx); toqueLista.dx = d; l.style.translate = `${d}px 0`; l.style.opacity = String(1 - Math.min(-d / l.offsetWidth, 1) * .7);
  });
  el.addEventListener('pointerup', e => soltarLista(e, false));
  el.addEventListener('pointercancel', e => soltarLista(e, true));
  el.addEventListener('click', e => { if (ag.arrastou) { e.stopPropagation(); e.preventDefault() } }, true);
}

/* ---------- Novo compromisso: a parte da direita vira o formulário ---------- */
const fo = { aberto: false, destinos: null, antigo: false, enviando: false, todo: false, querLista: false, espera: null, ate: 0 };
const ALERTAS_HORA = [['', 'Sem alerta'], ['0', 'No horário'], ['5', '5 minutos antes'], ['15', '15 minutos antes'], ['30', '30 minutos antes'], ['60', '1 hora antes'], ['1440', '1 dia antes']];
const ALERTAS_DIA = [['', 'Sem alerta'], ['0', 'No dia, às 9h'], ['1440', '1 dia antes, às 9h'], ['2880', '2 dias antes, às 9h'], ['10080', '1 semana antes, às 9h']];
const chaveDestino = d => d.tipo + ':' + d.id;
const destinoDe = v => { const i = v.indexOf(':'); return i < 0 ? null : { tipo: v.slice(0, i), id: v.slice(i + 1) } };
function mensagemNovo(txt, erro) { const m = $('#nc-msg'); m.textContent = txt || ''; m.classList.toggle('erro', !!erro) }
function pintarAlertas() {
  const sel = $('#nc-alerta'), antes = sel.value, lista = fo.todo ? ALERTAS_DIA : ALERTAS_HORA;
  sel.innerHTML = lista.map(([v, t]) => `<option value="${v}">${t}</option>`).join('');
  sel.value = lista.some(([v]) => v === antes) ? antes : '';
}
function pintarTipoNovo() {
  $('#nc-todo').checked = fo.todo;
  $('#nc-inicio').disabled = $('#nc-fim').disabled = fo.todo;
  pintarAlertas();
}
function pintarPadrao() {
  const v = $('#nc-destino').value, p = fo.destinos?.padrao, caixa = $('#nc-padrao'), ehPadrao = !!p && v === chaveDestino(p);
  caixa.disabled = ehPadrao || !destinoDe(v); if (ehPadrao) caixa.checked = true; else if (caixa.dataset.era === '1') caixa.checked = false;
  caixa.dataset.era = ehPadrao ? '1' : '0';
  $('#nc-padrao-txt').textContent = ehPadrao ? 'É o lugar padrão' : 'Usar como padrão';
}
/* o select de "Onde salvar": calendários e listas do Mac. Lembretes ainda sem acesso aparecem como uma opção que pede o acesso no Mac */
function pintarDestinos() {
  const d = fo.destinos, sel = $('#nc-destino'); if (!d) return;
  const opcao = (x, tipo) => `<option value="${esc(tipo + ':' + x.id)}">${esc(x.nome)}${x.conta ? ' (' + esc(x.conta) + ')' : ''}</option>`;
  let h = '', aviso = '';
  if (d.calendarios.length) h += `<optgroup label="Calendário">${d.calendarios.map(x => opcao(x, 'calendario')).join('')}</optgroup>`;
  if (d.listas.length) h += `<optgroup label="Lembretes">${d.listas.map(x => opcao(x, 'lembretes')).join('')}</optgroup>`;
  const esperando = esperandoLembretes(d);
  if (d.permissaoLembretes === 'pedir' && !esperando) h += '<optgroup label="Lembretes"><option value="pedir">Liberar os Lembretes no Mac</option></optgroup>';
  if (esperando) aviso = 'Aceite o pedido de acesso aos Lembretes na tela do Mac.';
  if (d.permissaoCalendario !== 'liberado' && !d.calendarios.length) aviso = d.permissaoCalendario === 'recusado' ? 'O Deck está sem acesso ao Calendário. No Mac: Ajustes do Sistema > Privacidade.' : 'Aceite o pedido de acesso ao Calendário na tela do Mac.';
  const antes = sel.value;
  sel.innerHTML = h || '<option value="">Nenhum lugar disponível</option>';
  const todos = [...sel.options].map(o => o.value);
  const primeiraLista = fo.querLista && d.listas[0] ? 'lembretes:' + d.listas[0].id : '';
  const escolha = [primeiraLista, antes, d.padrao ? chaveDestino(d.padrao) : '', d.calendarios[0] ? 'calendario:' + d.calendarios[0].id : ''].find(v => v && todos.includes(v));
  if (primeiraLista && escolha === primeiraLista) fo.querLista = false;
  sel.value = escolha ?? sel.options[0].value;
  pintarPadrao();
  if (aviso) mensagemNovo(aviso); else if (!$('#nc-msg').classList.contains('erro')) mensagemNovo('');
  if (esperando || d.permissaoCalendario === 'pedindo') esperarAcesso();
}
/* o Mac só devolve "pedindo" na chamada que abriu a janela. Nas seguintes ele ainda diz "pedir" até a pessoa responder, então depois de pedir "pedir" também é "esperando" */
function esperandoLembretes(d) { return d.permissaoLembretes === 'pedindo' || (d.permissaoLembretes === 'pedir' && Date.now() < fo.pediuAte) }
/* depois de pedir o acesso, olha de 2 em 2 s até a pessoa responder no Mac (no máximo 1 minuto) */
function esperarAcesso() {
  if (fo.espera) return;
  fo.ate = Date.now() + 60000;
  fo.espera = setInterval(() => {
    if (!fo.aberto || Date.now() > fo.ate) { clearInterval(fo.espera); fo.espera = null; if (fo.aberto) pintarDestinos(); return }
    carregarDestinos(false);
  }, 2000);
}
async function carregarDestinos(pedirAcesso) {
  try {
    const d = await canal.agendaDestinos(pedirAcesso);
    if (!fo.aberto) return;
    fo.antigo = false; fo.destinos = d;
    if (fo.espera && !esperandoLembretes(d) && d.permissaoCalendario !== 'pedindo') { clearInterval(fo.espera); fo.espera = null }
    pintarDestinos();
  } catch (e) {
    if (!fo.aberto) return;
    if (e.status === 401) return tratarErro(e);
    if (e.status === 404) { fo.antigo = true; mensagemNovo('Este Mac tem uma versão do Deck sem essa função. Atualize o Deck no Mac para criar compromissos.', true); return }
    mensagemNovo(msgErro(e), true);
  }
}
function abrirFormNovo() {
  fo.aberto = true; fo.pediuAte = 0; fo.destinos = null; fo.antigo = false; fo.enviando = false; fo.todo = false; fo.querLista = false;
  const hoje = mesmoDia(ag.dia, new Date(V.ref)), h = hoje ? Math.min(new Date(V.ref).getHours() + 1, 23) : 9;
  $('#nc-titulo').value = ''; $('#nc-dia').value = dataIso(ag.dia);
  $('#nc-inicio').value = pad2(h) + ':00'; $('#nc-fim').value = h < 23 ? pad2(h + 1) + ':00' : '23:59';
  $('#nc-destino').innerHTML = '<option value="">Lendo o Mac...</option>';
  $('#nc-padrao').checked = false; $('#nc-padrao').dataset.era = '0'; $('#nc-padrao').disabled = true;
  $('#nc-salvar').disabled = false; $('#nc-salvar').textContent = 'Salvar'; mensagemNovo('');
  pintarTipoNovo();
  $('#ca-lista').hidden = true; $('#ca-form').hidden = false; $('#ca-puxa').hidden = true;
  animarEntrada($('#ca-form'), 'entra-direita');
  carregarDestinos(false);
}
function fecharFormNovo() {
  fo.aberto = false; clearInterval(fo.espera); fo.espera = null;
  if ($('#ca-form').contains(document.activeElement)) document.activeElement.blur();
  $('#ca-form').hidden = true; $('#ca-lista').hidden = false; $('#ca-puxa').hidden = false;
  animarEntrada($('#ca-lista'), 'entra-esquerda');
}
// reinicia a animação de entrada (a classe sai quando acaba, para o gesto de arrastar poder usar translate depois)
function animarEntrada(el, classe) { el.classList.remove(classe); void el.offsetWidth; el.classList.add(classe); el.addEventListener('animationend', () => el.classList.remove(classe), { once: true }) }
async function salvarCompromisso() {
  if (fo.enviando) return;
  const titulo = $('#nc-titulo').value.trim(), dia = $('#nc-dia').value, inicio = $('#nc-inicio').value, fim = $('#nc-fim').value, destino = destinoDe($('#nc-destino').value);
  if (fo.antigo) return mensagemNovo('Atualize o Deck no Mac para criar compromissos.', true);
  if (!titulo) return mensagemNovo('Dê um título ao compromisso.', true);
  if (!dia) return mensagemNovo('Escolha o dia.', true);
  if (!fo.todo && !inicio) return mensagemNovo('Escolha a hora de início.', true);
  if (!fo.todo && fim && fim <= inicio) return mensagemNovo('O fim precisa ser depois do início.', true);
  if (!destino) return mensagemNovo($('#nc-destino').value === 'pedir' ? 'Libere os Lembretes antes de salvar neles.' : 'Escolha onde salvar.', true);
  const corpo = { titulo, dia, diaTodo: fo.todo, destino, padrao: $('#nc-padrao').checked && !$('#nc-padrao').disabled };
  if (!fo.todo) { corpo.inicio = inicio; if (fim) corpo.fim = fim }
  if ($('#nc-alerta').value !== '') corpo.alertaMin = Number($('#nc-alerta').value);
  fo.enviando = true; $('#nc-salvar').disabled = true; $('#nc-salvar').textContent = 'Salvando...'; mensagemNovo('');
  try {
    await canal.criarCompromisso(corpo);
    const [a, m, di] = dia.split('-').map(Number), nome = $('#nc-destino').selectedOptions[0]?.textContent || '';
    fecharFormNovo();
    ag.dia = new Date(a, m - 1, di); ag.mes = new Date(a, m - 1, 1); ag.aberto = null; ag.mesEv = null; ag.lista = null; vistoAg.mes = vistoAg.lista = '';
    pintarCal(); lerAgenda(true, true);
    avisar(destino.tipo === 'lembretes' ? `Lembrete criado em ${nome}. Ele aparece no app Lembretes.` : 'Compromisso criado no Calendário do Mac');
  } catch (e) {
    if (e.status === 401) return tratarErro(e);
    mensagemNovo(e.rede ? 'Sem conexão com o Mac. Confira o Wi-Fi e tente de novo.' : msgErro(e), true);
    if (e.status === 409) carregarDestinos(false);
  } finally { fo.enviando = false; $('#nc-salvar').disabled = false; $('#nc-salvar').textContent = 'Salvar' }
}
$('#ca-form').addEventListener('submit', e => { e.preventDefault(); salvarCompromisso() });
$('#ca-form').addEventListener('click', e => {
  if (e.target.closest('[data-nc-cancelar]')) return fecharFormNovo();
});
$('#nc-todo').addEventListener('change', e => { fo.todo = e.target.checked; pintarTipoNovo() });
$('#nc-destino').addEventListener('change', e => {
  mensagemNovo('');
  if (e.target.value === 'pedir') { fo.querLista = true; fo.pediuAte = Date.now() + 60000; mensagemNovo('Aceite o pedido de acesso na tela do Mac.'); carregarDestinos(true); return }
  pintarPadrao();
});

/* ---------- folha aberta: a lista acompanha o Mac a cada 4 s ---------- */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline) return;
  const id = folhaAberta?.id;
  if (id === 'f-whats') lerWhats(); else if (id === 'f-sessoes') lerSessoes(); else if (id === 'f-cal') lerAgenda(true, true, true);;
}, 4000);
