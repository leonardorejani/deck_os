/* Protótipo do Deck: dados de mentira, comportamento de verdade. Dados comuns em dados.js. */

const E = { comp: 'a', posicao: 'horizontal', mac: 'on', spotify: 'tocando', agenda: 'normal', sessoes: '5', qtd: 'poucas' };
// o Mac configura e o iPhone mostra: começa da última config gravada e se redesenha quando ela muda
function aplicarConfig(c) {
  aplicarConfigComum(c); teclas = perfilDe(perfilAtivo).teclas; if (c?.comp) E.comp = c.comp;
  if (c?.blocos) E.spotify = c.blocos.spotify === false ? 'fechado' : E.spotify === 'fechado' ? 'tocando' : E.spotify;
}
const gravar = () => { perfilDe(perfilAtivo).teclas = teclas; publicar(configAtual(E.comp)) };
aplicarConfig(lerConfig());
aoMudarConfig(c => { aplicarConfig(c); render() });

const WHATS = [
  { nome: 'Ministério de Louvor', grupo: true, hora: '10:21', msgs: [['Carla', 'Ensaio confirmado quinta 20h?'], ['Pedro', 'Mandei a setlist no drive'], ['Carla', 'Quem leva o cabo P10?']], qtd: 12 },
  { nome: 'Mãe', hora: '09:58', msgs: [['', 'Vem almoçar domingo?'], ['', 'Traz a Bia também']], qtd: 2 },
  { nome: 'Equipe do app', grupo: true, hora: '09:40', msgs: [['Rafael', 'Subi o build novo'], ['Lucas', 'Testei no Android, ok']], qtd: 5 },
  { nome: 'Pastor João', hora: 'ontem', msgs: [['', 'Leo, sobre domingo...'], ['', 'Me liga quando puder']], qtd: 3 },
  { nome: 'Rafael', hora: 'ontem', msgs: [['', 'Consegue ver o PR hoje?']], qtd: 1 },
];
const SESSOES = [
  { nome: 'convite novos usuarios', proj: 'app_web', q: 'Salvar o TXT de verificação do domínio no DNS?', ha: 'há 5 min', min: 5 },
  { nome: 'EXPORTAR_VIDEO_1080', proj: 'video', q: '1080p medido, aguarda decisão sobre times, PR e vídeo.', ha: 'há 13 h', min: 780 },
  { nome: 'CI_RUNNER_02', proj: 'infra', q: 'Você aprova o plano do runner 02 (e2e do ci-1)?', ha: 'há 14 h', min: 840 },
  { nome: 'instala repo', proj: 'app_web', q: 'Registro essa conclusão na memória do projeto?', ha: 'há 16 h', min: 960 },
  { nome: 'podio ranking pontuação', proj: 'app_web', q: 'Posso fazer o commit e abrir o PR?', ha: 'há 4 dias', min: 5760 },
];

/* agenda de mentira: semanais + avulsos por dia do mês */
const COR = { azul: '#60A5FA', verde: '#5FD49B', amarelo: '#E8B95B', rosa: '#F09090' };
function eventosDo(d) {
  const ev = [], dow = d.getDay(), dia = d.getDate();
  if (dow === 2) ev.push({ h: '10:30', t: 'Reunião de produto', cor: COR.azul, cal: 'Trabalho', local: 'Google Meet' });
  if (dow === 4) ev.push({ h: '20:00', t: 'Ensaio do louvor', cor: COR.verde, cal: 'Louvor', local: 'Templo' });
  if (dow === 0) ev.push({ h: '09:00', t: 'Escola dominical', cor: COR.amarelo, cal: 'Igreja', local: 'Sala 2' }, { h: '19:00', t: 'Culto', cor: COR.amarelo, cal: 'Igreja', local: 'Templo' });
  const avulsos = { 3: ['14:00', 'Revisão do projeto', COR.azul], 10: ['16:00', 'Dentista', COR.rosa], 12: ['12:30', 'Almoço com Rafael', COR.verde], 15: ['', 'Aniversário da Ana', COR.rosa], 21: ['15:00', 'Gravação do podcast', COR.azul], 27: ['18:00', 'Entrega do cliente', COR.azul] };
  if (avulsos[dia]) { const [h, t, cor] = avulsos[dia]; ev.push({ h: h || 'dia todo', t, cor, cal: cor === COR.rosa ? 'Pessoal' : 'Trabalho' }) }
  return ev.sort((a, b) => a.h.localeCompare(b.h));
}
function proximosEventos() {
  const agora = new Date(), lista = [];
  for (let i = 0; i < 3 && lista.length < 4; i++) {
    const d = new Date(agora); d.setDate(d.getDate() + i);
    for (const e of eventosDo(d)) {
      const [hh, mm] = e.h.split(':').map(Number);
      const quando = new Date(d); quando.setHours(hh || 0, mm || 0, 0, 0);
      if (i === 0 && e.h !== 'dia todo' && quando < agora) continue;
      const min = Math.round((quando - agora) / 60000);
      const em = i === 0 ? (min < 60 ? `em ${min} min` : 'hoje') : i === 1 ? 'amanhã' : d.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '');
      lista.push({ ...e, em });
    }
  }
  return lista;
}

const iniciais = n => n.split(' ').filter(Boolean).slice(0, 2).map(p => p[0]).join('').toUpperCase();
const totalWhats = () => WHATS.reduce((s, c) => s + c.qtd, 0);

