// Avisos que chegam de fora (toast), valores de fora (tecla Valores) e GitHub (tecla GitHub, PRs e CI).
// O Mac de mentira faz o papel do Mac: o que o script mandou já vem no estado, e o gh já foi lido.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const agoraIso = (deslocMs = 0) => new Date(Date.now() + deslocMs).toISOString();
const aviso = p => p.evaluate(() => { const a = document.querySelector('#aviso'); return { visivel: a.classList.contains('visivel'), erro: a.classList.contains('erro'), txt: document.querySelector('#aviso-txt').textContent } });
const GH = {
  estado: 'ok', lidoEm: agoraIso(),
  revisar: [{ id: 'dono/app#12', titulo: 'Ajusta o login do painel', repo: 'dono/app', numero: 12 }, { id: 'dono/api#7', titulo: 'Corrige a fila de envio que travava quando o Mac dormia por muito tempo', repo: 'dono/api', numero: 7 }],
  falhando: [{ id: 'dono/app#30', titulo: 'Nova tela de ajustes', repo: 'dono/app', numero: 30 }],
};
const linhas = p => p.evaluate(() => [...document.querySelectorAll('#gh-corpo .gh-linha')].map(l => l.querySelector('b').textContent + '|' + l.querySelector('small').textContent).join(';'));
const abrirGh = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="github"]').click());
  return h.espera(p, () => document.querySelector('#f-github').classList.contains('aberta'));
};
const abrirVl = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="valores"]').click());
  return h.espera(p, () => document.querySelector('#f-valores').classList.contains('aberta'));
};

