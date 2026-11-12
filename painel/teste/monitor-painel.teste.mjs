// Tela de fábrica do Monitor de Atividade no iPhone (SPEC, seção 13, item 38): a tecla do app abre uma folha com os dados do
// monitor em tamanho grande (só os itens escolhidos) e os 5 processos que mais usam processador e memória, com "Encerrar"
// que sempre pergunta antes. O Mac de mentira guarda os processos e diz quais pode encerrar.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const abrir = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="monitor"]').click());
  return h.espera(p, () => document.querySelector('#f-monitor').classList.contains('aberta') && !document.querySelector('#mn-corpo .esq-lista'));
};
const nomes = (p, i) => p.evaluate(i => [...document.querySelectorAll('#mn-corpo .mn-secao')[i].querySelectorAll('.mn-nome')].map(e => e.textContent).join('|'), i);
const cartoes = p => p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-cartao')].map(c => c.querySelector('.mn-rot').textContent.replace(/ \(.*\)/, '') + ':' + [...c.querySelectorAll('.mn-num')].map(n => n.textContent).join(' ')).join('|'));

export default async function (h) {
  /* ---------- tudo ligado: dados grandes e os dois tops ---------- */
  await h.cenario({ comMonitorApp: true, blocos: { monitor: true } });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'tocar na tecla do Monitor de Atividade abre a folha, sem esqueleto sobrando');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0, `a tecla abre a tela no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  h.ok(await p.evaluate(() => document.querySelector('#mn-titulo').textContent) === 'Monitor de Atividade', 'título "Monitor de Atividade"');
  h.ok(await cartoes(p) === 'Processador:12%|Memória:63%|Bateria:81%|Rede:1,2 MB/s 40 KB/s', `os quatro itens do bloco, grandes (${await cartoes(p)})`);
  h.ok(await nomes(p, 0) === 'Editor de Video|Navegador|WindowServer|Musica|Chat', `os 5 que mais usam o processador, do maior para o menor (${await nomes(p, 0)})`);
  h.ok(await nomes(p, 1) === 'Editor de Video|kernel_task|Navegador|Chat|Planilha', `os 5 que mais usam a memória (${await nomes(p, 1)})`);
  const valores = await p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-secao')].map(s => s.querySelector('.mn-valor').textContent).join('|'));
  h.ok(valores === '77,3%|3,0 GB', `valor do primeiro de cada lista: processador em %, memória em GB (${valores})`);
  const botoes = await p.evaluate(() => [...document.querySelectorAll('#mn-corpo .mn-secao')[0].querySelectorAll('.mn-proc')].map(l => !!l.querySelector('[data-mn-pedir]')).join(','));
  h.ok(botoes === 'true,true,false,true,true', `Encerrar só aparece onde o Mac diz que pode (WindowServer sem botão): ${botoes}`);
  await h.dormir(700); await h.foto(p, 'monitor-painel');

  /* ---------- confirmar antes de encerrar ---------- */
  await p.click('#mn-corpo .mn-secao >> nth=0 >> [data-pid="201"] [data-mn-pedir]');
  h.ok(await h.espera(p, () => /Encerrar Navegador\?/.test(document.querySelector('#mn-corpo .confirmando')?.textContent || '')), 'tocar em Encerrar pergunta antes, com o nome do programa');
  c = await h.contadores();
  h.ok(c.processos.every(x => x === 'ler'), `a pergunta ainda não mandou nada ao Mac (${c.processos.join(',')})`);
  await p.click('#mn-corpo [data-mn-cancelar]');
  h.ok(await p.evaluate(() => !document.querySelector('#mn-corpo .confirmando') && !!document.querySelector('[data-pid="201"] [data-mn-pedir]')), 'Cancelar volta a linha como estava');
  c = await h.contadores();
  h.ok(c.processos.every(x => x === 'ler'), 'Cancelar não encerra nada');
  // a pergunta aguenta a releitura de 3 s da lista
  await p.click('#mn-corpo .mn-secao >> nth=0 >> [data-pid="201"] [data-mn-pedir]');
  await h.dormir(3600);
  h.ok(await p.evaluate(() => !!document.querySelector('#mn-corpo .confirmando[data-pid="201"]')), 'a pergunta continua na tela enquanto a pessoa decide');
  await p.click('#mn-corpo [data-mn-sim]');
  h.ok(await h.ate(async () => (await h.contadores()).processos.includes('encerrar 201 Navegador')), 'Confirmar manda ao Mac o número e o nome do programa');
  h.ok(await h.espera(p, () => !document.querySelector('#mn-corpo [data-pid="201"]'), undefined, 6000), 'o programa encerrado sai das duas listas');
  h.ok(await nomes(p, 0) === 'Editor de Video|WindowServer|Musica|Chat|Planilha', `a lista do processador entra o próximo (${await nomes(p, 0)})`);
  // o dado do bloco acompanha o Mac com a folha aberta
  await h.cenario({ monitor: { cpu: 93, memoria: 63, bateria: 81, naTomada: false, baixa: 1258291, sobe: 40960 } });
  h.ok(await h.espera(p, () => document.querySelector('#mn-corpo .mn-cartao .mn-num').textContent.startsWith('93') && document.querySelector('#mn-corpo .mn-cartao').classList.contains('cheio'), undefined, 6000), 'o processador a 93% aparece grande e em alerta, sem fechar a folha');
  await p.click('#f-monitor [data-fechar]');
  h.ok(await h.espera(p, () => !document.querySelector('#f-monitor').classList.contains('aberta')), 'o X fecha a folha');
  await p.context().close();

  /* ---------- toque que não se perde quando o monitor muda no meio do toque ---------- */
  // Num Mac de verdade o processador e a rede mudam quase a cada segundo. Se a tela repintasse tudo no meio do toque, o botão
  // sumia antes de o dedo subir e o clique se perdia. Aqui o dedo desce, o Mac muda, a tela espera e o dedo sobe.
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  const botaoPedir = p.locator('#mn-corpo .mn-secao >> nth=0 >> [data-pid="201"] [data-mn-pedir]');
  await botaoPedir.scrollIntoViewIfNeeded();
  const alvo = await botaoPedir.boundingBox();
  await p.mouse.move(alvo.x + alvo.width / 2, alvo.y + alvo.height / 2); await p.mouse.down();
  await h.cenario({ monitor: { cpu: 55, memoria: 70, bateria: 80, naTomada: false, baixa: 2000000, sobe: 50000 } });
  h.ok(await h.espera(p, () => document.querySelector('#mn-corpo .mn-cartao .mn-num').textContent.startsWith('55'), undefined, 6000), 'com o dedo em cima, os cartões do monitor continuam andando');
  await h.dormir(1600);
  await p.mouse.up();
  h.ok(await h.espera(p, () => /Encerrar Navegador\?/.test(document.querySelector('#mn-corpo .confirmando')?.textContent || '')), 'o dedo desceu, o monitor mudou e subiu: o toque em Encerrar chega e abre a pergunta');
  await h.cenario({ monitor: { cpu: 20, memoria: 70, bateria: 80, naTomada: false, baixa: 2000000, sobe: 50000 } });
  await p.locator('#mn-corpo [data-mn-sim]').scrollIntoViewIfNeeded();
  const sim = await p.locator('#mn-corpo [data-mn-sim]').boundingBox();
  await p.mouse.move(sim.x + sim.width / 2, sim.y + sim.height / 2); await p.mouse.down();
  await h.cenario({ monitor: { cpu: 30, memoria: 70, bateria: 80, naTomada: false, baixa: 1, sobe: 1 } });
  await h.dormir(1600); await p.mouse.up();
  h.ok(await h.ate(async () => (await h.contadores()).processos.includes('encerrar 201 Navegador')), 'o mesmo vale para Encerrar da confirmação: o toque não se perde');
  await p.context().close();

  /* ---------- só os itens escolhidos nos Ajustes do Mac ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitorItens: { cpu: true, memoria: false, bateria: false, rede: true } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await cartoes(p) === 'Processador:12%|Rede:1,2 MB/s 40 KB/s', `item desligado nos Ajustes não aparece (${await cartoes(p)})`);
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, blocos: { monitor: true }, monitor: { cpu: 12, memoria: 63, baixa: 1, sobe: 1 } });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(!/Bateria/.test(await cartoes(p)), 'Mac sem bateria: o cartão da bateria some');
  await p.context().close();

  /* ---------- monitor desligado: avisa, e os processos aparecem mesmo assim ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(/O monitor está desligado/.test(await p.evaluate(() => document.querySelector('#mn-corpo').textContent)) && await cartoes(p) === '', 'bloco desligado: a tela diz onde ligar, sem cartão falso');
  h.ok(await nomes(p, 0) === 'Editor de Video|Navegador|WindowServer|Musica|Chat', 'os processos aparecem mesmo com o bloco desligado');
  await p.context().close();

  /* ---------- Mac antigo, erro e lista vazia ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, processos: 'antigo', blocos: { monitor: true } });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => document.querySelector('.tecla[data-id="monitor"]').click());
  h.ok(await h.espera(p, () => /Atualize o Deck no Mac/.test(document.querySelector('#mn-corpo').textContent)), 'Mac antigo (sem a rota): pede para atualizar o Deck, e os dados do bloco continuam');
  h.ok(await cartoes(p) !== '', 'mesmo sem a lista, os cartões do monitor aparecem');
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, processos: 'erro' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => document.querySelector('.tecla[data-id="monitor"]').click());
  h.ok(await h.espera(p, () => !!document.querySelector('#mn-corpo [data-mn-tentar]')), 'erro do Mac: "Tentar de novo" no lugar das listas');
  await h.cenario({ processos: 'normal' });
  await p.click('#mn-corpo [data-mn-tentar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#mn-corpo .mn-proc').length >= 10), 'Tentar de novo traz as listas');
  await p.context().close();

  await h.reset(); await h.cenario({ comMonitorApp: true, processos: 'vazio' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await p.evaluate(() => document.querySelectorAll('#mn-corpo .mn-nada').length) === 2, 'sem processo nenhum: cada lista diz que não há o que mostrar');
  await p.context().close();

  /* ---------- o Mac recusa: a tela mostra o motivo e volta ao normal ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, processos: 'recusa' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await p.click('#mn-corpo .mn-secao >> nth=0 >> [data-pid="204"] [data-mn-pedir]');
  await p.click('#mn-corpo [data-mn-sim]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro') && /não pode ser encerrado/.test(document.querySelector('#aviso-txt').textContent)), 'pedido recusado mostra o motivo do Mac');
  h.ok(await h.espera(p, () => !document.querySelector('#mn-corpo .confirmando') && !!document.querySelector('[data-pid="204"] [data-mn-pedir]')), 'depois da recusa a linha volta ao normal');
  await p.context().close();

  /* ---------- nome de programa com HTML não executa ---------- */
  await h.reset(); await h.cenario({ comMonitorApp: true, xss: true });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p); await h.dormir(300);
  h.ok(await p.evaluate(() => !window.__xss), 'nome de processo com HTML malicioso aparece como texto, sem executar');
  await p.context().close();

  /* ---------- a tecla vem do editor, como qualquer app ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const r = await p.evaluate(() => ({ painel: painelDe({ tipo: 'app', valor: 'Activity Monitor' }), comAcao: painelDe({ tipo: 'app', valor: 'Activity Monitor', acao: { id: 'x' } }) }));
  h.ok(r.painel === 'monitor' && r.comAcao === undefined, `a tecla de app "Activity Monitor" abre a tela do monitor, e com ação vai para o Mac (${JSON.stringify(r)})`);
  await p.context().close();
}
