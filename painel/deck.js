/* Painel do Deck: o visual do protótipo aprovado, com os dados vindo do Mac pelo canal (canal.js).
   Fluxo: um laço pede o estado a cada 1 s, monta a vista (V) e só mexe no que mudou. */

const tela = $('#tela');
let estado = null, config = null;     // o que o Mac mandou
let V = null;                         // a vista: o que a tela mostra agora (real ou o esqueleto)
let posicao = 'horizontal';
let offline = false, semAcesso = false, falhas = 0, tiquesConfig = 0;
let ultima = {};                      // o que já está desenhado, para só refazer o que mudou
let organizando = false;              // modo organizar (segurar uma tecla)
let sobrepor = {};                    // mudança local ainda a caminho do Mac (bloco escondido, perfil), por cima do estado
/* Resposta otimista: o toque muda a tela na hora e só volta se o Mac recusar. O laço de 1 s não desfaz a mudança
   antes de o Mac confirmar: cada sobreposição sai quando o estado dele já mostra o mesmo valor, quando o Mac recusa,
   ou depois de JANELA_OTM (ele não confirmou a tempo, vale o que ele diz). */
const JANELA_OTM = 4000;
let otmSpotify = null;                // { campos: {tocando, repetir, aleatorio}, pos: {p0, t0, andando}, faixa, ate }
let pendSpotify = 0;                  // comandos do Spotify ainda a caminho do Mac: enquanto houver, a intenção do último toque manda
const otmTeclas = {};                 // id da tecla -> { acesa, ate }

/* ---------- vista: do estado do Mac para o que a tela mostra ---------- */
const BLOCOS_PADRAO = { spotify: true, agenda: true, whatsapp: true, sessoes: true, uso: true, monitor: false };
function conferirSobrepor(e) {
  if (!sobrepor.ate) return;
  if (performance.now() > sobrepor.ate) { sobrepor = {}; return }
  for (const [b, v] of Object.entries(sobrepor.blocos || {})) if ((e.blocos?.[b] ?? BLOCOS_PADRAO[b]) === v) delete sobrepor.blocos[b];
  if (sobrepor.perfilAtivo === e.perfilAtivo) delete sobrepor.perfilAtivo;
}
const posEsperada = (p, agora) => p.p0 + (p.andando ? (agora - p.t0) / 1000 : 0);
/* o Spotify como a tela deve mostrar: o que o Mac mandou, com por cima o que o toque já mudou e ele ainda não confirmou */
function spotifyOtimista(s) {
  const o = otmSpotify; if (!o || !s) return s;
  const agora = performance.now();
  if ((agora > o.ate && !pendSpotify) || s.faixa !== o.faixa) { otmSpotify = null; return s } // passou o prazo (sem comando a caminho), ou a faixa já é outra: vale o Mac
  // "ele já confirmou" só vale com a fila vazia: com comandos a caminho, o valor que o Mac mostra ainda é o do toque anterior
  // (play, pausa, play seguidos: o 2º volta ao que o Mac mostra, e a tela piscaria pausada até o 2º chegar)
  if (!pendSpotify) for (const k of Object.keys(o.campos)) if (!!s[k] === o.campos[k]) delete o.campos[k];
  let posicao = null;
  if (o.pos) { const esperada = posEsperada(o.pos, agora); if (!pendSpotify && Math.abs((s.posicao || 0) - esperada) < 3) o.pos = null; else posicao = esperada }
  if (!Object.keys(o.campos).length && !o.pos) { otmSpotify = null; return s }
  return { ...s, ...o.campos, ...(posicao == null ? {} : { posicao: Math.min(posicao, s.duracao || posicao) }) };
}
function otimistaSpotify(campos, posicao) {
  const agora = performance.now(), s = V.spotify, antes = otmSpotify && agora < otmSpotify.ate ? otmSpotify : null;
  const novo = { campos: { ...(antes?.campos || {}), ...campos }, pos: antes?.pos ? { ...antes.pos, p0: posEsperada(antes.pos, agora), t0: agora } : null, faixa: s?.faixa, ate: agora + JANELA_OTM };
  if (posicao != null) novo.pos = { p0: posicao, t0: agora, andando: false };
  if (novo.pos) novo.pos.andando = !!(novo.campos.tocando ?? s?.tocando);
  otmSpotify = novo;
}
function acesasOtimistas(lista) {
  const agora = performance.now(), r = new Set(lista);
  for (const [id, o] of Object.entries(otmTeclas)) {
    if (agora > o.ate || r.has(id) === o.acesa) { delete otmTeclas[id]; continue }
    if (o.acesa) r.add(id); else r.delete(id);
  }
  return [...r];
}
function vistaReal() {
  const e = estado, ref = Date.parse(e.agora) || Date.now();
  conferirSobrepor(e);
  const blocos = { ...BLOCOS_PADRAO, ...e.blocos, ...sobrepor.blocos }, perfilId = sobrepor.perfilAtivo ?? e.perfilAtivo;
  const perfil = (config?.perfis || []).find(p => p.id === perfilId);
  const mostrar = id => (config?.contas || []).find(c => c.id === id)?.mostrar !== false;
  return {
    comp: ['b', 'c'].includes(e.comp) ? e.comp : 'a', blocos, ref, nomeMac: e.nomeMac,
    monitor: blocos.monitor ? e.monitor || {} : null,
    spotify: blocos.spotify === false ? null : spotifyOtimista(e.spotify || null),
    uso: blocos.uso === false ? [] : (e.uso || []).filter(u => mostrar(u.id)),
    sessoes: [...(e.sessoes || [])].filter(s => !dispensada(s)).sort((a, b) => Date.parse(b.desde) - Date.parse(a.desde)),
    teclas: perfil?.teclas || [], perfilAtivo: perfilId,
    perfis: (config?.perfis || []).map(p => ({ id: p.id, nome: p.nome, n: p.teclas.length })),
    acesas: acesasOtimistas(e.acesas || []), selos: e.selos || {}, agenda: e.agenda || null,
    whatsapp: blocos.whatsapp === false ? null : e.whatsapp || null,
  };
}
/* Esqueleto: a forma da última visita (só contagens, nunca texto), desenhada com os mesmos blocos da tela real. */
const CHAVE_FORMA = 'deck-forma-v1';
const FORMA_PADRAO = { v: 1, comp: 'a', blocos: { spotify: true, sessoes: true }, uso: 3, sessoes: 3, teclas: 4 };
function lerForma() {
  try {
    const f = JSON.parse(lerGuardado(CHAVE_FORMA));
    if (f?.v === 1 && ['a', 'b', 'c'].includes(f.comp) && typeof f.blocos?.spotify === 'boolean' && typeof f.blocos?.sessoes === 'boolean' && [f.uso, f.sessoes, f.teclas].every(n => Number.isInteger(n) && n >= 0)) return f;
  } catch {}
  return FORMA_PADRAO;
}
function guardarForma() {
  guardar(CHAVE_FORMA, JSON.stringify({ v: 1, comp: V.comp, blocos: { spotify: V.blocos.spotify !== false, sessoes: V.blocos.sessoes !== false }, uso: Math.min(V.uso.length, 6), sessoes: Math.min(V.sessoes.length, 6), teclas: Math.min(V.teclas.length, 12) }));
}
function vistaEsqueleto() {
  const f = lerForma(), agora = Date.now();
  return {
    carregando: true, comp: f.comp, blocos: { ...BLOCOS_PADRAO, ...f.blocos, uso: f.uso > 0 }, ref: agora, nomeMac: '',
    spotify: f.blocos.spotify ? { tocando: false, faixa: 'Música', artista: 'Artista', album: '', posicao: 0, duracao: 0, cores: [], repetir: false, aleatorio: false } : null,
    uso: Array.from({ length: f.uso }, (_, i) => ({ id: 'u' + i, nome: 'Claude', conta: 'conta', semana: 0, renova: null })),
    sessoes: Array.from({ length: f.sessoes }, (_, i) => ({ id: 's' + i, nome: 'Sessão', projeto: '', pergunta: 'Pergunta', desde: new Date(agora - 300000).toISOString() })),
    teclas: Array.from({ length: f.teclas }, (_, i) => ({ id: 'e' + i, nome: 'Tecla', tipo: 'comando', valor: '', icone: 'svg:raio' })),
    perfilAtivo: '', perfis: [], acesas: [], selos: {}, agenda: null, whatsapp: null, monitor: null,
  };
}
const semMusica = () => !V.spotify;
const usoVisivel = () => V.uso;

