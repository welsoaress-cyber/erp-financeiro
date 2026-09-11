-- =============================================================================
-- RECOMEÇO DA SERVNET: apaga TODOS os dados de teste do negócio Servnet para
-- começar a usar de verdade (rodar no SQL Editor como proprietário).
--
-- ⚠️ ANTES DE RODAR: gere um backup (GitHub → Actions → backup-banco →
--    Run workflow). Não há como desfazer.
--
-- APAGA (só do negócio Servnet):
--   • TODOS os lançamentos do negócio (com e sem contrato) e seus movimentos
--   • contratos, faturamentos, execuções, descontos, indicações e aceites
--   • cobranças Pix, bloqueios, notificações de cobrança e disparos
--   • ordens de serviço (com histórico, materiais e fotos) e comodatos
--   • movimentações de estoque, instalações, bolsas dos técnicos e
--     solicitações de reposição — os ITENS ficam cadastrados com quantidade 0
--   • clientes (pessoas) que só existiam na Servnet + logins do portal deles
--   • vínculos de porta CTO (portas voltam a livre) e histórico das caixas
--   • status/eventos de OLT e solicitações do portal
-- PRESERVA:
--   • o negócio Servnet, planos, contas, categorias, promoções e modelos
--   • itens e categorias de estoque (zerados), técnicos e seus logins
--   • rede FTTH física: POPs, CEOs, CTOs, fios e lacres
--   • os demais negócios (Toptv etc.) — nada deles é tocado
--   • pessoas com vínculo fora da Servnet (ficam, só perdem o vínculo Servnet)
--
-- DEPOIS: recadastre clientes e contratos (Configurações → Importar CSV ou um
-- a um) e lance de verdade. Tudo ou nada (uma transação).
-- =============================================================================
begin;

do $$
declare
  v_neg uuid;
  v_org uuid;
  n int; v_la int; v_ct int; v_pe int := 0;
  r record;
  t text;
  tabelas constant text[] := array[
    'lancamentos','movimentos','contratos','faturamentos','notificacoes_log',
    'ordens_servico','os_historico','os_materiais','os_fotos',
    'comodatos','comodato_historico','estoque_movimentacoes','estoque_instalacoes','estoque_itens',
    'aceites_contrato','cto_portas','cto_historico','pix_cobrancas','bloqueios',
    'tecnico_movimentacoes','tecnico_estoque','reposicao_solicitacoes',
    'pessoas','pessoa_negocio_vinculos','portal_acessos','portal_solicitacoes',
    'indicacoes','descontos_contrato','disparos','disparo_itens','transacoes_carteira','fatura_itens'
  ];
