-- Testes da migration 0095 (API de consulta de cliente: tokens). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'API TESTE', 'api-teste') returning id into v_neg;
end $$;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='api-teste') neg;

-- T1: membro gera token — nasce ativo, com prefixo de 8 caracteres, hash gravado (nunca o valor puro)
do $$ declare v r%rowtype; g record; begin
  select * into v from r;
  select * into g from public.criar_api_token(v.neg, 'Leveduca');
  assert char_length(g.token) = 48, 'T1 token com 48 caracteres hex: ' || char_length(g.token);
  assert g.token_prefixo = left(g.token, 8), 'T1 prefixo bate com o início do token';
  assert exists (select 1 from public.api_tokens where id = g.token_id and ativo and token_prefixo = g.token_prefixo), 'T1 token gravado ativo';
  assert not exists (select 1 from public.api_tokens where token_hash = g.token), 'T1 hash nunca é o valor puro';
  assert exists (select 1 from public.api_tokens where id = g.token_id and token_hash = encode(digest(g.token, 'sha256'), 'hex')), 'T1 hash bate com sha256(token)';
end $$;

-- T2: nome curto demais é rejeitado
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    perform public.criar_api_token(v.neg, 'X');
    raise exception 'T2 nome curto deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: quem não é membro da organização não gera token
do $$ declare v r%rowtype; begin
  select * into v from r;
  set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
  begin
    perform public.criar_api_token(v.neg, 'Intruso');
    raise exception 'T3 não-membro não deveria gerar token';
  exception when insufficient_privilege then null; end;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
end $$;

-- T4: revogar marca ativo=false e revogado_em; vw_api_tokens reflete
do $$ declare v r%rowtype; g record; begin
  select * into v from r;
  select * into g from public.criar_api_token(v.neg, 'Revogável');
  perform public.revogar_api_token(g.token_id);
  assert (select ativo from public.api_tokens where id = g.token_id) = false, 'T4 token revogado fica inativo';
  assert (select revogado_em from public.api_tokens where id = g.token_id) is not null, 'T4 revogado_em preenchido';
  assert (select ativo from public.vw_api_tokens where id = g.token_id) = false, 'T4 view reflete revogação';
end $$;

-- T5: vw_api_tokens nunca expõe o hash (só a view existe pra isso — checagem estrutural)
do $$ begin
  assert not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'vw_api_tokens' and column_name = 'token_hash'
  ), 'T5 view não expõe token_hash';
end $$;

-- T6: log de consultas soma por token, sem CPF completo no relatório — a gravação
-- é feita como service_role (é o que a Edge Function usa; authenticated só lê).
create temp table t6 as select (select org from r) org, g.token_id from public.criar_api_token((select neg from r), 'Auditoria') g;
grant select on t6 to service_role;
set local role service_role;
do $$ declare v t6%rowtype; begin
  select * into v from t6;
  insert into public.api_consultas (organizacao_id, token_id, documento_consultado, encontrado) values (v.org, v.token_id, '12345678901', true);
end $$;
set local role authenticated;
do $$ declare v t6%rowtype; begin
  select * into v from t6;
  assert (select consultas from public.vw_api_tokens where id = v.token_id) = 1, 'T6 contagem de consultas na view';
  assert exists (select 1 from public.vw_rel_api_consultas where token = 'Auditoria' and documento_mascarado = '***901' and situacao = 'Encontrado'), 'T6 relatório mascara o documento';
end $$;

rollback;
\echo OK
