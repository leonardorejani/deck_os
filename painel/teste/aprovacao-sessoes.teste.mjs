// 19/11/2026: aprovar pedidos de permissão do Claude Code no iPhone (Permitir e Negar), e as sessões que não esperam
// (trabalhando, paradas) como um resumo no bloco e a lista completa na folha. Fotos só com DECK_FOTOS_REFINOS=<pasta>.
import path from 'node:path';

const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const PEDIDO = { id: 'ab12cd34ef56', projeto: 'deck', ferramenta: 'Bash', titulo: 'Rodar um comando', resumo: 'npm run test -- --filter sessoes && git status', segundos: 90 };
const OUTRAS = [
  { id: 'o1', nome: 'melhorias do painel', projeto: 'deck', situacao: 'trabalhando', passo: 'rodando os testes de tela' },
  { id: 'o2', nome: 'gravacao da reuniao', projeto: 'fm_live', situacao: 'trabalhando', passo: 'dois agentes rodando, esperando o primeiro' },
  { id: 'o3', nome: 'testes na vps', projeto: 'kletos', situacao: 'parada' },
];
const foto = async (p, nome) => { const d = process.env.DECK_FOTOS_REFINOS; if (d) await p.screenshot({ path: path.join(d, `aprovacao-sessoes-${nome}.png`) }) };
const visivel = (p, sel) => p.evaluate(s => { const e = document.querySelector(s); return !!e && !e.hidden && getComputedStyle(e).display !== 'none' }, sel);

