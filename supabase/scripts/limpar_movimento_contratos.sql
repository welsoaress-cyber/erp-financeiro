-- =============================================================================
-- ZERAR O MOVIMENTO FINANCEIRO DOS CONTRATOS do negócio Servnet, mantendo a
-- estrutura montada (rodar no SQL Editor como proprietário).
-- Caso de uso: lançamentos bagunçados → apagar tudo que é cobrança de contrato
-- e lançar/refaturar de novo, sem recadastrar nada.
--
-- ⚠️ ANTES DE RODAR: gere um backup (GitHub → Actions → backup-banco →
--    Run workflow). Não há como desfazer.
--
-- APAGA (só do negócio Servnet):
--   • TODOS os lançamentos vinculados a contratos (previstos E efetivados,
--     cadeias de recorrência inteiras) e seus movimentos
--     → os SALDOS das contas recuam o valor das receitas/despesas apagadas
--   • faturamentos, execuções de faturamento e descontos de contrato
--   • notificações de cobrança, cobranças Pix e bloqueios pendentes
-- PRESERVA (tudo):
--   • contratos, clientes, planos, contas, categorias
--   • lançamentos SEM contrato (despesas avulsas, comissões, compras)
--   • ordens de serviço, comodatos, portas de CTO, instalações/payback,
--     estoque e aceites digitais — nada é tocado
--
-- DEPOIS: o faturamento automático recria as cobranças de cada competência
-- a partir do "faturar desde" de cada contrato (limpas), ou lance manualmente.
-- Tudo ou nada (uma transação).
-- =============================================================================
begin;

do $$
declare
  v_neg uuid;
  v_la int; n int;
begin
  select id into v_neg from public.negocios where lower(nome) like '%servnet%' or slug = 'servnet' limit 1;
  if v_neg is null then raise exception 'Negócio Servnet não encontrado. Ajuste o filtro no script.'; end if;

  create temp table _lanc on commit drop as
    select l.id from public.lancamentos l
     where l.contrato_id in (select id from public.contratos where negocio_id = v_neg);
  select count(*) into v_la from _lanc;
  raise notice 'Negócio: % · lançamentos de contrato a apagar: %', v_neg, v_la;

  -- imutabilidades saem do caminho só dentro desta transação
  alter table public.lancamentos      disable trigger user;
  alter table public.movimentos       disable trigger user;
  alter table public.faturamentos     disable trigger user;
  alter table public.notificacoes_log disable trigger user;
  alter table public.pix_cobrancas    disable trigger user;
  alter table public.bloqueios        disable trigger user;

  -- 1) dependências dos lançamentos de contrato
  delete from public.notificacoes_log where lancamento_id in (select id from _lanc);
  delete from public.pix_cobrancas    where lancamento_id in (select id from _lanc);
  delete from public.bloqueios        where negocio_id = v_neg and status = 'pendente';
  delete from public.descontos_contrato where contrato_id in (select id from public.contratos where negocio_id = v_neg);
  delete from public.faturamentos     where lancamento_id in (select id from _lanc);
  delete from public.faturamento_execucoes
   where organizacao_id = (select organizacao_id from public.negocios where id = v_neg);

  -- 2) movimentos e os próprios lançamentos (cadeias da ponta para trás)
  delete from public.movimentos where lancamento_id in (select id from _lanc);
  loop
    delete from public.lancamentos l
     where l.id in (select id from _lanc)
       and not exists (select 1 from public.lancamentos f
                        where f.lancamento_origem_id = l.id and f.id in (select id from _lanc));
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
  select count(*) into n from public.lancamentos where id in (select id from _lanc);
  if n > 0 then raise exception 'Sobraram % lançamentos — nada foi gravado. Reporte este erro.', n; end if;

  alter table public.lancamentos      enable trigger user;
  alter table public.movimentos       enable trigger user;
  alter table public.faturamentos     enable trigger user;
  alter table public.notificacoes_log enable trigger user;
  alter table public.pix_cobrancas    enable trigger user;
  alter table public.bloqueios        enable trigger user;

  raise notice 'Concluído: % lançamentos de contrato apagados. Contratos e cadastros intactos — pronto para lançar de novo.', v_la;
end $$;

commit;

-- Conferência: lançamentos de contrato do Servnet = 0; contratos continuam.
select
  (select count(*) from public.lancamentos l join public.contratos c on c.id = l.contrato_id
    join public.negocios n on n.id = c.negocio_id where lower(n.nome) like '%servnet%') as lancamentos_de_contrato,
  (select count(*) from public.contratos c join public.negocios n on n.id = c.negocio_id
    where lower(n.nome) like '%servnet%') as contratos_preservados,
  (select count(*) from public.faturamentos f join public.contratos c on c.id = f.contrato_id
    join public.negocios n on n.id = c.negocio_id where lower(n.nome) like '%servnet%') as faturamentos;
