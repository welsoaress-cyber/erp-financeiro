-- Testes da migration 0126 (controle de boletos v1 + desconto em lançamento). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare
  v_org uuid; v_neg uuid; v_conta uuid; v_cat uuid; v_plano uuid;
  v_pessoa_pix uuid; v_pessoa_boleto uuid; v_pessoa_susp uuid;
  v_ct_pix uuid; v_ct_boleto uuid; v_ct_susp uuid;
  v_l uuid; v_l2 uuid; v_l_efetivado uuid; r record; v_env public.boletos_enviados%rowtype;
begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'receita' limit 1;
  insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'Caixa Boletos', 'dinheiro') returning id into v_conta;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'Boletos T', 'boletos-t', true) returning id into v_neg;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Boleto', 100, 'mensal') returning id into v_plano;

  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Pix', '92988880001') returning id into v_pessoa_pix;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Boleto', '92988880002') returning id into v_pessoa_boleto;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Boleto Suspenso', '92988880003') returning id into v_pessoa_susp;

  -- T1 (0127): forma_pagamento nasce 'outro' por padrão — "pix" só quando escolhido de propósito
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  values (v_org, v_neg, v_pessoa_pix, v_plano, 100, 'mensal', current_date - 60, 10) returning id into v_ct_pix;
  if (select forma_pagamento from public.contratos where id = v_ct_pix) <> 'outro' then raise exception 'T1 default deveria ser outro'; end if;
  update public.contratos set forma_pagamento = 'pix' where id = v_ct_pix;

  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, forma_pagamento)
  values (v_org, v_neg, v_pessoa_boleto, v_plano, 150, 'mensal', current_date - 60, 15, 'boleto') returning id into v_ct_boleto;

  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, forma_pagamento, status)
  values (v_org, v_neg, v_pessoa_susp, v_plano, 120, 'mensal', current_date - 60, 12, 'boleto', 'suspenso') returning id into v_ct_susp;

  v_l  := (public.criar_lancamento('receita', 'Fatura boleto', 150, current_date + 5, current_date + 5, null, v_conta, null, v_cat, null, v_neg, v_pessoa_boleto, v_ct_boleto)).id;
  v_l2 := (public.criar_lancamento('receita', 'Fatura pix', 100, current_date + 5, current_date + 5, null, v_conta, null, v_cat, null, v_neg, v_pessoa_pix, v_ct_pix)).id;
  perform public.criar_lancamento('receita', 'Fatura boleto suspenso', 120, current_date + 5, current_date + 5, null, v_conta, null, v_cat, null, v_neg, v_pessoa_susp, v_ct_susp);
  v_l_efetivado := (public.criar_lancamento('receita', 'Já paga', 150, current_date - 30, current_date - 30, current_date - 30, v_conta, null, v_cat, null, v_neg, v_pessoa_boleto, v_ct_boleto)).id;

  -- T10a: pendentes mostra só o boleto ativo sem envio
  if not exists (select 1 from public.vw_rel_boletos_pendentes where id = v_l) then raise exception 'T10a boleto ativo deveria aparecer'; end if;
  if exists (select 1 from public.vw_rel_boletos_pendentes where id = v_l2) then raise exception 'T10a pix não deveria aparecer'; end if;
  if exists (select 1 from public.vw_rel_boletos_pendentes where contrato_id = v_ct_susp) then raise exception 'T10a suspenso não deveria aparecer'; end if;
  if exists (select 1 from public.vw_rel_boletos_pendentes where id = v_l_efetivado) then raise exception 'T10a efetivado não deveria aparecer'; end if;

  -- T2/T3/T4/T5: desconto
  perform public.conceder_desconto_lancamento(v_l, 20, 'Negociação');
  select * into r from public.lancamentos where id = v_l;
  if r.valor <> 130 or r.valor_desconto <> 20 or r.motivo_desconto <> 'Negociação' then
    raise exception 'T2 desconto: valor=% desconto=% motivo=%', r.valor, r.valor_desconto, r.motivo_desconto;
  end if;

  begin
    perform public.conceder_desconto_lancamento(v_l, 10, null);
    raise exception 'T3 deveria falhar sem motivo';
  exception when check_violation then null; end;

  begin
    perform public.conceder_desconto_lancamento(v_l, -5, 'x');
    raise exception 'T4 deveria falhar com desconto negativo';
  exception when check_violation then null; end;

  begin
    perform public.conceder_desconto_lancamento(v_l, 150, 'tudo');
    raise exception 'T5 deveria falhar descontando o valor cheio';
  exception when check_violation then null; end;

  begin
    perform public.conceder_desconto_lancamento(v_l_efetivado, 10, 'tarde demais');
    raise exception 'T6 deveria falhar em lançamento efetivado';
  exception when check_violation then null; end;

  -- T7: remover desconto (chamar com 0) restaura o valor cheio
  perform public.conceder_desconto_lancamento(v_l, 0, null);
  select * into r from public.lancamentos where id = v_l;
  if r.valor <> 150 or r.valor_desconto <> 0 or r.motivo_desconto is not null then
    raise exception 'T7 remover desconto: valor=% desconto=% motivo=%', r.valor, r.valor_desconto, r.motivo_desconto;
  end if;

  -- T8: código de barras
  perform public.definir_codigo_barras_lancamento(v_l, '34191.79001 01043.510047 91020.150008 1 96380000015000');
  if (select codigo_barras from public.lancamentos where id = v_l) is null then raise exception 'T8 código de barras não gravou'; end if;
  begin
    perform public.definir_codigo_barras_lancamento(v_l_efetivado, '123');
    raise exception 'T8b deveria falhar em efetivado';
  exception when check_violation then null; end;

  -- T9: registrar envio — some da lista de pendentes; reenvio soma histórico
  v_env := public.registrar_boleto_enviado(v_l, 'Olá! Segue o boleto, vencimento em breve.');
  if v_env.lancamento_id <> v_l then raise exception 'T9 envio não vinculou o lançamento certo'; end if;
  if exists (select 1 from public.vw_rel_boletos_pendentes where id = v_l) then raise exception 'T9 deveria sumir dos pendentes após o envio'; end if;
  perform public.registrar_boleto_enviado(v_l, 'Reenviando o boleto, por favor confirme o recebimento.');
  if (select count(*) from public.boletos_enviados where lancamento_id = v_l) <> 2 then raise exception 'T9b reenvio deveria criar uma segunda linha'; end if;

  -- T11: vw_rel_lancamentos carrega o desconto
  perform public.conceder_desconto_lancamento(v_l2, 15, 'Pontualidade');
  if (select valor_desconto from public.vw_rel_lancamentos where id = v_l2) <> 15 then raise exception 'T11 vw_rel_lancamentos sem valor_desconto'; end if;
  if (select motivo_desconto from public.vw_rel_lancamentos where id = v_l2) <> 'Pontualidade' then raise exception 'T11 vw_rel_lancamentos sem motivo_desconto'; end if;
end $$;

rollback;
\echo OK
