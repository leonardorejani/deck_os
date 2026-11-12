// Agenda: criar compromisso pelo iPhone (a parte da direita vira o formulário), com o Mac de mentira.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const aviso = p => p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, visivel: document.querySelector('#aviso').classList.contains('visivel'), erro: document.querySelector('#aviso').classList.contains('erro') }));
const texto = (p, sel) => p.evaluate(s => document.querySelector(s)?.textContent.replace(/\s+/g, ' ').trim() ?? null, sel);
const alvo = (p, sel) => p.evaluate(s => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, b = document.querySelector(s).getBoundingClientRect(); return { l: Math.round(b.width / k), a: Math.round(b.height / k) } }, sel);
const aqui = path.dirname(fileURLToPath(import.meta.url));

// abre a agenda no mês que vem (sempre no futuro) e toca no dia 15. Devolve o dia tocado (AAAA-MM-DD)
async function abrir(h, p) {
  await p.click('.tecla[data-id="calendario"]');
  await h.espera(p, () => document.querySelectorAll('#ca-lista .ev-linha').length > 0 || !!document.querySelector('#ca-lista .btn-novo'));
  await p.click('#ca-prox'); await h.dormir(500);
  const dia = await p.evaluate(() => document.querySelectorAll('#ca-grade .sb-dia')[14].dataset.dia);
  await p.locator('#ca-grade .sb-dia').nth(14).click();
  await h.espera(p, () => !!document.querySelector('#ca-lista .btn-novo'));
  return dia;
}
const formAberto = p => p.evaluate(() => !document.querySelector('#ca-form').hidden && document.querySelector('#ca-lista').hidden);

