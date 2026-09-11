-- Testes da migration 0055 (ordens de serviço). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_p uuid; v_pt uuid; v_plano uuid; v_conta uuid; v_tec uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'OS TESTE', 'os-teste', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos OS') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'OS-CABO', 'Cabo drop OS', 'metro') returning id into v_item;
  perform public.entrada_estoque(v_item, 1000, 1000, current_date, 'compra'); -- custo 1,00/m
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente OS') returning id into v_p;
  insert into public.pessoas (organizacao_id, nome, observacao) values (v_org, 'Técnico João', 'Técnico') returning id into v_pt;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Fibra OS', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa OS', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.tecnicos (organizacao_id, negocio_id, pessoa_id, nome, telefone) values (v_org, v_neg, v_pt, 'Técnico João', '92999990000') returning id into v_tec;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date - 30, 10, v_conta);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='os-teste') neg,
  (select id from public.estoque_itens where codigo='OS-CABO') item,
  (select id from public.pessoas where nome='Cliente OS') pessoa,
  (select id from public.tecnicos where nome='Técnico João') tec,
  (select id from public.contas where nome='Caixa OS') conta,
  (select id from public.contratos c where c.pessoa_id = (select id from public.pessoas where nome='Cliente OS')) ct,
  (select codigo from public.contratos c where c.pessoa_id = (select id from public.pessoas where nome='Cliente OS')) ct_codigo;

-- T1: número OS/MAN, atribuição automática ao único técnico, insert direto bloqueado
do $$ declare v r%rowtype; os public.ordens_servico; os2 public.ordens_servico; begin
  select * into v from r;
  os := public.abrir_os(v.neg, 'instalacao', 'Instalar fibra no cliente', v.pessoa, v.ct);
  assert os.numero = 'OS' || lpad(v.ct_codigo::text, 3, '0') || to_char(current_date, 'DDMMYYYY') || 'A', 'T1 número OS: ' || os.numero;
  assert os.tecnico_id = v.tec, 'T1 atribuição automática';
  assert os.status = 'aberto' and os.retorno = false, 'T1 estado inicial';
  os2 := public.abrir_os(v.neg, 'rompimento', 'Rompimento na rota principal');
  assert os2.numero = 'MAN' || to_char(current_date, 'DDMMYYYY') || 'A', 'T1 número MAN: ' || os2.numero;
  os2 := public.abrir_os(v.neg, 'vistoria', 'Vistoria de rede');
  assert os2.numero = 'MAN' || to_char(current_date, 'DDMMYYYY') || 'B', 'T1 sequência MAN: ' || os2.numero;
  perform set_config('erp.motor', '', true);
  begin
    insert into public.ordens_servico (organizacao_id, negocio_id, numero, tipo, descricao) values (v.org, v.neg, 'X1', 'reparo', 'direto');
    raise exception 'T1 insert direto deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    perform public.abrir_os(v.neg, 'reparo', 'contrato sem cliente', null, v.ct);
    raise exception 'T1 contrato sem cliente deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T2: bolsa — abastecer transfere do central, devolver volta, perda exige motivo, proteções
do $$ declare v r%rowtype; q numeric; begin
  select * into v from r;
  perform public.abastecer_tecnico(v.tec, v.item, 100);
  assert (select quantidade_atual from public.estoque_itens where id = v.item) = 900, 'T2 central após abastecer';
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.item) = 100, 'T2 bolsa abastecida';
  assert (select count(*) from public.estoque_movimentacoes where item_id = v.item and origem = 'transferencia' and tipo = 'saida') = 1, 'T2 movimentação central de transferência';
  perform public.devolver_tecnico(v.tec, v.item, 10);
  assert (select quantidade_atual from public.estoque_itens where id = v.item) = 910, 'T2 central após devolução';
  begin
    perform public.perda_tecnico(v.tec, v.item, 5, false, '');
    raise exception 'T2 perda sem motivo deveria falhar';
  exception when check_violation then null; end;
  perform public.perda_tecnico(v.tec, v.item, 5, false, 'caiu do poste');
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.item) = 85, 'T2 bolsa após perda';
  begin
    perform public.abastecer_tecnico(v.tec, v.item, 99999);
    raise exception 'T2 abastecer acima do central deveria falhar';
  exception when check_violation then null; end;
  perform set_config('erp.motor', '', true);
  begin
    update public.tecnico_estoque set quantidade = 999 where tecnico_id = v.tec and item_id = v.item;
    raise exception 'T2 quantidade direta na bolsa deveria falhar';
  exception when check_violation then null; end;
  update public.tecnico_estoque set quantidade_minima = 50 where tecnico_id = v.tec and item_id = v.item; -- mínimo é configurável
  begin
    update public.tecnico_movimentacoes set quantidade = 1 where tecnico_id = v.tec;
    raise exception 'T2 movimentação editada deveria falhar';
  exception when check_violation or insufficient_privilege then null; end;
end $$;

