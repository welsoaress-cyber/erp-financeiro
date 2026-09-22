// Descasca o prefixo /painel antes de buscar o arquivo estático — o build (vite.config.ts
// base: '/painel/') referencia tudo como /painel/assets/..., mas os arquivos no dist ficam
// na raiz. Sem isso, servnet.net.br/painel/* não acha nada (404). Só entra em ação pra esse
// prefixo (run_worker_first no wrangler.jsonc); o resto do tráfego nem passa por aqui.
//
// Link antigo (sem /painel, em qualquer domínio — workers.dev ou servnet.net.br) manda
// direto pro endereço novo: servnet.net.br/painel + o mesmo caminho.
const DOMINIO_NOVO = 'servnet.net.br'

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.pathname === '/painel' || url.pathname.startsWith('/painel/')) {
      const interno = new URL(request.url)
      interno.pathname = url.pathname.slice('/painel'.length) || '/'
      return env.ASSETS.fetch(new Request(interno, request))
    }
    if (request.method === 'GET' && !url.pathname.includes('.')) {
      const destino = new URL(request.url)
      destino.hostname = DOMINIO_NOVO
      destino.protocol = 'https:'
      destino.port = ''
      destino.pathname = '/painel' + url.pathname
      return Response.redirect(destino.toString(), 301)
    }
    return env.ASSETS.fetch(request)
  },
}
