// Tela de fábrica do Monitor de Atividade no iPhone (SPEC, seção 13, itens 38 e 39): a tecla do app abre uma folha com uma grade de
// cartões (CPU, GPU, memória, bateria, rede, disco disponível, energia, ventoinhas e dispositivos), só os que a pessoa deixou
// ligados e que o Mac conseguiu ler. Sem processos e sem "Encerrar". O número conta do valor antigo ao novo.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const abrir = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="monitor"]').click());
  return h.espera(p, () => document.querySelector('#f-monitor').classList.contains('aberta') && !!document.querySelector('#mn-corpo .mn-grade, #mn-corpo .mn-vazio'));
};
const cartoes = p => p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-cartao')].map(c => c.querySelector('.mn-rot').textContent + ':' + [...c.querySelectorAll('.mn-num')].map(n => n.textContent).join(' ')).join('|'));
const rotulos = p => p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-cartao .mn-rot')].map(e => e.textContent).join('|'));

const TUDO = 'CPU:12%|GPU:27%|Memória:63%|Bateria:81%|Rede:1,2 MB/s 40 KB/s|Disco disponível:412GB|Energia:11,4W|Ventoinhas:2.500RPM|Dispositivos:3';
const BASE = { cpu: 12, memoria: 63, bateria: 81, naTomada: false, baixa: 1258291, sobe: 40960, gpu: 27, discoLivre: 412000000000, discoTotal: 994000000000, watts: 11.4, carregando: false, ventoinhas: [2400, 2600], ventoinhaMax: 6000, dispositivos: 3 };