-- T3: fluxo completo — ciência, agenda ontem 08:00, inicia, pausa/retoma, encerra com material;
--     tempo conta do agendamento; instalação alimenta o payback sem tocar o central
do $$ declare v r%rowtype; v_os uuid; os public.ordens_servico; pb record; v_esp int; begin
  select * into v from r;
  select id into v_os from public.ordens_servico where tipo = 'instalacao' and pessoa_id = v.pessoa;
  begin
    perform public.iniciar_os(v_os);
    raise exception 'T3 iniciar sem agendar deveria falhar';
  exception when check_violation then null; end;
  perform public.ciencia_os(v_os);
  perform public.agendar_os(v_os, current_date - 1, '08:00');
  begin
    perform public.agendar_os(v_os, current_date, '09:00');
    raise exception 'T3 reagendar direto deveria falhar (pede remarcação)';
  exception when check_violation then null; end;
  perform public.solicitar_remarcacao_os(v_os, current_date - 1, '09:00', 'faltou material');
  perform public.responder_remarcacao_os(v_os, true);
  assert (select hora_agendada from public.ordens_servico where id = v_os) = '09:00'::time, 'T3 remarcação aprovada';
  perform public.iniciar_os(v_os);
  perform public.pausar_os(v_os, 'cliente ausente');
  perform public.retomar_os(v_os);
  os := public.encerrar_os(v_os, jsonb_build_array(jsonb_build_object('item_id', v.item, 'quantidade', 80)), 'outro', -18.5, 'instalado');
  assert os.status = 'encerrado' and os.sinal_dbm = -18.5, 'T3 encerrado';
  v_esp := floor(extract(epoch from (now() - ((current_date - 1) + time '09:00')::timestamptz)) / 60)::int;
  assert os.tempo_total_minutos between v_esp - 2 and v_esp + 2, 'T3 tempo desde o agendado: ' || os.tempo_total_minutos || ' (esperado ~' || v_esp || ')';
  assert os.tempo_execucao_minutos <= 1, 'T3 tempo de execução: ' || os.tempo_execucao_minutos;
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.item) = 5, 'T3 bolsa consumida';
  assert (select quantidade_atual from public.estoque_itens where id = v.item) = 910, 'T3 central intacto no consumo';
  assert (select valor_total from public.os_materiais where os_id = v_os) = 80, 'T3 material do chamado';
  select * into pb from public.vw_payback_contrato where contrato_id = v.ct;
  assert pb.custo_instalacao = 80 and pb.payback_estimado_meses = 1, 'T3 payback: ' || pb.custo_instalacao;
  assert (select os_id from public.estoque_instalacoes where contrato_id = v.ct) = v_os, 'T3 instalação ligada à OS';
end $$;

-- T4: retorno (reincidência ≤ 7 dias), reparo com custo do cliente fora do payback, bolsa negativa com alerta
do $$ declare v r%rowtype; os public.ordens_servico; c record; begin
  select * into v from r;
  os := public.abrir_os(v.neg, 'reparo', 'Sem sinal de novo', v.pessoa, v.ct);
  assert os.retorno, 'T4 marcado como retorno';
  perform public.agendar_os(os.id, current_date, '10:00');
  perform public.iniciar_os(os.id);
  os := public.encerrar_os(os.id, jsonb_build_array(jsonb_build_object('item_id', v.item, 'quantidade', 30)), 'conector', -21);
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.item) = -25, 'T4 bolsa negativa permitida';
  select * into c from public.vw_bolsa_tecnicos where tecnico_id = v.tec;
  assert c.itens_negativos = 1, 'T4 alerta de bolsa negativa';
  select * into c from public.vw_os_custo_contrato where contrato_id = v.ct;
  assert c.custo_material = 30 and c.chamados = 1, 'T4 custo de manutenção do cliente: ' || c.custo_material;
  select * into c from public.vw_payback_contrato where contrato_id = v.ct;
  assert c.custo_instalacao = 80, 'T4 reparo não entra no payback';
end $$;

-- T5: comissão — padrão 50% da mensalidade, categoria Comissões, fornecedor = pessoa do técnico
do $$ declare v r%rowtype; v_os uuid; l public.lancamentos; begin
  select * into v from r;
  select id into v_os from public.ordens_servico where tipo = 'instalacao' and pessoa_id = v.pessoa;
  l := public.aprovar_comissao_os(v_os, v.conta, current_date + 5);
  assert l.valor = 50 and l.status = 'previsto' and l.tipo = 'despesa', 'T5 comissão 50%: ' || l.valor;
  assert l.contrato_id is null and l.pessoa_id = (select pessoa_id from public.tecnicos where id = v.tec), 'T5 fornecedor técnico, sem contrato no lançamento';
  assert (select custo_instalacao from public.vw_payback_contrato where contrato_id = v.ct) = 130, 'T5 payback soma a comissão (80 + 50)';
  assert (select nome from public.categorias where id = l.categoria_id) = 'Comissões', 'T5 categoria';
  begin
    perform public.aprovar_comissao_os(v_os, v.conta, current_date + 5);
    raise exception 'T5 comissão duplicada deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.aprovar_comissao_os((select id from public.ordens_servico where tipo = 'reparo' and pessoa_id = v.pessoa), v.conta, current_date + 5);
    raise exception 'T5 comissão de reparo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T6: avaliação e reabertura (chamado novo com número original-A)
do $$ declare v r%rowtype; v_os uuid; os public.ordens_servico; begin
  select * into v from r;
  select id into v_os from public.ordens_servico where tipo = 'reparo' and pessoa_id = v.pessoa;
  perform public.avaliar_os(v_os, false);
  os := public.abrir_os(v.neg, 'reparo', 'Problema persiste', v.pessoa, v.ct, null, null, 'urgente', 'admin', v_os);
  assert os.numero = (select numero from public.ordens_servico where id = v_os) || '-A', 'T6 número da reabertura: ' || os.numero;
  assert os.tecnico_id = v.tec and os.prioridade = 'urgente', 'T6 reabertura atribuída';
  perform public.avaliar_os((select id from public.ordens_servico where tipo = 'instalacao' and pessoa_id = v.pessoa), true, 5);
  assert (select avaliacao_nota from public.ordens_servico where tipo = 'instalacao' and pessoa_id = v.pessoa) = 5, 'T6 nota gravada';
end $$;

rollback;
\echo OK
