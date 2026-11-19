// WhatsApp pelo Bluetooth (13/11/2026): "o app diz que está sem conexão com o Mac mesmo funcionando". O Bluetooth leva uns
// 25 KB/s, então a lista cheia passava dos 5 s do pedido (a tela dizia "sem conexão") e, mesmo quando passava, era reenviada
// inteira a cada segundo e tomava o canal. Aqui o Mac de mentira imita os dois: resposta lenta e lista versionada.
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const nomes = p => p.evaluate(() => [...document.querySelectorAll('#wa-lista .conversa .nome-c')].map(x => x.childNodes[0].textContent.trim()));

import { readFileSync } from 'node:fs';
export default async function (h) {
  /* ---------- o guarda de resposta velha de lerWhats tem que estar no código, não dentro de um comentário ---------- */
  const fonte = readFileSync(new URL('../paineis.js', import.meta.url), 'utf8').split('\n');
  const iLer = fonte.findIndex(l => l.startsWith('async function lerWhats'));
  const iCatch = fonte.findIndex((l, i) => i > iLer && l.includes('} catch'));
  const ativo = fonte.slice(iLer, iCatch).some(l => /^\s*if \(n !== wa\.seq\) return;\s*$/.test(l) && !l.includes('//'));
  h.ok(ativo, 'lerWhats descarta resposta de leitura velha (o guarda não está dentro de comentário)');

  /* ---------- lista lenta (canal devagar) chega, em vez de virar "sem conexão" ---------- */
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, atrasoListas: 1200 });
  let p = await h.pagina({ ajustes: { tempoLimite: 500 } }); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 4, undefined, 5000), 'a lista que demora mais que o tempo dos outros pedidos ainda chega');
  h.ok(!(await p.evaluate(() => document.querySelector('#wa-lista')?.textContent.includes('Não deu para ler'))), 'e a tela não diz que deu erro');
  await p.context().close();

  /* ---------- lista versionada: igual não reenvia, mudou traz de novo ---------- */
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, atrasoListas: 0, whatsappVersao: 5, whatsappExtra: false });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 4), 'a primeira leitura traz a lista inteira');
  h.ok(await h.ate(async () => (await h.contadores()).whatsappIguais >= 2, 5000), 'com a folha aberta o Mac responde "igual" e não reenvia a lista');
  const c = await h.contadores();
  h.ok(c.whatsappV[0] === '-1' && c.whatsappV.slice(1).every(v => v === '5'), `a primeira leitura pede sem versão e as seguintes mandam a que a tela tem (${c.whatsappV.join()})`);
  h.ok((await nomes(p)).length === 4, 'a lista continua na tela depois de um "igual"');
  await h.cenario({ whatsappVersao: 6, whatsappExtra: true });
  h.ok(await h.espera(p, () => [...document.querySelectorAll('#wa-lista .nome-c')].some(x => x.textContent.includes('Chegou Agora')), undefined, 4000), 'versão nova no Mac traz a lista nova');
  await p.context().close();

  /* ---------- Mac sem versão (banco do app, Web, Mac antigo): tudo como sempre ---------- */
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, whatsappVersao: null, whatsappExtra: false });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length === 4), 'Mac sem versão: a lista de sempre aparece');
  await p.context().close();
}
