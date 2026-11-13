/* Uso das IAs no iPhone: o toque no bloco de uso abre esta tela. Uma seção por conta (janelas de limite com ritmo e quando renova)
   e, onde o Mac sabe, o gasto de tokens do período (Dia, Semana ou Mês) com custo estimado, gráfico por dia e divisão por modelo.
   Cartões escuros no estilo do Monitor: ícone e rótulo cinza no topo, número grande, barra fina. Os mesmos elementos são
   atualizados no lugar e o número conta do valor antigo ao novo (tatile, movimento, regra 9), por isso a tela só é refeita quando a forma muda.
   Os dados vêm de GET /api/uso/detalhe, que responde na hora com o que já foi somado (o Mac varre os logs em segundo plano).
   Usa as peças de deck.js (V, folhaAberta, semAcesso, offline, nivel, tratarErro), monitor.js (mostrarNumero, decimal, inteiro),
   paineis.js (erroLista, msgErro, manterRolagem) e util.js (SVG, esc, icServico, haQuanto). */

const CHAVE_PERIODO_USO = 'deck-uso-periodo';
const PERIODOS_USO = [['dia', 'Dia'], ['semana', 'Semana'], ['mes', 'Mês']];
const periodoGuardado = () => { const p = lerGuardado(CHAVE_PERIODO_USO); return PERIODOS_USO.some(x => x[0] === p) ? p : 'semana' };
const us = { periodo: 'semana', dados: null, erro: '', semRota: false, seq: 0, lendo: false, resta: false, hora: false, chave: '' };

/* ---------- formatos ---------- */
const usoTexto = h => h.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
function usoTokens(n) {
  n = Math.round(n);
  if (n >= 1e9) return `${decimal(n / 1e9, n >= 1e10 ? 1 : 2)}<small>bi</small>`;
  if (n >= 1e6) return `${decimal(n / 1e6, n >= 1e7 ? 1 : 2)}<small>mi</small>`;
  if (n >= 1e4) return `${Math.round(n / 1e3)}<small>mil</small>`;
  return inteiro(n);
}
const usoDolar = n => `<small>US$</small> ${n >= 100 ? inteiro(n) : decimal(n, 2)}`;
const usoPct = n => `${Math.round(n)}<small>%</small>`;
const FORMATOS_USO = { pct: usoPct, tok: usoTokens, usd: usoDolar, int: inteiro };

/* Quanto falta para renovar: "3 d 14 h", "5 h 20 min" ou "40 min" */
function contagemRenova(iso, ref) {
  const d = new Date(iso); if (!iso || isNaN(d)) return '';
  const min = Math.round((d - ref) / 60000);
  if (min <= 0) return 'agora';
  if (min < 60) return `${min} min`;
  if (min < 1440) return `${Math.floor(min / 60)} h${min % 60 ? ` ${min % 60} min` : ''}`;
  return `${Math.floor(min / 1440)} d${Math.floor(min % 1440 / 60) ? ` ${Math.floor(min % 1440 / 60)} h` : ''}`;
}
function horaExata(iso) {
  const d = new Date(iso); if (!iso || isNaN(d)) return '';
  return d.toLocaleString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }).replace('.,', ',').replace('.', '');
}
const usoRef = () => V?.ref ?? Date.now();
function textoRitmo(r) {
  if (!r) return '';
  const base = r.situacao === 'rapido' ? 'Passa do limite antes de renovar' : r.situacao === 'sobra' ? 'Vai sobrar muito' : r.projecao != null ? `Chega a ${r.projecao}% ao renovar` : '';
  return `${base ? base + '. ' : ''}Esperado agora: ${r.esperado}%`;
}

