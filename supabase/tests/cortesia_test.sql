-- Testes da migration 0078 (contrato cortesia). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; v_cat uuid; v_ct uuid; v_ct0 uuid; e record; v_rel jsonb; begin
  select org into v_org from ids;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Cort', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_receita_id, conta_padrao_id) values (v_org, 'CORT T', 'cort-t', true, v_cat, v_conta) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Cortesia') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Cort', 100, 'mensal') returning id into v_plano;

  -- T1: cortesia exige valor 0
  begin
    insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
    values (v_org, v_neg, v_p, v_plano, 50, 'mensal', current_date - 40, 10, true);
    raise exception 'T1 aceitou cortesia com valor > 0';
  exception when check_violation then null; end;

  -- T2: cortesia fatura sem pendência e sem lançamento
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
  values (v_org, v_neg, v_p, v_plano, 0, 'mensal', current_date - 40, 10, true) returning id into v_ct;
  select * into e from public.gerar_faturamento_agora(current_date);
  if exists (select 1 from jsonb_array_elements(e.pendencias) x where (x->>'contrato_id')::uuid = v_ct) then raise exception 'T2 cortesia virou pendência'; end if;
  if exists (select 1 from public.lancamentos where contrato_id = v_ct) then raise exception 'T2 gerou lançamento'; end if;

  -- T3: valor 0 SEM cortesia continua pendência (erro de cadastro)
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  values (v_org, v_neg, v_p, v_plano, 0, 'mensal', current_date - 40, 15) returning id into v_ct0;
  select * into e from public.gerar_faturamento_agora(current_date);
  if not exists (select 1 from jsonb_array_elements(e.pendencias) x where (x->>'contrato_id')::uuid = v_ct0 and x->>'motivo' = 'Contrato com valor zero.') then raise exception 'T3 sem pendência: %', e.pendencias; end if;
  if exists (select 1 from jsonb_array_elements(e.pendencias) x where (x->>'contrato_id')::uuid = v_ct) then raise exception 'T3 cortesia virou pendência'; end if;

  -- T4: importação com cortesia → contrato valor 0 e flag; plano existente mantém o valor de tabela
  v_rel := public.importar_clientes(v_neg, jsonb_build_array(
    jsonb_build_object('linha', 2, 'nome', 'Importado Cortesia', 'plano', 'Plano Cort', 'cortesia', true, 'data_inicio', to_char(current_date, 'DD/MM/YYYY')),
    jsonb_build_object('linha', 3, 'nome', 'Importado Pagante', 'plano', 'Plano Cort', 'data_inicio', to_char(current_date, 'DD/MM/YYYY'))
  ), false, current_date);
  if (v_rel->>'importadas')::int <> 2 then raise exception 'T4 importadas=%', v_rel->>'importadas'; end if;
  if not exists (select 1 from public.contratos c join public.pessoas p on p.id = c.pessoa_id where p.nome = 'Importado Cortesia' and c.cortesia and c.valor = 0) then raise exception 'T4 cortesia não marcada'; end if;
  if not exists (select 1 from public.contratos c join public.pessoas p on p.id = c.pessoa_id where p.nome = 'Importado Pagante' and not c.cortesia and c.valor = 100) then raise exception 'T4 pagante errado'; end if;
  if (select valor_tabela from public.planos where id = v_plano) <> 100 then raise exception 'T4 plano alterado'; end if;
end $$;

rollback;
\echo OK
