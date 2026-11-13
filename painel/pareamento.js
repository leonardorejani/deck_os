/* Pareamento pela página (PWA no Safari do iPhone). O QR de Conectar iPhone leva ao endereço do Mac com
   o fragmento  #parear=<6 dígitos>&certificado=<link>  (SPEC, seção 9). Aqui a página:
     1. mostra o passo a passo para instalar e confiar no certificado do Deck (rota /ca.crt, SPEC seção 8)
     2. troca os 6 dígitos pelo código de acesso (POST /api/parear) e entra no painel
   Sem o fragmento (ícone da Tela de Início, que guarda os dados à parte do Safari), o botão da tela
   "Deck não pareado" abre o mesmo pedido, para digitar o código que o Mac mostra. No app nativo
   (window.DeckCanal) o pareamento é por cabo e Bluetooth, e esta tela nunca aparece. */

if (canal.parear) {
  const caixa = $('#t-parear'), corpo = $('#pa-corpo'), titulo = $('#pa-titulo'), CHAVE_PENDENTE = 'deck-parear-pendente';
  let pendente = null;   // { parear: "482913" | "", cert: bool }: o que o QR trouxe, na sessão da aba (some ao fechar)

  const sessao = {
    ler() { try { return JSON.parse(sessionStorage.getItem(CHAVE_PENDENTE)) } catch { return null } },
    gravar(v) { try { v ? sessionStorage.setItem(CHAVE_PENDENTE, JSON.stringify(v)) : sessionStorage.removeItem(CHAVE_PENDENTE) } catch {} },
  };
  const ehIphone = () => /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const instalado = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;

  function lerFragmento() {
    const h = new URLSearchParams(location.hash.replace(/^#/, '')), digitos = (h.get('parear') || '').replace(/\D/g, '');
    if (!digitos && !h.has('certificado')) return null;
    history.replaceState(null, '', location.pathname + location.search); // o código vale uma vez: não fica na barra nem no histórico
    // o certificado é sempre o desta mesma origem (/ca.crt): link vindo de fora do endereço do Mac nunca é seguido
    return { parear: /^\d{6}$/.test(digitos) ? digitos : '', cert: h.has('certificado') };
  }

  const PASSOS_CERT = [
    'Toque em <b>Baixar certificado</b> e depois em Permitir.',
    'Abra os <b>Ajustes</b> do iPhone, toque em Perfil Transferido e depois em Instalar.',
    'Vá em Ajustes &gt; Geral &gt; Sobre &gt; <b>Ajustes de Confiança de Certificados</b> e ligue o Deck.',
    'Volte aqui e toque em <b>Continuar</b>.',
  ];
  const PASSOS_INSTALAR = [
    'Toque no botão <b>Compartilhar</b> do Safari (o quadrado com a seta para cima).',
    'Escolha <b>Adicionar à Tela de Início</b>.',
    'Abra o Deck pelo ícone novo. Se ele pedir o código, digite o do Mac em Conexões, no método PWA.',
  ];
  const lista = passos => `<ol class="pa-passos">${passos.map(p => `<li>${p}</li>`).join('')}</ol>`;
  const botao = (acao, texto, classe = 'secundario') => `<button class="btn ${classe}" data-pa="${acao}">${texto}</button>`;

  const TELAS = {
    certificado: ({ erro }) => ({
      titulo: 'Instale o certificado do Deck',
      html: `${lista(PASSOS_CERT)}<p class="pa-nota">É um passo de um minuto, uma vez só. Sem ele o iPhone não deixa a tela acesa nem abre o painel com o Mac desligado.</p>${erro ? `<p class="pa-erro" role="alert">${esc(erro)}</p>` : ''}`,
      acoes: `<a class="btn primario" href="/ca.crt">Baixar certificado</a>${botao('continuar', 'Continuar')}`,
    }),
    codigo: ({ erro }) => ({
      titulo: 'Digite o código do Mac',
      html: `<p class="pa-nota">No Mac, abra o Deck, vá em Conexões, no método PWA, e digite aqui o código de 6 dígitos.</p>
        <div class="campo"><label for="pa-cod">Código</label><input id="pa-cod" inputmode="numeric" autocomplete="one-time-code" maxlength="7" placeholder="000 000" aria-describedby="pa-erro"></div>
        <p class="pa-erro" id="pa-erro" role="alert">${erro ? esc(erro) : ''}</p>`,
      acoes: `${botao('enviar', 'Parear', 'primario')}${botao('fechar', 'Cancelar')}`,
    }),
    ocupado: () => ({ titulo: 'Conectando ao Mac', html: '<p class="pa-nota">Só um instante.</p>', acoes: '' }),
    instalar: () => ({
      titulo: 'iPhone conectado',
      html: `<p class="pa-nota">Para abrir em tela cheia, como app:</p>${lista(PASSOS_INSTALAR)}`,
      acoes: botao('fechar', 'Abrir o painel', 'primario'),
    }),
  };

  function mostrar(nome, dados = {}) {
    const t = TELAS[nome](dados);
    titulo.textContent = t.titulo;
    corpo.innerHTML = `${t.html}<div class="pa-acoes">${t.acoes}</div>`;
    caixa.hidden = false;
    caixa.dataset.tela = nome;
    // foco no que a pessoa faz agora: o campo do código, ou o botão principal
    (nome === 'codigo' ? $('#pa-cod', corpo) : $('.btn.primario', corpo))?.focus({ preventScroll: true });
  }
  const fechar = () => { caixa.hidden = true; delete caixa.dataset.tela; pendente = null; sessao.gravar(null) };

  async function enviar(digitos) {
    mostrar('ocupado');
    try {
      await canal.parear(digitos);
    } catch (e) {
      // o código vale uma vez e conta como tentativa: depois de qualquer resposta do Mac ele não serve mais.
      // Falha de rede (Mac fora do ar, certificado ainda sem confiança) não gastou nada, o QR continua valendo
      if (e.rede && pendente?.parear) return mostrar('certificado', { erro: 'Não deu para falar com o Mac. Confira o Wi-Fi e se o Deck está ligado em Ajustes de Confiança de Certificados.' });
      pendente = null; sessao.gravar(null);
      return mostrar('codigo', { erro: e.message });
    }
    pendente = null; sessao.gravar(null);
    retomarAposParear();
    if (ehIphone() && !instalado()) return mostrar('instalar');
    fechar(); avisar('Pareado com o Mac');
  }

  corpo.addEventListener('click', ev => {
    const acao = ev.target.closest('[data-pa]')?.dataset.pa; if (!acao) return;
    if (acao === 'fechar') return fechar();
    if (acao === 'continuar') return pendente?.parear ? enviar(pendente.parear) : mostrar('codigo');
    if (acao === 'enviar') {
      const d = $('#pa-cod').value.replace(/\D/g, '');
      if (d.length !== 6) { $('#pa-erro').textContent = 'Digite os 6 dígitos que aparecem no Mac.'; return }
      enviar(d);
    }
  });
  corpo.addEventListener('keydown', ev => { if (ev.key === 'Enter' && ev.target.id === 'pa-cod') $('[data-pa="enviar"]', corpo).click() });
  // "482913" vira "482 913" enquanto digita
  corpo.addEventListener('input', ev => {
    if (ev.target.id !== 'pa-cod') return;
    const d = ev.target.value.replace(/\D/g, '').slice(0, 6);
    ev.target.value = d.length > 3 ? d.slice(0, 3) + ' ' + d.slice(3) : d;
  });

  // a tela "Deck não pareado" ganha a saída para digitar o código (o ícone da Tela de Início nasce sem o código do Safari)
  const digitar = $('#b-digitar');
  digitar.hidden = false;
  digitar.onclick = () => mostrar('codigo');

  pendente = lerFragmento() || sessao.ler();
  if (pendente) {
    sessao.gravar(pendente);
    if (pendente.cert) mostrar('certificado');
    else if (pendente.parear) enviar(pendente.parear);
    else mostrar('codigo');
  }
}
