-- Testes da migration 0137 (projeção de saldo mês a mês). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SALDO PROJ T', 'saldo-proj-t' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Saldo Proj', 'corrente' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Cliente Saldo Proj' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='saldo-proj-t'), 'Fibra Saldo Proj', 100 from ids;
update public.negocios set conta_padrao_id = (select id from public.contas where nome='Banco Saldo Proj'),
  categoria_receita_id = (select id from public.categorias where nome='Salário' limit 1),
  categoria_despesa_id = (select id from public.categorias where tipo='despesa' limit 1)
  where slug='saldo-proj-t';
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='saldo-proj-t') neg,
  (select id from public.pessoas where nome='Cliente Saldo Proj') cli,
  (select id from public.planos where nome='Fibra Saldo Proj') fibra,
  date_trunc('month', current_date)::date mes_atual,
  (date_trunc('month', current_date) + interval '1 month')::date mes_seguinte,
  (date_trunc('month', current_date) + interval '2 months')::date mes_2;

-- contrato mensal recorrente (fatura o mês seguinte sozinho via projeção)
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, neg, cli, fibra, 100, 'mensal', mes_atual, 10 from r;
select public.gerar_faturamento_agora(current_date);
-- lançamento vencido de mês anterior (atraso real) — deve cair no mês atual da projeção
do $$ declare v r%rowtype; v_cat uuid; begin
  select * into v from r;
  select id into v_cat from public.categorias where organizacao_id = v.org and tipo = 'despesa' limit 1;
  perform public.criar_lancamento('despesa', 'Atrasada', 40, (v.mes_atual - interval '1 month')::date, (v.mes_atual - interval '1 month')::date,
    null, (select id from public.contas where nome = 'Banco Saldo Proj'), null, v_cat, null, v.neg, v.cli, null);
end $$;
create temp table lanc_atrasada as select id from public.lancamentos where descricao = 'Atrasada';

-- T1: atrasado de mês anterior cai no bucket do mês atual, não em um mês passado
do $$ declare v r%rowtype; total numeric; begin
  select * into v from r;
  select coalesce(sum(valor), 0) into total from public.projecao_saldo_mensal(v.org, v.mes_2)
   where negocio_id = v.neg and mes < v.mes_atual;
  assert total = 0, 'T1 nada antes do mês atual: ' || total;
  select coalesce(sum(valor), 0) into total from public.projecao_saldo_mensal(v.org, v.mes_2)
   where negocio_id = v.neg and mes = v.mes_atual and tipo = 'despesa';
  assert total = 40, 'T1 atrasada entra no mês atual: ' || total;
end $$;

-- T2: mês seguinte traz a receita projetada do contrato (ainda não faturado)
do $$ declare v r%rowtype; total numeric; begin
  select * into v from r;
  select coalesce(sum(valor), 0) into total from public.projecao_saldo_mensal(v.org, v.mes_2)
   where negocio_id = v.neg and mes = v.mes_seguinte and tipo = 'receita';
  assert total = 100, 'T2 projeção do contrato no mês seguinte: ' || total;
end $$;

-- T3: período inválido (antes do mês atual) falha
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    perform public.projecao_saldo_mensal(v.org, (v.mes_atual - interval '1 month')::date);
    raise exception 'T3 p_ate antes do mês atual deveria falhar';
  exception when check_violation then null; end;
end $$;

rollback;
\echo OK
