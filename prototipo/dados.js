/* Dados e utilitários comuns aos dois protótipos (iPhone e Mac). No app de verdade isto é o
   config.json do Mac: os dois lados leem e gravam o mesmo arquivo. */
const SVG = {
  tela: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>',
  baixo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
  menos: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 12h12"/></svg>',
  mais: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 7h14M5 12h14M5 17h14"/></svg>',
  terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m4 17 6-6-6-6M12 19h8"/></svg>',
  raio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8Z"/></svg>',
  microfone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/></svg>',
  lapis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3l4 4L8 20H4v-4L17 3z"/></svg>',
  x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  esq: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
  dir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>',
  grupo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/></svg>',
  anterior: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg>',
  proxima: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 5h2v14h-2zM4 5v14l11-7z"/></svg>',
  tocar: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4v16l13-8z"/></svg>',
  pausar: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>',
};

const APPS = [
  { nome: 'Vorssaint', ic: 'icones/vorssaint.png' }, { nome: 'Spotify', ic: 'icones/spotify.png' },
  { nome: 'WhatsApp', ic: 'icones/whatsapp.png' }, { nome: 'Calendar', ic: 'icones/calendario.png' },
  { nome: 'Safari', ic: 'icones/safari.png' }, { nome: 'Notes', ic: 'icones/notas.png' },
  { nome: 'Terminal', ic: 'icones/terminal.png' }, { nome: 'Finder', ic: 'icones/finder.png' },
];
const icApp = n => (APPS.find(a => a.nome === n) || {}).ic;
// ícone pequeno de serviço: app do Mac quando existe, SVG neutro quando não (Codex só tem linha de comando)
// ícone do serviço: o do app oficial (Claude, Codex, Spotify)
const IC_SERVICO = { Claude: 'icones/claude.png', Codex: 'icones/codex.png', Spotify: 'icones/spotify.png' };
const icServico = n => IC_SERVICO[n] ? `<img class="ic-mini" src="${IC_SERVICO[n]}" alt="">` : `<span class="ic-mini svg" aria-hidden="true">${SVG.terminal}</span>`;
const PAINEIS = { whatsapp: 'Não lidas do WhatsApp', calendario: 'Agenda por data e mês', sessoes: 'Sessões esperando resposta' };

let teclas = [
  { id: 'acordado', nome: 'Manter acordado', tipo: 'tecla', valor: 'ctrl+opt+cmd+k', estado: "pmset -g assertions | grep -q 'Vorssaint: keep the Mac awake'", icone: 'Vorssaint', acesa: true },
  { id: 'whatsapp', nome: 'WhatsApp', tipo: 'app', valor: 'WhatsApp', icone: 'WhatsApp' },
  { id: 'calendario', nome: 'Agenda', tipo: 'app', valor: 'Calendar', icone: 'Calendar' },
  { id: 'apagar', nome: 'Apagar tela', tipo: 'comando', valor: 'pmset displaysleepnow', icone: 'svg:tela' },
];

const USO = [ // só semanal: o Claude não tem mais a janela de 5 h, e o Codex só registra a semana
  { id: 'claude-leo', nome: 'Claude', conta: 'leo', sem: 61, renova: 'sex 14h' },   // cada conta renova num dia (resets_at de cada uma)
  { id: 'claude-equipe', nome: 'Claude', conta: 'equipe', sem: 77, renova: 'dom 9h' },
  { id: 'codex', nome: 'Codex', conta: 'pro', sem: 4, renova: 'qua 22h' },
]

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function iconeHTML(ic) {
  if (ic && ic.startsWith('svg:')) return `<span class="svg">${SVG[ic.slice(4)]}</span>`;
  if (icApp(ic)) return `<img src="${icApp(ic)}" alt="">`;
  return `<span class="svg">${SVG.raio}</span>`;
}

