-- =============================================================================
-- 0124 · Relatório "Inadimplência" agrupa por mês de vencimento
-- =============================================================================
-- O proprietário pediu uma visão simples: mês → vencimento, cliente, negócio,
-- valor — sem precisar trocar o mês na tela de Contas a Receber nem entender
-- a diferença entre o aviso "pendências de meses anteriores" (só antes do mês
-- corrente) e o filtro "Vencidos" de cada mês (só dentro do mês escolhido). O
-- relatório "Inadimplência" já existente (0079) traz tudo que está vencido
-- agora, de qualquer mês, numa linha só — só faltava agrupar por mês.
-- =============================================================================

create or replace view public.vw_rel_inadimplencia
with (security_invoker = true) as
select l.id, l.organizacao_id, l.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       l.pessoa_id, p.nome as pessoa, p.telefone,
       l.contrato_id, k.codigo as contrato_codigo,
       l.descricao, l.valor, l.data_vencimento,
       (current_date - l.data_vencimento)::int as dias_atraso,
       date_trunc('month', l.data_vencimento)::date as mes_vencimento
  from public.lancamentos l
  left join public.negocios n on n.id = l.negocio_id
  left join public.pessoas p on p.id = l.pessoa_id
  left join public.contratos k on k.id = l.contrato_id
 where l.tipo = 'receita' and l.status = 'previsto' and l.data_vencimento < current_date;
