/* Fase 5, o que é novo no app nativo: estado e textos comuns a nativo.html (iPhone) e mac.html (Mac).
   Como dados.js, sincroniza entre abas: mexer num lado muda o outro. Os valores iniciais vêm da
   URL (?et=confirmar&canal=bluetooth&ren=falhou), para abrir o protótipo já na tela certa.
   Decidido em 10/11/2026: o caminho principal é o Bluetooth com código igual nas duas telas, e o
   cabo com código digitado no iPhone é a segunda via (link na tela de procurar). */
const NATIVO_ETAPAS = [['vazio', '1. Primeira abertura'], ['procurando', '2. Procurando por Bluetooth'], ['confirmar', '3. Confirmar o código'], ['pronto', '4. Pronto'], ['cabo', 'Segunda via: procurando no cabo'], ['codigo', 'Segunda via: digitar o código']];
const NATIVO_CODIGO = '483 291';
const NATIVO_PERGUNTAS = [['1', 'Parear'], ['2', 'Canal em uso']];
const NATIVO_REN = [['ok', 'Em dia'], ['pendente', 'Falhou, ainda com prazo'], ['falhou', 'Prazo apertando']];

const nativoEstado = { op: 'b', et: 'vazio', canal: 'bluetooth', ren: 'ok', pergunta: '1' };
// a via se deduz da etapa: as duas da segunda via são do cabo, as outras três do Bluetooth. "Pronto" mantém a que veio
const nativoVia = et => ['cabo', 'codigo'].includes(et) ? 'a' : ['vazio', 'procurando', 'confirmar'].includes(et) ? 'b' : null;
{
  const q = new URLSearchParams(location.search);
  const ok = (v, lista) => lista.some(([id]) => id === v);
  if (ok(q.get('et'), NATIVO_ETAPAS)) { nativoEstado.et = q.get('et'); nativoEstado.op = nativoVia(nativoEstado.et) || nativoEstado.op }
  if (q.get('op') === 'a' || q.get('op') === 'b') nativoEstado.op = q.get('op');
  if (ok(q.get('p'), NATIVO_PERGUNTAS)) nativoEstado.pergunta = q.get('p');
  if (['cabo', 'bluetooth'].includes(q.get('canal'))) nativoEstado.canal = q.get('canal');
  else nativoEstado.canal = nativoEstado.op === 'a' ? 'cabo' : 'bluetooth';
  if (ok(q.get('ren'), NATIVO_REN)) nativoEstado.ren = q.get('ren');
}
const nativoCanalDeck = 'BroadcastChannel' in self ? new BroadcastChannel('deck-nativo') : null;
function nativoPublicar(parcial) {
  if (parcial.et && nativoVia(parcial.et)) parcial = { op: nativoVia(parcial.et), ...parcial };
  Object.assign(nativoEstado, parcial); nativoCanalDeck?.postMessage({ ...nativoEstado });
}
function nativoAoMudar(fn) { nativoCanalDeck?.addEventListener('message', e => { Object.assign(nativoEstado, e.data); fn(nativoEstado) }) }

/* O que o Mac mostra em cada etapa (menu da barra e Ajustes > Conectar iPhone) */
const NATIVO_MAC = {
  vazio: { rotulo: 'Visível por Bluetooth', titulo: 'Abra o Deck no iPhone', texto: 'Ele lista os Macs por perto. Toque neste.' },
  procurando: { rotulo: 'Visível por Bluetooth', titulo: 'Esperando a escolha no iPhone', texto: 'O Bluetooth do Mac fica ligado só para o Deck.', girando: true },
  confirmar: { rotulo: 'iPhone de Exemplo quer parear', codigo: true, texto: 'Confira se o código é o mesmo do iPhone.', botoes: [['recusar', 'Recusar'], ['permitir', 'Permitir']] },
  cabo: { rotulo: 'Segunda via, pelo cabo', titulo: 'Abrindo o Deck no iPhone', texto: 'Se o iPhone perguntar, é só tocar em Confiar.', girando: true },
  codigo: { rotulo: 'Código', codigo: true, texto: 'Digite no iPhone. Vale por 10 minutos.' },
};
const NATIVO_PASSOS = ['Abra o <b>Deck</b> no iPhone e toque em <b>Procurar por perto</b>.', 'Toque no nome deste Mac na lista.', 'Veja se o <b>código é o mesmo</b> nas duas telas e toque em Permitir aqui.'];
const NATIVO_NOTA_VIA = 'Sem Bluetooth ou sem achar o Mac? Segunda via: plugue o iPhone no cabo e, na tela de procurar do app, toque em "Conectar pelo cabo com código". O Mac mostra um código de 6 dígitos para digitar no iPhone.';

/* Ícones novos (mesmo traço dos outros: 1.8, ponta redonda) */
const NATIVO_IC = {
  cabo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 2v5M15 2v5M7 7h10v4a5 5 0 0 1-10 0V7ZM12 16v6"/></svg>',
  bt: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m7 7 10 10-5 5V2l5 5L7 17"/></svg>',
  mac: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/></svg>',
};
const nativoCanalNome = c => c === 'bluetooth' ? 'Bluetooth' : 'Cabo';
