-- Testes da migration 0088 (atualizar_lancamento com p_parcela_inicial). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; l public.lancamentos%rowtype; e public.lancamentos%rowtype; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Edit Desp', 'despesa') returning id into v_cat;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'EDIT T', 'edit-t', true) returning id into v_neg;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Edit', 'dinheiro', v_neg) returning id into v_conta;

  -- T1: o app manda os MESMOS 18 parâmetros de criar_lancamento — a assinatura tem de existir
  l := public.criar_lancamento('despesa', 'Compra no cartão', 100, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null, 1);
  e := public.atualizar_lancamento(l.id, 'Compra no cartão (corrigida)', 120, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null, 1);
  assert e.descricao = 'Compra no cartão (corrigida)' and e.valor = 120, 'T1 edição simples';

  -- T2: marcar como pago e voltar para não pago (o caso que quebrou em produção)
  e := public.atualizar_lancamento(l.id, 'Compra no cartão', 120, current_date, current_date, current_date, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null, 1);
  assert e.status = 'efetivado' and e.data_efetivacao = current_date, 'T2 vira efetivado';
  e := public.atualizar_lancamento(l.id, 'Compra no cartão', 120, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, false, null, null, null, 1);
  assert e.status = 'previsto' and e.data_efetivacao is null, 'T2 volta para previsto';
  assert not exists (select 1 from public.movimentos where lancamento_id = l.id), 'T2 movimento sai junto';

  -- T3: avulso que vira parcelado começa na parcela pedida
  e := public.atualizar_lancamento(l.id, 'Compra parcelada', 120, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 24, null, 2);
  assert e.parcela_atual = 2 and e.numero_parcelas = 24, 'T3 vira 2/24';

  -- T4: edição seguinte não mexe na numeração da cadeia
  e := public.atualizar_lancamento(l.id, 'Compra parcelada', 130, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 24, null, 1);
  assert e.parcela_atual = 2, 'T4 numeração intocada';

  -- T5: sem o parâmetro (default 1) continua funcionando
  e := public.atualizar_lancamento(l.id, 'Compra parcelada', 140, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 24, null);
  assert e.valor = 140 and e.parcela_atual = 2, 'T5 default';
  -- T6: parcelamento com a próxima parcela já gerada — trocar só o fornecedor tem de passar
  -- (é o que a tela faz depois do lote: o trigger só barra mudança na recorrência em si)
  declare v_pes uuid; v_raiz public.lancamentos%rowtype; begin
    insert into public.pessoas (organizacao_id, nome, tipo) values (v_org, 'Loja Fornecedora', 'juridica') returning id into v_pes;
    v_raiz := public.criar_lancamento('despesa', 'Roteador 6x', 60, current_date, current_date, null, v_conta, null, v_cat, null, v_neg, null, null, true, 'mensal', 6, null, 1);
    perform public.efetivar_lancamento(v_raiz.id, current_date);
    assert exists (select 1 from public.lancamentos where lancamento_origem_id = v_raiz.id), 'T6 próxima parcela gerada';
    -- mudar só uma parcela continua barrado (o parcelamento ficaria inconsistente)
    begin
      perform public.atualizar_lancamento(v_raiz.id, 'Roteador 6x', 60, current_date, current_date, current_date, v_conta, null, v_cat, null, v_neg, v_pes, null, true, 'mensal', 6, null, 1);
      raise exception 'T6 mudar fornecedor de uma parcela só deveria falhar';
    exception when check_violation then null; end;
    -- corrigir a cadeia inteira é o caminho: todas as parcelas passam a ter o fornecedor
    perform public.corrigir_cadeia_lancamento(v_raiz.id, v_pes, v_cat, null, v_neg, null);
    assert (select count(*) from public.lancamentos where (id = v_raiz.id or lancamento_origem_id = v_raiz.id) and pessoa_id = v_pes) = 2,
      'T6 fornecedor aplicado na cadeia inteira';
    -- corrigir pela parcela filha também acha a raiz e aplica em todas
    perform public.corrigir_cadeia_lancamento((select id from public.lancamentos where lancamento_origem_id = v_raiz.id), null, v_cat, null, v_neg, null);
    assert (select count(*) from public.lancamentos where (id = v_raiz.id or lancamento_origem_id = v_raiz.id) and pessoa_id is null) = 2,
      'T6 correção pela filha sobe até a raiz';
  end;
end $$;

rollback;
\echo OK