/* ---------- blocos ---------- */
// Menu: a tecla isolada abre uma folha pequena com "Nova tecla" e a troca de perfil
function abrirMenu(el) {
  const r = el.getBoundingClientRect(), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth;
  const l = $('#lista-perfis');
  l.innerHTML = `<button data-nova-tecla>Nova tecla</button><span class="rotulo-lista">Perfil</span><div role="listbox" aria-label="Perfis">${V.perfis.map(p => `<button role="option" data-perfil="${esc(p.id)}" aria-selected="${p.id === V.perfilAtivo}">${esc(p.nome)}<small>${p.n} teclas</small></button>`).join('')}</div>${V.perfis.length > 1 ? '<span class="dica-perfis">Crie e edite perfis no Mac</span>' : ''}`;
  l.hidden = false;
  // ancorada na tecla: abre para cima, ou para baixo se faltar espaço. Sem espaço nos dois (B deitado), abre ao lado
  const w = l.offsetWidth, h = l.offsetHeight, H = tela.offsetHeight, W = tela.offsetWidth;
  const cx = (r.left + r.width / 2 - t.left) / k, cima = (r.top - t.top) / k, baixo = (r.bottom - t.top) / k;
  const pos = { left: Math.max(8, Math.min(W - w - 8, cx - w / 2)), top: cima - 8 - h };
  if (pos.top < 8) pos.top = baixo + 8;
  if (pos.top + h > H - 8) Object.assign(pos, { left: Math.max(8, (r.left - t.left) / k - 8 - w), top: Math.max(8, Math.min(H - h - 8, (cima + baixo) / 2 - h / 2)) });
  l.style.left = pos.left + 'px'; l.style.top = pos.top + 'px';
}
const relogioHTML = () => `<div class="relogio" aria-label="Hora"><div class="placa" data-i="0"></div><div class="placa" data-i="1"></div><div class="dois-pontos" aria-hidden="true"><i></i><i></i></div><div class="placa" data-i="2"></div><div class="placa" data-i="3"></div></div><div class="data-linha"><div class="data"></div></div>`;
const nivel = p => p == null ? '' : p >= 90 ? 'cheio' : p >= 70 ? 'alto' : '';
const medidor = (rot, p) => `<div class="medidor ${nivel(p)}" aria-label="${rot}: ${p == null ? 'sem medição' : p + '%'}"><span class="trilho"><i style="width:${p ?? 0}%"></i></span><b>${p == null ? '-' : p + '%'}</b></div>`;
function usoCartao() {
  if (!usoVisivel().length) return '';
  return `<div class="cartao uso depende">${esconder('uso')}<div class="cartao-titulo"><span>Uso da semana</span><span class="renova-tit">renova</span></div>
    ${usoVisivel().map(u => `<div class="uso-linha"><span class="uso-nome">${icServico(u.nome)}<span>${esc(u.nome)} <small>${esc(u.conta)}</small></span></span>${medidor('semana', u.semana)}<span class="renova" aria-label="renova ${renovaEm(u.renova, true, V.ref)}">${renovaEm(u.renova, true, V.ref)}</span></div>`).join('')}</div>`;
}
function usoTira() {
  if (!usoVisivel().length) return ''; // nenhuma conta para mostrar: a faixa some
  return `<div class="uso-tira depende">${esconder('uso')}${usoVisivel().map(u => { const p = u.semana, txt = p == null ? '-' : p + '%'; return `<span class="${nivel(p)}" aria-label="${esc(u.nome)} ${esc(u.conta)}: ${p == null ? 'sem medição' : txt}">${icServico(u.nome)}<span class="nome-u">${esc(u.nome === 'Claude' ? u.conta : u.nome)}</span> <span class="mini"><i style="width:${p ?? 0}%"></i></span><b>${txt}</b></span>` }).join('')}</div>`;
}
/* Monitor do Mac: uma faixa pequena com o que a pessoa deixou ligado nos Ajustes do Mac (`itens` do estado).
   Bateria some sozinha em Mac sem bateria. Processador, memória e rede ficam com "-" até a primeira medida. */
const MONITOR_ITENS = ['cpu', 'memoria', 'bateria', 'rede'];
const monitorItens = () => {
  const m = V.monitor; if (!m) return [];
  return MONITOR_ITENS.filter(k => (m.itens || []).includes(k) && (k !== 'bateria' || m.bateria != null)); // `itens`: o que a pessoa deixou ligado nos Ajustes do Mac
};
const velocidade = b => b == null ? '-' : b >= 1048576 ? (b / 1048576).toFixed(b >= 10485760 ? 0 : 1).replace('.', ',') + ' MB/s' : Math.round(b / 1024) + ' KB/s';
// na tela o "/s" é um pedaço à parte: na linha apertada da horizontal ele sai e a seta já diz que é por segundo
const velocidadeTela = b => esc(velocidade(b)).replace(/\/s$/, '<span class="por-s">/s</span>');
const nivelBateria = m => m.naTomada || m.bateria > 20 ? '' : m.bateria <= 10 ? 'cheio' : 'alto';
function monitorHTML() {
  const itens = monitorItens(); if (!itens.length) return '';
  const m = V.monitor, pct = (rot, nome, p, nv) => `<span class="${nv ?? nivel(p)}" aria-label="${nome}: ${p == null ? 'sem medição' : p + '%'}"><span class="rot-m">${rot}</span> <span class="mini"><i style="width:${p ?? 0}%"></i></span><b>${p == null ? '-' : p + '%'}</b></span>`;
  const por = {
    cpu: () => pct('CPU', 'Processador', m.cpu),
    memoria: () => pct('Mem', 'Memória', m.memoria),
    bateria: () => pct(m.naTomada ? 'Tomada' : 'Bat', 'Bateria' + (m.naTomada ? ', na tomada' : ''), m.bateria, nivelBateria(m)),
    rede: () => `<span aria-label="Rede: baixando ${velocidade(m.baixa)}, enviando ${velocidade(m.sobe)}"><span class="rot-m">${SVG.baixa}</span><b>${velocidadeTela(m.baixa)}</b> <span class="rot-m">${SVG.sobe}</span><b>${velocidadeTela(m.sobe)}</b></span>`,
  };
  return `<div class="monitor-tira" role="group" aria-label="Monitor do Mac">${itens.map(k => por[k]()).join('')}</div>`;
}
/* Composição C: o mês de agora com hoje marcado. O bloco todo é um botão que abre a agenda */
function mesCHTML() {
  const hoje = new Date(V.ref), ano = hoje.getFullYear(), mes = hoje.getMonth(), dias = new Date(ano, mes + 1, 0).getDate();
  const nome = hoje.toLocaleDateString('pt-BR', { month: 'long' });
  let dias_ = '<span></span>'.repeat(new Date(ano, mes, 1).getDay());
  for (let n = 1; n <= dias; n++) { const dow = new Date(ano, mes, n).getDay(); dias_ += `<span class="${dow === 0 || dow === 6 ? 'fds' : ''} ${n === hoje.getDate() ? 'hoje' : ''}">${n}</span>` }
  return `<button class="cartao mes-c" data-painel="calendario" aria-label="${nome} de ${ano}. Abrir a agenda"><span class="mes-c-nome">${nome}</span><span class="sb-semana" aria-hidden="true"><span class="fds">D</span><span>S</span><span>T</span><span>Q</span><span>Q</span><span>S</span><span class="fds">S</span></span><span class="mes-c-dias">${dias_}</span></button>`;
}
const usoAtual = () => posicao === 'horizontal' && V.comp === 'a' ? usoCartao() : usoTira();
const temModos = s => s.repetir !== undefined || s.aleatorio !== undefined; // Mac antigo não manda: sem inventar, os botões não aparecem
const botaoModo = (k, s, rot) => k === 'repetir' && conectado(s)
  ? `<button class="modo" data-midia="repetir" data-modo="${modoRepetir(s)}" aria-label="${ROTULO_REPETIR[modoRepetir(s)]}" aria-pressed="${modoRepetir(s) !== 'nao'}">${SVG.repetir}</button>`
  : `<button class="modo" data-midia="${k}" aria-label="${rot}" aria-pressed="${!!s[k]}">${SVG[k]}</button>`;
