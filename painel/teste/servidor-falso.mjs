// Mac de mentira para testar o painel: serve a página e implementa as rotas do contrato
// (mac/Nucleo/Modelos.swift) com dados de exemplo. Só módulos nativos do node.
// O cenário troca por uma rota que só existe aqui: POST /__cenario com um JSON parcial, GET /__cenario
// para ler o cenário e os contadores, POST /__reset para voltar ao começo.
//   node painel/teste/servidor-falso.mjs 4881      ->  http://localhost:4881/?codigo=ABCDEFGHJKLMNPQRSTUV
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const CODIGO = 'ABCDEFGHJKLMNPQRSTUV';
export const CODIGO_NOVO = 'NOVOCODIGOGIRADOPELO';  // o que o rodízio do Mac gera (mac/Nucleo/Rodizio.swift)
const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CODIGO_PAREAR = '482913';  // os 6 dígitos que o Mac mostra em Conectar iPhone (vale uma vez, como o Pareamento.swift)
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.json': 'application/json', '.webmanifest': 'application/manifest+json' };

const padrao = () => ({
  mac: 'on',                 // on | off (o Mac nem atende)
  pendurar: false,           // o Mac atende e nunca responde o estado
  atraso: 0,                 // ms de espera antes de responder o estado
  spotify: 'tocando',        // tocando | pausado | fechado
  agenda: 'normal',          // normal | vazia | sem | muitas (um dia lotado) | erro (a rota falha)
  sessoes: 5,                // 0 a 12
  sessaoMuda: false,         // a primeira sessão chega com outra pergunta (ela mudou)
  whatsapp: 'normal',        // normal | vazio | muitas (30 conversas) | erro (a rota falha)
  whatsappFotos: 0,          // quantas conversas extras com foto de perfil (para medir o pico de pedidos juntos)
  fotoFalhaPrimeira: false,  // o 1o pedido de cada foto de perfil dá erro 500 (rede ruim)
  abrirAtraso: 0,            // espera, em ms, antes de responder o Responder no Mac (abre a conversa pela busca da página)
  fotoAtraso: 0,             // espera, em ms, antes de responder cada foto de perfil
  whatsappRico: false,       // lista do aparelho conectado com foto, áudio, visualização única, arquivada e conversa sem nome (precisa de whatsappOrigem 'qr')
  whatsappVersao: null,      // número: o Mac por QR dá versão à lista (?v=<versão> igual responde só {igual}). null: Mac sem versão, a lista vai sempre inteira
  whatsappExtra: false,      // chega uma conversa nova na lista (mede a velocidade com que a folha aberta a mostra)
  whatsappOrigem: 'app',     // app | web (só o total, pelo título da aba) | web-fechado (sem aba aberta) | qr (aparelho conectado, com lista) | qr-caido | qr-reconectando (subindo ou queda curta, sem lista) | qr-reconectando-lista (queda curta com a lista de antes)
  uso: 'normal',             // normal | sem-medicao
  usoDetalhe: 'normal',      // normal | calculando (a primeira varredura ainda roda) | vazio (sem contas) | erro (500) | antigo (Mac sem a rota: 404) | xss (nomes com HTML)
  relogioMs: 0,              // adianta o relógio do Mac (o "há X min" das sessões anda)
  atrasoListas: 0,           // ms de espera nas listas de WhatsApp e Agenda
  textoLongo: false,         // URL e caminho de arquivo sem espaço nas mensagens e nas perguntas
  perguntaGigante: false,    // a pergunta da primeira sessão é um texto de 40 linhas (a sessão aberta tem que rolar)
  comAcao: false,            // uma tecla de Calendário com acao (calendario-dia): vai pro Mac, não abre a lista do iPhone
  falha: false,              // toda tecla falha com o motivo do Mac
  teclas: 'poucas',          // poucas (4) | muitas (12)
  perfis: 'um',              // um | dois
  comp: 'a',
  blocos: { spotify: true, agenda: true, whatsapp: true, sessoes: true, uso: true },
  monitorItens: { cpu: true, memoria: true, bateria: true, rede: true, gpu: true, disco: true, energia: true, ventoinhas: true, dispositivos: true }, // o que a pessoa deixou ligado nos Ajustes do Mac
  monitor: { cpu: 12, memoria: 63, bateria: 81, naTomada: false, baixa: 1258291, sobe: 40960, gpu: 27, discoLivre: 412000000000, discoTotal: 994000000000, watts: 11.4, carregando: false, ventoinhas: [2400, 2600], ventoinhaMax: 6000, dispositivos: 3 }, // o que o Mac mediu (sem `bateria` = Mac de mesa, e o que falta some)
  nomeMac: 'MacBook Pro de Teste',
  faixa: 'Faixa de Exemplo', artista: 'Artista Exemplo',
  acesas: ['acordado'],
  xss: false,                // texto do Mac, do WhatsApp e das sessões chega com HTML malicioso
  config500: false,          // GET /api/config responde erro 500
  rejeitar: '',              // PUT /api/config recusa com esse motivo (422), como a validação do Mac
  rodizio: '',               // trocar (o primeiro pedido troca o código) | botao (só um pedido de tecla troca)
  atrasoGravar: 0,           // ms de espera antes de o Mac aceitar o PUT /api/config
  atrasoAcao: 0,             // ms de espera antes de o Mac fazer uma tecla (POST /api/botao) ou um comando do Spotify
  spotifyRecusa: '',         // todo comando do Spotify é recusado (422) com esse motivo
  album: 'Artista Exemplo (Deluxe)', repetir: false, aleatorio: false,
  agendaCriar: 'normal',     // normal | antigo (Mac sem as rotas de criar: 404) | lembretes-pedir (Lembretes ainda sem acesso: o pedido abre no Mac) | recusa (o Mac recusa o compromisso, 409)
  reunioes: false,           // os eventos de Meet, Zoom e Teams chegam com o link da sala (Evento.link)
  reuniaoRecusa: '',         // POST /api/reuniao/entrar falha (422) com esse motivo
  sessaoAbre: 'terminal',    // o que "Abrir no Mac" de uma sessão fez: terminal (trouxe o app do terminal) | pasta (abriu o Terminal na pasta)
  sessaoAbreRecusa: '',      // POST /api/sessoes/<id>/abrir falha (422) com esse motivo
  spotifyExtras: 'nao',      // nao (Mac antigo: sem volume nem login) | volume (só o do Spotify) | dois (Spotify e Mac) | login (conectado: curtir, aparelhos, fila e repetir só a música)
  volume: 60, volumeMac: 40, curtida: false, repetirFaixa: false, aparelhoAtivo: 'd-mac', volumeAparelho: 35,
  filaVazia: false,          // GET /api/spotify/fila devolve a fila sem próximas
  filaContexto: '',          // nome da lista que toca ("Próximas de: ..."). Vazio: o Mac não soube dizer
  filaRecusa: '',            // POST /api/spotify/pular falha (422) com esse motivo
  aparelhosErro: '',         // GET /api/spotify/dispositivos falha (500) com esse motivo
  apps: 'antigo',            // antigo (Mac sem as rotas de apps: 404, o editor usa a lista curta) | normal | erro (a lista falha com 500) | muitos (140 apps)
  acoesAtraso: 0,            // ms de espera antes de o Mac responder o que um app oferece (ler as contas do Mail demora)
  mailAviso: '',             // a lista de contas do Mail não pôde ser lida: o motivo vem no aviso da ação
  comFoco: false,            // o perfil ganha uma tecla de comando com liga e desliga (sem comando de conferir: o Mac guarda o estado)
  comandoLento: 0,           // ms que o comando da tecla de comando demora no Mac: o Mac responde na hora e mostra `andamento` até acabar
  comandoFalha: '',          // o comando lento termina com esse erro (vai pelo `andamento`)
  comControles: false,       // o perfil ganha a tecla Controles (abre a tela dos controles do Mac no iPhone)
  controles: 'tudo',         // tudo | sem-brilho (Mac sem tela interna nem luz no teclado) | nada (não oferece nada) | antigo (Mac sem a rota: 404) | erro (500) | recusa (os pedidos de escrita falham com 422)
  comReuniao: false,         // o perfil ganha as teclas Mutar (microfone) e Câmera do Meet no navegador, e o estado delas chega em `reuniao`
  reuniaoEstado: { mic: 'ligado', cam: 'desligado' }, // ligado | desligado | desconhecido | sem-reuniao (o que o Mac leu). null: Mac antigo, não manda `reuniao`
  comMeet: false,            // o perfil ganha a tecla única "Google Meet" (abre a central do Meet no iPhone)
  meet: 'normal',            // normal | antigo (Mac sem a rota: 404) | erro (500) | recusa (as ações falham com 422)
  meetEstado: { aberta: true, naChamada: true, microfone: 'ligado', camera: 'desligado' }, // o que o Mac leu da reunião
  meetAtraso: 0,             // ms de espera antes de o Mac fazer uma ação do Meet
  comMonitorApp: false,      // o perfil ganha a tecla do app Monitor de Atividade (abre a tela do monitor no iPhone)
  ctVolume: 30, ctMudo: false, ctBrilho: 60, ctTeclado: 20, ctAtraso: 0,
  spotifyModos: 'sim',       // sim | sem (Mac antigo: o estado não traz álbum, repetir nem aleatório)
});
let c = padrao();
let T0 = Date.now(); // as sessões esperam desde um instante fixo (o Mac real manda sempre o mesmo `desde` até a sessão mudar)
let cont = { estado: 0, simultaneos: 0, maxSimultaneos: 0, botoes: [], spotify: [], configsGravadas: [], codigos: [], capas: 0, whatsapp: 0, whatsappV: [], whatsappIguais: 0, sessoes: 0, agenda: [], parear: [], ca: 0, reunioes: [], sessoesAbertas: [], aparelhos: 0, filas: 0, apps: 0, acoesApp: [], icones: [], criados: [], destinosPedidos: 0, controles: [], whatsappAbertas: [], midias: [], fotos: [], meetAcoes: [], meetLeituras: 0, usoDetalhe: [] };
let posicaoBase = { s: 132, desde: Date.now() };
let perfilAtivo = 'trabalho';
let criadosAgenda = [], padraoAgenda = null, lembretesAcesso = null, liberarEm = 0; // o que o iPhone criou na agenda, o destino padrão e o acesso aos Lembretes
let codigoAtual = CODIGO, codigoAnterior = null; // rodízio: o atual, e o anterior que ainda vale (a folga de 10 min)
let parearGasto = false, parearErros = 0; // o código de 6 dígitos serve uma vez e aguenta 5 erros
let gravada = null; // o que o iPhone gravou: perfis e blocos, como o Mac guardaria no config.json
const zerar = () => { parearGasto = false; parearErros = 0; codigoAtual = CODIGO; codigoAnterior = null; T0 = Date.now(); gravada = null; c = padrao(); cont = { estado: 0, simultaneos: 0, maxSimultaneos: 0, botoes: [], spotify: [], configsGravadas: [], codigos: [], capas: 0, whatsapp: 0, whatsappV: [], whatsappIguais: 0, sessoes: 0, agenda: [], parear: [], ca: 0, reunioes: [], sessoesAbertas: [], aparelhos: 0, filas: 0, apps: 0, acoesApp: [], icones: [], criados: [], destinosPedidos: 0, controles: [], whatsappAbertas: [], midias: [], fotos: [], meetAcoes: [], meetLeituras: 0, usoDetalhe: [] }; posicaoBase = { s: 132, desde: Date.now() }; perfilAtivo = 'trabalho'; criadosAgenda = []; padraoAgenda = null; lembretesAcesso = null };

