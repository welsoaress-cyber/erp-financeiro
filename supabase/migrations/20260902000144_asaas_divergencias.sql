-- =============================================================================
-- 0144 · Divergências de pagamento Asaas (não baixa sozinho, mas avisa)
-- =============================================================================
-- Pedido do proprietário: a baixa automática (0143) só confirma quando CPF +
-- valor + vencimento batem exatos com o Asaas — de propósito, pra nunca achar
-- a cobrança errada. Quando o Asaas tem um pagamento confirmado pro cliente
-- mas ele NÃO bate com o lançamento do ERP (vencimento diferente, por
-- exemplo), antes isso ficava silencioso, pendente pra sempre. Agora fica
-- registrado aqui — relatório "Divergências de pagamento Asaas" + alerta
-- (⚠️) ao lado do nome do cliente em Contas a receber. A escrita (quem acha a
-- divergência) é a reconciliação agendada — ver 0145.
-- Resolve sozinho quando: a baixa acontece de verdade (bateu numa rodada
-- seguinte) ou o lançamento sai de "previsto" por qualquer caminho.
-- =============================================================================

create table public.asaas_divergencias (
  id                   uuid primary key default gen_random_uuid(),
  organizacao_id       uuid not null references public.organizacoes (id) on delete restrict,
  lancamento_id        uuid not null unique references public.lancamentos (id) on delete cascade,
  pessoa_id            uuid references public.pessoas (id) on delete restrict,
  valor_esperado       numeric(14,2) not null,
  vencimento_esperado  date not null,
  pagamento            jsonb not null,
  detectado_em         timestamptz not null default now()
);
comment on table public.asaas_divergencias is 'Pagamento confirmado no Asaas que não bate (valor/vencimento) com o lançamento do ERP. Só a reconciliação agendada (0145) escreve.';
alter table public.asaas_divergencias enable row level security;
revoke all on public.asaas_divergencias from public, anon, authenticated;
create policy asaas_divergencias_select on public.asaas_divergencias
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
grant select on public.asaas_divergencias to authenticated;

create view public.vw_rel_asaas_divergencias with (security_invoker = true) as
select d.id, d.organizacao_id, d.lancamento_id, d.pessoa_id, p.nome as cliente, n.nome as negocio,
       d.valor_esperado, d.vencimento_esperado,
       (d.pagamento->>'value')::numeric as valor_pago, (d.pagamento->>'dueDate')::date as vencimento_pago,
       d.pagamento->>'status' as status_pagamento, d.detectado_em
  from public.asaas_divergencias d
  join public.pessoas p on p.id = d.pessoa_id
  left join public.lancamentos l on l.id = d.lancamento_id
  left join public.negocios n on n.id = l.negocio_id;
grant select on public.vw_rel_asaas_divergencias to authenticated;
