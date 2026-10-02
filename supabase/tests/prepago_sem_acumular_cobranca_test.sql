-- Testes da migration 0123 (negócio pré-pago nunca acumula cobrança em aberto). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Prepago Acumula', 'corrente' from ids;
create temp table r as select (select org from ids) org, (select id from public.contas where nome='Banco Prepago Acumula') conta;

-- T1: contrato pré-pago (Servidor), cliente não pagou o mês corrente — rodar o faturamento
-- de novo (ou atrasado, cobrindo vários meses) NÃO pode gerar uma segunda cobrança em aberto.
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; n int; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR SEM ACUMULAR', 'servidor-sem-acumular', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Sem Acumular') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Sem Acumular', 35) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 35, 'mensal', date '2026-07-01', 1) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- julho, previsto, nunca pago

  -- faturamento roda bem depois (atrasado), cobrindo julho/agosto/setembro/outubro de uma vez —
  -- antes da 0123 isso geraria 4 cobranças; agora só pode existir UMA em aberto (a de julho).
  perform public.gerar_faturamento_agora(date '2026-10-31');

  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 1, 'T1 só uma cobrança em aberto (encontrado ' || n || ')';
  assert (select data_competencia from public.lancamentos where contrato_id = v_ct and status = 'previsto') = date '2026-07-01',
    'T1 a que ficou em aberto é a mais antiga (julho), não uma nova em cima';

  -- cliente paga a de julho — só então o faturamento pode gerar a próxima (uma de cada vez)
  perform public.efetivar_lancamento(l0.id, date '2026-07-01');
  perform public.gerar_faturamento_agora(date '2026-10-31');
  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 1, 'T1 depois de pagar, gera só a próxima (1 em aberto), não todo o atraso de uma vez: ' || n;
end $$;

-- T2: já existiam DUAS em aberto (dado antigo / bug anterior) — rodar o faturamento de novo
-- limpa sozinho, cancelando a mais nova e mantendo só a mais antiga (a dívida real).
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; l0 public.lancamentos%rowtype; l1 public.lancamentos%rowtype; n int; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug, ciclo_prepago) values (v.org, 'SERVIDOR LIMPA DUPLA', 'servidor-limpa-dupla', true) returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Limpa Dupla') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Limpa Dupla', 30) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 30, 'mensal', date '2026-08-20', 20) returning id into v_ct;
  select * into l0 from public.lancamentos where contrato_id = v_ct; -- agosto

  -- simula o bug antigo: a segunda cobrança (setembro) já existe em aberto
  l1 := public.criar_lancamento('receita', 'Mensal/30 · 09/2026 · contrato duplicado', 30,
    date '2026-09-20', date '2026-09-20', null, v.conta, null, l0.categoria_id, null, v_neg, v_cli, v_ct);

  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 2, 'T2 pré-condição: duas em aberto (dado antigo simulado)';

  perform public.gerar_faturamento_agora(date '2026-10-31');

  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 1, 'T2 faturamento limpou sozinho, sobrou só uma: ' || n;
  assert (select data_competencia from public.lancamentos where contrato_id = v_ct and status = 'previsto') = date '2026-08-20',
    'T2 sobrou a mais antiga (agosto), que é a dívida real';
  assert (select status from public.lancamentos where id = l1.id) = 'cancelado', 'T2 a duplicada (setembro) foi cancelada';
  assert (select motivo_cancelamento from public.lancamentos where id = l1.id) ilike '%pré-pago%', 'T2 motivo explica o porquê';
end $$;

-- T3: negócio comum (não pré-pago) continua podendo faturar vários meses à frente, sem limite
do $$ declare v r%rowtype; v_neg uuid; v_cli uuid; v_plano uuid; v_ct uuid; n int; begin
  select * into v from r;
  insert into public.negocios (organizacao_id, nome, slug) values (v.org, 'PROVEDOR SEM LIMITE', 'provedor-sem-limite') returning id into v_neg;
  update public.negocios set conta_padrao_id = v.conta,
    categoria_receita_id = (select id from public.categorias where organizacao_id = v.org and tipo = 'receita' limit 1) where id = v_neg;
  insert into public.pessoas (organizacao_id, nome) values (v.org, 'Cliente Sem Limite') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) values (v.org, v_neg, 'Plano Sem Limite', 80) returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
    values (v.org, v_neg, v_cli, v_plano, 80, 'mensal', date '2026-07-10', 10) returning id into v_ct;
  perform public.gerar_faturamento_agora(date '2026-10-31');
  select count(*) into n from public.lancamentos where contrato_id = v_ct and status = 'previsto';
  assert n = 4, 'T3 negócio comum fatura julho/agosto/setembro/outubro de uma vez, sem limite: ' || n;
end $$;

rollback;
\echo OK
