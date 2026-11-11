/* Protótipo do app do Mac: barra de menus + Ajustes. Dados comuns e sincronia em dados.js. */
const IC = {
  geral: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/></svg>',
  tela: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="6" width="20" height="12" rx="3"/></svg>',
  teclas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></svg>',
  uso: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
  iphone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="6" y="2" width="12" height="20" rx="3"/><path d="M11 18h2"/></svg>',
  permissoes: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 3 4 6v6c0 4.5 3.4 8.3 8 9 4.6-.7 8-4.5 8-9V6l-8-3Z"/></svg>',
  sobre: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.01"/></svg>',
  ok: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5 9-10"/></svg>',
  alerta: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 2 20h20L12 3Z"/><path d="M12 10v4M12 17v.01"/></svg>',
  dados: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M9 10v10"/></svg>',
  mais: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0M12 19v.01"/></svg>',
};
const SECOES = [ // nomes no jeito do Deck, o que mais se usa em cima
  { id: 'teclas', nome: 'Suas teclas' },
  { id: 'uso', nome: 'Uso das IAs' },
  null,
  { id: 'iphone', nome: 'Conectar iPhone' },
  { id: 'permissoes', nome: 'Acessos do Mac' },
  null,
  { id: 'geral', nome: 'Este Mac' },
  { id: 'sobre', nome: 'Sobre o Deck' },
];
// cada acesso é pedido pelo próprio macOS na hora em que o Deck precisa dele (null = nunca pedido)
const PERMS = [
  { id: 'acess', nome: 'Acessibilidade', para: 'Para as teclas do tipo Teclado apertarem atalhos no Mac.', sem: 'As teclas do tipo Teclado não funcionam', onde: 'Privacidade e Segurança > Acessibilidade',
    alerta: ['“Deck” gostaria de controlar este computador usando os recursos de acessibilidade.', 'Conceda acesso a este app em Ajustes do Sistema > Privacidade e Segurança.', 'Recusar', 'Abrir Ajustes do Sistema'] },
  { id: 'cal', nome: 'Calendários', para: 'Para mostrar seus eventos na Agenda do iPhone.', sem: 'A Agenda não aparece no iPhone', onde: 'Privacidade e Segurança > Calendários',
    alerta: ['“Deck” gostaria de acessar seus Calendários.', 'Para mostrar seus eventos no iPhone.', 'Não Permitir', 'Permitir'] },
  { id: 'spotify', nome: 'Automação', nomeLista: 'Automação do Spotify', para: 'Para o player do iPhone mostrar a música e controlar o Spotify.', sem: 'O player não mostra a música nem controla o Spotify', onde: 'Privacidade e Segurança > Automação',
    alerta: ['“Deck” quer controlar o “Spotify”.', 'Permitir o controle dará acesso aos documentos e dados no “Spotify” e permitirá realizar ações nesse app.', 'Não Permitir', 'Permitir'] },
  { id: 'disco', nome: 'Acesso Total ao Disco', para: 'Para mostrar quem mandou mensagem no WhatsApp. Só leitura, nada sai do Mac.', sem: 'A tecla do WhatsApp mostra só o total, sem a lista por conversa', onde: 'Privacidade e Segurança > Acesso Total ao Disco',
    alerta: ['“Deck” gostaria de acessar dados de outros apps.', 'Para ler as não lidas do WhatsApp por conversa. Só leitura, nada sai do Mac.', 'Não Permitir', 'Permitir'] },
  // só aparecem na seção Acessos do Mac, não no passo da configuração inicial
  { id: 'nav', nome: 'Automação', nomeLista: 'Automação dos navegadores', para: 'Para contar as não lidas do WhatsApp Web aberto no navegador.', sem: 'O WhatsApp Web não entra na contagem', onde: 'Privacidade e Segurança > Automação',
    alerta: ['“Deck” quer controlar o “Safari”.', 'Permitir o controle dará acesso aos documentos e dados no “Safari” e permitirá realizar ações nesse app.', 'Não Permitir', 'Permitir'] },
  { id: 'bt', nome: 'Bluetooth', para: 'Para o app do iPhone falar com o Mac por Bluetooth, sem Wi-Fi.', sem: 'O app do iPhone não conecta sem Wi-Fi', onde: 'Privacidade e Segurança > Bluetooth',
    alerta: ['“Deck” gostaria de usar o Bluetooth.', 'Para o app do iPhone falar com o Mac por Bluetooth, sem Wi-Fi.', 'Não Permitir', 'Permitir'] },
  { id: 'rede', nome: 'Rede Local', para: 'Para o iPhone achar o Mac na rede de casa.', sem: 'O iPhone não acha o Mac', onde: 'Privacidade e Segurança > Rede Local',
    alerta: ['“Deck” gostaria de encontrar e se conectar a dispositivos em sua rede local.', 'Para o iPhone achar o Mac na rede de casa.', 'Não Permitir', 'Permitir'] },
];
// a seção Acessos do Mac lista todos, nesta ordem
const ORDEM_PAINEL = ['cal', 'spotify', 'nav', 'acess', 'disco', 'bt', 'rede'];
// contas que o app acharia neste Mac (Claude Code: cada conta logada, Codex: ~/.codex). Por perfil do protótipo
const ACHADAS = {
  leo: CONTAS_LEO,
  novo: [{ id: 'claude-pessoal', nome: 'Claude', conta: 'pessoal', sem: 23, renova: 'seg 10h' }, { id: 'codex', nome: 'Codex', conta: 'plus', sem: 41, renova: 'qui 8h' }],
};
const M = { perfil: 'leo', secao: 'teclas', pop: false, jan: false, iphone: 'on', perms: { acess: true, cal: true, spotify: false, disco: false, nav: true, bt: true, rede: true }, comp: 'a', sel: null, ouvindo: false, login: true, atualizar: true, configurado: true, conta: null, pag: 0, ini: null };
const salvo = lerConfig(); aplicarConfigComum(salvo); if (salvo?.comp) M.comp = salvo.comp;
// o Mac edita um perfil (M.editando) sem mudar o que o iPhone mostra (perfilAtivo)
// vindo do nativo.html (?op=...): sem iPhone pelo Wi-Fi e já em Conectar iPhone
if (new URLSearchParams(location.search).has('et') || new URLSearchParams(location.search).has('op')) { M.iphone = 'off'; M.secao = 'iphone' }
M.editando = perfilAtivo; teclas = perfilDe(M.editando).teclas;
M.sel = teclas[0]?.id;
const achadas = () => ACHADAS[M.perfil].filter(a => !USO.some(u => u.id === a.id));
const nomeIphone = () => M.perfil === 'leo' ? 'iPhone de Exemplo' : 'iPhone';

const mesa = $('#mesa'), corpo = $('#j-corpo');
const faltando = () => PERMS.filter(p => M.perms[p.id] === false); // só o que a pessoa recusou
const tecla = id => teclas.find(t => t.id === id);
const porPaginaMac = () => M.comp === 'b' ? 9 : 5; // deitado: o que cabe numa página do carrossel

/* ---------- avisos e sincronia ---------- */
let tAviso, tSinc, desfazer = null;
function avisar(txt, desf) {
  // com desf: botão "Desfazer" no próprio aviso por 5 s (como no iPhone). O ⌘Z continua valendo
  const a = $('#aviso'); desfazer = desf || null;
  a.innerHTML = `<span>${esc(txt)}</span>${desf ? '<button data-desfazer>Desfazer</button>' : ''}`;
  a.classList.add('visivel'); clearTimeout(tAviso); tAviso = setTimeout(() => { a.classList.remove('visivel'); if (desf && desfazer === desf) desfazer = null }, desf ? 5000 : 2600);
}
$('#aviso').addEventListener('click', e => { if (e.target.closest('[data-desfazer]') && desfazer) { e.stopPropagation(); const f = desfazer; desfazer = null; f(); avisar('Desfeito') } });
function pintarSinc(agora) {
  const s = $('#sincronia');
  s.innerHTML = M.iphone === 'on' || natPareado() ? `<span class="ponto on"></span>${agora ? 'Salvo. Já está no iPhone' : 'Sincronizado com o ' + nomeIphone()}` : `<span class="ponto"></span>${agora ? 'Salvo' : 'Nenhum iPhone pareado'}`;
  s.classList.toggle('agora', !!agora);
  clearTimeout(tSinc); if (agora) tSinc = setTimeout(() => pintarSinc(false), 1800);
}
const gravar = () => { perfilDe(M.editando).teclas = teclas; publicar(configAtual(M.comp)); pintarSinc(true) };
aoMudarConfig(c => { aplicarConfigComum(c); if (c?.comp) M.comp = c.comp; if (!perfis.some(p => p.id === M.editando)) M.editando = perfilAtivo; teclas = perfilDe(M.editando).teclas; if (!tecla(M.sel)) M.sel = teclas[0]?.id; pintar(); avisar('O iPhone mudou a ordem ou uma tecla') });

