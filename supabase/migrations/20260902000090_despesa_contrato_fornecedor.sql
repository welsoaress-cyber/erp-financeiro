-- =============================================================================
-- 0090 · Despesa ligada a contrato tem FORNECEDOR, não o cliente
-- =============================================================================
-- tg_lancamentos_contrato (0015) vale desde quando contrato só gerava receita:
-- todo lançamento com contrato era obrigado a ter a pessoa do contrato, e
-- pessoa nula virava o cliente na marra.
--
-- Desde a 0082 a despesa também se vincula ao contrato — "comprou para um
-- cliente, vincula ao contrato" — para entrar no payback e no relatório Custo
-- por cliente. Só que quem vendeu o roteador é a loja, não o cliente: a regra
-- antiga carimbava o cliente como fornecedor no Contas a pagar, sem como
-- corrigir (a tela travava o campo e o trigger reescrevia o valor).
--
-- Agora: RECEITA continua amarrada ao cliente do contrato (quem paga é ele).
-- DESPESA passa a ter a pessoa livre — é o fornecedor — e o contrato segue
-- valendo para custo e payback. Os relatórios não mudam: Custo por cliente e
-- rentabilidade leem a pessoa do CONTRATO, nunca a do lançamento.
-- =============================================================================

create or replace function public.tg_lancamentos_contrato()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
begin
  if new.contrato_id is null then return new; end if;
  if new.tipo = 'transferencia' then
    raise exception 'Transferência não pode ter contrato.' using errcode = 'check_violation';
  end if;
  select * into c from public.contratos where id = new.contrato_id;
  if not found or c.organizacao_id <> new.organizacao_id then
    raise exception 'Contrato inválido.' using errcode = 'check_violation';
  end if;
  new.negocio_id := coalesce(new.negocio_id, c.negocio_id);
  if new.negocio_id <> c.negocio_id then
    raise exception 'O negócio do lançamento difere do negócio do contrato.' using errcode = 'check_violation';
  end if;
  -- despesa: o contrato diz PARA QUEM foi a compra (custo/payback); a pessoa é quem VENDEU
  if new.tipo = 'despesa' then return new; end if;
  -- receita: quem paga é o cliente do contrato
  new.pessoa_id := coalesce(new.pessoa_id, c.pessoa_id);
  if new.pessoa_id <> c.pessoa_id then
    raise exception 'A pessoa do lançamento difere da pessoa do contrato.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
