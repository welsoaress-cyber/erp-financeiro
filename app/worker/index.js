// Descasca o prefixo /painel antes de buscar o arquivo estático — o build (vite.config.ts
// base: '/painel/') referencia tudo como /painel/assets/..., mas os arquivos no dist ficam
// na raiz. Sem isso, servnet.net.br/painel/* não acha nada (404). Só entra em ação pra esse
// prefixo (run_worker_first no wrangler.jsonc); o resto do tráfego nem passa por aqui.
export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.pathname === '/painel' || url.pathname.startsWith('/painel/')) {
      url.pathname = url.pathname.slice('/painel'.length) || '/'
      return env.ASSETS.fetch(new Request(url, request))
    }
    return env.ASSETS.fetch(request)
  },
}
