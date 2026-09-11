-- =============================================================================
-- 0070 · Etapa 44 — Conciliação bancária (conferir o caixa com o extrato)
-- =============================================================================
-- Cada movimento de conta pode ser marcado como "conferido no extrato".
-- A tela mostra, por conta e mês: movimentos conferidos × pendentes e a
-- diferença — o saldo do sistema deixa de ser fé e vira fato conferido.
-- A marca é reversível (motivo de auditoria fica na tabela auditoria) e só
-- passa pela função (sem grant de update na tabela).
-- =============================================================================

alter table public.movimentos add column conciliado_em timestamptz;
comment on column public.movimentos.conciliado_em is 'Quando este movimento foi conferido contra o extrato bancário (null = pendente).';

create function public.conciliar_movimentos(p_ids uuid[], p_conciliar boolean default true)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid; n int;
begin
  select organizacao_id into v_org from public.organizacao_membros where usuario_id = auth.uid() limit 1;
  perform public.exigir_membro(v_org);
  perform set_config('erp.motor', 'on', true);
  update public.movimentos
     set conciliado_em = case when p_conciliar then now() else null end
   where id = any(p_ids) and organizacao_id = v_org;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.conciliar_movimentos(uuid[], boolean) from public, anon;
grant execute on function public.conciliar_movimentos(uuid[], boolean) to authenticated;