// com xss ligado, todo texto que a página mostra chega como HTML que tenta executar código
const X = t => c.xss ? `"><img src=x onerror="window.__xss=(window.__xss||0)+1">${t}` : t;
const T = (id, nome, tipo, valor, extra = {}) => ({ id, nome, tipo, valor, ...extra });
function perfisConfig() {
  if (gravada) return gravada.perfis;
  const trabalho = [
    T('acordado', X('Manter acordado'), 'tecla', 'ctrl+opt+cmd+k', { estado: "pmset -g assertions | grep -q 'Vorssaint'", icone: 'Vorssaint' }),
    T('whatsapp', X('WhatsApp'), 'app', 'WhatsApp', { icone: c.xss ? X('x') : 'WhatsApp' }),
    T('calendario', 'Agenda', 'app', 'Calendar', { icone: 'Calendar' }),
    T('apagar', 'Apagar tela', 'comando', 'pmset displaysleepnow', { icone: 'svg:tela' }),
  ];
  if (c.comReuniao) trabalho.push(T('mic', 'Mutar', 'app', 'Google Meet', { icone: 'svg:video', acao: { id: 'reuniao-microfone' } }), T('cam', 'Câmera', 'app', 'Google Meet', { icone: 'svg:video', acao: { id: 'reuniao-camera' } }));
  if (c.comMeet) trabalho.push(T('meet', 'Google Meet', 'app', 'Google Meet', { icone: 'svg:video' }));
  if (c.comMonitorApp) trabalho.push(T('monitor', 'Monitor', 'app', 'Activity Monitor', { icone: 'Activity Monitor' }));
  if (c.comFoco) trabalho.push(T('foco', 'Mudar foco', 'comando', 'foco jogo', { icone: 'svg:tela', desligar: 'foco trabalho' }));
  if (c.comControles) trabalho.push(T('controles', 'Controles', 'app', 'Controles', { icone: 'svg:controles' }));
  if (c.comAcao) trabalho.push(T('cal-dia', 'Natal', 'app', 'Calendar', { icone: 'Calendar', acao: { id: 'calendario-dia', valor: '2026-12-25' } }));
  if (c.teclas === 'muitas') for (const n of ['Safari', 'Notes', 'Terminal', 'Finder', 'Spotify', 'Vorssaint', 'WhatsApp', 'Calendar']) trabalho.push(T('x' + n, n === 'Notes' ? 'Notas' : n, 'app', n, { icone: n }));
  const ensaio = [T('e-spotify', 'Spotify', 'app', 'Spotify', { icone: 'Spotify' }), T('e-cifras', 'Cifras', 'app', 'Notes', { icone: 'Notes' }), T('e-agenda', 'Agenda', 'app', 'Calendar', { icone: 'Calendar' }), T('e-apagar', 'Apagar tela', 'comando', 'pmset displaysleepnow', { icone: 'svg:tela' }), T('e-terminal', 'Terminal', 'app', 'Terminal', { icone: 'Terminal' })];
  return c.perfis === 'dois' ? [{ id: 'trabalho', nome: X('Trabalho'), teclas: trabalho }, { id: 'ensaio', nome: 'Ensaio', teclas: ensaio }] : [{ id: 'trabalho', nome: X('Trabalho'), teclas: trabalho }];
}
const contas = () => [
  { id: 'claude-leo', nome: 'Claude', conta: X('leo'), mostrar: true },
  { id: 'claude-equipe', nome: 'Claude', conta: 'equipe', mostrar: true },
  { id: 'codex', nome: 'Codex', conta: 'pro', mostrar: true },
];
const configCompleta = () => ({ versao: 1, perfis: perfisConfig(), perfilAtivo: perfilAtivo === 'ensaio' && c.perfis === 'dois' ? 'ensaio' : 'trabalho', comp: c.comp, contas: contas(), blocos: c.blocos, monitor: c.monitorItens, nomeMac: X(c.nomeMac), porta: 4777 });

