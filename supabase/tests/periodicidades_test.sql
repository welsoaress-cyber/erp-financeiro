-- Testes da migration 0033 (periodicidades bimestral/trimestral/semestral). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'PERIOD TESTE', 'period-teste' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Period', 'corrente' from ids;
update public.negocios set conta_padrao_id = (select id from public.contas where nome='Banco Period'),
  categoria_receita_id = (select id from public.categorias where nome='Salário' limit 1)
  where slug='period-teste';
insert into public.pessoas (organizacao_id, nome) select org, 'Cliente Period' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade)
  select org, (select id from public.negocios where slug='period-teste'), 'Bimestral 60', 60, 'bimestral' from ids;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='period-teste') neg,
  (select id from public.pessoas where nome='Cliente Period') cli,
  (select id from public.planos where nome='Bimestral 60') plano;

-- T1: contrato bimestral fatura mês sim, mês não
do $$ declare n int; v_datas date[]; begin
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    select org, neg, cli, plano, 60, 'bimestral', date '2026-01-10', 10 from r;
  perform public.gerar_faturamento_agora(date '2026-07-15');
  select count(*), array_agg(l.data_vencimento order by l.data_vencimento) into n, v_datas
    from public.lancamentos l where l.contrato_id = (select id from public.contratos where plano_id = (select plano from r));
  assert n = 4, 'T1 jan/mar/mai/jul = 4 cobranças, veio ' || n;
  assert v_datas = array[date '2026-01-10', date '2026-03-10', date '2026-05-10', date '2026-07-10'], 'T1 datas bimestrais: ' || v_datas::text;
end $$;

-- T2: importar_clientes com periodicidade trimestral por linha; inválida rejeita
do $$ declare v_rel jsonb; v_ct public.contratos%rowtype; begin
  v_rel := public.importar_clientes((select neg from r), jsonb_build_array(
    jsonb_build_object('nome', 'Trimestral da Silva', 'documento', '52998224725', 'telefone', '14991234567',
                       'plano', 'Trimestral 90', 'valor', '90', 'dia_vencimento', '15', 'data_inicio', '2026-08-01',
                       'periodicidade', 'trimestral'),
    jsonb_build_object('nome', 'Errado de Souza', 'documento', '11144477735', 'telefone', '14991234568',
                       'plano', 'Plano X', 'valor', '10', 'dia_vencimento', '15', 'data_inicio', '2026-08-01',
                       'periodicidade', 'quinzenal')
  ), false);
  assert (v_rel->>'importadas')::int = 1 and (v_rel->>'rejeitadas')::int = 1, 'T2 1 importada e 1 rejeitada: ' || v_rel::text;
  select c.* into v_ct from public.contratos c join public.pessoas p on p.id = c.pessoa_id where p.documento = '52998224725';
  assert v_ct.periodicidade = 'trimestral', 'T2 contrato trimestral';
  assert (select periodicidade from public.planos where nome = 'Trimestral 90') = 'trimestral', 'T2 plano trimestral';
end $$;

-- T3: projeção de contratos respeita o passo (bimestral projeta mês sim, mês não)
do $$ declare n int; begin
  select count(*) into n from public.projecao_contratos((select org from r),
    (date_trunc('month', current_date) + interval '1 month')::date,
    (date_trunc('month', current_date) + interval '12 months')::date)
    where contrato_id = (select id from public.contratos where plano_id = (select plano from r));
  assert n between 5 and 6, 'T3 bimestral projeta ~6 em 12 meses, veio ' || n;
end $$;

rollback;
\echo OK