/* ---------- blocos ---------- */
// Menu: a tecla isolada abre uma folha pequena com "Nova tecla" e a troca de perfil
function abrirMenu(el) {
  const r = el.getBoundingClientRect(), t = tela.getBoundingClientRect(), k = t.width / tela.offsetWidth;
  const l = $('#lista-perfis');
  l.innerHTML = `<button data-nova-tecla>Nova tecla</button><span class="rotulo-lista">Perfil</span><div role="listbox" aria-label="Perfis">${perfis.map(p => `<button role="option" data-perfil="${p.id}" aria-selected="${p.id === perfilAtivo}">${esc(p.nome)}<small>${p.teclas.length} teclas</small></button>`).join('')}</div>${perfis.length > 1 ? '<span class="dica-perfis">Crie e edite perfis no Mac</span>' : ''}`;
  l.hidden = false;
  // ancorada na tecla: abre para cima, ou para baixo se faltar espaço. Sem espaço nos dois (B deitado), abre ao lado
  const w = l.offsetWidth, h = l.offsetHeight, H = tela.offsetHeight, W = tela.offsetWidth;
  const cx = (r.left + r.width / 2 - t.left) / k, cima = (r.top - t.top) / k, baixo = (r.bottom - t.top) / k;
  const pos = { left: Math.max(8, Math.min(W - w - 8, cx - w / 2)), top: cima - 8 - h };
  if (pos.top < 8) pos.top = baixo + 8;
  if (pos.top + h > H - 8) Object.assign(pos, { left: Math.max(8, (r.left - t.left) / k - 8 - w), top: Math.max(8, Math.min(H - h - 8, (cima + baixo) / 2 - h / 2)) });
  l.style.left = pos.left + 'px'; l.style.top = pos.top + 'px';
}
function ativarPerfil(id) {
  perfilDe(perfilAtivo).teclas = teclas; perfilAtivo = id; teclas = perfilDe(id).teclas;
  $('#lista-perfis').hidden = true; render(); gravar(); avisar(`Perfil ${perfilDe(id).nome}`);
}
const relogioHTML = () => `<div class="relogio" aria-label="Hora"><div class="placa" data-i="0"></div><div class="placa" data-i="1"></div><div class="dois-pontos" aria-hidden="true"><i></i><i></i></div><div class="placa" data-i="2"></div><div class="placa" data-i="3"></div></div><div class="data-linha"><div class="data" id="data"></div></div>`;
const nivel = p => p == null ? '' : p >= 90 ? 'cheio' : p >= 70 ? 'alto' : '';
const medidor = (rot, p) => `<div class="medidor ${nivel(p)}" aria-label="${rot}: ${p == null ? 'sem medição' : p + '%'}"><span class="trilho"><i style="width:${p ?? 0}%"></i></span><b>${p == null ? '-' : p + '%'}</b></div>`;
function usoCartao() {
  if (!usoVisivel().length) return '';
  return `<div class="cartao uso depende">${esconder('uso')}<div class="cartao-titulo"><span>Uso da semana</span><span class="renova-tit">renova</span></div>
    ${usoVisivel().map(u => `<div class="uso-linha"><span class="uso-nome">${icServico(u.nome)}<span>${u.nome} <small>${esc(u.apelido || u.conta)}</small></span></span>${medidor('semana', u.sem)}<span class="renova" aria-label="renova ${renovaEm(u.renova, true)}">${renovaEm(u.renova, true)}</span></div>`).join('')}</div>`;
}
function usoTira() {
  if (!usoVisivel().length) return ''; // nenhuma conta configurada: a faixa some
  return `<div class="uso-tira depende">${esconder('uso')}${usoVisivel().map(u => { const p = u.sem; return `<span class="${nivel(p)}" aria-label="${u.nome} ${u.conta}: ${p}%">${icServico(u.nome)}<span class="nome-u">${esc(u.apelido || (u.nome === 'Claude' ? u.conta : u.nome))}</span> <span class="mini"><i style="width:${p}%"></i></span><b>${p}%</b></span>` }).join('')}</div>`;
}
function playerHTML() {
  const t = E.spotify === 'tocando';
  // cores da capa: no app de verdade o Mac tira as duas cores dominantes da arte e manda junto
  return `<div class="cartao player depende ${t ? '' : 'pausado'}" style="--capa-1: rgb(150 48 42 / .55); --capa-2: rgb(40 90 100 / .35)">${esconder('spotify')}
    <img class="capa" data-abrir-spotify src="icones/deck.png" alt="Capa: Faixa de Exemplo" onerror="this.removeAttribute('src')">
    <div class="info"><div class="titulos" data-abrir-spotify><div class="faixa">Faixa de Exemplo</div><div class="artista">${icServico('Spotify')}Artista Exemplo</div></div>
      <div class="midia"><button aria-label="Anterior" data-midia="anterior">${SVG.anterior}</button><button class="tocar ${t ? '' : 'play'}" aria-label="${t ? 'Pausar' : 'Tocar'}" data-midia="tocar">${t ? SVG.pausar : SVG.tocar}</button><button aria-label="Próxima" data-midia="proxima">${SVG.proxima}</button></div>
      <div class="progresso" data-total="221"><span class="decorrido">2:12</span><span class="trilho" role="slider" aria-label="Posição da música" aria-valuemin="0" aria-valuemax="221" aria-valuenow="132"><i style="width:60%"></i></span><span>3:41</span></div>
    </div></div>`;
}
const ESCONDE = { spotify: 'Spotify', sessoes: 'Sessões', uso: 'Uso das IAs' };
// "−" de esconder o bloco, só no modo organizar. span: o cartão de sessões já é um botão
const esconder = b => `<span class="esconder-bloco" role="button" tabindex="0" data-esconder="${b}" aria-label="Esconder ${ESCONDE[b]}">${SVG.menos}</span>`;
function sessoesHTML() {
  if (BLOCOS.sessoes === false) return '';
  const n = Number(E.sessoes);
  const corpo = n === 0 ? `<div class="vazio-rico"><img src="icones/claude.png" alt=""><div><strong>Tudo respondido</strong><span>Nenhuma sessão do Claude esperando você.</span></div></div>`
    : SESSOES.slice(0, n).map(s => `<div class="sessao"><b>${esc(s.nome)}</b><span>${esc(s.q)}</span><time class="${s.min >= 60 ? 'velha' : ''}">${s.ha.replace('há ', '')}</time></div>`).join('');
  // o bloco inteiro é um alvo só: linha pequena demais para acertar no dedo
  return `<button class="cartao sessoes depende" data-painel="sessoes" aria-label="Sessões esperando: ${n}">${esconder('sessoes')}<div class="cartao-titulo"><span>${icServico('Claude')}Sessões esperando</span>${n ? `<span class="conta">${n}</span>` : ''}</div>${corpo}</button>`;
}
function teclaHTML(t) {
  const prox = painelDe(t) === 'calendario' && E.agenda === 'normal' ? proximosEventos()[0] : null;
  const chip = painelDe(t) === 'calendario' ? (E.agenda === 'sem' ? '<span class="selo" aria-label="Agenda sem permissão">!</span>' : prox ? `<span class="hora-tecla" aria-label="Próximo: ${esc(prox.t)} ${prox.h}">${prox.h === 'dia todo' ? 'hoje' : prox.h}</span>` : '') : '';
  const selo = painelDe(t) === 'whatsapp' ? `<span class="selo" aria-label="${totalWhats()} não lidas">${totalWhats() > 99 ? '99+' : totalWhats()}</span>` : '';
  const ligado = t.estado && t.acesa;
  return `<button class="tecla depende ${ligado ? 'acesa' : ''}" data-id="${t.id}" ${t.estado ? `aria-pressed="${!!t.acesa}"` : ''}>
    <span class="editar" aria-hidden="true">${SVG.lapis}</span>
    ${iconeHTML(t.icone)}<span class="nome">${esc(t.nome)}</span><span class="led" aria-hidden="true"></span>${selo}${chip}
    </button>`;
}
const MENU = `<button class="tecla menu depende" data-id="menu" aria-haspopup="dialog"><span class="svg">${SVG.menu}</span><span class="nome">Menu</span></button>`;
function teclasHTML(porPagina) {
  // apps no carrossel (sempre centralizados), "Menu" isolada do outro lado da divisória;
  // a divisória vira os pontinhos quando há mais de uma página
  // B deitado: a grade fica como era, com "Menu" como última tecla. A e em pé: "Menu" numa seção só dela
  const grade = E.comp === 'b' && E.posicao === 'horizontal', itens = grade ? [...teclas.map(teclaHTML), MENU] : teclas.map(teclaHTML), paginas = [];
  for (let i = 0; i < itens.length; i += porPagina) paginas.push(itens.slice(i, i + porPagina));
  if (!paginas.length) paginas.push([]);
  const divisor = paginas.length > 1
    ? `<div class="divisor com-pontos" aria-hidden="true">${paginas.map(() => '<i class="ponto"></i>').join('')}<b class="indicador"></b></div>`
    : grade ? '' : '<div class="divisor" aria-hidden="true"><i class="linha"></i></div>';
  return `<div class="carrossel"><div class="paginas">${paginas.map(p => `<div class="pagina">${p.join('')}</div>`).join('')}</div></div>${divisor}${grade ? '' : `<div class="menu-area">${MENU}</div>`}`;
}
const porPagina = () => E.comp === 'b' ? (E.posicao === 'vertical' ? 6 : 9) : E.posicao === 'horizontal' ? 5 : 6;