export default async function (h) {
  /* ---------- tudo ligado: a grade com os nove cartões, sem processos ---------- */
  await h.cenario({ comMonitorApp: true, blocos: { monitor: true } });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'tocar na tecla do Monitor de Atividade abre a folha');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0, `a tecla abre a tela no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  h.ok(await p.evaluate(() => document.querySelector('#mn-titulo').textContent) === 'Monitor de Atividade', 'título "Monitor de Atividade"');
  h.ok(await cartoes(p) === TUDO, `os nove cartões, na ordem (${await cartoes(p)})`);
  h.ok(await p.evaluate(() => !document.querySelector('#mn-corpo [data-mn-pedir], #mn-corpo .mn-secao, #mn-corpo .mn-proc') && !/Encerrar|processos/i.test(document.querySelector('#f-monitor').textContent)), 'sem lista de processos e sem Encerrar na tela');
  const forma = await p.evaluate(() => {
    const cs = [...document.querySelectorAll('#mn-corpo .mn-cartao')], r = cs.map(x => x.getBoundingClientRect());
    return { n: cs.length, icones: cs.filter(x => x.querySelector('.mn-ic svg')).length, barras: cs.filter(x => !x.querySelector('.mn-barra').hidden).length, altura: new Set(r.map(q => Math.round(q.height))).size,
      raio: getComputedStyle(cs[0]).borderRadius, rede: !!cs[4].querySelector('.mn-seta'), setas: cs[4].querySelectorAll('.mn-seta').length, rotCor: getComputedStyle(cs[0].querySelector('.mn-rot')).color, numCor: getComputedStyle(cs[0].querySelector('.mn-num')).color,
      tabular: getComputedStyle(cs[0].querySelector('.mn-num')).fontVariantNumeric };
  });
  h.ok(forma.icones === 9, `cada cartão tem o ícone pequeno e o rótulo (ícones: ${forma.icones})`);
  h.ok(forma.barras === 6, `a barra fina aparece onde há porcentagem: CPU, GPU, memória, bateria, disco e ventoinhas (barras: ${forma.barras})`);
  h.ok(forma.setas === 2 && forma.rede, 'a rede mostra a seta de baixar e a de enviar');
  h.ok(forma.tabular.includes('tabular-nums'), 'algarismos de largura fixa, para o número não tremer ao contar');
  const grande = await p.evaluate(() => { const c = document.querySelectorAll('#mn-corpo .mn-cartao')[4]; return [...c.querySelectorAll('.mn-num')].map(n => parseFloat(getComputedStyle(n).fontSize)) });
  h.ok(grande.length === 2 && grande[0] > grande[1], `na rede, o download é grande e o upload é menor (${grande.join(' e ')} px)`);
  const caiu = await p.evaluate(() => { const g = document.querySelector('#mn-corpo'); return g.scrollHeight <= g.clientHeight + 1 });
  h.ok(caiu, 'deitado, os nove cartões cabem na tela sem rolar');
  await h.dormir(700); await h.foto(p, 'monitor-painel');

  /* ---------- cores: laranja quando alto, vermelho quando cheio ---------- */
  await h.cenario({ monitor: { ...BASE, cpu: 75, memoria: 95, gpu: 10 } });
  h.ok(await h.espera(p, () => { const q = document.querySelectorAll('#mn-corpo .mn-cartao'); return q[0].classList.contains('alto') && q[2].classList.contains('cheio') && !q[1].classList.contains('alto') }, undefined, 6000), 'CPU a 75% fica em alerta (alto), memória a 95% em cheio, GPU a 10% normal');
  await h.dormir(700); // a cor e a barra trocam com transição
  const cores = await p.evaluate(() => { const q = document.querySelectorAll('#mn-corpo .mn-cartao'); return { alto: getComputedStyle(q[0].querySelector('.mn-num')).color, normal: getComputedStyle(q[1].querySelector('.mn-num')).color, barra: getComputedStyle(q[0].querySelector('.mn-barra i')).backgroundColor, aviso: getComputedStyle(document.documentElement).getPropertyValue('--aviso') } });
  h.ok(cores.alto !== cores.normal && cores.barra === cores.alto, `o número e a barra do cartão em alerta trocam de cor juntos (${cores.alto} contra ${cores.normal})`);
  await h.cenario({ monitor: BASE });

  /* ---------- o número conta do valor antigo ao novo, no mesmo cartão ---------- */
  await p.evaluate(() => { document.querySelector('#mn-corpo .mn-cartao').dataset.marca = 'o-mesmo'; window.__amostras = []; });
  await h.cenario({ monitor: { ...BASE, cpu: 80 } });
  await p.evaluate(() => { const t0 = performance.now(), el = document.querySelector('#mn-corpo .mn-cartao .mn-num'); (function amostra() { window.__amostras.push(parseInt(el.textContent)); if (performance.now() - t0 < 4500) requestAnimationFrame(amostra) })() });
  h.ok(await h.espera(p, () => document.querySelector('#mn-corpo .mn-cartao .mn-num').textContent.startsWith('80'), undefined, 6000), 'a CPU muda de 12% para 80% na tela');
  await h.dormir(1500);
  const amostras = await p.evaluate(() => window.__amostras);
  const meio = amostras.filter(v => v > 12 && v < 80);
  h.ok(meio.length >= 3, `o número passa por valores no meio do caminho em vez de pular (${meio.length} amostras entre 12 e 80)`);
  h.ok(amostras.every((v, i) => i === 0 || v >= amostras[i - 1]), 'e só sobe, sem ir e voltar');
  h.ok(await p.evaluate(() => document.querySelector('#mn-corpo .mn-cartao').dataset.marca) === 'o-mesmo', 'o cartão é o mesmo elemento: a tela não é refeita a cada segundo');
  h.ok(await p.evaluate(() => getComputedStyle(document.querySelector('#mn-corpo .mn-cartao .mn-barra i')).transform.includes('0.8')), 'a barra acompanha o valor novo');
  h.ok(await p.evaluate(() => document.querySelector('#mn-corpo .mn-cartao .mn-num').textContent) === '80%', 'termina exatamente no valor novo');
  await p.click('#f-monitor [data-fechar]');
  h.ok(await h.espera(p, () => !document.querySelector('#f-monitor').classList.contains('aberta')), 'o X fecha a folha');
  await p.context().close();

  /* ---------- só os itens escolhidos nos Ajustes do Mac ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitorItens: { cpu: true, memoria: false, bateria: false, rede: true, gpu: false, disco: true, energia: false, ventoinhas: false, dispositivos: false } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await rotulos(p) === 'CPU|Rede|Disco disponível', `item desligado nos Ajustes não aparece (${await rotulos(p)})`);
  await p.context().close();

  /* ---------- o que o Mac não consegue ler some, em vez de virar "-" ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitor: { cpu: 12, memoria: 63, baixa: 1, sobe: 1 } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await rotulos(p) === 'CPU|Memória|Rede', `Mac de mesa sem bateria, GPU, disco, energia, ventoinha nem USB: só os três que ele leu (${await rotulos(p)})`);
  h.ok(await p.evaluate(() => document.querySelector('#mn-corpo .mn-grade').dataset.n) === '3', 'a grade se reorganiza para os cartões que sobraram');
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitor: { ...BASE, ventoinhas: [], dispositivos: 0, watts: undefined, carregando: undefined } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(!/Ventoinhas|Energia/.test(await rotulos(p)) && /Dispositivos:0/.test(await cartoes(p)), `Mac sem ventoinha e sem medida de energia: somem. Zero dispositivos continua valendo (${await rotulos(p)})`);
  await p.context().close();

  /* ---------- tags: na tomada, carregando, ventoinhas ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitor: { ...BASE, naTomada: true, carregando: true } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  const tags = await p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-cartao')].map(c => c.querySelector('.mn-rot').textContent + '=' + c.querySelector('.mn-tag').textContent + c.querySelector('.mn-nota').textContent).filter(x => !x.endsWith('=')).join('|'));
  h.ok(tags === 'Bateria=na tomada|Energia=carregando|Dispositivos=conectados', `as notas pequenas: na tomada ao lado do rótulo, o resto no lugar da barra (${tags})`);
  await p.context().close();

  /* ---------- em pé: duas colunas ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true } });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p); await abrir(h, p);
  const em_pe = await p.evaluate(() => { const g = document.querySelector('#mn-corpo .mn-grade'), col = getComputedStyle(g).gridTemplateColumns.split(' ').length, folha = document.querySelector('#f-monitor').getBoundingClientRect(); return { col, l: Math.min(...[...g.children].map(x => x.getBoundingClientRect().left)), r: Math.max(...[...g.children].map(x => x.getBoundingClientRect().right)), folhaR: folha.right, folhaL: folha.left } });
  h.ok(em_pe.col === 2 && em_pe.l >= em_pe.folhaL && em_pe.r <= em_pe.folhaR + 1, `em pé a grade tem 2 colunas e não passa da tela (${JSON.stringify(em_pe)})`);
  await h.foto(p, 'monitor-painel-pe');
  await p.context().close();

  /* ---------- monitor desligado, ou ligado sem nenhum item, ou nada lido: a tela explica ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(/O monitor está desligado/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)) && await cartoes(p) === '', 'bloco desligado: a tela diz onde ligar, sem cartão falso');
  h.ok(/em Este Mac/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)) && !/tecla Monitor de Atividade/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)), 'o aviso manda ligar em Este Mac, que todo perfil tem, e não na tecla do Monitor (que pode não existir)');
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitorItens: { cpu: false, memoria: false, bateria: false, rede: false, gpu: false, disco: false, energia: false, ventoinhas: false, dispositivos: false } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(/Nenhum item ligado/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)), 'ligado sem nenhum item: "Nenhum item ligado"');
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitorItens: { cpu: false, memoria: false, bateria: false, rede: false, gpu: true, disco: false, energia: false, ventoinhas: true, dispositivos: false }, monitor: {} });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(/não conseguiu ler/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)), 'itens ligados que o Mac não lê: a tela explica em vez de ficar vazia');
  await p.context().close();

  /* ---------- a tecla vem do editor, como qualquer app ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const r = await p.evaluate(() => ({ painel: painelDe({ tipo: 'app', valor: 'Activity Monitor' }), comAcao: painelDe({ tipo: 'app', valor: 'Activity Monitor', acao: { id: 'x' } }) }));
  h.ok(r.painel === 'monitor' && r.comAcao === undefined, `a tecla de app "Activity Monitor" abre a tela do monitor, e com ação vai para o Mac (${JSON.stringify(r)})`);
  await p.context().close();
}
