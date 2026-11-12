/* Painéis de tela inteira (SPEC, seção 5): WhatsApp, Agenda e Sessões. Mesmas folhas do protótipo,
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
  if (qual === 'whatsapp') abrirWhats(); else if (qual === 'calendario') abrirCal(); else if (qual === 'sessoes') abrirSessoes(); else if (qual === 'controles') abrirControles();
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
const wa = { lista: null, json: '', filtro: 'todas', aberta: null, erro: '', mexendo: false, seq: 0 };
function horaConversa(iso) {
  const d = new Date(iso); if (isNaN(d)) return '';
  const dias = diasEntre(d, V?.ref || Date.now());
  return dias <= 0 ? hhmm(d) : dias === 1 ? 'ontem' : dias < 7 ? d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '') : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}
function abrirWhats() { wa.aberta = null; wa.filtro = 'todas'; wa.lista = null; wa.json = ''; wa.erro = ''; pintarWhats(); abrirFolha('#f-whats'); lerWhats() }
async function lerWhats() {
  const n = ++wa.seq;
  try {
    const l = await canal.whatsapp(); if (n !== wa.seq) return;
    const lista = Array.isArray(l) ? l : [], j = JSON.stringify([lista, V?.whatsapp || null]); // o total e a origem vêm do estado, não da lista
    if (j !== wa.json || wa.erro) { wa.json = j; wa.lista = lista; wa.erro = ''; if (!wa.mexendo) pintarWhats() }
  } catch (e) {
    if (n !== wa.seq) return;
    if (e.status === 401) return tratarErro(e);
    const era = wa.erro; wa.erro = msgErro(e); if (!wa.lista) pintarWhats(); else if (!era) avisar(wa.erro, { erro: true }); // o aviso dura 4 s uma vez, não a cada leitura
  }
}
/* Pelo WhatsApp Web o Mac só enxerga o total (o título da aba), sem lista por conversa: a folha diz isso em vez de inventar linhas */
function pintarWhatsWeb() {
  const w = V.whatsapp, n = w.total || 0, aberto = w.aberto !== false;
  $('#wa-titulo').innerHTML = aberto ? `WhatsApp <small>${n} ${n === 1 ? 'não lida' : 'não lidas'}</small>` : 'WhatsApp';
  const aviso = aberto ? '' : `<span>O WhatsApp Web não está aberto no navegador${w.navegador ? ` (${esc(w.navegador)})` : ''}. Abra web.whatsapp.com para o Deck contar as não lidas.</span>`;
  $('#wa-lista').setAttribute('aria-busy', 'false');
  manterRolagem($('#wa-lista'), `<div class="vazio-bloco"><strong>${aberto ? (n ? `${n} ${n === 1 ? 'não lida' : 'não lidas'}` : 'Nada novo') : 'WhatsApp Web fechado'}</strong>${aviso}<span>Pelo WhatsApp Web o Deck vê só o total. Para ver cada conversa, use o app do WhatsApp no Mac.</span></div>`);
}
function pintarWhats() {
  $('#wa-filtro').hidden = V?.whatsapp?.origem === 'web';
  if (V?.whatsapp?.origem === 'web') return pintarWhatsWeb();
  const todas = wa.lista || [], total = todas.reduce((s, c) => s + (c.naoLidas || 0), 0);
  const lista = todas.filter(c => wa.filtro === 'todas' || (wa.filtro === 'grupos') === !!c.grupo);
  $('#wa-titulo').innerHTML = wa.lista ? `WhatsApp <small>${total} não lidas em ${todas.length} ${todas.length === 1 ? 'conversa' : 'conversas'}</small>` : 'WhatsApp';
  $$('#wa-filtro button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.f === wa.filtro)));
  $('#wa-lista').setAttribute('aria-busy', String(!wa.lista && !wa.erro));
  if (!wa.lista) { const el = $('#wa-lista'); if (wa.erro) el.innerHTML = erroLista(wa.erro); else if (!el.querySelector('.esq-lista')) el.innerHTML = esqueletoWa(); return }
  manterRolagem($('#wa-lista'), lista.map(c => {
    const msgs = c.mensagens || [], ult = msgs[msgs.length - 1] || { de: '', texto: '' }, aberta = wa.aberta === c.id;
    const corpo = aberta ? `<div class="mensagens">${msgs.map(m => `<p>${m.de ? `<small>${esc(m.de)}</small>` : ''}${esc(m.texto)}</p>`).join('')}<button class="btn secundario pequeno" data-wa-mac="${esc(c.id)}">Responder no Mac</button></div>` : '';
    return `<button class="conversa" data-wa="${esc(c.id)}" aria-expanded="${aberta}"><span class="avatar">${c.grupo ? SVG.grupo : esc(iniciais(c.nome))}</span>
      <span style="min-width:0"><div class="nome-c">${esc(c.nome)}${c.grupo ? '<small>grupo</small>' : ''}</div><div class="previa">${ult.de ? esc(ult.de) + ': ' : ''}${esc(ult.texto)}</div></span>
      <span class="lado"><span>${esc(horaConversa(c.ultima))}</span><span class="qtd">${esc(c.naoLidas)}</span></span></button>${corpo}`;
  }).join('') || '<div class="vazio-bloco" style="min-height:120px"><strong>Nada aqui</strong><span>Sem não lidas nesse filtro.</span></div>');
}
$('#wa-filtro').addEventListener('click', e => { const b = e.target.closest('button'); if (b) { wa.filtro = b.dataset.f; wa.aberta = null; pintarWhats() } });
$('#wa-lista').addEventListener('click', e => {
  if (e.target.closest('[data-tentar]')) { wa.erro = ''; pintarWhats(); return lerWhats() }
  if (e.target.closest('[data-wa-mac]')) return abrirNoMac('whatsapp', 'Abrindo o WhatsApp no Mac');
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
function pintarCal() {
  const hoje = new Date(V.ref), m = ag.mes;
  $('#ca-titulo').textContent = m.toLocaleDateString('pt-BR', { month: 'long' }) + (m.getFullYear() !== hoje.getFullYear() ? ' ' + m.getFullYear() : '');
  const dias = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate(), temEv = new Map();
  const m1 = new Date(m.getFullYear(), m.getMonth(), 1), m2 = new Date(m.getFullYear(), m.getMonth(), dias);
  for (const e of ag.mesEv || []) { // o evento de vários dias pinta cada dia do mês que ele cobre
    const t = trechoDoEvento(e); if (!t) continue;
    for (let d = new Date(Math.max(t.a, m1)); d <= Math.min(t.z, m2); d.setDate(d.getDate() + 1)) temEv.set(d.getDate(), (temEv.get(d.getDate()) || 0) + 1);
  }
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
  manterRolagem(el, h || '<div class="vazio-bloco"><strong>Nada neste mês a partir deste dia</strong><span>Os eventos do Calendário do Mac aparecem aqui.</span></div>');
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

/* ---------- folha aberta: a lista acompanha o Mac a cada 4 s ---------- */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline) return;
  const id = folhaAberta?.id;
  if (id === 'f-whats') lerWhats(); else if (id === 'f-sessoes') lerSessoes(); else if (id === 'f-cal') lerAgenda(true, true, true);
}, 4000);