function render() {
  $('#moldura').className = 'moldura ' + E.posicao;
  const tela = $('#tela');
  $('#nome-mac').textContent = nomeMac;
  tela.classList.toggle('offline', E.mac === 'off');
  const vagas = porPagina();
  const sem = `${E.spotify === 'fechado' ? 'sem-musica' : ''} ${BLOCOS.sessoes === false ? 'sem-sessoes' : ''} ${usoVisivel().length ? '' : 'sem-uso'}`;
  $('#conteudo').innerHTML = E.comp === 'a'
    ? `<div class="comp-a ${sem}"><div class="topo">
        <div class="esquerda"><div class="relogio-linha">${relogioHTML()}${E.posicao === 'vertical' ? usoTira() : ''}</div>${E.posicao === 'vertical' ? '' : usoCartao()}</div>
        <div class="direita">${playerHTML()}${sessoesHTML()}</div>
      </div><div class="teclas" id="teclas">${teclasHTML(vagas)}</div></div>`
    : `<div class="comp-b ${sem}"><div class="esquerda">
        <div class="relogio-linha"><div>${relogioHTML()}</div>${usoTira()}</div>
        ${playerHTML()}${sessoesHTML()}
      </div><div class="teclas" id="teclas">${teclasHTML(vagas)}</div></div>`;
  tique(true);
  ligarCarrossel();
  ajustarEscala();
  pintarEscondidos();
  $$('.opcoes').forEach(g => $$('button', g).forEach(b => b.setAttribute('aria-pressed', String(E[g.dataset.grupo] === b.dataset.v))));
}
function renderTeclas() { const t = $('#teclas'), x = t.querySelector('.paginas')?.scrollLeft || 0; t.innerHTML = teclasHTML(porPagina()); t.querySelector('.paginas').scrollLeft = x; ligarCarrossel() }
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
  if (!comp || !ses || E.posicao === 'vertical') { render(); return }
  const k = escalaTela().k, antes = ses.getBoundingClientRect();
  const lento = matchMedia('(prefers-reduced-motion: reduce)').matches ? 1 : 1;
  const dur = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--mov-lento')) || 480;
  if (fechado) pl.animate([{ opacity: 1, transform: 'scale(1)' }, { opacity: 0, transform: 'scale(.96)' }], { duration: dur * .45, easing: 'cubic-bezier(.32,0,.67,0)' });
  setTimeout(() => {
    comp.classList.toggle('sem-musica', fechado);
    const depois = ses.getBoundingClientRect();
    ses.animate([{ transform: `translateY(${(antes.top - depois.top) / k}px)`, height: antes.height / k + 'px' }, { transform: 'none', height: depois.height / k + 'px' }], { duration: dur, easing: 'cubic-bezier(.22,1,.36,1)' });
    if (!fechado) pl.animate([{ opacity: 0, transform: 'scale(.96)' }, { opacity: 1, transform: 'scale(1)' }], { duration: dur, delay: dur * .3, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' });
  }, fechado ? dur * .45 : 0);
}

/* barra de tempo arrastável: área de toque alta, numa linha só dela, longe dos botões */
const mmss = s => Math.floor(s / 60) + ':' + String(Math.round(s % 60)).padStart(2, '0');
let scrub = null;
document.addEventListener('pointerdown', ev => {
  const tr = ev.target.closest('.progresso .trilho'); if (!tr) return;
  scrub = { tr, pr: tr.closest('.progresso') }; scrub.pr.classList.add('arrastando'); tr.setPointerCapture?.(ev.pointerId); moverScrub(ev); ev.preventDefault();
});
document.addEventListener('pointermove', ev => { if (scrub) moverScrub(ev) });
document.addEventListener('pointerup', () => { if (!scrub) return; scrub.pr.classList.remove('arrastando'); avisar('Pulou para ' + scrub.pr.querySelector('.decorrido').textContent); scrub = null });
function moverScrub(ev) {
  const r = scrub.tr.getBoundingClientRect(), f = Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)), total = +scrub.pr.dataset.total;
  scrub.tr.querySelector('i').style.width = f * 100 + '%'; scrub.pr.querySelector('.decorrido').textContent = mmss(f * total); scrub.tr.setAttribute('aria-valuenow', Math.round(f * total));
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
  const d = $('#data'); if (d) d.innerHTML = `<b>${dia}</b>, ${resto.join(', ')}`;
}
setInterval(() => tique(false), 1000);

