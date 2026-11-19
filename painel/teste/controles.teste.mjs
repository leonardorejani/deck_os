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
// topo do branco, em px dentro do cartão (o Chrome devolve o inset do clip-path em % ou px)
const TOPO = String.raw`(el, h) => { const m = getComputedStyle(el).clipPath.match(/inset\(([\d.]+)(px|%)/); return !m ? NaN : m[2] === '%' ? h * m[1] / 100 : Number(m[1]) }`;
// caixa de um cartão e o nível do branco (a camada de cima, recortada de baixo)
const caixa = (p, id) => p.evaluate(i => { const r = document.querySelector(`#ct-corpo [data-ctl="${i}"]`).getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height } }, id);
// arrasta o dedo de baixo para cima (dy > 0 sobe) a partir do meio do cartão, em fração da altura dele
const arrastar = async (p, id, dy) => {
  const r = await caixa(p, id);
  await p.mouse.move(r.x + r.w / 2, r.y + r.h / 2); await p.mouse.down(); await p.mouse.move(r.x + r.w / 2, r.y + r.h / 2 - r.h * dy, { steps: 8 }); await p.mouse.up();
};
const nivel = (p, id) => p.evaluate(([i, T]) => { const topoDe = (0, eval)(T), c = document.querySelector(`#ct-corpo [data-ctl="${i}"]`), r = c.getBoundingClientRect(), topo = topoDe(c.querySelector('.ctl-cheio'), r.height);
  return { nivel: Number(getComputedStyle(c).getPropertyValue('--nivel')), pctClip: Math.round((r.height - topo) / r.height * 100), num: c.querySelector('.ctl-num').textContent.replace('%', '') } }, [id, TOPO]);
// cor do texto na linha do branco: amostra o ícone e o rótulo de cada camada (a visível é a que o recorte deixa aparecer)
const cores = (p, id) => p.evaluate(i => { const c = document.querySelector(`#ct-corpo [data-ctl="${i}"]`);
  const luz = el => { const m = getComputedStyle(el).color.match(/\d+/g).map(Number); return (m[0] + m[1] + m[2]) / 3 };
  const [baixo, cima] = c.querySelectorAll('.ctl-num'); return { baixo: luz(baixo), cima: luz(cima), fundoCima: getComputedStyle(c.querySelector('.ctl-cheio')).backgroundColor } }, id);
const fim = h => h.dormir(750); // o branco sobe com transição e o número conta

