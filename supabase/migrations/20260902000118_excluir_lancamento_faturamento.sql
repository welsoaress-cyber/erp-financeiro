-- =============================================================================
-- 0118 · excluir_lancamento barra cobrança de contrato com mensagem clara
-- =============================================================================
-- Cobrança gerada por contrato (origem = 'faturamento') tem uma linha em
-- faturamentos (controla "esta competência já foi cobrada") apontando pra ela
-- com on delete restrict. A tela ainda oferecia "Excluir" pra qualquer
-- previsto, e o clique estourava o erro cru do Postgres
-- ("update or delete on table lancamentos violates foreign key constraint
-- faturamentos_lancamento_id_fkey"). O botão já foi escondido nesse caso na
-- tela (a ação certa é Cancelar, que não mexe em faturamentos); aqui é a
-- blindagem do lado do banco, pra quem chamar a função direto também receber
-- uma mensagem útil em vez do erro de FK.
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
  if l.origem = 'faturamento' then
    raise exception 'Cobrança gerada por contrato não pode ser excluída. Use Cancelar.' using errcode = 'check_violation';
  end if;
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
