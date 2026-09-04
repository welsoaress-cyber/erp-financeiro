-- =============================================================================
-- 0035 · Excluir parcela prevista com futuras já geradas exclui a cadeia
-- =============================================================================
-- Com a projeção automática, toda recorrência tem as parcelas seguintes
-- geradas — excluir uma parcela batia na FK lancamento_origem_id (restrict).
-- Agora excluir_lancamento apaga esta parcela E todas as seguintes, desde que
-- todas sejam previstas (a tela já dizia "excluir interrompe a recorrência").
-- Se alguma seguinte estiver paga, o erro explica o caminho (cancelar).
-- =============================================================================

create or replace function public.excluir_lancamento(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.lancamentos%rowtype;
  n int;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if exists (
    with recursive cadeia as (
      select id, status from public.lancamentos where lancamento_origem_id = p_id
      union all
      select f.id, f.status from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
    )
    select 1 from cadeia where status <> 'previsto'
  ) then
    raise exception 'Há parcela seguinte já paga ou cancelada: cancele em vez de excluir.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  -- apaga da ponta para trás (FK restrict); trigger só permite previsto
  loop
    delete from public.lancamentos d
     where (d.id = p_id or d.id in (
             with recursive cadeia as (
               select id from public.lancamentos where lancamento_origem_id = p_id
               union all
               select f.id from public.lancamentos f join cadeia c on f.lancamento_origem_id = c.id
             ) select id from cadeia))
       and not exists (select 1 from public.lancamentos f where f.lancamento_origem_id = d.id);
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
end;
$$;
revoke all on function public.excluir_lancamento(uuid) from public, anon;
grant execute on function public.excluir_lancamento(uuid) to authenticated;
