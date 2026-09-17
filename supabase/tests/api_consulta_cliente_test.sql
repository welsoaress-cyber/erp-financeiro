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

-- 0096: api_consultar_cliente é o único ponto de acesso da Edge Function — roda
-- como service_role (só ele tem EXECUTE), sem grant nenhum nas tabelas por baixo.
do $$ declare v_org uuid; v_neg uuid; v_plano uuid; v_pessoa_ativa uuid; v_pessoa_suspensa uuid; begin
  select org, neg into v_org, v_neg from r;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v_org, v_neg, 'Fibra 300 API', 99.9) returning id into v_plano;
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Cliente API Ativo', '11122233396') returning id into v_pessoa_ativa;
  insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Cliente API Suspenso', '98765432100') returning id into v_pessoa_suspensa;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, codigo, valor, periodicidade, status, tipo_financeiro)
    values (v_org, v_neg, v_pessoa_ativa, v_plano, 901, 99.9, 'mensal', 'ativo', 'receita');
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, codigo, valor, periodicidade, status, tipo_financeiro)
    values (v_org, v_neg, v_pessoa_suspensa, v_plano, 902, 99.9, 'mensal', 'suspenso', 'receita');
end $$;
create temp table t7 as select g.token, g.token_id from public.criar_api_token((select neg from r), 'RPC') g;
grant select on t7 to service_role;

set local role service_role;

-- T7: token válido + cliente com contrato ativo → status Ativo, plano certo
do $$ declare v t7%rowtype; l record; begin
  select * into v from t7;
  select * into l from public.api_consultar_cliente(encode(digest(v.token, 'sha256'), 'hex'), '11122233396');
  assert l.situacao = 'ok', 'T7 situação ok: ' || l.situacao;
  assert l.cliente->>'nome_completo' = 'Cliente API Ativo', 'T7 nome bate';
  assert l.cliente->>'status_cliente' = 'Ativo', 'T7 status Ativo: ' || (l.cliente->>'status_cliente');
  assert l.cliente->>'plano' = 'Fibra 300 API', 'T7 plano bate';
  assert l.cliente->>'numero' is null and l.cliente->>'cep' is null, 'T7 numero/cep nulos (não existem separados)';
end $$;

-- T8: contrato suspenso → status_cliente Inativo (binário: só Ativo libera o curso), status_plano continua Suspenso
do $$ declare v t7%rowtype; l record; begin
  select * into v from t7;
  select * into l from public.api_consultar_cliente(encode(digest(v.token, 'sha256'), 'hex'), '98765432100');
  assert l.cliente->>'status_cliente' = 'Inativo', 'T8 status_cliente Inativo: ' || (l.cliente->>'status_cliente');
  assert l.cliente->>'status_plano' = 'Suspenso', 'T8 status_plano continua Suspenso: ' || (l.cliente->>'status_plano');
end $$;

-- T9: CPF que não é cliente dessa organização → não encontrado, fica auditado
do $$ declare v t7%rowtype; l record; begin
  select * into v from t7;
  select * into l from public.api_consultar_cliente(encode(digest(v.token, 'sha256'), 'hex'), '99988877665');
  assert l.situacao = 'nao_encontrado', 'T9 não encontrado: ' || l.situacao;
  assert l.cliente is null, 'T9 cliente nulo';
  assert exists (select 1 from public.api_consultas where token_id = v.token_id and documento_consultado = '99988877665' and not encontrado), 'T9 auditoria registrada';
end $$;

-- T10: token revogado/inexistente → token_invalido, nunca vaza se o CPF existe ou não
do $$ declare l record; begin
  select * into l from public.api_consultar_cliente('hash-que-nao-existe', '11122233396');
  assert l.situacao = 'token_invalido', 'T10 token inválido: ' || l.situacao;
end $$;

set local role authenticated;

rollback;
\echo OK
