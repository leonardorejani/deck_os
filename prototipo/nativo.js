/* Protótipo do app nativo (fase 5). O painel é o de verdade: traz o markup do index.html e roda o
   dados.js e o deck.js dele. Aqui só entra o que é novo: o pareamento e o canal em uso. */
(async function () {
  const palco = document.querySelector('.palco');
  const html = await fetch('index.html').then(r => r.text());
  const doc = new DOMParser().parseFromString(html, 'text/html');
  palco.innerHTML = doc.querySelector('.palco').innerHTML;
  for (const s of doc.querySelectorAll('script[src]')) {
    await new Promise((ok, falha) => { const el = document.createElement('script'); el.src = s.getAttribute('src'); el.onload = ok; el.onerror = falha; document.body.append(el) });
  }
  iniciar();
})().catch(() => { document.querySelector('.palco').innerHTML = '<p class="erro-carga">Não consegui carregar o painel. Abra por um servidor local: python3 -m http.server dentro de prototipo/.</p>' });

let dig = '', tChip;
const CODIGO_CERTO = NATIVO_CODIGO.replace(' ', '');

function iniciar() {
  // o iPhone vem deitado e o painel é o mesmo do index.html
  montarControles();
  const renderPainel = render;
  render = function () { renderPainel(); depoisDoRender() };
  nativoAoMudar(() => { dig = ''; pintarTudo() });
  tela.addEventListener('click', aoClicar);
  addEventListener('keydown', aoTeclar);
  depoisDoRender();
}

/* ---------- controles do protótipo ---------- */
function grupoHTML(titulo, grupo, lista, so) {
  return `<div class="controle" ${so ? `data-so="${so}"` : ''}><h2>${titulo}</h2><div class="opcoes" data-nativo="${grupo}">${lista.map(([v, rot]) => `<button data-v="${v}">${rot}</button>`).join('')}</div></div>`;
}
function montarControles() {
  const c = document.getElementById('controles');
  c.insertAdjacentHTML('afterbegin',
    grupoHTML('Pergunta', 'pergunta', [['1', '1. Como o app pareia'], ['2', '2. Como mostra o canal']]) +
    grupoHTML('Etapa do pareamento', 'et', NATIVO_ETAPAS, '1') +
    grupoHTML('Canal agora', 'canal', [['cabo', 'Cabo'], ['bluetooth', 'Bluetooth']], '2'));
  c.addEventListener('click', e => {
    const b = e.target.closest('[data-nativo] button'); if (!b) return;
    const g = b.parentElement.dataset.nativo, antes = nativoEstado[g];
    if (antes === b.dataset.v) return;
    nativoPublicar({ [g]: b.dataset.v }); dig = '';
    pintarTudo(g === 'canal');
  });
}
function marcarControles() {
  document.querySelectorAll('[data-nativo]').forEach(g => g.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(nativoEstado[g.dataset.nativo] === b.dataset.v))));
  document.querySelectorAll('[data-so]').forEach(c => { c.hidden = c.dataset.so !== nativoEstado.pergunta });
}

/* ---------- pintar ---------- */
function pintarTudo(trocouCanal) {
  render(); // volta por depoisDoRender
  if (trocouCanal) mostrarChip();
}
function depoisDoRender() {
  const n = nativoEstado;
  if (!document.getElementById('pareio')) montarPecas();
  tela.classList.toggle('pareando', n.pergunta === '1');
  $('#pareio > div').innerHTML = telaPareio();
  // tela escura: no app nativo não tem Wi-Fi, o Deck procura pelo cabo e pelo Bluetooth
  $('.tela-offline:not(.pareio) .dica-off').textContent = 'Procurando pelo cabo e pelo Bluetooth. Confira se ele está ligado.';
  marcarControles();
  pintarLegenda();
}
function montarPecas() {
  tela.insertAdjacentHTML('beforeend', `
    <div class="tela-offline pareio" id="pareio" role="status" aria-live="polite"><div></div></div>
    <div class="canal-chip" id="canal-chip" role="status" aria-live="polite"></div>`);
}
function mostrarChip() {
  const n = nativoEstado; if (n.pergunta !== '2' || E.mac === 'off') return;
  const c = $('#canal-chip');
  c.innerHTML = `${n.canal === 'bluetooth' ? NATIVO_IC.bt : NATIVO_IC.cabo}<span>${n.canal === 'bluetooth' ? 'Pelo Bluetooth' : 'Pelo cabo'}</span>`;
  c.classList.add('visivel'); clearTimeout(tChip); tChip = setTimeout(() => c.classList.remove('visivel'), 3000);
}

