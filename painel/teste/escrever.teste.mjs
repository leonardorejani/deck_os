// Escrever no Mac: o Menu abre uma folha com um campo e o Enviar, que manda o texto ao Mac (POST /api/colar), com o Mac de mentira.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const raiz = path.resolve(aqui, '../..'), sep = `${path.sep}.claude${path.sep}worktrees${path.sep}`;
const principal = raiz.includes(sep) ? raiz.split(sep)[0] : raiz;
const refinos = process.env.DECK_FOTOS_REFINOS || path.join(principal, '.teste', 'refinos');
const foto = async (p, nome) => { fs.mkdirSync(refinos, { recursive: true }); await p.screenshot({ path: path.join(refinos, `ditar-colar-${nome}.png`) }) };

const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla.menu'));
const aviso = p => p.evaluate(() => ({ txt: document.querySelector('#aviso-txt').textContent, erro: document.querySelector('#aviso').classList.contains('erro') }));
const msg = p => p.evaluate(() => ({ txt: document.querySelector('#es-msg').textContent, erro: document.querySelector('#es-msg').classList.contains('erro') }));
const aberta = p => p.evaluate(() => document.querySelector('#f-escrever').classList.contains('aberta'));
const abrir = async (h, p) => { await p.click('.tecla.menu'); await h.dormir(150); await p.click('[data-escrever]'); return h.espera(p, () => document.querySelector('#f-escrever').classList.contains('aberta')) };
const alvo = (p, sel) => p.evaluate(s => { const t = document.querySelector('#tela'), k = t.getBoundingClientRect().width / t.offsetWidth, b = document.querySelector(s).getBoundingClientRect(); return { l: Math.round(b.width / k), a: Math.round(b.height / k) } }, sel);

