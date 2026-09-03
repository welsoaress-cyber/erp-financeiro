-- Verificação da migration 0010 (pg_cron). Esperado: 1 linha com o job ativo.
select jobname, schedule, command, active from cron.job where jobname = 'erp-faturamento-diario';