/* ---------- tela de pareamento ---------- */
const T = t => `<strong>${t}</strong>`;
const D = t => `<span class="dica-off">${t}</span>`;
const pilula = (txt, { girando, led, ic } = {}) => `<span class="disp">${girando ? '<span class="girando" aria-hidden="true"></span>' : ''}${led ? '<span class="ponto-led" aria-hidden="true"></span>' : ''}<span class="ic">${ic || NATIVO_IC.mac}</span><span>${esc(txt)}</span></span>`;
const botao = (rot, acao, tipo) => `<button class="btn ${tipo}" data-n-et="${acao}">${rot}</button>`;
function slotsHTML() { return `<div class="slots" aria-label="Código de 6 dígitos">${[0, 1, 2, 3, 4, 5].map(i => `<span class="slot ${i === dig.length ? 'atual' : ''}">${dig[i] || ''}</span>`).join('')}</div>` }
function tecladoHTML() {
  const t = [1, 2, 3, 4, 5, 6, 7, 8, 9].map(d => `<button class="btn secundario" data-dig="${d}">${d}</button>`);
  return `<div class="teclado-num">${t.join('')}<span></span><button class="btn secundario" data-dig="0">0</button><button class="btn secundario texto" data-apagar>Apagar</button></div>`;
}
const link = (rot, acao) => `<button class="link-n" data-n-et="${acao}">${rot}</button>`;
function telaPareio() {
  const { op, et } = nativoEstado;
  if (et === 'pronto') return T('Pronto') + pilula(nomeMac, { led: true, ic: op === 'a' ? NATIVO_IC.cabo : NATIVO_IC.bt }) +
    D(op === 'a' ? 'Conectado pelo cabo. Se ele sair, o Deck troca para o Bluetooth.' : 'Conectado por Bluetooth. Plugue o cabo e o Deck troca sozinho.') +
    `<button class="btn primario" data-n-painel>Abrir o painel</button>`;
  if (et === 'vazio') return T('Conecte o iPhone ao Mac') + pilula('Nenhum Mac pareado', { ic: NATIVO_IC.bt }) +
    D('Abra o Deck no Mac e deixe o Bluetooth ligado.') + botao('Procurar por perto', 'procurando', 'primario');
  if (et === 'procurando') {
    const linha = (nome, sinal, quem) => `<button class="mac-linha" data-n-et="${quem ? 'confirmar' : ''}"><span class="ic">${NATIVO_IC.mac}</span><span><b>${nome}</b><small>${sinal}</small></span><span class="acao">${quem ? 'Parear' : ''}</span></button>`;
    return T('Macs por perto') + `<div class="macs">${linha(esc(nomeMac), 'Perto, sinal forte', true)}${linha('Mac mini do estúdio', 'Longe, sinal fraco', false)}</div>` +
      `<span class="dica-off linha-gira"><span class="girando" aria-hidden="true"></span>Procurando</span>` + link('Conectar pelo cabo com código', 'cabo');
  }
  if (et === 'confirmar') return T('Os códigos são iguais?') + `<span class="codigo-n">${NATIVO_CODIGO}</span>` + D('O mesmo código aparece no ' + esc(nomeMac) + '.') +
    `<div class="botoes-n">${botao('Não são iguais', 'vazio', 'secundario')}${botao('São iguais', 'pronto', 'primario')}</div>`;
  if (et === 'cabo') return T('Procurando o Mac no cabo') + pilula('Mac com Deck no cabo', { girando: true, ic: NATIVO_IC.cabo }) + D('Plugue o cabo e deixe o iPhone desbloqueado. Se ele perguntar, toque em Confiar.') + link('Voltar para o Bluetooth', 'procurando');
  return `<div class="par-duas"><div class="par-esq">${T('Digite o código que aparece no Mac')}${pilula(nomeMac)}${slotsHTML()}${link('Voltar', 'cabo')}</div>${tecladoHTML()}</div>`;
}