/* sincronia entre os protótipos: o que um grava o outro mostra na hora (abas do mesmo navegador) */
const canalDeck = 'BroadcastChannel' in self ? new BroadcastChannel('deck') : null;
const CHAVE_CONFIG = 'deck-config-v3'; // v3: perfis de teclas. v2 ainda é lida e vira um perfil só
function lerConfig() { try { return JSON.parse(localStorage.getItem(CHAVE_CONFIG) || localStorage.getItem('deck-config-v2')) } catch { return null } }
function publicar(config) {
  try { localStorage.setItem(CHAVE_CONFIG, JSON.stringify(config)) } catch {}
  canalDeck?.postMessage(config);
}
// "sex 14h" vira "em 3 dias", "amanhã", "hoje às 14h". curto: para a coluna estreita do iPhone
const DIAS_SEM = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
function renovaEm(txt, curto) {
  const m = /^(\w{3})\s+(\d{1,2})h$/.exec(String(txt).normalize('NFD').replace(/[\u0300-\u036f]/g, '')); if (!m) return txt;
  const agora = new Date(), alvo = new Date(agora); alvo.setHours(+m[2], 0, 0, 0);
  let falta = (DIAS_SEM.indexOf(m[1]) - agora.getDay() + 7) % 7; if (falta === 0 && alvo <= agora) falta = 7;
  alvo.setDate(alvo.getDate() + falta);
  const dias = Math.round((new Date(alvo).setHours(0, 0, 0, 0) - new Date(agora).setHours(0, 0, 0, 0)) / 864e5);
  if (dias === 0) return curto ? `hoje ${m[2]}h` : `hoje às ${m[2]}h`;
  if (dias === 1) return 'amanhã';
  return curto ? `${dias} dias` : `em ${dias} dias`;
}
const usoVisivel = () => BLOCOS.uso === false ? [] : USO.filter(u => u.mostrar !== false);
// o que o Mac configura e o iPhone mostra. Valores de exemplo são só o ponto de partida do protótipo
// tipos de tecla: app, teclado, comando, atalho. App do WhatsApp e do Calendário abre a lista no próprio iPhone
const PAINEL_DO_APP = { WhatsApp: 'whatsapp', Calendar: 'calendario' };
// tecla com ação (abrir a caixa de entrada, o dia da agenda) vai pro Mac: a lista do iPhone é só da tecla sem ação
const painelDe = t => t.tipo === 'app' && !t.acao ? PAINEL_DO_APP[t.valor] : undefined;
// config antiga tinha o tipo "painel": vira o app correspondente (Sessões abre pelo bloco, não precisa de tecla)
const normalizarTecla = t => t.tipo !== 'painel' ? t : ({ whatsapp: 'WhatsApp', calendario: 'Calendar' })[t.valor] ? { ...t, tipo: 'app', valor: ({ whatsapp: 'WhatsApp', calendario: 'Calendar' })[t.valor] } : null;
// tecla de app pode ter acao: { id, valor } (ex.: { id: 'mail-caixa', valor: '<id da conta>' }), lida do catálogo GET /api/apps/<bundle>/acoes do Mac (SPEC 13, item 26). O protótipo só a preserva
// config.whatsapp = { origem: 'auto' | 'app' | 'web', navegador? } existe só no config.json do Mac (SPEC 13, item 16): o protótipo não a usa
const BLOCOS = { spotify: true, agenda: true, whatsapp: true, sessoes: true, uso: true, monitor: false }; // o Deck mostra o que acha (o monitor do Mac nasce desligado). Esconder é no modo organizar
let nomeMac = 'MacBook Pro de Exemplo';
// perfis de teclas (Trabalho, Ensaio...): cada um com as suas. O iPhone mostra o perfil ativo
let perfis = [
  { id: 'trabalho', nome: 'Trabalho', teclas },
  { id: 'ensaio', nome: 'Ensaio', teclas: [
    { id: 'e-acordado', nome: 'Manter acordado', tipo: 'tecla', valor: 'ctrl+opt+cmd+k', estado: teclas[0].estado, icone: 'Vorssaint', acesa: true },
    { id: 'e-spotify', nome: 'Spotify', tipo: 'app', valor: 'Spotify', icone: 'Spotify' },
    { id: 'e-cifras', nome: 'Cifras', tipo: 'app', valor: 'Notes', icone: 'Notes' },
    { id: 'e-agenda', nome: 'Agenda', tipo: 'app', valor: 'Calendar', icone: 'Calendar' },
    { id: 'e-apagar', nome: 'Apagar tela', tipo: 'comando', valor: 'pmset displaysleepnow', icone: 'svg:tela' },
  ] },
];
let perfilAtivo = 'trabalho';
const perfilDe = id => perfis.find(p => p.id === id) || perfis[0];
const TECLAS_LEO = structuredClone(teclas), CONTAS_LEO = structuredClone(USO), PERFIS_LEO = structuredClone(perfis);
// teclas: cópia do perfil ativo, para quem ainda lê o formato antigo
const configAtual = comp => ({ perfis, perfilAtivo, teclas: perfilDe(perfilAtivo).teclas, comp, contas: USO, blocos: BLOCOS, nomeMac });
function aplicarConfigComum(c) {
  const limpar = l => (l || []).map(normalizarTecla).filter(Boolean);
  if (Array.isArray(c?.perfis) && c.perfis.length) { perfis = c.perfis.map(p => ({ ...p, teclas: limpar(p.teclas) })); perfilAtivo = perfilDe(c.perfilAtivo).id }
  else if (Array.isArray(c?.teclas)) { perfis = [{ id: 'principal', nome: 'Principal', teclas: limpar(c.teclas) }]; perfilAtivo = 'principal' }
  if (Array.isArray(c?.contas)) USO.splice(0, USO.length, ...c.contas);
  if (c?.blocos) Object.assign(BLOCOS, c.blocos);
  if (c?.nomeMac) nomeMac = c.nomeMac;
}
function aoMudarConfig(fn) { canalDeck?.addEventListener('message', e => fn(e.data)) }
