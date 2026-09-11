-- Testes da migration 0063 (aceite digital). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('66666666-6666-6666-6666-666666666666', 'aceite@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_plano uuid; v_conta uuid; v_ct uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'ACEITE T', 'aceite-t', true) returning id into v_neg;
  insert into public.portal_config (organizacao_id, negocio_id) values (v_org, v_neg);
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Cliente Aceite', '52998224725') returning id into v_p;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Aceite', 110, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Aceite', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 110, 'mensal', current_date, 10, v_conta) returning id into v_ct;
end $$;
create temp table r as select
  (select c.id from public.contratos c join public.negocios n on n.id=c.negocio_id where n.slug='aceite-t') ct,
  (select id from public.pessoas where nome='Cliente Aceite') pessoa;
grant select on r to service_role;

-- vincula o portal
set local role service_role;
do $$ begin perform public.portal_vincular_servico((select pessoa from r), '66666666-6666-6666-6666-666666666666'); end $$;

-- T1: termo renderizado com os dados; aceite via service com IP; duplicado bloqueado
do $$ declare v r%rowtype; t text; a public.aceites_contrato%rowtype; begin
  select * into v from r;
  t := public.contrato_texto_termo(v.ct);
  assert t like '%Cliente Aceite%' and t like '%R$ 110,00%' and t like '%dia 10%' and t like '%ACEITE T%', 'T1 termo renderizado';
  a := public.registrar_aceite_contrato(v.ct, v.pessoa, '187.10.20.30', 'Mozilla/5.0 Teste');
  assert a.ip = '187.10.20.30' and a.texto_hash = md5(t) and a.texto = t, 'T1 aceite gravado com hash';
  begin
    perform public.registrar_aceite_contrato(v.ct, v.pessoa, '1.1.1.1', 'x');
    raise exception 'T1 aceite duplicado deveria falhar';
  exception when check_violation then null; end;
end $$;
set local role authenticated;

-- T2: portal vê a situação; imutável; admin vê o aceite
set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
do $$ declare m record; begin
  select * into m from public.portal_meus_aceites();
  assert m.aceito and m.data_aceite is not null, 'T2 aceito no portal';
end $$;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  select count(*) into n from public.aceites_contrato where contrato_id = v.ct;
  assert n = 1, 'T2 admin vê o aceite';
  begin
    update public.aceites_contrato set ip = '9.9.9.9' where contrato_id = v.ct;
    raise exception 'T2 alterar aceite deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
end $$;

rollback;
\echo OK
