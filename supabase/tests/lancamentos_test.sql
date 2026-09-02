-- Testes da migration 0005 (motor financeiro). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- contas e categorias da Ana
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) select organizacao_id, 'Banco', 'corrente', 1000 from public.categorias limit 1;
insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) select organizacao_id, 'Carteira', 'dinheiro', 50 from public.categorias limit 1;

create temp table ids as
select (select id from public.contas where nome = 'Banco') as banco,
       (select id from public.contas where nome = 'Carteira') as carteira,
       (select id from public.categorias where nome = 'Salário') as cat_salario,
       (select id from public.categorias where nome = 'Alimentação') as cat_alim,
       (select id from public.categorias where nome = 'Outros' and tipo = 'receita') as cat_outros_rec;

-- T1: receita efetivada → 1 movimento positivo; despesa → 1 negativo; transferência → 2 com soma zero
select public.criar_lancamento('receita', 'Salário setembro', 3000, '2026-09-05', null, '2026-09-05', banco, null, cat_salario) from ids;
select public.criar_lancamento('despesa', 'Mercado', 250.50, '2026-09-06', null, '2026-09-06', banco, null, cat_alim) from ids;
select public.criar_lancamento('transferencia', 'Saque', 200, '2026-09-07', null, '2026-09-07', banco, carteira, null) from ids;
do $$
declare n int; s numeric;
begin
  select count(*), sum(m.valor) into n, s from public.movimentos m join public.lancamentos l on l.id = m.lancamento_id where l.descricao = 'Salário setembro'; assert n = 1 and s = 3000, 'T1 receita';
  select count(*), sum(m.valor) into n, s from public.movimentos m join public.lancamentos l on l.id = m.lancamento_id where l.descricao = 'Mercado'; assert n = 1 and s = -250.50, 'T1 despesa';
  select count(*), sum(m.valor) into n, s from public.movimentos m join public.lancamentos l on l.id = m.lancamento_id where l.descricao = 'Saque'; assert n = 2 and s = 0, 'T1 transferência';
end $$;

-- T2: saldo derivado
do $$
declare s numeric;
begin
  select saldo into s from public.vw_saldo_contas where nome = 'Banco'; assert s = 1000 + 3000 - 250.50 - 200, 'T2 saldo banco';
  select saldo into s from public.vw_saldo_contas where nome = 'Carteira'; assert s = 250, 'T2 saldo carteira';
end $$;

-- T3: resultado mensal ignora transferência; só efetivados
select public.criar_lancamento('despesa', 'Conta de luz', 180, '2026-09-20', '2026-09-25', null, banco, null, cat_alim) from ids; -- previsto
do $$
declare r record;
begin
  select * into r from public.vw_resultado_mensal where mes = '2026-09-01';
  assert r.receitas = 3000 and r.despesas = 250.50 and r.resultado = 2749.50, 'T3 resultado';
end $$;

-- T4: previsto não gera movimento; efetivar gera; saldo muda
do $$
declare v_id uuid; n int; s numeric;
begin
  select id into v_id from public.lancamentos where descricao = 'Conta de luz';
  select count(*) into n from public.movimentos where lancamento_id = v_id; assert n = 0, 'T4 previsto sem movimento';
  perform public.efetivar_lancamento(v_id, '2026-09-24');
  select count(*) into n from public.movimentos where lancamento_id = v_id; assert n = 1, 'T4 efetivado gera';
  select saldo into s from public.vw_saldo_contas where nome = 'Banco'; assert s = 3549.50 - 180, 'T4 saldo';
  begin
    perform public.efetivar_lancamento(v_id, '2026-09-24');
    raise exception 'T4 efetivar duas vezes deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: editar efetivado regenera movimentos (valor e conta)
do $$
declare v_id uuid; n int; s numeric;
begin
  select id into v_id from public.lancamentos where descricao = 'Mercado';
  perform public.atualizar_lancamento(v_id, 'Mercado', 300, '2026-09-06', null, '2026-09-06', (select carteira from ids), null, (select cat_alim from ids));
  select count(*), sum(valor) into n, s from public.movimentos where lancamento_id = v_id; assert n = 1 and s = -300, 'T5 regenerado';
  select saldo into s from public.vw_saldo_contas where nome = 'Banco'; assert s = 1000 + 3000 - 200 - 180, 'T5 saldo banco';
  select saldo into s from public.vw_saldo_contas where nome = 'Carteira'; assert s = 50 + 200 - 300, 'T5 saldo carteira';
