-- =============================================================================
-- 0082 · CUSTO POR CLIENTE: despesa vinculada ao contrato entra no payback (53B parcial)
-- =============================================================================
-- Regra do proprietário: "se comprei qualquer coisa para atender um cliente
-- específico, o gasto é dele" — o vínculo lançamento → contrato É o centro de
-- custo do cliente, e tudo decorre disso: rentabilidade (já era), payback (não
-- era: só instalação pelo Estoque + comissão de OS) e relatório.
-- 1) vw_payback_contrato: custo = instalações + comissões + despesas lançadas
--    para o contrato (não canceladas; comissões excluídas para não duplicar).
-- 2) vw_rel_custo_cliente: quanto cada cliente/contrato rendeu, custou e o payback.
-- =============================================================================
create or replace view public.vw_payback_contrato
with (security_invoker = true) as
with custo as (
  select contrato_id, sum(custo_total) as custo, count(*) as instalacoes, min(data) as primeira_instalacao
    from public.estoque_instalacoes where contrato_id is not null group by contrato_id
), com as (
  select o.contrato_id, sum(l.valor) as comissao
    from public.ordens_servico o
    join public.lancamentos l on l.id = o.comissao_lancamento_id and l.status <> 'cancelado'
   where o.contrato_id is not null group by o.contrato_id
), desp as (
  -- 0082: qualquer despesa lançada PARA o contrato (roteador, ONU, cabo comprado para o cliente)
  -- é custo dele — prevista ou paga (o custo existe desde a compra; parcelas não adiam o payback).
  -- Comissões de OS já entram em "com"; ficam fora daqui para não contar duas vezes.
  select l.contrato_id, sum(l.valor) as despesas, min(coalesce(l.data_efetivacao, l.data_competencia)) as primeira_despesa
    from public.lancamentos l
   where l.tipo = 'despesa' and l.status <> 'cancelado' and l.contrato_id is not null
     and not exists (select 1 from public.ordens_servico o where o.comissao_lancamento_id = l.id)
   group by l.contrato_id
), base as (
  select coalesce(cu.contrato_id, co.contrato_id, d.contrato_id) as contrato_id,
         coalesce(cu.custo, 0) + coalesce(co.comissao, 0) + coalesce(d.despesas, 0) as custo_instalacao,
         coalesce(cu.instalacoes, 0) as instalacoes,
         least(cu.primeira_instalacao, d.primeira_despesa) as primeira_instalacao,
         coalesce(d.despesas, 0) as despesas_contrato
    from custo cu
    full join com co on co.contrato_id = cu.contrato_id
    full join desp d on d.contrato_id = coalesce(cu.contrato_id, co.contrato_id)
), rec as (
  select l.contrato_id, l.data_efetivacao, l.valor,
         sum(l.valor) over (partition by l.contrato_id order by l.data_efetivacao, l.criado_em rows unbounded preceding) as acumulado
    from public.lancamentos l where l.tipo = 'receita' and l.status = 'efetivado' and l.contrato_id is not null
), pago as (
  select r.contrato_id, min(r.data_efetivacao) as data_payback_real
    from rec r join base c on c.contrato_id = r.contrato_id
   where c.custo_instalacao > 0 and r.acumulado >= c.custo_instalacao group by r.contrato_id
), total as (
  select contrato_id, sum(valor) as recebido from rec group by contrato_id
)
select c.id as contrato_id, c.organizacao_id, c.negocio_id, c.pessoa_id, c.status, c.valor, c.periodicidade, c.data_inicio,
       coalesce(b.custo_instalacao, 0)::numeric(12,2) as custo_instalacao,
       coalesce(b.instalacoes, 0) as instalacoes,
       b.primeira_instalacao,
       (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3
                             when 'semestral' then c.valor / 6 when 'anual' then c.valor / 12 else 0 end)::numeric(12,2) as mensalidade,
       case when b.custo_instalacao > 0 and c.periodicidade <> 'unico' and c.valor > 0
            then ceil(b.custo_instalacao / (case c.periodicidade when 'mensal' then c.valor when 'bimestral' then c.valor / 2 when 'trimestral' then c.valor / 3 when 'semestral' then c.valor / 6 else c.valor / 12 end))::int
            else null end as payback_estimado_meses,
       coalesce(t.recebido, 0)::numeric(12,2) as recebido,
       p.data_payback_real,
       case when b.custo_instalacao > 0 and p.data_payback_real is not null
            then (extract(year from age(p.data_payback_real, coalesce(b.primeira_instalacao, c.data_inicio))) * 12
                + extract(month from age(p.data_payback_real, coalesce(b.primeira_instalacao, c.data_inicio))))::int
            else null end as payback_real_meses,
       coalesce(b.despesas_contrato, 0)::numeric(12,2) as despesas_contrato
  from public.contratos c
  left join base b on b.contrato_id = c.id
  left join total t on t.contrato_id = c.id
  left join pago p on p.contrato_id = c.id;

create view public.vw_rel_custo_cliente
with (security_invoker = true) as
select p.organizacao_id, p.negocio_id, n.nome as negocio,
       p.pessoa_id, pe.nome as pessoa, pe.telefone,
       p.contrato_id, c.codigo as contrato_codigo, pl.nome as plano, p.status, p.data_inicio, c.data_fim,
       p.mensalidade,
       p.recebido as receitas,
       (p.custo_instalacao - p.despesas_contrato)::numeric(12,2) as custo_instalacao,
       p.despesas_contrato,
       p.custo_instalacao as custo_total,
       (p.recebido - p.custo_instalacao)::numeric(12,2) as resultado,
       p.payback_estimado_meses,
       p.payback_real_meses,
       p.data_payback_real
  from public.vw_payback_contrato p
  join public.contratos c on c.id = p.contrato_id
  join public.pessoas pe on pe.id = p.pessoa_id
  left join public.negocios n on n.id = p.negocio_id
  left join public.planos pl on pl.id = c.plano_id
 where c.tipo_financeiro = 'receita';
grant select on public.vw_rel_custo_cliente to authenticated;
