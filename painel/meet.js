/* Google Meet: a central da reunião numa folha cheia. Entrar no Meet (abre meet.google.com ou traz a aba da reunião que já
   está aberta), microfone, câmera e sair da chamada. O Mac diz o estado em GET /api/meet (lido pela Acessibilidade, sem o
   usuário ligar nada no navegador). Microfone e câmera ficam verdes ligados e vermelhos desligados, e sem reunião aberta
   os botões dizem isso em vez de fingir estado. Mac antigo, sem a rota, só oferece abrir o Meet nele.
   Usa as peças de deck.js (V, canal, avisar, abrirFolha, tratarErro, JANELA_OTM) e paineis.js (msgErro, abrirNoMac). */

const mt = { dados: null, erro: '', seq: 0, antigo: false, html: '', ocupado: null };
const otmMeet = {}; // o que o dedo pôs em microfone ou câmera: { v, ate }. Vale até o Mac confirmar ou a janela acabar
const ESTADOS_MEET = ['ligado', 'desligado', 'desconhecido', 'sem-reuniao'];
const estadoMeet = v => ESTADOS_MEET.includes(v) ? v : 'desconhecido';

function valorMeet(item) {
  const real = estadoMeet(mt.dados?.[item]), o = otmMeet[item];
  if (!o) return real;
  if (performance.now() > o.ate || real === o.v) { delete otmMeet[item]; return real }
  return o.v;
}

function abrirMeet() {
  mt.dados = null; mt.erro = ''; mt.antigo = false; mt.html = ''; mt.ocupado = null;
  for (const k in otmMeet) delete otmMeet[k];
  pintarMeet(); abrirFolha('#f-meet'); lerMeet();
}
async function lerMeet() {
  const n = ++mt.seq;
  try {
    const d = await canal.meet(); if (n !== mt.seq) return;
    mt.dados = d && typeof d === 'object' ? d : { aberta: false }; mt.erro = ''; mt.antigo = false;
  } catch (e) {
    if (n !== mt.seq) return;
    if (e.status === 401) return tratarErro(e);
    if (e.status === 404) { mt.antigo = true; mt.dados = null; mt.erro = '' }
    else {
      mt.erro = msgErro(e);
      if (mt.dados) { avisar(mt.erro, { erro: true }); mt.erro = ''; return } // com o que já estava na tela, só avisa
    }
  }
  pintarMeet();
}

const ICONES_MEET = { microfone: 'microfone', camera: 'camera' };
/* o texto e a classe de cada botão, pelo estado que o Mac leu */
function blocoMeet(item, nome, ligadoTxt, desligadoTxt, estado) {
  const classe = { ligado: 'ligado', desligado: 'desligado', desconhecido: 'incerto', 'sem-reuniao': 'sem' }[estado];
  const sub = { ligado: ligadoTxt, desligado: desligadoTxt, desconhecido: 'Não consegui ler', 'sem-reuniao': 'Sem reunião' }[estado];
  const icone = SVG[item === 'microfone' ? (estado === 'desligado' ? 'microfoneCortado' : 'microfone') : (estado === 'desligado' ? 'cameraCortada' : 'camera')];
  const sem = estado === 'sem-reuniao', pressionado = estado === 'ligado' || estado === 'desligado' ? ` aria-pressed="${estado === 'ligado'}"` : '';
  const dica = estado === 'ligado' ? (item === 'microfone' ? 'Toque para mutar' : 'Toque para desligar') : estado === 'desligado' ? (item === 'microfone' ? 'Toque para desmutar' : 'Toque para ligar') : '';
  return `<button class="mt-bloco ${classe}" data-mt="${item}"${pressionado}${sem || mt.ocupado ? ' disabled' : ''} aria-label="${esc(`${nome}: ${sub}.${dica ? ' ' + dica : ''}`)}">
    <span class="mt-ic" aria-hidden="true">${icone}</span><span class="mt-nome">${nome}</span><span class="mt-sub">${esc(sub)}</span></button>`;
}