/* ---------- forma (o que só muda quando a lista de contas, o período ou os modelos mudam) ---------- */
const cartaoJanela = (k, rot) => `<div class="mn-cartao us-cartao us-janela" data-c="${k}" role="group" aria-label="${esc(rot)}">
  <button type="button" class="us-valor" data-us-resta><span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG.raio}</span><span class="mn-rot">${esc(rot)}</span><span class="mn-tag" data-t="${k}.modo"></span></span><b class="mn-num us-num" data-n="${k}" data-f="pct"></b></button>
  <span class="mn-barra us-barra"><i data-b="${k}"></i><u data-m="${k}"></u></span>
  <button type="button" class="us-nota us-renova" data-us-hora data-t="${k}.renova"></button>
  <span class="us-nota" data-t="${k}.ritmo"></span><span class="us-nota" data-t="${k}.med"></span></div>`;

const cartaoNumero = (k, icone, rot, f) => `<div class="mn-cartao us-cartao" data-c="${k}" role="group"><span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG[icone]}</span><span class="mn-rot">${rot}</span></span><b class="mn-num us-num" data-n="${k}" data-f="${f}"></b><span class="us-nota" data-t="${k}.nota"></span></div>`;

function rotulosDoGrafico(periodo, ate) {
  const [a, m, d] = ate.split('-').map(Number), fim = new Date(a, m - 1, d);
  if (periodo === 'dia') return ['0h', '6h', '12h', '18h', '23h'].map(t => `<span>${t}</span>`).join('');
  const dia = n => new Date(fim.getFullYear(), fim.getMonth(), fim.getDate() - n);
  if (periodo === 'semana') return Array.from({ length: 7 }, (_, i) => dia(6 - i).toLocaleDateString('pt-BR', { weekday: 'narrow' }).toUpperCase()).map(t => `<span>${t}</span>`).join('');
  const f = x => x.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  return [29, 15, 0].map(n => `<span>${f(dia(n))}</span>`).join('');
}

function blocoGasto(k, g, periodo, ate) {
  const barras = '<i></i>'.repeat(g.serie.length || { dia: 24, semana: 7, mes: 30 }[periodo]);
  const modelos = g.modelos.map((m, i) => `<li class="us-modelo" data-c="${k}.m${i}"><span class="us-m-nome">${esc(m.nome)}</span><b class="us-m-parte" data-t="${k}.m${i}.parte"></b><span class="us-m-tok" data-t="${k}.m${i}.tok"></span><span class="us-m-custo" data-t="${k}.m${i}.custo"></span><span class="mn-barra us-m-barra"><i data-b="${k}.m${i}"></i></span></li>`).join('');
  return `${cartaoNumero(`${k}.tok`, 'cpu', 'Tokens', 'tok')}
  ${cartaoNumero(`${k}.usd`, 'raio', 'Custo estimado', 'usd')}
  ${cartaoNumero(`${k}.resp`, 'terminal', 'Respostas', 'int')}
  <div class="mn-cartao us-cartao us-larga" data-c="${k}.tipos" role="group" aria-label="Tokens por tipo"><span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG.memoria}</span><span class="mn-rot">Por tipo de token</span></span>
    <dl class="us-tipos">${[['ent', 'Entrada'], ['sai', 'Saída'], ['cl', 'Cache lido'], ['ce', 'Cache escrito']].map(([c, r]) => `<div><dt>${r}</dt><dd class="us-num" data-n="${k}.${c}" data-f="tok"></dd></div>`).join('')}</dl></div>
  <div class="mn-cartao us-cartao us-larga" data-c="${k}.graf" role="img"><span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG.disco}</span><span class="mn-rot">Tokens por ${periodo === 'dia' ? 'hora' : 'dia'}</span><span class="mn-tag" data-t="${k}.pico"></span></span>
    <span class="us-grafico" data-n-barras="${g.serie.length}">${barras}</span><span class="us-eixo us-eixo-${periodo}" aria-hidden="true">${rotulosDoGrafico(periodo, ate)}</span></div>
  <div class="mn-cartao us-cartao us-larga" data-c="${k}.modelos" role="group" aria-label="Divisão por modelo"><span class="mn-topo"><span class="mn-ic" aria-hidden="true">${SVG.rede}</span><span class="mn-rot">Por modelo</span></span>
    <ul class="us-modelos">${modelos || '<li class="us-nota">Nenhum uso neste período</li>'}</ul></div>`;
}

