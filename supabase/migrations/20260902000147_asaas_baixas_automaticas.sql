-- =============================================================================
-- 0147 · Histórico de baixas automáticas via Asaas (relatório de conferência)
-- =============================================================================
-- Pedido do proprietário: "necessário a gente ter um relatório diário de tudo
-- o que foi baixado automaticamente para conferirmos e entender se tudo o que
-- foi baixado está correto". Cada vez que a reconciliação agendada (0148) dá
-- baixa sozinha num lançamento, grava aqui — cliente, negócio, valor, forma
-- de pagamento e o pagamento do Asaas que casou. Nunca apaga (auditoria).
-- =============================================================================

create table public.asaas_baixas_automaticas (
  id              uuid primary key default gen_random_uuid(),
  organizacao_id  uuid not null references public.organizacoes (id) on delete restrict,
  lancamento_id   uuid not null references public.lancamentos (id) on delete restrict,
  pessoa_id       uuid references public.pessoas (id) on delete restrict,
  negocio_id      uuid references public.negocios (id) on delete restrict,
  valor           numeric(14,2) not null,
  data_pagamento  date not null,
  forma_pagamento public.forma_pagamento_contrato,
  pagamento       jsonb not null,
  baixado_em      timestamptz not null default now()
);
comment on table public.asaas_baixas_automaticas is 'Auditoria: toda baixa que a reconciliação agendada do Asaas (0148) fez sozinha. Nunca apagado, só a própria reconciliação escreve.';
alter table public.asaas_baixas_automaticas enable row level security;
revoke all on public.asaas_baixas_automaticas from public, anon, authenticated;
create policy asaas_baixas_automaticas_select on public.asaas_baixas_automaticas
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
grant select on public.asaas_baixas_automaticas to authenticated;

create view public.vw_rel_asaas_baixas_automaticas with (security_invoker = true) as
select b.id, b.organizacao_id, b.lancamento_id, b.negocio_id, n.nome as negocio, b.pessoa_id, p.nome as cliente,
       b.valor, b.data_pagamento, b.forma_pagamento, b.pagamento->>'id' as pagamento_asaas_id,
       b.pagamento->>'billingType' as forma_cobranca_asaas, b.baixado_em
  from public.asaas_baixas_automaticas b
  left join public.pessoas p on p.id = b.pessoa_id
  left join public.negocios n on n.id = b.negocio_id;
grant select on public.vw_rel_asaas_baixas_automaticas to authenticated;
