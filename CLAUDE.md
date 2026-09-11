# ERP Financeiro Pessoal — regras do projeto

Leia `docs/01-arquitetura.md` antes de propor mudanças de estrutura. Cada etapa tem um doc em `docs/`.

## Regras inegociáveis (definidas pelo proprietário)
- **Custo zero.** Nada pago, nenhum serviço externo com cobrança, nada ativado sem autorização prévia. Informe antes: serviço, motivo, plano gratuito, limites, quando cobra.
- **Sem segredos no repositório.** Chaves só em `app/.env.local` (ignorado) e nas variáveis de build do Cloudflare. Nunca pedir credenciais pelo chat.
- **Banco isolado.** Projeto Supabase novo e exclusivo. Os projetos legados `holding-financeiro` e `navalha-app` não são tocados (nem pausados, nem alterados).
- **Só migrations versionadas alteram o banco.** Nenhuma outra ferramenta (DeepSeek, painel, scripts avulsos) cria objetos. Se uma migration falhar em produção, reportar o erro exato e parar; nunca contornar. Ver `docs/15-incidente-producao.md`.
- **Uma etapa por vez.** Entregar migration + testes SQL + app + e2e + doc, commitar, enviar, mergear na `main` (para o deploy do Cloudflare sair sozinho) e então pedir para o proprietário testar — não deixar em branch/PR parado esperando ação dele. Não antecipar funcionalidades. MVP simples.
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
- Verificação consolidada: `supabase/tests/verificar_tudo.sql` (esperado 41 de 41). Diagnóstico somente leitura: `supabase/scripts/diagnostico_contratos.sql`.
- O ambiente remoto não alcança `*.supabase.co` nem `workers.dev`: o proprietário aplica SQL pelo SQL Editor e reporta o resultado.

## Estilo de resposta
Custo mínimo, sem rodeios, assertivo. Um item por vez quando o proprietário estiver executando passos. Dar link raw do GitHub e o SQL para copiar/colar.
- Etapas 11B/12/13: `docs/18-portal-servnet.md`, `docs/19-dominio-portal.md`, `docs/20-recorrencia-fixa-parcelada.md`, `docs/21-financeiro.md`. Lançamentos vivem em `/financeiro/lancamentos`; mês compartilhado em `core/periodo/usePeriodo.ts`.
- Etapas 14/15: `docs/22-contratos-fornecedor.md`, `docs/23-resumo-financeiro-dashboard.md`.
- Etapa 16: `docs/24-pendencias-projecao-edicao.md`.
- Etapa 17: `docs/25-carteira-dupla-saldo.md`.
- Etapas 18-25: `docs/26-projecao-contratos.md`, `docs/27-cartao-credito.md` (meses futuros de contrato são projeção derivada, nunca lançamentos pré-gerados).
- Etapa 26: `docs/28-disparos.md` (disparos WhatsApp manuais a partir do PDF de receitas; login do servidor em pessoas).
- Etapa 28 (A/B): `docs/30-estoque.md` (Estoque Servnet: itens com custo médio ponderado, movimentações imutáveis, compra com pagamento misto gerando despesa; etapa B = instalações com porta FTTH e mão de obra, payback no contrato, relatórios e alertas no dashboard — concluída).
- Etapa 27 (A–F): `docs/29-ftth.md` (Rede FTTH: POP e CTOs no mapa Leaflet/OSM, fios com vértices, lacres por porta e por caixa, vínculo cliente↔porta via contrato ativo, histórico; endereço em pessoas alimenta o fio automático).
- Etapa 29 (A/B/C): `docs/31-ordens-servico.md` (Ordens de Serviço: chamados técnicos, bolsa do técnico, tempo desde o agendamento, comissão no Contas a Pagar, payback; 29A/B/C entregues: admin, técnico com login restrito e portal do cliente com avisos WhatsApp.
- Etapa 30: `docs/32-comodato.md` (Comodato: equipamentos com série na casa do cliente; OS de recolhimento automática no encerramento do contrato; troca/perda/descarte com histórico imutável).
- Etapa 31: `docs/33-pix-bloqueio.md` (Pix Mercado Pago no portal e no aviso WhatsApp com baixa automática via webhook; bloqueio assistido em Financeiro → Cobrança).
- Etapa 32: `docs/34-bi-gerencial.md` (BI gerencial em tempo real: churn, MRR, ticket, inadimplência, payback médio, técnicos, CSV — menu Gerencial).
- Etapa 33: `docs/35-ftth-ceo.md` (FTTH: CEO como tipo de ponto, encadeamento alimentado-por com impacto de rompimento, OLT como cadastro no POP).
- Etapa 34: `docs/36-olt-monitoramento.md` (agente local pinga a OLT → Edge olt-ping → aviso WhatsApp ao admin quando cai/volta; alerta na tela FTTH).
- Etapa 35: `docs/37-backup.md` (backup semanal via GitHub Actions → artifact privado 90 dias; secret SUPABASE_DB_URL).
- Etapa 36: `docs/38-aceite-contrato.md` (aceite digital do contrato no portal: termo por negócio, snapshot+hash, IP/user-agent via Edge portal-aceite).
- **No radar (não iniciar sem o proprietário pedir):** integração ReceitaNet (API URA/Callcenter — consulta de cliente/faturas por CPF/telefone via Edge Function com token em secret). Aguarda: proprietário ativar o módulo de API no plano do ReceitaNet e obter o token com o suporte.
