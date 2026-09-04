-- Testes da migration 0035 (excluir parcela exclui a cadeia prevista). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Excl', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Excl') conta, (select id from public.categorias where nome='Moradia') moradia;

-- T1: excluir a raiz prevista apaga a cadeia inteira
do $$ declare v r%rowtype; l1 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Cadeia A', 10, date '2026-09-10', date '2026-09-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 3);
  perform public.excluir_lancamento(l1.id);
  select count(*) into n from public.lancamentos where descricao = 'Cadeia A';
  assert n = 0, 'T1 cadeia inteira excluída, restou ' || n;
end $$;

-- T2: excluir do meio apaga do meio para frente; anteriores ficam
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; n int; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Cadeia B', 10, date '2026-09-10', date '2026-09-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 3);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  perform public.excluir_lancamento(l2.id);
  select count(*) into n from public.lancamentos where descricao = 'Cadeia B';
  assert n = 1, 'T2 só a raiz fica, restou ' || n;
end $$;

-- T3: com parcela seguinte paga, excluir é recusado com orientação
do $$ declare v r%rowtype; l1 public.lancamentos; l2 public.lancamentos; begin
  select * into v from r;
  l1 := public.criar_lancamento('despesa', 'Cadeia C', 10, date '2026-09-10', date '2026-09-10', null, v.conta, null, v.moradia, null, null, null, null, true, 'mensal', null, null);
  perform public.projetar_lancamento(l1.id, 2);
  select * into l2 from public.lancamentos where lancamento_origem_id = l1.id;
  perform public.efetivar_lancamento(l2.id, date '2026-10-10');
  begin
    perform public.excluir_lancamento(l1.id);
    raise exception 'T3 deveria recusar (seguinte paga)';
  exception when check_violation then null; end;
end $$;

rollback;
\echo OK