/* ---------- aviso ---------- */
let tAviso;
function avisar(txt, { erro = false, desfazer = null } = {}) {
  const a = $('#aviso'); $('#aviso-txt').textContent = txt; a.classList.toggle('erro', erro);
  const b = $('#aviso-acao'); b.hidden = !desfazer; b.onclick = () => { desfazer(); a.classList.remove('visivel') };
  a.classList.add('visivel'); clearTimeout(tAviso); tAviso = setTimeout(() => a.classList.remove('visivel'), desfazer ? 5000 : 3000);
}

/* ---------- toque, segurar, organizar, arrastar ---------- */
const tela = $('#tela');
let gesto = null, organizando = false;
function escalaTela() { const r = tela.getBoundingClientRect(); return { r, k: r.width / tela.offsetWidth } }
// blocos escondidos aparecem na barra do modo organizar, com o "+" para voltar
function pintarEscondidos() {
  const fora = Object.keys(ESCONDE).filter(b => BLOCOS[b] === false);
  $('#escondidos').innerHTML = fora.map(b => `<button class="chip-volta" data-mostrar="${b}">${SVG.mais}${ESCONDE[b]}</button>`).join('');
}
function trocarBloco(b, on) {
  BLOCOS[b] = on;
  if (b === 'spotify') E.spotify = on ? 'tocando' : 'fechado';
  render(); gravar();
}
function entrarOrganizar() { organizando = true; $('#lista-perfis').hidden = true; tela.classList.add('organizando') }
function sairOrganizar() { organizando = false; tela.classList.remove('organizando') }
$('#b-pronto').onclick = sairOrganizar;

tela.addEventListener('pointerdown', ev => {
  const t = ev.target.closest('.tecla'); if (!t || tela.classList.contains('com-folha')) return;
  gesto = { el: t, id: t.dataset.id, x: ev.clientX, y: ev.clientY, arrastando: false, segurou: false };
  t.classList.add('apertada');
  if (!organizando) {
    t.classList.add('segurando');
    gesto.timer = setTimeout(() => { gesto.segurou = true; t.classList.remove('segurando', 'apertada'); entrarOrganizar() }, 500);
  }
});
tela.addEventListener('pointermove', ev => {
  if (!gesto) return;
  const longe = Math.hypot(ev.clientX - gesto.x, ev.clientY - gesto.y) > 8;
  if (!organizando && !gesto.segurou) { if (longe) cancelarGesto(); return }
  if (gesto.id === 'menu') return;
  if (!gesto.arrastando && longe) comecarArrasto(ev);
  if (gesto.arrastando) moverArrasto(ev);
});
tela.addEventListener('pointerup', ev => {
  if (!gesto) return;
  const g = gesto; clearTimeout(g.timer); g.el.classList.remove('segurando', 'apertada'); gesto = null;
  if (g.arrastando) return soltarArrasto();
  if (g.segurou) return;
  if (!$('#lista-perfis').hidden) { $('#lista-perfis').hidden = true; return } // toque fora só fecha a folha do Menu
  if (organizando) return abrirEditor(g.id === 'menu' ? 'nova' : g.id);
  executar(g.id);
});
tela.addEventListener('dragstart', e => e.preventDefault());
tela.addEventListener('pointercancel', () => { if (gesto?.arrastando) soltarArrasto(); cancelarGesto() });
function cancelarGesto() { if (!gesto) return; clearTimeout(gesto.timer); gesto.el.classList.remove('segurando', 'apertada'); gesto = null }

