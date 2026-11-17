// Frente agenda-seletores (17/11/2026): círculos do dia alinhados, seletores próprios de Dia, Início e Fim, e lembrete de outra cor que o feriado.
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
    const ctx = await h.novoContexto({ viewport: { width: w, height: al } });
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

    // Início
    await p.click('[data-sel="inicio"]'); await h.dormir(500);
    h.ok(await p.evaluate(() => document.querySelector('#sel-titulo').textContent === 'Início') && await p.evaluate(() => window.__nativo) === 0, `${nome}: tocar em Início abre o seletor do Deck`);
    await foto(p, `${nome}-inicio`);
    const horas = await p.evaluate(() => [...document.querySelectorAll('#sel-meio [data-sel-hora]')].map(b => b.dataset.selHora));
    h.ok(horas.length === 48 && horas[0] === '00:00' && horas[1] === '00:30' && horas[47] === '23:30', `${nome}: a grade tem os horários de 30 em 30 min, de 00:00 a 23:30 (${horas.length})`);
    const al2 = await p.evaluate(() => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth; return [...document.querySelectorAll('#ca-sel button')].map(b => { const r = b.getBoundingClientRect(); return Math.min(r.width, r.height) / k }).filter(v => v < 43.5).length });
    h.ok(al2 === 0, `${nome}: chips, passos e Pronto do Início têm 44 pt`);
    await p.locator('#sel-meio [data-sel-hora="14:30"]').scrollIntoViewIfNeeded(); await p.locator('#sel-meio [data-sel-hora="14:30"]').click(); await h.dormir(100);
    h.ok(await valor(p, 'nc-inicio') === '14:30' && await valor(p, 'nc-fim') === '15:30', `${nome}: escolher 14:30 leva o fim junto, mantendo 1 h (${await valor(p, 'nc-inicio')} até ${await valor(p, 'nc-fim')})`);
    h.ok(await p.evaluate(() => document.querySelector('#sel-meio [aria-pressed="true"]')?.dataset.selHora) === '14:30' && await p.evaluate(() => !document.querySelector('#ca-sel').hidden), `${nome}: o chip escolhido fica marcado e o seletor segue aberto para o ajuste fino`);
    await p.click('[data-sel-passo="5"]'); await h.dormir(80); await p.click('[data-sel-passo="5"]'); await h.dormir(80);
    h.ok(await valor(p, 'nc-inicio') === '14:40' && await valor(p, 'nc-fim') === '15:40', `${nome}: +5 min duas vezes dá 14:40 (${await valor(p, 'nc-inicio')})`);
    await p.click('[data-sel-passo="-5"]'); await h.dormir(80);
    h.ok(await valor(p, 'nc-inicio') === '14:35' && /14:35/.test(await p.textContent('#nc-inicio-val')), `${nome}: -5 min volta para 14:35 e o campo acompanha`);
    await p.click('[data-sel-ok]'); await h.dormir(150);
    h.ok(await p.evaluate(() => document.querySelector('#ca-sel').hidden), `${nome}: Pronto fecha o seletor`);

    // Fim
    await p.click('[data-sel="fim"]'); await h.dormir(500);
    h.ok(await p.evaluate(() => document.querySelector('#sel-titulo').textContent === 'Fim') && await p.evaluate(() => window.__nativo) === 0, `${nome}: tocar em Fim abre o seletor do Deck`);
    await foto(p, `${nome}-fim`);
    const durs = await p.evaluate(() => [...document.querySelectorAll('#sel-meio [data-sel-dur]')].map(b => b.querySelector('b').textContent));
    h.ok(['15 min', '30 min', '1 h', '2 h'].every(t => durs.includes(t)), `${nome}: o Fim oferece as durações 15 min, 30 min, 1 h e 2 h (${durs.join(' | ')})`);
    await p.click('[data-sel-dur="120"]'); await h.dormir(100);
    h.ok(await valor(p, 'nc-fim') === '16:35', `${nome}: 2 h depois de 14:35 é 16:35 (${await valor(p, 'nc-fim')})`);
    await p.click('[data-sel-dur="15"]'); await p.click('[data-sel-passo="-5"]'); await h.dormir(80); await p.click('[data-sel-passo="-5"]'); await h.dormir(80);
    h.ok(await valor(p, 'nc-fim') === '14:40', `${nome}: o fim nunca fica antes do início (parou em ${await valor(p, 'nc-fim')})`);
    await p.click('[data-sel-ok]'); await h.dormir(150);

    // início tarde: duração que passa da meia-noite fica desligada
    await p.click('[data-sel="inicio"]'); await h.dormir(300); await p.locator('#sel-meio [data-sel-hora="23:00"]').scrollIntoViewIfNeeded(); await p.locator('#sel-meio [data-sel-hora="23:00"]').click(); await p.click('[data-sel-ok]'); await h.dormir(150);
    await p.click('[data-sel="fim"]'); await h.dormir(300);
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
    await p.click('[data-sel="inicio"]'); await h.dormir(300); await p.locator('#sel-meio [data-sel-hora="19:30"]').scrollIntoViewIfNeeded(); await p.locator('#sel-meio [data-sel-hora="19:30"]').click(); await p.click('[data-sel-ok]'); await h.dormir(150);
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

  /* ---------- 2b. o início abre rolado até o horário de agora (hoje) ---------- */
  {
    const ctx = await h.novoContexto({ viewport: { width: 932, height: 430 } });
    const p = await h.pagina({ ctx }); await abrirAgenda(h, p); await abrirForm(h, p);
    await p.click('[data-sel="inicio"]'); await h.dormir(500);
    const r = await p.evaluate(() => { const ref = new Date(window.V?.ref || Date.now()), alvo = String(ref.getHours()).padStart(2, '0') + ':' + (ref.getMinutes() >= 30 ? '30' : '00'), m = document.querySelector('#sel-meio'), c = m.querySelector(`[data-sel-hora="${alvo}"]`); const a = m.getBoundingClientRect(), b = c.getBoundingClientRect(); return { alvo, visivel: b.top >= a.top - 1 && b.bottom <= a.bottom + 1, rolou: m.scrollTop > 0 } });
    h.ok(r.visivel && (r.rolou || r.alvo === '00:00' || r.alvo === '00:30'), `a grade de Início abre rolada até o horário de agora (${r.alvo}, visível ${r.visivel})`);
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
}
