/* Monitor de Atividade no iPhone: a tecla do app abre esta tela. Uma grade de cartões com o que o Mac mede (V.monitor, que o Mac
   já manda no estado): CPU, GPU, memória, bateria, rede, disco disponível, energia, ventoinhas e dispositivos conectados. Só
   aparece o que a pessoa deixou ligado na tecla do Monitor, nos Ajustes do Mac, e o que o Mac conseguiu ler (medida ausente some, não vira "-").
   O cartão não é refeito a cada segundo: os mesmos elementos são atualizados, e o número conta do valor antigo ao novo
   (tatile, movimento, regra 9: 600 ms, ease-out cúbico, algarismos de largura fixa).
   Usa as peças de deck.js (V, folhaAberta, semAcesso, offline, monitorItens, velocidade, nivel, nivelBateria) e util.js (SVG, esc). */

const ORDEM_MONITOR = ['cpu', 'gpu', 'memoria', 'bateria', 'rede', 'disco', 'energia', 'ventoinhas', 'dispositivos'];
const mn = { chave: '' };

const decimal = (n, casas = 1) => n.toFixed(casas).replace('.', ',');
const inteiro = n => Math.round(n).toLocaleString('pt-BR');
const pct = n => `${Math.round(n)}<small>%</small>`;
/* Disco em GB decimais, como o Finder mostra: sem casa decimal a partir de 10 GB */
const tamanhoDisco = b => b >= 1e12 ? `${decimal(b / 1e12, 2)}<small>TB</small>` : b >= 1e10 ? `${Math.round(b / 1e9)}<small>GB</small>` : `${decimal(b / 1e9)}<small>GB</small>`;
const nivelDisco = usado => usado >= 95 ? 'cheio' : usado >= 85 ? 'alto' : '';

/* O que cada cartão sabe dizer: `ler(m)` devolve null (o Mac não leu: o cartão some) ou { nums, fmt, barra, nivel, tag, rotulo }.
   CPU, memória e rede nunca devolvem null: na primeira leitura ainda não há taxa e o cartão mostra "-" até a segunda.
   nums são os valores que contam (o de rede tem dois), fmt desenha cada um, barra vai de 0 a 100 (null: sem barra). */
const CARTOES = {
  cpu: { rot: 'CPU', ic: 'cpu', ler: m => ({ nums: [m.cpu], fmt: pct, barra: m.cpu ?? 0, nivel: nivel(m.cpu) }) },
  gpu: { rot: 'GPU', ic: 'gpu', ler: m => m.gpu == null ? null : { nums: [m.gpu], fmt: pct, barra: m.gpu, nivel: nivel(m.gpu) } },
  memoria: { rot: 'Memória', ic: 'memoria', ler: m => ({ nums: [m.memoria], fmt: pct, barra: m.memoria ?? 0, nivel: nivel(m.memoria) }) },
  bateria: { rot: 'Bateria', ic: 'bateria', ler: m => m.bateria == null ? null : { nums: [m.bateria], fmt: pct, barra: m.bateria, nivel: nivelBateria(m), tag: m.naTomada ? 'na tomada' : '' } },
  rede: { rot: 'Rede', ic: 'rede', rede: true, ler: m => ({ nums: [m.baixa, m.sobe], fmt: n => esc(velocidade(n)), barra: null, nivel: '', rotulo: `Rede: baixando ${velocidade(m.baixa)}, enviando ${velocidade(m.sobe)}` }) },
  disco: {
    rot: 'Disco disponível', ic: 'disco',
    ler: m => {
      if (m.discoLivre == null || !(m.discoTotal > 0)) return null;
      const usado = Math.max(0, Math.min(100, 100 - m.discoLivre / m.discoTotal * 100));
      return { nums: [m.discoLivre], fmt: tamanhoDisco, barra: usado, nivel: nivelDisco(usado), rotulo: `Disco disponível: ${tamanhoDisco(m.discoLivre).replace(/<[^>]+>/g, ' ')}` };
    },
  },
  energia: { rot: 'Energia', ic: 'raio', ler: m => m.watts == null ? null : { nums: [m.watts], fmt: n => `${decimal(n)}<small>W</small>`, barra: null, nivel: '', tag: m.carregando ? 'carregando' : '' } },
  ventoinhas: {
    rot: 'Ventoinhas', ic: 'ventoinha',
    ler: m => {
      if (!Array.isArray(m.ventoinhas) || !m.ventoinhas.length) return null;
      const media = m.ventoinhas.reduce((a, b) => a + b, 0) / m.ventoinhas.length, p = m.ventoinhaMax > 0 ? Math.min(100, media / m.ventoinhaMax * 100) : null;
      return { nums: [media], fmt: n => `${inteiro(n)}<small>RPM</small>`, barra: p, nivel: p == null ? '' : nivel(p), rotulo: `Ventoinhas: ${inteiro(media)} RPM${m.ventoinhas.length > 1 ? `, ${m.ventoinhas.length} ventoinhas` : ''}` };
    },
  },
  dispositivos: { rot: 'Dispositivos', ic: 'usb', ler: m => m.dispositivos == null ? null : { nums: [m.dispositivos], fmt: n => String(Math.round(n)), barra: null, nivel: '', tag: 'conectados' } },
};

/* Os cartões que valem agora: o que está ligado nos Ajustes, na ordem da tela, sem o que o Mac não leu */
function cartoesAgora() {
  const m = V?.monitor; if (!m) return [];
  const ligados = m.itens || [];
  return ORDEM_MONITOR.filter(k => ligados.includes(k)).map(k => ({ k, def: CARTOES[k], d: CARTOES[k].ler(m) })).filter(c => c.d);
}

