-- Testes da migration 0008 (planos e contratos). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.negocios (organizacao_id, nome, slug) select org, 'Servidor', 'servidor' from ids;
insert into public.pessoas (organizacao_id, nome, documento) select org, 'João', '52998224725' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Maria' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90 from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) select org, (select id from public.negocios where slug='servnet'), 'Anual', 1200, 'anual' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servidor'), 'Hospedagem', 49 from ids;
create temp table r as select
  (select org from ids) as org,
  (select id from public.negocios where slug='servnet') as servnet,
  (select id from public.negocios where slug='servidor') as servidor,
  (select id from public.pessoas where nome='João') as joao,
  (select id from public.pessoas where nome='Maria') as maria,
  (select id from public.planos where nome='Fibra 500') as fibra,
  (select id from public.planos where nome='Anual') as anual,
  (select id from public.planos where nome='Hospedagem') as hosp,
  (select id from public.contas where nome='Banco') as banco,
  (select id from public.categorias where nome='Salário') as cat_rec,
  (select id from public.categorias where nome='Alimentação') as cat_desp;

-- T1: planos — nome único por negócio; negócio inativo rejeitado; negócio imutável
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    insert into public.planos (organizacao_id, negocio_id, nome) values (v.org, v.servnet, ' fibra 500 ');
    raise exception 'T1 plano duplicado deveria falhar';
  exception when unique_violation then null; end;
  begin
    update public.planos set negocio_id = v.servidor where id = v.fibra;
    raise exception 'T1 mudar negócio deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T2: contratos — código sequencial por negócio; valor/periodicidade do plano; vínculo cliente criado automaticamente
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, dia_vencimento) select org, servnet, joao, fibra, 89.90, 'mensal', 10 from r;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, dia_vencimento) select org, servnet, maria, anual, 1200, 'anual', 5 from r;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade) select org, servidor, joao, hosp, 49, 'mensal' from r;
do $$ declare n int; v r%rowtype; begin
  select * into v from r;
  assert (select array_agg(codigo order by codigo) from public.contratos where negocio_id = v.servnet) = array[1,2], 'T2 códigos servnet';
  assert (select codigo from public.contratos where negocio_id = v.servidor) = 1, 'T2 código servidor independente';
  select count(*) into n from public.pessoa_negocio_vinculos where pessoa_id = v.joao and papel = 'cliente' and ativo; assert n = 2, 'T2 vínculos cliente automáticos';
  begin
    insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade) values (v.org, v.servnet, v.joao, v.hosp, 49, 'mensal');
    raise exception 'T2 plano de outro negócio deveria falhar';
  exception when check_violation then null; end;
  update public.planos set ativo = false where id = v.anual;
  begin
    insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade) values (v.org, v.servnet, v.joao, v.anual, 1200, 'anual');
    raise exception 'T2 plano inativo deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, status, data_fim) values (v.org, v.servnet, v.joao, v.fibra, 1, 'mensal', 'encerrado', current_date);
    raise exception 'T2 criar encerrado deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: MRR por negócio (mensal + anual/12; suspenso não conta)
do $$ declare m numeric; begin
  select mrr into m from public.vw_receita_recorrente where negocio = 'SERVNET'; assert m = 89.90 + 100, 'T3 mrr servnet';
  update public.contratos set status = 'suspenso' where valor = 1200;
  select mrr into m from public.vw_receita_recorrente where negocio = 'SERVNET'; assert m = 89.90, 'T3 mrr sem suspenso';
  assert (select contratos_suspensos from public.vw_receita_recorrente where negocio = 'SERVNET') = 1, 'T3 suspensos';
end $$;

-- T4: lançamento com contrato herda negócio e pessoa; divergência rejeitada; transferência rejeitada
do $$ declare v r%rowtype; v_c uuid; l public.lancamentos%rowtype; begin
  select * into v from r;
  select id into v_c from public.contratos where negocio_id = v.servnet and codigo = 1;
  select * into l from public.criar_lancamento('receita', 'Mensalidade set', 89.90, '2026-09-10', null, '2026-09-10', v.banco, null, v.cat_rec, null, null, null, v_c);
  assert l.negocio_id = v.servnet and l.pessoa_id = v.joao, 'T4 herdou negócio e pessoa';
  perform public.criar_lancamento('despesa', 'Instalação', 30, '2026-09-11', null, '2026-09-11', v.banco, null, v.cat_desp, null, v.servnet, v.joao, v_c);
  begin
    perform public.criar_lancamento('receita', 'x', 1, '2026-09-10', null, '2026-09-10', v.banco, null, v.cat_rec, null, v.servidor, null, v_c);
    raise exception 'T4 negócio divergente deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('receita', 'x', 1, '2026-09-10', null, '2026-09-10', v.banco, null, v.cat_rec, null, null, v.maria, v_c);
    raise exception 'T4 pessoa divergente deveria falhar';
  exception when check_violation then null; end;
  insert into public.contas (organizacao_id, nome, tipo) values (v.org, 'Carteira', 'dinheiro');
  begin
    perform public.criar_lancamento('transferencia', 'x', 1, '2026-09-10', null, '2026-09-10', v.banco, (select id from public.contas where nome='Carteira'), null, null, null, null, v_c);
    raise exception 'T4 transferência com contrato deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: rentabilidade por contrato
do $$ declare rr record; begin
  select * into rr from public.vw_resultado_por_contrato where codigo = 1 and negocio_id = (select servnet from r);
  assert rr.receitas = 89.90 and rr.despesas = 30 and rr.resultado = 59.90 and rr.lancamentos = 2, 'T5 rentabilidade';
end $$;

-- T6: ciclo de vida — suspender/reativar; encerrar exige data_fim; encerrado imutável; campos imutáveis
do $$ declare v r%rowtype; v_c uuid; begin
  select * into v from r;
  select id into v_c from public.contratos where negocio_id = v.servnet and codigo = 1;
  update public.contratos set status = 'suspenso' where id = v_c;
  update public.contratos set status = 'ativo' where id = v_c;
  update public.contratos set valor = 79.90, dia_vencimento = 15 where id = v_c;
  begin
    update public.contratos set status = 'encerrado' where id = v_c;
    raise exception 'T6 encerrar sem data_fim deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.contratos set pessoa_id = v.maria where id = v_c;
    raise exception 'T6 mudar pessoa deveria falhar';
  exception when check_violation then null; end;
  update public.contratos set status = 'encerrado', data_fim = current_date where id = v_c;
  begin
    update public.contratos set valor = 1 where id = v_c;
    raise exception 'T6 encerrado imutável';
  exception when check_violation then null; end;
end $$;

-- T7: negócio e pessoa com contratos vigentes não inativam
do $$ declare v r%rowtype; begin
  select * into v from r;
  begin
    update public.pessoas set ativo = false where id = v.maria; -- contrato suspenso vigente
    raise exception 'T7 pessoa com contrato vigente deveria falhar';
  exception when check_violation then null; end;
  update public.pessoa_negocio_vinculos set ativo = false where pessoa_id = v.joao and negocio_id = v.servidor;
  begin
    update public.negocios set ativo = false where id = v.servidor; -- contrato ativo do João
    raise exception 'T7 negócio com contrato vigente deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T8: RLS e DELETE
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ declare n int; begin
  select count(*) into n from public.contratos; assert n = 0, 'T8 contratos alheios';
  select count(*) into n from public.vw_receita_recorrente; assert n = 0, 'T8 view alheia';
  begin
    delete from public.planos;
    raise exception 'T8 delete deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
\echo OK
