/* Monitor de Atividade no iPhone: a tecla do app abre esta tela. Em cima, os mesmos dados do bloco do monitor (V.monitor,
   que o Mac já manda no estado) em tamanho grande, só os itens que a pessoa deixou ligados nos Ajustes do Mac. Embaixo, os
   5 processos que mais usam processador e os 5 que mais usam memória (GET /api/processos), cada um com "Encerrar", que
   sempre pede confirmação antes. Quem diz se um processo pode ser encerrado é o Mac (`podeEncerrar`).
   Usa as peças de deck.js (V, canal, avisar, abrirFolha, tratarErro, monitorItens, velocidade, nivel) e paineis.js (msgErro). */

const mn = { dados: null, erro: '', seq: 0, confirmando: null, encerrando: null, chave: '', chaveM: '', chaveB: '', toque: false, soltou: 0 }; // confirmando e encerrando: { lista, pid }

const decimal = (n, casas = 1) => n.toFixed(casas).replace('.', ',');
const tamanhoMem = b => b >= 1073741824 ? decimal(b / 1073741824) + ' GB' : Math.round(b / 1048576) + ' MB';
const pctProc = c => decimal(c) + '%';

function abrirMonitor() {
  mn.dados = null; mn.erro = ''; mn.confirmando = null; mn.encerrando = null; mn.chave = ''; mn.chaveM = ''; mn.chaveB = ''; mn.toque = false;
  const c = $('#mn-corpo'); c.innerHTML = '<div id="mn-metricas"></div><div id="mn-baixo"></div>';
  pintarMonitor(true); abrirFolha('#f-monitor'); lerProcessos();
}
async function lerProcessos() {
  const n = ++mn.seq;
  try {
    const d = await canal.processos(); if (n !== mn.seq) return;
    mn.dados = { cpu: Array.isArray(d?.cpu) ? d.cpu : [], memoria: Array.isArray(d?.memoria) ? d.memoria : [] }; mn.erro = '';
  } catch (e) {
    if (n !== mn.seq) return;
    if (e.status === 401) return tratarErro(e);
    const msg = e.status === 404 ? 'Este Mac ainda não lista os processos. Atualize o Deck no Mac.' : msgErro(e);
    if (mn.dados) { if (!mn.erroAvisado) avisar(msg, { erro: true }); mn.erroAvisado = true; return } // com a lista na tela, avisa uma vez só
    mn.erro = msg;
  }
  mn.erroAvisado = false;
  const ainda = pid => [...mn.dados.cpu, ...mn.dados.memoria].some(p => p.pid === pid);
  if (mn.confirmando && !ainda(mn.confirmando.pid)) mn.confirmando = null; // o processo já saiu da lista: a pergunta perdeu o sentido
  pintarMonitor();
}

/* ---------- o que o Mac mede, grande ---------- */
const NOME_ITEM = { cpu: 'Processador', memoria: 'Memória', bateria: 'Bateria', rede: 'Rede' };
function cartaoMonitor(k, m) {
  const barra = (p, nv) => `<span class="mn-barra"><i style="width:${p ?? 0}%"></i></span>`;
  if (k === 'rede') {
    return `<div class="mn-cartao mn-rede" role="group" aria-label="Rede: baixando ${velocidade(m.baixa)}, enviando ${velocidade(m.sobe)}"><span class="mn-rot">Rede</span>
      <span class="mn-duas"><span><span class="mn-seta">${SVG.baixa}</span><b class="mn-num mn-vel">${esc(velocidade(m.baixa))}</b></span><span><span class="mn-seta">${SVG.sobe}</span><b class="mn-num mn-vel">${esc(velocidade(m.sobe))}</b></span></span></div>`;
  }
  const p = m[k], nv = k === 'bateria' ? nivelBateria(m) : nivel(p);
  const rot = k === 'bateria' ? 'Bateria' + (m.naTomada ? ' (na tomada)' : '') : NOME_ITEM[k];
  return `<div class="mn-cartao ${nv}" role="group" aria-label="${rot}: ${p == null ? 'sem medição' : p + '%'}"><span class="mn-rot">${rot}</span>
    <b class="mn-num">${p == null ? '-' : p + '<small>%</small>'}</b>${barra(p)}</div>`;
}
function metricasHTML() {
  const itens = monitorItens();
  if (!V?.monitor || !itens.length) {
    const desligado = !V?.blocos?.monitor;
    return `<div class="vazio-bloco mn-vazio"><strong>${desligado ? 'O monitor está desligado' : 'Nenhum item ligado'}</strong><span>Para ver o processador, a memória, a bateria e a rede aqui, ligue o Monitor do Mac em Ajustes, Este Mac.</span></div>`;
  }
  return `<div class="mn-grade" data-n="${itens.length}">${itens.map(k => cartaoMonitor(k, V.monitor)).join('')}</div>`;
}

