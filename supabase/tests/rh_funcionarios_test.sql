-- Testes da migration 0113 (RH simplificado — etapa 62). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_pessoa uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'RH TESTE', 'rh-teste') returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Banco RH', 'corrente') returning id into v_conta;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Carla Funcionária') returning id into v_pessoa;
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='rh-teste') neg,
  (select id from public.contas where nome='Banco RH') conta,
  (select id from public.pessoas where nome='Carla Funcionária') pessoa;

-- T1: funcionário a partir de pessoa existente; duplicar mesma pessoa na organização falha
do $$ declare v r%rowtype; fid uuid; begin
  select * into v from r;
  insert into public.funcionarios (organizacao_id, negocio_id, pessoa_id, cargo, departamento, salario_base)
  values (v.org, v.neg, v.pessoa, 'Atendente', 'Administrativo', 2000) returning id into fid;
  assert (select nome from public.pessoas p join public.funcionarios f on f.pessoa_id = p.id where f.id = fid) = 'Carla Funcionária', 'T1 vínculo com pessoa existente';
  begin
    insert into public.funcionarios (organizacao_id, negocio_id, pessoa_id, salario_base) values (v.org, v.neg, v.pessoa, 1000);
    raise exception 'T1 funcionário duplicado (mesma pessoa) deveria falhar';
  exception when unique_violation then null; end;
end $$;

-- T2: ponto informal — um registro por dia; update corrige o próprio registro
do $$ declare v r%rowtype; fid uuid; pid uuid; begin
  select * into v from r;
  select id into fid from public.funcionarios where pessoa_id = v.pessoa;
  insert into public.funcionario_ponto (funcionario_id, data, entrada, saida_almoco, volta_almoco, saida)
  values (fid, current_date, '08:00', '12:00', '13:00', '17:00') returning id into pid;
  update public.funcionario_ponto set observacao = 'saiu mais cedo' where id = pid;
  assert (select observacao from public.funcionario_ponto where id = pid) = 'saiu mais cedo', 'T2 ponto corrigido';
  begin
    insert into public.funcionario_ponto (funcionario_id, data, entrada) values (fid, current_date, '09:00');
    raise exception 'T2 ponto duplicado no mesmo dia deveria falhar';
  exception when unique_violation then null; end;
end $$;

-- T3: férias — tracker de datas, sem cálculo de valores
do $$ declare v r%rowtype; fid uuid; begin
  select * into v from r;
  select id into fid from public.funcionarios where pessoa_id = v.pessoa;
  insert into public.funcionario_ferias (funcionario_id, periodo_aquisitivo_inicio, periodo_aquisitivo_fim, data_inicio, data_fim)
  values (fid, current_date - interval '1 year', current_date, current_date + 30, current_date + 60);
  assert (select status from public.funcionario_ferias where funcionario_id = fid) = 'programada', 'T3 férias nascem programada';
  begin
    insert into public.funcionario_ferias (funcionario_id, periodo_aquisitivo_inicio, periodo_aquisitivo_fim) values (fid, current_date, current_date - 1);
    raise exception 'T3 período aquisitivo invertido deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: folha — lançamento de despesa por mês; segunda tentativa no mesmo mês falha; imutável
do $$ declare v r%rowtype; fid uuid; ff public.funcionario_folha; l public.lancamentos%rowtype; begin
  select * into v from r;
  select id into fid from public.funcionarios where pessoa_id = v.pessoa;
  ff := public.lancar_folha_funcionario(fid, date_trunc('month', current_date)::date, 2500, v.conta, current_date + 5, null, 'salário + comissões de setembro');
  select * into l from public.lancamentos where id = ff.lancamento_id;
  assert l.tipo = 'despesa' and l.valor = 2500 and l.pessoa_id = v.pessoa and l.negocio_id = v.neg, 'T4 lançamento de folha correto';
  assert (select nome from public.categorias where id = l.categoria_id) = 'Folha de pagamento', 'T4 categoria Folha de pagamento criada';
  begin
    perform public.lancar_folha_funcionario(fid, date_trunc('month', current_date)::date, 2500, v.conta, current_date + 5);
    raise exception 'T4 folha duplicada no mesmo mês deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.funcionario_folha set valor = 1 where id = ff.id;
    raise exception 'T4 editar folha deveria falhar (sem grant de update)';
  exception when insufficient_privilege then null; end;
end $$;

-- T5: histórico de cargo/salário vem da auditoria genérica (sem tabela própria)
do $$ declare v r%rowtype; fid uuid; n int; begin
  select * into v from r;
  select id into fid from public.funcionarios where pessoa_id = v.pessoa;
  update public.funcionarios set salario_base = 2800, cargo = 'Supervisora' where id = fid;
  select count(*) into n from public.auditoria where tabela = 'funcionarios' and registro_id = fid::text and acao = 'UPDATE';
  assert n >= 1, 'T5 mudança de cargo/salário auditada';
end $$;

rollback;
\echo OK
