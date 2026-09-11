-- =============================================================================
-- ZERAR OS NEGÓCIOS (reset para refazer os tipos de negócio do zero)
-- (rodar no SQL Editor como proprietário).
--
-- ⚠️ ANTES DE RODAR: gere um backup (GitHub → Actions → backup-banco).
--    Não há como desfazer. Pré-requisito: lançamentos já zerados
--    (supabase/scripts/zerar_lancamentos_categorias.sql) — o script confere.
--
-- APAGA: TODOS os negócios e tudo que pende deles — contratos, planos,
--   contas de negócio, estoque completo (categorias, itens, movimentações,
--   instalações, bolsas), rede FTTH (POPs/CEOs/CTOs, portas, histórico, OLT),
--   técnicos (e os logins deles), ordens de serviço, comodatos, indicações,
--   bloqueios, aceites, disparos, apps/carteira e configurações de portal e
--   notificações.
-- PRESERVA: pessoas (clientes/fornecedores), acessos ao portal, contas
--   PESSOAIS (sem negócio), categorias e modelos de disparo.
-- Tudo ou nada (uma transação).
-- =============================================================================
begin;

do $$
declare t text; v_auth uuid[]; n int;
  tabelas constant text[] := array[
    'negocios','contratos','planos','contas','pessoa_negocio_vinculos',
    'estoque_categorias','estoque_itens','estoque_movimentacoes','estoque_instalacoes',
    'tecnicos','tecnico_estoque','tecnico_movimentacoes','reposicao_solicitacoes',
    'ordens_servico','os_historico','os_materiais','os_fotos',
    'comodatos','comodato_historico','ctos','cto_portas','cto_historico',
    'indicacoes','descontos_contrato','bloqueios','aceites_contrato',
    'notificacoes_config','notificacoes_log','pix_cobrancas',
    'portal_config','portal_solicitacoes','portal_status_rede','promocoes',
    'disparos','disparo_itens','apps_catalogo','carteira','transacoes_carteira',
    'faturamentos','faturas','fatura_itens'
  ];
begin
  select count(*) into n from public.lancamentos;
  if n > 0 then
    raise exception 'Ainda existem % lançamentos — rode antes o zerar_lancamentos_categorias.sql.', n;
  end if;

  perform set_config('erp.motor', 'on', true);
  foreach t in array tabelas loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;

  -- logins dos técnicos (auth) saem junto com os técnicos
  select coalesce(array_agg(usuario_id), '{}') into v_auth from public.tecnicos where usuario_id is not null;

  -- filhos → pais
  delete from public.olt_eventos;
  delete from public.olt_status;
  delete from public.cto_historico;
  delete from public.cto_portas;
  delete from public.comodato_historico;
  delete from public.comodatos;
  delete from public.estoque_instalacoes;
  delete from public.os_historico;
  delete from public.os_materiais;
  delete from public.os_fotos;
  delete from public.ordens_servico;
  delete from public.tecnico_movimentacoes;
  delete from public.tecnico_estoque;
  delete from public.reposicao_solicitacoes;
  delete from public.estoque_movimentacoes;
  delete from public.estoque_itens;
  delete from public.estoque_categorias;
  delete from public.tecnicos;
  delete from public.ctos;
  delete from public.disparo_itens;
  delete from public.disparos;
  delete from public.notificacoes_log;
  delete from public.notificacoes_config;
  delete from public.pix_cobrancas;
  delete from public.bloqueios;
  delete from public.aceites_contrato;
  update public.indicacoes set desconto_id = null where desconto_id is not null;
  delete from public.descontos_contrato;
  delete from public.indicacoes;
  delete from public.portal_solicitacoes;
  delete from public.portal_status_rede;
  delete from public.portal_config;
  delete from public.promocoes;
  delete from public.transacoes_carteira;
  delete from public.carteira;
  delete from public.apps_catalogo;
  delete from public.fatura_itens;
  delete from public.faturas;
  delete from public.faturamentos;
  delete from public.faturamento_execucoes where true;
  delete from public.contratos;
  delete from public.planos;
  delete from public.pessoa_negocio_vinculos;
  delete from public.contas where negocio_id is not null; -- contas pessoais ficam
  delete from public.negocios;

  delete from auth.users where id = any(v_auth);

  foreach t in array tabelas loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;
  raise notice 'Concluído: negócios zerados. Cadastre os negócios novos, depois planos, contas e o resto.';
end $$;

commit;

-- Conferência
select
  (select count(*) from public.negocios)  as negocios,
  (select count(*) from public.contratos) as contratos,
  (select count(*) from public.planos)    as planos,
  (select count(*) from public.ctos)      as pontos_rede,
  (select count(*) from public.estoque_itens) as itens_estoque,
  (select count(*) from public.contas)    as contas_pessoais_preservadas,
  (select count(*) from public.pessoas)   as pessoas_preservadas;
