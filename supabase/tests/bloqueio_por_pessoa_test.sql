-- Testes da migration 0121 (bloqueio por pessoa, não só pelo contrato isolado). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_cli uuid; v_plano uuid; v_conta uuid;
  v_ct_susp1 uuid; v_ct_susp2 uuid; v_ct_limpo uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'BLQ PESSOA', 'blq-pessoa', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, dias_apos, bloqueio_apos_dias, bloqueio_automatico) values (v_org, v_neg, '+5592999990010', true, 5, 5, true);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Tres Contratos', '92988887001') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Blq Pessoa', 35, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Blq Pessoa', 'dinheiro', v_neg) returning id into v_conta;

  -- dois contratos velhos, já suspensos por inadimplência (dívida parada neles)
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg, v_cli, v_plano, 35, 'mensal', current_date - 200, 7, v_conta, 'suspenso') returning id into v_ct_susp1;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg, v_cli, v_plano, 35, 'mensal', current_date - 100, 10, v_conta, 'suspenso') returning id into v_ct_susp2;
  -- contrato novo, renumerado, sem nada vencido NELE mesmo
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, status)
  values (v_org, v_neg, v_cli, v_plano, 35, 'mensal', current_date - 20, 8, v_conta, 'ativo') returning id into v_ct_limpo;

  create temp table ctids as select v_ct_susp1 as susp1, v_ct_susp2 as susp2, v_ct_limpo as limpo, v_neg as neg;
end $$;

-- T1: contrato "limpo" (sem dívida própria) é sugerido pro bloqueio porque a mesma
-- pessoa tem outro contrato suspenso — não fica mais "Ativo" escondendo a inadimplência.
do $$ declare v_limpo uuid; v_neg uuid; res jsonb; begin
  select limpo, neg into v_limpo, v_neg from ctids;
  res := public.gerar_bloqueios(v_neg);
  assert (res->>'bloqueios')::int >= 1, 'T1 sugeriu bloqueio: ' || res;
  assert exists (
    select 1 from public.bloqueios where contrato_id = v_limpo and tipo = 'bloqueio' and status = 'pendente'
      and motivo ilike '%outro contrato suspenso%'
  ), 'T1 bloqueio cruzado sugerido pro contrato limpo';
end $$;

-- T2: botão "atualizar agora" (negócio com bloqueio_automatico ligado) executa a
-- sugestão e suspende o contrato limpo também, na hora
do $$ declare v_limpo uuid; v_neg uuid; begin
  select limpo, neg into v_limpo, v_neg from ctids;
  perform public.executar_bloqueios_agora(v_neg);
  assert (select status from public.contratos where id = v_limpo) = 'suspenso', 'T2 contrato limpo suspenso por causa do irmão';
end $$;

-- T3: um dos contratos velhos quita a dívida e some (previsto que vencia não existe mais / foi pago);
-- ainda assim NÃO desbloqueia sozinho, porque o outro irmão (susp2) continua suspenso.
do $$ declare v_susp1 uuid; v_neg uuid; res jsonb; begin
  select susp1, neg into v_susp1, v_neg from ctids;
  update public.contratos set status = 'ativo' where id = v_susp1; -- reativado manualmente pelo proprietário
  res := public.gerar_bloqueios(v_neg);
  assert not exists (select 1 from public.bloqueios where contrato_id = v_susp1 and tipo = 'desbloqueio' and status = 'pendente'),
    'T3 susp1 não sugere desbloqueio sozinho: irmão susp2 ainda suspenso';
end $$;

-- T4: reativando TODOS os irmãos, o contrato limpo (que foi suspenso só por causa deles)
-- passa a ser sugerido pro desbloqueio, e a pendência de bloqueio cruzado é descartada.
do $$ declare v_susp2 uuid; v_limpo uuid; v_neg uuid; res jsonb; begin
  select susp2, limpo, neg into v_susp2, v_limpo, v_neg from ctids;
  update public.contratos set status = 'ativo' where id = v_susp2;
  res := public.gerar_bloqueios(v_neg);
  assert exists (select 1 from public.bloqueios where contrato_id = v_limpo and tipo = 'desbloqueio' and status = 'pendente'),
    'T4 contrato limpo sugerido pro desbloqueio: nenhum irmão suspenso mais';
end $$;

rollback;
\echo OK