const cabecalhoConta = (id, c, sub) => `<h3 id="${id}">${icServico(c)}<span>${esc(c)}${sub ? ` <small>${esc(sub)}</small>` : ''}</span></h3>`;

function estruturaUso(d) {
  const partes = [`${d.periodo}|${d.ate}`];
  let html = '';
  d.contas.forEach((c, i) => {
    const gasto = c.gasto ? blocoGasto(`${i}.g`, c.gasto, d.periodo, d.ate) : '';
    const janelas = c.janelas.map((j, k) => cartaoJanela(`${i}.j${k}`, j.rotulo)).join('') || `<div class="mn-cartao us-cartao us-sem" data-c="${i}.sem" role="group"><span class="us-nota">Sem medição desta conta. O Mac ainda não leu o uso dela.</span></div>`;
    html += `<section class="us-conta${c.gasto ? '' : ' us-simples'}" aria-labelledby="us-c${i}">${cabecalhoConta(`us-c${i}`, c.nome, c.conta)}<div class="us-grade">${janelas}${gasto}</div></section>`;
    partes.push(`${c.id}:${c.janelas.map(j => j.rotulo).join(',')}:${c.gasto ? c.gasto.modelos.map(m => m.nome).join(',') + '/' + c.gasto.serie.length : '-'}`);
  });
  if (d.claudeMac) {
    html += `<section class="us-conta" aria-labelledby="us-cmac">${cabecalhoConta('us-cmac', 'Claude', 'neste Mac')}<p class="us-aviso">O Claude não diz de qual conta cada gasto saiu, então somei tudo o que foi usado neste Mac.</p><div class="us-grade">${blocoGasto('mac.g', d.claudeMac, d.periodo, d.ate)}</div></section>`;
    partes.push('mac:' + d.claudeMac.modelos.map(m => m.nome).join(',') + '/' + d.claudeMac.serie.length);
  }
  return { html: `<div class="us-secoes">${html}</div><p class="us-rodape" id="us-rodape" aria-live="polite"></p>`, chave: partes.join('#') };
}