const LEGENDA = {
  vazio: 'Primeira abertura, nenhum Mac pareado. O caminho principal é o Bluetooth: o botão procura os Macs com o Deck aberto.',
  procurando: 'Lista dos Macs com Deck por perto. Toque no seu. O outro Mac aparece sem nenhuma ação. O link discreto embaixo leva à segunda via, pelo cabo.',
  confirmar: 'Os dois mostram o mesmo código (483 291). Se for igual, a pessoa confirma aqui e toca em Permitir no Mac.',
  pronto: 'Pareado. Por Bluetooth, o canal troca sozinho para o cabo quando ele é plugado, e o aviso de canal aparece (pergunta 2).',
  cabo: 'Segunda via, como o "conectar com código" do WhatsApp. O app procura o Mac pelo cabo. Se o iPhone perguntar "Confiar neste computador?", é do iOS.',
  codigo: 'O Mac mostra um código de 6 dígitos (nesta prova, 483 291). A pessoa digita aqui. Código errado limpa e avisa.',
};
function pintarLegenda() {
  const n = nativoEstado, el = $('#legenda');
  const mac = `mac.html?et=${n.et}&canal=${n.canal}&ren=${n.ren}&op=${n.op}`;
  document.getElementById('l-mac').href = mac;
  el.innerHTML = n.pergunta === '1'
    ? `<span><b>${NATIVO_ETAPAS.find(e => e[0] === n.et)[1].replace(/^\d\. /, '')}.</b> ${LEGENDA[n.et]}</span><span><a href="${mac}" target="_blank" rel="noopener">Ver o que o Mac mostra nesta etapa</a></span>`
    : `<span><b>Aviso de 3 segundos ao trocar.</b> Troque o canal (Cabo e Bluetooth) e um aviso curto, com o ícone do canal, aparece no alto e some sozinho. Nada fica na tela. A tela escura (Mac: Desconectado) também mostra os canais.</span>`;
}

/* ---------- toque e teclado ---------- */
function digitar(d) {
  if (dig.length >= 6) return;
  dig += d;
  if (dig.length < 6) return depoisDoRender();
  if (dig === CODIGO_CERTO) { dig = ''; nativoPublicar({ et: 'pronto', op: 'a', canal: 'cabo' }); return depoisDoRender() }
  dig = ''; depoisDoRender(); avisar('Código errado. Confira o que aparece no Mac.', { erro: true });
}
function aoClicar(e) {
  const d = e.target.closest('[data-dig]'); if (d) return digitar(d.dataset.dig);
  if (e.target.closest('[data-apagar]')) { dig = dig.slice(0, -1); return depoisDoRender() }
  const et = e.target.closest('[data-n-et]'); if (et) { if (et.dataset.nEt) { dig = ''; nativoPublicar({ et: et.dataset.nEt }); depoisDoRender(); if (et.dataset.nEt === 'cabo') setTimeout(() => { if (nativoEstado.et === 'cabo') { nativoPublicar({ et: 'codigo' }); depoisDoRender() } }, 2200) } return }
  if (e.target.closest('[data-n-painel]')) { nativoPublicar({ pergunta: '2', canal: nativoEstado.op === 'a' ? 'cabo' : 'bluetooth' }); return pintarTudo() }
}
function aoTeclar(e) {
  const n = nativoEstado; if (n.pergunta !== '1' || n.et !== 'codigo') return;
  if (/^[0-9]$/.test(e.key)) digitar(e.key);
  if (e.key === 'Backspace') { dig = dig.slice(0, -1); depoisDoRender() }
}
