/* Apps do Mac no editor de tecla: a lista dos apps instalados no Mac de quem usa (GET /api/apps), com busca e o ícone de cada um,
   e o que a tecla faz além de abrir o app (a caixa de entrada de uma conta do Mail, um endereço no navegador, uma pasta das
   Notas...), que o Mac descobre em GET /api/apps/<id>/acoes. Nada aqui é fixo: tudo vem do Mac. Mac antigo, que não tem as
   rotas, cai na lista curta de sempre (APPS, em util.js). Usa as peças de deck.js (rasc, canal, avisar, pintarTipo) e é
   carregado antes dele, então só as toca quando a pessoa age. */

/* "Navegador padrão" não é um app da lista: é o que o Mac abre para um endereço quando a tecla não escolhe navegador */
const NAVEGADOR_PADRAO = { nome: 'Navegador padrão', valor: 'navegador-padrao', bundle: 'navegador-padrao', navegador: true };
const appsMac = { lista: null, estado: 'nada', versao: 0, em: 0 }; // estado: nada | lendo | ok | antigo (Mac sem a rota) | erro
const VALIDADE_APPS = 60000; // reler a lista ao abrir o editor, no máximo uma vez por minuto

async function carregarApps(forcar) {
  if (appsMac.estado === 'lendo' || appsMac.estado === 'antigo') return;
  if (!forcar && appsMac.lista && performance.now() - appsMac.em < VALIDADE_APPS) return;
  appsMac.estado = 'lendo';
  try { const l = await canal.apps(); appsMac.lista = Array.isArray(l) ? l : []; appsMac.estado = 'ok'; appsMac.em = performance.now() }
  catch (e) {
    if (e.status === 401) { appsMac.estado = appsMac.lista ? 'ok' : 'nada'; return tratarErro(e) }
    appsMac.estado = e.status === 404 ? 'antigo' : appsMac.lista ? 'ok' : 'erro'; // com a lista antiga na mão, segue com ela
  }
  appsMac.versao++;
  if (folhaAberta?.id === 'f-editor' && rasc?.tipo === 'app') { // o editor aberto troca a lista curta pela do Mac
    pintarTipo();
    if (edApp.passo === 'acao' && edApp.acoesEstado === 'lendo') lerAcoes();
  }
  if (V) atualizar(); // e as teclas de app sem ícone próprio ganham o do Mac
}
const appDoMac = valor => valor === NAVEGADOR_PADRAO.valor ? NAVEGADOR_PADRAO : valor === CONTROLES_DO_MAC.valor ? CONTROLES_DO_MAC : appsMac.lista?.find(a => a.valor === valor);
const iconeDoApp = a => a.controles ? `<span class="svg">${SVG.controles}</span>` : a.bundle === NAVEGADOR_PADRAO.bundle ? `<span class="svg">${SVG.globo}</span>` : `<img src="${esc(canal.appIconeUrl(a.bundle))}" loading="lazy" alt="">`;

/* O ícone de uma tecla de app: o do app, se a página já o tem; senão o que o Mac tem. Sem nenhum dos dois, o raio de sempre */
function iconeDaTecla(t) {
  const ic = t.icone ?? (t.tipo === 'app' ? t.valor : null);
  if (t.tipo !== 'app' || (ic && (ic.startsWith('svg:') || icApp(ic)))) return iconeHTML(ic);
  if (appsMac.estado === 'nada') carregarApps();
  const a = appDoMac(t.valor);
  return a ? iconeDoApp(a) : iconeHTML(ic);
}

/* ---------- o editor ---------- */
const edApp = { passo: 'escolher', busca: '', acoes: null, acoesEstado: '', seq: 0, nomeAuto: false, sugestao: '' };
const semAcento = s => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

/* chamado quando o editor abre: tecla já com app volta direto para o que ela faz, tecla nova começa escolhendo o app */
function iniciarEditorApp(nova) {
  edApp.busca = ''; edApp.acoes = null; edApp.acoesEstado = ''; edApp.sugestao = ''; edApp.nomeAuto = nova;
  edApp.passo = rasc.tipo === 'app' && rasc.valor ? 'acao' : 'escolher';
  carregarApps();
  if (edApp.passo === 'acao') lerAcoes();
}
async function lerAcoes() {
  const n = ++edApp.seq, app = appDoMac(rasc.valor);
  edApp.acoes = null; edApp.acoesEstado = 'lendo';
  if (!app) { // sem a lista do Mac (ou app que sumiu): não há o que perguntar, a tecla só abre o app
    if (appsMac.estado === 'lendo') return;
    edApp.acoesEstado = appsMac.estado === 'ok' ? 'sumiu' : 'nenhuma'; return pintarAcoes();
  }
  if (app.controles) { edApp.acoes = []; edApp.acoesEstado = 'ok'; return pintarAcoes() } // tela do próprio iPhone: não há o que perguntar ao Mac
  pintarAcoes();
  try { const r = await canal.acoesDoApp(app.bundle); if (n !== edApp.seq) return; edApp.acoes = Array.isArray(r?.acoes) ? r.acoes : []; edApp.acoesEstado = 'ok' }
  catch (e) {
    if (n !== edApp.seq) return;
    if (e.status === 401) return tratarErro(e);
    edApp.acoesEstado = e.status === 404 ? 'sumiu' : 'erro'; edApp.erro = e.rede ? 'Sem conexão com o Mac. Confira o Wi-Fi.' : e.message;
  }
  pintarAcoes();
}

