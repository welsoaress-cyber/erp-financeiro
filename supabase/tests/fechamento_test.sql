-- Testes da migration 0068 (fechamento de mês). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_rec uuid; v_ef uuid; v_pv uuid; v_mes date := date_trunc('month', current_date - interval '2 month')::date; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Fech Desp', 'despesa') returning id into v_cat;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Fech Rec', 'receita') returning id into v_rec;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'FECH T', 'fech-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Fech', 'dinheiro', v_neg) returning id into v_conta;
  -- efetivado e previsto dentro do mês que vai fechar
  select id into v_ef from public.criar_lancamento('despesa', 'Efetivada velha', 50, v_mes, v_mes, v_mes, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null);
  select id into v_pv from public.criar_lancamento('receita', 'Cobrança velha', 80, v_mes, v_mes, null, v_conta, null, v_rec, null, v_neg, null, null, false, null, null, null);

  -- T1: só mês passado fecha; fechar registra
  begin
    perform public.fechar_mes(current_date);
    raise exception 'T1 mês corrente não deveria fechar';
  exception when check_violation then null; end;
  perform public.fechar_mes(v_mes);
  assert public.mes_fechado(v_org, v_mes + 5), 'T1 mês fechado';

  -- T2: efetivado do mês fechado é intocável (editar, cancelar, excluir)
  begin
    perform public.atualizar_lancamento(v_ef, 'Mudança proibida', 60, v_mes, v_mes, v_mes, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null);
    raise exception 'T2 editar efetivado deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.cancelar_lancamento(v_ef, 'tentativa');
    raise exception 'T2 cancelar efetivado deveria falhar';
  exception when check_violation then null; end;

  -- T3: baixa atrasada da cobrança velha é permitida (caixa entra hoje)…
  perform public.efetivar_lancamento(v_pv, current_date);
  assert (select status from public.lancamentos where id = v_pv) = 'efetivado', 'T3 baixa atrasada ok';
  -- …mas efetivar com data DENTRO do mês fechado não
  declare v_pv2 uuid; begin
    select id into v_pv2 from public.criar_lancamento('receita', 'Cobrança velha 2', 30, v_mes, v_mes, null, v_conta, null, v_rec, null, v_neg, null, null, false, null, null, null);
    begin
      perform public.efetivar_lancamento(v_pv2, v_mes + 3);
      raise exception 'T3 efetivar dentro do mês fechado deveria falhar';
    exception when check_violation then null; end;
  end;

  -- T4: reabrir libera a edição de novo
  perform public.reabrir_mes(v_mes);
  perform public.cancelar_lancamento(v_ef, 'agora pode');
  assert (select status from public.lancamentos where id = v_ef) = 'cancelado', 'T4 reaberto edita';
end $$;

rollback;
\echo OK
