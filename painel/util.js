/* Peças comuns do painel: ícones, apps conhecidos e textos de tempo. Os dados vêm do Mac pelo canal (canal.js). */
const SVG = {
  tela: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg>',
  baixo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
  baixa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M6 13l6 6 6-6"/></svg>',
  sobe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg>',
  menos: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 12h12"/></svg>',
  mais: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 7h14M5 12h14M5 17h14"/></svg>',
  terminal: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m4 17 6-6-6-6M12 19h8"/></svg>',
  raio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8Z"/></svg>',
  microfone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 19v3"/></svg>',
  esq: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
  dir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>',
  pessoa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>',
  foto: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="9" cy="11" r="2"/><path d="m21 16-5-4-8 7"/></svg>',
  audio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7Z"/></svg>',
  unica: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" role="img" aria-label="Visualização única"><circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/><path d="m10 10 2-1.5V16"/></svg>',
  grupo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/></svg>',
  x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  lapis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3l4 4L8 20H4v-4L17 3z"/></svg>',
  anterior: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg>',
  proxima: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 5h2v14h-2zM4 5v14l11-7z"/></svg>',
  tocar: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4v16l13-8z"/></svg>',
  pausar: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>',
  aleatorio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m18 14 4 4-4 4M18 2l4 4-4 4M2 18h1.97a4 4 0 0 0 3.3-1.7l5.45-8.6a4 4 0 0 1 3.3-1.7H22M2 6h1.97a4 4 0 0 1 3.6 2.2M22 18h-6.04a4 4 0 0 1-3.3-1.8l-.36-.45"/></svg>',
  globo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20M12 2a15 15 0 0 0 0 20"/></svg>',
  sol: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  luzTeclado: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="9" width="20" height="11" rx="2"/><path d="M6 13h.01M10 13h.01M14 13h.01M18 13h.01M7 17h10M9 2v3M12 1v4M15 2v3"/></svg>',
  controles: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/></svg>',
  volume: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5 6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14"/></svg>',
  curtir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/></svg>',
  aparelhos: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect width="16" height="20" x="4" y="2" rx="2"/><circle cx="12" cy="14" r="4"/><path d="M12 6h.01"/></svg>',
  fila: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15V6M18.5 18a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM12 12H3M16 6H3M12 18H3"/></svg>',
  repetir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m17 2 4 4-4 4M3 11v-1a4 4 0 0 1 4-4h14M7 22l-4-4 4-4M21 13v1a4 4 0 0 1-4 4H3"/></svg>',
};

// ícones dos apps que o Mac pode ter em uma tecla (o nome vem em tecla.icone)
/* "Controles do Mac" não é um app: é uma tela do próprio iPhone (controles.js). Entra na lista de apps do editor, como o navegador padrão */
const CONTROLES_DO_MAC = { nome: 'Controles do Mac', valor: 'Controles', bundle: 'deck-controles', controles: true };
const APPS = [
  { nome: 'Vorssaint', ic: 'icones/vorssaint.png' }, { nome: 'Spotify', ic: 'icones/spotify.png' },
  { nome: 'WhatsApp', ic: 'icones/whatsapp.png' }, { nome: 'Calendar', ic: 'icones/calendario.png' },
  { nome: 'Safari', ic: 'icones/safari.png' }, { nome: 'Notes', ic: 'icones/notas.png' },
  { nome: 'Terminal', ic: 'icones/terminal.png' }, { nome: 'Finder', ic: 'icones/finder.png' },
];
const icApp = n => (APPS.find(a => a.nome === n) || {}).ic;
// ícone do serviço: o do app oficial (Claude, Codex, Spotify)
const IC_SERVICO = { Claude: 'icones/claude.png', Codex: 'icones/codex.png', Spotify: 'icones/spotify.png' };
const icServico = n => IC_SERVICO[n] ? `<img class="ic-mini" src="${IC_SERVICO[n]}" alt="">` : `<span class="ic-mini svg" aria-hidden="true">${SVG.terminal}</span>`;
// teclas de app que abrem uma lista no próprio iPhone (WhatsApp, Calendário, Mail, Monitor de Atividade e Controles)
const PAINEL_DO_APP = { WhatsApp: 'whatsapp', Calendar: 'calendario', Mail: 'mail', 'Activity Monitor': 'monitor', [CONTROLES_DO_MAC.valor]: 'controles' };
// tecla com ação (abrir a caixa de entrada, o dia da agenda) vai pro Mac: a lista do iPhone é só da tecla sem ação
const painelDe = t => t.tipo === 'app' && !t.acao ? PAINEL_DO_APP[t.valor] : undefined;

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
function iconeHTML(ic) {
  if (ic && ic.startsWith('svg:') && SVG[ic.slice(4)]) return `<span class="svg">${SVG[ic.slice(4)]}</span>`;
  if (icApp(ic)) return `<img src="${icApp(ic)}" alt="">`;
  return `<span class="svg">${SVG.raio}</span>`;
}

/* ---------- tempo: tudo a partir de datas ISO 8601 que o Mac manda ---------- */
const diaInicio = d => new Date(d).setHours(0, 0, 0, 0);
const diasEntre = (de, ate) => Math.round((diaInicio(ate) - diaInicio(de)) / 864e5);
const horaCurta = d => d.getMinutes() ? `${d.getHours()}h${String(d.getMinutes()).padStart(2, '0')}` : `${d.getHours()}h`;
// "2026-11-13T14:00:00-03:00" vira "em 3 dias", "amanhã" ou "hoje às 14h". curto: para a coluna estreita do iPhone
function renovaEm(iso, curto, ref = Date.now()) {
  const d = new Date(iso); if (!iso || isNaN(d)) return '-';
  const dias = diasEntre(ref, d);
  if (dias <= 0) return curto ? `hoje ${horaCurta(d)}` : `hoje às ${horaCurta(d)}`;
  if (dias === 1) return 'amanhã';
  return curto ? `${dias} dias` : `em ${dias} dias`;
}
// há quanto tempo a sessão espera: "5 min", "13 h", "4 dias". velha: passou de 1 h
function haQuanto(iso, ref = Date.now()) {
  const min = Math.max(1, Math.floor((ref - new Date(iso)) / 60000));
  const texto = isNaN(min) ? '-' : min < 60 ? `${min} min` : min < 1440 ? `${Math.floor(min / 60)} h` : `${Math.floor(min / 1440)} dias`;
  return { texto, velha: min >= 60 };
}
const mmss = s => { s = Math.max(0, Math.round(s) || 0); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0') };
// "#rrggbb" vira "r g b / alfa", ou nada se vier torto
function corCapa(hex, alfa) {
  const m = /^#([0-9a-f]{6})$/i.exec(hex || ''); if (!m) return '';
  const n = parseInt(m[1], 16); return `rgb(${n >> 16} ${(n >> 8) & 255} ${n & 255} / ${alfa})`;
}
// guardado no aparelho (nunca essencial: com o armazenamento bloqueado a tela funciona igual)
function lerGuardado(chave) { try { return localStorage.getItem(chave) } catch { return null } }
function guardar(chave, valor) { try { localStorage.setItem(chave, valor) } catch {} }
