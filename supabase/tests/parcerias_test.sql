-- Testes da migration 0103 (parcerias — clube de benefícios do Portal, etapa 59). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('99999999-9999-9999-9999-999999999902', 'parcerias-cliente@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_p1 uuid; v_plano uuid; v_conta uuid; v_cat uuid; v_ct uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PARCERIAS', 'parcerias-teste', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Parcerias', '92988889002') returning id into v_p1;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Parcerias', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Parcerias', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg, v_p1, v_plano, 100, 'mensal', current_date - 30, 20, v_conta, 'ativo') returning id into v_ct;
end $$;

create temp table r as select
  (select id from public.negocios where slug='parcerias-teste') neg,
  (select organizacao_id from public.negocios where slug='parcerias-teste') org,
  (select id from public.pessoas where nome='Cliente Parcerias') p1;
grant select on r to service_role;

-- T1: cadastro manual (origem servnet) funciona direto
do $$ declare v r%rowtype; pa public.parcerias%rowtype; begin
  select * into v from r;
  insert into public.parcerias (organizacao_id, negocio_id, nome, beneficio, categoria)
  values (v.org, v.neg, 'Academia Parceira', '20% de desconto na mensalidade', 'Saúde')
  returning * into pa;
  assert pa.origem = 'servnet', 'T1 origem default deveria ser servnet, veio ' || pa.origem;
  assert pa.ativo = true, 'T1 ativo default deveria ser true';
end $$;

-- T2: inserir direto com origem='leveduca' (sem o flag erp.motor) é rejeitado
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    insert into public.parcerias (organizacao_id, negocio_id, origem, nome, beneficio) values (v.org, v.neg, 'leveduca', 'Teste Direto', 'Desconto qualquer');
    raise exception 'T2 insert direto com origem leveduca deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: importar_parcerias_leveduca cria a primeira leva
do $$ declare v r%rowtype; v_total int; begin
  select * into v from r;
  select public.importar_parcerias_leveduca(v.neg, '[
    {"nome":"Casas Bahia","tipo":"Online","beneficio":"25% desconto em itens selecionados","categoria":"Eletroeletrônico","cobertura":"Nacional","status":"Ativo"},
    {"nome":"Dell","tipo":"Online","beneficio":"Ate 7% de desconto","categoria":"Eletroeletrônico","cobertura":"Nacional","status":"Ativo"},
    {"nome":"Parceiro Inativo","tipo":"Online","beneficio":"Benefício desativado","categoria":"Outros","cobertura":"Nacional","status":"Inativo"}
  ]'::jsonb) into v_total;
  assert v_total = 3, 'T3 deveria importar 3 linhas, veio ' || v_total;
  assert (select count(*) from public.parcerias where negocio_id = v.neg and origem = 'leveduca') = 3, 'T3 deveria ter 3 parcerias leveduca no banco';
  assert (select ativo from public.parcerias where negocio_id = v.neg and nome = 'Parceiro Inativo') = false, 'T3 status Inativo deveria virar ativo=false';
end $$;

-- T4: reimportar substitui a lista inteira (não acumula)
do $$ declare v r%rowtype; v_total int; begin
  select * into v from r;
  select public.importar_parcerias_leveduca(v.neg, '[
    {"nome":"Canon","tipo":"Online","beneficio":"Até 30% desconto","categoria":"Eletroeletrônico","cobertura":"Nacional","status":"Ativo"}
  ]'::jsonb) into v_total;
  assert v_total = 1, 'T4 deveria importar 1 linha, veio ' || v_total;
  assert (select count(*) from public.parcerias where negocio_id = v.neg and origem = 'leveduca') = 1, 'T4 a lista antiga deveria ter sido apagada';
  assert not exists (select 1 from public.parcerias where negocio_id = v.neg and nome = 'Casas Bahia'), 'T4 Casas Bahia não deveria mais existir';
  assert (select count(*) from public.parcerias where negocio_id = v.neg and origem = 'servnet') = 1, 'T4 parceiro servnet (T1) não deveria ser afetado pela importação';
end $$;

-- T4b: admin desativa e reativa uma parceria leveduca direto (update, sem flag erp.motor) — só INSERT é travado
do $$ declare v r%rowtype; v_id uuid; begin
  select * into v from r;
  select id into v_id from public.parcerias where negocio_id = v.neg and nome = 'Canon';
  update public.parcerias set ativo = false where id = v_id;
  assert (select ativo from public.parcerias where id = v_id) = false, 'T4b deveria conseguir desativar direto';
  update public.parcerias set ativo = true where id = v_id;
end $$;

-- T4c: admin guarda uma foto (arte) na parceria — não muda origem/negócio
do $$ declare v r%rowtype; v_id uuid; begin
  select * into v from r;
  select id into v_id from public.parcerias where negocio_id = v.neg and nome = 'Canon';
  update public.parcerias set foto1 = 'data:image/jpeg;base64,AAAA' where id = v_id;
  assert (select foto1 from public.parcerias where id = v_id) = 'data:image/jpeg;base64,AAAA', 'T4c foto1 deveria ter sido salva';
  begin
    update public.parcerias set foto1 = 'https://exemplo.com/foto.jpg' where id = v_id;
    raise exception 'T4c foto que não é data:image/ deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: portal_parcerias só traz ativos, ordenado por categoria/nome
-- (o id do negócio vem de r, pego ANTES de trocar de role — select direto em
-- public.negocios sob a role do portal cairia na RLS e voltaria null)
do $$ declare v_neg uuid; begin select neg into v_neg from r; perform set_config('erp.teste_neg', v_neg::text, false); end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999902';
do $$ declare v_neg uuid; v_total int; begin
  v_neg := current_setting('erp.teste_neg')::uuid;
  select count(*) into v_total from public.portal_parcerias(v_neg);
  assert v_total = 2, 'T5 portal_parcerias deveria trazer 2 (Canon + Academia Parceira), veio ' || v_total;
  assert exists (select 1 from public.portal_parcerias(v_neg) where nome = 'Canon'), 'T5 Canon deveria aparecer';
  assert exists (select 1 from public.portal_parcerias(v_neg) where nome = 'Academia Parceira'), 'T5 Academia Parceira deveria aparecer';
end $$;
reset role;

-- T6: relatório vw_rel_parcerias enxerga tudo (leveduca + servnet)
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; v_total int; begin
  select * into v from r;
  select count(*) into v_total from public.vw_rel_parcerias where negocio_id = v.neg;
  assert v_total = 2, 'T6 relatório deveria ter 2 linhas (Canon + Academia Parceira), veio ' || v_total;
end $$;

rollback;
\echo OK
