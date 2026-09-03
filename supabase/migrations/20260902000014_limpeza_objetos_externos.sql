-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0014: LIMPEZA DE OBJETOS EXTERNOS (correção de produção)
-- Em 03/09/2026 outra ferramenta criou objetos no banco de produção fora das
-- migrations (tabelas carteira/apps_catalogo/transacoes_carteira com estrutura
-- errada, colunas tipo_saldo/taxa_conversao em texto com padrão, funções
-- recarregar_saldo/ativar_app com assinaturas estranhas, trigger_auditoria,
-- atualizar_updated_at_carteira, vw_dashboard_apps) e deixou versões antigas
-- de criar/atualizar_lancamento (12 parâmetros). Esta migration remove tudo
-- isso com guardas: é segura em qualquer estado e não faz nada onde não há
-- resíduo. Não toca em dados de tabelas do repositório.
-- Ordem em produção: 0014 → diagnóstico → (0015 se necessário) → 0013.
-- =============================================================================
do $$
declare v_col record;
begin
  -- 1. Funções/views estranhas (assinaturas que o app não usa) e qualquer resto parcial da 0013
  drop function if exists public.recarregar_saldo(uuid, numeric, text);
  drop function if exists public.ativar_app(uuid, uuid, uuid, numeric, integer, date, text);
  drop view if exists public.vw_dashboard_apps;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'carteira' and column_name = 'organizacao_id') then
    -- a 0013 correta não está aplicada: remove qualquer pedaço dela que tenha sobrado
    drop view if exists public.vw_carteira_resumo;
    drop view if exists public.vw_contratos_app;
    drop function if exists public.ativar_app(uuid, uuid, uuid, date, numeric, integer, text);
    drop function if exists public.recarregar_carteira(uuid, numeric, uuid, date, text);
    drop function if exists public.criar_app(uuid, text, numeric, numeric);
    drop function if exists public.configurar_carteira(uuid, uuid, uuid);
    drop function if exists public.tg_carteira_protecao() cascade;
    drop function if exists public.tg_apps_catalogo_protecao() cascade;
    drop function if exists public.tg_apps_catalogo_sync() cascade;
    drop function if exists public.tg_transacoes_carteira_protecao() cascade;
    drop function if exists public.tg_transacoes_carteira_saldo() cascade;
  end if;

  -- 2. Tabelas da carteira criadas fora do repositório (sem organizacao_id = não são as da 0013)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'transacoes_carteira')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'transacoes_carteira' and column_name = 'organizacao_id') then
    drop table public.transacoes_carteira cascade;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'apps_catalogo')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'apps_catalogo' and column_name = 'organizacao_id') then
    drop table public.apps_catalogo cascade;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'carteira')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'carteira' and column_name = 'organizacao_id') then
    drop table public.carteira cascade;
  end if;
  drop function if exists public.atualizar_updated_at_carteira();
  -- tipos da 0013 que possam ter ficado de uma execução parcial (só se nenhuma coluna os usa)
  if exists (select 1 from pg_type where typname = 'tipo_saldo_app' and typnamespace = 'public'::regnamespace)
     and not exists (select 1 from pg_attribute a join pg_type t on t.oid = a.atttypid where t.typname = 'tipo_saldo_app' and a.attnum > 0 and not a.attisdropped) then
    drop type public.tipo_saldo_app;
  end if;
  if exists (select 1 from pg_type where typname = 'tipo_transacao_carteira' and typnamespace = 'public'::regnamespace)
     and not exists (select 1 from pg_attribute a join pg_type t on t.oid = a.atttypid where t.typname = 'tipo_transacao_carteira' and a.attnum > 0 and not a.attisdropped) then
    drop type public.tipo_transacao_carteira;
  end if;

  -- 3. Colunas em negocios criadas como texto com padrão (a 0013 cria com enum e sem padrão)
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'tipo_saldo' and data_type = 'text') then
    alter table public.negocios drop column tipo_saldo;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'taxa_conversao')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'negocios' and column_name = 'tipo_saldo') then
    alter table public.negocios drop column taxa_conversao;
  end if;

  -- 4. Versões antigas do motor (12 e 13 parâmetros) — o app usa as de 17 (migration 0012)
  drop function if exists public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid);
  drop function if exists public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid);
  drop function if exists public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid);
  drop function if exists public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text, uuid, uuid, uuid);
  drop function if exists public.criar_lancamento(text, text, numeric, date, date, date, uuid, uuid, uuid, text);
  drop function if exists public.atualizar_lancamento(uuid, text, numeric, date, date, date, uuid, uuid, uuid, text);

  -- 5. Função de auditoria estranha: só se nenhum trigger ainda a usa
  if exists (select 1 from pg_proc where proname = 'trigger_auditoria' and pronamespace = 'public'::regnamespace)
     and not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid where p.proname = 'trigger_auditoria') then
    drop function public.trigger_auditoria();
  end if;

  -- 6. Contratos: nomes de coluna que a outra ferramenta usou no lugar dos do repositório
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'valor_negociado')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'valor') then
    alter table public.contratos rename column valor_negociado to valor;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'faturamento_inicio')
     and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'faturar_desde') then
    alter table public.contratos rename column faturamento_inicio to faturar_desde;
  end if;
end $$;
