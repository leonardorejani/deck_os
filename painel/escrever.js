/* Escrever no Mac: um campo de texto (que usa o ditado do teclado do iPhone) e o botão Enviar, que cola o texto no app
   que está em foco no Mac (POST /api/colar). O Mac guarda a prancheta, cola e devolve a prancheta, então nada do que a
   pessoa tinha copiado se perde. Sem app em foco aceitável o Mac recusa e o texto fica aqui, intacto, para tentar de novo.
   O texto só vive nesta folha: não vai para a config, para o armazenamento do navegador nem para o log.
   Usa as peças de deck.js (canal, avisar, abrirFolha, fecharFolha, tratarErro) e paineis.js (msgErro). */

const LIMITE_ESCREVER = 32000; // o mesmo teto do Mac
const es = { enviando: false };

const textoEscrever = () => $('#es-texto').value;
const cabeEscrever = () => textoEscrever().length > 0 && Array.from(textoEscrever()).length <= LIMITE_ESCREVER;

function pintarEscrever() {
  const n = Array.from(textoEscrever()).length;
  $('#es-enviar').disabled = es.enviando || !cabeEscrever();
  $('#es-enviar').textContent = es.enviando ? 'Enviando' : 'Enviar';
  // o contador só aparece perto do teto: na maior parte do tempo não há nada para contar
  const perto = n >= LIMITE_ESCREVER * .9;
  if (perto || n > LIMITE_ESCREVER) mensagemEscrever(n > LIMITE_ESCREVER ? `${n - LIMITE_ESCREVER} ${n - LIMITE_ESCREVER === 1 ? 'caractere' : 'caracteres'} a mais que o limite` : `${n} de ${LIMITE_ESCREVER}`, n > LIMITE_ESCREVER);
  else if (!$('#es-msg').classList.contains('erro')) mensagemEscrever('');
}
function mensagemEscrever(txt, erro = false) {
  const m = $('#es-msg'); m.textContent = txt; m.classList.toggle('erro', erro);
}

function abrirEscrever() {
  es.enviando = false; mensagemEscrever(''); pintarEscrever();
  abrirFolha('#f-escrever');
  $('#es-texto').focus({ preventScroll: true }); // dentro do toque que abriu: é o que faz o teclado (e o ditado) subir no iPhone
}

async function enviarEscrever() {
  if (es.enviando || !cabeEscrever()) return;
  es.enviando = true; mensagemEscrever(''); pintarEscrever();
  try {
    await canal.colar(textoEscrever());
    $('#es-texto').value = ''; es.enviando = false;
    fecharFolha(); avisar('Colado no Mac');
  } catch (e) {
    es.enviando = false;
    if (e.status === 401) { pintarEscrever(); return tratarErro(e) }
    // o texto fica no campo: nada se perde
    mensagemEscrever(e.status === 404 ? 'Este Mac ainda não escreve por aqui. Atualize o Deck no Mac.' : msgErro(e), true);
    pintarEscrever();
  }
}

$('#es-texto').addEventListener('input', () => { $('#es-msg').classList.remove('erro'); pintarEscrever() });
$('#es-enviar').addEventListener('click', enviarEscrever);