function appEditorHTML() {
  if (appsMac.estado === 'antigo' || (appsMac.estado !== 'ok' && appsMac.estado !== 'lendo' && !appsMac.lista)) {
    // sem a lista do Mac: a lista curta de sempre, e se foi erro, o aviso com a saída
    const aviso = appsMac.estado === 'erro' ? '<span class="ajuda">Não deu para ler os apps do Mac. Aqui estão os mais comuns.</span><button class="btn secundario pequeno" data-apps-tentar style="justify-self:start">Tentar de novo</button>' : '';
    return `<span class="rotulo">Qual app</span><div class="lista-apps">${APPS.map(a => `<button data-app="${esc(a.nome)}" aria-pressed="${a.nome === rasc.valor}"><img src="${a.ic}" alt="">${esc(a.nome)}</button>`).join('')}</div>${aviso}<span class="ajuda">Escolha o app que a tecla abre no Mac.</span>`;
  }
  if (edApp.passo === 'acao' && rasc.valor) {
    const a = appDoMac(rasc.valor);
    return `<span class="rotulo">App</span><div class="app-escolhido"><span class="ic-app">${a ? iconeDoApp(a) : ''}</span><b>${esc(a?.nome || rasc.valor)}</b><button class="btn secundario pequeno" data-app-trocar>Trocar</button></div><div id="ed-acoes">${acoesHTML()}</div>`;
  }
  return `<span class="rotulo">Qual app</span><input id="ed-busca" type="search" placeholder="Buscar app" value="${esc(edApp.busca)}" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Buscar app"><div class="lista-apps real" id="ed-lista-apps" role="listbox" aria-label="Apps do Mac">${listaAppsHTML()}</div><button class="btn secundario pequeno" data-app-controles style="justify-self:start">${SVG.controles}Controles do Mac</button>`;
}
function listaAppsHTML() {
  if (!appsMac.lista) return `<div class="esq-lista" aria-hidden="true">${'<span class="esq-app"><i class="barra"></i><i class="barra"></i></span>'.repeat(8)}</div>`;
  const q = semAcento(edApp.busca.trim());
  const itens = [NAVEGADOR_PADRAO, ...appsMac.lista].filter(a => !q || semAcento(a.nome).includes(q));
  if (!itens.length) return '<span class="ajuda vazio-busca">Nenhum app com esse nome.</span>';
  return itens.map(a => `<button role="option" data-app-bundle="${esc(a.bundle)}" aria-selected="${a.valor === rasc.valor}" aria-pressed="${a.valor === rasc.valor}">${iconeDoApp(a)}<span>${esc(a.nome)}</span></button>`).join('');
}

