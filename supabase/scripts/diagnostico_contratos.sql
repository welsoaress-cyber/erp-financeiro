-- Diagnóstico curto (somente leitura): contratos/planos/lancamentos/negocios batem com o repositório?
with esperado(tabela, coluna) as (values
  ('planos','id'),('planos','organizacao_id'),('planos','negocio_id'),('planos','nome'),('planos','descricao'),('planos','valor_tabela'),('planos','periodicidade'),('planos','ativo'),('planos','criado_em'),('planos','atualizado_em'),
  ('contratos','id'),('contratos','organizacao_id'),('contratos','negocio_id'),('contratos','pessoa_id'),('contratos','plano_id'),('contratos','codigo'),('contratos','valor'),('contratos','periodicidade'),('contratos','data_inicio'),('contratos','data_fim'),('contratos','dia_vencimento'),('contratos','status'),('contratos','observacao'),('contratos','criado_em'),('contratos','atualizado_em'),('contratos','faturamento_automatico'),('contratos','faturar_desde'),('contratos','conta_id'),
  ('lancamentos','negocio_id'),('lancamentos','pessoa_id'),('lancamentos','contrato_id'),('lancamentos','recorrente'),('lancamentos','lancamento_origem_id'),
  ('negocios','conta_padrao_id'),('negocios','categoria_receita_id'),
  ('faturamentos','competencia'),('faturamento_execucoes','gerados')
), real as (
  select table_name as tabela, column_name as coluna, data_type from information_schema.columns where table_schema = 'public' and table_name in ('planos','contratos','lancamentos','negocios','faturamentos','faturamento_execucoes')
)
select 'FALTA' as situacao, e.tabela, e.coluna, null::text as tipo from esperado e left join real r using (tabela, coluna) where r.coluna is null
union all
select 'SOBRA', r.tabela, r.coluna, r.data_type from real r left join esperado e using (tabela, coluna) where e.coluna is null and r.tabela in ('planos','contratos')
union all
select 'LINHAS', 'contratos', count(*)::text, null from public.contratos
union all
select 'LINHAS', 'planos', count(*)::text, null from public.planos
union all
select 'FUNCAO', p.proname, pg_get_function_identity_arguments(p.oid), null from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('criar_lancamento','atualizar_lancamento','faturar_contrato','gerar_faturamento_agora','importar_clientes','gerar_proxima_parcela','recarregar_saldo','ativar_app','trigger_auditoria','tg_auditoria')
union all
select 'TRIGGER', t.tgrelid::regclass::text, t.tgname, t.tgfoid::regproc::text from pg_trigger t where not t.tgisinternal and t.tgrelid in ('public.contratos'::regclass, 'public.planos'::regclass, 'public.lancamentos'::regclass, 'public.negocios'::regclass)
order by 1, 2, 3;