/* ---------- número que conta ---------- */
const MOV_CONTAR = 600;
const reduzMovimento = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const easeOutCubico = f => 1 - Math.pow(1 - f, 3);
/* `el._alvo` é o valor que a tela deve mostrar e `el._atual` o que mostra agora. Mudou no meio da contagem: recomeça de onde está */
function mostrarNumero(el, para, fmt, animar) {
  if (para == null) { cancelAnimationFrame(el._raf); el._alvo = el._atual = null; el.textContent = '-'; return }
  if (el._alvo === para) return;
  cancelAnimationFrame(el._raf);
  const de = el._atual;
  el._alvo = para;
  if (!animar || de == null || document.hidden || reduzMovimento()) { el._atual = para; el.innerHTML = fmt(para); return }
  const t0 = performance.now();
  const passo = agora => {
    const f = Math.min(1, (agora - t0) / MOV_CONTAR);
    el._atual = f >= 1 ? para : de + (para - de) * easeOutCubico(f);
    el.innerHTML = fmt(el._atual);
    if (f < 1) el._raf = requestAnimationFrame(passo);
  };
  el._raf = requestAnimationFrame(passo);
}

/* ---------- desenho ---------- */
const cartaoVazio = (k, def) => {
  const topo = `<span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG[def.ic]}</span><span class="mn-rot">${def.rot}</span><span class="mn-tag"></span></span>`;
  const corpo = def.rede
    ? `<span class="mn-duas"><span class="mn-linha"><span class="mn-seta">${SVG.baixa}</span><b class="mn-num mn-vel" data-s="0"></b></span><span class="mn-linha"><span class="mn-seta">${SVG.sobe}</span><b class="mn-num mn-vel mn-menor" data-s="1"></b></span></span>`
    : `<b class="mn-num" data-s="0"></b>`;
  return `<div class="mn-cartao" data-k="${k}" role="group">${topo}${corpo}<span class="mn-barra" hidden><i></i></span><span class="mn-nota"></span></div>`;
};
function pintarCartao(el, def, d, animar) {
  const rot = d.rotulo || `${def.rot}: ${d.nums[0] == null ? 'sem medição' : d.fmt(d.nums[0]).replace(/<[^>]+>/g, ' ').trim()}`;
  el.setAttribute('aria-label', rot + (d.tag ? `, ${d.tag}` : ''));
  el.classList.toggle('alto', d.nivel === 'alto'); el.classList.toggle('cheio', d.nivel === 'cheio');
  // a nota pequena fica no topo, ao lado do rótulo, quando o cartão tem barra, e no lugar da barra quando não tem
  const tag = $('.mn-tag', el), nota = $('.mn-nota', el), noTopo = d.barra != null;
  if (tag.textContent !== (noTopo ? d.tag || '' : '')) tag.textContent = noTopo ? d.tag || '' : '';
  if (nota.textContent !== (noTopo ? '' : d.tag || '')) nota.textContent = noTopo ? '' : d.tag || '';
  const barra = $('.mn-barra', el); barra.hidden = d.barra == null;
  if (d.barra != null) $('i', barra).style.transform = `scaleX(${Math.max(0, Math.min(1, d.barra / 100))})`;
  $$('.mn-num', el).forEach(n => mostrarNumero(n, d.nums[+n.dataset.s], d.fmt, animar));
}

const avisoVazio = (titulo, texto) => `<div class="vazio-bloco mn-vazio"><strong>${titulo}</strong><span>${texto}</span></div>`;
function pintarMonitor() {
  const corpo = $('#mn-corpo'), cartoes = cartoesAgora(), ligado = !!V?.monitor && (V.monitor.itens || []).length > 0;
  let chave, aviso = '';
  if (!V?.monitor || !ligado) {
    chave = 'vazio:' + (V?.blocos?.monitor ? 'sem-item' : 'desligado');
    aviso = avisoVazio(V?.blocos?.monitor ? 'Nenhum item ligado' : 'O monitor está desligado', 'Para ver o uso do Mac aqui, ligue o monitor em Este Mac, nos Ajustes do Deck no Mac.');
  } else if (!cartoes.length) {
    chave = 'vazio:sem-leitura';
    aviso = avisoVazio('O Mac não conseguiu ler os itens', 'Os itens ligados em Este Mac, nos Ajustes do Deck no Mac, não estão disponíveis neste Mac agora.');
  } else chave = 'grade:' + cartoes.map(c => c.k).join(',');
  // a grade só é refeita quando a lista de cartões muda. No resto do tempo os mesmos elementos são atualizados no lugar
  const refez = chave !== mn.chave;
  if (refez) {
    mn.chave = chave;
    corpo.innerHTML = aviso || `<div class="mn-grade" data-n="${cartoes.length}">${cartoes.map(c => cartaoVazio(c.k, c.def)).join('')}</div>`;
  }
  corpo.setAttribute('aria-busy', 'false');
  for (const c of cartoes) pintarCartao($(`.mn-cartao[data-k="${c.k}"]`, corpo), c.def, c.d, !refez);
}

function abrirMonitor() { mn.chave = ''; pintarMonitor(); abrirFolha('#f-monitor') }

/* aberta, a tela acompanha o estado (V.monitor chega com ele) a cada segundo */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-monitor') return;
  pintarMonitor();
}, 1000);