export default async function (h) {
  /* ---------- avisos de fora: toast uma vez por id ---------- */
  await h.cenario({ avisosDeFora: [] });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(!(await aviso(p)).visivel, 'sem aviso de fora, nenhum toast');
  await h.cenario({ avisosDeFora: [{ id: 1, titulo: 'Build pronto', texto: 'Passou em 2 min', nivel: 'ok', em: agoraIso() }] });
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel')), 'o aviso de fora aparece como toast');
  let a = await aviso(p);
  h.ok(a.txt === 'Build pronto. Passou em 2 min' && !a.erro, `o toast leva o título e o texto, sem estilo de erro (${a.txt})`);
  await h.foto(p, 'avisos-github-toast');
  h.ok(await p.evaluate(() => { const r = document.querySelector('#aviso').getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(); return r.left >= t.left && r.right <= t.right }), 'o toast cabe na tela');
  h.ok(await h.espera(p, () => !document.querySelector('#aviso').classList.contains('visivel'), undefined, 6000), 'o toast some sozinho');
  await h.dormir(2500); // vários estados depois, o mesmo id não volta
  h.ok(!(await aviso(p)).visivel, 'o mesmo aviso não aparece de novo a cada segundo');
  await h.cenario({ avisosDeFora: [{ id: 1, titulo: 'Build pronto', texto: 'Passou em 2 min', nivel: 'ok', em: agoraIso() }, { id: 2, titulo: 'Deploy falhou', texto: '', nivel: 'erro', em: agoraIso() }] });
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel') && document.querySelector('#aviso-txt').textContent === 'Deploy falhou'), 'só o aviso novo (id 2) aparece');
  h.ok((await aviso(p)).erro, 'nível erro usa o estilo de erro');
  await p.context().close();

  /* ---------- o Mac reiniciou: os ids voltam a contar e o aviso novo ainda aparece ---------- */
  await h.reset(); await h.cenario({});
  p = await h.pagina(); await pronta(h, p);
  await h.cenario({ avisosDeFora: [{ id: 5, titulo: 'Antes de reiniciar', texto: '', nivel: 'info', em: agoraIso() }] });
  await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Antes de reiniciar');
  await h.cenario({ avisosDeFora: [{ id: 1, titulo: 'Depois de reiniciar', texto: '', nivel: 'info', em: agoraIso() }] });
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Depois de reiniciar', undefined, 8000), 'depois de o Mac reiniciar (id 1 de novo), o aviso novo ainda vira toast');
  await p.context().close();

  /* ---------- aviso de fora não pisa no Desfazer de outra ação ---------- */
  await h.reset(); await h.cenario({});
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => avisar('Tecla excluída', { desfazer: () => {} }));
  await h.cenario({ avisosDeFora: [{ id: 1, titulo: 'Build pronto', texto: '', nivel: 'ok', em: agoraIso() }] });
  await h.dormir(2200);
  const emCima = await p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, desfazer: !document.querySelector('#aviso-acao').hidden }));
  h.ok(emCima.txt === 'Tecla excluída' && emCima.desfazer, `o aviso de fora espera e o Desfazer continua na tela (${JSON.stringify(emCima)})`);
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Build pronto', undefined, 9000), 'passada a janela do Desfazer, o aviso de fora aparece');
  await p.context().close();

  /* ---------- aviso velho não volta ao abrir a página ---------- */
  await h.reset(); await h.cenario({ avisosDeFora: [{ id: 5, titulo: 'De ontem', texto: '', nivel: 'info', em: agoraIso(-300000) }] });
  p = await h.pagina(); await pronta(h, p); await h.dormir(1500);
  h.ok(!(await aviso(p)).visivel, 'um aviso de 5 minutos atrás não é mostrado de novo ao abrir a página');
  await p.context().close();

  /* ---------- rajada: não empilha ---------- */
  await h.reset(); await h.cenario({});
  p = await h.pagina(); await pronta(h, p);
  await h.cenario({ avisosDeFora: [1, 2, 3, 4, 5].map(i => ({ id: i, titulo: 'Aviso ' + i, texto: '', nivel: 'info', em: agoraIso() })) });
  await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel'));
  h.ok((await aviso(p)).txt === 'Aviso 3', `numa rajada, só os 3 últimos entram na fila e o primeiro a aparecer é o 3º (${(await aviso(p)).txt})`);
  await p.context().close();

  /* ---------- texto de fora nunca vira HTML ---------- */
  await h.reset(); await h.cenario({ comValores: true, valoresDeFora: [{ chave: '<img src=x onerror="window.__xss=1">', valor: '<b>1</b>', em: agoraIso(), ate: agoraIso(600000) }] });
  p = await h.pagina(); await pronta(h, p);
  await h.cenario({ avisosDeFora: [{ id: 1, titulo: '<img src=x onerror="window.__xss=1">', texto: '<b>oi</b>', nivel: 'info', em: agoraIso() }] });
  await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel'));
  await abrirVl(h, p);
  h.ok(await p.evaluate(() => !window.__xss && !document.querySelector('#aviso img, #vl-corpo img, #vl-corpo b:not(.mt-valor)')), 'título, chave e valor de fora entram como texto, nunca como HTML');
  await p.context().close();

  /* ---------- valores: a tecla Valores ---------- */
  await h.reset();
  const vals = [{ chave: 'build', valor: 'ok', em: agoraIso(), ate: agoraIso(600000) }, { chave: 'fila', valor: '42', em: agoraIso(), ate: agoraIso(90000) }];
  await h.cenario({ comValores: true, valoresDeFora: vals });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="valores"] .selo')?.textContent) === '2', 'a tecla Valores mostra quantos valores há (2)');
  h.ok(await abrirVl(h, p), 'tocar na tecla abre a folha Valores');
  h.ok((await h.contadores()).botoes.length === 0, 'a tecla abre a tela no iPhone, sem mandar nada ao Mac');
  const cartoes = () => p.evaluate(() => [...document.querySelectorAll('#vl-corpo .mt-bloco')].map(c => c.querySelector('.mt-nome').textContent + '=' + c.querySelector('.mt-valor').textContent + ' (' + c.querySelector('.mt-sub').textContent + ')').join(';'));
  h.ok(await cartoes() === 'build=ok (vence em 10 min);fila=42 (vence em 2 min)', `um cartão por valor, com o prazo (${await cartoes()})`);
  await h.dormir(700); await h.foto(p, 'avisos-github-valores');
  await h.cenario({ valoresDeFora: [{ chave: 'build', valor: 'falhou', em: agoraIso(), ate: agoraIso(600000) }] });
  h.ok(await h.espera(p, () => document.querySelectorAll('#vl-corpo .mt-bloco').length === 1 && document.querySelector('#vl-corpo .mt-valor').textContent === 'falhou'), 'aberta, a folha acompanha: valor novo troca e o que venceu some');
  await h.cenario({ valoresDeFora: [] });
  h.ok(await h.espera(p, () => /Nenhum valor agora/.test(document.querySelector('#vl-corpo').textContent)), 'sem valores, a folha explica de onde eles vêm');
  await p.click('#f-valores [data-fechar]');
  h.ok(await h.espera(p, () => !document.querySelector('#f-valores').classList.contains('aberta')), 'o Fechar fecha a folha');
  h.ok(await p.evaluate(() => !document.querySelector('.tecla[data-id="valores"] .selo')), 'sem valores a tecla fica sem selo');
  await p.context().close();

  /* ---------- GitHub ---------- */
  await h.reset(); await h.cenario({ comGitHub: true, github: GH });
  p = await h.pagina(); await pronta(h, p);
  const abertas = []; p.on('popup', x => abertas.push(x.url()));
  const url0 = p.url();
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="github"] .selo')?.textContent) === '3', 'o selo da tecla GitHub é a soma dos dois grupos (3)');
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="github"] .selo').getAttribute('aria-label')) === '3 PRs pedindo atenção', 'o selo tem texto para leitor de tela');
  h.ok(await abrirGh(h, p), 'tocar na tecla abre a folha GitHub');
  h.ok((await h.contadores()).botoes.length === 0, 'a tecla abre a tela no iPhone, sem mandar nada ao Mac');
  const t = await p.evaluate(() => [...document.querySelectorAll('#gh-corpo .gh-grupo h3')].map(x => x.textContent).join('|'));
  h.ok(t === 'Esperando sua revisão2|CI falhando1', `os dois grupos, com a contagem (${t})`);
  h.ok(await linhas(p) === 'Ajusta o login do painel|dono/app #12;Corrige a fila de envio que travava quando o Mac dormia por muito tempo|dono/api #7;Nova tela de ajustes|dono/app #30', `a lista curta: título e repo com o número (${await linhas(p)})`);
  const caber = await p.evaluate(() => { const c = document.querySelector('#gh-corpo'), r = c.getBoundingClientRect(); return { sobra: [...c.querySelectorAll('.gh-linha')].filter(l => { const q = l.getBoundingClientRect(); return q.right > r.right + 1 || q.left < r.left - 1 }).length, lateral: c.scrollWidth > c.clientWidth + 1, alvo: Math.min(...[...c.querySelectorAll('.gh-linha')].map(l => l.getBoundingClientRect().height)) } });
  h.ok(caber.sobra === 0 && !caber.lateral, `título longo é cortado na linha, sem rolagem lateral (${JSON.stringify(caber)})`);
  h.ok(caber.alvo >= 36, `cada linha tem alvo de toque de pelo menos 36 px (${Math.round(caber.alvo)})`);
  h.ok((await h.contadores()).githubAbertos.length === 0 && abertas.length === 0, 'nada abre sozinho: só depois do toque');
  await h.dormir(700); await h.foto(p, 'avisos-github-github-deitado');
  await p.click('#gh-corpo .gh-linha');
  h.ok(await h.ate(async () => (await h.contadores()).githubAbertos.join() === 'dono/app#12'), 'tocar no PR pede ao Mac para abrir só esse PR');
  h.ok(await h.espera(p, () => document.querySelector('#aviso-txt').textContent === 'Abrindo o PR no navegador do Mac'), 'o iPhone confirma com um toast');
  h.ok(abertas.length === 0 && p.url() === url0, 'o iPhone nunca navega para o GitHub: quem abre é o navegador do Mac');
  h.ok(!(await p.evaluate(() => document.documentElement.outerHTML)).includes('github.com'), 'nenhum endereço do GitHub chega ao iPhone, só o id do PR');
  await p.context().close();

  /* ---------- GitHub: recusa do Mac, estados claros, em pé e janela ---------- */
  await h.reset(); await h.cenario({ comGitHub: true, github: GH, githubRecusa: 'O Mac não conseguiu abrir o PR no navegador.' });
  p = await h.pagina(); await pronta(h, p); await abrirGh(h, p);
  await p.click('#gh-corpo .gh-linha');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro') && /não conseguiu abrir/.test(document.querySelector('#aviso-txt').textContent)), 'se o Mac não abre o PR, o toast diz o motivo');
  await p.context().close();

  /* ---------- GitHub: contagem verdadeira acima de cinco ---------- */
  const muitos = n => Array.from({ length: 5 }, (_, i) => ({ id: `dono/app#${n + i}`, titulo: `PR ${n + i}`, repo: 'dono/app', numero: n + i }));
  await h.reset(); await h.cenario({ comGitHub: true, github: { estado: 'ok', lidoEm: agoraIso(), revisar: muitos(1), falhando: muitos(20), maisRevisar: 7, maisFalhando: 3 } });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => document.querySelector('.tecla[data-id="github"] .selo')?.textContent) === '20', 'o selo conta além da lista (12 + 8 = 20)');
  await abrirGh(h, p);
  const t2 = await p.evaluate(() => [...document.querySelectorAll('#gh-corpo .gh-grupo h3')].map(x => x.textContent).join('|') + '#' + [...document.querySelectorAll('#gh-corpo .gh-mais')].map(x => x.textContent).join('|') + '#' + document.querySelectorAll('#gh-corpo .gh-linha').length);
  h.ok(t2 === 'Esperando sua revisão12|CI falhando8#e mais 7 no GitHub|e mais 3 no GitHub#10', `a folha mostra 5 por grupo, a contagem real e quantos faltam (${t2})`);
  await h.dormir(700); await h.foto(p, 'avisos-github-github-mais');
  await p.context().close();

  for (const [rotulo, github, texto] of [
    ['lendo', null, /Lendo o GitHub/],
    ['sem-gh', { estado: 'sem-gh', aviso: 'O gh (a ferramenta do GitHub) não está instalado neste Mac. Instale com brew install gh e entre com gh auth login.' }, /O gh não está instalado[\s\S]*brew install gh/],
    ['sem-login', { estado: 'sem-login', aviso: 'O gh não está logado. No Terminal do Mac, rode gh auth login.' }, /O gh não está logado[\s\S]*gh auth login/],
    ['erro', { estado: 'erro', aviso: 'Não consegui ler o GitHub agora. Confira a internet e o gh auth status.' }, /Não deu para ler o GitHub/],
    ['tudo-em-dia', { estado: 'ok', revisar: [], falhando: [], lidoEm: agoraIso() }, /Tudo em dia/],
  ]) {
    await h.reset(); await h.cenario({ comGitHub: true, github });
    p = await h.pagina(); await pronta(h, p); await abrirGh(h, p);
    h.ok(await h.espera(p, t => new RegExp(t.fonte, t.flags).test(document.querySelector('#gh-corpo').textContent), { fonte: texto.source, flags: texto.flags }), `estado "${rotulo}": a folha diz o que está acontecendo`);
    h.ok(await p.evaluate(() => !document.querySelector('.tecla[data-id="github"] .selo') && !document.querySelector('#gh-corpo .gh-linha')), `estado "${rotulo}": sem selo e sem lista falsa`);
    if (rotulo === 'sem-gh') await h.foto(p, 'avisos-github-github-sem-gh');
    await p.context().close();
  }

  await h.reset(); await h.cenario({ comGitHub: true, github: GH });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p); await abrirGh(h, p);
  const pe = await p.evaluate(() => { const g = document.querySelector('#gh-corpo .gh-grupos'); return { col: getComputedStyle(g).gridTemplateColumns.split(' ').length, lateral: document.querySelector('#gh-corpo').scrollWidth > document.querySelector('#gh-corpo').clientWidth + 1 } });
  h.ok(pe.col === 1 && !pe.lateral, `em pé os grupos empilham em uma coluna e nada passa da tela (${JSON.stringify(pe)})`);
  await h.dormir(700); await h.foto(p, 'avisos-github-github-em-pe');
  await p.context().close();

  await h.reset(); await h.cenario({ comGitHub: true, comValores: true, github: GH, valoresDeFora: vals });
  p = await h.pagina({ w: 1440, h: 900 }); await pronta(h, p); await abrirGh(h, p);
  await h.dormir(700); await h.foto(p, 'avisos-github-github-janela');
  await p.click('#f-github [data-fechar]'); await h.dormir(500);
  await abrirVl(h, p); await h.dormir(700); await h.foto(p, 'avisos-github-valores-janela');
  await p.context().close();

  await h.reset(); await h.cenario({ comValores: true, valoresDeFora: vals });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p); await abrirVl(h, p);
  const vpe = await p.evaluate(() => { const g = document.querySelector('#vl-corpo .vl-grade'); return { col: getComputedStyle(g).gridTemplateColumns.split(' ').length, lateral: document.querySelector('#vl-corpo').scrollWidth > document.querySelector('#vl-corpo').clientWidth + 1 } });
  h.ok(vpe.col === 2 && !vpe.lateral, `em pé os valores ficam em duas colunas sem passar da tela (${JSON.stringify(vpe)})`);
  await h.dormir(700); await h.foto(p, 'avisos-github-valores-em-pe');
  await p.context().close();

  /* ---------- as teclas vêm do editor, como as outras de fábrica ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const r = await p.evaluate(() => ({
    gh: painelDe({ tipo: 'app', valor: 'Deck GitHub' }), vl: painelDe({ tipo: 'app', valor: 'Deck Valores' }), comAcao: painelDe({ tipo: 'app', valor: 'Deck GitHub', acao: { id: 'x' } }),
    reconhece: appDoMac('Deck GitHub')?.nome + '|' + appDoMac('Deck Valores')?.nome, iconeGh: SVG[GITHUB_DECK.telaDoDeck] !== undefined, iconeVl: SVG[VALORES_DECK.telaDoDeck] !== undefined,
  }));
  h.ok(r.gh === 'github' && r.vl === 'valores' && r.comAcao === undefined, `as teclas "Deck GitHub" e "Deck Valores" abrem as telas do iPhone (${JSON.stringify(r)})`);
  h.ok(r.reconhece === 'GitHub (PRs e CI)|Valores de fora' && r.iconeGh && r.iconeVl, 'o editor do iPhone reconhece as duas ao editar, com ícone (a lista de apps dele não muda)');
  await p.context().close();
}
