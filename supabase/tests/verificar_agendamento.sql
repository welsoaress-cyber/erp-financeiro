-- Verificação da migration 0010 (pg_cron). Esperado: 2 linhas (faturamento e notificações) ativas.
select jobname, schedule, command, active from cron.job where jobname in ('erp-faturamento-diario', 'erp-notificacoes-diario');
