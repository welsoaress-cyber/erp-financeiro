# ERP Financeiro Pessoal — regras do projeto

Leia `docs/01-arquitetura.md` antes de propor mudanças de estrutura. Cada etapa tem um doc em `docs/`.

## Regras inegociáveis (definidas pelo proprietário)
- **Custo zero.** Nada pago, nenhum serviço externo com cobrança, nada ativado sem autorização prévia. Informe antes: serviço, motivo, plano gratuito, limites, quando cobra.
- **Sem segredos no repositório.** Chaves só em `app/.env.local` (ignorado) e nas variáveis de build do Cloudflare. Nunca pedir credenciais pelo chat.
- **Banco isolado.** Projeto Supabase novo e exclusivo. Os projetos legados `holding-financeiro` e `navalha-app` não são tocados (nem pausados, nem alterados).
- **Só migrations versionadas alteram o banco.** Nenhuma outra ferramenta (DeepSeek, painel, scripts avulsos) cria objetos. Se uma migration falhar em produção, reportar o erro exato e parar; nunca contornar. Ver `docs/15-incidente-producao.md`.
- **Uma etapa por vez.** Entregar migration + testes SQL + app + e2e + doc, commitar, enviar e PARAR para validação do proprietário. Não antecipar funcionalidades. MVP simples.
- **Avisar antes** de implementar algo que prejudique a arquitetura (regra 9), com o motivo em uma ou duas frases, e então entregar sob premissas explícitas.

## Stack e convenções
- `app/`: React 19 + TypeScript + Vite + Tailwind v4 + TanStack Query v5 + supabase-js + react-router 8. Deploy: Cloudflare Workers (assets estáticos) via push em `main`.
- `supabase/migrations/`: Postgres 17, uma migration por etapa, numeradas `20260902000NNN_*.sql`. Enums para tipos, `criado_em`/`atualizado_em`, `gen_random_uuid()`, RLS em toda tabela com `organizacao_id in (select public.minhas_organizacoes())`, sem grant de DELETE, nada para `anon`, funções com `set search_path = public`.
- **Motor financeiro:** `lancamentos` só é gravado pelas funções `criar/atualizar/efetivar/cancelar/excluir_lancamento` (flag de sessão `erp.motor`). Saldo e resultado são derivados (views), nunca gravados.
- Módulos em `app/src/modules/<nome>/` (`tipos.ts`, `api.ts`, `components/`, `pages/`, `index.ts`) registrados em `app/src/app/modulos.ts`. UI em `app/src/core/ui`. Textos em português.

## Como testar (obrigatório antes de commitar)
```
# Postgres local (16) em /var/tmp/erp-pg, porta 5433, socket /tmp, usuário postgres
PGHOST=/tmp PGPORT=5433 PGUSER=postgres supabase/tests/rodar_local.sh   # todas as suítes SQL + cenário de produção
cd app && npx tsc --noEmit -p tsconfig.app.json && npx oxlint src && npm run build
```
E2E: Playwright com API mock (`mock.mjs`, porta 54321) e `vite preview --port 4173`; um spec por módulo. Rodar os specs dos módulos tocados.

## Produção
- Verificação consolidada: `supabase/tests/verificar_tudo.sql` (esperado 17 de 17). Diagnóstico somente leitura: `supabase/scripts/diagnostico_contratos.sql`.
- O ambiente remoto não alcança `*.supabase.co` nem `workers.dev`: o proprietário aplica SQL pelo SQL Editor e reporta o resultado.

## Estilo de resposta
Custo mínimo, sem rodeios, assertivo. Um item por vez quando o proprietário estiver executando passos. Dar link raw do GitHub e o SQL para copiar/colar.