const emDias = (dias, h, m = 0) => { const d = new Date(); d.setDate(d.getDate() + dias); d.setHours(h, m, 0, 0); return d.toISOString() };
/* O detalhe do uso das IAs (GET /api/uso/detalhe). Números inventados, no formato do Mac. O mês inteiro de tokens só para dar volume ao gráfico */
function detalheUso(periodo) {
  const n = { dia: 24, semana: 7, mes: 30 }[periodo] || 7, k = { dia: 1, semana: 7, mes: 30 }[periodo] || 7;
  const serie = Array.from({ length: n }, (_, i) => periodo === 'dia' && i > new Date().getHours() ? 0 : Math.round((i % 5 + 1) * 1.8e6 * (periodo === 'dia' ? 1 : 3)));
  const soma = serie.reduce((a, b) => a + b, 0);
  const gasto = (rot, mult) => ({ entrada: Math.round(soma * .02 * mult), saida: Math.round(soma * .03 * mult), cacheLeitura: Math.round(soma * .85 * mult), cacheEscrita: Math.round(soma * .1 * mult), total: Math.round(soma * mult), turnos: 40 * k, sessoes: 3 * k > 9 ? 9 : 3 * k,
    custo: Math.round(soma * mult / 1e6 * 2.1 * 100) / 100, custoParcial: true, serie: serie.map(v => Math.round(v * mult)),
    modelos: [{ nome: 'Opus 5.5', tokens: Math.round(soma * mult * .6), custo: Math.round(soma * mult / 1e6 * 1.5 * 100) / 100, parte: 60 }, { nome: 'Sonnet 5.5', tokens: Math.round(soma * mult * .3), custo: Math.round(soma * mult / 1e6 * .6 * 100) / 100, parte: 30 }, { nome: 'modelo-a', tokens: Math.round(soma * mult * .1), parte: 10 }] });
  if (c.usoDetalhe === 'vazio') return { periodo, ate: ateHoje(), contas: [] };
  const semMed = c.uso === 'sem-medicao', ritmo = { esperado: 50, projecao: 140, situacao: 'rapido' };
  const nome = t => c.usoDetalhe === 'xss' ? '<img src=x onerror=window.__xss=1>' : t;
  return { periodo, atualizadoEm: new Date(Date.now() - 90000).toISOString(), ...(c.usoDetalhe === 'calculando' ? { calculando: true } : {}), ate: ateHoje(),
    contas: [
      { id: 'claude-leo', nome: 'Claude', conta: nome('leo'), janelas: semMed ? [] : [{ rotulo: 'Semana', percentual: 61, renova: emDias(3, 14), medidoEm: new Date(Date.now() - 180000).toISOString(), ritmo: { esperado: 55, projecao: 111, situacao: 'rapido' } }] },
      { id: 'claude-equipe', nome: 'Claude', conta: 'equipe', janelas: semMed ? [] : [{ rotulo: 'Semana', percentual: 94, renova: emDias(1, 9), ritmo }] },
      { id: 'codex', nome: 'Codex', conta: 'pro', janelas: semMed ? [] : [{ rotulo: '5 horas', percentual: 20, renova: emDias(0, 23), medidoEm: new Date(Date.now() - 600000).toISOString(), ritmo: { esperado: 30, projecao: 66 } }, { rotulo: 'Semana', percentual: 4, renova: emDias(0, 23), ritmo: { esperado: 90, projecao: 5, situacao: 'sobra' } }],
        gasto: c.usoDetalhe === 'calculando' ? { ...gasto('c', 0), modelos: [] } : { ...gasto('c', .4), modelos: [{ nome: 'GPT-5.5-codex', tokens: Math.round(soma * .4), custo: 3.2, parte: 100 }] } },
    ],
    claudeMac: gasto('mac', c.usoDetalhe === 'calculando' ? 0 : 1) };
}
const ateHoje = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` };

const SESSOES = () => [...SESSOES_BASE(), ...Array.from({ length: 7 }, (_, i) => ({ id: 's' + (6 + i), nome: 'sessão extra ' + (i + 1), projeto: 'projeto_' + (i + 1), pergunta: 'Pergunta longa da sessão extra ' + (i + 1) + ', com bastante texto para passar de duas linhas na lista e mostrar inteira só quando a pessoa tocar em Responder, sem cortar nada. '.repeat(4), desde: new Date(T0 - (5 + i) * 86400000).toISOString() }))];
const SESSOES_BASE = () => [
  { id: 's1', nome: X('convite novos usuarios'), projeto: X('app_web'), pergunta: c.perguntaGigante ? Array.from({ length: 40 }, (_, i) => `Linha ${i + 1} da pergunta: posso seguir com o plano e abrir o PR agora?`).join('\n') : c.textoLongo ? 'Posso editar /Users/exemplo/projeto/painel/paineis.js agora?' : X(c.sessaoMuda ? 'Agora pode salvar o TXT no DNS?' : 'Salvar o TXT de verificação do domínio no DNS?'), desde: new Date(T0 - 5 * 60000).toISOString() },
  { id: 's2', nome: 'EXPORTAR_VIDEO_1080', projeto: 'video', pergunta: '1080p medido, aguarda decisão sobre times, PR e vídeo.', desde: new Date(T0 - 13 * 3600000).toISOString(),
    pedido: 'Escolha: A reserva 2 das 4 vagas para reuniões, B times em 540p, ou C vídeo dos times no node01. Depois diga se abro o PR rascunho.', sugestao: 'A, e pode abrir o PR rascunho',
    contexto: c.xss ? '<img src=x onerror=window.__xss=1> **negrito** `codigo`' : 'needs input ficou claro.\n\n## O que foi medido\n\n| Item | Valor |\n|---|---|\n| 1080p | 4 vagas |\n| 540p | 9 vagas |\n\nCom **A** sobram 2 vagas para as reuniões, usando `tc` no wg0.' },
  { id: 's3', nome: 'CI_RUNNER_02', projeto: 'infra', pergunta: 'Você aprova o plano do runner 02 (e2e do ci-1)?', desde: new Date(T0 - 14 * 3600000).toISOString() },
  { id: 's4', nome: 'instala repo', projeto: 'app_web', pergunta: 'Registro essa conclusão na memória do projeto?', desde: new Date(T0 - 16 * 3600000).toISOString() },
  { id: 's5', nome: 'podio ranking pontuação', projeto: 'app_web', pergunta: 'Posso fazer o commit e abrir o PR?', desde: new Date(T0 - 4 * 86400000).toISOString() },
];

// Imagem e áudio de mentira (1 pixel e 0,1 s de silêncio) para a folha do WhatsApp por QR
const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const WAV_B64 = (() => { const n = 800, b = Buffer.alloc(44 + n); b.write('RIFF', 0); b.writeUInt32LE(36 + n, 4); b.write('WAVEfmt ', 8); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(8000, 24); b.writeUInt32LE(8000, 28); b.writeUInt16LE(1, 32); b.writeUInt16LE(8, 34); b.write('data', 36); b.writeUInt32LE(n, 40); b.fill(128, 44); return b.toString('base64') })();
const WHATSAPP_RICO = () => {
  const ha = min => new Date(T0 - min * 60000).toISOString(), M = (texto, min, extra = {}) => ({ de: '', texto, hora: ha(min), ...extra });
  return [
    { id: 'r1@s.whatsapp.net', nome: 'Ana Souza', grupo: false, naoLidas: 3, ultima: ha(2), numero: '5544999990001', foto: '0123456789abcdef.jpg', mensagens: [M('Oi, tudo bem?', 6), M('Foto', 4, { id: 'F1', tipo: 'foto', midia: true }), M('Áudio', 3, { id: 'A1', tipo: 'audio', midia: true })] },
    { id: 'r2@lid', nome: '+55 44 99999-0002', grupo: false, naoLidas: 2, ultima: ha(10), numero: '5544999990002', mensagens: [M('Foto única', 12, { id: 'U1', tipo: 'foto', unica: true }), M('Áudio único', 11, { id: 'U2', tipo: 'audio', unica: true })] },
    { id: 'g1@g.us', nome: 'Louvor', grupo: true, naoLidas: 1, ultima: ha(30), mensagens: [{ de: 'Carla', texto: 'Ensaio confirmado', hora: ha(30) }] },
    { id: 'sn@lid', nome: '', grupo: false, naoLidas: 1, ultima: ha(40), mensagens: [M('Alguém sem nome salvo', 40)] },
    { id: 'arq@s.whatsapp.net', nome: 'Bia Arquivada', grupo: false, naoLidas: 4, ultima: ha(50), arquivada: true, mensagens: [M('Mensagem de conversa arquivada', 50)] },
    ...Array.from({ length: c.whatsappFotos }, (_, i) => ({ id: 'f' + i + '@s.whatsapp.net', nome: 'Foto ' + (i + 1), grupo: false, naoLidas: 1, ultima: ha(60 + i), foto: i.toString(16).padStart(16, 'a') + '.jpg', mensagens: [M('Oi ' + i, 60 + i)] })),
    ...(c.whatsappExtra ? [{ id: 'novo@s.whatsapp.net', nome: 'Chegou Agora', grupo: false, naoLidas: 1, ultima: ha(0), mensagens: [M('Acabou de chegar', 0)] }] : []),
  ];
};
// WhatsApp: as 5 conversas do protótipo (o tempo é relativo a agora, para "hoje" e "ontem" não envelhecerem)
const WHATSAPP = () => {
  if (c.whatsapp === 'vazio') return [];
  if (c.whatsappRico) return WHATSAPP_RICO();
  const ha = min => new Date(T0 - min * 60000).toISOString(), M = (de, texto, hora = '10:00') => ({ de: X(de), texto: X(texto), hora });
  const base = [
    { id: 'w1', nome: X('Ministério de Louvor'), grupo: true, naoLidas: 12, ultima: ha(3), mensagens: [M('Carla', c.textoLongo ? 'Olha o PR: https://github.com/leonardorejani/deck_os/pull/30/files#diff-8f3b2c1d9e7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e' : 'Ensaio confirmado quinta 20h?'), M('Pedro', 'Mandei a setlist no drive'), M('Carla', 'Quem leva o cabo P10?')] },
    { id: 'w2', nome: 'Mãe', grupo: false, naoLidas: 2, ultima: ha(20), mensagens: [M('', 'Vem almoçar domingo?'), M('', 'Traz a Bia também')] },
    { id: 'w3', nome: 'Equipe do app', grupo: true, naoLidas: 5, ultima: ha(40), mensagens: [M('Rafael', 'Subi o build novo'), M('Lucas', 'Testei no Android, ok')] },
    { id: 'w4', nome: 'Pastor João', grupo: false, naoLidas: 3, ultima: emDias(-1, 12), mensagens: [M('', 'Leo, sobre domingo...'), M('', 'Me liga quando puder')] },
    { id: 'w5', nome: 'Rafael', grupo: false, naoLidas: 1, ultima: emDias(-1, 11), mensagens: [M('', 'Consegue ver o PR hoje?')] },
  ];
  if (c.whatsapp !== 'muitas') return base;
  return [...base, ...Array.from({ length: 25 }, (_, i) => ({ id: 'wx' + i, nome: 'Contato ' + (i + 1), grupo: i % 4 === 0, naoLidas: 1 + i % 3, ultima: ha(60 + i * 90), mensagens: [M(i % 4 === 0 ? 'Alguém' : '', 'Mensagem número ' + (i + 1))] }))];
};

// Agenda: eventos semanais e avulsos por dia do mês (como o protótipo), devolvidos para o intervalo pedido
const AZUL = '#60A5FA', VERDE = '#5FD49B', AMARELO = '#E8B95B', ROSA = '#F09090';
const mesmoDiaF = (a, b) => a.toDateString() === b.toDateString();
function eventosDoDia(d) {
  const dow = d.getDay(), dia = d.getDate(), ev = [], E = (h, m, titulo, cor, calendario, local, diaTodo = false, link = '') => { const q = new Date(d); q.setHours(h, m, 0, 0); ev.push({ titulo: X(titulo), inicio: q.toISOString(), diaTodo, calendario: X(calendario), cor, ...(local ? { local: X(local) } : {}), ...(link && c.reunioes ? { link } : {}) }) };
  if (dow === 2) E(10, 30, 'Reunião de produto', AZUL, 'Trabalho', 'Google Meet', false, 'https://meet.google.com/abc-defg-hij');
  if (dow === 4) E(20, 0, 'Ensaio do louvor', VERDE, 'Louvor', 'Templo');
  if (dow === 0) { E(9, 0, 'Escola dominical', AMARELO, 'Igreja', 'Sala 2'); E(19, 0, 'Culto', AMARELO, 'Igreja', 'Templo') }
  const avulsos = { 3: [14, 0, 'Revisão do projeto', AZUL, 'Trabalho', c.reunioes ? 'https://us02web.zoom.us/j/81234567890?pwd=abc123' : '', false, 'https://us02web.zoom.us/j/81234567890?pwd=abc123'], 10: [16, 0, 'Dentista', ROSA, 'Pessoal'], 12: [12, 30, 'Almoço com Rafael', VERDE, 'Trabalho'], 15: [0, 0, 'Aniversário da Ana', ROSA, 'Pessoal', '', true], 21: [15, 0, 'Gravação do podcast', AZUL, 'Trabalho', '', false, 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc'], 27: [18, 0, 'Entrega do cliente', AZUL, 'Trabalho'] };
  if (avulsos[dia]) E(...avulsos[dia]);
  const chaveDia = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  for (const n of criadosAgenda) if (n.dia === chaveDia) { const [h, mi] = (n.inicio || '00:00').split(':').map(Number); E(h, mi, n.titulo, VERDE, n.calendario, '', !!n.diaTodo) }
  if (c.agenda === 'muitas' && mesmoDiaF(d, new Date(Date.now() + 86400000))) for (let i = 0; i < 14; i++) E(7 + i, 0, 'Compromisso ' + (i + 1), AZUL, 'Trabalho', 'Sala ' + (i + 1));
  return ev;
}
function eventos(de, dias) {
  const [a, m, di] = String(de).split('-').map(Number), lista = [];
  for (let i = 0; i < (dias || 0); i++) lista.push(...eventosDoDia(new Date(a, m - 1, di + i)));
  return lista;
}
const aparelhos = () => [
  { id: 'd-mac', nome: X('MacBook Pro de Teste'), tipo: 'computer', ativo: c.aparelhoAtivo === 'd-mac', volume: c.aparelhoAtivo === 'd-mac' ? c.volumeAparelho : 60, restrito: false },
  { id: 'd-sala', nome: X('Caixa da sala'), tipo: 'speaker', ativo: c.aparelhoAtivo === 'd-sala', volume: c.aparelhoAtivo === 'd-sala' ? c.volumeAparelho : 35, restrito: false },
  { id: 'd-tv', nome: 'TV do quarto', tipo: 'tv', ativo: false, volume: null, restrito: true },
  { id: 'd-cel', nome: 'Celular', tipo: 'smartphone', ativo: c.aparelhoAtivo === 'd-cel', volume: null, restrito: false },
];
const CAPA_FILA = i => `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="hsl(${i * 40} 50% 40%)"/></svg>`)}`;
const proximasDaFila = () => c.filaVazia ? [] : Array.from({ length: 9 }, (_, i) => ({ faixa: X('Próxima música ' + (i + 1)), artista: i % 3 === 0 ? 'Artista Exemplo, Convidado' : 'Banda ' + (i + 1), uri: 'spotify:track:p' + (i + 1), capa: CAPA_FILA(i + 1) })).slice(c.filaPulou || 0);
const FILA = () => ({ atual: { faixa: X('Faixa de Exemplo'), artista: X('Artista Exemplo') }, proximas: proximasDaFila(), ...(c.filaContexto ? { contexto: X(c.filaContexto) } : {}) });
// os apps do Mac de quem usa (GET /api/apps) e o que cada um oferece (GET /api/apps/<id>/acoes), como o Apps.swift e o AcoesDeApp.swift
const APPS_MAC = () => [
  ...[['Calculadora', 'Calculator', 'com.apple.calculator'], ['Calendário', 'Calendar', 'com.apple.iCal'], ['Finder', 'Finder', 'com.apple.finder'], ['Mail', 'Mail', 'com.apple.mail'], ['Notas', 'Notes', 'com.apple.Notes'], ['Terminal', 'Terminal', 'com.apple.Terminal'], ['WhatsApp', 'WhatsApp', 'net.whatsapp.WhatsApp'], ['Spotify', 'Spotify', 'com.spotify.client']]
    .map(([nome, valor, bundle]) => ({ nome: X(nome), valor, bundle, navegador: false })),
  { nome: 'Google Chrome', valor: 'Google Chrome', bundle: 'com.google.Chrome', navegador: true }, { nome: 'Safari', valor: 'Safari', bundle: 'com.apple.Safari', navegador: true },
  ...(c.apps === 'muitos' ? Array.from({ length: 130 }, (_, i) => ({ nome: 'Aplicativo ' + String(i + 1).padStart(3, '0'), valor: 'App' + (i + 1), bundle: 'com.exemplo.app' + (i + 1), navegador: false })) : []),
].sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'));
const ACAO_LINK = { id: 'link', nome: 'Abrir um endereço', entrada: 'texto', rotulo: 'Endereço', exemplo: 'https://github.com' };
const ACAO_GMAIL = { id: 'gmail', nome: 'Abrir o Gmail de uma conta', entrada: 'texto', rotulo: 'Conta (número ou e-mail)', exemplo: '1 ou nome@gmail.com' };
function acoesDoApp(bundle) {
  if (bundle === 'navegador-padrao') return [ACAO_LINK, ACAO_GMAIL];
  if (bundle === 'deck-meet-navegador') return [{ id: 'reuniao-microfone', nome: 'Mutar ou desmutar o microfone da reunião', entrada: 'nenhuma' }, { id: 'reuniao-camera', nome: 'Ligar ou desligar a câmera da reunião', entrada: 'nenhuma' }];
  const a = APPS_MAC().find(x => x.bundle === bundle); if (!a) return null;
  const lista = bundle === 'com.apple.mail' ? [c.mailAviso
      ? { id: 'mail-caixa', nome: 'Abrir a caixa de entrada de uma conta', entrada: 'lista', rotulo: 'Conta', opcoes: [], aviso: c.mailAviso }
      : { id: 'mail-caixa', nome: 'Abrir a caixa de entrada de uma conta', entrada: 'lista', rotulo: 'Conta', opcoes: [{ valor: 'conta-1', nome: 'iCloud', detalhe: 'maria@icloud.com' }, { valor: 'conta-2', nome: 'Trabalho', detalhe: 'maria@empresa.com.br' }, { valor: 'conta-3', nome: 'Pessoal', detalhe: 'maria@gmail.com' }] },
      { id: 'mail-novo', nome: 'Escrever um e-mail novo', entrada: 'nenhuma' }]
    : bundle === 'com.apple.Notes' ? [{ id: 'notas-pasta', nome: 'Abrir uma pasta', entrada: 'lista', rotulo: 'Pasta', opcoes: [{ valor: 'p1', nome: 'Receitas', detalhe: 'iCloud' }, { valor: 'p2', nome: 'Cifras', detalhe: 'iCloud' }] }]
    : bundle === 'com.apple.iCal' ? [{ id: 'calendario-hoje', nome: 'Mostrar hoje', entrada: 'nenhuma' }, { id: 'calendario-dia', nome: 'Mostrar um dia', entrada: 'texto', rotulo: 'Dia', exemplo: '2026-12-25' }]
    : [];
  return a.navegador ? [...lista, ACAO_LINK, ACAO_GMAIL] : lista;
}
function estadoSpotify() {
  if (c.spotify === 'fechado') return null;
  const tocando = c.spotify === 'tocando';
  const s = posicaoBase.s + (tocando ? (Date.now() - posicaoBase.desde) / 1000 : 0);
  return { tocando, faixa: X(c.faixa), artista: X(c.artista), posicao: Math.min(221, Math.floor(s)), duracao: 221, capaId: X('capa-1'), cores: c.xss ? [X('#963030'), X('#285A64')] : ['#963030', '#285A64'],
    ...(c.spotifyModos === 'sem' ? {} : { album: X(c.album), repetir: c.repetir, aleatorio: c.aleatorio }),
    ...(c.spotifyExtras === 'nao' ? {} : { volume: c.volume, ...(c.spotifyExtras === 'volume' ? {} : { volumeMac: c.volumeMac }),
      ...(c.spotifyExtras === 'login' ? { conectado: true, curtida: c.curtida, repetirFaixa: c.repetirFaixa, aparelho: aparelhos().find(a => a.ativo).nome } : { conectado: false }) }) };
}
function estado() {
  const semMed = c.uso === 'sem-medicao';
  const selos = { whatsapp: c.xss ? X('23') : '23' };
  if (c.agenda === 'sem') selos.calendario = '!';
  return {
    agora: new Date(Date.now() + c.relogioMs).toISOString(), nomeMac: X(c.nomeMac), perfilAtivo: configCompleta().perfilAtivo, comp: c.comp, blocos: c.blocos,
    ...(c.blocos.monitor ? { monitor: { ...c.monitor, itens: Object.keys(c.monitorItens).filter(k => c.monitorItens[k]) } } : {}),
    spotify: estadoSpotify(),
    uso: [
      { id: 'claude-leo', nome: 'Claude', conta: X('leo'), semana: semMed ? null : 61, renova: emDias(3, 14) },
      { id: 'claude-equipe', nome: 'Claude', conta: 'equipe', semana: semMed ? null : 77, renova: emDias(1, 9) },
      { id: 'codex', nome: 'Codex', conta: 'pro', semana: semMed ? null : 4, renova: emDias(0, 23) },
    ],
    sessoes: SESSOES().slice(0, c.sessoes).map(({ contexto, ...leve }) => leve), // o Mac de verdade só manda o contexto em /api/sessoes
    whatsapp: c.whatsappOrigem === 'web' ? { total: 23, conversas: 0, origem: 'web', navegador: 'Google Chrome', aberto: true }
      : c.whatsappOrigem === 'qr' ? { total: 23, conversas: 5, origem: 'qr', aberto: true }
      : c.whatsappOrigem === 'qr-reconectando' ? { total: 0, conversas: 0, origem: 'qr', aberto: false, reconectando: true }
      : c.whatsappOrigem === 'qr-reconectando-lista' ? { total: 23, conversas: 5, origem: 'qr', aberto: false, reconectando: true }
      : c.whatsappOrigem === 'qr-caido' ? { total: 0, conversas: 0, origem: 'qr', aberto: false }
      : c.whatsappOrigem === 'web-fechado' ? { total: 0, conversas: 0, origem: 'web', navegador: 'Arc', aberto: false }
      : { total: 23, conversas: 5, origem: 'app' },
    agenda: c.agenda === 'sem' ? { permissao: false, proximo: null }
      : { permissao: true, proximo: c.agenda === 'vazia' ? null : { titulo: X('Reunião de produto'), inicio: new Date(Date.now() + 2 * 3600000).toISOString(), diaTodo: false, calendario: X('Trabalho'), cor: X('#60A5FA'), local: X('Google Meet') } },
    acesas: c.acesas, selos, avisos: [],
    ...(c.andamento && Object.keys(c.andamento).length ? { andamento: c.andamento } : {}),
    ...(c.comReuniao && c.reuniaoEstado ? { reuniao: { mic: c.reuniaoEstado.mic, cam: c.reuniaoEstado.cam } } : {}),
  };
}