let fantasma = null;
function comecarArrasto(ev) {
  gesto.arrastando = true;
  const { r, k } = escalaTela(), b = gesto.el.getBoundingClientRect();
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
  const de = teclas.findIndex(t => t.id === gesto.id), para = teclas.findIndex(t => t.id === alvo.dataset.id);
  const [item] = teclas.splice(de, 1); teclas.splice(para, 0, item);
  renderTeclas();
  gesto.el = $(`.tecla[data-id="${gesto.id}"]`); gesto.el.classList.add('arrastando');
}
function soltarArrasto() { fantasma?.remove(); fantasma = null; renderTeclas(); gravar() }

function executar(id) {
  if (id === 'menu') return abrirMenu($('.tecla.menu'));
  const t = teclas.find(x => x.id === id), el = $(`.tecla[data-id="${id}"]`);
  if (painelDe(t)) return abrirPainel(painelDe(t)); // WhatsApp e Calendário abrem a lista aqui, com "Abrir no Mac" dentro
  if (t.estado) { t.acesa = !t.acesa; renderTeclas(); avisar(`${t.nome}: ${t.acesa ? 'ligado' : 'desligado'}`); return }
  el.classList.add('piscando'); setTimeout(() => el.classList.remove('piscando'), 400);
  avisar(t.tipo === 'app' ? `Abrindo ${t.nome} no Mac` : `${t.nome}: feito`);
}

tela.addEventListener('click', ev => {
  if (!ev.target.isConnected) return; // alvo redesenhado por outro ouvinte (ex.: lista de apps do editor)
  const lp = $('#lista-perfis'), pf = ev.target.closest('[data-perfil]');
  if (pf) return ativarPerfil(pf.dataset.perfil);
  if (ev.target.closest('[data-nova-tecla]')) { lp.hidden = true; return abrirEditor('nova') }
  if (!lp.hidden && !ev.target.closest('#lista-perfis, .tecla.menu')) { lp.hidden = true; return }
  const eb = ev.target.closest('[data-esconder]'); if (eb && organizando) { ev.stopPropagation(); return trocarBloco(eb.dataset.esconder, false) }
  const mb = ev.target.closest('[data-mostrar]'); if (mb) return trocarBloco(mb.dataset.mostrar, true);
  const m = ev.target.closest('[data-midia]');
  if (m) { if (m.dataset.midia === 'tocar') { E.spotify = E.spotify === 'tocando' ? 'pausado' : 'tocando'; render() } else avisar(m.dataset.midia === 'proxima' ? 'Próxima faixa' : 'Faixa anterior'); return }
  if (ev.target.closest('[data-abrir-spotify]')) return avisar('Abrindo o Spotify no Mac');
  const p = ev.target.closest('[data-painel]'); if (p && !organizando) return abrirPainel(p.dataset.painel);
  if (ev.target.closest('[data-fechar]') || ev.target.id === 'veu') return fecharFolha();
  if (organizando && !ev.target.closest('.tecla, .barra-organizar, .folha, .veu')) sairOrganizar();
});
addEventListener('keydown', e => { if (e.key === 'Escape') { fecharFolha(); sairOrganizar() } });

/* ---------- folhas ---------- */
let folhaAberta = null;
function abrirFolha(id) { folhaAberta = $(id); folhaAberta.classList.add('aberta'); tela.classList.add('com-folha') }
function fecharFolha() { folhaAberta?.classList.remove('aberta'); folhaAberta = null; tela.classList.remove('com-folha') }
$$('[data-fechar]').forEach(b => { if (!b.textContent.trim()) b.innerHTML = SVG.x });
function abrirPainel(qual) { if (qual === 'whatsapp') abrirWhats(); else if (qual === 'calendario') abrirCal(); else if (qual === 'sessoes') abrirSessoes() }

