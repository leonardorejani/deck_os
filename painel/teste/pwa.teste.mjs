// Fase 4: o painel como PWA. Manifesto, service worker que abre sem o Mac, tela acesa, deslocamento contra
// queima de tela e o pareamento pelo QR (certificado, 6 dígitos e a saída para digitar o código).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { iniciar, CODIGO_PAREAR } from './servidor-falso.mjs';

const PAINEL = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const lerPainel = f => fs.readFileSync(path.join(PAINEL, f), 'utf8');
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

export default async function (h) {
  const porta = Number(new URL(h.base).port);

  /* 1. manifesto e ícones: o que o iPhone e o Chrome leem para instalar */
  const m = await (await fetch(h.base + '/manifest.webmanifest')).json();
  h.ok(m.name === 'Deck' && m.short_name === 'Deck' && m.display === 'standalone' && m.id === '/' && m.scope === '/' && m.start_url === '/?origem=app', `manifesto: nome, tela cheia, id, escopo e start_url (${m.name}, ${m.display}, ${m.start_url})`);
  h.ok(m.theme_color === '#0E0E0E' && m.background_color === '#0E0E0E', 'manifesto: a cor da abertura é a do fundo do painel');
  const tamanhos = m.icons.map(i => `${i.sizes}/${i.purpose}`);
  h.ok(['192x192/any', '512x512/any', '192x192/maskable', '512x512/maskable'].every(t => tamanhos.includes(t)), `manifesto: ícones 192 e 512, comuns e maskable (${tamanhos.join(' ')})`);
  const iconesOk = await Promise.all(m.icons.map(async i => { const r = await fetch(new URL(i.src, h.base + '/')); return r.status === 200 && r.headers.get('content-type') === 'image/png' }));
  h.ok(iconesOk.every(Boolean), 'manifesto: cada ícone citado responde 200 como PNG');
  const html = lerPainel('index.html');
  h.ok(/<link rel="manifest" href="manifest\.webmanifest">/.test(html) && /rel="apple-touch-icon" href="icones\/pwa\/apple-touch-icon-180\.png"/.test(html), 'index.html liga o manifesto e o ícone de 180 px da Tela de Início');
  h.ok(/apple-mobile-web-app-capable" content="yes"/.test(html) && !/user-scalable|maximum-scale/.test(html), 'index.html abre em tela cheia pela Tela de Início e não trava o zoom');

  /* 2. a lista da casca no service worker bate com o que o index.html carrega (arquivo novo fora da lista não abre offline) */
  const lista = [...lerPainel('sw.js').match(/const ESSENCIAIS = \[([\s\S]*?)\]\nconst NA_CASCA/)[1].matchAll(/'([^']+)'/g)].map(x => x[1]);
  const usados = [...html.matchAll(/(?:src|href)="([^"#]+)"/g)].map(x => '/' + x[1]).filter(x => !x.includes('://'));
  h.ok(usados.every(u => lista.includes(u)), `service worker: tudo que o index.html carrega está na casca (faltando: ${usados.filter(u => !lista.includes(u)).join(', ') || 'nada'})`);
  h.ok(lista.every(u => u === '/' || fs.existsSync(path.join(PAINEL, u))), `service worker: cada arquivo da lista existe (${lista.length} arquivos)`);
  h.ok(!lista.some(u => u.startsWith('/api') || u.includes('ca.crt')), 'service worker: a lista nunca leva a API nem o certificado');

  /* 3. service worker de verdade, num Mac que a gente derruba. Servidor próprio, para o do teste seguir de pé */
  const porta2 = porta + 100, base2 = `http://localhost:${porta2}`;
  let srv = await iniciar(porta2);
  const derrubar = s => new Promise(ok => { s.closeAllConnections?.(); s.close(ok) });
  const ctx = await h.novoContexto();
  const p = await ctx.newPage();
  const erros = []; p.on('pageerror', e => erros.push(e.message));
  await p.goto(`${base2}/?codigo=${h.CODIGO}`);
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a .faixa')), 'service worker: o painel abre com o Mac no ar');
  h.ok(await h.espera(p, () => navigator.serviceWorker.getRegistration().then(r => r?.active?.state === 'activated'), null, 15000), 'service worker: instalado e ativo');
  // o clients.claim() do activate assume a página aberta sem recarregar. Só depois disso o recarregar é a prova de que a casca vem dele
  h.ok(await h.espera(p, () => !!navigator.serviceWorker.controller, null, 15000), 'service worker: assume a página que já estava aberta (clients.claim)');
  await p.reload();
  const controlada = await h.espera(p, () => !!navigator.serviceWorker.controller && !!document.querySelector('.comp-a .faixa'));
  h.ok(controlada, `service worker: depois de recarregar, a página já é controlada por ele (${controlada || JSON.stringify(await p.evaluate(() => [!!navigator.serviceWorker.controller, !!document.querySelector('.comp-a .faixa'), document.title, location.href]))})`);
  const caches = await p.evaluate(async () => { const o = {}; for (const n of await window.caches.keys()) o[n] = (await (await window.caches.open(n)).keys()).map(r => new URL(r.url).pathname); return o });
  const nomes = Object.keys(caches), guardados = Object.values(caches).flat();
  h.ok(nomes.length === 1 && nomes[0] === 'deck-casca-v1', `cache: um só, o da versão atual (${nomes.join(', ')})`);
  h.ok(lista.every(u => guardados.includes(u)), `cache: a casca inteira ficou guardada (${guardados.length} arquivos)`);
  h.ok(!guardados.some(u => u.startsWith('/api') || u === '/ca.crt'), `cache: nada da API nem o certificado (${guardados.filter(u => u.startsWith('/api')).length} pedidos de API guardados)`);
  await h.dormir(2300); // o laço pediu o estado várias vezes e a lista de baixo continua limpa
  h.ok(!(await p.evaluate(async () => (await (await window.caches.open('deck-casca-v1')).keys()).some(r => r.url.includes('/api/')))), 'cache: depois de vários passos do laço, ainda nenhuma resposta da API guardada');

  await derrubar(srv); // o Mac "desliga"
  await p.reload();
  h.ok(await h.espera(p, () => document.title === 'Deck' && !!document.querySelector('#tela'), null, 4000), 'sem o Mac: a página abre mesmo assim, na hora');
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 6000), 'sem o Mac: a tela fecha em "Mac desconectado"');
  await h.espera(p, () => getComputedStyle(document.querySelector('.tela-offline:not(.acesso)')).opacity === '1');
  const off = await p.evaluate(() => { const o = document.querySelector('.tela-offline:not(.acesso)'); return { op: getComputedStyle(o).opacity, txt: o.textContent.replace(/\s+/g, ' ').trim() } });
  h.ok(off.op === '1' && off.txt.includes('Mac desconectado') && off.txt.includes('Confira se ele está ligado e no mesmo Wi-Fi'), `sem o Mac: o aviso é o da spec (${off.txt})`);
  h.ok(await p.evaluate(() => document.querySelector('#nome-mac').textContent) === 'MacBook Pro de Teste', 'sem o Mac: a pílula mostra o nome dele, guardado na última visita');
  h.ok(await p.evaluate(() => fetch('/api/estado', { headers: { 'X-Deck-Codigo': 'x' } }).then(() => 'respondeu', () => 'falhou')) === 'falhou', 'sem o Mac: a API não vem do cache, o pedido falha de verdade');
  await h.foto(p, 'pwa-mac-desconectado');
  await p.goto(`${base2}/?origem=app`); // o endereço que o ícone da Tela de Início abre
  h.ok(await h.espera(p, () => document.querySelector('#tela').classList.contains('offline'), null, 6000), 'sem o Mac: o endereço do ícone (/?origem=app) também abre');
  srv = await iniciar(porta2); // o Mac "volta"
  h.ok(await h.espera(p, () => !!document.querySelector('.comp-a .faixa') && !document.querySelector('#tela').classList.contains('offline'), null, 8000), 'o Mac volta: o painel reconecta sozinho');
  h.ok(erros.length === 0, `service worker: nenhum erro de JavaScript (${erros.join(' | ')})`);
  await ctx.close(); await derrubar(srv);

  /* 4. tela sempre acesa: pedida ao abrir, de novo ao voltar à tela, nunca com a página escondida */
  const lock = () => {
    const w = window.__wl = { pedidos: 0, soltas: [], modo: 'ok', escondida: false };
    Object.defineProperty(navigator, 'wakeLock', { configurable: true, value: { request: async () => {
      w.pedidos++;
      if (w.modo === 'nega') throw Object.assign(new Error('x'), { name: 'NotAllowedError' });
      const s = new EventTarget(); w.soltas.push(s); return s;
    } } });
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => w.escondida });
  };
  let wp = await h.pagina({ antes: lock });
  h.ok(await h.espera(wp, () => __wl.pedidos === 1), 'tela acesa: a trava é pedida ao abrir');
  await wp.evaluate(() => { __wl.escondida = true; __wl.soltas[0].dispatchEvent(new Event('release')); document.dispatchEvent(new Event('visibilitychange')) });
  await h.dormir(300);
  h.ok(await wp.evaluate(() => __wl.pedidos) === 1, 'tela acesa: com a página escondida não pede de novo');
  await wp.evaluate(() => { __wl.escondida = false; document.dispatchEvent(new Event('visibilitychange')) });
  h.ok(await h.espera(wp, () => __wl.pedidos === 2), 'tela acesa: ao voltar à tela, pede de novo (o sistema soltou a trava)');
  await wp.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await h.dormir(200);
  h.ok(await wp.evaluate(() => __wl.pedidos) === 2, 'tela acesa: com a trava ativa não pede em dobro');
  await wp.context().close();
  // negada: avisa uma vez e o toque tenta de novo, sem repetir o aviso
  const negado = await h.novoContexto(); await negado.addInitScript(lock); await negado.addInitScript(() => { __wl.modo = 'nega' });
  wp = await h.pagina({ ctx: negado });
  h.ok(await h.espera(wp, () => document.querySelector('#aviso').classList.contains('visivel') && document.querySelector('#aviso-txt').textContent.includes('Desligue o bloqueio automático')), 'tela acesa: trava negada, o aviso manda desligar o bloqueio automático do iPhone');
  await wp.evaluate(() => { __wl.modo = 'ok' }); await wp.mouse.click(5, 5);
  h.ok(await h.espera(wp, () => __wl.pedidos === 2 && __wl.soltas.length === 1), 'tela acesa: o toque na tela tenta de novo e consegue');
  await wp.context().close();
  // sem a API (Safari antigo): o mesmo aviso
  wp = await h.pagina({ antes: () => { Object.defineProperty(Navigator.prototype, 'wakeLock', { configurable: true, get: () => undefined }); delete navigator.wakeLock } });
  h.ok(await h.espera(wp, () => document.querySelector('#aviso-txt').textContent.includes('Desligue o bloqueio automático')), 'tela acesa: navegador sem Wake Lock mostra o aviso');
  await wp.context().close();

  /* 5. deslocamento contra queima de tela */
  wp = await h.pagina();
  h.ok(await wp.evaluate(() => AJUSTES.deslocamento) === 180000, 'queima de tela: o intervalo padrão é de 3 minutos');
  await wp.context().close();
  wp = await h.pagina({ ajustes: { deslocamento: 350 } });
  const passos = new Set();
  for (let i = 0; i < 24; i++) { passos.add(await wp.evaluate(() => getComputedStyle(document.querySelector('#moldura')).translate)); await h.dormir(150) }
  const valores = [...passos].map(t => t === 'none' ? [0, 0] : t.split(' ').map(parseFloat).concat(0).slice(0, 2));
  h.ok(passos.size >= 4 && valores.every(([x, y]) => Math.abs(x) <= 2 && Math.abs(y) <= 2), `queima de tela: a tela anda entre posições a até 2 px do centro (${[...passos].join(' | ')})`);
  h.ok(await wp.evaluate(() => { const r = document.querySelector('#tela').getBoundingClientRect(); return r.width > 100 }), 'queima de tela: o painel continua inteiro depois do deslocamento');
  await wp.context().close();

  /* 6. pareamento pelo QR */
  const qr = (frag, opcoes = {}) => h.novoContexto().then(async c => {
    const pg = await c.newPage();
    if (opcoes.antes) await pg.addInitScript(opcoes.antes);
    await pg.goto(`${h.base}/${frag}`);
    return pg;
  });
  const visivel = (pg, sel) => pg.evaluate(s => { const e = document.querySelector(s); return !!e && !e.hidden && getComputedStyle(e).display !== 'none' }, sel);
  const textoTela = pg => pg.evaluate(() => document.querySelector('#t-parear').textContent.replace(/\s+/g, ' ').trim());
  const pronto = pg => h.espera(pg, () => !!document.querySelector('.comp-a .faixa') && !document.querySelector('#conteudo.carregando'));
  const link = `#parear=${CODIGO_PAREAR}&certificado=${encodeURIComponent(h.base + '/ca.crt')}`;

  // 6a. o link do QR abre o passo a passo do certificado, com o link do /ca.crt do próprio Mac
  await h.reset();
  let q = await qr(link);
  h.ok(await h.espera(q, () => !document.querySelector('#t-parear').hidden), 'pareamento: o link do QR abre a tela do certificado');
  let t = await textoTela(q);
  h.ok(t.includes('Instale o certificado do Deck') && t.includes('Ajustes de Confiança de Certificados') && t.includes('Perfil Transferido') && t.includes('Baixar certificado') && t.includes('Continuar'), `pareamento: o passo a passo da SPEC 8 está na tela (${t.slice(0, 90)}...)`);
  h.ok(await q.evaluate(() => new URL(document.querySelector('#t-parear a.btn').href).pathname) === '/ca.crt', 'pareamento: "Baixar certificado" leva ao /ca.crt do Mac');
  h.ok(!q.url().includes('parear=') && !q.url().includes('#'), `pareamento: o código sai da barra de endereço (${q.url()})`);
  h.ok((await h.contadores()).parear.length === 0, 'pareamento: antes de tocar em Continuar nada é gasto do código');
  await h.foto(q, 'pwa-certificado');
  h.ok(await q.evaluate(() => { const e = document.querySelector('#t-parear'); return e.scrollHeight <= e.clientHeight + 1 }), 'pareamento: deitado, o passo a passo cabe na tela sem rolar');
  // recarregar no meio (o Safari às vezes descarta a aba ao ir aos Ajustes) não perde o passo
  await q.reload();
  h.ok(await h.espera(q, () => !document.querySelector('#t-parear').hidden && document.querySelector('#pa-titulo').textContent.includes('certificado')), 'pareamento: recarregar a aba no meio volta ao mesmo passo');
  await q.click('[data-pa="continuar"]');
  h.ok(await pronto(q) && !await visivel(q, '#t-parear'), 'pareamento: Continuar pareia com os 6 dígitos do QR e entra no painel');
  h.ok((await h.contadores()).parear.join() === CODIGO_PAREAR, 'pareamento: o Mac recebeu os 6 dígitos uma única vez');
  h.ok(await q.evaluate(() => localStorage.getItem('deck-codigo')) === h.CODIGO, 'pareamento: o código de acesso fica guardado no aparelho');
  h.ok(await h.espera(q, () => document.querySelector('#aviso-txt').textContent === 'Pareado com o Mac'), 'pareamento: aviso curto de pareado');
  await q.goto(h.base + '/');
  h.ok(await pronto(q), 'pareamento: reabrir sem QR continua pareado');
  await q.context().close();

  // 6b. em pé: a mesma tela cabe
  await h.reset();
  const cv = await (await h.novoContexto({ viewport: { width: 430, height: 932 } })).newPage();
  await cv.goto(`${h.base}/${link}`);
  h.ok(await h.espera(cv, () => !document.querySelector('#t-parear').hidden), 'pareamento: em pé a tela do certificado também abre');
  h.ok(await cv.evaluate(() => { const e = document.querySelector('#t-parear'); return e.scrollHeight <= e.clientHeight + 1 && document.documentElement.scrollWidth === innerWidth }), 'pareamento: em pé cabe sem rolar e sem estourar a largura');
  await h.foto(cv, 'pwa-certificado-em-pe');
  await cv.context().close();

  // 6c. iPhone no Safari (sem Tela de Início): depois de parear, mostra como instalar
  await h.reset();
  const ci = await (await h.novoContexto({ userAgent: IPHONE })).newPage();
  await ci.goto(`${h.base}/${link}`);
  await h.espera(ci, () => !document.querySelector('#t-parear').hidden);
  await ci.click('[data-pa="continuar"]');
  h.ok(await h.espera(ci, () => document.querySelector('#pa-titulo').textContent === 'iPhone conectado'), 'pareamento: no Safari do iPhone, pareado mostra como adicionar à Tela de Início');
  t = await textoTela(ci);
  h.ok(t.includes('Adicionar à Tela de Início') && t.includes('Compartilhar'), `pareamento: os passos de instalar estão lá (${t.slice(0, 80)}...)`);
  await h.foto(ci, 'pwa-instalar');
  await ci.click('[data-pa="fechar"]');
  h.ok(await pronto(ci) && !await visivel(ci, '#t-parear'), 'pareamento: "Abrir o painel" mostra o painel pareado');
  await ci.context().close();

  // 6d. link só com os dígitos (sem certificado): pareia direto
  await h.reset();
  q = await qr(`#parear=${CODIGO_PAREAR}`);
  h.ok(await pronto(q) && !await visivel(q, '#t-parear'), 'pareamento: link sem certificado pareia direto, sem passo a passo');
  await q.context().close();

  // 6e. código errado: o Mac diz quantas tentativas restam e a pessoa digita o certo
  await h.reset();
  q = await qr(`#parear=000000&certificado=${encodeURIComponent(h.base + '/ca.crt')}`);
  await h.espera(q, () => !document.querySelector('#t-parear').hidden);
  await q.click('[data-pa="continuar"]');
  h.ok(await h.espera(q, () => document.querySelector('#pa-titulo').textContent === 'Digite o código do Mac' && document.querySelector('#pa-erro').textContent.includes('Código incorreto. Restam 4 tentativas.')), 'pareamento: código do QR errado cai na tela do código com o motivo do Mac');
  await q.fill('#pa-cod', '12');
  await q.click('[data-pa="enviar"]');
  h.ok(await q.evaluate(() => document.querySelector('#pa-erro').textContent) === 'Digite os 6 dígitos que aparecem no Mac.', 'pareamento: menos de 6 dígitos nem sai do aparelho');
  h.ok((await h.contadores()).parear.length === 1, 'pareamento: e não gasta tentativa do Mac');
  await q.fill('#pa-cod', '');
  await q.type('#pa-cod', '482913');
  h.ok(await q.inputValue('#pa-cod') === '482 913', 'pareamento: o campo agrupa os dígitos em 3 e 3');
  await q.keyboard.press('Enter');
  h.ok(await pronto(q) && !await visivel(q, '#t-parear'), 'pareamento: digitando o código certo (Enter) entra no painel');
  await q.context().close();

  // 6f. sem QR (ícone da Tela de Início sem os dados do Safari): "Deck não pareado" ganha a saída do código
  await h.reset();
  q = await qr('');
  h.ok(await h.espera(q, () => document.querySelector('#tela').classList.contains('sem-acesso')), 'pareamento: sem código nem QR cai em "Deck não pareado"');
  h.ok(await visivel(q, '#b-digitar') && (await q.evaluate(() => document.querySelector('.tela-offline.acesso').textContent)).includes('Abra o Deck no Mac e leia o QR de novo'), 'pareamento: a tela mantém o texto de sempre e ganha o botão "Digitar o código do Mac"');
  await h.dormir(700);
  await q.click('#b-digitar');
  h.ok(await h.espera(q, () => document.querySelector('#pa-titulo').textContent === 'Digite o código do Mac' && document.activeElement?.id === 'pa-cod'), 'pareamento: o botão abre o campo do código, já com o foco');
  await q.type('#pa-cod', '482913'); await q.click('[data-pa="enviar"]');
  h.ok(await h.espera(q, () => !!document.querySelector('.comp-a .faixa') && !document.querySelector('#tela').classList.contains('sem-acesso')), 'pareamento: o painel volta a andar sozinho depois de parear (o laço retoma)');
  await h.dormir(2200);
  h.ok((await h.contadores()).estado >= 3, `pareamento: e segue pedindo o estado a cada segundo (${(await h.contadores()).estado} pedidos)`);
  await q.context().close();

  // 6g. Mac fora do ar no Continuar: volta ao certificado com o aviso, o QR segue valendo e funciona quando o Mac volta
  await h.reset(); await h.cenario({ mac: 'off' });
  q = await qr(link);
  await h.espera(q, () => !document.querySelector('#t-parear').hidden);
  await q.click('[data-pa="continuar"]');
  h.ok(await h.espera(q, () => document.querySelector('#pa-titulo').textContent.includes('certificado') && document.querySelector('.pa-erro')?.textContent.includes('Não deu para falar com o Mac')), 'pareamento: Mac fora do ar volta ao certificado com o aviso do que conferir');
  await h.cenario({ mac: 'on' });
  await q.click('[data-pa="continuar"]');
  h.ok(await pronto(q), 'pareamento: com o Mac de volta, o mesmo QR pareia (a falha de rede não gastou o código)');
  await q.context().close();

  // 6h. app nativo: o pareamento é por cabo e Bluetooth, nada disso aparece e o service worker não registra
  await h.reset();
  const nativo = () => {
    const e = { agora: new Date().toISOString(), nomeMac: 'Mac do App', perfilAtivo: 'p', comp: 'a', blocos: { spotify: true, agenda: true, whatsapp: true, sessoes: true, uso: true }, spotify: { tocando: true, faixa: 'Faixa do app nativo', artista: 'Canal injetado', posicao: 10, duracao: 100, capaId: 'x', cores: [] }, uso: [], sessoes: [], acesas: [], selos: {}, avisos: [] };
    const cfg = { versao: 1, perfis: [{ id: 'p', nome: 'P', teclas: [{ id: 'k1', nome: 'Tecla nativa', tipo: 'comando', valor: 'x', icone: 'svg:raio' }] }], perfilAtivo: 'p', comp: 'a', contas: [], blocos: e.blocos, nomeMac: 'Mac do App' };
    window.DeckCanal = { estado: async () => e, config: async () => cfg, botao: async () => ({ ok: true }), spotify: async () => ({ ok: true }), capaUrl: id => 'icones/deck.png?c=' + id, gravarConfig: async c => c, whatsapp: async () => [], agenda: async () => [], sessoes: async () => [] };
    window.__wl = 0; Object.defineProperty(navigator, 'wakeLock', { configurable: true, value: { request: async () => { __wl++; return new EventTarget() } } });
  };
  q = await qr(link, { antes: nativo });
  h.ok(await h.espera(q, () => document.querySelector('.faixa')?.textContent === 'Faixa do app nativo'), 'app nativo: o painel abre pelo canal injetado');
  await h.dormir(500);
  h.ok(!await visivel(q, '#t-parear') && !await visivel(q, '#b-digitar'), 'app nativo: nenhuma tela de certificado ou de código');
  h.ok(await q.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length) === 0, 'app nativo: o service worker não é registrado');
  h.ok(await q.evaluate(() => __wl) === 0, 'app nativo: a página não pede Wake Lock (a casca cuida da tela acesa)');
  await q.context().close();
}
