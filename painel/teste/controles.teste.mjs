// Controles do Mac (SPEC, seção 13, item 35): volume com mudo, brilho da tela e luz do teclado numa folha do iPhone.
// O Mac de mentira diz o que "oferece" (tudo, sem brilho, nada, Mac antigo, erro) e a tela mostra só isso.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const abrir = async (h, p) => {
  await p.evaluate(() => document.querySelector('.tecla[data-id="controles"]').click());
  const ok = await h.espera(p, () => document.querySelector('#f-controles').classList.contains('aberta') && !document.querySelector('#ct-corpo .esq-lista'));
  await h.dormir(500); // a folha ainda desliza para o lugar: arrastar a barra só depois de parar
  return ok;
};
// o número é o valor grande do cartão ("30%"): aqui só os dígitos. O Mudo é um cartão à parte (sem data-ctl)
const linhas = p => p.evaluate(() => [...document.querySelectorAll('#ct-corpo .ctl-cartao[data-ctl]')].map(l => `${l.dataset.ctl}:${l.querySelector('.ctl-num').textContent.replace('%', '')}`).join('|'));
// leva o dedo da barra até a fração f da largura (0 a 1), como no player
const arrastar = async (p, id, f) => {
  const r = await p.evaluate(i => { const b = document.querySelector(`#ct-corpo [data-ctl="${i}"] .trilho`).getBoundingClientRect(); return { x: b.left, y: b.top + b.height / 2, w: b.width } }, id);
  await p.mouse.move(r.x + r.w * 0.5, r.y); await p.mouse.down(); await p.mouse.move(r.x + r.w * f, r.y, { steps: 6 }); await p.mouse.up();
};