/* editor */
let editando = null, rasc = null;
const TIPOS = {
  app: { rot: 'Qual app', html: v => `<div class="lista-apps">${APPS.map(a => `<button data-app="${a.nome}" aria-pressed="${a.nome === v}"><img src="${a.ic}" alt="">${esc(a.nome)}</button>`).join('')}</div><span class="ajuda">A lista vem dos apps instalados no Mac. WhatsApp e Calendário abrem a lista aqui no iPhone.</span>` },
  atalho: { rot: 'Atalho da Apple', html: v => `<input id="ed-valor" value="${esc(v)}" list="l-atalhos"><datalist id="l-atalhos"><option>Hora do Dia<option>Enviar Mensagem<option>Novo Atalho</datalist><span class="ajuda">A lista vem do app Atalhos do Mac.</span>` },
  tecla: { rot: 'Combinação de teclas', html: v => `<div class="tecla-gravada">${(v || 'cmd+shift+4').split('+').map(k => `<kbd>${esc({ ctrl: 'control', opt: 'option', cmd: 'command' }[k] || k.toUpperCase())}</kbd>`).join('')}</div><button class="btn secundario pequeno" type="button" style="justify-self:start" id="ed-gravar">Gravar de novo</button>` },
  comando: { rot: 'Comando de shell', html: v => `<input id="ed-valor" value="${esc(v)}" spellcheck="false" autocapitalize="off"><span class="ajuda">Roda no Mac com zsh.</span>` },
  painel: { rot: 'Abre no iPhone', html: v => `<div class="segmentos" id="ed-painel">${Object.entries(PAINEIS).map(([k, n]) => `<button data-p="${k}" aria-pressed="${k === v}">${n.split(' ')[0] === 'Não' ? 'WhatsApp' : n.split(' ')[0]}</button>`).join('')}</div><span class="ajuda">${PAINEIS[v] || 'Escolha o que abre no celular.'}</span>` },
};
function abrirEditor(id) {
  editando = id;
  const t = id === 'nova' ? { nome: '', tipo: 'app', valor: '', icone: '' } : teclas.find(x => x.id === id);
  rasc = { ...t };
  $('#ed-titulo').textContent = id === 'nova' ? 'Nova tecla' : 'Editar tecla';
  $('#ed-nome').value = t.nome;
  $('#ed-excluir').hidden = id === 'nova';
  pintarTipo(); abrirFolha('#f-editor');
}
function pintarTipo() {
  $$('#ed-tipo button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tipo === rasc.tipo)));
  $('#ed-acao').innerHTML = `<span class="rotulo">${TIPOS[rasc.tipo].rot}</span>${TIPOS[rasc.tipo].html(rasc.valor)}`;
  $('#ed-campo-icone').hidden = rasc.tipo === 'app';
  const opcoes = [...APPS.map(a => a.nome), 'svg:tela', 'svg:terminal', 'svg:raio', 'svg:microfone'];
  $('#ed-icones').innerHTML = opcoes.map(o => `<button aria-label="${o.replace('svg:', '')}" aria-pressed="${rasc.icone === o}" data-ic="${o}">${o.startsWith('svg:') ? SVG[o.slice(4)] : `<img src="${icApp(o)}" alt="">`}</button>`).join('');
}
$('#ed-tipo').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; rasc.tipo = b.dataset.tipo; rasc.valor = ''; pintarTipo() });
$('#ed-acao').addEventListener('click', e => {
  const a = e.target.closest('[data-app]'); if (a) { rasc.valor = a.dataset.app; rasc.icone = a.dataset.app; if (!$('#ed-nome').value || APPS.some(x => x.nome === $('#ed-nome').value)) $('#ed-nome').value = a.dataset.app; pintarTipo(); return }
  const p = e.target.closest('[data-p]'); if (p) { rasc.valor = p.dataset.p; pintarTipo(); return }
  if (e.target.id === 'ed-gravar') avisar('No app de verdade: aperte a combinação no teclado do Mac');
});
$('#ed-icones').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; rasc.icone = b.dataset.ic; pintarTipo() });
$('#ed-salvar').onclick = () => {
  const nome = $('#ed-nome').value.trim();
  if (!nome) { avisar('Dê um nome para a tecla', { erro: true }); $('#ed-nome').focus(); return }
  const v = $('#ed-valor'); if (v) rasc.valor = v.value;
  if (!rasc.valor) { avisar('Escolha o que a tecla faz', { erro: true }); return }
  rasc.nome = nome; // aceso (verde) é automático para função conhecida, sem campo para o usuário
  if (editando === 'nova') teclas.push({ ...rasc, id: 't' + Date.now() }); else teclas = teclas.map(t => t.id === editando ? { ...t, ...rasc } : t);
  fecharFolha(); renderTeclas(); gravar(); avisar('Tecla salva');
};
$('#ed-excluir').onclick = () => {
  const i = teclas.findIndex(t => t.id === editando), velha = teclas[i];
  teclas.splice(i, 1); fecharFolha(); renderTeclas(); gravar();
  avisar(`"${velha.nome}" excluída`, { desfazer: () => { teclas.splice(i, 0, velha); renderTeclas(); gravar() } });
};