function acoesHTML() {
  const e = edApp;
  if (e.acoesEstado === 'lendo') return '<span class="rotulo">O que a tecla faz</span><span class="ajuda">Lendo o que o app oferece. O Mac pode pedir permissão para o Deck controlar o app: toque em Permitir nele.</span>';
  if (e.acoesEstado === 'erro') return `<span class="rotulo">O que a tecla faz</span><span class="ajuda">${esc(e.erro || 'Não deu para ler o que o app oferece.')}</span><button class="btn secundario pequeno" data-acoes-tentar style="justify-self:start">Tentar de novo</button>`;
  if (e.acoesEstado === 'sumiu') return '<span class="ajuda">Esse app não foi achado neste Mac. A tecla vai tentar abrir mesmo assim.</span>';
  const acoes = e.acoes || [];
  if (!acoes.length) return `<span class="ajuda">${rasc.valor === CONTROLES_DO_MAC.valor ? 'A tecla abre os controles do Mac aqui no iPhone.' : 'A tecla abre o app.'}</span>`;
  const atual = rasc.acao?.id || '';
  const opcoes = [{ id: '', nome: 'Só abrir o app' }, ...acoes].map(a => `<button class="opcao" role="radio" aria-checked="${a.id === atual}" data-acao-id="${esc(a.id)}">${esc(a.nome)}</button>`).join('');
  return `<span class="rotulo">O que a tecla faz</span><div class="opcoes" role="radiogroup" aria-label="O que a tecla faz">${opcoes}</div>${escolhaDaAcaoHTML(acoes.find(a => a.id === atual))}`;
}
function escolhaDaAcaoHTML(a) {
  if (!a || a.entrada === 'nenhuma') return '';
  const valor = rasc.acao?.valor || '';
  if (a.entrada === 'lista') {
    const aviso = a.aviso ? `<span class="ajuda aviso-acao">${esc(a.aviso)}</span>` : '';
    const itens = (a.opcoes || []).map(o => `<button class="opcao" role="radio" aria-checked="${o.valor === valor}" data-acao-valor="${esc(o.valor)}"><b>${esc(o.nome)}</b>${o.detalhe ? `<small>${esc(o.detalhe)}</small>` : ''}</button>`).join('');
    return `<span class="rotulo">${esc(a.rotulo || 'Escolha')}</span>${aviso}<div class="opcoes" role="radiogroup" aria-label="${esc(a.rotulo || 'Escolha')}">${itens}</div>`;
  }
  return `<div class="campo-acao"><label class="rotulo" for="ed-acao-texto">${esc(a.rotulo || 'Valor')}</label><input id="ed-acao-texto" value="${esc(valor)}" placeholder="${esc(a.exemplo || '')}" autocomplete="off" autocapitalize="off" spellcheck="false"></div>`;
}
function pintarAcoes() {
  const el = $('#ed-acoes'); if (!el) return;
  const y = $('#f-editor .corpo')?.scrollTop ?? 0;
  el.innerHTML = acoesHTML();
  const c = $('#f-editor .corpo'); if (c) c.scrollTop = y;
}

/* o nome da tecla acompanha a escolha enquanto a pessoa não mexe nele ("Mail", depois "Mail Trabalho") */
function sugerirNome() {
  if (!edApp.nomeAuto) return;
  const app = appDoMac(rasc.valor), acao = edApp.acoes?.find(a => a.id === rasc.acao?.id);
  const op = acao?.entrada === 'lista' ? acao.opcoes?.find(o => o.valor === rasc.acao.valor) : null;
  const nome = [app?.nome || rasc.valor, op?.nome].filter(Boolean).join(' ');
  $('#ed-nome').value = edApp.sugestao = nome;
}
$('#ed-nome').addEventListener('input', () => { if ($('#ed-nome').value !== edApp.sugestao) edApp.nomeAuto = false });

function escolherApp(a) {
  rasc.valor = a.valor; rasc.icone = a.controles ? 'svg:controles' : a.valor; delete rasc.acao;
  edApp.passo = 'acao'; sugerirNome(); pintarTipo(); lerAcoes();
}
/* o que falta preencher na ação antes de gravar, ou nada */
function faltaNaAcao() {
  if (rasc.tipo !== 'app' || !rasc.acao) return null;
  const a = edApp.acoes?.find(x => x.id === rasc.acao.id);
  if (!a || a.entrada === 'nenhuma' || (rasc.acao.valor || '').trim()) return null;
  return a.entrada === 'lista' ? `Escolha: ${(a.rotulo || 'uma opção').toLowerCase()}` : `Preencha: ${(a.rotulo || 'o valor').toLowerCase()}`;
}

$('#ed-acao').addEventListener('input', ev => {
  if (ev.target.id === 'ed-busca') { edApp.busca = ev.target.value; $('#ed-lista-apps').innerHTML = listaAppsHTML(); return }
  if (ev.target.id === 'ed-acao-texto' && rasc.acao) rasc.acao.valor = ev.target.value;
});
$('#ed-acao').addEventListener('click', ev => {
  if (ev.target.closest('[data-app-controles]')) return escolherApp(CONTROLES_DO_MAC);
  const b = ev.target.closest('[data-app-bundle]');
  if (b) { const a = appDoMac(b.dataset.appBundle === NAVEGADOR_PADRAO.bundle ? NAVEGADOR_PADRAO.valor : appsMac.lista?.find(x => x.bundle === b.dataset.appBundle)?.valor); if (a) escolherApp(a); return }
  if (ev.target.closest('[data-app-trocar]')) { edApp.passo = 'escolher'; edApp.busca = ''; edApp.seq++; return pintarTipo() }
  if (ev.target.closest('[data-apps-tentar]')) { appsMac.estado = 'nada'; carregarApps(true); return }
  if (ev.target.closest('[data-acoes-tentar]')) return lerAcoes();
  const ac = ev.target.closest('[data-acao-id]');
  if (ac) { rasc.acao = ac.dataset.acaoId ? { id: ac.dataset.acaoId, valor: '' } : undefined; if (!rasc.acao) delete rasc.acao; sugerirNome(); pintarAcoes(); return }
  const op = ev.target.closest('[data-acao-valor]');
  if (op && rasc.acao) { rasc.acao.valor = op.dataset.acaoValor; sugerirNome(); pintarAcoes() }
});
