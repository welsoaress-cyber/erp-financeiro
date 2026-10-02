-- Testes da migration 0122 (reancoragem vale mesmo com o contrato suspenso). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Reanc Suspenso', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Reanc Suspenso') conta;

-- T1: contrato pré-pago SUSPENSO (pagou atrasado, ainda não foi reativado) — a reancoragem
-- (dia_vencimento) tem que valer mesmo assim, não só quando status = 'ativo'.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR REANC SUSPENSO', 'servidor-reanc-suspenso', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Reanc Suspenso') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Reanc Suspenso', 30) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 30, 'mensal', date '2026-08-29', 29) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto, 29/08, previsto (vencida)
  update public.contratos set status = 'suspenso' where id = v_ct; -- suspenso por inadimplência, antes de pagar

  perform public.efetivar_lancamento(l0.id, date '2026-10-01'); -- paga bem atrasado, contrato CONTINUA suspenso

  assert (select status from public.contratos where id = v_ct) = 'suspenso', 'T1 pré-condição: contrato continua suspenso (baixa não reativa sozinha)';
  assert (select dia_vencimento from public.contratos where id = v_ct) = 1, 'T1 reancorou mesmo suspenso: pagamento (01/10) + 1 mês = dia 1';
end $$;

-- T2: contrato comum (não pré-pago) SUSPENSO — mesma correção, caminho antigo (dia do mês)
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'PROVEDOR REANC SUSPENSO', 'provedor-reanc-suspenso') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Provedor Suspenso') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Provedor Suspenso', 80) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 80, 'mensal', date '2026-08-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  update public.contratos set status = 'suspenso' where id = v_ct;
  perform public.efetivar_lancamento(l0.id, date '2026-09-25');
  assert (select status from public.contratos where id = v_ct) = 'suspenso', 'T2 pré-condição: continua suspenso';
  assert (select dia_vencimento from public.contratos where id = v_ct) = 25, 'T2 reancorou mesmo suspenso (caminho dia do mês)';
end $$;

-- T3: contrato ENCERRADO nunca é tocado (não faz sentido reancorar quem não cobra mais)
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'PROVEDOR REANC ENCERRADO', 'provedor-reanc-encerrado') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Provedor Encerrado') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Provedor Encerrado', 80) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 80, 'mensal', date '2026-06-10', 10) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct;
  update public.contratos set status = 'encerrado', data_fim = date '2026-09-01' where id = v_ct;
  perform public.efetivar_lancamento(l0.id, date '2026-09-25');
  assert (select dia_vencimento from public.contratos where id = v_ct) = 10, 'T3 contrato encerrado não é reancorado';
end $$;

rollback;
\echo OK
