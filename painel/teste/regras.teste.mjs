// Regras automáticas (SPEC 13, item 40, 19/11/2026): o Mac manda estado.regras e o iPhone mostra o cartão "Indo para Sessões em 3"
// com Ficar e Ir agora, troca de tela, composição ou perfil, desfaz o "enquanto durar" e nunca troca com a pessoa tocando na tela.
// Fotos em <repo principal>/.teste/refinos/regras-*.png (celular deitado, em pé e janela larga).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url)), raiz = path.resolve(aqui, '../..'), sep = path.sep;
const principal = raiz.includes(`${sep}.claude${sep}worktrees${sep}`) ? raiz.split(`${sep}.claude${sep}worktrees${sep}`)[0] : raiz;
const refinos = path.join(principal, '.teste', 'refinos');
fs.mkdirSync(refinos, { recursive: true });

const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
let seq = 1000;
const regra = (extra = {}) => ({ id: 'r1', nome: 'Sessão pede você: ir para Sessões', seq: ++seq, tipo: 'tela', alvo: 'sessoes', texto: 'Indo para Sessões', durar: false, segundos: 3, ...extra });
const cartao = p => p.evaluate(() => { const c = document.querySelector('#cartao-regra'); return { visivel: c.classList.contains('visivel'), texto: document.querySelector('#cr-texto').textContent, aria: c.getAttribute('aria-hidden') } });
const aberta = (p, id) => p.evaluate(i => document.querySelector(i).classList.contains('aberta'), id);
const toque = p => p.evaluate(() => dispatchEvent(new Event('pointerdown')));
const ultimaConfig = async h => { const c = (await h.contadores()).configsGravadas; return c[c.length - 1] };