// o slider vertical em um tamanho de tela: arrastar sobe e desce, o branco e o número acompanham, o texto troca de cor na linha, o Mudo alterna
async function provaSlider(h, w, alt, nome) {
  await h.reset(); await h.cenario({ comControles: true });
  const p = await h.pagina({ w, h: alt }); await pronta(h, p); await abrir(h, p);
  const rotulo = `${nome} ${w}x${alt}`;
  const cx = await p.evaluate(() => [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => { const r = c.getBoundingClientRect(); return [r.left, r.right, r.top, r.bottom] }));
  h.ok(cx.every(([l, r, t, b]) => l >= 0 && r <= w && t >= 0 && b <= alt), `${rotulo}: nenhum cartão estoura a tela`);
  h.ok(new Set(cx.map(([, , t, b]) => Math.round(b - t))).size === 1 && cx.every(([l, r, t, b]) => b - t >= 120 && r - l >= 80), `${rotulo}: cartões da mesma altura e com área de toque grande (${cx.map(([l, r, t, b]) => Math.round(r - l) + 'x' + Math.round(b - t))})`);
  const n0 = await nivel(p, 'volume'); h.ok(n0.nivel === 30 && Math.abs(n0.pctClip - 30) <= 1, `${rotulo}: o branco vai até o valor do Mac (${JSON.stringify(n0)})`);
  await arrastar(p, 'volume', 0.3); await fim(h);
  const sobe = await nivel(p, 'volume'); h.ok(sobe.nivel >= 55 && sobe.nivel <= 65 && Math.abs(sobe.pctClip - sobe.nivel) <= 1 && Number(sobe.num) === sobe.nivel, `${rotulo}: arrastar para cima sobe o valor, o branco e o número (${JSON.stringify(sobe)})`);
  await arrastar(p, 'volume', -0.2); await fim(h);
  const desce = await nivel(p, 'volume'); h.ok(desce.nivel >= 35 && desce.nivel <= 45 && Math.abs(desce.pctClip - desce.nivel) <= 1, `${rotulo}: arrastar para baixo desce (${JSON.stringify(desce)})`);
  await arrastar(p, 'volume', 3); await fim(h); h.ok((await nivel(p, 'volume')).nivel === 100, `${rotulo}: passar do topo trava em 100`);
  await arrastar(p, 'volume', -3); await fim(h); h.ok((await nivel(p, 'volume')).nivel === 0, `${rotulo}: passar da base trava em 0`);
  // tocar com o dedo na altura do número: a linha do branco passa pelo meio do número e o texto troca de cor ali
  const num = await p.evaluate(() => { const c = document.querySelector('[data-ctl="brilho"]'), r = c.querySelector('.ctl-num').getBoundingClientRect(), k = c.getBoundingClientRect(); return { x: k.left + k.width / 2, y: r.top + r.height / 2 } });
  await p.mouse.click(num.x, num.y); await fim(h);
  const linha = await p.evaluate(T => { const topoDe = (0, eval)(T), c = document.querySelector('[data-ctl="brilho"]'), [a, b] = [...c.querySelectorAll('.ctl-num')], ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(), r = c.getBoundingClientRect();
    const topo = r.top + topoDe(c.querySelector('.ctl-cheio'), r.height), luz = e => getComputedStyle(e).color.match(/\d+/g).slice(0, 3).reduce((x, y) => x + Number(y), 0) / 3;
    return { mesmoLugar: ra.top === rb.top && ra.left === rb.left, passa: topo > ra.top && topo < ra.bottom, claroEmbaixo: luz(a), escuroNoBranco: luz(b) } }, TOPO);
  h.ok(linha.mesmoLugar && linha.passa && linha.claroEmbaixo > 200 && linha.escuroNoBranco < 90, `${rotulo}: o texto troca de cor exatamente na linha do branco (${JSON.stringify(linha)})`);
  await h.foto(p, `controles-vertical-${nome}`);
  // Mudo alterna e troca a cor (vermelho ligado, cinza desligado)
  const cor = () => p.evaluate(() => { const b = document.querySelector('[data-mudo]'); return { fundo: getComputedStyle(b).backgroundColor, texto: b.querySelector('.ctl-estado').textContent, pressionado: b.getAttribute('aria-pressed') } });
  const antes = await cor(); await p.click('#ct-corpo [data-mudo]'); await fim(h); const depois = await cor();
  const verm = c => { const m = c.match(/\d+/g).map(Number); return m[0] > 200 && m[1] < 120 };
  h.ok(!verm(antes.fundo) && verm(depois.fundo) && depois.texto === 'Mudo' && depois.pressionado === 'true' && antes.texto === 'Som ligado', `${rotulo}: Mudo vira vermelho com "Mudo" e volta cinza com "Som ligado" (${antes.fundo} -> ${depois.fundo})`);
  await h.foto(p, `controles-vertical-${nome}-mudo`);
  await p.click('#ct-corpo [data-mudo]'); await fim(h);
  h.ok(!verm((await cor()).fundo), `${rotulo}: tocar de novo volta ao cinza`);
  await p.context().close();
}

