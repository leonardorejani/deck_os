/* A ponte do app nativo: define window.DeckCanal, a interface que a página usa no lugar do HTTPS
   (ver painel/canal.js). Cada chamada vira uma mensagem para o Swift (WKScriptMessageHandlerWithReply),
   que leva o pedido pelo canal em uso (cabo ou Bluetooth) até o roteador do Mac.
   Roda antes dos scripts da página. O Swift define DECK_NATIVO_INICIO (o código guardado) antes disto. */
(function () {
  'use strict';
  const ponte = window.webkit.messageHandlers.deck;
  const inicio = window.DECK_NATIVO_INICIO || {};
  const tempoLimite = Object.assign({ tempoLimite: 5000 }, window.DECK_AJUSTES).tempoLimite; // o mesmo de painel/canal.js

  /* O código de acesso fica só na memória da página, e o Swift guarda a cópia no Keychain.
     Rodízio: quando o Mac troca o código, a resposta traz o novo e a página passa a usar ele. */
  let codigo = inicio.codigo || null;

  const falar = async msg => JSON.parse(await ponte.postMessage(msg));
  const erroDeCanal = (mensagem, status = 0, rede = false) => Object.assign(new Error(mensagem), { status, rede });

  /* Uma ida ao Mac. O código novo do rodízio é guardado aqui dentro, assim vale mesmo quando a resposta
     chega depois do limite de tempo da página (o Swift já gravou o mesmo código no Keychain). */
  async function enviar(metodo, caminho, query, corpo, cod) {
    const r = await falar({
      op: 'requisitar', metodo, caminho, query: query || {},
      cabecalhos: { 'X-Deck-Codigo': cod },
      corpo: corpo === undefined ? null : JSON.stringify(corpo),
    });
    if (r.codigoNovo) codigo = r.codigoNovo;
    return r;
  }

  async function pedir(metodo, caminho, query, corpo, tempoMax = tempoLimite) {
    // Sem código ainda (a tela de pareamento está aberta) ou sem Mac: a página mostra "Mac desconectado" e tenta de novo.
    if (!codigo) throw erroDeCanal('Não deu para falar com o Mac.', 0, true);
    let tempo;
    const limite = new Promise((_, falha) => { tempo = setTimeout(() => falha(erroDeCanal('O Mac demorou demais para responder.', 0, true)), tempoMax) });
    try {
      const corrida = (async () => {
        let usado = codigo;
        let r = await enviar(metodo, caminho, query, corpo, usado);
        if (r.status === 401 && !r.erro) {
          /* 401 com o código velho é rodízio em andamento (outra chamada já trouxe o novo, ou a resposta
             que trazia o novo estourou o tempo). Só esquece o Mac se o código atual também for recusado. */
          let atual = codigo;
          if (atual === usado) {
            const guardado = (await falar({ op: 'codigo' })).codigo;
            if (guardado && guardado !== usado) { codigo = guardado; atual = guardado }
          }
          if (atual && atual !== usado) r = await enviar(metodo, caminho, query, corpo, atual);
          if (r.status === 401 && !r.erro) falar({ op: 'acao', acao: 'esquecer' }); // o Mac não reconhece mais este iPhone: pareia de novo
        }
        return r;
      })();
      corrida.catch(() => {}); // a resposta atrasada ainda aplica o código novo, mesmo depois do limite
      const r = await Promise.race([corrida, limite]);
      if (r.erro === 'semCanal') throw erroDeCanal('Não deu para falar com o Mac.', 0, true);
      if (r.erro) throw erroDeCanal(r.mensagem || 'Não deu para falar com o Mac.', 0, true);
      let dados = null;
      try { dados = JSON.parse(r.corpo) } catch {}
      if (r.status < 200 || r.status >= 300) throw erroDeCanal(dados?.erro || 'O Mac não conseguiu fazer isso.', r.status);
      return dados;
    } finally { clearTimeout(tempo) }
  }

  window.DeckCanal = {
    nativo: true,
    estado: () => pedir('GET', '/api/estado'),
    botao: id => pedir('POST', '/api/botao/' + encodeURIComponent(id)),
    spotify: (acao, valor) => pedir('POST', '/api/spotify/' + encodeURIComponent(acao), acao === 'posicao' ? { s: String(valor) } : (acao === 'repetir' || acao === 'aleatorio') && valor !== undefined ? { v: valor ? '1' : '0' } : undefined),
    spotifyVolume: (v, alvo) => pedir('POST', '/api/spotify/volume', { v: String(v), alvo: String(alvo) }),
    aparelhos: () => pedir('GET', '/api/spotify/dispositivos'),
    transferir: id => pedir('POST', '/api/spotify/dispositivo', { id: String(id) }),
    curtir: curtir => pedir('POST', '/api/spotify/curtir', { v: curtir ? '1' : '0' }),
    fila: () => pedir('GET', '/api/spotify/fila'),
    repetirModo: modo => pedir('POST', '/api/spotify/repetir', { modo: String(modo) }),
    config: () => pedir('GET', '/api/config'),
    gravarConfig: config => pedir('PUT', '/api/config', undefined, config),
    whatsapp: () => pedir('GET', '/api/whatsapp'),
    agenda: (de, dias) => pedir('GET', '/api/agenda', { de: String(de), dias: String(dias) }),
    sessoes: () => pedir('GET', '/api/sessoes'),
    abrirSessao: id => pedir('POST', '/api/sessoes/' + encodeURIComponent(id) + '/abrir'),
    entrarNaReuniao: link => pedir('POST', '/api/reuniao/entrar', undefined, { link }),
    controles: () => pedir('GET', '/api/controles'),
    controle: (item, v) => pedir('POST', '/api/controles/' + encodeURIComponent(item), { v: String(v) }),
    apps: () => pedir('GET', '/api/apps'),
    acoesDoApp: bundle => pedir('GET', '/api/apps/' + encodeURIComponent(bundle) + '/acoes', undefined, undefined, 15000), // ler as contas do Mail pode levar uns 8 s
    // o ícone de um app do Mac (editor de tecla): também numa <img>, pelo mesmo esquema. O app do iPhone guarda por um dia
    appIconeUrl: bundle => `deckcapa://apps/${encodeURIComponent(bundle)}/icone?codigo=${encodeURIComponent(codigo || '')}`,
    // <img> não manda cabeçalho: o Swift atende deckcapa:// com o canal em uso, e o capaId troca a imagem só quando ela muda
    capaUrl: capaId => `deckcapa://capa/?codigo=${encodeURIComponent(codigo || '')}&v=${encodeURIComponent(capaId || '')}`,
    /* Extras do app nativo. A vibração leve do toque de tecla o Swift já faz em botao(), antes de o Mac responder. */
    vibrar: () => { ponte.postMessage({ op: 'vibrar' }) },
    // chamado pelo Swift: um código novo (pareamento feito ou rodízio vindo pela capa)
    codigo: novo => { codigo = novo || null },
  };
})();