/* ---------- valores (a cada leitura, nos mesmos elementos) ---------- */
function preencherUso(corpo, d, animar) {
  const el = (a, k) => corpo.querySelector(`[data-${a}="${k}"]`);
  const num = (k, v) => { const e = el('n', k); if (e) mostrarNumero(e, v, FORMATOS_USO[e.dataset.f], animar) };
  const txt = (k, s) => { const e = el('t', k); if (e && e.textContent !== s) e.textContent = s };
  const ref = usoRef();

  const janela = (k, j) => {
    const p = us.resta ? Math.max(0, 100 - j.percentual) : j.percentual, c = el('c', k);
    c.classList.toggle('alto', nivel(j.percentual) === 'alto'); c.classList.toggle('cheio', nivel(j.percentual) === 'cheio');
    c.setAttribute('aria-label', `${j.rotulo}: ${p}% ${us.resta ? 'restam' : 'usados'}`);
    num(k, p); txt(`${k}.modo`, us.resta ? 'resta' : 'usado');
    el('b', k).style.transform = `scaleX(${Math.max(0, Math.min(1, j.percentual / 100))})`;
    const m = el('m', k); m.hidden = !j.ritmo; if (j.ritmo) m.style.left = `${Math.max(0, Math.min(100, j.ritmo.esperado))}%`;
    const r = j.renova ? (us.hora ? `Renova ${horaExata(j.renova)}` : `Renova em ${contagemRenova(j.renova, ref)}`) : '';
    txt(`${k}.renova`, r); el('t', `${k}.renova`).hidden = !r;
    txt(`${k}.ritmo`, textoRitmo(j.ritmo));
    txt(`${k}.med`, j.medidoEm ? `Medido há ${haQuanto(j.medidoEm, ref).texto}` : '');
  };

  const gasto = (k, g) => {
    num(`${k}.tok`, g.total); txt(`${k}.tok.nota`, g.total ? `${usoTexto(usoTokens(g.entrada + g.saida))} sem contar o cache` : 'Nada neste período');
    num(`${k}.usd`, g.custo ?? null);
    txt(`${k}.usd.nota`, g.custo == null ? (g.total ? 'Modelo sem preço na tabela' : '') : g.custoParcial ? 'Estimado, falta preço de algum modelo' : 'Estimado a preço de API');
    num(`${k}.resp`, g.turnos); txt(`${k}.resp.nota`, g.sessoes ? `${g.sessoes} ${g.sessoes === 1 ? 'sessão' : 'sessões'}` : '');
    num(`${k}.ent`, g.entrada); num(`${k}.sai`, g.saida); num(`${k}.cl`, g.cacheLeitura); num(`${k}.ce`, g.cacheEscrita);
    const max = Math.max(1, ...g.serie), barras = $$('.us-grafico i', el('c', `${k}.graf`));
    const agora = us.dados.periodo === 'dia' ? new Date(ref).getHours() : g.serie.length - 1;
    barras.forEach((b, i) => { b.style.transform = `scaleY(${g.serie[i] ? Math.max(.04, g.serie[i] / max) : 0})`; b.classList.toggle('agora', i === agora); b.classList.toggle('vazia', !g.serie[i]) });
    txt(`${k}.pico`, g.total ? `Pico ${usoTexto(usoTokens(max))}` : '');
    el('c', `${k}.graf`).setAttribute('aria-label', g.total ? `Tokens por ${d.periodo === 'dia' ? 'hora' : 'dia'}. O maior valor foi ${usoTexto(usoTokens(max))}` : 'Nenhum uso neste período');
    g.modelos.forEach((m, i) => {
      txt(`${k}.m${i}.parte`, `${m.parte}%`); txt(`${k}.m${i}.tok`, usoTexto(usoTokens(m.tokens)));
      txt(`${k}.m${i}.custo`, m.custo == null ? '-' : `US$ ${decimal(m.custo, 2)}`);
      el('b', `${k}.m${i}`).style.transform = `scaleX(${Math.max(0, Math.min(1, m.parte / 100))})`;
      el('c', `${k}.m${i}`).setAttribute('aria-label', `${m.nome}: ${m.parte}% dos tokens`);
    });
  };

  d.contas.forEach((c, i) => {
    c.janelas.forEach((j, k) => janela(`${i}.j${k}`, j));
    if (c.gasto) gasto(`${i}.g`, c.gasto);
  });
  if (d.claudeMac) gasto('mac.g', d.claudeMac);
  corpo.classList.toggle('us-recalculando', !!d.calculando);
  const rod = $('#us-rodape', corpo);
  rod.textContent = d.calculando ? 'Calculando o gasto de tokens. Na primeira vez demora um pouco, e depois fica rápido.'
    : d.atualizadoEm ? `Gasto calculado há ${haQuanto(d.atualizadoEm, ref).texto}. O custo é uma estimativa a preço de API, quem usa assinatura não paga isso.` : '';
}

/* ---------- desenho ---------- */
const esqueletoUso = () => '<div class="esq-lista us-esq" aria-hidden="true"><div class="mn-cartao us-cartao esq"><i class="barra" style="width:40%"></i><i class="barra" style="width:60%"></i></div><div class="mn-cartao us-cartao esq"><i class="barra" style="width:40%"></i><i class="barra" style="width:60%"></i></div><div class="mn-cartao us-cartao esq"><i class="barra" style="width:40%"></i><i class="barra" style="width:60%"></i></div></div>';