const capaEstilo = s => { const c1 = corCapa(s.cores?.[0], .55), c2 = corCapa(s.cores?.[1] || s.cores?.[0], .35); return c1 ? ` style="--capa-1: ${c1}; --capa-2: ${c2}"` : '' };
function playerHTML() {
  const s = V.spotify || { tocando: false, faixa: '', artista: '', posicao: 0, duracao: 0, cores: [] }, t = !!s.tocando;
  // cores da capa: o Mac tira as duas cores dominantes da arte e manda junto
  const capa = s.capaId ? ` src="${esc(canal.capaUrl(s.capaId))}"` : '';
  const modos = temModos(s);
  return `<div class="cartao player depende ${t ? '' : 'pausado'}"${capaEstilo(s)}>${esconder('spotify')}
    <img class="capa" data-abrir-spotify${capa} alt="${V.carregando ? '' : 'Capa: ' + esc(s.faixa)}" onerror="this.dataset.erro=1;this.removeAttribute('src')">
    <div class="info"><div class="titulos" data-abrir-spotify><div class="faixa">${esc(s.faixa)}</div><div class="artista">${icServico('Spotify')}${esc(s.artista)}</div></div>
      <div class="midia"><button aria-label="Anterior" data-midia="anterior">${SVG.anterior}</button><button class="tocar ${t ? '' : 'play'}" aria-label="${t ? 'Pausar' : 'Tocar'}" data-midia="tocar">${t ? SVG.pausar : SVG.tocar}</button><button aria-label="Próxima" data-midia="proxima">${SVG.proxima}</button></div>
      <div class="progresso ${modos ? 'com-modos' : ''}" data-total="${s.duracao || 0}">${modos ? botaoModo('aleatorio', s, 'Aleatório') : ''}<span class="decorrido">${mmss(s.posicao)}</span><span class="trilho" role="slider" aria-label="Posição da música" aria-valuemin="0" aria-valuemax="${Math.round(s.duracao || 0)}" aria-valuenow="${Math.round(s.posicao || 0)}"><i style="width:${s.duracao > 0 ? Math.min(100, s.posicao / s.duracao * 100) : 0}%"></i></span><span class="total">${mmss(s.duracao)}</span>${modos ? botaoModo('repetir', s, 'Repetir a lista ou o álbum') : ''}</div>
    </div></div>`;
}
const ESCONDE = { spotify: 'Spotify', sessoes: 'Sessões', uso: 'Uso das IAs' };
// "−" de esconder o bloco, só no modo organizar. span: o cartão de sessões já é um botão
const esconder = b => `<span class="esconder-bloco" role="button" tabindex="0" data-esconder="${b}" aria-label="Esconder ${ESCONDE[b]}">${SVG.menos}</span>`;
function sessoesHTML() {
  if (V.blocos.sessoes === false) return '';
  const n = V.sessoes.length;
  const corpo = n === 0 ? `<div class="vazio-rico"><img src="icones/claude.png" alt=""><div><strong>Tudo respondido</strong><span>Nenhuma sessão do Claude esperando você.</span></div></div>`
    : V.sessoes.slice(0, 7).map(s => { const h = haQuanto(s.desde, V.ref); return `<div class="sessao"><b>${esc(s.nome)}</b><span>${esc(s.pergunta)}</span><time class="${h.velha ? 'velha' : ''}">${h.texto}</time></div>` }).join('');
  // o bloco inteiro é um alvo só: linha pequena demais para acertar no dedo
  return `<button class="cartao sessoes depende" data-painel="sessoes" aria-label="Sessões esperando: ${n}">${esconder('sessoes')}<div class="cartao-titulo"><span>${icServico('Claude')}Sessões esperando</span>${n ? `<span class="conta">${n}</span>` : ''}</div>${corpo}</button>`;
}
/* horário do próximo evento na tecla da Agenda: "14:00", "amanhã 10:30", "qui 20:00" */
function horaDoEvento(ev) {
  const d = new Date(ev.inicio), dias = diasEntre(V.ref, d), hh = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
  const dia = dias <= 0 ? '' : dias === 1 ? 'amanhã' : d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '');
  return ev.diaTodo ? dia || 'hoje' : (dia + ' ' + hh).trim();
}
// tecla que acende: a que tem comando de conferir (`estado`) ou liga e desliga (`desligar`, o Mac guarda o estado)
const acendeTecla = t => !!(t.estado || t.desligar);
// o que muda na tecla a cada estado: acesa, selo (WhatsApp, "!" da Agenda) e horário da Agenda
function infoTecla(t) {
  const cal = painelDe(t) === 'calendario';
  const selo = V.selos[t.id] ?? (cal && V.agenda && V.agenda.permissao === false ? '!' : null);
  const prox = cal && !selo && V.agenda?.proximo ? V.agenda.proximo : null;
  return { acesa: acendeTecla(t) && V.acesas.includes(t.id), selo, hora: prox ? horaDoEvento(prox) : null, titulo: prox?.titulo };
}
function extraTecla(t, i) {
  const seloTxt = i.selo == null ? '' : /^\d+$/.test(i.selo) && +i.selo > 99 ? '99+' : i.selo;
  const aria = i.selo === '!' ? 'Agenda sem permissão' : `${i.selo} não lidas`;
  return (i.selo != null ? `<span class="selo" aria-label="${esc(aria)}">${esc(seloTxt)}</span>` : '')
    + (i.hora ? `<span class="hora-tecla" aria-label="Próximo: ${esc(i.titulo)} ${esc(i.hora)}">${esc(i.hora)}</span>` : '');
}
function teclaHTML(t) {
  const i = infoTecla(t);
  return `<button class="tecla depende ${i.acesa ? 'acesa' : ''}" data-id="${esc(t.id)}" ${acendeTecla(t) ? `aria-pressed="${i.acesa}"` : ''}>
    <span class="editar" aria-hidden="true">${SVG.lapis}</span>
    ${iconeDaTecla(t)}<span class="nome">${esc(t.nome)}</span><span class="led" aria-hidden="true"></span>${extraTecla(t, i)}
    </button>`;
}
const MENU = `<button class="tecla menu depende" data-id="menu" aria-haspopup="dialog"><span class="svg">${SVG.menu}</span><span class="nome">Menu</span></button>`;
function teclasHTML(porPagina) {
  // apps no carrossel (sempre centralizados), "Menu" isolada do outro lado da divisória;
  // a divisória vira os pontinhos quando há mais de uma página
  // B deitado: a grade fica como era, com "Menu" como última tecla. A e em pé: "Menu" numa seção só dela
  const grade = V.comp === 'b' && posicao === 'horizontal', itens = grade ? [...V.teclas.map(teclaHTML), MENU] : V.teclas.map(teclaHTML), paginas = [];
  for (let i = 0; i < itens.length; i += porPagina) paginas.push(itens.slice(i, i + porPagina));
  if (!paginas.length) paginas.push([]);
  const divisor = paginas.length > 1
    ? `<div class="divisor com-pontos" aria-hidden="true">${paginas.map(() => '<i class="ponto"></i>').join('')}<b class="indicador"></b></div>`
    : grade ? '' : '<div class="divisor" aria-hidden="true"><i class="linha"></i></div>';
  return `<div class="carrossel"><div class="paginas">${paginas.map(p => `<div class="pagina">${p.join('')}</div>`).join('')}</div></div>${divisor}${grade ? '' : `<div class="menu-area">${MENU}</div>`}`;
}
const porPagina = () => V.comp === 'b' ? (posicao === 'vertical' ? 6 : 9) : posicao === 'horizontal' ? 5 : 6;

/* ---------- desenho ---------- */
// o que, se mudar, obriga a refazer a tela inteira
const chaveLayout = () => JSON.stringify([posicao, V.comp, monitorItens(), !!V.carregando, V.blocos.sessoes !== false, usoVisivel().length > 0, V.perfilAtivo, V.perfis, V.teclas.map(t => [t.id, t.nome, t.tipo, t.valor, t.icone, acendeTecla(t)]), appsMac.versao]);
const chaveTeclas = () => JSON.stringify(V.teclas.map(t => { const i = infoTecla(t); return [i.acesa, i.selo, i.hora] }));
const chavePlayer = () => { const s = V.spotify; return s ? JSON.stringify([s.faixa, s.artista, s.album, s.capaId, s.cores, s.duracao, temModos(s), conectado(s)]) : null };

