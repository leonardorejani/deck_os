// Modo organizar: segurar, arrastar, editor, excluir e desfazer, esconder blocos, perfil, e o Mac recusando.
// Tudo que muda grava a config inteira (PUT /api/config) e só vale depois do Mac aceitar.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const ordem = p => p.evaluate(() => [...document.querySelectorAll('.pagina .tecla:not(.menu)')].map(t => t.dataset.id));
const organizando = p => p.evaluate(() => document.querySelector('#tela').classList.contains('organizando'));
const gravadas = async h => (await h.contadores()).configsGravadas;
async function esperaGravadas(h, n, ms = 4000) {
  for (let t = 0; t < ms; t += 50) { if ((await gravadas(h)).length >= n) return true; await h.dormir(50) }
  return false;
}
const aviso = p => p.evaluate(() => { const a = document.querySelector('#aviso'); return { txt: document.querySelector('#aviso-txt').textContent, visivel: a.classList.contains('visivel'), erro: a.classList.contains('erro'), desfazer: !document.querySelector('#aviso-acao').hidden } });
const centro = async (p, sel) => { const b = await p.locator(sel).boundingBox(); return { x: b.x + b.width / 2, y: b.y + b.height / 2 } };
// as teclas tremem no modo organizar (o Playwright não clica em alvo se mexendo): toque pelo ponto
const tocar = async (p, sel) => { const c = await centro(p, sel); await p.mouse.click(c.x, c.y) };
// segura meio segundo numa tecla (e solta): entra no modo organizar
async function entrar(h, p, id = 'apagar') {
  const c = await centro(p, `.tecla[data-id="${id}"]`);
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await h.dormir(650); await p.mouse.up();
}
// arrasta uma tecla até a outra, passo a passo, como o dedo
async function arrastar(p, de, para) {
  const a = await centro(p, `.tecla[data-id="${de}"]`), b = await centro(p, `.tecla[data-id="${para}"]`);
  await p.mouse.move(a.x, a.y); await p.mouse.down();
  for (let i = 1; i <= 12; i++) { await p.mouse.move(a.x + (b.x - a.x) * i / 12, a.y + (b.y - a.y) * i / 12); await p.waitForTimeout(20) }
  await p.mouse.up();
}
const cfgOk = (c, msg, h) => h.ok(c.versao === 1 && c.comp === 'a' && c.nomeMac === 'MacBook Pro de Teste' && c.contas.length === 3 && c.porta === 4777 && c.perfilAtivo === 'trabalho' && !('codigoAcesso' in c), `${msg}: a config vai inteira (versão, composição, contas, nome do Mac, porta)`);