end $$;

-- T6: cancelar remove movimentos, mantém histórico, fica imutável
do $$
declare v_id uuid; n int; l public.lancamentos%rowtype;
begin
  select id into v_id from public.lancamentos where descricao = 'Saque';
  perform public.cancelar_lancamento(v_id, 'lançado errado');
  select * into l from public.lancamentos where id = v_id; assert l.status = 'cancelado' and l.cancelado_em is not null and l.motivo_cancelamento = 'lançado errado', 'T6 status';
  select count(*) into n from public.movimentos where lancamento_id = v_id; assert n = 0, 'T6 movimentos removidos';
  select count(*) into n from public.auditoria where tabela = 'movimentos' and acao = 'DELETE' and registro_id in (select registro_id from public.auditoria where tabela='movimentos' and acao='INSERT' and dados_depois->>'lancamento_id' = v_id::text); assert n = 2, 'T6 auditoria dos movimentos';
  begin
    perform public.atualizar_lancamento(v_id, 'x', 1, '2026-09-07', null, null, null, null, null);
    raise exception 'T6 editar cancelado deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.cancelar_lancamento(v_id);
    raise exception 'T6 cancelar duas vezes deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T7: excluir só previsto
do $$
declare v_prev uuid; v_ef uuid; n int;
begin
  select id into v_ef from public.lancamentos where descricao = 'Mercado';
  begin
    perform public.excluir_lancamento(v_ef);
    raise exception 'T7 excluir efetivado deveria falhar';
  exception when check_violation then null; end;
  perform public.criar_lancamento('despesa', 'Temporário', 10, '2026-10-01', null, null, (select banco from ids), null, (select cat_alim from ids));
  select id into v_prev from public.lancamentos where descricao = 'Temporário';
  perform public.excluir_lancamento(v_prev);
  select count(*) into n from public.lancamentos where id = v_prev; assert n = 0, 'T7 excluído';
end $$;

-- T8: validações do motor
do $$
declare b uuid; c uuid; cs uuid; ca uuid;
begin
  select banco, carteira, cat_salario, cat_alim into b, c, cs, ca from ids;
  begin
    perform public.criar_lancamento('receita', 'x', 10, '2026-09-01', null, '2026-09-01', b, null, ca);
    raise exception 'T8 categoria de despesa em receita deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('transferencia', 'x', 10, '2026-09-01', null, '2026-09-01', b, null, cs);
    raise exception 'T8 transferência com categoria deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('transferencia', 'x', 10, '2026-09-01', null, '2026-09-01', b, b, null);
    raise exception 'T8 transferência mesma conta deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('despesa', 'x', 0, '2026-09-01', null, '2026-09-01', b, null, ca);
    raise exception 'T8 valor zero deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_lancamento('despesa', 'x', 10, '2026-09-01', null, '2026-09-01', b, null, null);
    raise exception 'T8 despesa sem categoria deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T9: cliente não escreve direto em lancamentos/movimentos
do $$ begin
  begin
    insert into public.movimentos (organizacao_id, lancamento_id, conta_id, valor, data) select organizacao_id, id, conta_id, 999, current_date from public.lancamentos limit 1;
    raise exception 'T9 insert direto em movimentos deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    update public.lancamentos set valor = 1;
    raise exception 'T9 update direto em lancamentos deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.lancamentos;
    raise exception 'T9 delete direto deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T10: agora as regras de Contas e Categorias valem de verdade
do $$ begin
  begin
    update public.contas set ativo = false where nome = 'Banco';
    raise exception 'T10 inativar conta com movimentos deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.categorias set ativo = false where nome = 'Salário';
    raise exception 'T10 inativar categoria com lançamentos deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T11: RLS — Bruno não vê nada nem consegue lançar na conta da Ana
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare n int; b uuid; ca uuid;
begin
  select count(*) into n from public.lancamentos; assert n = 0, 'T11 select lancamentos';
  select count(*) into n from public.movimentos; assert n = 0, 'T11 select movimentos';
  select count(*) into n from public.vw_saldo_contas; assert n = 0, 'T11 view saldo';
  reset role;
  select banco, cat_alim into b, ca from ids;
  set local role authenticated;
  begin
    perform public.criar_lancamento('despesa', 'invasao', 10, '2026-09-01', null, '2026-09-01', b, null, ca);
    raise exception 'T11 lançar em conta alheia deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
rollback;
\echo OK