function render() {
  $('#lista-perfis').hidden = true; // a folha do Menu fica presa à tecla de antes: sem ela, refazer a tela a fecha
  const x = $('#teclas .paginas')?.scrollLeft || 0;
  const sem = V.comp === 'c' ? 'sem-musica sem-sessoes sem-uso' : `${semMusica() ? 'sem-musica' : ''} ${V.blocos.sessoes === false ? 'sem-sessoes' : ''} ${usoVisivel().length ? '' : 'sem-uso'}`;
  const c = $('#conteudo');
  c.classList.toggle('carregando', !!V.carregando);
  c.setAttribute('aria-busy', String(!!V.carregando));
  const cm = monitorItens().length ? ' com-monitor' : '';
  c.innerHTML = V.comp === 'c'
    // C: o relógio com as horas sobre os minutos (o mesmo desenho do relógio grande da A) e o mês, com a fileira de teclas da A
    ? `<div class="comp-a comp-c ${sem}${cm}"><div class="topo">
        <div class="esquerda"><div class="relogio-linha">${relogioHTML()}${monitorHTML()}</div></div>
        <div class="direita">${mesCHTML()}</div>
      </div><div class="teclas" id="teclas">${teclasHTML(porPagina())}</div></div>`
    : V.comp === 'a'
    ? `<div class="comp-a ${sem}${cm}"><div class="topo">
        <div class="esquerda"><div class="relogio-linha">${relogioHTML()}${posicao === 'vertical' ? usoTira() : ''}${monitorHTML()}</div>${posicao === 'vertical' ? '' : usoCartao()}</div>
        <div class="direita">${playerHTML()}${sessoesHTML()}</div>
      </div><div class="teclas" id="teclas">${teclasHTML(porPagina())}</div></div>`
    : `<div class="comp-b ${sem}${cm}"><div class="esquerda">
        <div class="relogio-linha"><div>${relogioHTML()}</div>${usoTira()}${monitorHTML()}</div>
        ${playerHTML()}${sessoesHTML()}
      </div><div class="teclas" id="teclas">${teclasHTML(porPagina())}</div></div>`;
  marcarRelogioGrande();
  tique(true);
  ligarCarrossel();
  const pg = $('#teclas .paginas'); if (pg && x) pg.scrollLeft = x;
  pintarEscondidos();
  ultima = { layout: chaveLayout(), semMusica: semMusica(), player: chavePlayer(), uso: usoAtual(), sessoes: sessoesHTML(), teclas: chaveTeclas(), monitor: monitorHTML(), mes: V.comp === 'c' ? mesCHTML() : '' };
  pintarProgresso(true);
}
// só o que mudou: o relógio, o carrossel e os gestos em andamento não são refeitos a cada segundo
function atualizar() {
  if (gesto?.arrastando) return; // o arrasto mexe nas teclas na mão: o laço não redesenha por cima
  pintarEscondidos();
  if (chaveLayout() !== ultima.layout) { render(); return }
  const sem = semMusica();
  if (V.spotify && V.comp !== 'c') { // a C não tem o player pequeno
    const kp = chavePlayer();
    if (kp !== ultima.player) { $('.player').outerHTML = playerHTML(); ultima.player = kp }
    const pl = $('.player');
    // a capa que falhou ao baixar (Mac ocupado, rede) é pedida de novo no próximo passo
    const img = $('.capa', pl);
    if (img?.dataset.erro && V.spotify.capaId) { delete img.dataset.erro; img.src = canal.capaUrl(V.spotify.capaId) }
    pintarMidia(pl, V.spotify);
  }
  if (folhaAberta?.id === 'f-player') pintarPlayerCheio();
  if (sem !== ultima.semMusica) { ultima.semMusica = sem; if (V.comp !== 'c') alternarMusica(sem) } // a C não tem player: o relógio já ocupa o lugar
  const uso = usoAtual(), elUso = $('.cartao.uso, .uso-tira');
  if (elUso && uso !== ultima.uso) { elUso.outerHTML = uso; ultima.uso = uso }
  const mon = monitorHTML(), elMon = $('.monitor-tira');
  if (elMon && mon !== ultima.monitor) { elMon.outerHTML = mon; ultima.monitor = mon }
  if (V.comp === 'c') { const mes = mesCHTML(), elMes = $('.mes-c'); if (elMes && mes !== ultima.mes) { elMes.outerHTML = mes; ultima.mes = mes } }
  const ses = sessoesHTML(), elSes = $('.sessoes');
  if (elSes && ses !== ultima.sessoes) { elSes.outerHTML = ses; ultima.sessoes = ses }
  const kt = chaveTeclas();
  if (kt !== ultima.teclas) { pintarTeclas(); ultima.teclas = kt }
  pintarProgresso();
}
/* play/pausa, aleatório e repetir de um player (o pequeno ou o de tela cheia): só o que mudou */
function pintarMidia(raiz, s) {
  const t = !!s.tocando;
  raiz.classList.toggle('pausado', !t);
  const b = $('.tocar', raiz);
  if (b && b.classList.contains('play') === t) { b.classList.toggle('play', !t); b.setAttribute('aria-label', t ? 'Pausar' : 'Tocar'); b.innerHTML = t ? SVG.pausar : SVG.tocar }
  $$('.modo', raiz).forEach(m => {
    if (m.dataset.midia !== 'repetir') return m.setAttribute('aria-pressed', String(!!s[m.dataset.midia]));
    const modo = modoRepetir(s); // com o Spotify conectado são três jeitos: nada, a lista, só a música
    m.setAttribute('aria-pressed', String(modo !== 'nao')); m.setAttribute('aria-label', conectado(s) ? ROTULO_REPETIR[modo] : 'Repetir a lista ou o álbum');
    if (conectado(s)) m.dataset.modo = modo; else delete m.dataset.modo;
  });
}
/* O relógio ocupa o espaço que sobra quando um bloco do lado some (ver .relogio-grande no CSS) */
function marcarRelogioGrande() {
  const comp = $('.comp-a, .comp-b'); if (!comp) return;
  const c = n => comp.classList.contains(n), m = c('sem-musica'), ss = c('sem-sessoes'), u = c('sem-uso'), a = c('comp-a');
  const grande = posicao === 'vertical' ? m + ss + u >= 2 : a ? u || (m && ss) : ss && (u || m);
  comp.classList.toggle('relogio-grande', grande);
  comp.classList.toggle('relogio-maior', !grande && !a && posicao === 'horizontal' && ss);
}
function pintarTeclas() {
  for (const t of V.teclas) {
    const el = $(`.tecla[data-id="${CSS.escape(t.id)}"]`); if (!el) continue;
    const i = infoTecla(t);
    el.classList.toggle('acesa', i.acesa);
    if (acendeTecla(t)) el.setAttribute('aria-pressed', String(i.acesa));
    $$('.selo, .hora-tecla', el).forEach(x => x.remove());
    el.insertAdjacentHTML('beforeend', extraTecla(t, i));
  }
}
let travaProgressoAte = 0; // depois de arrastar a barra, o Mac leva um instante para confirmar a posição nova
function pintarProgresso(forcar) {
  if (!V.spotify || scrub || (!forcar && performance.now() < travaProgressoAte)) return;
  const s = V.spotify;
  $$('.progresso').forEach(pr => {
    const tr = $('.trilho', pr);
    pr.dataset.total = s.duracao || 0;
    $('.decorrido', pr).textContent = mmss(s.posicao); $('.total', pr).textContent = mmss(s.duracao);
    $('i', tr).style.width = (s.duracao > 0 ? Math.min(100, s.posicao / s.duracao * 100) : 0) + '%';
    tr.setAttribute('aria-valuenow', Math.round(s.posicao || 0)); tr.setAttribute('aria-valuemax', Math.round(s.duracao || 0));
  });
}
function ligarCarrossel() {
  const pg = $('#teclas .paginas'); if (!pg) return;
  // desfoque e transparência calculados pela posição de cada tecla, um quadro por vez: entram e saem
  // junto com o dedo, sem ligar ou desligar de repente. Parado e encaixado, tudo fica nítido.
  let quadro = 0;
  pg.addEventListener('scroll', () => { if (quadro) return; quadro = requestAnimationFrame(() => { quadro = 0; moverIndicador(pg); desfocarBordas(pg) }) }, { passive: true });
  moverIndicador(pg);
}
/* desfoque leve na tecla que está saindo: proporcional ao quanto dela já está fora da área */
function desfocarBordas(pg) {
  const v = pg.getBoundingClientRect();
  $$('.tecla', pg).forEach(t => {
    const r = t.getBoundingClientRect(), dentro = Math.max(0, Math.min(r.right, v.right) - Math.max(r.left, v.left)) / r.width;
    const fora = 1 - Math.min(1, dentro) ** 1.5; // curva suave: começa devagar, acelera perto da borda
    t.style.filter = fora > .01 ? `blur(${(fora * 6).toFixed(2)}px)` : '';
    t.style.opacity = fora > .01 ? (1 - fora * .85).toFixed(3) : '';
  });
}
/* "minhoca": o indicador estica até a próxima bolinha na primeira metade do arrasto e encolhe nela na segunda, seguindo o dedo */
function moverIndicador(pg) {
  const div = $('#teclas .divisor.com-pontos'); if (!div) return;
  const pontos = $$('.ponto', div), ind = $('.indicador', div), vert = getComputedStyle(div).flexDirection === 'column';
  const cs = getComputedStyle(pg), passo = pg.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) + parseFloat(cs.columnGap || 0);
  const prog = Math.max(0, Math.min(pontos.length - 1, pg.scrollLeft / passo)), i = Math.min(Math.floor(prog), pontos.length - 2), f = prog - i;
  const pos = n => vert ? pontos[n].offsetTop : pontos[n].offsetLeft, tam = vert ? pontos[0].offsetHeight : pontos[0].offsetWidth;
  const ini = pos(i) + Math.max(0, (f - .5) * 2) * (pos(i + 1) - pos(i)), fim = pos(i) + tam + Math.min(1, f * 2) * (pos(i + 1) - pos(i));
  if (vert) { ind.style.top = ini + 'px'; ind.style.height = fim - ini + 'px' } else { ind.style.left = ini + 'px'; ind.style.width = fim - ini + 'px' }
}

