# 19 · Portal em servnet.net.br/portal (custo zero)

Objetivo: manter o endereço antigo `https://servnet.net.br/portal` apontando para o portal novo, sem mexer no site institucional.

Pré-requisito: o domínio `servnet.net.br` precisa estar na sua conta Cloudflare (DNS gerenciado pela Cloudflare, plano Free). Se hoje o DNS está em outro lugar, é preciso migrar os nameservers primeiro (gratuito).

## Como funciona
O Worker `erp-financeiro` já serve o app. Uma **rota de Worker** faz a Cloudflare entregar esse mesmo Worker para `servnet.net.br/portal*`. O restante do site continua no host atual. O app usa caminhos absolutos (`/portal/...`, `/assets/...`), então a rota precisa cobrir também os assets — por isso são duas rotas.

## Passos (painel Cloudflare, um por vez)
1. Workers & Pages → `erp-financeiro` → Settings → Domains & Routes → Add → Route.
2. Route: `servnet.net.br/portal*` · Zone: `servnet.net.br` → Save.
3. Repetir com a rota `servnet.net.br/assets/*` (os arquivos JS/CSS do app). Se o site institucional também usa `/assets/`, avise: nesse caso a alternativa é o subdomínio `portal.servnet.net.br` (Custom Domain no mesmo painel, sem conflito).
4. Supabase → Authentication → URL Configuration → adicionar `https://servnet.net.br/portal/**` em Redirect URLs.
5. Portal do cliente (ERP) → Configurar → "Site do provedor" = `https://www.servnet.net.br` (link de indicação `?ref=CODIGO`).

Custos: rotas e domínios personalizados de Worker estão no plano Free (100 mil requisições/dia). Nada é cobrado sem upgrade manual.
