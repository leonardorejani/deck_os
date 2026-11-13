// Service worker do Deck: guarda só a casca da página (HTML, CSS, JS e ícones) para o painel abrir na hora
// mesmo com o Mac desligado. Quem diz "Mac desconectado" é a própria página, quando o canal não responde.
// A API NUNCA entra em cache: estado, config, WhatsApp, agenda, sessões e capa são sempre do Mac, agora.
// Suba VERSAO quando mudar a lista ou a estratégia. O activate apaga os caches das versões anteriores.
const VERSAO = 'v1'
const CASCA = `deck-casca-${VERSAO}`

// Tudo que o index.html carrega. O teste do painel (pwa.teste.mjs) falha se um arquivo daqui sumir
// ou se o index.html passar a carregar algo que não está na lista.
const ESSENCIAIS = [
  '/', '/manifest.webmanifest',
  '/deck.css', '/util.js', '/canal.js', '/pwa.js', '/pareamento.js', '/paineis.js', '/player.js', '/controles.js', '/meet.js', '/monitor.js', '/apps.js', '/deck.js',
  '/tatile/cor.css', '/tatile/tipo.css', '/tatile/espaco.css', '/tatile/forma.css', '/tatile/movimento.css',
  '/icones/deck.png', '/icones/deck-128.png', '/icones/claude.png', '/icones/codex.png', '/icones/spotify.png',
  '/icones/whatsapp.png', '/icones/calendario.png', '/icones/safari.png', '/icones/notas.png',
  '/icones/terminal.png', '/icones/finder.png', '/icones/vorssaint.png',
  '/icones/pwa/icon-192.png', '/icones/pwa/icon-512.png', '/icones/pwa/apple-touch-icon-180.png',
]
const NA_CASCA = new Set(ESSENCIAIS)

self.addEventListener('install', evento => {
  // reload: a casca nova vem do Mac, nunca do cache HTTP do navegador
  evento.waitUntil(
    caches.open(CASCA)
      .then(cache => cache.addAll(ESSENCIAIS.map(caminho => new Request(caminho, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', evento => {
  evento.waitUntil(
    caches.keys()
      .then(nomes => Promise.all(nomes.filter(nome => nome !== CASCA).map(nome => caches.delete(nome))))
      .then(() => self.clients.claim()),
  )
})

// Cache primeiro, com atualização por trás: o painel abre na hora e a versão nova vale na abertura seguinte.
// Rede primeiro ficaria pendurado no tempo limite do iPhone quando o Mac está desligado.
async function daCasca(chave, evento) {
  const cache = await caches.open(CASCA)
  const guardada = await cache.match(chave)
  const atualizar = fetch(chave, { cache: 'no-cache' })
    .then(resposta => { if (resposta.ok) cache.put(chave, resposta.clone()); return resposta })
    .catch(() => null)
  if (guardada) { evento.waitUntil(atualizar); return guardada }
  return (await atualizar) || Response.error()
}

self.addEventListener('fetch', evento => {
  const { request } = evento
  if (request.method !== 'GET') return
  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  // API, certificado e qualquer rota do Mac: direto na rede, sem cache e sem passar por aqui
  if (url.pathname === '/api' || url.pathname.startsWith('/api/') || url.pathname === '/ca.crt') return
  // página: qualquer endereço dela (com ?codigo=, ?origem=app) é a mesma casca
  if (request.mode === 'navigate') {
    if (url.pathname !== '/' && url.pathname !== '/index.html') return
    return evento.respondWith(daCasca('/', evento))
  }
  if (NA_CASCA.has(url.pathname)) evento.respondWith(daCasca(url.pathname, evento))
})
