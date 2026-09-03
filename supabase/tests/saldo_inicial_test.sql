-- Testes da migration 0028 (saldo_inicial_mes). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial, data_inicio) select org, 'Banco pessoal', 'corrente', 1000, '2026-01-01' from ids;
insert into public.contas (organizacao_id, nome, tipo, negocio_id, saldo_inicial, data_inicio) select org, 'Banco SERVNET', 'corrente', (select id from public.negocios where slug='servnet'), 500, '2026-01-01' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco pessoal') pessoal, (select id from public.contas where nome='Banco SERVNET') servnet,
  (select id from public.categorias where nome='Salário') cat_rec, (select id from public.categorias where nome='Alimentação') cat_desp;
grant select on r to service_role, anon;

do $$ declare v r%rowtype; l public.lancamentos; begin
  select * into v from r;
  -- agosto/2026: +2000 na pessoal (salário), -300 na servnet (despesa)
  l := public.criar_lancamento('receita', 'Salário', 2000, date '2026-08-05', date '2026-08-05', date '2026-08-05', v.pessoal, null, v.cat_rec, null, null, null, null, false, null, null, null);
  l := public.criar_lancamento('despesa', 'Fornecedor', 300, date '2026-08-10', date '2026-08-10', date '2026-08-10', v.servnet, null, v.cat_desp, null, (select id from public.negocios where slug='servnet'), null, null, false, null, null, null);
  -- setembro/2026 (não deve entrar no saldo inicial de setembro nem de agosto)
  l := public.criar_lancamento('receita', 'Outro', 999, date '2026-09-05', date '2026-09-05', date '2026-09-05', v.pessoal, null, v.cat_rec, null, null, null, null, false, null, null, null);

  -- saldo inicial de agosto/2026 = só saldo_inicial (nada efetivado antes de agosto)
  assert (select saldo from public.saldo_inicial_mes(date '2026-08-01') where negocio_id is null) = 1000, 'saldo inicial pessoal em agosto = 1000';
  assert (select saldo from public.saldo_inicial_mes(date '2026-08-01') where negocio_id = (select id from public.negocios where slug='servnet')) = 500, 'saldo inicial servnet em agosto = 500';

  -- saldo inicial de setembro/2026 = saldo_inicial + movimentos de agosto
  assert (select saldo from public.saldo_inicial_mes(date '2026-09-01') where negocio_id is null) = 3000, 'saldo inicial pessoal em setembro = 1000+2000';
  assert (select saldo from public.saldo_inicial_mes(date '2026-09-15') where negocio_id = (select id from public.negocios where slug='servnet')) = 200, 'saldo inicial servnet em setembro = 500-300';

  -- conta aberta durante o mês não entra no saldo inicial daquele mês
  insert into public.contas (organizacao_id, nome, tipo, saldo_inicial, data_inicio) select v.org, 'Nova conta', 'corrente', 5000, date '2026-08-20';
  assert (select saldo from public.saldo_inicial_mes(date '2026-08-01') where negocio_id is null) = 1000, 'conta aberta no mês não conta no saldo inicial daquele mês';
  assert (select saldo from public.saldo_inicial_mes(date '2026-09-01') where negocio_id is null) = 8000, 'conta aberta em agosto já conta no saldo inicial de setembro (1000+2000+5000)';
end $$;
rollback;
\echo OK
