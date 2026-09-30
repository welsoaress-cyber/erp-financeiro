# 66 · CRM / Gestão de leads — Etapa 61 (migration `20260902000111_crm_leads.sql`)

Captura, funil e conversão de leads em clientes. Escopo aprovado pelo proprietário — sem drag-and-drop, sem follow-up automático, sem captura via WhatsApp inbound (essas três peças ficam pra etapa 62; as duas últimas são categorias de complexidade diferente: webhook recebendo mensagem e robô que manda mensagem sozinho).

## Modelo

- **`leads`**: campos mínimos de propósito — nunca duplica `pessoas` (sem CPF/documento). `status` (`novo → contatado → qualificado → negociando → fechado | perdido`), `origem` (`site | whatsapp | indicacao | manual | api`), `plano_interesse_id` opcional (validado contra o negócio do lead via trigger), `convertido_pessoa_id`/`convertido_em` linkam quem ele virou.
- **`lead_eventos`**: só interação manual (ligação/whatsapp/email/visita) — imutável (grant de `insert`/`select`, sem `update`/`delete`). Mudança de status **não** duplica aqui: já fica na `auditoria` genérica (mesmo `tg_auditoria` usado em outras tabelas), então "histórico de mudanças" não pediu tabela própria.
- **RLS** padrão (`organizacao_id in minhas_organizacoes()`), grants diretos (`select/insert/update` em `leads`, sem `update`/`delete` em `lead_eventos`) — sem motor dedicado, mover de etapa é um `update` comum.

## Funções

- `converter_lead_pessoa(lead_id)` — cria a `pessoa` (física, com nome/telefone/email/endereço do lead) + vínculo `cliente` no negócio do lead, marca o lead como convertido e `fechado`. **Não cria contrato** — contrato precisa de conta de pagamento, dia de vencimento etc. que o lead não tem; um contrato errado criado sozinho seria pior que nenhum.
- `lead_publico_capturar(slug, nome, telefone, email?, plano_interesse_id?)` — `security definer`, `grant` só pra `anon`, origem fixa `'site'`. Mesmo padrão de `portal_indicacao_publica`/`vitrine_publica`: recebe o `slug` do negócio (não o `id`), valida telefone/nome/plano antes de gravar.

## App

- `/leads` (menu Cadastros, entre Pessoas e Contratos): 4 cartões de dashboard (leads por etapa, taxa de conversão, tempo médio de conversão em dias, origem dos leads) — tudo calculado no front a partir da lista já buscada, sem view nova.
- Lista com busca (nome/telefone) e filtros (negócio/etapa/origem); clique abre o detalhe.
- Detalhe: mover etapa (select, sem drag-and-drop), registrar interação, histórico de interações, botão **Converter em cliente**.
- **Conversão**: chama `converter_lead_pessoa` e navega pra `/contratos?novo=1&negocio=…&pessoa=…&plano=…` — `ContratosPage` lê esses query params e abre "Novo contrato" já com negócio/pessoa/plano (e valor/periodicidade do plano) preenchidos, pra revisão manual antes de salvar.

## Captura pelo site

Sem tela própria no ERP — é uma função pública (`lead_publico_capturar`) pra quem cuida do site do negócio chamar via `supabase-js`/REST, informando `slug` do negócio. Fora do escopo desta etapa incorporar isso a um formulário hospedado no ERP.

## Testes

`supabase/tests/crm_leads_test.sql`: captura manual normaliza telefone, plano de outro negócio é rejeitado, mover status grava na auditoria, interação é imutável (sem update/delete pro cliente), conversão cria pessoa+vínculo e bloqueia reconversão, captura pública valida slug/telefone/plano. `verificar_tudo.sql`: 77 de 77 (sem verificação nova — nenhum dado financeiro é criado por esta etapa).
