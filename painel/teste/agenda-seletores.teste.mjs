// Frente agenda-seletores (17/11/2026): círculos do dia alinhados, seletores próprios de Dia, Início e Fim, e lembrete de outra cor que o feriado.
// Roleta (19/11/2026): Início e Fim viraram a roleta de horário do iPhone (horas e minutos de 5 em 5, scroll-snap), testada com toque de verdade (hasTouch).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const raiz = path.resolve(aqui, '../..'), marca = `${path.sep}.claude${path.sep}worktrees${path.sep}`;
const principal = raiz.includes(marca) ? raiz.split(marca)[0] : raiz;
const fotos = process.env.DECK_FOTOS || path.join(principal, '.teste');
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="calendario"]'));
const VISTAS = [['deitado', 932, 430], ['em-pe', 430, 932], ['janela', 1440, 900]];

// decodifica um PNG 8 bits sem entrelaçamento (o que o Chrome grava) para achar onde está a tinta do número
function decodificar(buf) {
  let o = 8, w = 0, a = 0, canais = 4; const dados = [];
  while (o < buf.length) {
    const n = buf.readUInt32BE(o), tipo = buf.toString('latin1', o + 4, o + 8), corpo = buf.subarray(o + 8, o + 8 + n);
    if (tipo === 'IHDR') { w = corpo.readUInt32BE(0); a = corpo.readUInt32BE(4); canais = corpo[9] === 6 ? 4 : corpo[9] === 2 ? 3 : 1 }
    if (tipo === 'IDAT') dados.push(corpo);
    o += 12 + n;
  }
  const cru = zlib.inflateSync(Buffer.concat(dados)), linha = w * canais, px = Buffer.alloc(a * linha);
  for (let y = 0; y < a; y++) {
    const f = cru[y * (linha + 1)], de = y * (linha + 1) + 1;
    for (let x = 0; x < linha; x++) {
      const bruto = cru[de + x], esq = x >= canais ? px[y * linha + x - canais] : 0, cima = y ? px[(y - 1) * linha + x] : 0, cimaEsq = y && x >= canais ? px[(y - 1) * linha + x - canais] : 0;
      let v = bruto;
      if (f === 1) v += esq; else if (f === 2) v += cima; else if (f === 3) v += (esq + cima) >> 1;
      else if (f === 4) { const pp = esq + cima - cimaEsq, pa = Math.abs(pp - esq), pb = Math.abs(pp - cima), pc = Math.abs(pp - cimaEsq); v += pa <= pb && pa <= pc ? esq : pb <= pc ? cima : cimaEsq }
      px[y * linha + x] = v & 255;
    }
  }
  return { w, a, canais, px };
}
// centro da tinta clara (o número) dentro do círculo, em px do círculo, contra o centro do círculo
function desvioDaTinta(png, escala) {
  const { w, a, canais, px } = decodificar(png); let x0 = w, x1 = -1, y0 = a, y1 = -1;
  for (let y = 0; y < a; y++) for (let x = 0; x < w; x++) { const i = (y * w + x) * canais; if (Math.min(px[i], px[i + 1], px[i + 2]) > 150) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y } }
  return x1 < 0 ? null : { dx: ((x0 + x1 + 1) / 2 - w / 2) / escala, dy: ((y0 + y1 + 1) / 2 - a / 2) / escala };
}
const escalaDe = p => p.evaluate(() => { const t = document.querySelector('#tela'); return t.getBoundingClientRect().width / t.offsetWidth });
const tamanho = (p, sel) => p.evaluate(s => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, r = document.querySelector(s).getBoundingClientRect(); return { l: Math.round(r.width / k * 10) / 10, a: Math.round(r.height / k * 10) / 10 } }, sel);
const foto = (p, nome) => { fs.mkdirSync(fotos, { recursive: true }); return p.screenshot({ path: path.join(fotos, `agenda-seletores-${nome}.png`) }) };
const fotoRoleta = (p, nome) => { const d = path.join(fotos, 'agenda-roleta'); fs.mkdirSync(d, { recursive: true }); return p.screenshot({ path: path.join(d, `${nome}.png`) }) };
// roleta: o que está na faixa do meio (as duas colunas) e como mexer nela como o dedo e o teclado mexem
const naFaixa = p => p.evaluate(() => [...document.querySelectorAll('#sel-meio .rol-col [aria-selected="true"]')].map(o => o.textContent).join(':'));
const assentada = p => p.evaluate(() => [...document.querySelectorAll('#sel-meio .rol-col')].every(c => c.scrollTop % c.querySelector('[role=option]').offsetHeight < .6));
// arrasta a coluna n itens (positivo = para cima, valor maior) com um dedo de verdade (CDP, toque sintético), sem fling
async function arrastar(p, ctx, chave, itens) {
  const cdp = await ctx.newCDPSession(p), c = await p.locator(`#sel-meio [data-rol="${chave}"]`).boundingBox(), k = await escalaDe(p);
  await cdp.send('Input.synthesizeScrollGesture', { x: c.x + c.width / 2, y: c.y + c.height / 2, yDistance: -itens * 44 * k, speed: 500, gestureSourceType: 'touch', preventFling: true });
  await cdp.detach();
}
async function tocarItem(p, chave, valor) { const b = await p.locator(`#sel-meio [data-rol="${chave}"] [data-v="${valor}"]`).boundingBox(); await p.touchscreen.tap(b.x + b.width / 2, b.y + b.height / 2) }
// teclado: Home e depois n setas para baixo levam a coluna ao item n (sem depender do dedo)
async function irPara(p, h, chave, idx) { await p.focus(`#sel-meio [data-rol="${chave}"]`); await p.keyboard.press('Home'); for (let i = 0; i < idx; i++) await p.keyboard.press('ArrowDown'); await h.dormir(150) }
async function abrirRoleta(h, p, qual) { await p.click(`[data-sel="${qual}"]`); await h.dormir(500) }
async function definirInicio(h, p, hh, mm) { await abrirRoleta(h, p, 'inicio'); await irPara(p, h, 'h', hh); await irPara(p, h, 'm', mm / 5); await p.click('[data-sel-ok]'); await h.dormir(150) }
const abrirAgenda = async (h, p) => { await pronta(h, p); await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0 || !!document.querySelector('#ca-lista .vazio-bloco')); await h.dormir(500) };
const abrirForm = async (h, p) => { await p.click('#ca-puxa'); await h.espera(p, () => !document.querySelector('#ca-form').hidden); await h.dormir(500) };
const valor = (p, id) => p.evaluate(i => document.querySelector('#' + i).value, id);
const hoje = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` };

export default async function (h) {
  /* ---------- 1. círculos do dia: mesmo tamanho e o número no centro ---------- */
  for (const [nome, w, al] of VISTAS) {
    const ctx = await h.novoContexto({ viewport: { width: w, height: al }, deviceScaleFactor: 3 });
    const p = await h.pagina({ ctx }); await abrirAgenda(h, p);
    const k = await escalaDe(p);
    const outro = p.locator('#ca-grade .sb-dia:not(.hoje)').nth(6); await outro.click(); await h.dormir(300);
    const caixa = await p.evaluate(() => ['hoje', 'sel'].map(c => { const r = document.querySelector('#ca-grade .sb-dia.' + c)?.getBoundingClientRect(); return r && { l: r.width, a: r.height } }));
    h.ok(caixa[0] && caixa[1] && Math.abs(caixa[0].l - caixa[1].l) < .5 && Math.abs(caixa[0].a - caixa[1].a) < .5 && Math.abs(caixa[0].l - caixa[0].a) < .5, `${nome}: o círculo de hoje e o do dia escolhido têm o mesmo diâmetro (${JSON.stringify(caixa)})`);
    for (const c of ['hoje', 'sel']) {
      const d = desvioDaTinta(await p.locator('#ca-grade .sb-dia.' + c).screenshot(), 3 * k);
      h.ok(d && Math.abs(d.dx) <= 1 && Math.abs(d.dy) <= 1, `${nome}: o número do círculo ${c === 'hoje' ? 'de hoje' : 'do dia escolhido'} fica no centro (desvio ${d ? d.dx.toFixed(2) + ', ' + d.dy.toFixed(2) : 'sem número'} px)`);
    }
    if (nome !== 'janela') { await p.locator('#ca-grade').screenshot({ path: path.join(fotos, `agenda-seletores-circulos-${nome}.png`) }) }
    await ctx.close();
  }

  /* ---------- 2. seletores próprios ---------- */
  for (const [nome, w, al] of VISTAS) {
    const ctx = await h.novoContexto({ viewport: { width: w, height: al }, hasTouch: true });
    const p = await h.pagina({ ctx }); await abrirAgenda(h, p);
    await p.evaluate(() => { window.__nativo = 0; HTMLInputElement.prototype.showPicker = function () { window.__nativo++ } });
    await abrirForm(h, p);
    h.ok(await p.evaluate(() => ['nc-dia', 'nc-inicio', 'nc-fim'].every(i => { const e = document.getElementById(i); return getComputedStyle(e).pointerEvents === 'none' && e.tabIndex === -1 }) && !document.querySelector('label[for="nc-dia"], label[for="nc-inicio"], label[for="nc-fim"]')), `${nome}: os campos nativos de data e hora ficam só como guarda do valor (sem toque, sem foco, sem rótulo que os acorde)`);
    const diaAntes = await valor(p, 'nc-dia');

    // Dia
    await p.click('[data-sel="dia"]'); await h.dormir(500);
    h.ok(await p.evaluate(() => !document.querySelector('#ca-sel').hidden && document.querySelector('#sel-titulo').textContent === 'Dia') && await p.evaluate(() => window.__nativo) === 0, `${nome}: tocar em Dia abre o seletor do Deck, nunca o do navegador`);
    await foto(p, `${nome}-dia`);
    const alvos = await p.evaluate(() => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth; return [...document.querySelectorAll('#ca-sel button')].filter(b => !b.disabled).map(b => { const r = b.getBoundingClientRect(); return { n: b.textContent.trim() || b.getAttribute('aria-label'), l: r.width / k, a: r.height / k } }).filter(b => b.l < 43.5 || b.a < 43.5) });
    h.ok(alvos.length === 0, `${nome}: todo botão do seletor de dia tem 44 pt (${JSON.stringify(alvos)})`);
    const dentro = await p.evaluate(() => { const s = document.querySelector('#ca-sel').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); const pior = [...document.querySelectorAll('#ca-sel button')].map(b => b.getBoundingClientRect()).filter(r => r.bottom > t.bottom + 1 || r.right > t.right + 1 || r.left < t.left - 1 || r.top < t.top - 1).length; return pior });
    h.ok(dentro === 0, `${nome}: o seletor de dia cabe na tela inteiro (${dentro} botões fora)`);
    await p.click('[data-sel-atalho]:has-text("Amanhã")'); await h.dormir(150);
    const amanha = await valor(p, 'nc-dia'); const dA = new Date(); dA.setDate(dA.getDate() + 1);
    h.ok(amanha === `${dA.getFullYear()}-${String(dA.getMonth() + 1).padStart(2, '0')}-${String(dA.getDate()).padStart(2, '0')}` && await p.evaluate(() => document.querySelector('#ca-sel').hidden), `${nome}: o atalho Amanhã escolhe o dia e fecha (${amanha})`);
    await p.click('[data-sel="dia"]'); await h.dormir(300); await p.click('[data-sel-atalho]:has-text("Hoje")'); await h.dormir(150);
    h.ok(await valor(p, 'nc-dia') === hoje(), `${nome}: o atalho Hoje escolhe o dia de hoje`);
    await p.click('[data-sel="dia"]'); await h.dormir(300);
    const mes0 = await p.textContent('#sel-meio .mes-topo h2'); await p.click('[data-sel-mes="1"]'); await h.dormir(100);
    const mes1 = await p.textContent('#sel-meio .mes-topo h2');
    h.ok(mes0 !== mes1, `${nome}: a seta troca o mês (${mes0} para ${mes1})`);
    await p.locator('#sel-meio [data-sel-data$="-15"]').click(); await h.dormir(150);
    const d15 = await valor(p, 'nc-dia');
    h.ok(/-15$/.test(d15) && d15 > hoje() && await p.evaluate(() => document.querySelector('#ca-sel').hidden) && /^15 /.test(await p.textContent('#nc-dia-val')), `${nome}: tocar num dia do mês seguinte escolhe e fecha, e o campo mostra o valor (${d15}, "${await p.textContent('#nc-dia-val')}")`);
    h.ok(d15 !== diaAntes, `${nome}: o dia mudou de verdade`);

    // Início: só a roleta
    await abrirRoleta(h, p, 'inicio');
    h.ok(await p.evaluate(() => document.querySelector('#sel-titulo').textContent === 'Início') && await p.evaluate(() => window.__nativo) === 0, `${nome}: tocar em Início abre o seletor do Deck`);
    const ini0 = await valor(p, 'nc-inicio');
    h.ok(await naFaixa(p) === ini0 && await assentada(p), `${nome}: a roleta abre já no valor atual (${ini0}) e assentada`);
    const est = await p.evaluate(() => ({ chips: document.querySelectorAll('#sel-meio [data-sel-hora], #sel-extra button').length, horas: document.querySelectorAll('#sel-meio [data-rol="h"] [role=option]').length, mins: [...document.querySelectorAll('#sel-meio [data-rol="m"] [role=option]')].map(o => o.textContent).join(), listas: document.querySelectorAll('#sel-meio [role=listbox]').length, ativo: !!document.querySelector('#sel-meio [data-rol="h"]').getAttribute('aria-activedescendant'), grande: document.querySelector('#sel-valor').textContent }));
    h.ok(est.chips === 0 && est.horas === 24 && est.mins === '00,05,10,15,20,25,30,35,40,45,50,55' && est.listas === 2 && est.ativo && est.grande === ini0, `${nome}: Início tem só a roleta, 24 horas e minutos de 5 em 5, com role listbox e a hora grande (${JSON.stringify(est)})`);
    const itens = await p.evaluate(() => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth; return [...document.querySelectorAll('#sel-meio [role=option], #ca-sel button')].map(b => { const r = b.getBoundingClientRect(); return b.matches('[role=option]') ? Math.min(b.offsetWidth, b.offsetHeight) : Math.min(r.width, r.height) / k }).filter(v => v < 43.5).length });
    h.ok(itens === 0, `${nome}: item da roleta e Pronto têm 44 pt`);
    const geo = await p.evaluate(() => { const r = s => document.querySelector(s).getBoundingClientRect(), t = r('#tela'), ro = r('#sel-meio'), v = r('#sel-valor'), f = document.querySelector('#ca-sel'); return { dentro: ro.top >= t.top - 1 && ro.bottom <= t.bottom + 1 && ro.left >= t.left - 1 && ro.right <= t.right + 1, esquerda: v.right <= ro.left + 1, abaixo: v.bottom <= ro.top + 1, semRolar: f.scrollHeight <= f.clientHeight + 1 } });
    h.ok(geo.dentro && geo.semRolar && (nome === 'deitado' ? geo.esquerda : nome === 'em-pe' ? geo.abaixo : true), `${nome}: a folha não rola, a roleta cabe na tela e ${nome === 'deitado' ? 'a hora grande fica à esquerda' : nome === 'em-pe' ? 'fica uma coluna só (hora em cima, roleta embaixo)' : 'o layout largo se mantém'} (${JSON.stringify(geo)})`);
    await fotoRoleta(p, `${nome}-inicio`);
    // toque num item vizinho seleciona e o fim vai junto, mantendo 1 h
    await p.click('[data-sel-ok]'); await h.dormir(150);
    await definirInicio(h, p, 14, 30); await abrirRoleta(h, p, 'inicio');
    await tocarItem(p, 'h', 15); await h.dormir(500);
    h.ok(await valor(p, 'nc-inicio') === '15:30' && await valor(p, 'nc-fim') === '16:30' && await naFaixa(p) === '15:30' && await assentada(p), `${nome}: tocar na hora vizinha (15) seleciona, a roleta assenta e o fim vai junto (${await valor(p, 'nc-inicio')} até ${await valor(p, 'nc-fim')})`);
    await tocarItem(p, 'm', 35); await h.dormir(500);
    h.ok(await valor(p, 'nc-inicio') === '15:35' && /15:35/.test(await p.textContent('#nc-inicio-val')) && await p.textContent('#sel-valor') === '15:35', `${nome}: tocar no minuto vizinho (35) seleciona e o campo e a hora grande acompanham`);
    // rolar com o dedo
    await arrastar(p, ctx, 'h', 3); await h.dormir(700);
    const aposH = await valor(p, 'nc-inicio');
    h.ok(aposH === '18:35' && await naFaixa(p) === '18:35' && await assentada(p), `${nome}: arrastar a coluna das horas 3 itens com o dedo leva a 18:35 e assenta (${aposH})`);
    await arrastar(p, ctx, 'm', -2); await h.dormir(700);
    h.ok(await valor(p, 'nc-inicio') === '18:25' && await naFaixa(p) === '18:25' && await assentada(p), `${nome}: arrastar os minutos 2 itens para baixo leva a 18:25 (${await valor(p, 'nc-inicio')})`);
    // teclado
    await p.focus('#sel-meio [data-rol="h"]'); await p.keyboard.press('ArrowDown'); await h.dormir(500);
    h.ok(await valor(p, 'nc-inicio') === '19:25', `${nome}: seta para baixo na hora avança 1 h (${await valor(p, 'nc-inicio')})`);
    await p.keyboard.press('ArrowRight'); await p.keyboard.press('ArrowUp'); await h.dormir(500);
    h.ok(await valor(p, 'nc-inicio') === '19:20' && await p.evaluate(() => document.activeElement.dataset.rol) === 'm', `${nome}: seta para a direita passa para os minutos e seta para cima volta 5 min (${await valor(p, 'nc-inicio')})`);
    await p.click('[data-sel-ok]'); await h.dormir(150);
    h.ok(await p.evaluate(() => document.querySelector('#ca-sel').hidden), `${nome}: Pronto fecha o seletor`);

    // Fim: durações acima da roleta
    await definirInicio(h, p, 14, 35);
    await abrirRoleta(h, p, 'fim');
    h.ok(await p.evaluate(() => document.querySelector('#sel-titulo').textContent === 'Fim') && await p.evaluate(() => window.__nativo) === 0, `${nome}: tocar em Fim abre o seletor do Deck`);
    const durs = await p.evaluate(() => [...document.querySelectorAll('#sel-extra [data-sel-dur]')].map(b => b.textContent));
    h.ok(durs.join('|') === '15 min|30 min|1 h|2 h', `${nome}: o Fim tem a fileira 15 min, 30 min, 1 h e 2 h (${durs.join(' | ')})`);
    h.ok(await p.evaluate(() => { const c = document.querySelector('#sel-extra').getBoundingClientRect(), r = document.querySelector('#sel-meio').getBoundingClientRect(); return document.querySelector('#sel-meio [data-sel-dur]') === null && (c.bottom <= r.top + 1 || c.right <= r.left + 1) }), `${nome}: as durações ficam acima (ou ao lado, deitado) da roleta`);
    h.ok(await naFaixa(p) === '15:35' && await p.evaluate(() => document.querySelector('[data-sel-dur="60"]').getAttribute('aria-pressed')) === 'true', `${nome}: o Fim abre no valor atual (15:35) com a duração de 1 h marcada`);
    await fotoRoleta(p, `${nome}-fim`);
    await p.touchscreen.tap(...await p.locator('[data-sel-dur="120"]').boundingBox().then(b => [b.x + b.width / 2, b.y + b.height / 2])); await h.dormir(600);
    h.ok(await valor(p, 'nc-fim') === '16:35' && await naFaixa(p) === '16:35' && await assentada(p), `${nome}: tocar em 2 h move a roleta para 16:35 (${await valor(p, 'nc-fim')})`);
    await arrastar(p, ctx, 'm', 2); await h.dormir(700);
    h.ok(await valor(p, 'nc-fim') === '16:45' && await p.evaluate(() => ['60', '120'].map(n => document.querySelector(`[data-sel-dur="${n}"]`).getAttribute('aria-pressed')).join()) === 'false,false', `${nome}: a roleta ajusta o Fim com o dedo (16:45) e a duração marcada sai (${await valor(p, 'nc-fim')})`);
    await p.click('[data-sel-dur="15"]'); await h.dormir(500);
    await p.focus('#sel-meio [data-rol="m"]'); for (let i = 0; i < 3; i++) await p.keyboard.press('ArrowUp'); await h.dormir(700);
    h.ok(await valor(p, 'nc-fim') === '14:40' && await naFaixa(p) === '14:40' && await assentada(p), `${nome}: o fim nunca fica antes do início, a roleta volta para ${await naFaixa(p)} (campo ${await valor(p, 'nc-fim')})`);
    await p.click('[data-sel-ok]'); await h.dormir(150);

    // início tarde: duração que passa da meia-noite fica desligada
    await definirInicio(h, p, 23, 0);
    await abrirRoleta(h, p, 'fim');
    h.ok(await p.evaluate(() => document.querySelector('[data-sel-dur="120"]').disabled && !document.querySelector('[data-sel-dur="30"]').disabled), `${nome}: começando às 23:00, 2 h (passa da meia-noite) fica desligado e 30 min não`);
    await p.keyboard.press('Escape'); await h.dormir(150);
    h.ok(await p.evaluate(() => document.querySelector('#ca-sel').hidden), `${nome}: Esc fecha o seletor`);

    // dia todo desliga Início e Fim
    await p.check('#nc-todo'); await h.dormir(100);
    h.ok(await p.evaluate(() => document.querySelector('[data-sel="inicio"]').disabled && document.querySelector('[data-sel="fim"]').disabled && !document.querySelector('[data-sel="dia"]').disabled), `${nome}: Dia todo desliga Início e Fim e deixa o Dia`);
    await p.uncheck('#nc-todo');
    await foto(p, `${nome}-formulario`);

    // salvar segue como era
    await p.fill('#nc-titulo', 'Ensaio dos seletores');
    await p.click('[data-sel="dia"]'); await h.dormir(300); await p.click('[data-sel-atalho]:has-text("Amanhã")'); await h.dormir(150);
    await definirInicio(h, p, 19, 30);
    await p.click('[data-sel="fim"]'); await h.dormir(300); await p.click('[data-sel-dur="60"]'); await p.click('[data-sel-ok]'); await h.dormir(150);
    await p.click('#nc-salvar');
    h.ok(await h.ate(async () => (await h.contadores()).criados.length === 1), `${nome}: Salvar manda o compromisso ao Mac`);
    const c = (await h.contadores()).criados[0];
    h.ok(c.inicio === '19:30' && c.fim === '20:30' && c.titulo === 'Ensaio dos seletores' && c.dia === amanha && !c.diaTodo, `${nome}: o corpo enviado tem o dia, o início e o fim escolhidos nos seletores (${JSON.stringify(c)})`);
    await h.reset();

    // fechar o formulário fecha o seletor
    await h.espera(p, () => document.querySelector('#ca-form').hidden);
    await p.click('#ca-puxa'); await h.dormir(400); await p.click('[data-sel="inicio"]'); await h.dormir(300);
    await p.evaluate(() => document.querySelector('[data-nc-cancelar]').click()); await h.dormir(100);
    h.ok(await p.evaluate(() => document.querySelector('#ca-sel').hidden && document.querySelector('#ca-form').hidden), `${nome}: fechar o formulário fecha o seletor junto`);
    await ctx.close();
  }

  /* ---------- 3. lembrete tem cor e ícone próprios ---------- */
  for (const [nome, w, al] of VISTAS) {
    await h.reset(); await h.cenario({ agendaLembretes: true });
    const ctx = await h.novoContexto({ viewport: { width: w, height: al } });
    const p = await h.pagina({ ctx }); await abrirAgenda(h, p);
    await p.locator('#ca-grade [data-dia$="-20"]').click(); await h.dormir(500);
    const linhas = await p.evaluate(() => [...document.querySelectorAll('#ca-lista .ev-linha')].filter(l => /boleto|Consciência/.test(l.textContent)).map(l => ({ t: l.querySelector('b').textContent, sub: l.querySelector('.tx > span').textContent, cor: getComputedStyle(l.querySelector(':scope > i')).backgroundColor, icone: !!l.querySelector('.ic-lem') })));
    const lem = linhas.find(l => /boleto/.test(l.t)), feriado = linhas.find(l => /Consciência/.test(l.t));
    h.ok(!!lem && !!feriado && lem.cor !== feriado.cor, `${nome}: lembrete e feriado, os dois roxos no Mac, aparecem em cores diferentes (${lem?.cor} contra ${feriado?.cor})`);
    h.ok(lem?.cor === 'rgb(255, 159, 10)' && lem.icone && /^Lembrete, Trabalho/.test(lem.sub), `${nome}: o lembrete é laranja, tem o ícone do app Lembretes e diz "Lembrete" (${JSON.stringify(lem)})`);
    h.ok(feriado?.cor === 'rgb(180, 75, 214)' && !feriado.icone, `${nome}: o evento do calendário segue com a cor real do calendário e sem ícone (${feriado?.cor})`);
    await foto(p, `${nome}-lembrete`);
    await ctx.close(); await h.cenario({ agendaLembretes: false });
  }

  /* ---------- 4. verificação: teto de 23:59 e duração mantida perto da meia-noite, agora na roleta ---------- */
  for (const [nome, w, al] of VISTAS) {
    await h.reset();
    const ctx = await h.novoContexto({ viewport: { width: w, height: al }, hasTouch: true });
    const p = await h.pagina({ ctx }); await abrirAgenda(h, p); await abrirForm(h, p);
    // teto: Início 23:55 deixa o Fim em 23:59 e mexer na roleta do Fim não invalida o campo
    await definirInicio(h, p, 23, 55);
    h.ok(await valor(p, 'nc-inicio') === '23:55' && await valor(p, 'nc-fim') === '23:59', `${nome}: Início 23:55 deixa o Fim em 23:59 (${await valor(p, 'nc-inicio')} até ${await valor(p, 'nc-fim')})`);
    await abrirRoleta(h, p, 'fim');
    h.ok(await naFaixa(p) === '23:59' && /23:59/.test(await p.textContent('#sel-valor')), `${nome}: a roleta do Fim mostra 23:59 (${await naFaixa(p)})`);
    for (const [chave, itens] of [['m', -1], ['m', 1], ['h', -1], ['h', 1]]) {
      await arrastar(p, ctx, chave, itens); await h.dormir(1500);
      const v = await valor(p, 'nc-fim');
      h.ok(v === '23:59' && /23:59/.test(await p.textContent('#nc-fim-val')) && await naFaixa(p) === '23:59' && await assentada(p), `${nome}: no teto, arrastar ${chave === 'h' ? 'as horas' : 'os minutos'} ${itens > 0 ? 'para cima' : 'para baixo'} mantém 23:59 e a roleta volta (campo "${v}", roleta "${await naFaixa(p)}")`);
    }
    await p.click('[data-sel-ok]'); await h.dormir(150);
    // duração guardada: voltar para um horário cedo devolve 1 h, não a duração comprimida
    await definirInicio(h, p, 10, 0);
    h.ok(await valor(p, 'nc-inicio') === '10:00' && await valor(p, 'nc-fim') === '11:00', `${nome}: depois de 23:55, voltar para 10:00 devolve a duração de 1 h (${await valor(p, 'nc-inicio')} até ${await valor(p, 'nc-fim')})`);
    // duração escolhida e mantida ao mover o início
    await definirInicio(h, p, 9, 0);
    await abrirRoleta(h, p, 'fim'); await p.click('[data-sel-dur="120"]'); await h.dormir(500);
    h.ok(await valor(p, 'nc-fim') === '11:00', `${nome}: 9:00 com 2 h termina às 11:00 (${await valor(p, 'nc-fim')})`);
    await p.click('[data-sel-ok]'); await h.dormir(150);
    await definirInicio(h, p, 10, 0);
    h.ok(await valor(p, 'nc-fim') === '12:00', `${nome}: mover o Início mantém a duração escolhida de 2 h (${await valor(p, 'nc-fim')})`);
    // a duração vinda da roleta do Fim também fica guardada
    await abrirRoleta(h, p, 'fim'); await tocarItem(p, 'h', 14); await h.dormir(500); await p.click('[data-sel-ok]'); await h.dormir(150);
    await definirInicio(h, p, 8, 0);
    h.ok(await valor(p, 'nc-fim') === '12:00', `${nome}: o Fim ajustado na roleta (4 h) é a duração guardada e acompanha o Início (${await valor(p, 'nc-fim')})`);
    await ctx.close();
  }
}
