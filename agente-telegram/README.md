# Agente Telegram — painel de revenda (PoC)

Roda **na máquina do proprietário** (PC ou VM), **fora** do deploy do ERP
(Cloudflare/Supabase não seguram um userbot de Telegram).

## Pré-requisitos
- Node.js 18+ (`node -v`)
- `api_id` e `api_hash` do Telegram: https://my.telegram.org → API development tools
- @username do bot do painel

## Passos
```
cd agente-telegram
cp .env.example .env      # preencha TELEGRAM_API_ID, TELEGRAM_API_HASH, PAINEL_BOT, PAINEL_USUARIO, PAINEL_SENHA
npm install
node explorar.mjs
```
Na 1ª vez pede telefone + código (e senha 2FA se houver) e imprime uma
`TELEGRAM_SESSION` — cole no `.env` para não relogar depois.

O script entra no painel (/entrar → usuário → senha) e abre um prompt para
você navegar vendo as respostas e os **botões** do bot:
- `<texto>` envia texto (ex.: o login de um cliente)
- `/b` lista os botões da última resposta
- `/click N` clica no botão N
- `/ver` reimprime a última resposta
- `/sair` encerra

## Segurança / avisos
- Credenciais só no `.env` local (ignorado pelo git). Nunca no repositório nem no chat.
- Automatizar um userbot pode fazer o Telegram **sinalizar/banir** a conta. Use com parcimônia.
- O painel muda de menu às vezes → a automação quebra; por isso esta 1ª fase é só **exploração**, para mapear o fluxo do "Ativar" antes de automatizar.