/* sem música: o player sai e as sessões crescem até o topo (FLIP: mede antes e depois, anima a diferença) */
function alternarMusica(fechado) {
  const comp = $('.comp-a, .comp-b'), ses = $('.sessoes'), pl = $('.player');
  if (!comp) return;
  if (!ses || posicao === 'vertical') { comp.classList.toggle('sem-musica', fechado); marcarRelogioGrande(); return }
  const k = escalaTela().k, antes = ses.getBoundingClientRect();
  const dur = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--mov-lento')) || 480;
  if (fechado) pl.animate([{ opacity: 1, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(.96)' }], { duration: dur * .45, easing: 'cubic-bezier(.32,0,.67,0)' });
  setTimeout(() => {
    comp.classList.toggle('sem-musica', fechado); marcarRelogioGrande();
    const depois = ses.getBoundingClientRect();
    ses.animate([{ transform: `translateY(${(antes.top - depois.top) / k}px)`, height: antes.height / k + 'px' }, { transform: 'none', height: depois.height / k + 'px' }], { duration: dur, easing: 'cubic-bezier(.22,1,.36,1)' });
    if (!fechado) pl.animate([{ opacity: 0, transform: 'scale(.96)' }, { opacity: 1, transform: 'scale(1)' }], { duration: dur, delay: dur * .3, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' });
  }, fechado ? dur * .45 : 0);
}

/* barra de tempo arrastável: área de toque alta, numa linha só dela, longe dos botões */
let scrub = null;
document.addEventListener('pointerdown', ev => {
  const tr = ev.target.closest('.progresso .trilho'); if (!tr) return;
  scrub = { tr, pr: tr.closest('.progresso'), f: 0 }; scrub.pr.classList.add('arrastando'); tr.setPointerCapture?.(ev.pointerId); moverScrub(ev); ev.preventDefault();
});
document.addEventListener('pointermove', ev => { if (scrub) moverScrub(ev) });
document.addEventListener('pointerup', async () => {
  if (!scrub) return;
  const { pr, f } = scrub, s = Math.round(f * (+pr.dataset.total)), texto = $('.decorrido', pr).textContent;
  pr.classList.remove('arrastando'); scrub = null; travaProgressoAte = performance.now() + 1500;
  otimistaSpotify({}, s); avisar('Pulou para ' + texto); // a barra já fica onde o dedo soltou: o Mac confirma em seguida
  V = vistaReal(); pintarProgresso(true); // e a do outro player (o pequeno atrás da tela cheia) também, sem esperar a trava
  enfileirarSpotify(async () => { try { await canal.spotify('posicao', s); await atualizarJa() } catch (e) { travaProgressoAte = 0; desfazerSpotify(); tratarErro(e) } });
});
document.addEventListener('pointercancel', () => { if (!scrub) return; scrub.pr.classList.remove('arrastando'); scrub = null; pintarProgresso(true) });
function moverScrub(ev) {
  const r = scrub.tr.getBoundingClientRect(), f = Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)), total = +scrub.pr.dataset.total;
  scrub.f = f;
  $('i', scrub.tr).style.width = f * 100 + '%'; $('.decorrido', scrub.pr).textContent = mmss(f * total); scrub.tr.setAttribute('aria-valuenow', Math.round(f * total));
}

/* ---------- relógio ---------- */
function montarPlaca(el, d) { el.innerHTML = `<div class="metade cima"><span>${d}</span></div><div class="metade baixo"><span>${d}</span></div>`; el.dataset.d = d }
function virarPlaca(el, novo) {
  const velho = el.dataset.d;
  el.classList.remove('virando');
  el.innerHTML = `<div class="metade cima"><span>${novo}</span></div><div class="metade baixo"><span>${velho}</span></div><div class="metade cima aba-cima"><span>${velho}</span></div><div class="metade baixo aba-baixo"><span>${novo}</span></div>`;
  el.dataset.d = novo;
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('virando')));
  setTimeout(() => { if (el.dataset.d === novo) montarPlaca(el, novo) }, 900);
}
function tique(inicial) {
  const agora = new Date();
  const dig = (String(agora.getHours()).padStart(2, '0') + String(agora.getMinutes()).padStart(2, '0')).split('');
  $$('.placa').forEach(el => { const d = dig[el.dataset.i]; if (inicial || !el.dataset.d) montarPlaca(el, d); else if (el.dataset.d !== d) virarPlaca(el, d) });
  const [dia, ...resto] = agora.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' }).split(', ');
  $$('.data').forEach(d => { d.innerHTML = `<b>${dia}</b>, ${resto.join(', ')}` });
}
setInterval(() => tique(false), 1000);
/* tela cheia: as mesmas placas e a data, grandes, em fundo preto. Tocar em qualquer lugar volta */
$('#f-relogio').innerHTML = relogioHTML();
function abrirRelogio() { tique(true); $('#f-relogio').classList.add('aberta') }
function fecharRelogio() { $('#f-relogio').classList.remove('aberta') }
$('#f-relogio').addEventListener('click', fecharRelogio); // direto no elemento: a placa que vira no meio do toque some do DOM e o clique não chegaria na tela

/* ---------- aviso ---------- */
let tAviso;
function avisar(txt, { erro = false, desfazer = null } = {}) {
  const a = $('#aviso'); $('#aviso-txt').textContent = txt; a.classList.toggle('erro', erro);
  const b = $('#aviso-acao'); b.hidden = !desfazer; b.onclick = () => { desfazer(); a.classList.remove('visivel') };
  a.classList.add('visivel'); clearTimeout(tAviso); tAviso = setTimeout(() => a.classList.remove('visivel'), erro ? 4000 : desfazer ? 5000 : 3000);
}
// falha de uma ação: o motivo vem do Mac. Sem acesso (401) cai na tela de pareamento
function tratarErro(e) {
  if (e.status === 401) { semAcesso = true; pintarGlobal(); return }
  avisar(e.rede ? 'Sem conexão com o Mac. Confira o Wi-Fi.' : e.message, { erro: true });
}

/* ---------- toque ---------- */
const escalaTela = () => { const r = tela.getBoundingClientRect(); return { r, k: r.width / tela.offsetWidth } };
const ocupadas = new Set(); // um toque, uma ação: a tecla espera o Mac responder antes de aceitar outro
async function executar(id) {
  if (id === 'menu') { const lp = $('#lista-perfis'); return lp.hidden ? abrirMenu($('.tecla.menu')) : (lp.hidden = true) }
  const t = V.teclas.find(x => x.id === id); if (!t || ocupadas.has(id)) return;
  if (painelDe(t)) return abrirPainel(painelDe(t), id); // WhatsApp e Calendário abrem a lista aqui, com "Abrir no Mac" dentro
  ocupadas.add(id);
  // resposta otimista: a tecla acende (ou pisca) e o aviso aparece no toque. Se o Mac recusar, volta e o aviso vira o erro
  const el = $(`.tecla[data-id="${CSS.escape(id)}"]`), quer = !V.acesas.includes(id);
  el?.classList.add('piscando'); setTimeout(() => el?.classList.remove('piscando'), 400);
  if (acendeTecla(t)) { otmTeclas[id] = { acesa: quer, ate: performance.now() + JANELA_OTM }; V = vistaReal(); atualizar(); avisar(`${t.nome}: ${quer ? 'ligado' : 'desligado'}`) }
  else avisar(t.tipo === 'app' ? `Abrindo ${t.nome} no Mac` : `${t.nome}: feito`);
  try { await canal.botao(id); atualizarJa() }
  catch (e) { delete otmTeclas[id]; el?.classList.remove('piscando'); if (V) { V = vistaReal(); atualizar() } tratarErro(e) }
  finally { ocupadas.delete(id) }
}
/* Spotify: um comando de cada vez, na ordem do toque (dois pedidos soltos podem chegar trocados ao Mac) */
let filaSpotify = Promise.resolve();
const enfileirarSpotify = fn => { pendSpotify++; return filaSpotify = filaSpotify.then(fn).finally(() => { pendSpotify-- }) };
function desfazerSpotify() { otmSpotify = null; if (V) { V = vistaReal(); atualizar() } }
function midia(acao) {
  const s = V.spotify; if (!s || V.carregando) return;
  if (acao === 'repetir' && conectado(s)) return repetirCiclo(); // conectado: nada, a lista ou só a música (player.js)
  const quer = acao === 'tocar' ? (s.tocando ? 'pausar' : 'tocar') : acao, modo = acao === 'repetir' || acao === 'aleatorio', valor = modo ? !s[acao] : undefined;
  // a tela muda no toque. Pular faixa começa a nova do zero e tocando, pausar para a barra, e o Mac confirma em seguida
  if (modo) otimistaSpotify({ [acao]: valor });
  else if (quer === 'tocar' || quer === 'pausar') otimistaSpotify({ tocando: quer === 'tocar' });
  else otimistaSpotify({ tocando: true }, 0);
  V = vistaReal(); atualizar();
  const aviso = quer === 'proxima' ? 'Próxima faixa' : quer === 'anterior' ? 'Faixa anterior' : modo ? `${acao === 'repetir' ? 'Repetir' : 'Aleatório'}: ${valor ? 'ligado' : 'desligado'}` : null;
  if (aviso) avisar(aviso);
  return enfileirarSpotify(async () => { try { await canal.spotify(quer, valor); await atualizarJa() } catch (e) { desfazerSpotify(); tratarErro(e) } });
}
/* ---------- player em tela cheia: capa grande, faixa, artista, álbum, barra, botões, repetir e aleatório ----------
   Só o que o AppleScript do Spotify entrega. A próxima da fila e o "repetir só a música" não existem nele (precisam do login
   na API do Spotify), então não aparecem. */
let cheioChave = '';
function playerCheioHTML(s) {
  const t = !!s.tocando, modos = temModos(s), capa = s.capaId ? ` src="${esc(canal.capaUrl(s.capaId))}"` : '';
  return `<div class="pc ${t ? '' : 'pausado'}">
    <img class="capa-grande"${capa} alt="Capa: ${esc(s.faixa)}" onerror="this.dataset.erro=1;this.removeAttribute('src')">
    <div class="pc-info">
      <div class="pc-titulos"><div class="faixa">${esc(s.faixa)}</div><div class="artista">${icServico('Spotify')}<span class="texto-artista">${esc(s.artista)}</span></div>${s.album ? `<div class="album">${esc(s.album)}</div>` : ''}</div>
      <div class="progresso" data-total="${s.duracao || 0}"><span class="decorrido">${mmss(s.posicao)}</span><span class="trilho" role="slider" aria-label="Posição da música" aria-valuemin="0" aria-valuemax="${Math.round(s.duracao || 0)}" aria-valuenow="${Math.round(s.posicao || 0)}"><i style="width:${s.duracao > 0 ? Math.min(100, s.posicao / s.duracao * 100) : 0}%"></i></span><span class="total">${mmss(s.duracao)}</span></div>
      <div class="midia grande">${modos ? botaoModo('aleatorio', s, 'Aleatório') : ''}<button aria-label="Anterior" data-midia="anterior">${SVG.anterior}</button><button class="tocar ${t ? '' : 'play'}" aria-label="${t ? 'Pausar' : 'Tocar'}" data-midia="tocar">${t ? SVG.pausar : SVG.tocar}</button><button aria-label="Próxima" data-midia="proxima">${SVG.proxima}</button>${modos ? botaoModo('repetir', s, 'Repetir a lista ou o álbum') : ''}</div>
      ${extrasPlayerHTML(s)}
    </div></div>`;
}
function abrirPlayer() { cheioChave = ''; fecharListaPlayer(); pintarPlayerCheio(); abrirFolha('#f-player') }
function pintarPlayerCheio() {
  const s = V.spotify; if (!s) return fecharFolha(); // o Spotify fechou ou o bloco foi escondido: não há o que mostrar
  const f = $('#f-player'), k = JSON.stringify([s.faixa, s.artista, s.album, s.capaId, s.cores, s.duracao, temModos(s), chaveExtras(s)]);
  if (k !== cheioChave) {
    cheioChave = k;
    f.style.setProperty('--capa-1', corCapa(s.cores?.[0], .55) || 'transparent'); f.style.setProperty('--capa-2', corCapa(s.cores?.[1] || s.cores?.[0], .35) || 'transparent');
    $('#pc-corpo').innerHTML = playerCheioHTML(s); pintarProgresso(true);
  }
  pintarMidia($('.pc', f), s); pintarExtras(s);
  if (lp.qual === 'fila' && s.faixa !== lp.faixa) { lp.faixa = s.faixa; lerListaPlayer() } // a fila anda com a música
  const img = $('.capa-grande', f); if (img?.dataset.erro && s.capaId) { delete img.dataset.erro; img.src = canal.capaUrl(s.capaId) }
}
async function ativarPerfil(id) {
  $('#lista-perfis').hidden = true;
  const novo = V.perfis.find(p => p.id === id); if (!novo || id === V.perfilAtivo || !config) return;
  avisar(`Perfil ${novo.nome}`); // as teclas do outro perfil aparecem no toque. Se o Mac recusar, voltam e o aviso vira o erro
  await salvar(base => { if (!base.perfis.some(p => p.id === id)) throw new Error('Esse perfil não existe mais no Mac.'); base.perfilAtivo = id; return base }, () => { sobrepor.perfilAtivo = id; sobrepor.ate = performance.now() + JANELA_OTM });
}
tela.addEventListener('click', ev => {
  if (!ev.target.isConnected || !V || V.carregando) return;
  const lp = $('#lista-perfis'), pf = ev.target.closest('[data-perfil]');
  if (pf) return ativarPerfil(pf.dataset.perfil);
  if (ev.target.closest('[data-nova-tecla]')) { lp.hidden = true; return abrirEditor('nova') }
  if (!lp.hidden && !ev.target.closest('#lista-perfis, .tecla.menu')) { lp.hidden = true; return }
  const eb = ev.target.closest('[data-esconder]'); if (eb && organizando) { ev.stopPropagation(); return trocarBloco(eb.dataset.esconder, false) }
  const mb = ev.target.closest('[data-mostrar]'); if (mb) return trocarBloco(mb.dataset.mostrar, true);
  if (ev.target.closest('#f-relogio')) return fecharRelogio();
  const m = ev.target.closest('[data-midia]'); if (m) return midia(m.dataset.midia);
  if (!organizando && ev.target.closest('[data-abrir-spotify]') && V.spotify) return abrirPlayer();
  if (!organizando && ev.target.closest('.relogio, .data-linha')) return abrirRelogio();
  const pn = ev.target.closest('[data-painel]'); if (pn && !organizando) return abrirPainel(pn.dataset.painel);
  if (ev.target.closest('[data-fechar]') || ev.target.id === 'veu') return fecharFolha();
  const t = ev.target.closest('.tecla');
  // o toque de verdade já agiu no pointerup. Clique sem ponteiro (teclado, leitor de tela) age aqui
  if (t && ev.detail === 0) return organizando ? abrirEditor(t.dataset.id === 'menu' ? 'nova' : t.dataset.id) : executar(t.dataset.id);
  if (organizando && !t && !ev.target.closest('.barra-organizar, .folha, .veu, #aviso')) sairOrganizar();
});
addEventListener('keydown', e => { if (e.key === 'Escape') { fecharRelogio(); fecharFolha(); sairOrganizar() } });

/* ---------- gravar no Mac: o iPhone só grava pela config inteira (PUT /api/config) ---------- */
/* Cada gravação lê a config de agora do Mac, muda só o que é dela e devolve inteira. Uma de cada vez,
   para duas mudanças seguidas nunca pisarem uma na outra. Erro do Mac (validação) vai para o aviso. */
let fila = Promise.resolve(), pendentes = 0, falhasGravar = 0;
let geracaoConfig = 0; // sobe a cada gravação: leitura de config que saiu antes dela chega velha e é descartada
function gravar(mudar) {
  pendentes++; geracaoConfig++;
  const feita = fila.then(async () => {
    try {
      const nova = mudar(structuredClone(await canal.config()));
      const resp = await canal.gravarConfig(nova);
      config = Array.isArray(resp?.perfis) ? resp : nova;
      return true;
    } catch (e) { falhasGravar++; tratarErro(e); return false } finally { pendentes--; geracaoConfig++ }
  });
  return fila = feita;
}
/* local: a mudança já aparece na tela enquanto o Mac responde. Se o Mac recusar, a tela volta ao que estava */
async function salvar(mudar, local) {
  const antes = config;
  if (local) { local(); V = vistaReal(); atualizar() }
  const ok = await gravar(mudar);
  if (!ok) { try { config = await canal.config() } catch { config = antes } if (!pendentes) sobrepor = {} }
  // aceitou: a sobreposição fica até o estado do Mac mostrar o mesmo (conferirSobrepor), senão a tela piscaria de volta ao valor velho
  V = vistaReal(); atualizar()
  atualizarJa(); // o estado novo (perfil, acesas) chega depois, sem segurar quem chamou
  return ok;
}
const perfilVisto = c => c?.perfis?.find(p => p.id === V.perfilAtivo);

/* ---------- organizar: segurar, arrastar, trocar ---------- */
const ESCONDE_ORDEM = ['spotify', 'sessoes', 'uso'];
let escondidosHTML = '';
// blocos escondidos aparecem na barra do modo organizar, com o "+" para voltar
function pintarEscondidos() {
  const html = ESCONDE_ORDEM.filter(b => V.blocos[b] === false).map(b => `<button class="chip-volta" data-mostrar="${b}">${SVG.mais}${ESCONDE[b]}</button>`).join('');
  if (html !== escondidosHTML) { escondidosHTML = html; $('#escondidos').innerHTML = html }
}
function trocarBloco(b, on) {
  salvar(base => { base.blocos = { ...BLOCOS_PADRAO, ...base.blocos, [b]: on }; return base }, () => { sobrepor.blocos = { ...sobrepor.blocos, [b]: on }; sobrepor.ate = performance.now() + JANELA_OTM });
}
function entrarOrganizar() { organizando = true; $('#lista-perfis').hidden = true; tela.classList.add('organizando') }
/* só sai depois do Mac aceitar tudo que estava a caminho. Se ele recusar, fica para a pessoa ver o aviso */
async function sairOrganizar() {
  if (!organizando) return;
  if (pendentes) { const n = falhasGravar; await fila; if (falhasGravar !== n) return }
  organizando = false; tela.classList.remove('organizando');
}
$('#b-pronto').onclick = sairOrganizar;

let gesto = null;
tela.addEventListener('pointerdown', ev => {
  const t = ev.target.closest('.tecla'); if (!t || ev.button || !config || !V || V.carregando || tela.classList.contains('com-folha')) return;
  gesto = { el: t, id: t.dataset.id, x: ev.clientX, y: ev.clientY, arrastando: false, segurou: false, antes: config };
  t.classList.add('apertada');
  if (!organizando) {
    t.classList.add('segurando');
    gesto.timer = setTimeout(() => { gesto.segurou = true; t.classList.remove('segurando', 'apertada'); entrarOrganizar() }, 500);
  }
});
// pointermove/up/cancel no documento: soltar o dedo fora da tela (faixa preta, borda do aparelho) também termina o arrasto.
// Só na tela, o fantasma da tecla e a tecla apagada (25%) ficavam para sempre
document.addEventListener('pointermove', ev => {
  if (!gesto) return;
  const longe = Math.hypot(ev.clientX - gesto.x, ev.clientY - gesto.y) > 8;
  if (!organizando && !gesto.segurou) { if (longe) cancelarGesto(); return }
  if (gesto.id === 'menu') return;
  if (!gesto.arrastando && longe) comecarArrasto(ev);
  if (gesto.arrastando) moverArrasto(ev);
});
document.addEventListener('pointerup', () => {
  if (!gesto) return;
  const g = gesto; clearTimeout(g.timer); g.el.classList.remove('segurando', 'apertada');
  if (g.arrastando) return soltarArrasto();
  gesto = null;
  if (g.segurou) return;
  if (!$('#lista-perfis').hidden) { $('#lista-perfis').hidden = true; return } // toque fora só fecha a folha do Menu
  if (organizando) return abrirEditor(g.id === 'menu' ? 'nova' : g.id);
  executar(g.id);
});
tela.addEventListener('dragstart', e => e.preventDefault());
document.addEventListener('pointercancel', () => { if (gesto?.arrastando) soltarArrasto(); cancelarGesto() });
function cancelarGesto() { if (!gesto) return; clearTimeout(gesto.timer); gesto.el.classList.remove('segurando', 'apertada'); gesto = null }
// rede de segurança: nenhum rastro de arrasto sobrevive ao fim do gesto (fantasma, tecla apagada, tecla apertada)
function limparRastroDeArrasto() { $$('.fantasma').forEach(f => f.remove()); fantasma = null; $$('.tecla.arrastando, .tecla.apertada, .tecla.segurando').forEach(t => t.classList.remove('arrastando', 'apertada', 'segurando')) }

let fantasma = null;
function comecarArrasto(ev) {
  gesto.arrastando = true;
  const b = gesto.el.getBoundingClientRect(), { k } = escalaTela();
  fantasma = gesto.el.cloneNode(true); fantasma.classList.add('fantasma'); fantasma.classList.remove('apertada');
  Object.assign(fantasma.style, { width: b.width / k + 'px', height: b.height / k + 'px', left: '0', top: '0' });
  gesto.dx = (ev.clientX - b.left) / k; gesto.dy = (ev.clientY - b.top) / k;
  tela.appendChild(fantasma); gesto.el.classList.add('arrastando');
  moverArrasto(ev);
}
function moverArrasto(ev) {
  const { r, k } = escalaTela();
  fantasma.style.translate = `${(ev.clientX - r.left) / k - gesto.dx}px ${(ev.clientY - r.top) / k - gesto.dy}px`;
  const alvo = document.elementFromPoint(ev.clientX, ev.clientY)?.closest('.tecla:not(.menu)');
  if (!alvo || alvo.dataset.id === gesto.id) return;
  const nova = structuredClone(config), lista = perfilVisto(nova).teclas;
  const de = lista.findIndex(t => t.id === gesto.id), para = lista.findIndex(t => t.id === alvo.dataset.id);
  if (de < 0 || para < 0) return;
  lista.splice(para, 0, lista.splice(de, 1)[0]);
  config = nova; V = vistaReal(); renderTeclas();
  gesto.el = $(`.tecla[data-id="${CSS.escape(gesto.id)}"]`); gesto.el.classList.add('arrastando');
}
function renderTeclas() {
  const t = $('#teclas'), x = $('.paginas', t)?.scrollLeft || 0;
  t.innerHTML = teclasHTML(porPagina());
  const pg = $('.paginas', t); if (pg) pg.scrollLeft = x;
  ligarCarrossel(); ultima.layout = chaveLayout(); ultima.teclas = chaveTeclas();
}
async function soltarArrasto() {
  const g = gesto; gesto = null;
  limparRastroDeArrasto(); renderTeclas();
  const ordem = V.teclas.map(t => t.id), pid = V.perfilAtivo;
  if (ordem.join() === perfilVisto(g.antes).teclas.map(t => t.id).join()) return; // soltou onde estava
  const antes = g.antes;
  // a tela já mostra a ordem nova. O Mac recebe a config inteira com as teclas nessa ordem
  const ok = await gravar(base => {
    const p = base.perfis.find(x => x.id === pid); if (!p) throw new Error('Esse perfil não existe mais no Mac.');
    const por = new Map(p.teclas.map(t => [t.id, t]));
    p.teclas = [...ordem.filter(id => por.has(id)).map(id => por.get(id)), ...p.teclas.filter(t => !ordem.includes(t.id))];
    return base;
  });
  if (!ok) { try { config = await canal.config() } catch { config = antes } V = vistaReal(); atualizar() }
  await atualizarJa();
}

/* ---------- folhas e editor de tecla ---------- */
let folhaAberta = null;
// a tela nunca rola: foco num campo da folha (aberta ou ainda saindo) faria o navegador deslocar tudo
tela.addEventListener('scroll', () => { tela.scrollTop = 0; tela.scrollLeft = 0 });
function abrirFolha(id) { folhaAberta = $(id); folhaAberta.classList.add('aberta'); tela.classList.add('com-folha') }
function fecharFolha() { if (folhaAberta?.contains(document.activeElement)) document.activeElement.blur(); folhaAberta?.classList.remove('aberta'); folhaAberta = null; tela.classList.remove('com-folha') }
$$('[data-fechar]').forEach(b => { if (!b.textContent.trim()) b.innerHTML = SVG.x });

/* Puxar de cima para baixo fecha a tela aberta (folhas e relógio). A tela acompanha o dedo e, se soltar cedo, volta.
   Não rouba o gesto de lista que ainda rola para cima, de barra arrastável nem de campo de texto */
let puxar = null, puxouAte = 0;
const LONGE_PUXAR = .25, RAPIDO_PUXAR = .5; // fração da altura, e px por ms
const telaAberta = () => $('#f-relogio.aberta') || folhaAberta;
function rolaParaCima(el, topo) { // algum pai ainda tem rolagem a desfazer? Então o gesto é dele
  for (; el && el !== topo; el = el.parentElement) if (el.scrollHeight > el.clientHeight + 1 && el.scrollTop > 0 && getComputedStyle(el).overflowY !== 'visible') return true;
  return false;
}
function devolverTela(f, fechar) {
  f.style.transition = ''; f.style.translate = '';
  if (fechar) { if (f.id === 'f-relogio') fecharRelogio(); else fecharFolha() }
}
tela.addEventListener('touchstart', e => {
  puxar = null;
  const f = telaAberta(); if (!f || e.touches.length !== 1 || !f.contains(e.target)) return;
  if (e.target.closest('input, textarea, select, .progresso, .volume, .trilho') || rolaParaCima(e.target, f)) return;
  const t = e.touches[0]; puxar = { f, x: t.clientX, y: t.clientY, t: e.timeStamp, dy: 0, seguindo: false };
}, { passive: true });
tela.addEventListener('touchmove', e => {
  if (!puxar) return;
  const t = e.touches[0], dx = t.clientX - puxar.x, dy = t.clientY - puxar.y, f = puxar.f;
  if (!puxar.seguindo) {
    if (Math.abs(dx) > 10 && Math.abs(dx) >= Math.abs(dy) || dy < -10) { puxar = null; return } // para o lado ou para cima: não é fechar
    // No iPhone a rolagem nativa começa nos primeiros pixels e, depois dela, o touchmove não é mais cancelável: o gesto é cancelado
    // já no primeiro movimento para baixo (a lista está no topo, então não há o que rolar para esse lado)
    if (dy > 0 && dy > Math.abs(dx) && e.cancelable) e.preventDefault();
    if (dy < 10 || dy < Math.abs(dx) * 1.5) return;
    puxar.seguindo = true; f.style.transition = 'none';
  }
  puxar.dy = Math.max(0, dy); f.style.translate = `0 ${puxar.dy / escalaTela().k}px`;
  e.preventDefault();
}, { passive: false });
function soltarPuxada(e, cancelado) {
  const p = puxar; puxar = null; if (!p?.seguindo) return;
  puxouAte = e.timeStamp + 400;
  const alto = p.f.getBoundingClientRect().height, rapido = !cancelado && p.dy > 30 && p.dy / Math.max(1, e.timeStamp - p.t) > RAPIDO_PUXAR;
  const fechar = !cancelado && (p.dy > alto * LONGE_PUXAR || rapido);
  if (fechar && p.f.id === 'f-relogio') { // o relógio some em fade: desce junto até acabar o fade
    p.f.style.transition = 'translate var(--mov-sai-padrao) var(--curva-sai), opacity var(--mov-sai-padrao) var(--curva-sai)'; p.f.style.translate = `0 ${alto / escalaTela().k}px`;
    fecharRelogio(); setTimeout(() => devolverTela(p.f, false), msCss('--mov-sai-padrao') + 60); return;
  }
  devolverTela(p.f, fechar);
}
tela.addEventListener('touchend', e => soltarPuxada(e, false));
tela.addEventListener('touchcancel', e => soltarPuxada(e, true));
// o toque que terminou a puxada não aperta o que estava embaixo do dedo
tela.addEventListener('click', e => { if (performance.now() < puxouAte) { e.stopPropagation(); e.preventDefault() } }, true);

let editando = null, rasc = null;
const TIPOS = {
  // a lista vem dos apps instalados no Mac de quem usa, com busca, ícone e as ações de cada app (apps.js). Mac antigo cai na lista curta (APPS)
  app: { rot: '', html: () => appEditorHTML() },
  // PENDENCIA fase 2: a lista de Atalhos do Mac também espera uma rota. Até lá o nome é digitado
  atalho: { rot: 'Atalho da Apple', html: v => `<input id="ed-valor" value="${esc(v)}" spellcheck="false"><span class="ajuda">Digite o nome do atalho como está no app Atalhos do Mac.</span>` },
  tecla: { rot: 'Combinação de teclas', html: v => `<div class="tecla-gravada">${(v || '').split('+').filter(Boolean).map(k => `<kbd>${esc({ ctrl: 'control', opt: 'option', cmd: 'command' }[k] || k.toUpperCase())}</kbd>`).join('') || '<span class="ajuda">Nenhuma combinação ainda</span>'}</div><button class="btn secundario pequeno" type="button" style="justify-self:start" id="ed-gravar">Gravar de novo</button>` },
  comando: { rot: 'Comando de shell', html: v => `<input id="ed-valor" value="${esc(v)}" spellcheck="false" autocapitalize="off"><span class="ajuda">Roda no Mac com zsh.</span>` },
};
function abrirEditor(id) {
  const t = id === 'nova' ? { nome: '', tipo: 'app', valor: '', icone: '' } : V.teclas.find(x => x.id === id);
  if (!t) return;
  editando = id; rasc = { ...t }; iniciarEditorApp(id === 'nova');
  $('#ed-titulo').textContent = id === 'nova' ? 'Nova tecla' : 'Editar tecla';
  $('#ed-nome').value = t.nome;
  $('#ed-excluir').hidden = id === 'nova';
  pintarTipo(); abrirFolha('#f-editor');
}
function pintarTipo() {
  $$('#ed-tipo button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tipo === rasc.tipo)));
  $('#ed-acao').innerHTML = `${TIPOS[rasc.tipo].rot ? `<span class="rotulo">${TIPOS[rasc.tipo].rot}</span>` : ''}${TIPOS[rasc.tipo].html(rasc.valor)}`;
  $('#ed-campo-icone').hidden = rasc.tipo === 'app';
  const opcoes = [...APPS.map(a => a.nome), 'svg:tela', 'svg:terminal', 'svg:raio', 'svg:microfone'];
  $('#ed-icones').innerHTML = opcoes.map(o => `<button aria-label="${o.replace('svg:', '')}" aria-pressed="${rasc.icone === o}" data-ic="${o}">${o.startsWith('svg:') ? SVG[o.slice(4)] : `<img src="${icApp(o)}" alt="">`}</button>`).join('');
}
$('#ed-tipo').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; rasc.tipo = b.dataset.tipo; rasc.valor = ''; delete rasc.acao; iniciarEditorApp(editando === 'nova'); pintarTipo() }); // só tecla de app tem ação
$('#ed-acao').addEventListener('click', e => {
  const a = e.target.closest('[data-app]'); if (a) { rasc.valor = a.dataset.app; rasc.icone = a.dataset.app; if (!$('#ed-nome').value || APPS.some(x => x.nome === $('#ed-nome').value)) $('#ed-nome').value = a.dataset.app; pintarTipo(); return }
  if (e.target.id === 'ed-gravar') avisar('Grave a combinação no editor de teclas do Mac');
});
$('#ed-icones').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; rasc.icone = b.dataset.ic; pintarTipo() });
/* Salvar e Excluir são otimistas como o resto: o editor fecha e a tecla muda no toque. Se o Mac recusar, a tela volta
   ao que era e o editor reabre com o que a pessoa tinha digitado, junto com o motivo no aviso. */
