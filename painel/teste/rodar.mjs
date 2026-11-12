// Roda os testes do painel contra o Mac de mentira (servidor-falso.mjs) no Chrome. Sai 1 se algo falhar.
//   node painel/teste/rodar.mjs            fotos em <repo>/.teste (fora do git), porta 4881 (DECK_TESTE_PORTA muda)
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { iniciar, CODIGO, CODIGO_NOVO } from './servidor-falso.mjs';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const SKILL = path.join(os.homedir(), '.claude/skills/tatile/node_modules/playwright/index.mjs');
const { chromium } = await import(process.env.DECK_PLAYWRIGHT || (fs.existsSync(SKILL) ? SKILL : "playwright"));
const porta = Number(process.env.DECK_TESTE_PORTA || 4881), base = `http://localhost:${porta}`;
// fotos ficam no .teste da raiz do repo principal (a worktree fica em <repo>/.claude/worktrees/<nome>)
const raiz = path.resolve(aqui, '../..'), principal = raiz.includes(`${path.sep}.claude${path.sep}worktrees${path.sep}`) ? raiz.split(`${path.sep}.claude${path.sep}worktrees${path.sep}`)[0] : raiz;
const fotos = process.env.DECK_FOTOS || path.join(principal, '.teste');
fs.mkdirSync(fotos, { recursive: true });

const servidor = await iniciar(porta);
const navegador = await chromium.launch({ channel: 'chrome' });
const falhas = [], paginasComErro = [];
const h = {
  base, CODIGO, CODIGO_NOVO, falhas,
  ok(cond, msg) { console.log((cond ? 'OK    ' : 'FALHA ') + msg); if (!cond) falhas.push(msg) },
  async cenario(patch) { return (await fetch(base + '/__cenario', { method: 'POST', body: JSON.stringify(patch) })).json() },
  async contadores() { return (await (await fetch(base + '/__cenario')).json()).contadores },
  async reset() { await fetch(base + '/__reset') },
  dormir: ms => new Promise(r => setTimeout(r, ms)),
  // codigo: true (certo, na URL), false (sem), ou um texto (errado)
  async pagina({ w = 932, h: alt = 430, codigo = true, ajustes, antes, ctx } = {}) {
    const contexto = ctx || await navegador.newContext({ viewport: { width: w, height: alt } });
    const p = await contexto.newPage();
    p.on('pageerror', e => { paginasComErro.push(e.message); console.log('ERRO na página: ' + e.message) });
    if (ajustes) await p.addInitScript(a => { window.DECK_AJUSTES = a }, ajustes);
    if (antes) await p.addInitScript(antes);
    await p.goto(`${base}/${codigo ? '?codigo=' + (codigo === true ? CODIGO : codigo) : ''}`);
    return p;
  },
  novoContexto: (opcoes = {}) => navegador.newContext({ viewport: { width: 932, height: 430 }, ...opcoes }),
  foto: (p, nome) => p.screenshot({ path: path.join(fotos, `painel-${nome}.png`) }),
  // espera uma condição dentro da página
  // espera uma condição no lado do teste (contadores do Mac de mentira). Com a resposta otimista a tela muda antes de o Mac receber
  async ate(fn, ms = 4000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await fn()) return true; await new Promise(r => setTimeout(r, 40)) } return false },
  espera: (p, fn, arg, timeout = 6000) => p.waitForFunction(fn, arg, { timeout, polling: 50 }).then(() => true, () => false),
};

const arquivos = ['canal.teste.mjs', 'estados.teste.mjs', 'composicoes.teste.mjs', 'laco.teste.mjs', 'robustez.teste.mjs', 'organizar.teste.mjs', 'menu.teste.mjs', 'corrigidos.teste.mjs', 'paineis.teste.mjs', 'mail.teste.mjs', 'ux.teste.mjs', 'leva2.teste.mjs', 'agenda-criar.teste.mjs', 'verificacao.teste.mjs', 'correcoes.teste.mjs', 'home-extras.teste.mjs', 'pwa.teste.mjs', 'iphone-bugs.teste.mjs', 'controles.teste.mjs'];
const so = process.argv[2];
for (const a of arquivos) {
  if (so && !a.startsWith(so)) continue;
  console.log(`\n== ${a}`);
  await h.reset();
  try { await (await import('./' + a)).default(h) } catch (e) { h.ok(false, `${a} quebrou: ${e.message}`) }
}
h.ok(paginasComErro.length === 0, 'nenhum erro de JavaScript em nenhuma página');
await navegador.close(); servidor.close();
console.log(`\n${falhas.length ? 'FALHOU: ' + falhas.length + ' verificação(ões)' : 'tudo certo'}`);
process.exit(falhas.length ? 1 : 0);
