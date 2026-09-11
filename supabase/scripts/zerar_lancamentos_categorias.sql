-- =============================================================================
-- ZERAR LANÇAMENTOS E CATEGORIAS (todos os negócios) para recadastrar do zero
-- (rodar no SQL Editor como proprietário).
--
-- ⚠️ ANTES DE RODAR: gere um backup (GitHub → Actions → backup-banco).
--    Não há como desfazer.
--
-- APAGA (da organização inteira):
--   • TODOS os lançamentos (previstos e efetivados, todas as cadeias) e seus
--     movimentos → saldos das contas voltam ao saldo inicial
--   • faturamentos, execuções, faturas de cartão, notificações ligadas a
--     lançamento e cobranças Pix
--   • TODAS as categorias e subcategorias
-- AJUSTA:
--   • carteira de app exige uma categoria: o script cria "Consumo de
--     créditos" (despesa) e aponta a carteira para ela — única que fica
--   • negócios ficam SEM categoria padrão de receita/despesa: reconfigure em
--     Negócios antes do próximo faturamento automático
--   • vínculos de lançamento em estoque, OS (comissão), descontos e
--     transações de carteira são desfeitos (os registros ficam)
-- PRESERVA: contratos, pessoas, contas, negócios, estoque, rede, OS,
--   comodatos, indicações. As cobranças dos contratos renascem pelo
--   faturamento automático ("faturar desde").
-- Tudo ou nada (uma transação).
-- =============================================================================
begin;

do $$
declare
  v_la int; n int; t text; r record;
  tabelas constant text[] := array[
    'lancamentos','movimentos','faturamentos','fatura_itens','faturas',
    'notificacoes_log','pix_cobrancas','descontos_contrato',
    'estoque_movimentacoes','ordens_servico','transacoes_carteira',
    'categorias','negocios','carteira'
  ];
begin
  perform set_config('erp.motor', 'on', true);
  foreach t in array tabelas loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;

  select count(*) into v_la from public.lancamentos;
  raise notice 'Lançamentos a apagar: %', v_la;

  -- 1) dependências dos lançamentos
  delete from public.notificacoes_log where lancamento_id is not null;
  delete from public.pix_cobrancas;
  delete from public.faturamentos;
  delete from public.faturamento_execucoes where true;
  delete from public.fatura_itens;
  delete from public.faturas;
  update public.descontos_contrato   set lancamento_id = null where lancamento_id is not null;
  update public.estoque_movimentacoes set lancamento_id = null where lancamento_id is not null;
  update public.ordens_servico set comissao_lancamento_id = null where comissao_lancamento_id is not null;
  update public.transacoes_carteira set lancamento_id = null where lancamento_id is not null;

  -- 2) movimentos e lançamentos (cadeias da ponta para trás)
  delete from public.movimentos;
  loop
    delete from public.lancamentos l
     where not exists (select 1 from public.lancamentos f where f.lancamento_origem_id = l.id);
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
  select count(*) into n from public.lancamentos;
  if n > 0 then raise exception 'Sobraram % lançamentos — nada foi gravado. Reporte este erro.', n; end if;

  -- 3) carteira exige categoria: cria "Consumo de créditos" e reaponta
  for r in select distinct organizacao_id from public.carteira loop
    insert into public.categorias (organizacao_id, nome, tipo)
    values (r.organizacao_id, 'Consumo de créditos', 'despesa');
  end loop;
  update public.carteira c
     set categoria_consumo_id = (select id from public.categorias k
                                  where k.organizacao_id = c.organizacao_id and k.nome = 'Consumo de créditos');

  -- 4) categorias: some tudo, menos a de consumo da carteira
  update public.negocios set categoria_receita_id = null, categoria_despesa_id = null;
  update public.categorias set categoria_pai_id = null where categoria_pai_id is not null;
  delete from public.categorias where id not in (select categoria_consumo_id from public.carteira);

  foreach t in array tabelas loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;
  raise notice 'Concluído: % lançamentos e as categorias apagados. Cadastre as categorias novas e defina os padrões em Negócios.', v_la;
end $$;

commit;

-- Conferência: lançamentos = 0; categorias = só a da carteira (se houver app)
select
  (select count(*) from public.lancamentos) as lancamentos,
  (select count(*) from public.movimentos)  as movimentos,
  (select count(*) from public.categorias)  as categorias_restantes,
  (select count(*) from public.contratos)   as contratos_preservados,
  (select count(*) from public.pessoas)     as pessoas_preservadas;