const mudarTecla = (pid, fn) => base => { const p = base.perfis.find(x => x.id === pid); if (!p) throw new Error('Esse perfil não existe mais no Mac.'); fn(p.teclas); return base };
const localTecla = (pid, fn) => () => { try { config = mudarTecla(pid, fn)(structuredClone(config)) } catch {} };
function reabrirEditor(id, rascunho) { if (folhaAberta) return; abrirEditor(id); rasc = { ...rascunho }; $('#ed-nome').value = rascunho.nome; pintarTipo() }
$('#ed-salvar').onclick = async () => {
  const nome = $('#ed-nome').value.trim();
  if (!nome) { avisar('Dê um nome para a tecla', { erro: true }); $('#ed-nome').focus(); return }
  const v = $('#ed-valor'); if (v) rasc.valor = v.value.trim();
  if (!rasc.valor) { avisar('Escolha o que a tecla faz', { erro: true }); return }
  const falta = faltaNaAcao(); if (falta) { avisar(falta, { erro: true }); return }
  const feita = { ...rasc, nome }, id = editando, pid = V.perfilAtivo;
  if (!feita.icone) delete feita.icone;
  const novaId = 't' + Date.now().toString(36); // o mesmo id na tela e no Mac
  const mudar = fn => mudarTecla(pid, fn);
  const aplicar = teclas => {
    if (id === 'nova') teclas.push({ ...feita, id: novaId });
    else { const i = teclas.findIndex(t => t.id === id); if (i < 0) throw new Error('Essa tecla não existe mais no Mac.'); teclas[i] = { ...teclas[i], ...feita, id }; if (!feita.acao) delete teclas[i].acao }
  };
  fecharFolha(); avisar('Tecla salva');
  const ok = await salvar(mudar(aplicar), localTecla(pid, aplicar));
  if (!ok) reabrirEditor(id, feita);
};
$('#ed-excluir').onclick = async () => {
  const id = editando, pid = V.perfilAtivo, lista = V.teclas, i = lista.findIndex(t => t.id === id), velha = lista[i];
  if (!velha) return;
  const tirar = teclas => { const j = teclas.findIndex(t => t.id === id); if (j < 0) throw new Error('Essa tecla não existe mais no Mac.'); teclas.splice(j, 1) };
  const devolver = teclas => { if (!teclas.some(t => t.id === id)) teclas.splice(Math.min(i, teclas.length), 0, velha) };
  fecharFolha();
  avisar(`"${velha.nome}" excluída`, { desfazer: () => salvar(mudarTecla(pid, devolver), localTecla(pid, devolver)) });
  const ok = await salvar(mudarTecla(pid, tirar), localTecla(pid, tirar));
  if (!ok) reabrirEditor(id, velha);
};

