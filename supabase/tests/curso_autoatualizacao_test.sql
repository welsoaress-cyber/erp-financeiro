-- Testes da migration 0107 (autoatualização de cadastro pro curso, página pública). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
grant select on ids to anon;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_p1 uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'Servnet Telecomunicações Ltda', 'servnet-curso', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Curso', 'dinheiro', v_neg) returning id into v_conta;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  update public.negocios set conta_padrao_id = v_conta, categoria_receita_id = v_cat where id = v_neg;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade, ativo) values (v_org, v_neg, 'Curso Leveduca', 0, 'mensal', true);
  insert into public.pessoas (organizacao_id, nome, telefone, ativo) values (v_org, 'Cliente Curso', '11954490001', true) returning id into v_p1;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug = 'servnet-curso') neg,
  (select p.id from public.planos p join public.negocios n on n.id = p.negocio_id where n.slug = 'servnet-curso') plano,
  (select id from public.pessoas where nome = 'Cliente Curso') pessoa;
grant select on r to anon;

-- T0: anon não lê pessoas direto (RLS) — só via RPC security definer
set local role anon;
do $$ begin
  perform 1 from public.pessoas limit 1;
  raise exception 'T0 anon não deveria ler pessoas direto';
exception when insufficient_privilege then null; end $$;

-- T1: busca por telefone acha a pessoa (com e sem +55/DDI)
do $$ declare j jsonb; v r%rowtype; begin
  select * into v from r;
  j := public.curso_buscar_pessoa('11954490001');
  assert (j->>'encontrado')::boolean and j->>'pessoa_id' = v.pessoa::text and j->>'nome' = 'Cliente Curso', 'T1 achou pelo telefone puro: ' || j::text;
  j := public.curso_buscar_pessoa('+55 (11) 95449-0001');
  assert (j->>'encontrado')::boolean, 'T1 achou com formatação e DDI: ' || j::text;
  assert j->>'cpf' is null and j->>'email' is null, 'T1 campos vazios antes de atualizar';
end $$;

-- T2: telefone que não existe
do $$ declare j jsonb; begin
  j := public.curso_buscar_pessoa('11900000000');
  assert not (j->>'encontrado')::boolean, 'T2 telefone não encontrado';
end $$;

-- T3: validações (CPF, e-mail, data de nascimento)
do $$ declare v r%rowtype; falhou boolean; begin
  select * into v from r;
  falhou := false;
  begin perform public.curso_atualizar_cadastro(v.pessoa, '123', 'a@b.com', '2000-01-01');
  exception when check_violation then falhou := true; end;
  assert falhou, 'T3 CPF inválido recusado';
  falhou := false;
  begin perform public.curso_atualizar_cadastro(v.pessoa, '52998224725', 'nao-e-email', '2000-01-01');
  exception when check_violation then falhou := true; end;
  assert falhou, 'T3 e-mail inválido recusado';
  falhou := false;
  begin perform public.curso_atualizar_cadastro(v.pessoa, '52998224725', 'a@b.com', current_date + 1);
  exception when check_violation then falhou := true; end;
  assert falhou, 'T3 data de nascimento futura recusada';
end $$;

-- T4: atualização válida — atualiza cadastro e cria o contrato cortesia
do $$ declare v r%rowtype; j jsonb; begin
  select * into v from r;
  j := public.curso_atualizar_cadastro(v.pessoa, '529.982.247-25', 'cliente@teste.dev', '2000-05-10');
  assert (j->>'ok')::boolean and (j->>'contrato_criado')::boolean, 'T4 ok e contrato criado: ' || j::text;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; p public.pessoas%rowtype; c public.contratos%rowtype; begin
  select * into v from r;
  select * into p from public.pessoas where id = v.pessoa;
  assert p.documento = '52998224725' and p.email = 'cliente@teste.dev' and p.data_nascimento = '2000-05-10', 'T4 cadastro atualizado';
  select * into c from public.contratos where pessoa_id = v.pessoa and plano_id = v.plano;
  assert found, 'T4 contrato existe';
  assert c.status = 'ativo' and c.cortesia and c.valor = 0 and c.data_inicio = '2026-10-01' and c.dia_vencimento = 1 and c.tipo_financeiro = 'receita', 'T4 contrato com os dados certos: ' || c::text;
end $$;

-- T5: rodar de novo não duplica o contrato (idempotente)
set local role anon;
do $$ declare v r%rowtype; j jsonb; begin
  select * into v from r;
  j := public.curso_atualizar_cadastro(v.pessoa, '52998224725', 'cliente2@teste.dev', '2000-05-10');
  assert (j->>'ok')::boolean and not (j->>'contrato_criado')::boolean, 'T5 não recria contrato: ' || j::text;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  select count(*) into n from public.contratos where pessoa_id = v.pessoa and plano_id = v.plano;
  assert n = 1, 'T5 continua só 1 contrato';
end $$;

rollback;
\echo OK