export default async function (h) {
  /* ---------- abrir pelo Menu, enviar e fechar ---------- */
  await h.reset();
  let p = await h.pagina(); await pronta(h, p);
  h.ok(await abrir(h, p), 'o Menu tem "Escrever no Mac" e ele abre a folha');
  h.ok(await p.evaluate(() => document.activeElement.id === 'es-texto'), 'o campo já nasce com o foco (o teclado e o ditado sobem juntos)');
  h.ok(await p.isDisabled('#es-enviar'), 'Enviar começa desligado (campo vazio)');
  h.ok(!(await p.evaluate(() => JSON.stringify(Object.keys(localStorage)))).includes('es-'), 'nada do texto vai para o armazenamento do navegador');
  const tam = await alvo(p, '#es-enviar');
  h.ok(tam.a >= 44, `o Enviar tem alvo de toque de 44 pt (${tam.a})`);
  await foto(p, 'deitado-vazio');
  await p.fill('#es-texto', 'olá, isto vai para o Mac\nsegunda linha');
  h.ok(!(await p.isDisabled('#es-enviar')), 'com texto, o Enviar liga');
  await p.click('#es-enviar');
  h.ok(await h.ate(async () => (await h.contadores()).colados.length === 1), 'Enviar manda o texto ao Mac');
  h.ok((await h.contadores()).colados[0] === 'olá, isto vai para o Mac\nsegunda linha', 'o texto chega inteiro, com a quebra de linha');
  h.ok(await h.espera(p, () => !document.querySelector('#f-escrever').classList.contains('aberta')), 'depois de enviar a folha fecha');
  h.ok((await aviso(p)).txt === 'Colado no Mac', 'um aviso confirma');
  await abrir(h, p);
  h.ok(await p.inputValue('#es-texto') === '', 'o campo volta vazio depois de enviar');

  /* ---------- o Mac recusa: o texto fica, com o motivo ---------- */
  await h.cenario({ colar: 'sem-app' });
  await p.fill('#es-texto', 'não pode perder isto');
  await p.click('#es-enviar');
  h.ok(await h.espera(p, () => document.querySelector('#es-msg').textContent.length > 0), 'sem app em foco o Mac recusa e a folha mostra o motivo');
  const m = await msg(p);
  h.ok(m.erro && m.txt === 'Nenhum app do Mac está pronto para receber texto. Abra o app e clique no campo.', `o motivo é o do Mac, em cor de erro (${m.txt})`);
  h.ok(await p.inputValue('#es-texto') === 'não pode perder isto' && await aberta(p), 'o texto continua no campo e a folha continua aberta');
  h.ok((await h.contadores()).colados.length === 1, 'nada foi colado');
  await foto(p, 'deitado-recusa');
  await h.cenario({ colar: 'normal' });
  await p.click('#es-enviar');
  h.ok(await h.ate(async () => (await h.contadores()).colados.length === 2), 'tentar de novo, agora com app em foco, cola o mesmo texto');
  await h.espera(p, () => !document.querySelector('#f-escrever').classList.contains('aberta'));

  /* ---------- sem Acessibilidade e Mac antigo ---------- */
  await h.cenario({ colar: 'sem-acesso' });
  await abrir(h, p); await p.fill('#es-texto', 'oi'); await p.click('#es-enviar');
  await h.espera(p, () => document.querySelector('#es-msg').textContent.length > 0);
  h.ok((await msg(p)).txt === 'O Deck precisa do acesso de Acessibilidade para teclar', 'sem Acessibilidade o Mac diz o que falta');
  await h.cenario({ colar: 'antigo' });
  await p.click('#es-enviar');
  await h.espera(p, () => /Atualize/.test(document.querySelector('#es-msg').textContent));
  h.ok((await msg(p)).txt === 'Este Mac ainda não escreve por aqui. Atualize o Deck no Mac.', 'Mac antigo (sem a rota) pede para atualizar');
  h.ok(await p.inputValue('#es-texto') === 'oi', 'e o texto segue no campo');
  await h.cenario({ colar: 'normal' });

  /* ---------- limite ---------- */
  await p.fill('#es-texto', 'a'.repeat(32001));
  h.ok(await p.isDisabled('#es-enviar'), 'acima de 32 mil caracteres o Enviar desliga');
  h.ok(/^1 caractere a mais/.test((await msg(p)).txt) && (await msg(p)).erro, `o campo diz quanto passou (${(await msg(p)).txt})`);
  await p.fill('#es-texto', 'a'.repeat(32000));
  h.ok(!(await p.isDisabled('#es-enviar')), 'no limite exato o Enviar liga');
  await p.fill('#es-texto', 'curto');
  h.ok((await msg(p)).txt === '', 'texto curto não mostra contador nenhum');
  await p.fill('#es-texto', '   ');
  h.ok(!(await p.isDisabled('#es-enviar')), 'só espaços ainda é texto (o Mac decide)');
  await p.fill('#es-texto', '');
  await p.click('#f-escrever .fechar'); await h.dormir(100);
  h.ok(!(await aberta(p)), 'Fechar fecha a folha');

  /* ---------- as três telas ---------- */
  for (const [nome, w, alt] of [['deitado', 932, 430], ['em-pe', 430, 932], ['janela', 1440, 900]]) {
    await h.reset();
    const q = await h.pagina({ w, h: alt }); await pronta(h, q);
    await abrir(h, q);
    await q.fill('#es-texto', 'Reunião às 15h com o time.\nPauta: revisar o plano e fechar a lista de entregas da semana.');
    await h.dormir(450);
    const g = await q.evaluate(() => {
      const t = document.querySelector('#tela').getBoundingClientRect(), f = document.querySelector('#f-escrever').getBoundingClientRect();
      const e = document.querySelector('#es-enviar').getBoundingClientRect(), x = document.querySelector('#es-texto').getBoundingClientRect(), c = document.querySelector('#f-escrever .fechar').getBoundingClientRect();
      return { enviarDentro: e.left >= t.left && e.right <= t.right && e.top >= t.top && e.bottom <= t.bottom, campoDentro: x.left >= f.left - 1 && x.right <= f.right + 1 && x.bottom <= f.bottom + 1, campoAlto: Math.round(x.height), sobrepoe: e.right > c.left + 1 && e.left < c.right - 1 };
    });
    h.ok(g.enviarDentro && g.campoDentro && !g.sobrepoe && g.campoAlto >= 80, `${nome}: Enviar à vista, campo dentro da folha e sem sobrepor o Fechar (${JSON.stringify(g)})`);
    await foto(q, nome);
  }
}
