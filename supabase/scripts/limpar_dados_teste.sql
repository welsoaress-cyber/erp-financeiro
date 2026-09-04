-- Limpeza de dados de teste (rodar no SQL Editor como proprietário).
-- Apaga TODO o movimento financeiro: lançamentos (qualquer status), contratos,
-- faturamentos, descontos, movimentos e log de notificações.
-- PRESERVA: organização, membros, contas, categorias, negócios, planos,
-- pessoas, configuração de notificações e do portal.
-- Ajuste os deletes se quiser preservar algo a mais. Tudo ou nada (transação).
begin;
alter table public.lancamentos disable trigger user;
alter table public.contratos disable trigger user;
alter table public.faturamentos disable trigger user;
alter table public.notificacoes_log disable trigger user;
alter table public.movimentos disable trigger user;

delete from public.notificacoes_log;
delete from public.movimentos;
delete from public.faturamentos;
delete from public.faturamento_execucoes;
delete from public.descontos_contrato;
delete from public.transacoes_carteira;
-- cadeias de recorrência: apaga da ponta para trás (FK restrict)
do $$
declare n int;
begin
  loop
    delete from public.lancamentos l
     where not exists (select 1 from public.lancamentos f where f.lancamento_origem_id = l.id);
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
end $$;
delete from public.contratos;

alter table public.movimentos enable trigger user;
alter table public.notificacoes_log enable trigger user;
alter table public.faturamentos enable trigger user;
alter table public.contratos enable trigger user;
alter table public.lancamentos enable trigger user;
commit;
