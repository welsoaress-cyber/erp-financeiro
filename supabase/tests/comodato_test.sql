-- Testes da migration 0058 (comodato). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_onu uuid; v_p uuid; v_pt uuid; v_plano uuid; v_conta uuid; v_tec uuid; v_ct uuid; os public.ordens_servico; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'COMODATO T', 'comodato-t', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip Com') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome) values (v_org, v_neg, v_cat, 'ONU-C', 'ONU Comodato') returning id into v_onu;
  perform public.entrada_estoque(v_onu, 10, 1500, current_date, 'compra'); -- 150 cada
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Cliente Comodato') returning id into v_p;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Téc Comodato') returning id into v_pt;
  insert into public.tecnicos (organizacao_id, negocio_id, pessoa_id, nome) values (v_org, v_neg, v_pt, 'Téc Comodato') returning id into v_tec;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Com', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Com', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date - 30, 10, v_conta) returning id into v_ct;
  perform public.abastecer_tecnico(v_tec, v_onu, 3);
  os := public.abrir_os(v_neg, 'instalacao', 'Instalar com ONU', v_p, v_ct, v_tec);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='comodato-t') neg,
  (select id from public.estoque_itens where codigo='ONU-C') onu,
  (select id from public.pessoas where nome='Cliente Comodato') pessoa,
  (select id from public.tecnicos where nome='Téc Comodato') tec,
  (select c.id from public.contratos c join public.pessoas p on p.id=c.pessoa_id where p.nome='Cliente Comodato') ct,
  (select id from public.ordens_servico where descricao='Instalar com ONU') os1;

-- T1: encerramento com equipamento — comodato instalado, série única, bolsa -1, custo no chamado
do $$ declare v r%rowtype; os public.ordens_servico; c public.comodatos%rowtype; begin
  select * into v from r;
  perform public.agendar_os(v.os1, current_date, '08:00');
  perform public.iniciar_os(v.os1);
  os := public.encerrar_os(v.os1, '[]'::jsonb, 'outro', -18, null, jsonb_build_array(jsonb_build_object('item_id', v.onu, 'numero_serie', 'zte123abc')));
  select * into c from public.comodatos where pessoa_id = v.pessoa;
  assert c.status = 'instalado' and c.numero_serie = 'ZTE123ABC' and c.contrato_id = v.ct and c.os_instalacao_id = v.os1, 'T1 comodato instalado';
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.onu) = 2, 'T1 bolsa -1';
  assert (select sum(valor_total) from public.os_materiais where os_id = v.os1) = 150, 'T1 custo do equipamento no chamado';
  assert (select custo_instalacao from public.vw_payback_contrato where contrato_id = v.ct) = 150, 'T1 payback com a ONU';
  -- série repetida instalada falha
  begin
    perform public.registrar_comodato(v.neg, v.onu, ' zte123abc ', v.pessoa, v.ct);
    raise exception 'T1 série duplicada deveria falhar';
  exception when check_violation then null; end;
  -- escrita direta bloqueada
  perform set_config('erp.motor', '', true);
  begin
    update public.comodatos set status = 'perdido' where id = c.id;
    raise exception 'T1 update direto deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T2: troca com defeito de fábrica — antigo trocado (não volta ao estoque), novo da bolsa; série antiga liberada
do $$ declare v r%rowtype; v_old uuid; novo public.comodatos%rowtype; n int; begin
  select * into v from r;
  select id into v_old from public.comodatos where pessoa_id = v.pessoa and status = 'instalado';
  begin
    perform public.trocar_comodato(v_old, 'ZTE999XYZ', v.tec, true, '');
    raise exception 'T2 troca sem motivo deveria falhar';
  exception when check_violation then null; end;
  novo := public.trocar_comodato(v_old, 'ZTE999XYZ', v.tec, true, 'ONU queimada');
  assert novo.numero_serie = 'ZTE999XYZ' and novo.status = 'instalado' and novo.contrato_id = v.ct, 'T2 novo instalado';
  assert (select status::text from public.comodatos where id = v_old) = 'trocado', 'T2 antigo trocado';
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec and item_id = v.onu) = 1, 'T2 novo saiu da bolsa';
  assert (select quantidade_atual from public.estoque_itens where id = v.onu) = 7, 'T2 defeito de fábrica não volta ao central';
  -- registro manual reutiliza a série antiga liberada (sem mexer no estoque)
  perform public.registrar_comodato(v.neg, v.onu, 'ZTE123ABC', v.pessoa, null, 'legado');
  assert (select quantidade_atual from public.estoque_itens where id = v.onu) = 7, 'T2 registro manual não mexe no estoque';
  select count(*) into n from public.comodato_historico where evento = 'troca';
  assert n = 2, 'T2 histórico da troca (saída e entrada)';
end $$;

-- T3: contrato encerrado gera OS de recolhimento (uma só); encerrá-la recolhe e devolve ao central
do $$ declare v r%rowtype; v_os uuid; os public.ordens_servico; n int; begin
  select * into v from r;
  update public.contratos set status = 'encerrado', data_fim = current_date where id = v.ct;
  select id into v_os from public.ordens_servico where contrato_id = v.ct and tipo::text = 'recolhimento' and status = 'aberto';
  assert v_os is not null, 'T3 OS de recolhimento aberta';
  assert (select descricao from public.ordens_servico where id = v_os) like '%ZTE999XYZ%', 'T3 série na descrição';
  select count(*) into n from public.ordens_servico where contrato_id = v.ct and tipo::text = 'recolhimento';
  assert n = 1, 'T3 uma OS só';
  perform public.agendar_os(v_os, current_date, '10:00');
  perform public.iniciar_os(v_os);
  os := public.encerrar_os(v_os, '[]'::jsonb, null, null, 'recolhido ok');
  assert (select status::text from public.comodatos where numero_serie = 'ZTE999XYZ') = 'recolhido', 'T3 comodato recolhido';
  assert (select quantidade_atual from public.estoque_itens where id = v.onu) = 8, 'T3 voltou ao central';
end $$;

-- T4: perda exige justificativa; recolhimento manual com descarte não volta ao estoque
do $$ declare v r%rowtype; v_id uuid; n int; begin
  select * into v from r;
  select id into v_id from public.comodatos where numero_serie = 'ZTE123ABC' and status = 'instalado';
  begin
    perform public.perda_comodato(v_id, '');
    raise exception 'T4 perda sem justificativa deveria falhar';
  exception when check_violation then null; end;
  perform public.perda_comodato(v_id, 'cliente mudou e sumiu com a ONU');
  assert (select status::text from public.comodatos where id = v_id) = 'perdido', 'T4 perdido';
  -- novo registro + recolhimento com descarte
  perform public.registrar_comodato(v.neg, v.onu, 'HW555AAA', v.pessoa);
  select id into v_id from public.comodatos where numero_serie = 'HW555AAA';
  select quantidade_atual::int into n from public.estoque_itens where id = v.onu;
  perform public.recolher_comodato(v_id, true, 'queimada por raio');
  assert (select quantidade_atual from public.estoque_itens where id = v.onu) = n, 'T4 descarte não volta ao estoque';
  assert (select count(*) from public.comodato_historico where comodato_id = v_id and evento = 'descarte') = 1, 'T4 histórico do descarte';
end $$;

rollback;
\echo OK
