-- Bug: vw_receita_recorrente (0015) somava TODOS os contratos do negócio — receita E despesa —
-- num único número rotulado "receita recorrente". Um negócio com só contrato de despesa (ex.:
-- aluguel de imóvel, fornecedor) aparecia com o card "RECEITA RECORRENTE · R$ X/mês" mostrando
-- na verdade uma despesa. tipo_financeiro (0016, contratos_despesa) nunca foi incorporado a esta
-- view. Separa por tipo_financeiro: uma linha de receita e uma de despesa por negócio (quando
-- existir contrato do tipo).
drop view public.vw_receita_recorrente;
create view public.vw_receita_recorrente
with (security_invoker = true) as
select n.id as negocio_id, n.organizacao_id, n.nome as negocio, c.tipo_financeiro,
       count(c.id) filter (where c.status = 'ativo') as contratos_ativos,
       count(c.id) filter (where c.status = 'suspenso') as contratos_suspensos,
       coalesce(sum(case c.periodicidade when 'mensal' then c.valor when 'anual' then c.valor / 12 else 0 end) filter (where c.status = 'ativo'), 0)::numeric(14,2) as mrr
from public.negocios n
join public.contratos c on c.negocio_id = n.id
group by n.id, c.tipo_financeiro;
grant select on public.vw_receita_recorrente to authenticated;