/* ---------- processos ---------- */
function linhaProcesso(p, lista) {
  const valor = lista === 'cpu' ? pctProc(p.cpu) : tamanhoMem(p.memoria);
  const nome = esc(p.nome);
  if (mn.confirmando && mn.confirmando.lista === lista && mn.confirmando.pid === p.pid) {
    const indo = mn.encerrando?.pid === p.pid;
    return `<li class="mn-proc confirmando" data-pid="${p.pid}"><span class="mn-pergunta">Encerrar <b>${nome}</b>? O que não foi salvo nele pode ser perdido.</span>
      <span class="mn-acoes"><button class="btn secundario pequeno" data-mn-cancelar${indo ? ' disabled' : ''}>Cancelar</button><button class="btn pequeno mn-sim" data-mn-sim data-pid="${p.pid}"${indo ? ' disabled' : ''}>${indo ? 'Encerrando' : 'Encerrar'}</button></span></li>`;
  }
  return `<li class="mn-proc" data-pid="${p.pid}"><span class="mn-nome">${nome}</span><span class="mn-valor">${valor}</span>
    <span class="mn-fim">${p.podeEncerrar ? `<button class="btn secundario pequeno" data-mn-pedir data-lista="${lista}" data-pid="${p.pid}" aria-label="Encerrar ${nome}">Encerrar</button>` : ''}</span></li>`;
}
const listaHTML = (titulo, lista) => `<section class="mn-secao" aria-label="${titulo}"><h3>${titulo}</h3>${
  mn.dados[lista].length ? `<ul class="mn-lista">${mn.dados[lista].map(p => linhaProcesso(p, lista)).join('')}</ul>` : '<p class="mn-nada">Nenhum processo para mostrar.</p>'}</section>`;
const esqueletoMn = () => '<div class="esq-lista" aria-hidden="true">' + '<div class="mn-proc esq"><i class="barra" style="width:45%"></i><i class="barra" style="width:56px"></i></div>'.repeat(5) + '</div>';

/* O corpo tem duas partes que se repintam sozinhas: os cartões (mudam quase a cada segundo, não têm botão) e as listas (têm
   Encerrar). Repintar a lista com o dedo em cima do botão destrói o botão e o clique se perde, então enquanto há toque em
   andamento (e uns instantes depois) a lista espera. `forcar` é o clique da própria pessoa, que repinta na hora. */
const tocando = () => mn.toque || Date.now() - mn.soltou < 400;
function pintarMonitor(forcar) {
  const corpo = $('#mn-corpo'), metricas = metricasHTML();
  let baixo;
  if (!mn.dados) baixo = mn.erro ? `<div class="vazio-bloco mn-vazio"><strong>Não deu para ler</strong><span>${esc(mn.erro)}</span><button class="btn secundario pequeno" data-mn-tentar style="justify-self:start">Tentar de novo</button></div>` : esqueletoMn();
  else baixo = `<div class="mn-listas">${listaHTML('Mais usam o processador', 'cpu')}${listaHTML('Mais usam a memória', 'memoria')}</div>`;
  corpo.setAttribute('aria-busy', String(!mn.dados && !mn.erro));
  const y = corpo.scrollTop;
  if (metricas !== mn.chaveM) { mn.chaveM = metricas; $('#mn-metricas').innerHTML = metricas }
  if (baixo !== mn.chaveB && (forcar || !tocando())) { mn.chaveB = baixo; $('#mn-baixo').innerHTML = baixo }
  corpo.scrollTop = y;
}
$('#mn-corpo').addEventListener('pointerdown', () => { mn.toque = true });
const soltarMn = () => { mn.toque = false; mn.soltou = Date.now() };
$('#mn-corpo').addEventListener('pointerup', soltarMn);
$('#mn-corpo').addEventListener('pointercancel', soltarMn);

async function encerrarProcesso(pid, nome) {
  mn.encerrando = { pid }; pintarMonitor(true);
  try {
    await canal.encerrarProcesso(pid, nome);
    mn.confirmando = null; mn.encerrando = null; avisar(`Pedi para o ${nome} fechar`);
    await new Promise(r => setTimeout(r, 600)); // o programa leva um instante para sair
  } catch (e) {
    mn.encerrando = null; mn.confirmando = null; tratarErro(e);
  }
  lerProcessos();
}

$('#f-monitor').addEventListener('click', ev => {
  const pedir = ev.target.closest('[data-mn-pedir]');
  if (pedir) { mn.confirmando = { lista: pedir.dataset.lista, pid: Number(pedir.dataset.pid) }; return pintarMonitor(true) }
  if (ev.target.closest('[data-mn-cancelar]')) { mn.confirmando = null; return pintarMonitor(true) }
  const sim = ev.target.closest('[data-mn-sim]');
  if (sim && !mn.encerrando) {
    const pid = Number(sim.dataset.pid), p = [...mn.dados.cpu, ...mn.dados.memoria].find(x => x.pid === pid); // o nome é o que a tela mostrava: o Mac confere
    return p && encerrarProcesso(pid, p.nome);
  }
  if (ev.target.closest('[data-mn-tentar]')) { mn.erro = ''; mn.dados = null; pintarMonitor(true); lerProcessos() }
});

/* aberta, a tela repinta o monitor a cada segundo (V.monitor chega com o estado) e relê os processos a cada 3 s.
   Com a pergunta de confirmar na tela a lista não é relida: o processo não troca de lugar embaixo do dedo. */
let ticMn = 0;
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-monitor') { ticMn = 0; return }
  pintarMonitor();
  if (++ticMn % 3 === 0 && !mn.confirmando && !mn.encerrando) lerProcessos();
}, 1000);
