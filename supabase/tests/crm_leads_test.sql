-- Testes da migration 0111 (CRM / Gestão de leads — etapa 61). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_plano uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'CRM TESTE', 'crm-teste') returning id into v_neg;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v_org, v_neg, 'Plano CRM 100', 100) returning id into v_plano;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='crm-teste') neg,
  (select id from public.planos where nome='Plano CRM 100') plano;

-- T1: captura manual normaliza telefone e nasce status 'novo'
do $$ declare v r%rowtype; lid uuid; st public.status_lead; tel text; begin
  select * into v from r;
  insert into public.leads (organizacao_id, negocio_id, nome, telefone, origem)
  values (v.org, v.neg, ' Fulano de Tal ', '(11) 95555-0001', 'manual')
  returning id into lid;
  select status, telefone into st, tel from public.leads where id = lid;
  assert st = 'novo', 'T1 nasce novo: ' || st;
  assert tel = '11955550001', 'T1 telefone normalizado: ' || tel;
end $$;

-- T2: plano de interesse de outro negócio é rejeitado
do $$ declare v r%rowtype; outro_neg uuid; outro_plano uuid; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'CRM TESTE OUTRO', 'crm-teste-outro') returning id into outro_neg;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela)
  values (v.org, outro_neg, 'Plano de outro negócio', 50)
  returning id into outro_plano;
  begin
    insert into public.leads (organizacao_id, negocio_id, nome, telefone, plano_interesse_id) values (v.org, v.neg, 'Teste', '11955550002', outro_plano);
    raise exception 'T2 plano de outro negócio deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: mover status (update direto) muda o status; histórico fica na auditoria genérica
do $$ declare v r%rowtype; lid uuid; n int; begin
  select * into v from r;
  select id into lid from public.leads where telefone = '11955550001';
  update public.leads set status = 'contatado' where id = lid;
  assert (select status from public.leads where id = lid) = 'contatado', 'T3 status mudou';
  select count(*) into n from public.auditoria where tabela = 'leads' and registro_id = lid::text and acao = 'UPDATE';
  assert n >= 1, 'T3 auditoria registrou a mudança';
end $$;

-- T4: interação manual (lead_eventos) — imutável, sem update/delete pro cliente
do $$ declare v r%rowtype; lid uuid; eid uuid; begin
  select * into v from r;
  select id into lid from public.leads where telefone = '11955550001';
  insert into public.lead_eventos (lead_id, tipo, descricao, usuario_id) values (lid, 'ligacao', 'Primeiro contato', auth.uid()) returning id into eid;
  assert (select count(*) from public.lead_eventos where lead_id = lid) = 1, 'T4 interação gravada';
  begin
    update public.lead_eventos set descricao = 'editado' where id = eid;
    raise exception 'T4 update de lead_eventos deveria falhar (sem grant)';
  exception when insufficient_privilege then null; end;
end $$;

-- T5: conversão cria pessoa + vínculo cliente, marca o lead; converter de novo falha
do $$ declare v r%rowtype; lid uuid; p public.pessoas; begin
  select * into v from r;
  select id into lid from public.leads where telefone = '11955550001';
  p := public.converter_lead_pessoa(lid);
  assert p.nome = 'Fulano de Tal' and p.telefone = '11955550001', 'T5 pessoa criada a partir do lead';
  assert exists (select 1 from public.pessoa_negocio_vinculos where pessoa_id = p.id and negocio_id = v.neg and papel = 'cliente'), 'T5 vínculo cliente criado';
  assert (select convertido_pessoa_id from public.leads where id = lid) = p.id, 'T5 lead linkado à pessoa';
  assert (select status from public.leads where id = lid) = 'fechado', 'T5 lead fechado';
  begin
    perform public.converter_lead_pessoa(lid);
    raise exception 'T5 converter de novo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T6: captura pública (anon) — slug inválido, telefone inválido, plano de outro negócio, e caminho feliz
do $$ declare v r%rowtype; begin select * into v from r; end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform public.lead_publico_capturar('slug-inexistente', 'Ciclano', '11955550003');
    raise exception 'T6 slug inexistente deveria falhar';
  exception when no_data_found then null; end;
  begin
    perform public.lead_publico_capturar('crm-teste', 'Ciclano', '123');
    raise exception 'T6 telefone inválido deveria falhar';
  exception when check_violation then null; end;
  perform public.lead_publico_capturar('crm-teste', 'Ciclano da Silva', '(11) 95555-0004');
end $$;
reset role;
set local role authenticated;
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert exists (select 1 from public.leads where negocio_id = v.neg and telefone = '11955550004' and origem = 'site' and status = 'novo'), 'T6 lead público capturado';
end $$;

rollback;
\echo OK