/* ---------- barra de menus e menu do Deck ---------- */
// ícone do app (A-3) nos lugares grandes. Na barra de menus vai o desenho de uma cor só, como pede o macOS
const LOGO = '<img class="logo" src="icones/deck-128.png" alt="">';
const LOGO_GRANDE = '<img class="logo grande" src="icones/deck.png" alt="">';
const GLIFO_MENU = '<svg viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><rect x="2" y="2" width="6" height="6" rx="1.6" fill="currentColor"/><rect x="10" y="2" width="6" height="6" rx="1.6"/><rect x="2" y="10" width="6" height="6" rx="1.6"/><rect x="10" y="10" width="6" height="6" rx="1.6"/></svg>';
$('#b-deck').innerHTML = GLIFO_MENU; $('#ic-wifi').innerHTML = IC.wifi;
function relogio() { const d = new Date(); $('#relogio-menu').textContent = d.toLocaleDateString('pt-BR', { weekday: 'short', day: 'numeric', month: 'short' }).replace(/\./g, '') + '  ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) }
relogio(); setInterval(relogio, 15000);

function pintarPop() {
  const p = $('#popover'), f = faltando();
  p.hidden = !M.pop; $('#b-deck').setAttribute('aria-expanded', String(M.pop));
  if (!M.pop) return;
  p.innerHTML = `
    <div class="pop-topo">${LOGO}<b>Deck</b><span>${natPareado() ? `<i class="ponto on"></i>${nomeIphone()}, ${canalTxt()}` : M.iphone === 'on' ? `<i class="ponto on"></i>${nomeIphone()}, pelo Wi-Fi` : '<i class="ponto"></i>Nenhum iPhone pareado'}</span></div>
    ${natPop()}
    ${!M.configurado ? `<div class="pop-bloco"><span class="rotulo">Configuração inicial</span><span class="pop-passo">Faltam alguns passos para o iPhone mostrar o Deck.</span><button class="btn primario" data-ini>Continuar configuração</button></div>` : M.iphone === 'on' || natPareado() ? `<div class="pop-bloco"><span class="rotulo">Layout no iPhone</span>
      <div class="comps-pop" data-comp>${['a', 'b'].map(c => `<button class="comp" data-v="${c}" aria-pressed="${M.comp === c}">${MINI[c]}<small>${c === 'a' ? 'Relógio em cima' : 'Deck 3 x 3'}</small></button>`).join('')}</div></div>`
      : natPop() ? '' : `<button class="btn primario" data-ir="iphone">Parear um iPhone</button>`}
    ${M.configurado && perfis.length > 1 ? `<div class="pop-bloco"><span class="rotulo">Perfil no iPhone</span><div class="segmentos" data-perfil-pop>${perfis.map(p => `<button data-v="${p.id}" aria-pressed="${p.id === perfilAtivo}">${esc(p.nome)}</button>`).join('')}</div></div>` : ''}
    ${natPareado() && nat().ren === 'falhou' ? `<button class="pop-alerta" data-ir="iphone">${IC.alerta}O app vence em 2 dias</button>` : ''}
    ${f.length ? `<button class="pop-alerta" data-ir="permissoes">${IC.alerta}${f.length} ${f.length > 1 ? 'acessos recusados' : 'acesso recusado'}</button>` : ''}
    <div class="pop-sep"></div>
    <button class="pop-item" data-ir="">Ajustes...<kbd>⌘,</kbd></button>
    <div class="pop-sep"></div>
    <button class="pop-item" data-sair>Sair do Deck<kbd>⌘Q</kbd></button>`;
}
$('#b-deck').onclick = e => { e.stopPropagation(); M.pop = !M.pop; pintarPop() };
$('#popover').addEventListener('click', e => {
  e.stopPropagation();
  const nt = e.target.closest('[data-nat]'); if (nt) return natAcao(nt.dataset.nat);
  const c = e.target.closest('[data-comp] button'); if (c) { M.comp = c.dataset.v; gravar(); pintarPop(); if (M.jan) pintar(); avisar(`Layout ${c.dataset.v === 'a' ? 'relógio em cima' : 'deck 3 x 3'} no iPhone`); return }
  const pp = e.target.closest('[data-perfil-pop] button'); if (pp) { usarPerfil(pp.dataset.v); pintarPop(); return }
  if (e.target.closest('[data-ini]')) { M.pop = false; abrirIni(); return }
  const ir = e.target.closest('[data-ir]'); if (ir) { M.pop = false; abrirJanela(ir.dataset.ir || (SECOES.some(x => x?.id === M.secao) ? M.secao : 'teclas')); return }
  if (e.target.closest('[data-sair]')) { M.pop = false; pintarPop(); avisar('No app de verdade: o Deck fecha e o iPhone mostra "Mac desconectado"') }
});
mesa.addEventListener('click', () => { if (M.pop) { M.pop = false; pintarPop() } });

const MINI = {
  a: '<span class="mini-tela mini-a" aria-hidden="true"><i class="r"></i><i></i><i></i><i></i><span class="k"><b></b><b></b><b></b><b></b><b></b><i></i><b></b></span></span>',
  b: '<span class="mini-tela mini-b" aria-hidden="true"><span class="e"><i class="r"></i><i></i><i></i></span><span class="k"><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b></span></span>',
};

/* ---------- alerta do macOS (simulado): é assim que cada acesso é pedido, na hora do uso ---------- */
const filaPerm = [];
function pedirPerm(id) {
  if (M.perms[id] !== null || filaPerm.includes(id)) return;
  filaPerm.push(id); if (filaPerm.length === 1) mostrarAlerta();
}
function mostrarAlerta() {
  const id = filaPerm[0], el = $('#alerta-sis'); if (!id) { el.hidden = true; return }
  const [tit, txt, nao, sim] = PERMS.find(p => p.id === id).alerta;
  el.innerHTML = `<div class="alerta-caixa" role="alertdialog" aria-labelledby="al-tit"><img src="icones/deck-128.png" alt=""><b id="al-tit">${tit}</b><p>${txt}</p><div class="alerta-botoes"><button data-resp="nao">${nao}</button><button class="padrao" data-resp="sim">${sim}</button></div></div>`;
  el.hidden = false;
}
$('#alerta-sis').addEventListener('click', e => {
  e.stopPropagation();
  const b = e.target.closest('[data-resp]'); if (!b) return;
  const id = filaPerm.shift(), p = PERMS.find(x => x.id === id);
  if (b.dataset.resp === 'nao') { M.perms[id] = false; avisar(`${p.nome}: recusado. Dá para liberar depois em Acessos do Mac`) }
  else if (id === 'acess') { M.perms[id] = null; avisar('Ajustes do Sistema abertos. Ligue o Deck e volte'); setTimeout(() => { M.perms.acess = true; pintar(); if (M.ini) pintarIni(0); avisar('Acessibilidade: liberado') }, 1400) }
  else M.perms[id] = true;
  pintar(); marcarControles(); mostrarAlerta(); if (M.ini) pintarIni(0);
});

/* ---------- janela de Ajustes ---------- */
function abrirJanela(secao) { M.jan = true; M.secao = secao; pintar() }
$('[data-fechar-janela]').onclick = () => { M.jan = false; pintar() };
function pintarNav() {
  const n = faltando().length;
  $('#nav').innerHTML = SECOES.map(s => s ? `<button data-secao="${s.id}" ${M.secao === s.id ? 'aria-current="page"' : ''}><span class="ic-sec">${IC[s.id]}</span>${s.nome}${s.id === 'permissoes' && n ? `<span class="selo-nav" aria-label="${n} faltando">${n}</span>` : s.id === 'iphone' && natPareado() && nat().ren === 'falhou' ? '<span class="selo-nav" aria-label="1 aviso">1</span>' : '<span></span>'}</button>` : '<span class="grupo-nav"></span>').join('');
}
$('#nav').addEventListener('click', e => { const b = e.target.closest('[data-secao]'); if (b) { M.secao = b.dataset.secao; M.ouvindo = false; pintar() } });

const chave = (id, on, rot) => `<button class="chave" role="switch" aria-checked="${on}" aria-label="${esc(rot)}" data-chave="${id}"></button>`;
const linha = (titulo, sub, lado) => `<div class="linha-a"><div class="txt"><span>${titulo}</span>${sub ? `<small>${sub}</small>` : ''}</div>${lado || ''}</div>`;
const grupo = (titulo, html, nota) => `<section class="grupo">${titulo ? `<h3>${titulo}</h3>` : ''}${html}${nota ? `<p class="nota">${nota}</p>` : ''}</section>`;

const TELAS = {
  geral: () => grupo('', `<div class="linhas">
      ${linha('Nome deste Mac', 'Aparece no iPhone quando o Mac sai da rede', `<input class="entrada" data-nome-mac value="${esc(nomeMac)}" aria-label="Nome deste Mac" autocomplete="off">`)}
      ${linha('Abrir junto com o Mac', 'O Deck fica na barra de menus, sem ícone no Dock', chave('login', M.login, 'Abrir junto com o Mac'))}
      ${linha('Procurar atualizações', 'Uma vez por dia', chave('atualizar', M.atualizar, 'Procurar atualizações'))}
      ${linha('Configuração inicial', 'Refaz os passos da primeira vez, sem apagar suas teclas', '<button class="btn secundario" data-ini>Refazer</button>')}
    </div>`),
  teclas: () => {
    const pp = porPaginaMac(), pags = [];
    for (let i = 0; i < teclas.length; i += pp) pags.push(teclas.slice(i, i + pp));
    if (!pags.length) pags.push([]);
    const pag = M.pag = Math.min(M.pag || 0, pags.length - 1); // uma página por vez, nas abas
    const t = tecla(M.sel);
    const ed = perfilDe(M.editando);
    return `<section class="perfis-barra"><div class="perfil-abas" role="tablist" aria-label="Perfis">${perfis.map(p => `<button role="tab" class="perfil-aba" data-perfil-ed="${p.id}" aria-selected="${p.id === M.editando}">${esc(p.nome)}${p.id === perfilAtivo ? '<i class="ponto on" title="É o que o iPhone mostra agora"></i>' : ''}</button>`).join('')}<button class="perfil-aba novo" data-perfil-novo>${IC.mais}Perfil</button></div>
      <div class="perfil-acoes"><input class="entrada" data-perfil-nome value="${esc(ed.nome)}" aria-label="Nome do perfil" autocomplete="off">${ed.id === perfilAtivo ? '<span class="no-iphone-agora"><i class="ponto on"></i>No iPhone agora</span>' : `<button class="btn secundario" data-usar-perfil>Usar no iPhone agora</button>`}<span class="espaco"></span>${perfis.length > 1 ? '<button class="btn perigo" data-excluir-perfil>Excluir perfil</button>' : ''}</div></section>
      <section class="grupo"><h3>No iPhone <small>Arraste para mudar a ordem, ou solte numa aba para mudar de página. É a mesma lista do modo organizar do iPhone</small></h3>
      ${pags.length > 1 ? `<div class="abas-pag" role="tablist" aria-label="Páginas do iPhone">${pags.map((p, i) => `<button role="tab" class="aba-pag" data-pag="${i}" aria-selected="${i === pag}">Página ${i + 1}</button>`).join('')}</div>` : ''}
      <div class="grade-mac" role="listbox" aria-label="Teclas da página ${pag + 1}">${pags[pag].map(t => teclaMac(t)).join('')}${pag === pags.length - 1 ? `<button class="tecla-m nova" data-nova><span class="svg">${SVG.mais}</span><span class="nome">Nova</span></button>` : ''}</div></section>
      ${t ? editorMac(t) : '<section class="cartao vazio">Crie a primeira tecla no "Nova".</section>'}`;
  },
  uso: () => {
    const nivel = p => p >= 90 ? 'cheio' : p >= 70 ? 'alto' : '';
    const perto = [...USO].filter(u => u.mostrar !== false).sort((a, b) => b.sem - a.sem)[0];
    const cards = USO.map(u => `<article class="cartao conta ${nivel(u.sem)} ${u.mostrar === false ? 'oculta' : ''}">
        <header><img src="${IC_SERVICO[u.nome]}" alt=""><input class="entrada nome-conta" data-apelido="${u.id}" value="${esc(u.apelido || u.conta)}" aria-label="Nome no iPhone"><span class="no-iphone">No iPhone${chave('uso:' + u.id, u.mostrar !== false, `Mostrar ${u.conta} no iPhone`)}</span></header>
        <small class="servico">${u.nome === 'Claude' ? 'Claude Code' : 'Codex'}, conta ${esc(u.conta)}</small>
        <div class="numero"><b>${u.sem}%</b><span>da semana</span></div>
        <span class="trilho"><i style="width:${u.sem}%"></i></span>
        <footer><span title="${esc(u.renova)}">Renova ${renovaEm(u.renova)}</span><button class="btn perigo" data-remover="${u.id}">Remover</button></footer></article>`).join('');
    return `${perto ? `<p class="resumo-uso">Mais perto do limite: <b>${esc(perto.apelido || perto.conta)}</b>, ${perto.sem}% da semana.</p>` : ''}
      <div class="dash">${cards}<button class="cartao conta nova" data-abrir-somar>${IC.mais}<b>Adicionar conta</b><small>Claude Code ou Codex</small></button></div>
      <p class="nota">O nome é o que aparece no iPhone. Conta só a janela semanal.</p>`;
  },
  iphone: () => {
    // aparelhos pareados (um por forma de conexão) + o app nativo + o pareamento pelo Wi-Fi, como já era
    const ap = [];
    if (M.iphone === 'on') ap.push(linha(nomeIphone(), 'Safari, pelo Wi-Fi desde 09:12', '<button class="btn secundario" data-acao="desparear">Desconectar</button>'));
    if (natPareado()) ap.push(linha(nomeIphone(), `App nativo, ${canalTxt()} desde 09:12`, '<button class="btn secundario" data-nat="desparear-nativo">Desconectar</button>'));
    return (ap.length ? grupo('Aparelhos', `<div class="linhas">${ap.join('')}</div>`) : '') + grupo('App no iPhone, por cabo e Bluetooth', natSecao()) + grupo(M.iphone === 'on' ? 'Parear outro iPhone pelo Wi-Fi' : 'Parear um iPhone pelo Wi-Fi', `${parearHTML()}`, 'Pelo Wi-Fi o iPhone usa o Deck como app da Tela de Início (PWA), que é limitado. Só funciona com o iPhone na mesma rede do Mac, não conecta por cabo nem por Bluetooth, deixa de atualizar quando o iPhone sai do Wi-Fi e a tela pode apagar sozinha. Para ter tudo isso, use o app no iPhone, acima. Nada sai da sua rede.');
  },
  permissoes: () => grupo('O que o Deck usa neste Mac', `<div class="linhas">${ORDEM_PAINEL.map(id => { const p = PERMS.find(x => x.id === id), v = M.perms[id];
    const estado = v ? `<span class="liberado">${IC.ok}Liberado</span>` : v === false ? '<span class="valor recusado">Recusado</span>' : '<span class="valor">Não perguntado</span>';
    return linha(p.nomeLista || p.nome, p.para, `<span class="lado-acesso">${estado}${v === null ? `<button class="btn primario" data-permitir="${id}">Permitir</button>` : ''}<button class="btn ${v === false ? 'primario' : 'secundario'}" data-liberar="${id}">Abrir Ajustes do Sistema</button></span>`) }).join('')}</div>`,
    'O macOS só deixa o próprio dono liberar. "Permitir" faz o Deck pedir agora, e o botão dos Ajustes do Sistema abre a página certa. Esta lista se atualiza sozinha quando você volta.'),
  sobre: () => `<div class="sobre">
      <div class="sobre-topo">${LOGO_GRANDE}<div><h3>Deck</h3><p>Painel de mesa no iPhone para controlar o Mac.</p></div></div>
      <div class="linhas">
        ${linha('Versão', 'A mais recente', '<span class="valor">0.1 (1)</span>')}
        ${linha('Atualizado em', '', '<span class="valor">10 de novembro de 2026</span>')}
        ${linha('Mac', 'Precisa do macOS 13 ou mais novo', '<span class="valor">macOS 26</span>')}
        ${linha('iPhone', 'Precisa do iOS 16.4 ou mais novo', `<span class="valor">${M.iphone === 'on' ? 'iOS 26' : 'nenhum pareado'}</span>`)}
      </div>
      ${grupo('Projeto aberto', `<div class="linhas">
        ${linha('Gostou do Deck?', 'Abre a página do projeto no GitHub', '<a class="btn estrela" href="https://github.com/leonardorejani/deck_os" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.2 6.1 20.6l1.3-6.6L2.5 9.4l6.6-.8z"/></svg>Dar uma estrela no GitHub</a>')}
        ${linha('Licença', 'Uso livre, com o aviso de direitos mantido', '<a class="btn link" href="https://github.com/leonardorejani/deck_os/blob/main/LICENSE" target="_blank" rel="noopener">MIT</a>')}
        ${linha('Achou um erro?', 'Abre o formulário de problema no GitHub', '<a class="btn secundario" href="https://github.com/leonardorejani/deck_os/issues/new" target="_blank" rel="noopener">Relatar um problema</a>')}
      </div>`, 'O Deck é código aberto, com licença MIT. Uma estrela ajuda outras pessoas a achar o projeto.')}</div>`,

};
function usarPerfil(id) { perfilAtivo = id; gravar(); pintar(); avisar(`O iPhone agora mostra o perfil ${perfilDe(id).nome}`) }
function editarPerfil(id) { perfilDe(M.editando).teclas = teclas; M.editando = id; teclas = perfilDe(id).teclas; M.sel = teclas[0]?.id; M.pag = 0; M.busca = ''; M.ouvindo = false; pintar() }
function teclaMac(t, previa) {
  // mesma tecla do iPhone: ícone, nome, a barrinha embaixo, verde quando acesa. Selecionada ganha o lápis do modo organizar
  const ic = t.tipo === 'app' && t.valor ? icDoApp(t.valor) : iconeHTML(t.icone);
  return `<${previa ? 'span' : 'button'} class="tecla-m ${t.estado && t.acesa ? 'acesa' : ''}" ${previa ? '' : `draggable="true" role="option" data-id="${t.id}" aria-selected="${t.id === M.sel}"`}>${previa ? '' : `<span class="editar" aria-hidden="true">${SVG.lapis}</span>`}${ic}<span class="nome">${esc(t.nome)}</span><span class="led" aria-hidden="true"></span></${previa ? 'span' : 'button'}>`;
}
const TIPOS_MAC = {
  app: { nome: 'App', diz: 'Abre um app', ic: IC.teclas },
  tecla: { nome: 'Teclado', diz: 'Aperta teclas', ic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/></svg>' },
  comando: { nome: 'Comando', diz: 'Roda no Terminal', ic: SVG.terminal },
  atalho: { nome: 'Atalho', diz: 'Roda um atalho', ic: SVG.raio },
};
const NOMES_KBD = { ctrl: '⌃ control', opt: '⌥ option', cmd: '⌘ command', shift: '⇧ shift' };
// todos os apps da pasta Aplicativos (de mentira). Os com ícone vêm de APPS, o resto ganha a inicial
const TODOS_APPS = [...APPS.map(a => a.nome), 'Ableton Live', 'App Store', 'Arc', 'Atalhos', 'Calculadora', 'Contatos', 'Discord', 'FaceTime', 'Figma', 'Final Cut Pro', 'Fotos', 'GarageBand', 'Google Chrome', 'Lembretes', 'Logic Pro', 'Mail', 'Mapas', 'Mensagens', 'Música', 'Notion', 'OBS', 'Obsidian', 'Prévia', 'ProPresenter', 'Slack', 'Ajustes do Sistema', 'Visual Studio Code', 'Xcode', 'Zoom'].sort((a, b) => a.localeCompare(b, 'pt-BR'));
const ATALHOS = ['Hora do Dia', 'Modo Ensaio', 'Ligar Luzes', 'Enviar Mensagem', 'Iniciar Gravação', 'Foco: Trabalho', 'Converter Imagem', 'Dividir Conta'];
const EX_TECLAS = [['ctrl+opt+cmd+k', 'Manter acordado no Vorssaint'], ['cmd+shift+4', 'Captura de parte da tela'], ['ctrl+cmd+q', 'Bloquear o Mac']];
const EX_COMANDOS = [['Apagar tela', 'pmset displaysleepnow'], ['Abrir Downloads', 'open ~/Downloads'], ['Silenciar', "osascript -e 'set volume output muted true'"], ['Esvaziar Lixeira', "osascript -e 'tell app \"Finder\" to empty trash'"]];
const icLetra = n => `<span class="svg letra" aria-hidden="true">${esc(n[0])}</span>`;
const icDoApp = n => icApp(n) ? `<img src="${icApp(n)}" alt="">` : icLetra(n);
const sem = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
function listaBusca(t) {
  const q = sem(M.busca || '');
  if (t.tipo === 'app') {
    const achou = TODOS_APPS.filter(n => sem(n).includes(q));
    const grade = l => `<div class="grade-apps">${l.map(n => `<button data-app="${esc(n)}" aria-pressed="${n === t.valor}">${icDoApp(n)}<span>${esc(n)}</span></button>`).join('')}</div>`;
    if (!achou.length) return `<p class="sem-achar">Nenhum app com "${esc(M.busca)}" na pasta Aplicativos.</p>`;
    return q ? grade(achou) : `<h5>Mais usados</h5>${grade(APPS.map(a => a.nome))}<h5>Todos, de A a Z</h5>${grade(TODOS_APPS.filter(n => !icApp(n)))}`;
  }
  const achou = ATALHOS.filter(n => sem(n).includes(q));
  return achou.length ? `<div class="lista-atalhos">${achou.map(n => `<button data-atalho="${esc(n)}" aria-pressed="${n === t.valor}">${SVG.raio}<span>${esc(n)}</span></button>`).join('')}</div>` : `<p class="sem-achar">Nenhum atalho com "${esc(M.busca)}".</p>`;
}
function acaoHTML(t) {
  const busca = rot => `<div class="busca"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg><input id="m-busca" type="search" placeholder="${rot}" value="${esc(M.busca || '')}" autocomplete="off" aria-label="${rot}"></div><div id="lista-busca" class="lista-busca">${listaBusca(t)}</div>`;
  if (t.tipo === 'app') return { tit: 'Qual app abre', html: busca(`Buscar entre ${TODOS_APPS.length} apps`) + '<span class="ajuda">WhatsApp e Calendário abrem a lista no próprio iPhone, com "Abrir no Mac" dentro.</span>' };
  if (t.tipo === 'atalho') return { tit: 'Qual atalho do app Atalhos roda', html: busca('Buscar atalho') + '<span class="ajuda">São as automações que você monta no app Atalhos da Apple (ícone de raio no Mac). Criou uma nova lá, ela aparece aqui sozinha.</span>' };
  if (t.tipo === 'tecla') return { tit: 'Qual combinação', html: `<button class="gravador ${M.ouvindo ? 'ouvindo' : ''}" data-gravar>${M.ouvindo ? 'Aperte a combinação no teclado. Esc cancela' : t.valor ? t.valor.split('+').map(k => `<kbd>${esc(NOMES_KBD[k] || k.toUpperCase())}</kbd>`).join('') : 'Clique aqui e aperte as teclas'}</button>
      <span class="ajuda">Serve para atalho de qualquer app, mesmo em segundo plano. Exemplos:</span><div class="chips">${EX_TECLAS.map(([v, d]) => `<button class="chip" data-ex-tecla="${v}">${d}</button>`).join('')}</div>` };
  if (t.tipo === 'comando') return { tit: 'Qual comando', html: `<textarea id="m-valor" data-campo="valor" spellcheck="false" placeholder="ex.: open ~/Downloads">${esc(t.valor)}</textarea><div class="rodape-ed"><span class="teste-saida" id="saida"></span><button class="btn secundario" data-acao="testar">Testar agora</button></div>
      <span class="ajuda">Roda no zsh do Mac. Prontos para usar:</span><div class="chips">${EX_COMANDOS.map(([n, v]) => `<button class="chip" data-ex-cmd="${esc(v)}" data-ex-nome="${esc(n)}">${n}</button>`).join('')}</div>` };
  return { tit: '', html: '' };
}
function editorMac(t) {
  const icones = [...APPS.map(a => a.nome), 'svg:tela', 'svg:terminal', 'svg:raio', 'svg:microfone'], a = acaoHTML(t);
  return `<section class="cartao editor-mac" aria-label="Editar ${esc(t.nome)}">
    <header class="ed-topo"><span class="previa">${teclaMac(t, true)}</span><div class="ed-nome"><input class="entrada titulo" id="m-nome" data-campo="nome" value="${esc(t.nome)}" placeholder="Nome da tecla" aria-label="Nome da tecla" autocomplete="off"><small>${TIPOS_MAC[t.tipo].diz}. O nome é o que aparece no iPhone</small></div><button class="btn perigo" data-acao="excluir">Excluir tecla</button></header>
    <div class="passo"><h4><i>1</i>O que a tecla faz</h4><div class="tipos">${Object.entries(TIPOS_MAC).map(([k, x]) => `<button class="tipo" data-tipo="${k}" aria-pressed="${t.tipo === k}"><span class="ic-tipo">${x.ic}</span><span><b>${x.nome}</b><small>${x.diz}</small></span></button>`).join('')}</div></div>
    <div class="passo"><h4><i>2</i>${a.tit}</h4>${a.html}
      ${t.tipo === 'app' ? '' : `<div class="campo"><span class="rotulo">Ícone</span><div class="icones">${icones.map(o => `<button aria-label="${o.replace('svg:', '')}" aria-pressed="${t.icone === o}" data-ic="${o}">${o.startsWith('svg:') ? SVG[o.slice(4)] : `<img src="${icApp(o)}" alt="">`}</button>`).join('')}</div></div>`}</div>
  </section>`;
}
function parearHTML(extra = '') {
  // no cartão só o que se usa para parear (QR, endereço, código). Os passos ficam embaixo, fora dele
  const end = 'https://' + nomeMac.toLowerCase().normalize('NFD').replace(/[^a-z0-9 ]/g, '').trim().replace(/ +/g, '-') + '.local:4777';
  return `<div class="parear"><div class="qr" aria-label="QR code de pareamento">${qrSVG()}</div><div class="parear-dados">
      <div class="campo"><span class="rotulo">Código</span><div class="codigo-linha"><span class="codigo">K7P 2QX</span><small>vale por 10 minutos</small></div></div>
      <div class="campo"><span class="rotulo">Ou abra no Safari do iPhone</span><div class="endereco"><span>${end}</span><button class="btn secundario" data-acao="copiar">Copiar</button></div></div>${extra}</div></div>
    <ol class="passos-n"><li><i>1</i><span>No iPhone, aponte a <b>câmera</b> para o código e toque no link.</span></li><li><i>2</i><span>Instale o <b>certificado</b> e ligue a confiança em Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados.</span></li><li><i>3</i><span>No Safari, <b>Compartilhar > Adicionar à Tela de Início</b>. O Deck abre como app.</span></li></ol>`;
}
/* ---------- app nativo (fase 5): estado em nativo-dados.js, sincronizado com nativo.html ---------- */
const nat = () => nativoEstado;
const natPareado = () => nat().et === 'pronto';
const canalTxt = () => nat().canal === 'bluetooth' ? 'por Bluetooth' : 'pelo cabo';
const natBotoes = (d, cls) => d.botoes ? `<div class="${cls}">${d.botoes.map(([a, r], i) => `<button class="btn ${i ? 'primario' : 'secundario'}" data-nat="${a}">${r}</button>`).join('')}</div>` : '';
const natTitulo = d => `<b class="titulo-n">${d.girando ? '<span class="girando" aria-hidden="true"></span>' : ''}${d.titulo}</b>`;
// menu da barra: só aparece enquanto está pareando (sem o código o menu continua o de sempre)
function natPop() {
  const n = nat(); if (n.et === 'vazio' || n.et === 'pronto') return '';
  const d = NATIVO_MAC[n.et];
  return `<div class="pop-bloco"><span class="rotulo">${d.rotulo}</span>${d.codigo ? `<span class="codigo medio">${NATIVO_CODIGO}</span>` : natTitulo(d)}<span class="pop-passo">${d.texto}</span>${natBotoes(d, 'pop-botoes')}</div>`;
}
// Ajustes > Conectar iPhone: pareando mostra o estado e os passos, pareado mostra o app e a renovação
function natSecao() {
  const n = nat();
  if (n.et !== 'pronto') {
    const d = NATIVO_MAC[n.et];
    return `<div class="parear sem-qr"><div class="parear-dados"><div class="campo"><span class="rotulo">${d.rotulo}</span><div class="codigo-linha">${d.codigo ? `<span class="codigo">${NATIVO_CODIGO}</span>` : natTitulo(d)}<small>${d.texto}</small></div></div>${natBotoes(d, 'botoes-linha')}</div></div>
      <ol class="passos-n">${NATIVO_PASSOS.map((t, i) => `<li><i>${i + 1}</i><span>${t}</span></li>`).join('')}</ol><p class="nota">${NATIVO_NOTA_VIA}</p>`;
  }
  const falhou = n.ren === 'falhou', pend = n.ren === 'pendente';
  // a renovação é automática. O cartão amarelo só aparece quando o prazo de 7 dias aperta sem ter dado certo
  return (falhou ? `<div class="alerta-linha" role="alert">${IC.alerta}<div class="txt"><b>O app vence em 2 dias e a renovação não deu certo</b><small>O Deck tenta de novo sozinho assim que o iPhone aparecer no cabo ou no Wi-Fi, ou for desbloqueado. Se puder, plugue e desbloqueie agora.</small></div><button class="btn primario" data-nat="renovar">Tentar agora</button></div>` : '') +
    `<div class="linhas">${linha('App no iPhone', 'Instalado pelo Xcode em 10 de novembro de 2026', '<span class="valor">0.1 (1)</span>')}
      ${linha('Último canal', 'O Deck usa o cabo quando ele está plugado e o Bluetooth quando não está', `<span class="valor">${nativoCanalNome(n.canal)}, agora</span>`)}
      ${linha('Renovação automática', 'O Deck renova sozinho a cada 5 dias, sem abrir nenhuma tela. A Apple faz o app vencer em 7. Se não der, tenta de novo quando o iPhone aparecer no cabo ou no Wi-Fi, ou for desbloqueado', falhou ? '<span class="valor alerta">Vence em 2 dias</span><button class="btn secundario" data-nat="renovar">Renovar agora</button>' : pend ? '<span class="valor">Tenta de novo sozinha</span><button class="btn secundario" data-nat="renovar">Renovar agora</button>' : '<span class="valor">próxima em 3 dias, seg 10h</span><button class="btn secundario" data-nat="renovar">Renovar agora</button>')}</div>
    <p class="nota">Para renovar sozinho, o Mac precisa estar ligado com o Deck na barra, e o iPhone no cabo ou no mesmo Wi-Fi do Mac (pareado com o Xcode pela rede), com a conta da Apple entrada no Xcode e a pasta do projeto do Deck no Mac. O iPhone pode estar bloqueado, menos logo depois de ligar. Você só é avisado quando o prazo aperta.</p>`;
}
function natAcao(a) {
  if (a === 'permitir') { nativoPublicar({ et: 'pronto' }); avisar('iPhone pareado. O app já pode abrir o painel') }
  else if (a === 'recusar') { nativoPublicar({ et: 'vazio' }); avisar('Pareamento recusado') }
  else if (a === 'desparear-nativo') { nativoPublicar({ et: 'vazio' }); avisar('App desconectado. Ele volta a pedir pareamento') }
  else if (a === 'renovar') { avisar('Renovando o app no iPhone...'); setTimeout(() => { nativoPublicar({ ren: 'ok' }); pintar(); marcarControles(); avisar('App renovado. Vale por mais 7 dias') }, 1400); return }
  pintar(); marcarControles();
}
nativoAoMudar(() => { pintar(); marcarControles() });

function qrSVG() {
  // desenho de QR (de mentira): os três quadrados de canto e um padrão fixo no meio
  let s = 1, r = '';
  const n = 25, rnd = () => (s = (s * 9301 + 49297) % 233280) / 233280;
  const canto = (x, y) => (x < 7 && y < 7) || (x > 17 && y < 7) || (x < 7 && y > 17);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    let on;
    if (canto(x, y)) { const cx = x > 17 ? x - 18 : x, cy = y > 17 ? y - 18 : y; on = cx === 0 || cx === 6 || cy === 0 || cy === 6 || (cx > 1 && cx < 5 && cy > 1 && cy < 5) } else on = rnd() > .52;
    if (on) r += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
  }
  return `<svg viewBox="0 0 25 25" fill="#000" shape-rendering="crispEdges">${r}</svg>`;
}

function pintar() {
  pintarPop();
  const j = $('#janela'); j.hidden = !M.jan; if (!M.jan) return;
  pintarNav();
  $('#j-titulo').textContent = SECOES.find(s => s?.id === M.secao).nome;
  const rolagem = corpo.scrollTop;
  corpo.innerHTML = TELAS[M.secao]();
  corpo.scrollTop = rolagem;
  pintarSinc(false);
  pintarConta();
}

/* ---------- adicionar conta: achada no Mac, token colado (Claude) ou login (Codex) ---------- */
const PREFIXO_TOKEN = 'sk-ant-oat01-';
const nomeServ = s => s === 'Claude' ? 'Claude Code' : 'Codex';
const cmdLinha = cmd => `<div class="cmd"><code>${cmd}</code><button class="btn secundario" data-c-copiar="${cmd}">Copiar</button><button class="btn secundario" data-c-terminal="${cmd}">Abrir no Terminal</button></div>`;
function abrirConta() { M.conta = { serv: 'Claude', token: '', nome: '', mostrar: false, erro: '', conferindo: false, esperando: false }; pintarConta(); $('#c-token')?.focus() }
function fecharConta() { M.conta = null; pintarConta() }
function pintarConta() {
  const el = $('#modal-j'), c = M.conta; el.hidden = !(c && (M.jan || M.ini)); if (el.hidden) return;
  const casa = M.ini ? mesa : $('#janela'); if (el.parentNode !== casa) casa.appendChild(el); el.classList.toggle('no-ini', !!M.ini);
  const ach = M.ini ? [] : achadas().filter(a => a.nome === c.serv); // na configuração as achadas já estão na lista do passo
  const serv = s => `<button class="serv" data-serv="${s}" aria-pressed="${c.serv === s}"><img src="${IC_SERVICO[s]}" alt=""><span>${nomeServ(s)}</span></button>`;
  const achou = ach.length ? `<section class="bloco-c"><h4>Achei neste Mac</h4>${ach.map(a => `<div class="linha-a"><img class="ic" src="${IC_SERVICO[a.nome]}" alt=""><div class="txt"><span>Conta ${esc(a.conta)}</span><small>${a.sem}% da semana usado</small></div><button class="btn primario" data-somar="${a.id}">Adicionar</button></div>`).join('')}</section>` : '';
  const claude = `<section class="bloco-c"><h4>${ach.length ? 'Ou outra conta' : 'Outra conta'}</h4><ol class="passos-c">
      <li><div class="txt"><b>Gere um token no Terminal</b><small>Ele abre o navegador. Entre na conta que você quer acompanhar e copie o token que aparece no fim.</small></div>${cmdLinha('claude setup-token')}</li>
      <li><div class="txt"><b>Cole o token aqui</b><small>Começa com ${PREFIXO_TOKEN}. Fica no Chaveiro deste Mac e só serve para ler o uso.</small></div>
        <div class="campo-token"><input class="entrada" id="c-token" type="${c.mostrar ? 'text' : 'password'}" value="${esc(c.token)}" placeholder="${PREFIXO_TOKEN}..." autocomplete="off" spellcheck="false" aria-label="Token" aria-invalid="${!!c.erro}" aria-describedby="c-erro"><button class="btn link" data-c-mostrar>${c.mostrar ? 'Esconder' : 'Mostrar'}</button></div>
        <p class="erro-c" id="c-erro" role="alert">${esc(c.erro)}</p></li>
      <li><div class="txt"><b>Dê um nome</b><small>É o que aparece no iPhone.</small></div><input class="entrada" id="c-nome" value="${esc(c.nome)}" placeholder="Ex.: Trabalho" autocomplete="off" aria-label="Nome no iPhone"></li></ol></section>`;
  const codex = `<section class="bloco-c"><h4>${ach.length ? 'Ou outra conta' : 'Outra conta'}</h4><ol class="passos-c">
      <li><div class="txt"><b>Entre na conta pelo Terminal</b><small>Ele abre o navegador para você entrar com a conta do ChatGPT.</small></div>${cmdLinha('codex login')}</li>
      <li><div class="txt"><b>Volte aqui</b><small>O Deck acha a conta sozinho quando o login terminar.</small></div><p class="esperando" aria-live="polite">${c.esperando ? '<span class="girando" aria-hidden="true"></span>Esperando o login...' : ''}</p></li></ol></section>`;
  el.innerHTML = `<div class="modal-caixa" role="dialog" aria-modal="true" aria-labelledby="c-titulo">
    <header><h3 id="c-titulo">Adicionar conta</h3><button class="fechar-c" data-c-fechar aria-label="Fechar">${IC.mais}</button></header>
    <div class="servicos" role="group" aria-label="Serviço">${serv('Claude')}${serv('Codex')}</div>
    ${achou}${c.serv === 'Claude' ? claude : codex}
    <footer><button class="btn secundario" data-c-fechar>Cancelar</button>${c.serv === 'Claude' ? `<button class="btn primario" data-c-adicionar ${c.token && !c.conferindo ? '' : 'disabled'}>${c.conferindo ? 'Conferindo...' : 'Adicionar'}</button>` : ''}</footer></div>`;
}
// na configuração inicial a conta nova entra na lista do passo, já marcada
function contaNaIni(a) { ACHADAS[M.perfil].push(a); M.ini.contas.add(a.id); fecharConta(); pintarIni(0); avisar('Conta conectada') }
function somarAchada(id) { USO.push(structuredClone(ACHADAS[M.perfil].find(a => a.id === id))); fecharConta(); gravar(); pintar(); avisar('Conta adicionada. Já aparece no iPhone') }
function adicionarToken() {
  const c = M.conta;
  if (!c.token.startsWith(PREFIXO_TOKEN)) c.erro = `Isso não é um token do Claude Code. Ele começa com ${PREFIXO_TOKEN}`;
  else if (c.token.length < 100) c.erro = 'O token parece cortado. Copie de novo, ele é bem longo.';
  else c.erro = '';
  if (c.erro) { pintarConta(); $('#c-token').focus(); return }
  c.conferindo = true; pintarConta();
  setTimeout(() => { // o app de verdade pede o uso da semana com o token. Recusou: erro do lado do campo
    if (M.conta !== c) return;
    c.conferindo = false;
    if (c.token.includes('recusado')) { c.erro = 'O Claude recusou esse token. Gere outro com claude setup-token.'; pintarConta(); return }
    const nome = c.nome.trim() || 'nova conta';
    const nova = { id: 'claude-' + Date.now(), nome: 'Claude', conta: nome, sem: 8, renova: 'sex 18h' };
    if (M.ini) return contaNaIni(nova);
    USO.push(nova);
    fecharConta(); gravar(); pintar(); avisar('Conta adicionada. Já aparece no iPhone');
  }, 900);
}
const modal = $('#modal-j');
modal.addEventListener('click', e => {
  const c = M.conta; if (!c) return;
  if (e.target === modal) { if (!c.token) fecharConta(); return } // com token digitado, clicar fora não perde o que colou
  if (e.target.closest('[data-c-fechar]')) return fecharConta();
  const s = e.target.closest('[data-serv]'); if (s) { c.serv = s.dataset.serv; c.erro = ''; pintarConta(); return }
  const so = e.target.closest('[data-somar]'); if (so) return somarAchada(so.dataset.somar);
  const cp = e.target.closest('[data-c-copiar]'); if (cp) { navigator.clipboard?.writeText(cp.dataset.cCopiar).catch(() => {}); avisar('Comando copiado'); return }
  const tm = e.target.closest('[data-c-terminal]'); if (tm) {
    avisar('Terminal aberto com o comando pronto');
    if (c.serv === 'Codex' && !c.esperando) { // protótipo: o login "termina" sozinho e a conta aparece em "Achei neste Mac"
      c.esperando = true; pintarConta();
      setTimeout(() => { if (M.conta !== c) return; c.esperando = false; const a = { id: 'codex-' + Date.now(), nome: 'Codex', conta: 'pro', sem: 12, renova: 'dom 9h' }; if (M.ini) return contaNaIni(a); ACHADAS[M.perfil].push(a); pintarConta() }, 2500);
    }
    return;
  }
  if (e.target.closest('[data-c-mostrar]')) { c.mostrar = !c.mostrar; pintarConta(); $('#c-token').focus(); return }
  if (e.target.closest('[data-c-adicionar]')) adicionarToken();
});
modal.addEventListener('input', e => {
  const c = M.conta; if (!c) return;
  if (e.target.id === 'c-token') { // o Terminal quebra o token em linhas: tira espaço e quebra de linha ao colar
    const limpo = e.target.value.replace(/\s+/g, ''); if (limpo !== e.target.value) e.target.value = limpo;
    c.token = limpo; if (c.erro) { c.erro = ''; $('#c-erro').textContent = ''; e.target.setAttribute('aria-invalid', 'false') }
    const b = $('[data-c-adicionar]'); if (b) b.disabled = !c.token || c.conferindo;
  }
  if (e.target.id === 'c-nome') c.nome = e.target.value;
});
modal.addEventListener('keydown', e => { if (e.key === 'Escape') fecharConta(); if (e.key === 'Enter' && e.target.id !== 'c-nome' && M.conta?.serv === 'Claude' && M.conta.token) adicionarToken() });

/* ---------- interação dentro da janela ---------- */
let tDigita;
function mudarTecla(campo, valor, redesenhar = false) {
  const t = tecla(M.sel); if (!t) return;
  if (campo === 'estado') valor = valor.trim() || undefined;
  t[campo] = valor;
  if (campo === 'nome') $$(`.tecla-m[data-id="${t.id}"] .nome, .ed-topo .previa .nome`).forEach(el => el.textContent = valor);
  if (redesenhar) pintar();
  clearTimeout(tDigita); tDigita = setTimeout(gravar, redesenhar ? 0 : 400);
}
corpo.addEventListener('input', e => {
  const c = e.target.dataset.campo; if (c) return mudarTecla(c, e.target.value, e.target.tagName === 'SELECT');
  if (e.target.id === 'm-busca') { M.busca = e.target.value; const t = tecla(M.sel); $('#lista-busca').innerHTML = listaBusca(t); return }
  const ap = e.target.dataset.apelido; if (ap) { USO.find(u => u.id === ap).apelido = e.target.value.trim() || undefined; clearTimeout(tDigita); tDigita = setTimeout(gravar, 400); return }
  if ('perfilNome' in e.target.dataset) { perfilDe(M.editando).nome = e.target.value.trim() || 'Sem nome'; const a = $(`[data-perfil-ed="${M.editando}"]`); if (a) a.firstChild.textContent = perfilDe(M.editando).nome; clearTimeout(tDigita); tDigita = setTimeout(gravar, 400); return }
  if ('nomeMac' in e.target.dataset) { nomeMac = e.target.value.trim() || 'Mac'; clearTimeout(tDigita); tDigita = setTimeout(gravar, 400) }
});
corpo.addEventListener('click', e => {
  const nt = e.target.closest('[data-nat]'); if (nt) return natAcao(nt.dataset.nat);
  const ch = e.target.closest('[data-chave]');
  if (ch) {
    const k = ch.dataset.chave, on = ch.getAttribute('aria-checked') !== 'true'; ch.setAttribute('aria-checked', String(on));
    if (k.startsWith('uso:')) { USO.find(u => u.id === k.slice(4)).mostrar = on; gravar() }
    else { M[k] = on; pintarSinc(true) }
    return;
  }
  if (e.target.closest('[data-ini]')) { abrirIni(); return }
  const pe = e.target.closest('[data-perfil-ed]'); if (pe) { editarPerfil(pe.dataset.perfilEd); return }
  if (e.target.closest('[data-perfil-novo]')) { const p = { id: 'p' + Date.now(), nome: 'Novo perfil', teclas: [] }; perfilDe(M.editando).teclas = teclas; perfis.push(p); editarPerfil(p.id); gravar(); $('[data-perfil-nome]')?.select(); return }
  if (e.target.closest('[data-usar-perfil]')) { usarPerfil(M.editando); return }
  if (e.target.closest('[data-excluir-perfil]')) {
    const i = perfis.findIndex(p => p.id === M.editando), velho = perfis[i], eraAtivo = perfilAtivo === velho.id;
    perfis.splice(i, 1); if (eraAtivo) perfilAtivo = perfis[0].id; M.editando = perfilAtivo; teclas = perfilDe(M.editando).teclas; M.sel = teclas[0]?.id;
    publicar(configAtual(M.comp)); pintarSinc(true); pintar();
    avisar(`Perfil ${velho.nome} excluído`, () => { perfis.splice(i, 0, velho); if (eraAtivo) perfilAtivo = velho.id; editarPerfil(velho.id); gravar() });
    return;
  }
  const irS = e.target.closest('[data-ir-secao]'); if (irS) { M.secao = irS.dataset.irSecao; pintar(); return }
  if (e.target.closest('[data-abrir-somar]')) { abrirConta(); return }
  const rm = e.target.closest('[data-remover]');
  if (rm) { const i = USO.findIndex(u => u.id === rm.dataset.remover), velha = USO[i]; USO.splice(i, 1); gravar(); pintar(); avisar(`Conta ${velha.conta} removida`, () => { USO.splice(i, 0, velha); gravar(); pintar() }); return }
  const ab = e.target.closest('[data-pag]'); if (ab) { M.pag = +ab.dataset.pag; pintar(); return }
  const tm = e.target.closest('.tecla-m[data-id]'); if (tm) { M.sel = tm.dataset.id; M.ouvindo = false; M.busca = ''; pintar(); return }
  if (e.target.closest('[data-nova]')) { const t = { id: 't' + Date.now(), nome: 'Nova tecla', tipo: 'app', valor: '', icone: '' }; teclas.push(t); M.sel = t.id; M.pag = Math.floor((teclas.length - 1) / porPaginaMac()); M.busca = ''; gravar(); pintar(); $('#m-nome')?.select(); return }
  const tp = e.target.closest('[data-tipo]'); if (tp) { const t = tecla(M.sel); if (t.tipo !== tp.dataset.tipo) { t.tipo = tp.dataset.tipo; t.valor = ''; if (t.tipo === 'tecla') pedirPerm('acess') } M.ouvindo = false; M.busca = ''; gravar(); pintar(); return }
  const at = e.target.closest('[data-atalho]'); if (at) { const t = tecla(M.sel); if (!t.nome || t.nome === 'Nova tecla') t.nome = at.dataset.atalho; t.valor = at.dataset.atalho; gravar(); pintar(); return }
  const et = e.target.closest('[data-ex-tecla]'); if (et) { mudarTecla('valor', et.dataset.exTecla, true); return }
  const ec = e.target.closest('[data-ex-cmd]'); if (ec) { const t = tecla(M.sel); if (!t.nome || t.nome === 'Nova tecla') t.nome = ec.dataset.exNome; mudarTecla('valor', ec.dataset.exCmd, true); return }
  const ap = e.target.closest('[data-app]'); if (ap) { const t = tecla(M.sel); if (!t.nome || t.nome === 'Nova tecla' || TODOS_APPS.includes(t.nome)) t.nome = ap.dataset.app; t.valor = t.icone = ap.dataset.app; gravar(); pintar(); avisar(`${ap.dataset.app} escolhido`); return }
  const ic = e.target.closest('[data-ic]'); if (ic) { mudarTecla('icone', ic.dataset.ic, true); return }
  if (e.target.closest('[data-gravar]')) { M.ouvindo = !M.ouvindo; pintar(); return }
  const per = e.target.closest('[data-permitir]'); if (per) { pedirPerm(per.dataset.permitir); return }
  const lib = e.target.closest('[data-liberar]');
  if (lib) { const p = PERMS.find(x => x.id === lib.dataset.liberar); avisar(`Abre ${p.onde}. Ligue o Deck lá e volte`); setTimeout(() => { M.perms[p.id] = true; pintar(); avisar(`${p.nome}: liberado`) }, 1400); return }
  const ac = e.target.closest('[data-acao]')?.dataset.acao;
  if (ac === 'excluir') {
    const i = teclas.findIndex(t => t.id === M.sel), velha = teclas[i]; teclas.splice(i, 1); M.sel = teclas[Math.min(i, teclas.length - 1)]?.id; gravar(); pintar();
    avisar(`"${velha.nome}" excluída`, () => { teclas.splice(i, 0, velha); M.sel = velha.id; gravar(); pintar() });
  }
  if (ac === 'testar') { const s = $('#saida'); s.textContent = 'rodando...'; setTimeout(() => s.textContent = 'saiu com 0 em 38 ms', 500) }
  if (ac === 'copiar') avisar('Endereço copiado');
  if (ac === 'desparear') { M.iphone = 'off'; pintar(); marcarControles(); avisar('iPhone desconectado. Ele volta a pedir pareamento') }
});
addEventListener('keydown', e => {
  if (M.ouvindo) {
    e.preventDefault();
    if (e.key === 'Escape') { M.ouvindo = false; pintar(); return }
    if (['Control', 'Alt', 'Meta', 'Shift'].includes(e.key)) return;
    const k = [e.ctrlKey && 'ctrl', e.altKey && 'opt', e.metaKey && 'cmd', e.shiftKey && 'shift'].filter(Boolean);
    const base = e.code.startsWith('Key') ? e.code.slice(3).toLowerCase() : e.code.startsWith('Digit') ? e.code.slice(5) : e.key.toLowerCase();
    if (!k.length) { avisar('Use pelo menos uma tecla de controle (⌘, ⌥, ⌃ ou ⇧)'); return }
    M.ouvindo = false; mudarTecla('valor', [...k, base].join('+'), true); avisar('Combinação gravada'); return;
  }
  if ((e.metaKey || e.ctrlKey) && e.key === 'z' && desfazer && !e.target.closest('input, textarea')) { e.preventDefault(); desfazer(); desfazer = null; avisar('Desfeito') }
  if (e.key === 'Escape' && M.pop) { M.pop = false; pintarPop() }
});

/* arrastar para reordenar (mouse: arrastar nativo do navegador basta) */
let arrastando = null;
corpo.addEventListener('dragstart', e => { const t = e.target.closest('.tecla-m[data-id]'); if (!t) return; arrastando = t.dataset.id; e.dataTransfer.effectAllowed = 'move'; requestAnimationFrame(() => t.classList.add('arrastando')) });
corpo.addEventListener('dragover', e => {
  if (!arrastando) return;
  const aba = e.target.closest('[data-pag]'); if (aba) { e.preventDefault(); $$('.aba-pag.soltar').forEach(a => a !== aba && a.classList.remove('soltar')); aba.classList.add('soltar'); return }
  $$('.aba-pag.soltar').forEach(a => a.classList.remove('soltar'));
  const alvo = e.target.closest('.tecla-m[data-id]'); e.preventDefault();
  if (!alvo || alvo.dataset.id === arrastando) return;
  // move só o elemento: redesenhar no meio tiraria a tecla arrastada da página e o arrasto morreria
  const de = teclas.findIndex(t => t.id === arrastando), para = teclas.findIndex(t => t.id === alvo.dataset.id);
  const [item] = teclas.splice(de, 1); teclas.splice(para, 0, item);
  alvo.parentNode.insertBefore($(`.tecla-m[data-id="${arrastando}"]`), de < para ? alvo.nextSibling : alvo);
});
corpo.addEventListener('drop', e => {
  if (!arrastando) return; e.preventDefault();
  // solta na aba: a tecla vai para o fim daquela página
  const aba = e.target.closest('[data-pag]'); if (!aba) return;
  const i = +aba.dataset.pag, pp = porPaginaMac(), de = teclas.findIndex(t => t.id === arrastando);
  const [item] = teclas.splice(de, 1); teclas.splice(Math.min((i + 1) * pp - 1, teclas.length), 0, item);
  M.pag = Math.floor(teclas.indexOf(item) / pp); M.sel = item.id;
});
corpo.addEventListener('dragend', () => { if (!arrastando) return; arrastando = null; pintar(); gravar() });

/* ---------- controles do protótipo e escala ---------- */
function marcarControles() { $$('.opcoes').forEach(g => $$('button', g).forEach(b => b.setAttribute('aria-pressed', String((g.dataset.nativo ? { [g.dataset.nativo]: nativoEstado[g.dataset.nativo] } : { perfil: M.perfil, iphone: M.iphone, perms: faltando().length ? 'faltando' : 'todas', abrir: M.jan ? 'janela' : M.pop ? 'popover' : '' })[g.dataset.nativo || g.dataset.grupo] === b.dataset.v)))) }
$$('.opcoes').forEach(g => g.addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return; e.stopPropagation();
  const v = b.dataset.v, grupo = g.dataset.grupo;
  if (grupo === 'perfil') return trocarPerfil(v);
  if (grupo === 'iphone') M.iphone = v;
  if (grupo === 'perms') M.perms = v === 'todas' ? { acess: true, cal: true, spotify: true, disco: true, nav: true, bt: true, rede: true } : { acess: true, cal: true, spotify: false, disco: false, nav: true, bt: true, rede: true };
  if (grupo === 'simular') { if (M.perms.disco === null) pedirPerm('disco'); else avisar(M.perms.disco ? 'O acesso já foi liberado' : 'Já foi recusado: o macOS não pergunta de novo, só em Acessos do Mac'); return }
  if (grupo === 'abrir') { if (v === 'popover') { M.pop = true } else { M.pop = false; M.jan = true } }
  pintar(); marcarControles();
}));
$$('[data-nativo]').forEach(g => g.addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; e.stopPropagation(); nativoPublicar({ [g.dataset.nativo]: b.dataset.v }); pintar(); marcarControles() }));
function ajustarEscala() { const k = Math.min(1, $('#palco').clientWidth / mesa.offsetWidth); mesa.style.setProperty('--escala', k); $('#palco').style.height = mesa.offsetHeight * k + 'px' }
addEventListener('resize', ajustarEscala);
function trocarPerfil(p) {
  // o protótipo começa como o Exemplo (já configurado) ou como alguém que acabou de instalar
  M.perfil = p; M.pop = false; M.conta = null; desfazer = null;
  if (p === 'leo') { perfis = structuredClone(PERFIS_LEO); perfilAtivo = 'trabalho'; M.editando = 'trabalho'; teclas = perfilDe('trabalho').teclas; USO.splice(0, USO.length, ...structuredClone(CONTAS_LEO)); nomeMac = 'MacBook Pro de Exemplo'; Object.assign(M, { iphone: 'on', perms: { acess: true, cal: true, spotify: false, disco: false, nav: true, bt: true, rede: true }, configurado: true, jan: true, ini: null, comp: 'a' }) }
  else { perfis = [{ id: 'principal', nome: 'Principal', teclas: [] }]; perfilAtivo = M.editando = 'principal'; teclas = perfis[0].teclas; USO.splice(0); nomeMac = 'MacBook Pro'; Object.assign(M, { iphone: 'off', perms: { acess: null, cal: null, spotify: null, disco: null, nav: null, bt: null, rede: null }, configurado: false, jan: false, comp: 'a' }) }
  Object.assign(BLOCOS, { spotify: true, agenda: true, whatsapp: true, sessoes: true });
  M.sel = teclas[0]?.id; gravar(); pintar(); marcarControles();
  if (p === 'novo') abrirIni();
}
M.jan = true; pintar(); marcarControles(); ajustarEscala();

