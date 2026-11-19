/* As telas do app nativo em cima do painel (prototipo/nativo.html, aprovado em 10/11/2026): pareamento
   e o aviso do canal em uso. O painel é o de sempre. Aqui só entra o que é novo, e o estado vem do Swift
   (FluxoPareamento): esta página só desenha e manda as ações. O CSS é o prototipo/nativo.css. */
(function () {
  'use strict';
  const ponte = window.webkit.messageHandlers.deck;
  const tela = document.getElementById('tela');
  if (!tela) return;

  const IC = {
    cabo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 2v5M15 2v5M7 7h10v4a5 5 0 0 1-10 0V7ZM12 16v6"/></svg>',
    bt: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 7 10 10-5 5V2l5 5L7 17"/></svg>',
    mac: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/></svg>',
  };
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const falar = async msg => JSON.parse(await ponte.postMessage(msg));

  const inicio = window.DECK_NATIVO_INICIO || {};
  let estado = inicio.estado || { etapa: 'vazio', macs: [], codigo: '', nomeMac: '' };
  let canalAtual = inicio.canal || null, dig = '', tChip = 0, busca = inicio.busca || null;

  tela.insertAdjacentHTML('beforeend', `
    <div class="tela-offline pareio" id="pareio" role="status" aria-live="polite"><div></div></div>
    <div class="canal-chip" id="canal-chip" role="status" aria-live="polite"></div>`);
  const pareio = document.getElementById('pareio'), chip = document.getElementById('canal-chip');

  /* ---------- as telas ---------- */
  const T = t => `<strong>${t}</strong>`;
  const D = t => `<span class="dica-off">${t}</span>`;
  const pilula = (txt, { girando, led, ic } = {}) => `<span class="disp">${girando ? '<span class="girando" aria-hidden="true"></span>' : ''}${led ? '<span class="ponto-led" aria-hidden="true"></span>' : ''}<span class="ic">${ic || IC.mac}</span><span>${esc(txt)}</span></span>`;
  const botao = (rot, acao, tipo, extra = '') => `<button class="btn ${tipo}" data-acao="${acao}" ${extra}>${rot}</button>`;
  const link = (rot, acao) => `<button class="link-n" data-acao="${acao}">${rot}</button>`;
  const icVia = via => via === 'cabo' ? IC.cabo : IC.bt;
  const slots = () => `<div class="slots" aria-label="Código de 6 dígitos">${[0, 1, 2, 3, 4, 5].map(i => `<span class="slot ${i === dig.length ? 'atual' : ''}">${dig[i] || ''}</span>`).join('')}</div>`;
  const teclado = () => {
    const t = [1, 2, 3, 4, 5, 6, 7, 8, 9].map(d => `<button class="btn secundario" data-dig="${d}">${d}</button>`);
    return `<div class="teclado-num">${t.join('')}<span></span><button class="btn secundario" data-dig="0">0</button><button class="btn secundario texto" data-apagar>Apagar</button></div>`;
  };
  // O Mac tocado vira o botão de progresso ("Procurando o Mac...") e o resto da lista fica parado: toque duplo não faz nada.
  const ROT_PROGRESSO = { procurandoMac: 'Procurando o Mac...', pareando: 'Pareando...' };
  const emCurso = () => !!estado.progresso;
  function macLinha(m) {
    const sinal = m.perto ? 'Perto, sinal forte' : 'Longe, sinal fraco';
    const meu = emCurso() && estado.alvoId === m.id;
    const acao = meu
      ? `<span class="acao em-curso"><span class="girando" aria-hidden="true"></span>${ROT_PROGRESSO[estado.progresso]}</span>`
      : `<span class="acao">${m.perto ? 'Parear' : ''}</span>`;
    const ativo = m.perto && !emCurso();
    return `<button class="mac-linha${meu ? ' em-curso' : emCurso() ? ' parada' : ''}" ${ativo ? `data-escolher="${esc(m.id)}"` : 'aria-disabled="true"'}${meu ? ' aria-busy="true"' : ''}><span class="ic">${IC.mac}</span><span><b>${esc(m.nome)}</b><small>${sinal}</small></span>${acao}</button>`;
  }
  // Pareamento que não deu certo: o motivo e "Tentar de novo" no mesmo Mac (ou procurar de novo se ele sumiu da lista).
  function falhaDoPareio() {
    return `<div class="falha-par" role="alert">${T('Não consegui parear')}<span class="dica-off">${esc(estado.falha)}</span>` +
      `<div class="botoes-n">${botao('Procurar de novo', 'procurar', 'secundario')}${botao('Tentar de novo', 'tentarDeNovo', 'primario')}</div></div>`;
  }

  function telaPareio() {
    const { etapa, macs, codigo, nomeMac, via } = estado;
    if (etapa === 'pronto') return T('Pareado') + pilula(nomeMac, { led: true, ic: icVia(via) }) +
      D(via === 'cabo' ? 'Conectado pelo cabo. Se ele sair, o Deck troca para o Bluetooth.' : 'Conectado por Bluetooth. Plugue o cabo e o Deck troca sozinho.') +
      botao('Abrir o painel', 'abrirPainel', 'primario');
    if (etapa === 'vazio') return T('Conecte o iPhone ao Mac') + pilula('Nenhum Mac pareado', { ic: IC.bt }) +
      D('Abra o Deck no Mac e deixe o Bluetooth ligado.') + botao('Procurar por perto', 'procurar', 'primario');
    if (etapa === 'procurando') {
      if (estado.falha && !emCurso()) return falhaDoPareio();
      return T('Macs por perto') +
        (macs.length ? `<div class="macs">${macs.map(macLinha).join('')}</div>` : '') +
        (emCurso() ? '' : `<span class="dica-off linha-gira"><span class="girando" aria-hidden="true"></span>Procurando</span>` + link('Conectar pelo cabo com código', 'cabo'));
    }
    if (etapa === 'confirmar') {
      const pareando = estado.progresso === 'pareando';
      return T('Os códigos são iguais?') + `<span class="codigo-n">${esc(codigo)}</span>` + D('O mesmo código aparece no ' + esc(nomeMac) + '.') +
        `<div class="botoes-n">${botao('Não são iguais', 'recusar', 'secundario', pareando ? 'disabled' : '')}` +
        `${botao(pareando ? `<span class="girando" aria-hidden="true"></span>${ROT_PROGRESSO.pareando}` : 'São iguais', 'confirmar', 'primario', pareando ? 'disabled aria-busy="true"' : '')}</div>`;
    }
    if (etapa === 'cabo') return T('Procurando o Mac no cabo') + pilula('Mac com Deck no cabo', { girando: true, ic: IC.cabo }) +
      D('Plugue o cabo e deixe o iPhone desbloqueado. Se ele perguntar, toque em Confiar.') + link('Voltar para o Bluetooth', 'voltarParaBluetooth');
    return `<div class="par-duas"><div class="par-esq">${T('Digite o código que aparece no Mac')}${pilula(nomeMac)}${slots()}${estado.progresso ? `<span class="dica-off linha-gira"><span class="girando" aria-hidden="true"></span>${ROT_PROGRESSO.pareando}</span>` : link('Voltar', 'voltar')}</div>${teclado()}</div>`;
  }

  /* ---------- pintar ---------- */
  function pintar() {
    tela.classList.toggle('pareando', estado.etapa !== 'painel');
    pareio.firstElementChild.innerHTML = telaPareio();
    // tela escura: no app nativo não tem Wi-Fi, o Deck procura pelo cabo e pelo Bluetooth
    const off = document.querySelector('.tela-offline:not(.pareio):not(.acesso) .dica-off');
    if (off) off.textContent = busca || 'Procurando pelo cabo e pelo Bluetooth. Confira se ele está ligado.';
  }
  function aplicar(novo) {
    if (novo.etapa !== 'codigo') dig = '';
    estado = novo;
    pintar();
  }

  // O mesmo aviso do painel (avisar em deck.js). Sem ele, o mesmo markup (#aviso).
  function avisar(txt) {
    if (typeof window.avisar === 'function') return window.avisar(txt, { erro: true });
    const a = document.getElementById('aviso'), t = document.getElementById('aviso-txt'); if (!a || !t) return;
    t.textContent = txt; a.classList.add('erro', 'visivel'); setTimeout(() => a.classList.remove('visivel'), 4000);
  }

  async function acao(nome, extra) {
    let r;
    try { r = await falar({ op: 'acao', acao: nome, ...extra }) } catch { if (emCurso()) { estado = { ...estado, progresso: null }; pintar() } return }
    if (r.estado) aplicar(r.estado);
    // Falha de pareamento já está na tela (com "Tentar de novo"): o aviso de 4 segundos seria o mesmo texto de novo.
    if (r.erro) { dig = ''; pintar(); if (!(r.estado && r.estado.falha)) avisar(r.erro) }
  }

  // O toque responde antes de o Swift responder: o estado de progresso aparece já, e o do Swift (o mesmo) chega logo atrás.
  function escolher(id) {
    estado = { ...estado, progresso: 'procurandoMac', alvoId: id, falha: null };
    pintar();
    return acao('escolher', { id });
  }
  function confirmar() {
    estado = { ...estado, progresso: 'pareando' };
    pintar();
    return acao('confirmar', { ok: true });
  }

  /* ---------- aviso do canal em uso: 3 segundos ao trocar ---------- */
  function mostrarChip(tipo) {
    chip.innerHTML = `${tipo === 'cabo' ? IC.cabo : IC.bt}<span>${tipo === 'cabo' ? 'Pelo cabo' : 'Pelo Bluetooth'}</span>`;
    chip.classList.add('visivel'); clearTimeout(tChip); tChip = setTimeout(() => chip.classList.remove('visivel'), 3000);
  }

  /* ---------- toque ---------- */
  pareio.addEventListener('click', e => {
    // Um passo em andamento: o toque já valeu, o resto da tela espera.
    if (emCurso()) return;
    const d = e.target.closest('[data-dig]');
    if (d) {
      if (dig.length >= 6) return;
      dig += d.dataset.dig;
      if (dig.length < 6) return pintar();
      const digitos = dig; pintar();
      return acao('digitos', { digitos });
    }
    if (e.target.closest('[data-apagar]')) { dig = dig.slice(0, -1); return pintar() }
    const m = e.target.closest('[data-escolher]'); if (m) return escolher(m.dataset.escolher);
    const a = e.target.closest('[data-acao]'); if (!a) return;
    if (a.dataset.acao === 'tentarDeNovo') {
      const mac = (estado.macs || []).find(x => x.id === estado.alvoId && x.perto);
      return mac ? escolher(mac.id) : acao('procurar');
    }
    if (a.dataset.acao === 'recusar') return acao('confirmar', { ok: false });
    if (a.dataset.acao === 'confirmar') return confirmar();
    acao(a.dataset.acao);
  });

  /* O Swift chama estas: o estado do pareamento mudou, o canal em uso mudou, ou o Bluetooth mudou o que diz da busca. */
  window.DeckNativo = {
    busca: texto => { busca = texto || null; pintar() },
    estado: novo => aplicar(novo),
    canal: tipo => {
      const mudou = tipo !== canalAtual; canalAtual = tipo;
      if (mudou && estado.etapa === 'painel') mostrarChip(tipo);
    },
  };

  pintar();
  // a página pode abrir depois do Swift ter mudado de etapa: pede o estado de agora, sem aviso de canal
  falar({ op: 'estado' }).then(r => { if (r.canal) canalAtual = r.canal; if (r.busca) busca = r.busca; if (r.estado) aplicar(r.estado) }).catch(() => {});
})();