begin
  select id, organizacao_id into v_neg, v_org
    from public.negocios where lower(nome) like '%servnet%' or slug = 'servnet' limit 1;
  if v_neg is null then raise exception 'Negócio Servnet não encontrado. Ajuste o filtro no script.'; end if;

  create temp table _contratos on commit drop as select id from public.contratos where negocio_id = v_neg;
  create temp table _lanc on commit drop as select id from public.lancamentos where negocio_id = v_neg;
  create temp table _os on commit drop as select id from public.ordens_servico where negocio_id = v_neg;
  -- candidatos a sair: pessoas com vínculo na Servnet (contrato ou vínculo direto);
  -- quem tiver qualquer outro vínculo (outro negócio, técnico) fica — o banco barra o delete
  create temp table _pessoas on commit drop as
    select distinct pessoa_id as id from public.contratos where negocio_id = v_neg
    union
    select pessoa_id from public.pessoa_negocio_vinculos where negocio_id = v_neg;
  create temp table _auth (usuario_id uuid) on commit drop;
  select count(*) into v_ct from _contratos;
  select count(*) into v_la from _lanc;
  raise notice 'Servnet: % · contratos: % · lançamentos: %', v_neg, v_ct, v_la;

  -- imutabilidades e proteções saem do caminho só dentro desta transação
  foreach t in array tabelas loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;

  -- 1) dependências dos lançamentos e contratos
  delete from public.notificacoes_log where negocio_id = v_neg;
  delete from public.pix_cobrancas    where negocio_id = v_neg;
  delete from public.bloqueios        where negocio_id = v_neg;
  delete from public.aceites_contrato where contrato_id in (select id from _contratos);
  update public.indicacoes set desconto_id = null where negocio_id = v_neg;
  delete from public.descontos_contrato where contrato_id in (select id from _contratos);
  delete from public.indicacoes       where negocio_id = v_neg;
  delete from public.faturamentos     where contrato_id in (select id from _contratos);
  delete from public.faturamento_execucoes where organizacao_id = v_org;
  delete from public.fatura_itens     where lancamento_id in (select id from _lanc);
  update public.transacoes_carteira set contrato_id = null   where contrato_id in (select id from _contratos);
  update public.transacoes_carteira set lancamento_id = null where lancamento_id in (select id from _lanc);

  -- 2) ordens de serviço, comodatos e estoque (tudo teste)
  delete from public.comodato_historico where comodato_id in (select id from public.comodatos where negocio_id = v_neg);
  delete from public.estoque_instalacoes where negocio_id = v_neg;
  delete from public.comodatos where negocio_id = v_neg;
  delete from public.os_historico  where os_id in (select id from _os);
  delete from public.os_materiais  where os_id in (select id from _os);
  delete from public.os_fotos      where os_id in (select id from _os);
  delete from public.tecnico_movimentacoes where os_id in (select id from _os) or tecnico_id in (select id from public.tecnicos where negocio_id = v_neg);
  delete from public.ordens_servico where negocio_id = v_neg;
  delete from public.estoque_movimentacoes where negocio_id = v_neg;
  update public.estoque_itens set quantidade_atual = 0 where negocio_id = v_neg;
  update public.tecnico_estoque set quantidade = 0 where tecnico_id in (select id from public.tecnicos where negocio_id = v_neg);
  delete from public.reposicao_solicitacoes where tecnico_id in (select id from public.tecnicos where negocio_id = v_neg);

  -- 3) rede: portas voltam a livre, histórico de teste sai; OLT zera
  update public.cto_portas set pessoa_id = null, contrato_id = null, status = 'livre',
         data_ocupacao = null, cliente_latitude = null, cliente_longitude = null, rota_cliente = null
   where cto_id in (select id from public.ctos where negocio_id = v_neg)
     and (pessoa_id is not null or contrato_id is not null or status <> 'livre');
  delete from public.cto_historico where cto_id in (select id from public.ctos where negocio_id = v_neg);
  delete from public.olt_eventos where pop_id in (select id from public.ctos where negocio_id = v_neg);
  delete from public.olt_status  where pop_id in (select id from public.ctos where negocio_id = v_neg);

  -- 4) portal e disparos
  delete from public.portal_solicitacoes where negocio_id = v_neg;
  delete from public.disparo_itens where disparo_id in (select id from public.disparos where negocio_id = v_neg);
  delete from public.disparos where negocio_id = v_neg;
  delete from public.portal_login_tentativas;

  -- 5) lançamentos (cadeias) e contratos
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
  delete from public.contratos where id in (select id from _contratos);

  -- 6) clientes: sai quem só existia na Servnet; quem tem vínculo em outro
  --    lugar o banco segura (fica, sem o vínculo Servnet)
  delete from public.pessoa_negocio_vinculos where negocio_id = v_neg;
  for r in select id from _pessoas loop
    begin
      insert into _auth select usuario_id from public.portal_acessos where pessoa_id = r.id and usuario_id is not null;
      delete from public.portal_acessos where pessoa_id = r.id;
      delete from public.pessoas where id = r.id;
      v_pe := v_pe + 1;
    exception when foreign_key_violation then
      delete from _auth where usuario_id in (select usuario_id from public.portal_acessos where pessoa_id = r.id);
      -- pessoa tem vínculo fora da Servnet (técnico, outro negócio…): fica
    end;
  end loop;
  -- logins do portal dos clientes apagados
  delete from auth.users where id in (select usuario_id from _auth);

  foreach t in array tabelas loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;

  raise notice 'Concluído: % contratos, % lançamentos e % clientes apagados. Servnet zerada — pode lançar de verdade.', v_ct, v_la, v_pe;
end $$;

commit;

-- Conferência (tudo da Servnet deve ser 0; o resto fica):
with neg as (select id from public.negocios where lower(nome) like '%servnet%' or slug = 'servnet' limit 1)
select
  (select count(*) from public.contratos where negocio_id in (select id from neg)) as contratos,
  (select count(*) from public.lancamentos where negocio_id in (select id from neg)) as lancamentos,
  (select count(*) from public.ordens_servico where negocio_id in (select id from neg)) as ordens_servico,
  (select count(*) from public.comodatos where negocio_id in (select id from neg)) as comodatos,
  (select count(*) from public.estoque_movimentacoes where negocio_id in (select id from neg)) as mov_estoque,
  (select count(*) from public.pessoas) as pessoas_restantes,
  (select count(*) from public.planos) as planos_preservados,
  (select count(*) from public.ctos) as pontos_rede_preservados;