export default async function (h) {
  /* ---------- abrir o formulário ---------- */
  await h.reset();
  let p = await h.pagina(); await pronta(h, p);
  const dia = await abrir(h, p);
  const rotulo = await texto(p, '#ca-lista .btn-novo');
  h.ok(/^Novo compromisso em \d+ de \S+$/.test(rotulo), `tocar num dia oferece "Novo compromisso em <dia>" no topo da lista (${rotulo})`);
  h.ok((await alvo(p, '#ca-lista .btn-novo')).a >= 44, 'o botão Novo compromisso tem alvo de toque de 44 pt');
  const listaAntes = await p.evaluate(() => { const r = document.querySelector('#ca-lista').getBoundingClientRect(); return { x: Math.round(r.x), w: Math.round(r.width) } });
  await p.click('#ca-lista .btn-novo');
  h.ok(await h.espera(p, () => !document.querySelector('#ca-form').hidden && !!document.querySelector('#nc-destino option[value^="calendario:"]')), 'o botão abre o formulário e ele carrega os lugares do Mac');
  h.ok(await formAberto(p), 'a lista some e o formulário fica no lugar dela');
  const form = await p.evaluate(() => { const r = document.querySelector('#ca-form').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return { x: Math.round(r.x - t.x), dir: Math.round(r.right - t.right) } });
  h.ok(Math.abs(form.x - listaAntes.x) <= 2 && form.dir <= 2, `o formulário ocupa a parte da direita inteira (x ${form.x} contra ${listaAntes.x} da lista)`);
  const campos = await p.evaluate(() => ({ dia: document.querySelector('#nc-dia').value, destino: document.querySelector('#nc-destino').value, alerta: document.querySelector('#nc-alerta').value, todo: document.querySelector('#nc-todo').checked, titulo: document.querySelector('#nc-titulo').value }));
  h.ok(campos.dia === dia && campos.destino === 'calendario:cal-trab' && campos.alerta === '' && campos.todo === false && campos.titulo === '', `já vem com o dia tocado, o primeiro calendário, sem alerta e com hora (dia todo desligado) (${JSON.stringify(campos)})`);
  const rolo = await p.evaluate(() => { const t = document.querySelector('#tela').getBoundingClientRect(), s = document.querySelector('#nc-salvar').getBoundingClientRect(); return { dentro: s.bottom <= t.bottom + 1 && s.top >= t.top, a: Math.round(s.height) } });
  h.ok(rolo.dentro, 'em 932x430 o botão Salvar fica à vista (o corpo é que rola)');
  h.ok((await alvo(p, '#nc-salvar')).a >= 44 && (await alvo(p, '[data-nc-cancelar]')).a >= 44, 'Salvar e Cancelar têm alvo de toque de 44 pt');
  const corte = await p.evaluate(() => { const c = document.querySelector('.nc-corpo'); return c.scrollHeight - c.clientHeight });
  h.ok(corte <= 1, `em 932x430 todos os campos cabem sem rolar (sobram ${corte} px)`);
  await h.foto(p, 'agenda-novo-deitado');

  /* ---------- validação antes de ir ao Mac ---------- */
  await p.click('#nc-salvar'); await h.dormir(150);
  h.ok(await texto(p, '#nc-msg') === 'Dê um título ao compromisso.' && (await h.contadores()).criados.length === 0, 'sem título: avisa dentro do formulário e não manda nada');
  await p.fill('#nc-titulo', 'Ensaio geral'); await p.fill('#nc-inicio', '19:00'); await p.fill('#nc-fim', '18:00');
  await p.click('#nc-salvar'); await h.dormir(150);
  h.ok(await texto(p, '#nc-msg') === 'O fim precisa ser depois do início.' && (await h.contadores()).criados.length === 0, 'fim antes do início: avisa e não manda nada');
  h.ok(await p.evaluate(() => document.querySelector('#nc-msg').classList.contains('erro')), 'o aviso de erro usa a cor de erro');

  /* ---------- criar, escolher o destino e marcar como padrão ---------- */
  await p.fill('#nc-fim', '21:00'); await p.selectOption('#nc-alerta', '15'); await p.selectOption('#nc-destino', 'calendario:cal-pes');
  h.ok(await texto(p, '#nc-padrao-txt') === 'Usar como padrão' && !(await p.isDisabled('#nc-padrao')), 'um lugar que não é o padrão oferece "Usar como padrão"');
  await p.check('#nc-padrao');
  await p.click('#nc-salvar');
  h.ok(await h.ate(async () => (await h.contadores()).criados.length === 1), 'Salvar manda o compromisso ao Mac');
  let c = await h.contadores();
  h.ok(JSON.stringify(c.criados[0]) === JSON.stringify({ titulo: 'Ensaio geral', dia, diaTodo: false, destino: { tipo: 'calendario', id: 'cal-pes' }, padrao: true, inicio: '19:00', fim: '21:00', alertaMin: 15 }), `o corpo tem título, dia, horas, destino, alerta e padrão (${JSON.stringify(c.criados[0])})`);
  h.ok(await h.espera(p, () => document.querySelector('#ca-form').hidden && !document.querySelector('#ca-lista').hidden), 'depois de salvar o formulário fecha e a lista volta');
  h.ok(await h.espera(p, t => [...document.querySelectorAll('#ca-lista .ev-linha b')].some(b => b.textContent === t), 'Ensaio geral'), 'a agenda recarrega e mostra o compromisso novo');
  h.ok(await p.evaluate(d => document.querySelector('#ca-grade .sb-dia.sel')?.dataset.dia === d, dia), 'o dia do compromisso fica escolhido no mês');
  h.ok((await aviso(p)).txt === 'Compromisso criado no Calendário do Mac', 'um aviso confirma');

  /* ---------- o padrão vale na próxima vez ---------- */
  await p.click('#ca-lista .btn-novo');
  await h.espera(p, () => document.querySelector('#nc-destino').value.startsWith('calendario:'));
  await h.dormir(200);
  const padrao = await p.evaluate(() => ({ v: document.querySelector('#nc-destino').value, marcado: document.querySelector('#nc-padrao').checked, off: document.querySelector('#nc-padrao').disabled, t: document.querySelector('#nc-padrao-txt').textContent }));
  h.ok(padrao.v === 'calendario:cal-pes' && padrao.marcado && padrao.off && padrao.t === 'É o lugar padrão', `o lugar padrão já vem escolhido e diz que é o padrão (${JSON.stringify(padrao)})`);

  /* ---------- dia todo ---------- */
  await p.fill('#nc-titulo', 'Retiro'); await p.check('#nc-todo');
  const todo = await p.evaluate(() => ({ off: document.querySelector('#nc-inicio').disabled && document.querySelector('#nc-fim').disabled, alertas: [...document.querySelectorAll('#nc-alerta option')].map(o => o.textContent) }));
  h.ok(todo.off && todo.alertas.includes('No dia, às 9h') && !todo.alertas.includes('5 minutos antes'), `dia todo desliga as horas e troca as opções de alerta (${todo.alertas.join(' | ')})`);
  await p.selectOption('#nc-alerta', '1440'); await p.click('#nc-salvar');
  h.ok(await h.ate(async () => (await h.contadores()).criados.length === 2), 'o dia todo vai ao Mac');
  c = await h.contadores();
  h.ok(c.criados[1].diaTodo === true && c.criados[1].inicio === undefined && c.criados[1].fim === undefined && c.criados[1].alertaMin === 1440 && !c.criados[1].padrao, `sem horas, com alerta de 1 dia antes e sem repetir o padrão (${JSON.stringify(c.criados[1])})`);

  /* ---------- cancelar ---------- */
  await h.espera(p, () => document.querySelector('#ca-form').hidden);
  await p.click('#ca-lista .btn-novo'); await p.fill('#nc-titulo', 'Não vai'); await p.click('[data-nc-cancelar]');
  h.ok(!(await formAberto(p)) && (await h.contadores()).criados.length === 2, 'Cancelar fecha sem mandar nada');
  await p.click('#ca-lista .btn-novo');
  h.ok(await p.evaluate(() => document.querySelector('#nc-titulo').value === ''), 'e o formulário abre limpo da próxima vez');
  await p.context().close();

  /* ---------- Lembretes: o acesso é pedido só quando a pessoa escolhe ---------- */
  await h.reset(); await h.cenario({ agendaCriar: 'lembretes-pedir' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await p.click('#ca-lista .btn-novo');
  await h.espera(p, () => !!document.querySelector('#nc-destino option[value="pedir"]'));
  c = await h.contadores();
  h.ok(await p.evaluate(() => document.querySelector('#nc-destino option[value="pedir"]').textContent) === 'Liberar os Lembretes no Mac' && c.destinosPedidos === 0, 'sem acesso aos Lembretes: só aparece "Liberar os Lembretes no Mac" e nada foi pedido ainda');
  await p.selectOption('#nc-destino', 'pedir');
  h.ok(await h.ate(async () => (await h.contadores()).destinosPedidos === 1), 'escolher essa opção pede o acesso no Mac');
  h.ok((await texto(p, '#nc-msg')).includes('Aceite o pedido'), 'e o formulário manda aceitar na tela do Mac');
  h.ok(await h.espera(p, () => !!document.querySelector('#nc-destino option[value="lembretes:lis-compras"]'), undefined, 9000), 'quando o Mac libera, as listas dos Lembretes aparecem sozinhas');
  h.ok(await p.evaluate(() => document.querySelector('#nc-destino').value) === 'lembretes:lis-compras', 'e a primeira lista já fica escolhida');
  await p.fill('#nc-titulo', 'Comprar pão'); await p.check('#nc-todo'); await p.click('#nc-salvar');
  h.ok(await h.ate(async () => (await h.contadores()).criados.length === 1), 'salva na lista dos Lembretes');
  c = await h.contadores();
  h.ok(c.criados[0].destino.tipo === 'lembretes' && c.criados[0].destino.id === 'lis-compras', 'o destino vai como lembretes');
  await h.espera(p, () => document.querySelector('#aviso-txt').textContent.startsWith('Lembrete criado'));
  h.ok((await aviso(p)).txt === 'Lembrete criado em Compras. Ele aparece no app Lembretes.', `o aviso diz onde o lembrete foi parar (${(await aviso(p)).txt})`);
  await p.context().close();

  /* ---------- o Mac recusa ---------- */
  await h.reset(); await h.cenario({ agendaCriar: 'recusa' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await p.click('#ca-lista .btn-novo'); await h.espera(p, () => !!document.querySelector('#nc-destino option[value^="calendario:"]'));
  await p.fill('#nc-titulo', 'Reunião'); await p.click('#nc-salvar'); await h.dormir(400);
  h.ok(await formAberto(p) && (await texto(p, '#nc-msg')).startsWith('O Deck está sem acesso ao Calendário') && await p.evaluate(() => document.querySelector('#nc-msg').classList.contains('erro')), 'Mac que recusa: o motivo aparece no formulário, que continua aberto com o que foi digitado');
  h.ok(await p.evaluate(() => !document.querySelector('#nc-salvar').disabled && document.querySelector('#nc-titulo').value === 'Reunião'), 'e dá para tentar de novo');
  await p.context().close();

  /* ---------- Mac sem a função (versão antiga) ---------- */
  await h.reset(); await h.cenario({ agendaCriar: 'antigo' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await p.click('#ca-lista .btn-novo'); await h.espera(p, () => (document.querySelector('#nc-msg').textContent || '').includes('Atualize'));
  await p.fill('#nc-titulo', 'Teste'); await p.click('#nc-salvar'); await h.dormir(200);
  h.ok((await texto(p, '#nc-msg')).includes('Atualize o Deck no Mac') && (await h.contadores()).criados.length === 0, 'Mac antigo: pede para atualizar o Deck e não manda nada');
  await p.context().close();

  /* ---------- em pé ---------- */
  await h.reset();
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p);
  await p.click('.tecla[data-id="calendario"]'); await h.espera(p, () => !!document.querySelector('#ca-lista .btn-novo'));
  await p.click('#ca-lista .btn-novo'); await h.espera(p, () => !!document.querySelector('#nc-destino option[value^="calendario:"]')); await h.dormir(300);
  h.ok(await p.evaluate(() => { const f = document.querySelector('#ca-form').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return document.documentElement.scrollWidth <= innerWidth + 1 && f.right <= t.right + 1 && f.left >= t.left - 1 && document.querySelector('#nc-salvar').getBoundingClientRect().bottom <= t.bottom + 1 }), 'em pé: o formulário cabe na tela, sem rolar para o lado, com o Salvar à vista');
  await h.foto(p, 'agenda-novo-em-pe');
  await p.context().close();

  /* ---------- o app nativo conhece as duas rotas ---------- */
  const ponte = fs.readFileSync(path.join(aqui, '../../ios/Web/ponte.js'), 'utf8');
  h.ok(ponte.includes("'/api/agenda/destinos'") && ponte.includes("'/api/agenda/criar'"), 'a ponte do app nativo (ios/Web/ponte.js) tem agendaDestinos e criarCompromisso');
}
