-- Remove tabelas lancamentos/movimentos criadas FORA da migration 0005 (sem o motor).
-- Travas: só age se a função criar_lancamento não existir E as tabelas estiverem vazias.
-- Depois de rodar, aplicar supabase/migrations/20260902000005_lancamentos.sql.
do $$
declare
  n_l bigint := 0;
  n_m bigint := 0;
begin
  if exists (select 1 from pg_proc where proname = 'criar_lancamento' and pronamespace = 'public'::regnamespace) then
    raise exception 'O motor financeiro já existe neste banco. Nada foi alterado.';
  end if;
  if to_regclass('public.lancamentos') is not null then execute 'select count(*) from public.lancamentos' into n_l; end if;
  if to_regclass('public.movimentos')  is not null then execute 'select count(*) from public.movimentos'  into n_m; end if;
  if n_l > 0 or n_m > 0 then
    raise exception 'As tabelas possuem dados (lancamentos=%, movimentos=%). Limpeza não executada: avise o assistente.', n_l, n_m;
  end if;

  drop view  if exists public.vw_resultado_mensal;
  drop view  if exists public.vw_saldo_contas;
  drop table if exists public.movimentos  cascade;
  drop table if exists public.lancamentos cascade;
  drop type  if exists public.tipo_lancamento   cascade;
  drop type  if exists public.status_lancamento cascade;
  drop type  if exists public.origem_lancamento cascade;
  raise notice 'Tabelas externas removidas. Agora aplique a migration 0005.';
end $$;
