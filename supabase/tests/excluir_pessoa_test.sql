-- Testes da migration 0064 (excluir pessoa sem histórico). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('77777777-7777-7777-7777-777777777777', 'excluir@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v_org uuid; v_neg uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'EXCL T', 'excl-t', true) returning id into v_neg;
end $$;

-- T1: pessoa sem histórico é excluída, levando vínculo de negócio e portal junto
do $$ declare v_org uuid; v_neg uuid; v_p uuid; begin
  select organizacao_id, id into v_org, v_neg from public.negocios where slug = 'excl-t';
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Sem Histórico', '52998224725') returning id into v_p;
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) values (v_org, v_p, v_neg, 'cliente');
end $$;
reset role;
insert into public.portal_acessos (organizacao_id, pessoa_id, usuario_id, codigo_indicacao)
select organizacao_id, id, '77777777-7777-7777-7777-777777777777', 'EXCLT001' from public.pessoas where nome = 'Sem Histórico';
set local role authenticated;
do $$ declare v_p uuid; begin
  select id into v_p from public.pessoas where nome = 'Sem Histórico';
  perform public.excluir_pessoa(v_p);
  assert not exists (select 1 from public.pessoas where id = v_p), 'T1 pessoa excluída';
  assert not exists (select 1 from public.pessoa_negocio_vinculos where pessoa_id = v_p), 'T1 vínculo excluído';
  assert not exists (select 1 from public.portal_acessos where pessoa_id = v_p), 'T1 acesso do portal excluído';
end $$;
reset role;
do $$ begin
  assert not exists (select 1 from auth.users where id = '77777777-7777-7777-7777-777777777777'), 'T1 login do portal excluído';
end $$;
set local role authenticated;

-- T2: pessoa com histórico (contrato) é barrada com erro amigável
do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; begin
  select organizacao_id, id into v_org, v_neg from public.negocios where slug = 'excl-t';
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Com Contrato', '15350946056') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Excl', 90, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Excl', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 90, 'mensal', current_date, 10, v_conta);
  begin
    perform public.excluir_pessoa(v_p);
    raise exception 'T2 deveria barrar pessoa com contrato';
  exception when check_violation then null; end;
  assert exists (select 1 from public.pessoas where id = v_p), 'T2 pessoa continua';
end $$;

-- T3: fora da organização não exclui
reset role;
create temp table _t3 as select id from public.pessoas where nome = 'Com Contrato';
grant select on _t3 to authenticated;
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ declare v_p uuid; begin
  select id into v_p from _t3;
  begin
    perform public.excluir_pessoa(v_p);
    raise exception 'T3 deveria negar fora da organização';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