/* ---------- tamanho: a tela é desenhada no 15 Pro Max e escala para o aparelho ---------- */
function posicionar() {
  const nova = innerWidth >= innerHeight ? 'horizontal' : 'vertical', h = nova === 'horizontal';
  $('#moldura').className = 'moldura ' + nova;
  $('#moldura').style.setProperty('--escala', Math.min(innerWidth / (h ? 932 : 430), innerHeight / (h ? 430 : 932)));
  const mudou = nova !== posicao; posicao = nova; return mudou;
}
addEventListener('resize', () => { if (posicionar() && V) atualizar() });

/* ---------- o laço: estado a cada 1 s, um pedido de cada vez ---------- */
function pintarGlobal() {
  tela.classList.toggle('offline', offline && !semAcesso);
  tela.classList.toggle('sem-acesso', semAcesso);
  const nome = estado?.nomeMac || lerGuardado('deck-nome-mac'); $('#nome-mac').textContent = nome || 'Seu Mac';
}
const precisaConfig = e => !pendentes && !gesto?.arrastando && (!config || config.perfilAtivo !== e.perfilAtivo || config.comp !== e.comp || config.nomeMac !== e.nomeMac
  || JSON.stringify(config.blocos) !== JSON.stringify(e.blocos) || ++tiquesConfig % 5 === 0); // e de vez em quando: teclas editadas no Mac. Nunca por cima de uma gravação a caminho