export default async function (h) {
  /* ---------- Mac que oferece tudo ---------- */
  await h.cenario({ comControles: true });
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'tocar na tecla Controles abre a folha, sem esqueleto sobrando');
  let c = await h.contadores();
  h.ok(c.botoes.length === 0, `a tecla abre a tela no iPhone, sem mandar nada ao Mac (botões: ${c.botoes.length})`);
  h.ok(await linhas(p) === 'volume:30|brilho:60|teclado:20', `os três cartões com o valor do Mac (${await linhas(p)})`);
  h.ok(await p.evaluate(() => document.querySelector('#ct-titulo').textContent) === 'Controles do Mac', 'título "Controles do Mac"');
  await h.dormir(300); await h.foto(p, 'controles-tudo');
  // 13/11/2026 ("esses comandos podem ser cada retangulo um volume inteiro na vertical"): o cartão inteiro é o slider vertical
  const forma = await p.evaluate(() => ({ cartoes: [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => (c.querySelector('.ctl-rot')?.textContent || c.getAttribute('aria-label'))).join('|'), botoesSoltos: document.querySelectorAll('#ct-corpo .btn').length,
    mudo: document.querySelector('[data-mudo]').tagName, estado: document.querySelector('[data-mudo] .ctl-estado').textContent, fonte: parseFloat(getComputedStyle(document.querySelector('[data-ctl="volume"] .ctl-num')).fontSize),
    caixa: [...document.querySelectorAll('#ct-corpo .ctl-cartao')].map(c => { const r = c.getBoundingClientRect(); return [r.left, r.right, r.top, r.bottom] }), tela: [innerWidth, innerHeight],
    papel: document.querySelector('[data-ctl="volume"]').getAttribute('role'), barraAntiga: document.querySelectorAll('#ct-corpo .trilho').length, chave: document.querySelectorAll('#ct-corpo .ctl-chave').length }));
  h.ok(forma.cartoes === 'Volume|Mudo|Brilho da tela|Luz do teclado', `quatro cartões na ordem (${forma.cartoes})`);
  h.ok(forma.botoesSoltos === 0 && forma.mudo === 'BUTTON' && forma.estado === 'Som ligado', `Mudo é um botão do tamanho do cartão, sem chave (${forma.botoesSoltos}, ${forma.mudo}, ${forma.estado}, chave ${forma.chave})`);
  h.ok(forma.barraAntiga === 0 && forma.papel === 'slider', `sem a barra horizontal antiga, o cartão é o slider (${forma.barraAntiga}, ${forma.papel})`);
  h.ok(forma.fonte >= 28, `o valor é grande (${forma.fonte}px)`);
  h.ok(forma.caixa.every(([l, r, t, b]) => l >= 0 && r <= forma.tela[0] && t >= 0 && b <= forma.tela[1]), `deitado, nenhum cartão estoura a tela (${JSON.stringify(forma.caixa)} em ${forma.tela})`);
  const alturas = forma.caixa.map(([, , t, b]) => Math.round(b - t)); h.ok(new Set(alturas).size === 1 && alturas[0] >= 120, `os cartões têm a mesma altura e área de toque grande (${alturas})`);
  const n0 = await nivel(p, 'volume'); h.ok(n0.nivel === 30 && Math.abs(n0.pctClip - 30) <= 1 && n0.num === '30', `o branco vai até o valor do Mac (${JSON.stringify(n0)})`);
  // barra arrastável com resposta otimista: a tela já mostra o valor antes de o Mac confirmar
  await h.cenario({ ctAtraso: 800 });
  await arrastar(p, 'brilho', 0.2);
  const logo = await p.evaluate(() => document.querySelector('[data-ctl="brilho"] .ctl-num').textContent.replace('%', ''));
  h.ok(Number(logo) >= 70 && Number(logo) <= 90, `o cartão mostra o valor do dedo na hora, antes do Mac responder (${logo})`);
  h.ok(await h.ate(async () => (await h.contadores()).controles.some(x => /^brilho=\d+$/.test(x))), 'o Mac recebe o brilho');
  await h.ate(async () => (await h.contadores()).controles.filter(x => x.startsWith('brilho=')).at(-1) === `brilho=${logo}`, 6000);
  const enviados = (await h.contadores()).controles.filter(x => x.startsWith('brilho='));
  h.ok(Number(enviados.at(-1).split('=')[1]) === Number(logo), `o último valor que o Mac recebe é o que o dedo soltou (${enviados.join(',')})`);
  await h.cenario({ ctAtraso: 0 });
  await h.dormir(2300);
  h.ok((await linhas(p)).startsWith('volume:30|brilho:') && (await linhas(p)).includes(`brilho:${logo}|`), `depois de o Mac confirmar a tela continua no valor (${await linhas(p)})`);
  // mudo
  await p.click('#ct-corpo [data-mudo]');
  h.ok(await p.evaluate(() => document.querySelector('[data-mudo] .ctl-estado').textContent) === 'Mudo', 'o botão Mudo passa a dizer Mudo');
  h.ok(await h.espera(p, () => /235|2[0-9]{2}, *\d+, *\d+/.test(getComputedStyle(document.querySelector('[data-mudo]')).backgroundColor)), 'mudo ligado: fundo vermelho');
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
  await arrastar(p, 'brilho', 0.3);
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

  /* ---------- o slider vertical nos três tamanhos: deitado, em pé e janela larga do desktop ---------- */
  await provaSlider(h, 932, 430, 'deitado');
  await provaSlider(h, 430, 932, 'em-pe');
  await provaSlider(h, 1440, 800, 'desktop');
}