// a validação do Mac (ConfigDeck.validar): id único, nome, tipo conhecido e ação preenchida
function validar(cfg) {
  if (!Array.isArray(cfg.perfis) || !cfg.perfis.some(p => p.id === cfg.perfilAtivo)) return 'Perfil ativo inexistente.';
  const ids = new Set();
  for (const t of cfg.perfis.flatMap(p => p.teclas)) {
    if (!t.id || ids.has(t.id)) return 'Tecla com id vazio ou repetido.';
    ids.add(t.id);
    if (!String(t.nome || '').trim()) return 'Tecla sem nome.';
    if (!['app', 'atalho', 'tecla', 'comando'].includes(t.tipo)) return `Tipo inválido em "${t.nome}".`;
    if (!String(t.valor || '').trim()) return `"${t.nome}" está sem ação.`;
    if (t.acao) { // a validação do Mac (Config.validarAcao)
      const esc = String(t.acao.valor || '').trim();
      if (t.tipo !== 'app') return `Só tecla de app pode ter ação ("${t.nome}").`;
      if (!['mail-caixa', 'mail-novo', 'link', 'gmail', 'notas-pasta', 'calendario-hoje', 'calendario-dia', 'abrir-arquivo'].includes(t.acao.id)) return `A ação da tecla "${t.nome}" não existe.`;
      if (['mail-caixa', 'notas-pasta'].includes(t.acao.id) && !esc) return `A tecla "${t.nome}" está sem a escolha da ação.`;
      if (t.acao.id === 'link' && !/^(https?:\/\/)?[^\s/]+\.[^\s/]+/.test(esc)) return `O endereço da tecla "${t.nome}" não é válido.`;
      if (t.acao.id === 'calendario-dia' && !/^\d{4}-\d{2}-\d{2}$/.test(esc)) return `O dia da tecla "${t.nome}" não é válido.`;
    }
  }
  return null;
}
const json = (res, status, corpo) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(corpo)) };
const lerCorpo = req => new Promise(r => { let b = ''; req.on('data', x => b += x); req.on('end', () => { try { r(JSON.parse(b || '{}')) } catch { r({}) } }) });