let esqueletoDesde = 0, esqueletoTimer = 0, configFalhou = false;
let ultimoOk = performance.now(); // a última resposta boa do Mac
async function passo() {
  try {
    const e = await canal.estado();
    estado = e; falhas = 0; ultimoOk = performance.now(); offline = false; semAcesso = false;
    if (e.nomeMac) guardar('deck-nome-mac', e.nomeMac);
    if (precisaConfig(e)) {
      const gen = geracaoConfig;
      try { const nova = await canal.config(); if (gen === geracaoConfig && !pendentes) config = nova; configFalhou = false }
      catch (er) {
        if (er.status === 401) throw er;
        // sem config não há teclas: avisa uma vez e continua tentando a cada passo
        if (!config && !configFalhou) { configFalhou = true; avisar('Não consegui ler as teclas do Mac. Tentando de novo.', { erro: true }) }
      }
    }
    pintarGlobal(); mostrarVista();
  } catch (er) {
    if (er.status === 401) semAcesso = true;
    // Com o painel já aberto, o Mac só "sumiu" depois de várias falhas seguidas E de um tempo sem resposta boa: um tropeço
    // (pedido lento, o Mac reiniciando) não fecha a tela. Na primeira abertura não há o que proteger, e a falha já fecha.
    else { falhas++; if (!estado || (falhas >= AJUSTES.falhasParaOffline && performance.now() - ultimoOk > AJUSTES.msParaOffline)
      || (falhas >= AJUSTES.falhasTravado && performance.now() - ultimoOk > AJUSTES.msTravado)) offline = true }
    pintarGlobal();
  }
}
function mostrarVista() {
  // o esqueleto, depois de aparecer, fica pelo menos 400 ms (resposta que chega logo depois não pisca a tela)
  const resta = esqueletoDesde ? esqueletoDesde + 400 - performance.now() : 0;
  if (resta > 0) { clearTimeout(esqueletoTimer); esqueletoTimer = setTimeout(mostrarVista, resta); return }
  const eraEsqueleto = !!V?.carregando;
  V = vistaReal(); guardarForma(); esqueletoDesde = 0;
  atualizar();
  if (eraEsqueleto) $('#conteudo').animate([{ opacity: 0 }, { opacity: 1 }], { duration: parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--mov-rapido')) || 180 });
}
let emVoo = null, acordar = null, lacoAtivo = false;
const buscar = () => emVoo ??= passo().finally(() => { emVoo = null }); // nunca dois pedidos de estado ao mesmo tempo
async function atualizarJa() { if (emVoo) await emVoo; return buscar() }
async function laco() {
  if (lacoAtivo) return; lacoAtivo = true;
  try { await rodarLaco() } finally { lacoAtivo = false }
}
// o pareamento pela página (pareamento.js) deu um código novo: o laço parou no 401 e volta a andar
function retomarAposParear() { semAcesso = false; falhas = 0; ultimoOk = performance.now(); pintarGlobal(); laco() }
async function rodarLaco() {
  for (;;) {
    const t0 = performance.now();
    await buscar();
    if (semAcesso) return; // código inválido: sem QR novo nada mais vale
    await new Promise(r => { const t = setTimeout(r, Math.max(0, AJUSTES.intervalo - (performance.now() - t0))); acordar = () => { clearTimeout(t); r() } });
  }
}
document.addEventListener('visibilitychange', () => { if (!document.hidden && !semAcesso) acordar?.() });

// carregando: nada nos primeiros 200 ms, depois o esqueleto com a forma da última visita
posicionar();
setTimeout(() => {
  if (V || offline || semAcesso) return;
  V = vistaEsqueleto(); esqueletoDesde = performance.now(); atualizar();
}, 200);
pintarGlobal();
laco();