export default async function (h) {
  /* segurar 500 ms entra no modo organizar, e tocar rápido continua executando */
  let p = await h.pagina();
  h.ok(await pronta(h, p), 'painel pronto');
  let c = await centro(p, '.tecla[data-id="apagar"]');
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await h.dormir(300);
  h.ok(!(await organizando(p)), 'segurando 300 ms ainda não entra');
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="apagar"]').classList.contains('segurando')), 'a tecla afunda enquanto segura');
  await h.dormir(350);
  h.ok(await organizando(p), 'segurando 650 ms entra no modo organizar');
  await p.mouse.up(); await h.dormir(100);
  let v = await p.evaluate(() => ({ barra: getComputedStyle(document.querySelector('.barra-organizar')).opacity, lapis: getComputedStyle(document.querySelector('.tecla .editar')).display, menos: document.querySelectorAll('.esconder-bloco').length, txt: document.querySelector('.barra-organizar').textContent.replace(/\s+/g, ' ').trim() }));
  h.ok(Number(v.barra) > .95 && v.lapis !== 'none' && v.menos === 3, `a barra, os lápis e os "−" dos 3 blocos aparecem (${v.txt})`);
  h.ok((await h.contadores()).botoes.length === 0, 'segurar não executa a tecla');
  await h.foto(p, 'organizar-horizontal');
  await p.keyboard.press('Escape'); await h.dormir(150);
  h.ok(!(await organizando(p)), 'Esc sai do modo organizar');
  await tocar(p, '.tecla[data-id="apagar"]'); await h.dormir(400);
  h.ok((await h.contadores()).botoes.join() === 'apagar' && !(await organizando(p)), 'toque rápido continua executando a tecla');
  c = await centro(p, '.tecla[data-id="apagar"]');
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await p.mouse.move(c.x + 40, c.y + 30, { steps: 4 }); await h.dormir(650); await p.mouse.up();
  h.ok(!(await organizando(p)), 'mexer o dedo antes de 500 ms cancela o segurar');
  await p.context().close();

  /* arrastar muda a ordem na hora e grava a config inteira. Segurar e já arrastar, no mesmo gesto */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  c = await centro(p, '.tecla[data-id="apagar"]');
  const alvo = await centro(p, '.tecla[data-id="acordado"]');
  await p.mouse.move(c.x, c.y); await p.mouse.down(); await h.dormir(650);
  for (let i = 1; i <= 12; i++) { await p.mouse.move(c.x + (alvo.x - c.x) * i / 12, c.y + (alvo.y - c.y) * i / 12); await p.waitForTimeout(20) }
  h.ok(await p.evaluate(() => !!document.querySelector('.fantasma')), 'arrastando aparece a tecla fantasma');
  h.ok((await ordem(p)).join() === 'apagar,acordado,whatsapp,calendario', `as outras abrem espaço na hora (${(await ordem(p)).join()})`);
  await h.foto(p, 'organizar-arrastando');
  await p.mouse.up();
  h.ok(await esperaGravadas(h, 1), 'soltar grava no Mac');
  let g = await gravadas(h);
  h.ok(g.length === 1 && g[0].perfis[0].teclas.map(t => t.id).join() === 'apagar,acordado,whatsapp,calendario', `a ordem nova vai no PUT (${g[0]?.perfis[0].teclas.map(t => t.id).join()})`);
  cfgOk(g[0], 'arrastar', h);
  h.ok(g[0].perfis[0].teclas.find(t => t.id === 'acordado').estado?.includes('pmset'), 'os outros campos da tecla (estado) seguem intactos');
  await h.dormir(2600); // o laço e a releitura da config não desfazem a ordem
  h.ok((await ordem(p)).join() === 'apagar,acordado,whatsapp,calendario', 'a ordem nova continua depois do laço reler o Mac');
  h.ok(await p.evaluate(() => !document.querySelector('.fantasma')), 'o fantasma some ao soltar');
  await p.context().close();

  /* só sai do modo organizar depois do Mac aceitar */
  await h.reset(); await h.cenario({ atrasoGravar: 900 });
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p); await arrastar(p, 'apagar', 'acordado');
  await p.click('#b-pronto'); await h.dormir(350);
  h.ok(await organizando(p), 'Pronto com o Mac ainda respondendo: continua no modo organizar');
  h.ok(await h.espera(p, () => !document.querySelector('#tela').classList.contains('organizando'), null, 4000), 'sai quando o Mac aceita');
  h.ok((await gravadas(h)).length === 1, 'uma gravação só');
  await p.context().close();

  /* editor: tocar na tecla abre, Salvar grava, Cancelar descarta */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await tocar(p, '.tecla[data-id="apagar"]');
  h.ok(await h.espera(p, () => document.querySelector('#f-editor').classList.contains('aberta')), 'tocar numa tecla no modo organizar abre o editor');
  h.ok(await p.evaluate(() => document.querySelector('#tela').scrollTop === 0), 'abrir o editor não desloca a tela');
  v = await p.evaluate(() => ({ titulo: document.querySelector('#ed-titulo').textContent, nome: document.querySelector('#ed-nome').value, valor: document.querySelector('#ed-valor')?.value, tipo: document.querySelector('#ed-tipo [aria-pressed="true"]')?.textContent, excluir: !document.querySelector('#ed-excluir').hidden }));
  h.ok(v.titulo === 'Editar tecla' && v.nome === 'Apagar tela' && v.valor === 'pmset displaysleepnow' && v.tipo === 'Comando' && v.excluir, `o editor traz a tecla (${JSON.stringify(v)})`);
  await h.dormir(600); await h.foto(p, 'editor-horizontal');
  await p.fill('#ed-nome', 'Apagar a tela'); await p.click('#f-editor [data-fechar].btn');
  await h.dormir(500);
  h.ok((await gravadas(h)).length === 0 && !(await p.evaluate(() => document.querySelector('#f-editor').classList.contains('aberta'))), 'Cancelar fecha sem gravar');
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="apagar"] .nome').textContent) === 'Apagar tela', 'e o nome da tecla não mudou');
  await tocar(p, '.tecla[data-id="apagar"]');
  await p.fill('#ed-nome', 'Apagar a tela'); await p.fill('#ed-valor', 'pmset displaysleepnow ; echo oi');
  await p.click('#ed-salvar');
  h.ok(await esperaGravadas(h, 1), 'Salvar grava no Mac');
  g = await gravadas(h);
  const sal = g[0]?.perfis[0].teclas.find(t => t.id === 'apagar');
  h.ok(sal?.nome === 'Apagar a tela' && sal.valor === 'pmset displaysleepnow ; echo oi' && sal.tipo === 'comando' && sal.icone === 'svg:tela' && g[0].perfis[0].teclas.length === 4, `a tecla editada vai na config com o resto dela (${JSON.stringify(sal)})`);
  cfgOk(g[0], 'editar', h);
  h.ok(await h.espera(p, () => !document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('.tecla[data-id="apagar"] .nome').textContent === 'Apagar a tela'), 'o editor fecha e a tecla mostra o nome novo');
  h.ok((await aviso(p)).txt === 'Tecla salva', 'aviso "Tecla salva"');
  // sem nome e sem ação: não vai para o Mac
  await tocar(p, '.tecla[data-id="apagar"]'); await p.fill('#ed-nome', '   '); await p.click('#ed-salvar');
  v = await aviso(p);
  h.ok(v.txt === 'Dê um nome para a tecla' && v.erro && (await gravadas(h)).length === 1, 'nome em branco avisa e não grava');
  await p.click('#f-editor [data-fechar].btn'); await h.dormir(400);
  // tecla nova: escolhe o app, o nome vem do app

  await tocar(p, '.tecla.menu'); await h.dormir(300);
  h.ok(await p.evaluate(() => document.querySelector('#ed-titulo').textContent === 'Nova tecla' && document.querySelector('#ed-excluir').hidden), 'Nova abre o editor vazio, sem Excluir');
  await p.click('#ed-acao [data-app="Safari"]');
  h.ok(await p.inputValue('#ed-nome') === 'Safari', 'escolher o app preenche o nome');
  await p.click('#ed-salvar');
  h.ok(await esperaGravadas(h, 2), 'tecla nova grava');
  g = await gravadas(h); const nv = g[1]?.perfis[0].teclas;
  h.ok(nv?.length === 5 && nv[4].nome === 'Safari' && nv[4].tipo === 'app' && nv[4].valor === 'Safari' && nv[4].icone === 'Safari' && nv[4].id && nv.filter(t => t.id === nv[4].id).length === 1, `entra no fim com id próprio (${JSON.stringify(nv?.[4])})`);
  h.ok(await h.espera(p, () => document.querySelectorAll('.pagina .tecla:not(.menu)').length === 5), 'a tecla nova aparece no painel');
  await p.context().close();

  /* excluir oferece Desfazer por 5 s */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await tocar(p, '.tecla[data-id="whatsapp"]'); await p.click('#ed-excluir');
  h.ok(await esperaGravadas(h, 1), 'Excluir grava no Mac');
  g = await gravadas(h);
  h.ok(g[0]?.perfis[0].teclas.map(t => t.id).join() === 'acordado,calendario,apagar', `a tecla sai da config (${g[0]?.perfis[0].teclas.map(t => t.id).join()})`);
  h.ok(await h.espera(p, () => !document.querySelector('.tecla[data-id="whatsapp"]') && !document.querySelector('#f-editor').classList.contains('aberta')), 'a tecla some e o editor fecha');
  v = await aviso(p);
  h.ok(v.visivel && v.desfazer && v.txt === '"WhatsApp" excluída', `aviso com Desfazer (${v.txt})`);
  await h.foto(p, 'excluida-desfazer');
  await h.dormir(3900);
  h.ok((await aviso(p)).visivel, 'o Desfazer segue ali aos 4 s');
  await h.dormir(1300);
  h.ok(!(await aviso(p)).visivel, 'o Desfazer some aos 5 s');
  await p.context().close();

  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await tocar(p, '.tecla[data-id="whatsapp"]'); await p.click('#ed-excluir');
  await esperaGravadas(h, 1); await h.espera(p, () => !document.querySelector('.tecla[data-id="whatsapp"]'));
  await p.click('#aviso-acao');
  h.ok(await esperaGravadas(h, 2), 'Desfazer grava no Mac');
  g = await gravadas(h);
  h.ok(g[1]?.perfis[0].teclas.map(t => t.id).join() === 'acordado,whatsapp,calendario,apagar', `a tecla volta no mesmo lugar (${g[1]?.perfis[0].teclas.map(t => t.id).join()})`);
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="whatsapp"]')) && (await ordem(p)).join() === 'acordado,whatsapp,calendario,apagar', 'e volta no painel');
  await p.context().close();

  /* esconder e mostrar blocos grava blocos */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  for (const [b, sel] of [['uso', '.cartao.uso'], ['sessoes', '.cartao.sessoes'], ['spotify', '.cartao.player']]) {
    // clique do DOM, sem coordenada: o bloco anterior some e o layout desloca o alvo, e um clique por coordenada cai fora e sai do organizar.
    // Achar o "−" e clicar tem que ser um passo só dentro da página: o laço do Mac repinta os cartões a qualquer momento, e um
    // clique num "−" que já foi trocado por outro não faz nada (com a máquina ocupada isso derrubava este teste de vez em quando).
    // Se o bloco não sumiu, acha de novo e clica de novo (o "−" de um bloco já escondido não existe, então não duplica).
    const sumiu = ([b, s]) => b === 'spotify' ? !!document.querySelector('.sem-musica') : !document.querySelector(s);
    let escondeu = false;
    for (let t = 0; t < 40 && !escondeu; t++) {
      await p.evaluate(([b, s]) => document.querySelector(`${s} [data-esconder="${b}"]`)?.click(), [b, sel]);
      escondeu = await h.espera(p, sumiu, [b, sel], 250);
    }
    h.ok(escondeu, `"−" esconde o bloco ${b}`);
  }
  h.ok(await p.evaluate(() => document.querySelector('.organizando') !== null), 'esconder os três blocos não tira do modo organizar');
  h.ok(await esperaGravadas(h, 3), 'cada bloco escondido grava');
  g = await gravadas(h);
  h.ok(g[2]?.blocos.uso === false && g[2].blocos.sessoes === false && g[2].blocos.spotify === false && g[2].blocos.agenda === true && g[2].blocos.whatsapp === true, `blocos na config (${JSON.stringify(g[2]?.blocos)})`);
  cfgOk(g[2], 'esconder', h);
  v = await p.evaluate(() => [...document.querySelectorAll('#escondidos .chip-volta')].map(b => b.textContent));
  h.ok(v.join() === 'Spotify,Sessões,Uso das IAs', `os escondidos ficam na barra para voltar (${v.join()})`);
  await h.foto(p, 'organizar-escondidos');
  await p.click('#escondidos [data-mostrar="uso"]');
  h.ok(await h.espera(p, () => !!document.querySelector('.cartao.uso')), 'o "+" traz o bloco de volta');
  h.ok(await esperaGravadas(h, 4) && (await gravadas(h))[3].blocos.uso === true && (await gravadas(h))[3].blocos.spotify === false, 'e grava blocos.uso = true');
  await h.dormir(2300); // o laço não traz de volta o que o Mac já aceitou esconder
  h.ok(await p.evaluate(() => !!document.querySelector('.sem-musica') && !!document.querySelector('.cartao.uso')), 'depois do laço o painel segue como o Mac guardou');
  await p.context().close();

  /* trocar perfil grava perfilAtivo com a config inteira */
  await h.reset(); await h.cenario({ perfis: 'dois' });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla.menu'); await p.click('#lista-perfis [data-perfil="ensaio"]');
  h.ok(await esperaGravadas(h, 1), 'trocar perfil grava no Mac');
  g = await gravadas(h);
  h.ok(g[0].perfilAtivo === 'ensaio' && g[0].perfis.length === 2 && g[0].perfis[0].teclas.length === 4 && g[0].perfis[1].teclas.length === 5 && g[0].blocos.uso === true && g[0].nomeMac === 'MacBook Pro de Teste', 'perfilAtivo "ensaio" e os dois perfis inteiros');
  h.ok(await h.espera(p, () => !!document.querySelector('.tecla[data-id="e-spotify"]') && !document.querySelector('.tecla[data-id="acordado"]')), 'a tela mostra o perfil novo');
  // organizar no perfil novo mexe só nas teclas dele
  await entrar(h, p, 'e-agenda'); await arrastar(p, 'e-terminal', 'e-spotify');
  await esperaGravadas(h, 2); g = await gravadas(h);
  h.ok(g[1].perfilAtivo === 'ensaio' && g[1].perfis[1].teclas[0].id === 'e-terminal' && g[1].perfis[0].teclas.map(t => t.id).join() === 'acordado,whatsapp,calendario,apagar', 'reordenar no Ensaio não mexe nas teclas do Trabalho');
  await p.context().close();

  /* o Mac recusa: o motivo vai para o aviso e a tela volta ao que estava */
  const MOTIVO = 'Tecla não reconhecida em "Apagar tela": xyz';
  await h.reset(); await h.cenario({ rejeitar: MOTIVO });
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await arrastar(p, 'apagar', 'acordado');
  h.ok(await esperaGravadas(h, 1), 'o arrasto chega ao Mac');
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent.includes('xyz')), 'o motivo do Mac aparece no aviso');
  v = await aviso(p);
  h.ok(v.erro && v.txt === MOTIVO, `aviso de erro com o texto do Mac (${v.txt})`);
  h.ok(await h.espera(p, () => [...document.querySelectorAll('.pagina .tecla:not(.menu)')].map(t => t.dataset.id).join() === 'acordado,whatsapp,calendario,apagar'), 'a ordem volta ao que estava');
  h.ok(await organizando(p), 'continua no modo organizar');
  await h.foto(p, 'erro-do-mac');
  // esconder: volta
  await p.click('.cartao.uso [data-esconder="uso"]', { force: true });
  h.ok(await esperaGravadas(h, 2) && await h.espera(p, () => !!document.querySelector('.cartao.uso') && !document.querySelector('#escondidos .chip-volta')), 'bloco escondido que o Mac recusou volta para a tela');
  // editor: salvar recusado deixa o editor aberto e a tecla como era
  await tocar(p, '.tecla[data-id="apagar"]'); await p.fill('#ed-nome', 'Outro nome'); await p.click('#ed-salvar');
  h.ok(await esperaGravadas(h, 3) && await h.espera(p, () => document.querySelector('#aviso-txt').textContent.includes('xyz')), 'salvar recusado mostra o motivo');
  h.ok(await p.evaluate(() => document.querySelector('#f-editor').classList.contains('aberta') && document.querySelector('#ed-nome').value === 'Outro nome' && document.querySelector('.tecla[data-id="apagar"] .nome').textContent === 'Apagar tela'), 'o editor fica aberto com o que a pessoa digitou e a tecla segue como era');
  // excluir recusado: a tecla fica
  await p.click('#ed-excluir');
  h.ok(await esperaGravadas(h, 4), 'excluir chega ao Mac');
  await h.dormir(400);
  h.ok(await p.evaluate(() => !!document.querySelector('.tecla[data-id="apagar"]') && document.querySelector('#f-editor').classList.contains('aberta')), 'excluir recusado não tira a tecla');
  // Pronto: com tudo já resolvido, sai
  await p.click('#f-editor [data-fechar].btn'); await h.dormir(400);
  await p.click('#b-pronto'); await h.dormir(300);
  h.ok(!(await organizando(p)), 'Pronto sem nada a caminho sai do modo organizar');
  await p.context().close();

  // Pronto com uma gravação a caminho que o Mac recusa: fica no modo organizar
  await h.reset(); await h.cenario({ rejeitar: MOTIVO, atrasoGravar: 700 });
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario'); await arrastar(p, 'apagar', 'acordado');
  await p.click('#b-pronto'); await h.dormir(1500);
  h.ok(await organizando(p) && (await aviso(p)).txt === MOTIVO, 'Pronto durante uma gravação recusada: não sai, o aviso fica para a pessoa ver');
  await p.context().close();

  /* Mac fora do ar na hora de gravar: aviso de conexão e a tela volta */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  await entrar(h, p, 'calendario');
  await h.cenario({ mac: 'off' });
  await p.click('.cartao.uso [data-esconder="uso"]', { force: true });
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent.includes('Mac')), 'sem o Mac: avisa');
  h.ok(await h.espera(p, () => !!document.querySelector('.cartao.uso')), 'e o bloco continua na tela');
  await p.context().close();

  /* em pé (430 x 932) */
  await h.reset();
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p);
  await entrar(h, p, 'calendario');
  h.ok(await organizando(p), 'em pé: segurar entra no modo organizar');
  await h.foto(p, 'organizar-vertical');
  await tocar(p, '.tecla[data-id="apagar"]');
  await h.espera(p, () => document.querySelector('#f-editor').classList.contains('aberta'));
  await h.dormir(500);
  await h.foto(p, 'editor-vertical');
  v = await p.evaluate(() => { const f = document.querySelector('#f-editor').getBoundingClientRect(); return { ok: f.left >= 0 && f.right <= innerWidth + 1 && f.top >= 0 && f.bottom <= innerHeight + 1 } });
  h.ok(v.ok, 'em pé: o editor cabe na tela');
  await p.context().close();
}
