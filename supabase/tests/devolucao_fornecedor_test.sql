-- Testes da migration 0085 (devolução ao fornecedor / RMA). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_p uuid; v_conta uuid; v_categ uuid; v_dev uuid; r record; l record; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'DEV T', 'dev-t', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Equip DEV') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome) values (v_org, v_neg, v_cat, 'ONU-DEV', 'ONU DEV') returning id into v_item;
  perform public.entrada_estoque(v_item, 5, 500); -- custo médio 100
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Fornecedor DEV', '92988882222') returning id into v_p;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa DEV', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Reembolso fornecedor DEV', 'receita') returning id into v_categ;

  -- T1: abrir devolução baixa o estoque e cria receita prevista
  select * into r from public.abrir_devolucao_fornecedor(v_item, 1, 'Veio com defeito de fábrica', v_conta, v_categ, current_date, v_p);
  v_dev := r.id;
  if r.status <> 'aberta' or r.quantidade <> 1 or r.valor <> 100 then raise exception 'T1 status/valor %', to_jsonb(r); end if;
  if (select quantidade_atual from public.estoque_itens where id = v_item) <> 4 then raise exception 'T1 saldo não baixou'; end if;
  select * into l from public.lancamentos where id = r.lancamento_id;
  if l.status <> 'previsto' or l.tipo <> 'receita' or l.valor <> 100 then raise exception 'T1 lancamento %', to_jsonb(l); end if;

  -- T2: não abre com quantidade maior que o disponível
  begin
    perform public.abrir_devolucao_fornecedor(v_item, 999, 'Excesso', v_conta, v_categ);
    raise exception 'T2 deveria falhar (saldo insuficiente)';
  exception when others then null; end;

  -- T3: resolver com reembolso efetiva o lançamento
  select * into r from public.resolver_devolucao_fornecedor(v_dev, 'reembolso');
  if r.status <> 'reembolsada' then raise exception 'T3 status=%', r.status; end if;
  select * into l from public.lancamentos where id = r.lancamento_id;
  if l.status <> 'efetivado' then raise exception 'T3 lancamento status=%', l.status; end if;

  -- não resolve de novo
  begin
    perform public.resolver_devolucao_fornecedor(v_dev, 'troca');
    raise exception 'T3b deveria falhar (já resolvida)';
  exception when others then null; end;

  -- T4: troca — entrada pelo mesmo valor (custo médio preservado) e cancela a receita
  select * into r from public.abrir_devolucao_fornecedor(v_item, 1, 'Outro defeito', v_conta, v_categ);
  select * into r from public.resolver_devolucao_fornecedor(r.id, 'troca');
  if r.status <> 'trocada' then raise exception 'T4 status=%', r.status; end if;
  if (select valor_custo from public.estoque_itens where id = v_item) <> 100 then raise exception 'T4 custo médio mudou: %', (select valor_custo from public.estoque_itens where id = v_item); end if;
  select * into l from public.lancamentos where id = r.lancamento_id;
  if l.status <> 'cancelado' then raise exception 'T4 lancamento status=%', l.status; end if;

  -- T5: negada — cancela a receita, saldo não volta
  select * into r from public.abrir_devolucao_fornecedor(v_item, 1, 'Sem solução', v_conta, v_categ);
  select * into r from public.resolver_devolucao_fornecedor(r.id, 'negada');
  if r.status <> 'negada' then raise exception 'T5 status=%', r.status; end if;
  select * into l from public.lancamentos where id = r.lancamento_id;
  if l.status <> 'cancelado' then raise exception 'T5 lancamento status=%', l.status; end if;

  -- T6: relatório reflete tudo
  if (select count(*) from public.vw_rel_devolucoes_fornecedor where item_id = v_item) <> 3 then raise exception 'T6 relatório'; end if;
  if (select fornecedor from public.vw_rel_devolucoes_fornecedor where devolucao_id = v_dev) <> 'Fornecedor DEV' then raise exception 'T6 fornecedor'; end if;
end $$;

rollback;
\echo OK
