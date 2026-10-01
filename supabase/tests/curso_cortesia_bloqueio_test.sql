-- Testes da migration 0114 (curso cortesia acompanha inadimplência dos outros contratos). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_cat uuid; v_contaA uuid; v_contaB uuid; v_negA uuid; v_negB uuid; v_pessoa uuid; v_planoCurso uuid; v_planoPago uuid; v_planoPresente uuid; begin
  select org into v_org from ids;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Curso Bloq', 'dinheiro') returning id into v_contaA;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Pago Bloq', 'dinheiro') returning id into v_contaB;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_receita_id, conta_padrao_id) values (v_org, 'Servnet Curso Bloq', 'servnet-curso-bloq', true, v_cat, v_contaA) returning id into v_negA;
  insert into public.negocios (organizacao_id, nome, slug, ativo, categoria_receita_id, conta_padrao_id) values (v_org, 'Provedor Pago Bloq', 'provedor-pago-bloq', true, v_cat, v_contaB) returning id into v_negB;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Dupla Bloq') returning id into v_pessoa;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_negA, 'Curso Leveduca Bloq', 0, 'mensal') returning id into v_planoCurso;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_negA, 'Presente Indicação Bloq', 50, 'mensal') returning id into v_planoPresente;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_negB, 'Internet Pago Bloq', 80, 'mensal') returning id into v_planoPago;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.pessoas where nome = 'Cliente Dupla Bloq') pessoa,
  (select p.id from public.planos p join public.negocios n on n.id = p.negocio_id where n.slug = 'servnet-curso-bloq' and p.nome = 'Curso Leveduca Bloq') plano_curso,
  (select p.id from public.planos p join public.negocios n on n.id = p.negocio_id where n.slug = 'servnet-curso-bloq' and p.nome = 'Presente Indicação Bloq') plano_presente,
  (select p.id from public.planos p join public.negocios n on n.id = p.negocio_id where n.slug = 'provedor-pago-bloq') plano_pago,
  (select id from public.negocios where slug = 'servnet-curso-bloq') neg_curso,
  (select id from public.negocios where slug = 'provedor-pago-bloq') neg_pago;

do $$ declare v r%rowtype; v_ct_curso uuid; v_ct_pago uuid; v_ct_presente uuid; j jsonb; begin
  select * into v from r;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
  values (v.org, v.neg_curso, v.pessoa, v.plano_curso, 0, 'mensal', current_date - 10, 1, true) returning id into v_ct_curso;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
  values (v.org, v.neg_curso, v.pessoa, v.plano_presente, 0, 'mensal', current_date - 10, 1, true) returning id into v_ct_presente;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, cortesia)
  values (v.org, v.neg_pago, v.pessoa, v.plano_pago, 80, 'mensal', current_date - 10, 10, false) returning id into v_ct_pago;

  create temp table ctids as select v_ct_curso as curso, v_ct_pago as pago, v_ct_presente as presente;

  -- T1: paga em dia (ativo) em outro negócio — curso continua ativo, sync não mexe em nada
  j := public.sincronizar_cortesia_curso(v.org);
  assert (j->>'suspensos')::int = 0 and (j->>'liberados')::int = 0, 'T1 nada a fazer: ' || j::text;
  assert (select status from public.contratos where id = v_ct_curso) = 'ativo', 'T1 curso continua ativo';

  -- T2: contrato pago fica suspenso (ex.: bloqueio manual/automático de outro negócio) — sync suspende o curso também
  update public.contratos set status = 'suspenso' where id = v_ct_pago;
  j := public.sincronizar_cortesia_curso(v.org);
  assert (j->>'suspensos')::int = 1, 'T2 suspendeu 1: ' || j::text;
  assert (select status from public.contratos where id = v_ct_curso) = 'suspenso', 'T2 curso suspenso';
  -- cortesia que não é curso (presente de indicação) não é afetada
  assert (select status from public.contratos where id = v_ct_presente) = 'ativo', 'T2 presente de indicação não mexe';

  -- T3: cliente quita o atraso, contrato pago volta a ativo — sync libera o curso de novo
  update public.contratos set status = 'ativo' where id = v_ct_pago;
  j := public.sincronizar_cortesia_curso(v.org);
  assert (j->>'liberados')::int = 1, 'T3 liberou 1: ' || j::text;
  assert (select status from public.contratos where id = v_ct_curso) = 'ativo', 'T3 curso liberado de volta';

  -- prepara T4: atraso de novo, fora da sessão autenticada o robô é quem sincroniza
  update public.contratos set status = 'suspenso' where id = v_ct_pago;
end $$;
grant select on ctids to service_role;

-- T4: robô diário (sem sessão de usuário, mesma simulação dos testes de bloqueio_automatico) para todas as organizações
set local role service_role;
do $$ declare v_ct_curso uuid; j jsonb; begin
  select curso into v_ct_curso from ctids;
  j := public.sincronizar_cortesia_curso_automatico();
  assert (j->>'suspensos')::int >= 1, 'T4 robô suspendeu: ' || j::text;
  assert (select status from public.contratos where id = v_ct_curso) = 'suspenso', 'T4 curso suspenso pelo robô';
end $$;
set local role authenticated;

rollback;
\echo OK