/* ---------- configuração inicial (primeira vez) ---------- */
const SUGESTOES = [
  { id: 's-whats', nome: 'WhatsApp', tipo: 'app', valor: 'WhatsApp', icone: 'WhatsApp' },
  { id: 's-agenda', nome: 'Agenda', tipo: 'app', valor: 'Calendar', icone: 'Calendar' },
  { id: 's-spotify', nome: 'Spotify', tipo: 'app', valor: 'Spotify', icone: 'Spotify' },
  { id: 's-apagar', nome: 'Apagar tela', tipo: 'comando', valor: 'pmset displaysleepnow', icone: 'svg:tela' },
  { id: 's-safari', nome: 'Safari', tipo: 'app', valor: 'Safari', icone: 'Safari' },
  { id: 's-notas', nome: 'Notas', tipo: 'app', valor: 'Notes', icone: 'Notes' },
  { id: 's-terminal', nome: 'Terminal', tipo: 'app', valor: 'Terminal', icone: 'Terminal' },
  { id: 's-finder', nome: 'Finder', tipo: 'app', valor: 'Finder', icone: 'Finder' },
];
function abrirIni() {
  M.jan = false; M.pop = false;
  M.ini = { passo: 0, contas: new Set(ACHADAS[M.perfil].map(a => a.id)), teclas: new Set(['s-whats', 's-agenda', 's-spotify', 's-apagar']), comp: M.comp, conectado: M.iphone === 'on' };
  pintar(); pintarIni(0);
}
// sem escolher o que aparece (o Deck detecta). Os acessos vêm num passo próprio, cada um com o motivo
const passosIni = () => ['boas', 'iphone', 'layout', 'contas', 'teclas', 'acessos', 'pronto'];
const ORDEM_PERMS = ['cal', 'spotify', 'disco', 'acess'];
const TELAS_INI = {
  boas: () => `<div class="ini-centro">${LOGO_GRANDE}
      <h2>Seu iPhone vira um painel do Mac</h2>
      <p>Relógio, música, agenda, mensagens e teclas que controlam o Mac, numa tela só ao lado do teclado. Leva uns dois minutos.</p></div>`,
  iphone: () => `<h2>Conecte o iPhone</h2><p>Os dois precisam estar no mesmo Wi-Fi. Nada sai da sua rede.</p>
    ${parearHTML(`<div class="esperando ${M.ini.conectado ? 'ok' : ''}" role="status">${M.ini.conectado ? `${IC.ok}${nomeIphone()} conectado` : '<span class="girando"></span>Esperando o iPhone...'}</div>`)}`,
  layout: () => `<h2>Como o iPhone fica</h2><p>O Deck mostra sozinho o que você tem no Mac: Spotify, agenda, WhatsApp, sessões e uso das IAs. Escolha só o jeito.</p>
    <div class="comps-ini">${['a', 'b'].map(c => `<button class="comp-ini" data-comp-ini="${c}" aria-pressed="${M.ini.comp === c}"><img src="previas/comp-${c}.jpg" alt="Prévia do iPhone deitado: ${c === 'a' ? 'relógio e player em cima, teclas numa fileira embaixo' : 'relógio, uso, player e sessões à esquerda, teclas em grade à direita'}" width="932" height="431"><b>${c === 'a' ? 'Relógio em cima' : 'Deck 3 x 3'}</b><small>${c === 'a' ? 'Relógio e player em cima, teclas numa fileira embaixo' : 'Informações à esquerda, teclas grandes em grade à direita'}</small></button>`).join('')}</div>`,
  contas: () => `<h2>Suas contas de IA</h2><p>${ACHADAS[M.perfil].length ? 'Achamos estas neste Mac. Marque as que quer ver no iPhone ou conecte outra.' : 'Conecte o Claude Code ou o Codex para ver o uso da semana no iPhone.'}</p>
    <div class="escolhas">${ACHADAS[M.perfil].map(a => `<button class="escolha" data-conta-ini="${a.id}" aria-pressed="${M.ini.contas.has(a.id)}"><img src="${IC_SERVICO[a.nome]}" alt=""><span><b>${nomeServ(a.nome)}, conta ${esc(a.conta)}</b><small>${a.sem}% da semana usado, renova ${renovaEm(a.renova)}</small></span><i class="marca">${IC.ok}</i></button>`).join('')}<button class="escolha conectar" data-conectar-ini>${IC.mais}<span><b>Conectar outra conta</b><small>Claude Code ou Codex</small></span></button></div>`,
  teclas: () => `<h2>Primeiras teclas</h2><p>Escolha algumas para começar. Depois você cria as suas: app, atalho, combinação de teclas ou comando.</p>
    <div class="grade-ini">${SUGESTOES.map(t => `<button class="tecla-m sug" data-sug="${t.id}" aria-pressed="${M.ini.teclas.has(t.id)}">${iconeHTML(t.icone)}<span class="nome">${esc(t.nome)}</span><i class="marca">${IC.ok}</i></button>`).join('')}</div>`,
  acessos: () => `<h2>Libere os acessos</h2><p>O macOS pergunta uma vez cada um. Sem eles, só a parte que depende deles fica de fora. Dá para liberar depois em Ajustes.</p>
    <div class="acessos-ini">${ORDEM_PERMS.map(id => { const p = PERMS.find(x => x.id === id), v = M.perms[id];
      return `<div class="acesso-ini ${v ? 'ok' : ''}"><div class="txt"><b>${p.nome}</b><small>${p.para}</small></div>${v ? `<span class="liberado">${IC.ok}Liberado</span>` : v === false ? `<button class="btn secundario" data-liberar-ini="${id}">Abrir Ajustes do Sistema</button>` : `<button class="btn primario" data-perm-ini="${id}">Permitir</button>`}</div>` }).join('')}</div>`,
  pronto: () => `<div class="ini-centro"><span class="feito">${IC.ok}</span><h2>Pronto, o Deck está no ar</h2><p>Ele mora no ícone da barra de menus. ${M.ini.conectado ? 'O que você escolheu já está no iPhone.' : 'Conecte o iPhone quando quiser em Ajustes, Conectar iPhone.'}</p></div>`,
};
function pintarIni(dir) {
  const el = $('#ini'); el.hidden = !M.ini; if (!M.ini) return;
  const ps = passosIni(), qual = ps[M.ini.passo], ultimo = M.ini.passo === ps.length - 1;
  el.innerHTML = `<div class="ini-barra" aria-hidden="true">${ps.map((_, i) => `<i class="${i <= M.ini.passo ? 'cheia' : ''}"></i>`).join('')}</div>
    <div class="ini-corpo" aria-live="polite">${TELAS_INI[qual]()}</div>
    <footer>${M.ini.passo ? '<button class="btn secundario" data-ini-voltar>Voltar</button>' : '<span></span>'}<span class="espaco"></span>
      ${qual === 'iphone' && !M.ini.conectado ? '<button class="btn link" data-ini-pular>Fazer depois</button>' : ''}
      <button class="btn primario" data-ini-ir ${qual === 'iphone' && !M.ini.conectado ? 'disabled' : ''}>${M.ini.passo === 0 ? 'Começar' : ultimo ? 'Concluir' : 'Continuar'}</button></footer>`;
  if (dir) $('.ini-corpo', el).animate([{ opacity: 0, transform: `translateX(${dir * 24}px)` }, { opacity: 1, transform: 'none' }], { duration: ms('--mov-padrao'), easing: tok('--curva-entra') });
  if (qual === 'iphone' && !M.ini.conectado) { clearTimeout(M.ini.t); M.ini.t = setTimeout(() => { if (!M.ini || passosIni()[M.ini.passo] !== 'iphone') return; M.ini.conectado = true; M.iphone = 'on'; marcarControles(); pintarIni(0) }, 2500) }
}
const tok = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim(), ms = n => parseFloat(tok(n));
function concluirIni() {
  const i = M.ini;
  teclas = SUGESTOES.filter(t => i.teclas.has(t.id)).map(t => ({ ...t, id: 't' + t.id.slice(2) })); perfilDe(M.editando).teclas = teclas;
  USO.splice(0, USO.length, ...ACHADAS[M.perfil].filter(a => i.contas.has(a.id)).map(a => structuredClone(a)));
  Object.assign(BLOCOS, { spotify: true, agenda: true, whatsapp: true, sessoes: true });
  M.comp = i.comp; M.configurado = true; M.ini = null; M.sel = teclas[0]?.id;
  gravar(); pintarIni(0); M.pop = true; pintar(); avisar('O Deck mora aqui, na barra de menus');
}
$('#ini').addEventListener('click', e => {
  e.stopPropagation();
  const i = M.ini; if (!i) return;
  const ps = passosIni();
  if (e.target.closest('[data-ini-ir]')) { if (i.passo === ps.length - 1) return concluirIni(); i.passo++; return pintarIni(1) }
  if (e.target.closest('[data-ini-voltar]')) { i.passo--; return pintarIni(-1) }
  if (e.target.closest('[data-ini-pular]')) { i.passo++; return pintarIni(1) }
  const ci = e.target.closest('[data-comp-ini]'); if (ci) { i.comp = ci.dataset.compIni; return pintarIni(0) }
  const co = e.target.closest('[data-conta-ini]'); if (co) { i.contas.has(co.dataset.contaIni) ? i.contas.delete(co.dataset.contaIni) : i.contas.add(co.dataset.contaIni); return pintarIni(0) }
  const sg = e.target.closest('[data-sug]'); if (sg) { i.teclas.has(sg.dataset.sug) ? i.teclas.delete(sg.dataset.sug) : i.teclas.add(sg.dataset.sug); return pintarIni(0) }
  if (e.target.closest('[data-conectar-ini]')) return abrirConta();
  const pi = e.target.closest('[data-perm-ini]'); if (pi) return pedirPerm(pi.dataset.permIni);
  const li = e.target.closest('[data-liberar-ini]'); if (li) { const p = PERMS.find(x => x.id === li.dataset.liberarIni); avisar(`Abre ${p.onde}. Ligue o Deck lá e volte`); setTimeout(() => { M.perms[p.id] = true; pintar(); if (M.ini) pintarIni(0); avisar(`${p.nome}: liberado`) }, 1400) }
});
