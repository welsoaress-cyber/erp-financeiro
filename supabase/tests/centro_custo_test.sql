-- Testes da migration 0081 (centros de custo 54A). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_neg2 uuid; v_conta uuid; v_cat uuid; v_cc uuid; v_cc2 uuid; v_cto uuid; v_l public.lancamentos%rowtype; v_p uuid; v_plano uuid; v_ct uuid; e record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'despesa' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa CCu', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_despesa_id, conta_padrao_id) values (v_org, 'CCU T', 'ccu-t', true, v_cat, v_conta) returning id into v_neg;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'CCU T2', 'ccu-t2', true) returning id into v_neg2;

  -- T1: cadastro, nome único por negócio, ponto de rede exige CTO do mesmo negócio
  insert into public.centros_custo (organizacao_id, negocio_id, nome, tipo) values (v_org, v_neg, '  Administrativo ', 'departamento') returning id into v_cc;
  if (select nome from public.centros_custo where id = v_cc) <> 'Administrativo' then raise exception 'T1 nome não normalizado'; end if;
  begin
    insert into public.centros_custo (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'administrativo');
    raise exception 'T1 duplicou nome';
  exception when unique_violation then null; end;
  begin
    insert into public.centros_custo (organizacao_id, negocio_id, nome, tipo) values (v_org, v_neg, 'POP X', 'ponto_rede');
    raise exception 'T1 ponto_rede sem referência';
  exception when check_violation then null; end;
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas) values (v_org, v_neg, 'CTO-CCU', -3.1, -60.0, 16) returning id into v_cto;
  insert into public.centros_custo (organizacao_id, negocio_id, nome, tipo, referencia_id) values (v_org, v_neg, 'CTO-CCU', 'ponto_rede', v_cto) returning id into v_cc2;

  -- T2: lançamento com centro do mesmo negócio ok; de outro negócio barra; inativo barra
  v_l := public.criar_lancamento('despesa', 'CCU chave', 12, current_date, current_date, current_date, v_conta, null, v_cat, null, v_neg);
  v_l := public.definir_centro_custo_lancamento(v_l.id, v_cc);
  if v_l.centro_custo_id <> v_cc then raise exception 'T2 não definiu'; end if;
  begin
    perform public.definir_centro_custo_lancamento(v_l.id, (select id from public.centros_custo where nome = 'CTO-CCU' and negocio_id = v_neg));
  end;
  begin
    insert into public.centros_custo (organizacao_id, negocio_id, nome) values (v_org, v_neg2, 'Outro neg');
    perform public.definir_centro_custo_lancamento(v_l.id, (select id from public.centros_custo where nome = 'Outro neg'));
    raise exception 'T2 aceitou centro de outro negócio';
  exception when check_violation then null; end;
  update public.centros_custo set ativo = false where id = v_cc;
  begin
    perform public.definir_centro_custo_lancamento(v_l.id, v_cc);
    raise exception 'T2 aceitou centro inativo';
  exception when check_violation then null; end;
  update public.centros_custo set ativo = true where id = v_cc;
  perform public.definir_centro_custo_lancamento(v_l.id, v_cc);

  -- T3: contrato de fornecedor com centro → despesa mensal nasce classificada
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Fornecedor CCU') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Link CCU', 300, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro, centro_custo_id)
  values (v_org, v_neg, v_p, v_plano, 300, 'mensal', current_date - 5, 10, 'despesa', v_cc2) returning id into v_ct;
  select * into e from public.gerar_faturamento_agora(current_date);
  if not exists (select 1 from public.lancamentos where contrato_id = v_ct and centro_custo_id = v_cc2) then raise exception 'T3 fatura sem centro'; end if;

  -- T4: views — gastos por centro (Geral × nomeado) e lançamentos com o nome
  if (select centro_custo from public.vw_rel_lancamentos where id = v_l.id) <> 'Administrativo' then raise exception 'T4 nome no relatório'; end if;
  if (select sum(valor) from public.vw_rel_gastos_centro_custo where negocio_id = v_neg and centro_custo = 'Administrativo' and status = 'efetivado') <> 12 then raise exception 'T4 gastos por centro'; end if;
  if (select sum(valor) from public.vw_rel_gastos_centro_custo where negocio_id = v_neg and centro_custo = 'CTO-CCU') <> 300 then raise exception 'T4 gastos CTO'; end if;

  -- T5: sem DELETE; inativar é o caminho
  begin
    delete from public.centros_custo where id = v_cc2;
  exception when insufficient_privilege or foreign_key_violation then null; end;
  if not exists (select 1 from public.centros_custo where id = v_cc2) then raise exception 'T5 apagou centro em uso'; end if;
end $$;

rollback;
\echo OK