export default async function (h) {
  /* 1. cartão, contagem e troca sozinha (nas três telas, com foto) */
  for (const [w, alt, nome] of [[932, 430, 'deitado'], [430, 932, 'pe'], [1440, 900, 'janela']]) {
    await h.reset();
    const p = await h.pagina({ w, h: alt }); await pronta(h, p); await h.dormir(300);
    h.ok(await p.evaluate(() => AJUSTES.semToqueMs === 10000), `${nome}: a pessoa tocando nos últimos 10 s segura a troca (padrão 10000 ms)`);
    await h.cenario({ regras: [regra()] });
    h.ok(await h.espera(p, () => document.querySelector('#cartao-regra').classList.contains('visivel'), null, 4000), `${nome}: o cartão aparece quando o Mac manda a regra`);
    const c = await cartao(p);
    h.ok(/^Indo para Sessões em [123]$/.test(c.texto) && c.aria === 'false', `${nome}: o cartão diz "${c.texto}"`);
    await h.dormir(500);
    const m = await p.evaluate(() => {
      const c = document.querySelector('#cartao-regra'), r = c.getBoundingClientRect(), t = document.querySelector('#tela').getBoundingClientRect(), tx = document.querySelector('#cr-texto');
      const b = [...c.querySelectorAll('button')].map(x => x.textContent.trim());
      return { dentro: r.left >= t.left && r.right <= t.right && r.bottom <= t.bottom && r.top >= t.top, cortado: tx.scrollWidth > tx.clientWidth + 1, botoes: b, ring: !!document.querySelector('#cr-volta'), larg: r.width, alt: r.height };
    });
    h.ok(m.dentro && !m.cortado, `${nome}: o cartão cabe na tela e o texto não é cortado (${Math.round(m.larg)}x${Math.round(m.alt)})`);
    h.ok(m.botoes.join() === 'Ficar,Ir agora' && m.ring, `${nome}: Ficar, Ir agora e o anel que esvazia (${m.botoes.join()})`);
    await p.screenshot({ path: path.join(refinos, `regras-cartao-${nome}.png`) });
    h.ok(await h.espera(p, () => document.querySelector('#f-sessoes').classList.contains('aberta'), null, 5000), `${nome}: acabou a contagem, foi para Sessões`);
    h.ok(!(await cartao(p)).visivel, `${nome}: o cartão some quando troca`);
    await p.screenshot({ path: path.join(refinos, `regras-depois-${nome}.png`) });
    await p.context().close();
  }

  /* 2. Ficar: não troca, e a mesma regra que segue valendo não volta a mostrar o cartão */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    const r = regra(); await h.cenario({ regras: [r] });
    await h.espera(p, () => document.querySelector('#cartao-regra').classList.contains('visivel'));
    await p.click('#cr-ficar'); await h.dormir(500);
    h.ok(!(await cartao(p)).visivel, 'Ficar: o cartão fecha');
    await h.dormir(4500);
    h.ok(!(await aberta(p, '#f-sessoes')) && !(await cartao(p)).visivel, 'Ficar: não trocou e o cartão não voltou com a regra ainda valendo');
    // a regra acaba e volta com disparo novo: aí mostra de novo
    await h.cenario({ regras: null }); await h.dormir(1500);
    await h.cenario({ regras: [regra()] });
    h.ok(await h.espera(p, () => document.querySelector('#cartao-regra').classList.contains('visivel'), null, 4000), 'Ficar: um disparo novo da regra volta a mostrar o cartão');
    await p.context().close();
  }

  /* 3. Ir agora troca na hora */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ alvo: 'meet', texto: 'Indo para Meet' })] });
    await h.espera(p, () => document.querySelector('#cartao-regra').classList.contains('visivel'));
    const t0 = Date.now(); await p.click('#cr-ir');
    h.ok(await h.espera(p, () => document.querySelector('#f-meet').classList.contains('aberta'), null, 1500) && Date.now() - t0 < 1500, 'Ir agora: abre o Meet sem esperar a contagem');
    await p.context().close();
  }

  /* 4. nunca troca enquanto a pessoa está tocando na tela */
  await h.reset(); {
    const p = await h.pagina({ ajustes: { semToqueMs: 3000 } }); await pronta(h, p);
    await toque(p); await h.cenario({ regras: [regra()] });
    await h.dormir(2200);
    h.ok(!(await cartao(p)).visivel && !(await aberta(p, '#f-sessoes')), 'toque: com a pessoa tocando há 2 s, nem o cartão aparece');
    h.ok(await h.espera(p, () => document.querySelector('#cartao-regra').classList.contains('visivel'), null, 4000), 'toque: passada a espera sem tocar, o cartão aparece');
    h.ok(!(await aberta(p, '#f-sessoes')), 'toque: o cartão aparece antes de trocar');
    await h.dormir(1200); await toque(p); await h.dormir(500);
    h.ok(!(await cartao(p)).visivel, 'toque: tocar durante a contagem esconde o cartão');
    await h.dormir(2000);
    h.ok(!(await aberta(p, '#f-sessoes')), 'toque: não trocou enquanto a pessoa tocava');
    h.ok(await h.espera(p, () => document.querySelector('#f-sessoes').classList.contains('aberta'), null, 9000), 'toque: quando a pessoa sossega, a contagem recomeça e troca');
    await p.context().close();
  }

  /* 5. enquanto durar: desfaz quando a regra deixa de valer. Sem durar, fica */
  for (const durar of [true, false]) {
    await h.reset();
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ alvo: 'meet', texto: 'Indo para Meet', durar })] });
    await h.espera(p, () => document.querySelector('#f-meet').classList.contains('aberta'), null, 6000);
    await h.cenario({ regras: null });
    await h.dormir(2500);
    const fechou = !(await aberta(p, '#f-meet'));
    h.ok(durar ? fechou : !fechou, `enquanto durar ${durar ? 'ligado' : 'desligado'}: depois que a regra acaba a tela ${durar ? 'volta' : 'continua'}`);
    await p.context().close();
  }
  await h.reset(); {
    // se a pessoa já fechou ou trocou a tela sozinha, desfazer não mexe em nada
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ alvo: 'meet', texto: 'Indo para Meet', durar: true })] });
    await h.espera(p, () => document.querySelector('#f-meet').classList.contains('aberta'), null, 6000);
    await p.evaluate(() => { fecharFolha(); abrirControles() }); await h.dormir(500);
    await h.cenario({ regras: null }); await h.dormir(2500);
    h.ok(await aberta(p, '#f-controles'), 'enquanto durar: a tela que a pessoa abriu depois não é fechada');
    await p.context().close();
  }

  /* 6. composição: grava no Mac, e com "enquanto durar" volta à de antes */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ tipo: 'composicao', alvo: 'c', texto: 'Trocando para Relógio e mês', durar: true })] });
    const ok = await h.ate(async () => (await ultimaConfig(h))?.comp === 'c', 8000);
    h.ok(ok, 'composição: depois da contagem o iPhone grava a composição C no Mac');
    h.ok(await h.espera(p, () => V.comp === 'c', null, 6000), 'composição: a tela já está na composição C');
    await h.cenario({ regras: null });
    h.ok(await h.ate(async () => (await ultimaConfig(h))?.comp === 'a', 8000), 'composição: com enquanto durar, a regra acabando volta para a composição de antes');
    h.ok(await h.espera(p, () => V.comp === 'a', null, 6000), 'composição: e a tela volta à A');
    await p.context().close();
  }

  /* 7. perfil */
  await h.reset(); {
    await h.cenario({ perfis: 'dois' });
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ tipo: 'perfil', alvo: 'ensaio', texto: 'Trocando para o perfil Ensaio', durar: true })] });
    h.ok(await h.ate(async () => (await ultimaConfig(h))?.perfilAtivo === 'ensaio', 8000), 'perfil: depois da contagem o iPhone troca para o perfil Ensaio');
    await h.cenario({ regras: null });
    h.ok(await h.ate(async () => (await ultimaConfig(h))?.perfilAtivo === 'trabalho', 8000), 'perfil: com enquanto durar, volta ao perfil de antes');
    await p.context().close();
  }

  /* 8. mostrar aviso: sem cartão e sem contagem */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [regra({ tipo: 'aviso', alvo: 'Mensagem nova', texto: 'Mensagem nova' })] });
    h.ok(await h.espera(p, () => document.querySelector('#aviso').classList.contains('visivel') && document.querySelector('#aviso-txt').textContent === 'Mensagem nova', null, 3000), 'aviso: o texto aparece na pílula de aviso');
    h.ok(!(await cartao(p)).visivel, 'aviso: sem cartão de contagem');
    await p.context().close();
  }

  /* 9. Mac antigo (sem a chave) e lista vazia: nada acontece */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    await h.cenario({ regras: [] }); await h.dormir(2500);
    h.ok(!(await cartao(p)).visivel, 'lista vazia: sem cartão');
    await p.context().close();
  }

  /* 10. organizando as teclas a troca espera */
  await h.reset(); {
    const p = await h.pagina(); await pronta(h, p);
    await p.evaluate(() => entrarOrganizar());
    await h.cenario({ regras: [regra()] }); await h.dormir(3500);
    h.ok(!(await cartao(p)).visivel && !(await aberta(p, '#f-sessoes')), 'organizar: com o modo organizar aberto nada troca');
    await p.context().close();
  }
}
