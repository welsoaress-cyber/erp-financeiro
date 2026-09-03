#!/usr/bin/env bash
# Roda todas as migrations e testes em um Postgres local (porta/host via PG*).
# Uso: PGHOST=/tmp PGPORT=5433 PGUSER=postgres supabase/tests/rodar_local.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
MIG=(supabase/migrations/*.sql)
preparar() { # $1 = nome do banco, $2 = "com_ana" para inserir usuário antes da migration 0004
  psql -q -c "drop database if exists $1" -c "create database $1"
  for m in "${MIG[@]}"; do
    [[ "$m" == *agendado* ]] && continue
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
for t in categorias lancamentos negocios pessoas contratos faturamento importacao recorrencias; do printf "%-12s " "$t"; (psql -q -d erp_test_b -f "supabase/tests/${t}_test.sql" 2>&1 || true) | grep -E "ERROR|^OK" | head -1; done
printf "%-12s " "rls"; psql -At -d erp_test_b -f supabase/tests/verificar_rls.sql | awk -F'|' '{ok=ok&&($NF=="t")} BEGIN{ok=1} END{print (ok?"OK":"FALHOU")}'
