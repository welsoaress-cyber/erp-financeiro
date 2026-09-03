-- Verificação da migration 0010 (pg_cron). Esperado: 2 linhas (3 se a 0019 foi aplicada), todas ativas.
select jobname, schedule, active from cron.job where jobname in ('erp-faturamento-diario', 'erp-notificacoes-diario', 'erp-notificacoes-envio') order by 1;