export default async function (h) {
  // ---------- pedido de permissão ----------
  await h.cenario({ aprovacoes: [] });
  let p = await h.pagina(); await pronta(h, p); await h.dormir(300);
  h.ok(!(await visivel(p, '#aprovacao')), 'sem pedido, o cartão de aprovação não aparece');

  await h.cenario({ aprovacoes: [{ ...PEDIDO }] });
  h.ok(await h.espera(p, () => !document.querySelector('#aprovacao').hidden), 'o pedido do Claude Code aparece no iPhone');
  let t = await p.evaluate(() => ({ titulo: document.querySelector('#ap-titulo').textContent, projeto: document.querySelector('.ap-projeto')?.textContent, resumo: document.querySelector('.ap-resumo')?.textContent, tempo: document.querySelector('.ap-tempo').textContent, botoes: [...document.querySelectorAll('[data-ap]')].map(b => [b.textContent.trim(), b.dataset.ap]) }));
  h.ok(t.titulo === 'Rodar um comando' && t.projeto === 'deck' && t.resumo.includes('npm run test'), `mostra o que ele quer fazer e o projeto (${t.titulo}, ${t.projeto})`);
  h.ok(/^1:[23]\d$|^1:[01]\d$|^0:[5-9]\d$/.test(t.tempo), `mostra o tempo que resta (${t.tempo})`);
  h.ok(JSON.stringify(t.botoes) === JSON.stringify([['Negar', 'deny'], ['Permitir', 'allow']]), 'tem Negar e Permitir');
  const toque = await p.evaluate(() => [...document.querySelectorAll('[data-ap]')].map(b => { const r = b.getBoundingClientRect(), k = document.querySelector('.moldura').getBoundingClientRect().width / 932 || 1; return { alt: r.height / k, ok: document.elementFromPoint((r.left + r.right) / 2, r.top + 1)?.closest('[data-ap]') === b } }));
  h.ok(toque.every(x => x.alt >= 43.5 && x.ok), `os dois botões têm 44 pt de altura (${toque.map(x => Math.round(x.alt))})`);
  await foto(p, 'pedido-deitado');
  await p.click('[data-ap="allow"]');
  h.ok(await h.espera(p, () => document.querySelector('#aprovacao').hidden), 'Permitir fecha o cartão na hora');
  h.ok(await h.ate(async () => (await h.contadores()).aprovacoes.length === 1), 'o Mac recebeu a resposta');
  let c = (await h.contadores()).aprovacoes;
  h.ok(c[0]?.id === PEDIDO.id && c[0]?.decisao === 'allow', `a decisão foi allow (${JSON.stringify(c)})`);
  await h.dormir(1300);
  h.ok(await p.evaluate(() => document.querySelector('#aprovacao').hidden), 'depois do estado seguinte o cartão continua fechado');

  // Negar
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'neg1' }] });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  await p.click('[data-ap="deny"]');
  h.ok(await h.ate(async () => (await h.contadores()).aprovacoes.length === 2), 'Negar também chega no Mac');
  c = (await h.contadores()).aprovacoes;
  h.ok(c[1]?.decisao === 'deny', 'a decisão foi deny');

  // o terminal respondeu antes: o Mac deixa de mandar o pedido e ele some do iPhone
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'term1' }] });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  await h.cenario({ aprovacoes: [] });
  h.ok(await h.espera(p, () => document.querySelector('#aprovacao').hidden, null, 4000), 'se o terminal responde antes, o pedido some do iPhone');

  // prazo: o tempo chega a zero e o cartão sai sozinho (o Mac também deixa de mandar)
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'prazo1', segundos: 2 }] });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  h.ok(await h.espera(p, () => document.querySelector('#aprovacao').hidden, null, 5000), 'pedido que vence sai da tela sozinho');

  // dois pedidos: um de cada vez
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'um', titulo: 'Rodar um comando' }, { ...PEDIDO, id: 'dois', titulo: 'Editar um arquivo', resumo: '/a/b/c.swift' }] });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  h.ok(await p.evaluate(() => document.querySelector('.ap-n')?.textContent === '1 de 2' && document.querySelector('#ap-titulo').textContent === 'Rodar um comando'), 'com dois pedidos mostra o primeiro e "1 de 2"');
  await p.click('[data-ap="allow"]');
  h.ok(await h.espera(p, () => document.querySelector('#ap-titulo')?.textContent === 'Editar um arquivo' && !document.querySelector('.ap-n')), 'responder o primeiro traz o segundo');
  await p.click('[data-ap="deny"]');
  h.ok(await h.espera(p, () => document.querySelector('#aprovacao').hidden), 'responder o último fecha o cartão');
  await h.cenario({ aprovacoes: [] });

  // pedido que já venceu quando a resposta chega (404): avisa, não trava
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'venc' }], aprovacaoVencida: true });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  await p.click('[data-ap="allow"]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel') && /já foi respondido ou venceu/.test(document.querySelector('#aviso-txt').textContent)), 'resposta a pedido vencido avisa que ele já foi respondido ou venceu');
  await h.cenario({ aprovacoes: [], aprovacaoVencida: false });
  await h.dormir(1200);

  // erro do Mac (500): o pedido não fica perdido, volta no próximo estado
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'falha' }], aprovacaoFalha: true });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  await p.click('[data-ap="allow"]');
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro')), 'falha ao responder mostra o erro');
  h.ok(await h.espera(p, () => !document.querySelector('#aprovacao').hidden, null, 4000), 'e o pedido volta, para tentar de novo');
  await h.cenario({ aprovacoes: [], aprovacaoFalha: false });
  await p.context().close();

  // o cartão mostra o comando inteiro: nada de cortar as linhas de baixo (verificação 19/11/2026)
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'multi', resumo: 'echo a\necho b\necho c\necho d\necho e\nrm -rf ~/algo' }] });
  p = await h.pagina(); await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  t = await p.evaluate(() => { const e = document.querySelector('.ap-resumo'); return { cortado: e.scrollHeight > e.clientHeight + 1, clamp: getComputedStyle(e).webkitLineClamp, texto: e.textContent }; });
  h.ok(!t.cortado && t.clamp === 'none' && t.texto.endsWith('rm -rf ~/algo'), `um comando de várias linhas aparece inteiro, até a última (${t.clamp})`);

  // texto que vem do Claude Code nunca vira HTML
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'xss', resumo: '"><img src=x onerror="window.__xss=1">', projeto: '<b>x</b>' }] });
  p = await h.pagina(); await h.espera(p, () => !document.querySelector('#aprovacao').hidden);
  h.ok(await p.evaluate(() => !window.__xss && !document.querySelector('.ap-resumo img') && document.querySelector('.ap-projeto').textContent === '<b>x</b>'), 'o texto do pedido é escapado');
  await h.cenario({ aprovacoes: [] });
  await p.context().close();

  // vibração no app nativo: window.DeckCanal.vibrar é chamado uma vez por pedido novo
  await h.cenario({ aprovacoes: [] });
  p = await h.pagina({ antes: () => { window.__vib = 0; Object.defineProperty(window, '__canalVib', { value: true }) } });
  await pronta(h, p);
  await p.evaluate(() => { canal.vibrar = () => { window.__vib++ } });
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'vib1' }] });
  await h.espera(p, () => !document.querySelector('#aprovacao').hidden); await h.dormir(2500);
  h.ok(await p.evaluate(() => window.__vib === 1), 'o app nativo vibra uma vez por pedido novo, e não a cada estado');
  await h.cenario({ aprovacoes: [{ ...PEDIDO, id: 'vib1' }, { ...PEDIDO, id: 'vib2' }] }); await h.dormir(1500);
  h.ok(await p.evaluate(() => window.__vib === 2), 'um segundo pedido vibra de novo');
  await h.cenario({ aprovacoes: [] });
  await p.context().close();

  // ---------- sessões que não esperam ----------
  await h.reset(); await h.cenario({ sessoes: 2, outrasSessoes: OUTRAS });
  p = await h.pagina(); await pronta(h, p); await h.dormir(300);
  t = await p.evaluate(() => ({ resumo: document.querySelector('.sessoes .outras')?.textContent, conta: document.querySelector('.sessoes .conta')?.textContent, linhas: document.querySelectorAll('.sessoes .sessao').length, aria: document.querySelector('.sessoes').getAttribute('aria-label') }));
  h.ok(t.resumo === '2 trabalhando, 1 parada', `o bloco mostra só um resumo das outras (${t.resumo})`);
  h.ok(t.conta === '2' && /esperando: 2, 2 trabalhando/.test(t.aria), `as que esperam continuam primeiro e contadas (${t.conta})`);
  h.ok(await p.evaluate(() => !/melhorias do painel|rodando os testes/.test(document.querySelector('.sessoes').textContent)), 'o bloco não lista as outras uma por uma');
  await foto(p, 'bloco-deitado');
  await p.evaluate(() => abrirSessoes());
  h.ok(await h.espera(p, () => document.querySelectorAll('#se-lista .linha-sessao').length === 3), 'a tela de sessões lista as outras');
  t = await p.evaluate(() => ({ cartoes: document.querySelectorAll('#se-lista .cartao-sessao').length, titulo: document.querySelector('#se-titulo').textContent, linhas: [...document.querySelectorAll('#se-lista .linha-sessao')].map(l => [l.querySelector('b').textContent, l.querySelector('.estado-sessao').textContent, l.querySelector('p')?.textContent || '']) }));
  h.ok(t.cartoes === 2 && /Sessões esperando/.test(t.titulo), 'os cartões das que esperam vêm primeiro e o título segue igual');
  h.ok(t.linhas[0][1] === 'Trabalhando' && t.linhas[0][2] === 'rodando os testes de tela' && t.linhas[2][1] === 'Parada' && t.linhas[2][2] === '', `cada outra mostra estado e último passo (${JSON.stringify(t.linhas)})`);
  await h.dormir(500); await foto(p, 'folha-deitado');
  await p.context().close();

  // ninguém espera, mas há trabalho: o vazio de sempre mais o resumo
  await h.cenario({ sessoes: 0 });
  p = await h.pagina(); await pronta(h, p);
  t = await p.evaluate(() => ({ vazio: document.querySelector('.sessoes .vazio-rico strong')?.textContent, resumo: document.querySelector('.sessoes .outras')?.textContent, conta: !!document.querySelector('.sessoes .conta') }));
  h.ok(t.vazio === 'Tudo respondido' && t.resumo === '2 trabalhando, 1 parada' && !t.conta, 'sem ninguém esperando o bloco diz "Tudo respondido" e ainda resume as outras');
  await p.evaluate(() => abrirSessoes());
  h.ok(await h.espera(p, () => document.querySelectorAll('#se-lista .linha-sessao').length === 3 && !!document.querySelector('#se-lista .vazio-bloco')), 'na folha, o vazio e as outras aparecem juntos');
  h.ok(await p.evaluate(() => { const l = document.querySelector('#se-lista .linha-sessao').getBoundingClientRect(), f = document.querySelector('#f-sessoes').getBoundingClientRect(); return l.top < f.bottom }), 'as outras estão ao alcance, sem o vazio ocupar a folha toda');
  await p.context().close();

  // singular, sem trabalhando, e Mac antigo (sem o campo)
  await h.cenario({ sessoes: 1, outrasSessoes: [{ id: 'p1', nome: 'a', projeto: 'x', situacao: 'parada' }] });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => document.querySelector('.sessoes .outras')?.textContent === '1 parada'), 'uma só parada: "1 parada"');
  await p.context().close();
  await h.cenario({ outrasSessoes: [] });
  p = await h.pagina(); await pronta(h, p);
  h.ok(await p.evaluate(() => !document.querySelector('.sessoes .outras')), 'Mac antigo, sem outras sessões: nada de resumo');
  await p.context().close();

  // aviso discreto quando uma sessão termina
  await h.cenario({ sessoes: 1, outrasSessoes: [{ id: 'f1', nome: 'melhorias do painel', projeto: 'deck', situacao: 'trabalhando', passo: 'x' }] });
  p = await h.pagina(); await pronta(h, p); await h.dormir(1500);
  h.ok(await p.evaluate(() => !document.querySelector('#aviso').classList.contains('visivel')), 'ao abrir não avisa de nada');
  await h.cenario({ outrasSessoes: [{ id: 'f1', nome: 'melhorias do painel', projeto: 'deck', situacao: 'concluida', passo: 'pronto' }] });
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel') && document.querySelector('#aviso-txt').textContent === 'melhorias do painel terminou', null, 4000), 'quando a sessão que trabalhava termina, aparece "<nome> terminou"');
  await h.dormir(3600);
  await h.cenario({ outrasSessoes: [{ id: 'f1', nome: 'melhorias do painel', projeto: 'deck', situacao: 'concluida', passo: 'pronto' }] });
  await h.dormir(1500);
  h.ok(await p.evaluate(() => !document.querySelector('#aviso').classList.contains('visivel')), 'o mesmo término não avisa duas vezes');
  await p.context().close();

  // fotos nos três tamanhos
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'pe'], [1440, 900, 'janela']]) {
    await h.cenario({ sessoes: 2, outrasSessoes: OUTRAS, aprovacoes: [] });
    p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(400);
    await foto(p, `bloco-${nome}`);
    await p.evaluate(() => abrirSessoes()); await h.dormir(900); await foto(p, `folha-${nome}`);
    await p.keyboard.press('Escape'); await h.dormir(500);
    await h.cenario({ aprovacoes: [{ ...PEDIDO, segundos: 90 }] });
    await h.espera(p, () => !document.querySelector('#aprovacao').hidden); await h.dormir(300);
    const m = await p.evaluate(() => { const r = document.querySelector('.ap-caixa').getBoundingClientRect(); return { dentro: r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight, btns: [...document.querySelectorAll('[data-ap]')].every(b => { const q = b.getBoundingClientRect(); return q.right <= innerWidth && q.bottom <= innerHeight }) } });
    h.ok(m.dentro && m.btns, `${nome}: o cartão do pedido cabe na tela, com os dois botões`);
    await foto(p, `pedido-${nome}`);
    await h.cenario({ aprovacoes: [] });
    await p.context().close();
  }
}