/* WhatsApp */
let filtroWa = 'todas', abertaWa = null;
function abrirWhats() { abertaWa = null; pintarWhats(); abrirFolha('#f-whats') }
function pintarWhats() {
  const lista = WHATS.filter(c => filtroWa === 'todas' || (filtroWa === 'grupos') === !!c.grupo);
  $('#wa-titulo').innerHTML = `WhatsApp <small>${totalWhats()} não lidas em ${WHATS.length} conversas</small>`;
  $$('#wa-filtro button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.f === filtroWa)));
  $('#wa-lista').innerHTML = lista.map(c => {
    const ultima = c.msgs[c.msgs.length - 1];
    const msgs = abertaWa === c.nome ? `<div class="mensagens">${c.msgs.map(([q, m]) => `<p>${q ? `<small>${esc(q)}</small>` : ''}${esc(m)}</p>`).join('')}<button class="btn secundario pequeno" data-wa-mac="${esc(c.nome)}">Responder no Mac</button></div>` : '';
    return `<button class="conversa" data-wa="${esc(c.nome)}" aria-expanded="${abertaWa === c.nome}"><span class="avatar">${c.grupo ? SVG.grupo : iniciais(c.nome)}</span>
      <span style="min-width:0"><div class="nome-c">${esc(c.nome)}${c.grupo ? '<small>grupo</small>' : ''}</div><div class="previa">${ultima[0] ? esc(ultima[0]) + ': ' : ''}${esc(ultima[1])}</div></span>
      <span class="lado"><span>${c.hora}</span><span class="qtd">${c.qtd}</span></span></button>${msgs}`;
  }).join('') || '<div class="vazio-bloco" style="min-height:120px"><strong>Nada aqui</strong><span>Sem não lidas nesse filtro.</span></div>';
}
$('#wa-filtro').addEventListener('click', e => { const b = e.target.closest('button'); if (b) { filtroWa = b.dataset.f; pintarWhats() } });
$('#wa-lista').addEventListener('click', e => {
  const mac = e.target.closest('[data-wa-mac]'); if (mac) return avisar(`Abrindo a conversa com ${mac.dataset.waMac} no Mac`);
  const c = e.target.closest('[data-wa]'); if (c) alternarConversa(c.dataset.wa);
});
// abrir e fechar a conversa com movimento: a que estava aberta recolhe, a nova se expande e os balões
// entram em cascata. Tempos e curvas vêm dos tokens (com movimento reduzido eles viram 0).
const tok = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), ms = n => parseFloat(tok(n));
let mexendoWa = false;
async function alternarConversa(nome) {
  if (mexendoWa) return; mexendoWa = true;
  const velha = $('#wa-lista .mensagens');
  if (velha) { velha.style.overflow = 'hidden';
    await velha.animate([{ height: velha.offsetHeight + 'px', opacity: 1 }, { height: '0px', opacity: 0, marginBottom: '0px' }], { duration: ms('--mov-sai-padrao'), easing: tok('--curva-sai'), fill: 'forwards' }).finished }
  abertaWa = abertaWa === nome ? null : nome; pintarWhats();
  const nova = $('#wa-lista .mensagens');
  if (nova) {
    const h = nova.offsetHeight, mb = getComputedStyle(nova).marginBottom; nova.style.overflow = 'hidden';
    nova.animate([{ height: '0px', opacity: 0, marginBottom: '0px' }, { height: h + 'px', opacity: 1, marginBottom: mb }], { duration: ms('--mov-padrao'), easing: tok('--curva-entra') }).finished.then(() => nova.style.overflow = '');
    [...nova.children].forEach((f, i) => f.animate([{ opacity: 0, transform: 'translateY(-8px)' }, { opacity: 1, transform: 'none' }], { duration: ms('--mov-padrao'), delay: i * ms('--mov-cascata'), easing: tok('--curva-entra'), fill: 'backwards' }));
    nova.previousElementSibling.scrollIntoView({ block: 'nearest', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  }
  mexendoWa = false;
}
$('#wa-abrir').onclick = () => avisar('Abrindo o WhatsApp no Mac');

/* sessões */
function abrirSessoes() {
  const n = Number(E.sessoes), lista = SESSOES.slice(0, n);
  $('#se-titulo').innerHTML = `Sessões esperando <small>${n} ${n === 1 ? 'sessão' : 'sessões'}</small>`;
  $('#se-lista').innerHTML = lista.map((s, i) => `<div class="item-sessao"><b>${esc(s.nome)}<small>${esc(s.proj)}, ${s.ha}</small></b><p>${esc(s.q)}</p>
    <div class="acoes"><button class="btn secundario pequeno" data-dispensar="${i}">Dispensar</button><button class="btn primario pequeno" data-sessao="${i}">Responder</button></div></div>`).join('')
    || '<div class="vazio-bloco" style="min-height:160px"><strong>Ninguém esperando</strong><span>Quando uma sessão do Claude pedir resposta, ela aparece aqui.</span></div>';
  abrirFolha('#f-sessoes');
}
$('#se-lista').addEventListener('click', e => {
  const r = e.target.closest('[data-sessao]'); if (r) return avisar(`Abrindo ${SESSOES[r.dataset.sessao].nome} no Claude do iPhone`);
  const d = e.target.closest('[data-dispensar]'); if (d) { d.closest('.item-sessao').remove(); avisar('Dispensada até ela mudar de novo') }
});

/* agenda: mês no estilo do StandBy à esquerda, lista por data a partir do dia tocado à direita */
let mesVisto = new Date(), diaSel = new Date(), abertoEv = null;
function abrirCal() { mesVisto = new Date(); mesVisto.setDate(1); diaSel = new Date(); abertoEv = null; pintarCal(); abrirFolha('#f-cal') }
function mesmoDia(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
function nomeDia(d) {
  const hoje = new Date(), amanha = new Date(); amanha.setDate(hoje.getDate() + 1);
  const longo = d.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  return mesmoDia(d, hoje) ? 'Hoje, ' + longo.split(', ')[1] : mesmoDia(d, amanha) ? 'Amanhã, ' + longo.split(', ')[1] : longo[0].toUpperCase() + longo.slice(1);
}
function pintarCal() {
  const hoje = new Date(), nome = mesVisto.toLocaleDateString('pt-BR', { month: 'long' }) + (mesVisto.getFullYear() !== hoje.getFullYear() ? ' ' + mesVisto.getFullYear() : '');
  $('#ca-titulo').textContent = nome;
  const primeiro = new Date(mesVisto.getFullYear(), mesVisto.getMonth(), 1), dias = new Date(mesVisto.getFullYear(), mesVisto.getMonth() + 1, 0).getDate();
  let h = '<span></span>'.repeat(primeiro.getDay());
  for (let n = 1; n <= dias; n++) {
    const d = new Date(mesVisto.getFullYear(), mesVisto.getMonth(), n), dow = d.getDay(), tem = eventosDo(d).length;
    h += `<button class="sb-dia ${dow === 0 || dow === 6 ? 'fds' : ''} ${mesmoDia(d, hoje) ? 'hoje' : ''} ${mesmoDia(d, diaSel) && !mesmoDia(d, hoje) ? 'sel' : ''} ${tem ? 'tem' : ''}" data-dia="${d.toISOString()}" aria-label="${d.toLocaleDateString('pt-BR')}, ${tem} eventos">${n}</button>`;
  }
  $('#ca-grade').innerHTML = h;
  pintarLista();
}
function pintarLista() {
  const el = $('#ca-lista');
  if (E.agenda === 'sem') { el.innerHTML = '<div class="vazio-bloco"><strong>Agenda sem permissão</strong><span>No Mac: Ajustes > Privacidade > Calendários, ligue o Deck.</span></div>'; return }
  if (E.agenda === 'vazia') { el.innerHTML = '<div class="vazio-bloco"><strong>Nada marcado</strong><span>Os eventos do Calendário do Mac aparecem aqui.</span></div>'; return }
  const agora = new Date(); let h = '';
  for (let i = 0; i < 21; i++) {
    const d = new Date(diaSel); d.setDate(diaSel.getDate() + i);
    const ev = eventosDo(d).filter(e => !mesmoDia(d, agora) || e.h === 'dia todo' || e.h >= agora.toTimeString().slice(0, 5));
    if (!ev.length) continue;
    h += `<section class="grupo-data"><h3>${nomeDia(d)}</h3>` + ev.map((e, j) => {
      const k = d.toDateString() + j, aberto = abertoEv === k;
      return `<button class="ev-linha" data-ev="${k}" aria-expanded="${aberto}"><time>${e.h}</time><i style="background:${e.cor}"></i><span class="tx"><b>${esc(e.t)}</b><span>${esc(e.cal || '')}${e.local ? ', ' + esc(e.local) : ''}</span></span></button>`
        + (aberto ? `<div class="ev-detalhe"><button class="btn secundario pequeno" data-ev-mac>Abrir no Calendário do Mac</button></div>` : '');
    }).join('') + '</section>';
  }
  el.innerHTML = h || '<div class="vazio-bloco"><strong>Nada nas próximas 3 semanas</strong></div>';
}
function trocarMes(passo) {
  const g = $('#ca-mes'); g.classList.add(passo > 0 ? 'saindo-esq' : 'saindo-dir');
  setTimeout(() => {
    mesVisto = new Date(mesVisto.getFullYear(), mesVisto.getMonth() + passo, 1); pintarCal();
    g.classList.remove('saindo-esq', 'saindo-dir'); g.style.translate = `${passo * 24}px 0`; g.style.opacity = 0;
    requestAnimationFrame(() => requestAnimationFrame(() => { g.style.translate = ''; g.style.opacity = '' }));
  }, 130);
}
$('#ca-ant').innerHTML = SVG.esq; $('#ca-prox').innerHTML = SVG.dir;
$('#ca-ant').onclick = () => trocarMes(-1); $('#ca-prox').onclick = () => trocarMes(1);
$('#ca-grade').addEventListener('click', e => { const d = e.target.closest('[data-dia]'); if (!d) return; diaSel = new Date(d.dataset.dia); abertoEv = null; pintarCal() });
$('#ca-lista').addEventListener('click', e => {
  if (e.target.closest('[data-ev-mac]')) return avisar('Abrindo o evento no Calendário do Mac');
  const b = e.target.closest('[data-ev]'); if (b) { abertoEv = abertoEv === b.dataset.ev ? null : b.dataset.ev; pintarLista() }
});
let toqueCal = null;
$('#ca-mes').addEventListener('pointerdown', e => { toqueCal = { x: e.clientX, y: e.clientY } });
$('#ca-mes').addEventListener('pointerup', e => {
  if (!toqueCal) return; const dx = e.clientX - toqueCal.x, dy = e.clientY - toqueCal.y; toqueCal = null;
  if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) trocarMes(dx < 0 ? 1 : -1);
});

/* ---------- controles do protótipo ---------- */
const EXTRAS = ['Safari', 'Notes', 'Terminal', 'Finder', 'Spotify', 'Vorssaint', 'Calendar', 'WhatsApp'].map((n, i) => ({ id: 'x' + i, nome: n === 'Notes' ? 'Notas' : n, tipo: 'app', valor: n, icone: n }));
$$('.opcoes').forEach(g => g.addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  const grupo = g.dataset.grupo, antes = E[grupo]; E[grupo] = b.dataset.v; fecharFolha(); sairOrganizar();
  if (grupo === 'qtd') { teclas = teclas.filter(t => !t.id.startsWith('x')); if (b.dataset.v === 'muitas') teclas.push(...EXTRAS) }
  if (grupo === 'spotify' && (antes === 'fechado') !== (b.dataset.v === 'fechado')) { $$('.opcoes').forEach(o => $$('button', o).forEach(x => x.setAttribute('aria-pressed', String(E[o.dataset.grupo] === x.dataset.v)))); $('.player')?.classList.toggle('pausado', b.dataset.v === 'pausado'); return alternarMusica(b.dataset.v === 'fechado') }
  render(); if (grupo === 'qtd' || grupo === 'comp') gravar();
}));
function ajustarEscala() {
  const m = $('#moldura'), h = m.classList.contains('horizontal'), larg = h ? 960 : 458, alt = h ? 458 : 960;
  const k = Math.min(1, $('.palco').clientWidth / larg);
  m.style.setProperty('--escala', k); $('.palco').style.height = (alt * k) + 'px';
}
addEventListener('resize', ajustarEscala);
render();