export default async function (h) {
  /* ---------- Mac que oferece tudo ---------- */
  await h.cenario({ comControles: true });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'tocar na tecla Controles abre a folha, sem esqueleto sobrando');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0, `a tecla abre a tela no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  h.ok(await linhas(p) === 'volume:30|brilho:60|teclado:20', `as três barras com o valor do Mac (${await linhas(p)})`);
  h.ok(await p.evaluate(() => document.querySelector('#ct-titulo').textContent) === 'Controles do Mac', 'título "Controles do Mac"');
  await h.dormir(300); await h.foto(p, 'controles-tudo');
  // 13/11/2026 ("achei muito feia a interface"): um cartão por controle no estilo do Monitor, Mudo como cartão que alterna, sem botão solto
  const forma = await p.evaluate(() => ({ cartoes: [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => c.querySelector('.ctl-rot').textContent).join('|'), botoesSoltos: document.querySelectorAll('#ct-corpo .btn').length,
    mudo: document.querySelector('[data-mudo]').tagName, estado: document.querySelector('[data-mudo] .ctl-estado').textContent, fonte: parseFloat(getComputedStyle(document.querySelector('[data-ctl="volume"] .ctl-num')).fontSize),
    caixa: [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => { const r = c.getBoundingClientRect(); return [r.left, r.right, r.top, r.bottom] }), tela: [innerWidth, innerHeight],
    toque: (() => { const t = document.querySelector('[data-ctl="volume"] .trilho'); const a = getComputedStyle(t, '::before'); return parseFloat(a.height) })() }));
  h.ok(forma.cartoes === 'Volume|Mudo|Brilho da tela|Luz do teclado', `quatro cartões na ordem (${forma.cartoes})`);
  h.ok(forma.botoesSoltos === 0 && forma.mudo === 'BUTTON' && forma.estado === 'Desligado', `Mudo é um cartão que alterna, sem botão solto (${forma.botoesSoltos}, ${forma.mudo}, ${forma.estado})`);
  h.ok(forma.fonte >= 28, `o valor é grande (${forma.fonte}px)`);
  h.ok(forma.caixa.every(([l, r, t, b]) => l >= 0 && r <= forma.tela[0] && t >= 0 && b <= forma.tela[1]), `deitado, nenhum cartão estoura a tela (${JSON.stringify(forma.caixa)} em ${forma.tela})`);
  h.ok(forma.toque >= 44, `a barra tem área de toque grande (${forma.toque}px)`);
  // barra arrastável com resposta otimista: a tela já mostra o valor antes de o Mac confirmar
  await h.cenario({ ctAtraso: 800 });
  await arrastar(p, 'brilho', 0.8);
  const logo = await p.evaluate(() => document.querySelector('[data-ctl="brilho"] .ctl-num').textContent.replace('%', ''));
  h.ok(Number(logo) >= 70 && Number(logo) <= 90, `a barra mostra o valor do dedo na hora, antes do Mac responder (${logo})`);
  h.ok(await h.ate(async () => (await h.contadores()).controles.some(x => /^brilho=\d+$/.test(x))), 'o Mac recebe o brilho');
  await h.ate(async () => (await h.contadores()).controles.filter(x => x.startsWith('brilho=')).at(-1) === `brilho=${logo}`, 6000);
  const enviados = (await h.contadores()).controles.filter(x => x.startsWith('brilho='));
  h.ok(Number(enviados.at(-1).split('=')[1]) === Number(logo), `o último valor que o Mac recebe é o que o dedo soltou (${enviados.join(',')})`);
  await h.cenario({ ctAtraso: 0 });
  await h.dormir(2300);
  h.ok(await linhas(p) === `volume:30|brilho:${logo}|teclado:20`, `depois de o Mac confirmar a tela continua no valor (${await linhas(p)})`);
  // mudo
  await p.click('#ct-corpo [data-mudo]');
  h.ok(await p.evaluate(() => document.querySelector('[data-mudo] .ctl-estado').textContent) === 'Ligado', 'o cartão Mudo troca o valor para Ligado');
  h.ok(await p.evaluate(() => document.querySelector('[data-mudo]').getAttribute('aria-pressed')) === 'true' && await p.evaluate(() => document.querySelector('[data-ctl="volume"]').classList.contains('mudo')), 'Mudo acende na hora');
  h.ok(await h.ate(async () => (await h.contadores()).controles.includes('mudo=1')), 'o Mac recebe mudo=1');
  await p.click('#ct-corpo [data-mudo]');
  h.ok(await h.ate(async () => (await h.contadores()).controles.includes('mudo=0')), 'tocar de novo volta o som (mudo=0)');
  // o Mac mexe sozinho (teclas do próprio Mac): a folha aberta acompanha
  await h.cenario({ ctVolume: 77 });
  h.ok(await h.espera(p, () => document.querySelector('[data-ctl="volume"] .ctl-num').textContent === '77%', undefined, 5000), 'o volume mudado no Mac aparece na folha aberta');
  // fechar
  await p.click('#f-controles [data-fechar]');
  h.ok(await h.espera(p, () => !document.querySelector('#f-controles').classList.contains('aberta')), 'o X fecha a folha');
  await p.context().close();

  /* ---------- em pé: dois por linha, nada passa da área segura ---------- */
  await h.reset(); await h.cenario({ comControles: true });
  p = await h.pagina({ w: 430, h: 932 }); await pronta(h, p); await abrir(h, p);
  const pe = await p.evaluate(() => ({ colunas: new Set([...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => Math.round(c.getBoundingClientRect().left))).size,
    caixa: [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => { const r = c.getBoundingClientRect(); return [r.left, r.right, r.top, r.bottom] }), horizontal: document.documentElement.scrollWidth > innerWidth }));
  h.ok(pe.colunas === 2 && !pe.horizontal, `em pé são duas colunas, sem rolagem de lado (${pe.colunas})`);
  h.ok(pe.caixa.every(([l, r, t, b]) => l >= 0 && r <= 430 && t >= 0 && b <= 932), `em pé nenhum cartão estoura a tela (${JSON.stringify(pe.caixa)})`);
  await h.dormir(300); await h.foto(p, 'controles-em-pe');
  await p.context().close();

  /* ---------- o que o Mac não oferece some ---------- */
  await h.reset(); await h.cenario({ comControles: true, controles: 'sem-brilho' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(await linhas(p) === 'volume:30', `sem tela interna nem luz no teclado, só o volume aparece (${await linhas(p)})`);
  await p.context().close();

  await h.reset(); await h.cenario({ comControles: true, controles: 'nada' });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  h.ok(/Nada para controlar/.test(await p.evaluate(() => document.querySelector('#ct-corpo').textContent)) && await linhas(p) === '', 'sem nenhum controle a tela diz que não há o que controlar, sem barra falsa');
  await p.context().close();

  await h.reset(); await h.cenario({ comControles: true, controles: 'antigo' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => document.querySelector('.tecla[data-id="controles"]').click());
  h.ok(await h.espera(p, () => /Atualize o Deck no Mac/.test(document.querySelector('#ct-corpo').textContent)), 'Mac antigo (sem a rota): a tela pede para atualizar o Deck');
  await p.context().close();

  await h.reset(); await h.cenario({ comControles: true, controles: 'erro' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => document.querySelector('.tecla[data-id="controles"]').click());
  h.ok(await h.espera(p, () => !!document.querySelector('#ct-corpo [data-ct-tentar]')), 'erro do Mac: "Tentar de novo" no lugar das barras');
  await h.cenario({ controles: 'tudo' });
  await p.click('#ct-corpo [data-ct-tentar]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#ct-corpo .ctl-cartao[data-ctl]').length === 3), 'Tentar de novo traz as barras');
  await p.context().close();

  /* ---------- o Mac recusa: a barra volta ao valor real ---------- */
  await h.reset(); await h.cenario({ comControles: true });
  p = await h.pagina(); await pronta(h, p); await abrir(h, p);
  await h.cenario({ controles: 'recusa' });
  await arrastar(p, 'brilho', 0.9);
  h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('erro')), 'pedido recusado mostra o erro do Mac');
  await h.cenario({ controles: 'tudo' });
  h.ok(await h.espera(p, () => document.querySelector('[data-ctl="brilho"] .ctl-num').textContent === '60%', undefined, 6000), 'a barra volta ao valor que o Mac realmente tem');
  await p.context().close();

  /* ---------- a tecla vem do editor, como um app ---------- */
  await h.reset();
  p = await h.pagina(); await pronta(h, p);
  const noEditor = await p.evaluate(() => ({ valor: CONTROLES_DO_MAC.valor, painel: painelDe({ tipo: 'app', valor: CONTROLES_DO_MAC.valor }), comAcao: painelDe({ tipo: 'app', valor: CONTROLES_DO_MAC.valor, acao: { id: 'x' } }) }));
  h.ok(noEditor.painel === 'controles' && noEditor.comAcao === undefined, `a tecla de app "${noEditor.valor}" abre a tela dos controles (${JSON.stringify(noEditor)})`);
  await p.context().close();

  /* ---------- no editor, "Controles do Mac" está na lista de apps (era um botão escondido embaixo) e vira a tecla ---------- */
  await h.reset(); await h.cenario({ apps: 'normal' });
  p = await h.pagina(); await pronta(h, p);
  await p.evaluate(() => abrirEditor('nova'));
  h.ok(await h.espera(p, () => !!document.querySelector('#ed-lista-apps button[data-app-bundle="deck-controles"]')), 'o editor de tecla nova lista "Controles do Mac" junto dos apps');
  h.ok(await p.evaluate(() => !document.querySelector('[data-app-controles]')), 'o botão escondido embaixo da lista saiu');
  await p.click('#ed-lista-apps button[data-app-bundle="deck-controles"]');
  const rascunho = await p.evaluate(() => ({ valor: rasc.valor, icone: rasc.icone, tipo: rasc.tipo, nome: document.querySelector('#ed-nome').value, ajuda: document.querySelector('#ed-acoes')?.textContent.trim() }));
  h.ok(rascunho.valor === 'Controles' && rascunho.icone === 'svg:controles' && rascunho.tipo === 'app' && rascunho.nome === 'Controles do Mac', `escolher cria a tecla de app "Controles" com o ícone próprio (${JSON.stringify(rascunho)})`);
  h.ok(/abre os controles do Mac aqui no iPhone/.test(rascunho.ajuda), 'a tela diz que a tecla abre os controles aqui, sem lista de ações');
  await p.context().close();
}
