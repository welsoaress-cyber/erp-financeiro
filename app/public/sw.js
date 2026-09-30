// Service Worker "raso": só instalabilidade + cache de leitura dos assets estáticos.
// Sem fila de sincronização offline, sem cache de respostas da API (Supabase) — isso é
// deliberado (etapa 63): ações do técnico passam por funções do motor com efeito colateral
// real, enfileirar isso offline arrisca duplicar/conflitar com o que mudou no servidor.
const CACHE = 'erp-estatico-v1'
const BASE = '/painel/'

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches.keys().then((chaves) => Promise.all(chaves.filter((c) => c !== CACHE).map((c) => caches.delete(c)))).then(() => self.clients.claim()),
  )
})

function estatico(pathname) {
  return pathname.startsWith(BASE + 'assets/') || pathname.startsWith(BASE + 'icons/') || pathname === BASE + 'manifest.webmanifest'
}

self.addEventListener('fetch', (evento) => {
  const req = evento.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return // API do Supabase e outros domínios: sempre rede, nunca cache

  if (req.mode === 'navigate') {
    // HTML: network-first — nunca serve versão velha da tela se tiver internet
    evento.respondWith(
      fetch(req)
        .then((resp) => { caches.open(CACHE).then((c) => c.put(req, resp.clone())); return resp })
        .catch(() => caches.match(req).then((r) => r || caches.match(BASE))),
    )
    return
  }

  if (estatico(url.pathname)) {
    // JS/CSS com hash, ícones, manifest: cache-first — são imutáveis por URL
    evento.respondWith(
      caches.match(req).then((cacheado) => cacheado || fetch(req).then((resp) => { caches.open(CACHE).then((c) => c.put(req, resp.clone())); return resp })),
    )
  }
})
