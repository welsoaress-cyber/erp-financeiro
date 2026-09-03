-- Testes da migration 0027 (contratos de fornecedor/despesa + lançamento automático ao criar). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.pessoas (organizacao_id, nome, documento) select org, 'João Cliente', '52998224725' from ids;
insert into public.pessoas (organizacao_id, nome, tipo, documento) select org, 'Fibra Distribuidora', 'juridica'::public.tipo_pessoa, '11222333000181' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90 from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet, (select id from public.pessoas where nome='João Cliente') joao,
  (select id from public.pessoas where nome='Fibra Distribuidora') fornecedor, (select id from public.planos where nome='Fibra 500') fibra, (select id from public.contas where nome='Banco') banco,
  (select id from public.categorias where nome='Salário') cat_rec, (select id from public.categorias where nome='Alimentação') cat_desp;
grant select on r to service_role, anon;

-- T1: negócio sem categoria de despesa → contrato criado, mas sem lançamento (pendência avisada)
do $$ declare v r%rowtype; c public.contratos%rowtype; n int; begin
  select * into v from r;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro, conta_id)
    values (v.org, v.servnet, v.fornecedor, v.fibra, 500, 'mensal', current_date, 10, 'despesa', v.banco) returning * into c;
  assert c.tipo_financeiro = 'despesa', 'T1 tipo_financeiro despesa';
  select count(*) into n from public.lancamentos where contrato_id = c.id; assert n = 0, 'T1 sem categoria de despesa: nenhum lançamento';
  assert (select papel from public.pessoa_negocio_vinculos where pessoa_id = v.fornecedor and negocio_id = v.servnet) = 'fornecedor', 'T1 vínculo fornecedor criado';
end $$;

-- T2: com categoria de despesa configurada, o lançamento de despesa nasce sozinho ao salvar o contrato
do $$ declare v r%rowtype; c public.contratos%rowtype; l public.lancamentos%rowtype; begin
  select * into v from r;
  update public.negocios set categoria_despesa_id = v.cat_desp where id = v.servnet;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro, conta_id)
    values (v.org, v.servnet, v.fornecedor, v.fibra, 500, 'mensal', current_date, 10, 'despesa', v.banco) returning * into c;
  select * into l from public.lancamentos where contrato_id = c.id;
  assert l.id is not null and l.tipo = 'despesa' and l.status = 'previsto' and l.valor = 500 and l.categoria_id = v.cat_desp and l.conta_id = v.banco and l.pessoa_id = v.fornecedor, 'T2 despesa gerada ao criar: ' || coalesce(l.tipo::text,'nenhuma');
  assert (select count(*) from public.descontos_contrato where contrato_id = c.id) = 0, 'T2 sem fidelidade/desconto em despesa';
end $$;

-- T3: contrato de receita (padrão) continua gerando a receita sozinho ao criar, como antes
do $$ declare v r%rowtype; c public.contratos%rowtype; l public.lancamentos%rowtype; begin
  select * into v from r;
  update public.negocios set categoria_receita_id = v.cat_rec where id = v.servnet;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
    values (v.org, v.servnet, v.joao, v.fibra, 99.90, 'mensal', current_date, 10, v.banco) returning * into c;
  assert c.tipo_financeiro = 'receita', 'T3 tipo_financeiro padrão receita';
  select * into l from public.lancamentos where contrato_id = c.id;
  assert l.id is not null and l.tipo = 'receita' and l.status = 'previsto' and l.valor = 99.90, 'T3 receita gerada ao criar';
  assert (select papel from public.pessoa_negocio_vinculos where pessoa_id = v.joao and negocio_id = v.servnet) = 'cliente', 'T3 vínculo cliente (comportamento anterior mantido)';
end $$;

-- T4: categoria de despesa precisa ser do tipo despesa
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    update public.negocios set categoria_despesa_id = v.cat_rec where id = v.servnet;
    raise exception 'T4 categoria de receita como despesa deveria falhar';
  exception when check_violation then null; end;
end $$;
rollback;
\echo OK