function pintarMeet() {
  const corpo = $('#mt-corpo'); if (!corpo) return;
  let h;
  if (mt.antigo) {
    h = `<div class="vazio-bloco" style="min-height:160px"><strong>Este Mac ainda não tem a central do Meet</strong><span>Atualize o Deck no Mac. Até lá, a tecla só abre o Meet no navegador dele.</span><button class="btn primario" data-mt-mac style="justify-self:start">Abrir o Meet no Mac</button></div>`;
  } else if (!mt.dados) {
    h = mt.erro
      ? `<div class="vazio-bloco" style="min-height:160px"><strong>Não deu para ler</strong><span>${esc(mt.erro)}</span><button class="btn secundario pequeno" data-mt-tentar style="justify-self:start">Tentar de novo</button></div>`
      : '<div class="esq-lista" aria-hidden="true"><div class="mt-grade">' + '<span class="mt-bloco esq"></span>'.repeat(4) + '</div></div>';
  } else {
    const d = mt.dados, aberta = d.aberta === true, naChamada = d.naChamada;
    const estado = aberta ? (naChamada === false ? 'Você está na tela de entrada' : 'Reunião aberta') : 'Nenhuma reunião aberta';
    const mic = aberta ? valorMeet('microfone') : 'sem-reuniao', cam = aberta ? valorMeet('camera') : 'sem-reuniao';
    const sai = aberta && naChamada !== false;
    h = `<div class="mt-estado ${aberta ? 'aberta' : ''}"><i aria-hidden="true"></i><span>${estado}</span></div>
      <div class="mt-aviso">${aberta && d.aviso ? esc(d.aviso) : ''}</div>
      <div class="mt-grade">
        <button class="mt-bloco entrar" data-mt="entrar"${mt.ocupado ? ' disabled' : ''}><span class="mt-ic" aria-hidden="true">${SVG.video}</span><span class="mt-nome">Entrar no Meet</span><span class="mt-sub">${aberta ? 'Trazer a reunião para a frente' : 'Abrir meet.google.com'}</span></button>
        ${blocoMeet('microfone', 'Microfone', 'Ligado', 'Mutado', mic)}
        ${blocoMeet('camera', 'Câmera', 'Ligada', 'Desligada', cam)}
        <button class="mt-bloco sair ${sai ? '' : 'sem'}" data-mt="sair"${sai && !mt.ocupado ? '' : ' disabled'}><span class="mt-ic" aria-hidden="true">${SVG.desligar}</span><span class="mt-nome">Sair da chamada</span><span class="mt-sub">${!aberta ? 'Sem reunião' : naChamada === false ? 'Você ainda não entrou' : 'Encerrar a chamada'}</span></button>
      </div>`;
  }
  if (h === mt.html) return; // nada mudou: não refaz (o laço de 2 s não pode apagar o toque em andamento)
  mt.html = h; corpo.innerHTML = h; corpo.setAttribute('aria-busy', String(!mt.dados && !mt.erro && !mt.antigo));
}

const TEXTO_MEET = { entrar: 'Abrindo o Meet', microfone: 'Microfone', camera: 'Câmera', sair: 'Saindo da chamada' };
async function agirMeet(acao) {
  if (mt.ocupado) return;
  mt.ocupado = acao;
  if (acao === 'microfone' || acao === 'camera') { // a resposta é na hora: vale o que o dedo pôs até o Mac confirmar
    const atual = valorMeet(acao);
    if (atual === 'ligado' || atual === 'desligado') otmMeet[acao] = { v: atual === 'ligado' ? 'desligado' : 'ligado', ate: performance.now() + JANELA_OTM };
  }
  pintarMeet();
  try { await canal.meetAcao(acao); if (acao === 'entrar') avisar(TEXTO_MEET.entrar) }
  catch (e) { delete otmMeet[acao]; tratarErro(e) }
  finally { mt.ocupado = null; pintarMeet(); lerMeet(); setTimeout(lerMeet, 800) }
}

$('#f-meet').addEventListener('click', ev => {
  const b = ev.target.closest('[data-mt]'); if (b && !b.disabled) return agirMeet(b.dataset.mt);
  if (ev.target.closest('[data-mt-tentar]')) { mt.erro = ''; mt.dados = null; pintarMeet(); lerMeet(); return }
  if (ev.target.closest('[data-mt-mac]')) abrirNoMac('meet', 'Abrindo o Meet no Mac');
});

/* aberta, a folha acompanha o Mac a cada 2 s (a pessoa também muta pelo próprio Meet) */
setInterval(() => {
  if (document.hidden || !V || V.carregando || semAcesso || offline || folhaAberta?.id !== 'f-meet' || mt.ocupado || mt.antigo) return;
  lerMeet();
}, 2000);