function pintarUso(animar) {
  const corpo = $('#us-corpo');
  corpo.setAttribute('aria-busy', String(!us.dados && !us.erro));
  $$('#us-filtro button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.p === us.periodo)));
  if (!us.dados) {
    const chave = us.erro ? 'erro:' + us.erro : 'carregando';
    if (chave === us.chave) return;
    us.chave = chave;
    corpo.innerHTML = !us.erro ? esqueletoUso()
      : us.semRota ? '<div class="vazio-bloco mn-vazio"><strong>Este Mac ainda não tem o detalhe do uso</strong><span>Atualize o Deck no Mac para ver o gasto de tokens aqui.</span></div>' : erroLista(us.erro);
    return;
  }
  const d = us.dados;
  if (!d.contas.length && !d.claudeMac) {
    if (us.chave !== 'vazio') { us.chave = 'vazio'; corpo.innerHTML = '<div class="vazio-bloco mn-vazio"><strong>Nenhuma conta ligada</strong><span>Para ver o uso das IAs aqui, ligue "No iPhone" nas contas, em Uso das IAs, nos Ajustes do Deck no Mac.</span></div>' }
    return;
  }
  const est = estruturaUso(d), refez = est.chave !== us.chave;
  if (refez) { us.chave = est.chave; manterRolagem(corpo, est.html) }
  corpo.classList.remove('us-carregando');
  preencherUso(corpo, d, !!animar && !refez);
}

function abrirUso() {
  us.periodo = periodoGuardado(); us.dados = null; us.erro = ''; us.semRota = false; us.chave = '';
  pintarUso(); $('#us-corpo').scrollTop = 0; abrirFolha('#f-uso'); lerUso();
}

async function lerUso() {
  const n = ++us.seq, periodo = us.periodo; us.lendo = true;
  try {
    const d = await canal.usoDetalhe(periodo);
    if (n !== us.seq) return;
    us.erro = ''; us.erroAvisado = false; us.semRota = false; us.dados = d; pintarUso(true);
  } catch (e) {
    if (n !== us.seq) return;
    if (e.status === 401) return tratarErro(e);
    us.semRota = e.status === 404; us.erro = us.semRota ? 'sem rota' : msgErro(e);
    if (!us.dados) pintarUso(); else if (!us.erroAvisado) { us.erroAvisado = true; avisar(us.erro, { erro: true }) } // o aviso dura 4 s uma vez, não a cada leitura
  } finally { if (n === us.seq) us.lendo = false }
}

/* ---------- toques ---------- */
$('#us-filtro').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b || b.dataset.p === us.periodo) return;
  us.periodo = b.dataset.p; guardar(CHAVE_PERIODO_USO, us.periodo);
  $$('#us-filtro button').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
  $('#us-corpo').classList.add('us-carregando'); // o gasto do período antigo fica apagado até o novo chegar
  lerUso();
});
$('#us-corpo').addEventListener('click', e => {
  if (e.target.closest('[data-tentar]')) { us.erro = ''; us.erroAvisado = false; us.chave = ''; pintarUso(); return lerUso() }
  if (e.target.closest('[data-us-resta]')) { us.resta = !us.resta; if (us.dados) preencherUso($('#us-corpo'), us.dados, true) }
  else if (e.target.closest('[data-us-hora]')) { us.hora = !us.hora; if (us.dados) preencherUso($('#us-corpo'), us.dados, false) }
});

/* aberta, a tela se atualiza a cada 4 s (a cada 2 s enquanto o Mac ainda calcula pela primeira vez) */
let usoTic = 0;
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-uso') { usoTic = 0; return }
  usoTic++;
  if (us.dados?.calculando || usoTic % 4 === 0) lerUso();
  else if (us.dados) preencherUso($('#us-corpo'), us.dados, false); // a contagem para renovar e o "medido há" andam sem ir ao Mac
}, 1000);
