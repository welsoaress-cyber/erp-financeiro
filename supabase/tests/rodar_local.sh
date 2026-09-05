#!/usr/bin/env bash
# Roda todas as migrations e testes em um Postgres local (porta/host via PG*).
# Uso: PGHOST=/tmp PGPORT=5433 PGUSER=postgres supabase/tests/rodar_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG=(supabase/migrations/*.sql)
preparar() { # $1 = nome do banco, $2 = "com_ana" para inserir usuário antes da migration 0004
  psql -q -c "drop database if exists $1" -c "create database $1"
  for m in "${MIG[@]}"; do
    [[ "$m" == *agendado* || "$m" == *0015_* ]] && continue
    if [[ "$2" == "com_ana" && "$m" == *0004_categorias* ]]; then
      psql -q -d "$1" -c "insert into auth.users (id, email, raw_user_meta_data) values ('11111111-1111-1111-1111-111111111111','ana@teste.dev','{\"nome\":\"Ana\"}')"
    fi
    [[ "$m" == *0001_fundacao* ]] && psql -q -d "$1" -v ON_ERROR_STOP=1 -f supabase/tests/00_shim_local.sql
    psql -q -d "$1" -v ON_ERROR_STOP=1 -f "$m"
  done
}
preparar erp_test_a sem_ana
for t in fundacao contas seguranca; do printf "%-12s " "$t"; (psql -q -d erp_test_a -f "supabase/tests/${t}_test.sql" 2>&1 || true) | grep -E "ERROR|^OK" | head -1; done
preparar erp_test_b com_ana
for t in categorias lancamentos negocios pessoas contratos faturamento importacao recorrencias apps_saldo notificacoes notificacoes_envio portal portal_servnet recorrencia_fixa financeiro contratos_despesa saldo_inicial projecao_edicao projecao_contratos recorrencia_data periodicidades reancoragem excluir_cadeia importacao_opcional cartoes; do printf "%-12s " "$t"; (psql -q -d erp_test_b -f "supabase/tests/${t}_test.sql" 2>&1 || true) | grep -E "ERROR|^OK" | head -1; done
printf "%-12s " "rls"; psql -At -d erp_test_b -f supabase/tests/verificar_rls.sql | awk -F'|' '{ok=ok&&($NF=="t")} BEGIN{ok=1} END{print (ok?"OK":"FALHOU")}'

# Cenário C: esquema de produção criado fora do repositório (0001–0007 + externo + 0011/0012), corrigido por 0014 → 0015 → 0013
psql -q -c "drop database if exists erp_test_c" -c "create database erp_test_c"
for m in "${MIG[@]}"; do
  case "$m" in *agendado*|*0008_*|*0009_*|*0013_*|*0014_*|*0015_*|*0016_*|*0018_*|*0021_*|*0023_*|*0024_*|*0025_*|*0026_*|*0027_*|*0028_*|*0029_*|*0030_*|*0031_*|*0032_*|*0033_*|*0034_*|*0035_*|*0036_*|*0037_*|*0038_*) continue;; esac
  [[ "$m" == *0004_categorias* ]] && psql -q -d erp_test_c -c "insert into auth.users (id, email, raw_user_meta_data) values ('11111111-1111-1111-1111-111111111111','ana@teste.dev','{\"nome\":\"Ana\"}')"
  [[ "$m" == *0001_fundacao* ]] && psql -q -d erp_test_c -v ON_ERROR_STOP=1 -f supabase/tests/00_shim_local.sql
  [[ "$m" == *0011_* ]] && psql -q -d erp_test_c -v ON_ERROR_STOP=1 -f supabase/tests/simulacao_estado_externo.sql
  psql -q -d erp_test_c -v ON_ERROR_STOP=1 -f "$m"
done
for m in 0014 0015 0013 0030 0016 0018 0021 0023 0024 0025 0026 0027 0028 0029 0031 0032 0033 0034 0035 0036 0037 0038; do psql -q -d erp_test_c -v ON_ERROR_STOP=1 -1 -f supabase/migrations/2026090200${m}_*.sql 2>&1 | { grep -vE "NOTICE|DETAIL|drop cascades" || true; }; done
printf "%-12s " "producao"; psql -At -d erp_test_c -f supabase/tests/verificar_tudo.sql | grep TOTAL | awk -F'|' '{print ($2=="t"?"OK":"FALHOU") " (" $3 ")"}'
for t in contratos faturamento importacao recorrencias apps_saldo notificacoes notificacoes_envio portal portal_servnet recorrencia_fixa financeiro contratos_despesa saldo_inicial projecao_edicao projecao_contratos recorrencia_data periodicidades reancoragem excluir_cadeia importacao_opcional cartoes; do printf "%-12s " "prod:$t"; (psql -q -d erp_test_c -f "supabase/tests/${t}_test.sql" 2>&1 || true) | grep -E "ERROR|^OK" | head -1; done
