-- Testes da migration 0128 (dedup de nota fiscal importada por chave). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare
  v_org uuid; v_neg uuid; v_fornecedor uuid; v_plano uuid; v_ct uuid; v_cat uuid;
  v_req public.compra_requisicoes%rowtype; v_ped public.compras%rowtype;
  v_chave1 text := '31261031405199000161550010000101591325848159';
  v_chave2 text := '31261031405199000161550010000101591325848100';
  r public.notas_fiscais_importadas%rowtype;
begin
  select organizacao_id into v_org from public.categorias limit 1;
  select id into v_cat from public.categorias where organizacao_id = v_org and tipo = 'despesa' limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'NF Teste', 'nf-teste', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, tipo, nome, documento) values (v_org, 'juridica', 'Nubbi Educacao', '31405199000161') returning id into v_fornecedor;

  -- T1: destino 'contrato' exige contrato_id; destino 'compra' exige compra_id
  begin
    perform public.registrar_nota_fiscal_importada(v_neg, v_fornecedor, v_chave1, '10159', 270, current_date, 'contrato', null, null, null);
    raise exception 'T1 deveria falhar sem contrato_id';
  exception when check_violation then null; end;

  -- T2: chave com tamanho errado falha
  begin
    perform public.registrar_nota_fiscal_importada(v_neg, v_fornecedor, '123', '1', 10, current_date, 'compra', gen_random_uuid());
    raise exception 'T2 deveria falhar com chave curta';
  exception when check_violation then null; end;

  -- monta um pedido real (requisição → aprovação) pra ter um compra_id válido
  v_req := public.criar_requisicao_compra(v_neg, jsonb_build_array(jsonb_build_object('descricao', 'Material Didático Digital', 'quantidade', 300, 'destino', 'despesa')));
  v_ped := public.aprovar_requisicao_compra(v_req.id, v_fornecedor, jsonb_build_array(jsonb_build_object('valor_unitario', 0.90, 'categoria_id', v_cat)));

  -- T3: registra nota vinculada ao pedido (destino compra)
  r := public.registrar_nota_fiscal_importada(v_neg, v_fornecedor, v_chave1, '10159', 270, current_date, 'compra', v_ped.id);
  if r.chave <> v_chave1 or r.compra_id <> v_ped.id then raise exception 'T3 nota não gravou certo'; end if;

  -- T4: mesma chave de novo falha (duplicidade)
  begin
    perform public.registrar_nota_fiscal_importada(v_neg, v_fornecedor, v_chave1, '10159', 270, current_date, 'compra', v_ped.id);
    raise exception 'T4 deveria bloquear nota duplicada';
  exception when unique_violation then null; end;

  -- contrato de fornecedor pra testar o caminho "recorrente"
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'SVA Leveduca', 270, 'mensal') returning id into v_plano;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, tipo_financeiro)
  values (v_org, v_neg, v_fornecedor, v_plano, 270, 'mensal', current_date, 5, 'despesa') returning id into v_ct;

  -- T5: destino 'contrato' com chave nova funciona
  r := public.registrar_nota_fiscal_importada(v_neg, v_fornecedor, v_chave2, '10200', 270, current_date, 'contrato', null, v_ct);
  if r.contrato_id <> v_ct then raise exception 'T5 contrato não gravou certo'; end if;

  -- T6: negócio de outra organização não pode gravar (exigir_membro)
  begin
    perform public.registrar_nota_fiscal_importada('00000000-0000-0000-0000-000000000000', v_fornecedor, '00000000000000000000000000000000000000000000', '1', 1, current_date, 'contrato', null, v_ct);
    raise exception 'T6 deveria falhar (negócio inexistente)';
  exception when no_data_found then null; end;
end $$;

rollback;
\echo OK