async function api(req, res, url) {
  if (c.mac === 'off') return req.socket.destroy();
  const codigo = req.headers['x-deck-codigo'] || url.searchParams.get('codigo');
  const rota = url.pathname, m = req.method;
  // como o Rotas.swift: o único pedido de /api que não leva código de acesso. 6 dígitos certos devolvem o código longo
  if (rota === '/api/parear' && m === 'POST') {
    const dig = String((await lerCorpo(req)).codigo || '').trim();
    cont.parear.push(dig);
    if (parearErros >= 5) return json(res, 429, { erro: 'Muitas tentativas erradas. Gere um novo código no Mac.' });
    if (parearGasto || dig !== CODIGO_PAREAR) { parearErros++; return json(res, 401, { erro: `Código incorreto. Restam ${5 - parearErros} tentativas.` }) }
    parearGasto = true;
    return json(res, 200, { codigoAcesso: codigoAtual });
  }
  // como o Rodizio.swift: a troca acontece no pedido que a dispara, e quem veio com o código anterior (na folga) recebe o novo
  // no cabeçalho X-Deck-Codigo-Novo, em qualquer status. Código fora da folga é 401 sem cabeçalho.
  if (codigo === codigoAtual && codigoAtual === CODIGO && (c.rodizio === 'trocar' || (c.rodizio === 'botao' && rota.startsWith('/api/botao/')))) { codigoAnterior = CODIGO; codigoAtual = CODIGO_NOVO }
  if (codigo !== codigoAtual && !(codigo && codigo === codigoAnterior)) return json(res, 401, { erro: 'Código de acesso inválido. Abra o Deck no Mac e leia o QR de novo.' });
  cont.codigos.push(codigo);
  if (codigo === codigoAnterior) res.setHeader('X-Deck-Codigo-Novo', codigoAtual);
  if (rota === '/api/estado' && m === 'GET') {
    const meu = cont; // o reset troca o objeto: quem fecha depois desconta do contador antigo
    meu.estado++; meu.simultaneos++; meu.maxSimultaneos = Math.max(meu.maxSimultaneos, meu.simultaneos);
    res.on('close', () => { meu.simultaneos-- });
    if (c.pendurar) return;
    if (c.atraso) await new Promise(r => setTimeout(r, c.atraso));
    if (!res.writableEnded && !res.destroyed) json(res, 200, estado());
    return;
  }
  if (rota === '/api/config' && m === 'GET') return c.config500 ? json(res, 500, { erro: 'config quebrada' }) : json(res, 200, configCompleta());
  if (rota === '/api/config' && m === 'PUT') {
    const nova = await lerCorpo(req); cont.configsGravadas.push(nova);
    if (c.atrasoGravar) await new Promise(r => setTimeout(r, c.atrasoGravar));
    const erro = c.rejeitar || validar(nova);
    if (erro) return json(res, 422, { erro });
    if (nova.perfilAtivo) perfilAtivo = nova.perfilAtivo;
    gravada = { perfis: nova.perfis };
    if (nova.blocos) c.blocos = nova.blocos;
    return json(res, 200, { ...nova, versao: 1, porta: 4777 });
  }
  if (rota.startsWith('/api/botao/') && m === 'POST') {
    const id = decodeURIComponent(rota.slice(11)), tecla = perfisConfig().flatMap(p => p.teclas).find(t => t.id === id);
    if (c.atrasoAcao) await new Promise(r => setTimeout(r, c.atrasoAcao));
    if (!tecla) return json(res, 404, { erro: 'Essa tecla não existe mais no Mac.' });
    if (c.falha) return json(res, 500, { erro: 'O Mac não deixou: ligue a Acessibilidade para o Deck nos Ajustes do Sistema.' });
    cont.botoes.push(id);
    // o Mac aperta o atalho do app e a leitura seguinte já traz o estado novo
    if ((id === 'mic' || id === 'cam') && c.reuniaoEstado) { const v = c.reuniaoEstado[id]; if (v === 'ligado' || v === 'desligado') c.reuniaoEstado[id] = v === 'ligado' ? 'desligado' : 'ligado' }
    if (id === 'acordado') c.acesas = c.acesas.includes(id) ? [] : [id];
    // comando lento (o "mudar foco" passa de 10 s): o Mac responde na hora, mostra "ligando" e muda o estado só no fim
    if (c.comandoLento && tecla.tipo === 'comando') {
      const ligada = c.acesas.includes(id), fase = tecla.desligar ? (ligada ? 'desligando' : 'ligando') : 'rodando';
      c.andamento = { ...(c.andamento || {}), [id]: { fase } };
      setTimeout(() => {
        if (c.comandoFalha) c.andamento = { ...c.andamento, [id]: { fase: 'falhou', erro: c.comandoFalha, fim: new Date().toISOString() } };
        else { const { [id]: _, ...resto } = c.andamento || {}; c.andamento = resto; if (tecla.desligar) c.acesas = ligada ? c.acesas.filter(x => x !== id) : [...c.acesas, id] }
      }, c.comandoLento);
      return json(res, 200, { ok: true });
    }
    if (tecla.desligar) c.acesas = c.acesas.includes(id) ? c.acesas.filter(x => x !== id) : [...c.acesas, id]; // o Mac guarda o estado da tecla liga e desliga
    return json(res, 200, { ok: true });
  }
  const semLogin = () => c.spotifyExtras !== 'login' && (json(res, 409, { erro: 'O Spotify não está conectado. Conecte nos Ajustes do Mac.' }), true); // responde 409 e devolve true
  if (rota === '/api/spotify/dispositivos' && m === 'GET') {
    cont.aparelhos = (cont.aparelhos || 0) + 1;
    if (semLogin()) return;
    if (c.aparelhosErro) return json(res, 500, { erro: c.aparelhosErro });
    return json(res, 200, aparelhos());
  }
  if (rota === '/api/spotify/recentes' && m === 'GET') { if (semLogin()) return; return json(res, 200, { itens: c.filaVazia ? [] : [{ faixa: X('Tocada antes 1'), artista: 'Artista Velho', capa: CAPA_FILA(1) }, { faixa: 'Tocada antes 2', artista: 'Banda Velha' }] }) }
  if (rota === '/api/spotify/pular' && m === 'POST') {
    if (semLogin()) return;
    if (c.atrasoAcao) await new Promise(r => setTimeout(r, c.atrasoAcao));
    if (c.filaRecusa) return json(res, 422, { erro: c.filaRecusa });
    const n = +url.searchParams.get('n'), alvo = proximasDaFila()[n - 1];
    cont.spotify.push(`pular:${n}:${url.searchParams.get('uri')}`);
    if (!alvo || alvo.uri !== url.searchParams.get('uri')) return json(res, 422, { erro: 'A fila mudou. Abra a fila de novo.' });
    c.filaPulou = (c.filaPulou || 0) + n; c.faixa = alvo.faixa;
    return json(res, 200, { ok: true });
  }
  if (rota === '/api/spotify/fila' && m === 'GET') { cont.filas = (cont.filas || 0) + 1; if (semLogin()) return; return json(res, 200, FILA()) }
  if (rota.startsWith('/api/spotify/') && m === 'POST') {
    const acao = rota.slice(13);
    if (c.atrasoAcao) await new Promise(r => setTimeout(r, c.atrasoAcao));
    if (c.spotify === 'fechado') return json(res, 409, { erro: 'O Spotify está fechado no Mac.' });
    if (c.spotifyRecusa) return json(res, 422, { erro: c.spotifyRecusa });
    if (['curtir', 'dispositivo'].includes(acao) || (acao === 'repetir' && url.searchParams.has('modo'))) { if (semLogin()) return }
    if (acao === 'volume') {
      const alvo = url.searchParams.get('alvo') || 'spotify', v = +url.searchParams.get('v');
      cont.spotify.push(`volume:${alvo}:${v}`);
      if (alvo === 'spotify') c.volume = v; else if (alvo === 'mac') c.volumeMac = v; else c.volumeAparelho = v;
      return json(res, 200, { ok: true });
    }
    if (acao === 'curtir') { cont.spotify.push('curtir:' + url.searchParams.get('v')); c.curtida = url.searchParams.get('v') === '1'; return json(res, 200, { ok: true }) }
    if (acao === 'dispositivo') { const id = url.searchParams.get('id'); cont.spotify.push('dispositivo:' + id); if (aparelhos().some(a => a.id === id && !a.restrito)) c.aparelhoAtivo = id; return json(res, 200, { ok: true }) }
    if (acao === 'repetir' && url.searchParams.has('modo')) { const modo = url.searchParams.get('modo'); cont.spotify.push('repetir:modo=' + modo); c.repetirFaixa = modo === 'faixa'; c.repetir = modo === 'contexto'; return json(res, 200, { ok: true }) }
    cont.spotify.push(acao + (acao === 'posicao' ? ':' + url.searchParams.get('s') : acao === 'repetir' || acao === 'aleatorio' ? ':' + (url.searchParams.get('v') ?? 'alterna') : ''));
    if (acao === 'repetir' || acao === 'aleatorio') { const v = url.searchParams.get('v'); c[acao] = v === null ? !c[acao] : v === '1' }
    const agora = estadoSpotify().posicao;
    if (acao === 'tocar') { c.spotify = 'tocando'; posicaoBase = { s: agora, desde: Date.now() } }
    if (acao === 'pausar') { c.spotify = 'pausado'; posicaoBase = { s: agora, desde: Date.now() } }
    if (acao === 'posicao') posicaoBase = { s: +url.searchParams.get('s'), desde: Date.now() };
    return json(res, 200, { ok: true });
  }
  if (rota === '/api/meet' || rota.startsWith('/api/meet/')) {
    if (c.meet === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    if (c.meet === 'erro') return json(res, 500, { erro: 'O Mac não conseguiu ler o Meet.' });
    if (rota === '/api/meet') {
      if (m !== 'GET') return json(res, 405, { erro: 'Esse pedido não é aceito nessa rota.' });
      cont.meetLeituras++;
      return json(res, 200, c.meetEstado);
    }
    if (m !== 'POST') return json(res, 405, { erro: 'Esse pedido não é aceito nessa rota.' });
    const acao = rota.slice('/api/meet/'.length);
    if (!['entrar', 'microfone', 'camera', 'sair'].includes(acao)) return json(res, 404, { erro: 'Essa rota não existe.' });
    if (c.meet === 'recusa') return json(res, 422, { erro: 'Não achei a chamada do Meet na frente do navegador.' });
    if (c.meetAtraso) await new Promise(r => setTimeout(r, c.meetAtraso));
    cont.meetAcoes.push(acao);
    const e = c.meetEstado, inverte = v => v === 'ligado' ? 'desligado' : v === 'desligado' ? 'ligado' : v;
    if (acao === 'microfone') e.microfone = inverte(e.microfone);
    if (acao === 'camera') e.camera = inverte(e.camera);
    if (acao === 'sair') c.meetEstado = { aberta: false, microfone: 'sem-reuniao', camera: 'sem-reuniao' };
    return json(res, 200, { ok: true });
  }
  if (rota === '/api/controles' || rota.startsWith('/api/controles/')) {
    if (c.controles === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    if (c.controles === 'erro') return json(res, 500, { erro: 'O Mac não conseguiu ler os controles.' });
    if (rota === '/api/controles') {
      if (m !== 'GET') return json(res, 405, { erro: 'Esse pedido não é aceito nessa rota.' });
      cont.controles.push('ler');
      const nada = c.controles === 'nada', semBrilho = c.controles === 'sem-brilho';
      return json(res, 200, { ...(nada ? {} : { volume: c.ctVolume, mudo: c.ctMudo }), ...(nada || semBrilho ? {} : { brilho: c.ctBrilho, teclado: c.ctTeclado }) });
    }
    if (m !== 'POST') return json(res, 405, { erro: 'Esse pedido não é aceito nessa rota.' });
    const item = rota.slice('/api/controles/'.length), v = Number(url.searchParams.get('v'));
    if (!['volume', 'mudo', 'brilho', 'teclado'].includes(item) || !Number.isInteger(v)) return json(res, 400, { erro: 'Pedido de controle inválido.' });
    if (c.controles === 'recusa') return json(res, 422, { erro: 'Não consegui mudar o brilho da tela.' });
    if (c.ctAtraso) await new Promise(r => setTimeout(r, c.ctAtraso));
    cont.controles.push(`${item}=${v}`);
    if (item === 'volume') c.ctVolume = v; else if (item === 'mudo') c.ctMudo = v === 1; else if (item === 'brilho') c.ctBrilho = v; else c.ctTeclado = v;
    return json(res, 200, { ok: true });
  }
  if (rota === '/api/agenda/destinos' && m === 'GET') {
    if (c.agendaCriar === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    if (lembretesAcesso === null) lembretesAcesso = c.agendaCriar === 'lembretes-pedir' ? 'pedir' : 'liberado';
    // Como o Mac real: só a chamada com ?pedir=1 que abre a janela devolve "pedindo". Enquanto a janela está aberta as outras devolvem "pedir".
    let devolve = lembretesAcesso;
    if (url.searchParams.get('pedir') === '1') { cont.destinosPedidos++; if (lembretesAcesso === 'pedir') { lembretesAcesso = 'pedindo'; liberarEm = Date.now() + 4500; devolve = 'pedindo' } }
    if (lembretesAcesso === 'pedindo' && Date.now() >= liberarEm) lembretesAcesso = devolve = 'liberado';
    else if (devolve === 'pedindo' && url.searchParams.get('pedir') !== '1') devolve = 'pedir';
    return json(res, 200, {
      calendarios: [{ id: 'cal-trab', nome: X('Trabalho'), cor: AZUL, conta: 'iCloud' }, { id: 'cal-pes', nome: X('Pessoal'), cor: ROSA, conta: 'iCloud' }],
      listas: devolve === 'liberado' ? [{ id: 'lis-compras', nome: X('Compras'), cor: VERDE }, { id: 'lis-tarefas', nome: X('Tarefas'), cor: AMARELO }] : [],
      permissaoCalendario: 'liberado', permissaoLembretes: devolve, padrao: padraoAgenda });
  }
  if (rota === '/api/agenda/criar' && m === 'POST') {
    if (c.agendaCriar === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    const n = await lerCorpo(req);
    if (!n.titulo || !n.dia || !n.destino) return json(res, 400, { erro: 'Dê um título ao compromisso.' });
    if (c.agendaCriar === 'recusa') return json(res, 409, { erro: 'O Deck está sem acesso ao Calendário. No Mac: Ajustes do Sistema > Privacidade.' });
    cont.criados.push(n);
    if (n.destino.tipo === 'calendario') criadosAgenda.push({ ...n, calendario: n.destino.id === 'cal-pes' ? 'Pessoal' : 'Trabalho' });
    if (n.padrao) padraoAgenda = n.destino;
    return json(res, 200, { ok: true, padraoSalvo: !!n.padrao });
  }
  if (rota === '/api/reuniao/entrar' && m === 'POST') {
    const link = String((await lerCorpo(req)).link || '');
    if (!/^https:\/\/(meet\.google\.com|([a-z0-9-]+\.)?zoom\.us|teams\.microsoft\.com|teams\.live\.com)\//.test(link)) return json(res, 400, { erro: 'Esse link não é de uma reunião do Meet, do Zoom ou do Teams.' });
    if (c.reuniaoRecusa) return json(res, 422, { erro: c.reuniaoRecusa });
    cont.reunioes.push(link);
    return json(res, 200, { ok: true });
  }
  const abrir = rota.match(/^\/api\/sessoes\/([^/]+)\/abrir$/);
  if (abrir && m === 'POST') {
    const id = decodeURIComponent(abrir[1]);
    if (!SESSOES().some(x => x.id === id)) return json(res, 404, { erro: 'Essa sessão não existe mais neste Mac.' });
    if (c.sessaoAbreRecusa) return json(res, 422, { erro: c.sessaoAbreRecusa });
    cont.sessoesAbertas.push(id);
    return json(res, 200, { ok: true, como: c.sessaoAbre, app: c.sessaoAbre === 'pasta' ? 'Terminal' : 'Orca' });
  }
  if (rota === '/api/apps' || rota.startsWith('/api/apps/')) {
    if (m !== 'GET') return json(res, 405, { erro: 'Esse pedido não é aceito nessa rota.' });
    if (c.apps === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    if (rota === '/api/apps') { cont.apps++; return c.apps === 'erro' ? json(res, 500, { erro: 'O Mac não conseguiu listar os apps.' }) : json(res, 200, APPS_MAC()) }
    const [bundle, parte] = rota.slice(10).split('/');
    if (parte === 'icone') { cont.icones.push(bundle); res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'private, max-age=86400' }); return res.end(fs.readFileSync(path.join(RAIZ, 'icones/deck-128.png'))) }
    if (parte === 'acoes') {
      cont.acoesApp.push(bundle);
      if (c.acoesAtraso) await new Promise(r => setTimeout(r, c.acoesAtraso));
      const acoes = acoesDoApp(bundle);
      return acoes ? json(res, 200, { bundle, acoes }) : json(res, 404, { erro: 'Esse app não está instalado neste Mac.' });
    }
    return json(res, 404, { erro: 'Essa rota não existe.' });
  }
  if (rota === '/api/capa') { cont.capas++; res.writeHead(200, { 'Content-Type': 'image/png' }); return res.end(fs.readFileSync(path.join(RAIZ, 'icones/deck.png'))) }
  if (rota === '/api/uso/detalhe') {
    const periodo = url.searchParams.get('periodo'); cont.usoDetalhe.push(periodo);
    if (c.usoDetalhe === 'antigo') return json(res, 404, { erro: 'Essa rota não existe.' });
    if (c.usoDetalhe === 'erro') return json(res, 500, { erro: 'O Mac não conseguiu ler o uso.' });
    return json(res, 200, detalheUso(['dia', 'semana', 'mes'].includes(periodo) ? periodo : 'semana'));
  }
  if (rota === '/api/sessoes') { cont.sessoes++; return json(res, 200, SESSOES().slice(0, c.sessoes)) }
  if ((rota === '/api/whatsapp' || rota === '/api/agenda') && c.atrasoListas) await new Promise(r => setTimeout(r, c.atrasoListas));
  if (c.whatsappRico && rota.startsWith('/api/whatsapp/foto/') && m === 'GET') {
    const arq = rota.split('/').pop(); cont.fotos.push(arq);
    cont.fotoAgora = (cont.fotoAgora || 0) + 1; cont.fotoPico = Math.max(cont.fotoPico || 0, cont.fotoAgora);
    if (c.fotoAtraso) await new Promise(r => setTimeout(r, c.fotoAtraso));
    cont.fotoAgora--;
    if (c.fotoFalhaPrimeira && cont.fotos.filter(x => x === arq).length === 1) return json(res, 500, { erro: 'O Mac não conseguiu.' });
    return json(res, 200, { tipo: 'image/png', dados: PNG_B64 });
  }
  if (c.whatsappRico && rota === '/api/whatsapp/midia' && m === 'GET') {
    const id = url.searchParams.get('id'); cont.midias.push(id);
    return json(res, 200, id === 'A1' ? { tipo: 'audio/wav', dados: WAV_B64 } : { tipo: 'image/png', dados: PNG_B64 });
  }
  if (c.whatsappRico && rota === '/api/whatsapp/abrir' && m === 'POST') {
    const id = String((await lerCorpo(req)).id || ''); cont.whatsappAbertas.push(id);
    if (c.abrirAtraso) await new Promise(r => setTimeout(r, c.abrirAtraso));
    return json(res, 200, id.endsWith('@g.us') ? { ok: true, aviso: 'Abri o WhatsApp Web. Grupo não tem link direto: procure o grupo na lista.' } : { ok: true });
  }
  if (rota === '/api/whatsapp') {
    cont.whatsapp++;
    if (c.whatsappOrigem === 'qr-caido' || c.whatsappOrigem === 'qr-reconectando' || c.whatsappOrigem.startsWith('web')) return json(res, 200, []); // pelo navegador o Mac não tem lista por conversa
    if (c.whatsapp === 'erro') return json(res, 500, { erro: 'O WhatsApp não respondeu no Mac.' });
    if (c.whatsappVersao !== null && url.searchParams.has('v')) { // Mac com a lista versionada (Bluetooth: não reenvia o que o iPhone já tem)
      const v = url.searchParams.get('v'); cont.whatsappV.push(v);
      if (v === String(c.whatsappVersao)) { cont.whatsappIguais++; return json(res, 200, { v: c.whatsappVersao, igual: true }) }
      return json(res, 200, { v: c.whatsappVersao, conversas: WHATSAPP() });
    }
    return json(res, 200, WHATSAPP());
  }
  if (rota === '/api/agenda') {
    cont.agenda.push(`${url.searchParams.get('de')}|${url.searchParams.get('dias')}`);
    if (c.agenda === 'erro') return json(res, 500, { erro: 'O Calendário não respondeu no Mac.' });
    if (c.agenda === 'sem') return json(res, 403, { erro: 'O Deck não tem permissão para ler o Calendário.' });
    return json(res, 200, c.agenda === 'vazia' ? [] : eventos(url.searchParams.get('de'), Number(url.searchParams.get('dias'))));
  }
  json(res, 404, { erro: 'Rota desconhecida.' });
}

export function iniciar(porta) {
  const servidor = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname === '/__cenario') {
      if (req.method === 'POST') { const p = await lerCorpo(req); const { blocos, ...resto } = p; Object.assign(c, resto); if (blocos) c.blocos = { ...c.blocos, ...blocos }; if (p.spotify === 'tocando' || p.spotify === 'pausado') posicaoBase = { s: estadoSpotify()?.posicao ?? 132, desde: Date.now() } }
      return json(res, 200, { cenario: c, contadores: cont });
    }
    if (url.pathname === '/__reset') { zerar(); return json(res, 200, { ok: true }) }
    if (url.pathname.startsWith('/api/')) return api(req, res, url);
    // o certificado público do CA do Deck: sem código de acesso (o iPhone ainda não confia no Deck quando o baixa)
    if (url.pathname === '/ca.crt') { cont.ca++; res.writeHead(200, { 'Content-Type': 'application/x-x509-ca-cert', 'Content-Disposition': 'attachment; filename="Deck.crt"' }); return res.end('CERTIFICADO DE MENTIRA') }
    let arquivo = path.join(RAIZ, url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname));
    if (!arquivo.startsWith(RAIZ) || arquivo.includes(path.sep + 'teste' + path.sep) || !fs.existsSync(arquivo) || fs.statSync(arquivo).isDirectory()) { res.writeHead(404); return res.end('não achei') }
    res.writeHead(200, { 'Content-Type': TIPOS[path.extname(arquivo)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    fs.createReadStream(arquivo).pipe(res);
  });
  return new Promise(ok => servidor.listen(porta, () => ok(servidor)));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const porta = Number(process.argv[2] || 4881);
  await iniciar(porta);
  console.log(`Mac de mentira no ar: http://localhost:${porta}/?codigo=${CODIGO}`);
}
