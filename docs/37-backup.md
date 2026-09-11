# 37 · Backup automático semanal — Etapa 35 (`.github/workflows/backup-banco.yml`)

Dump completo do banco (schema + dados, esquemas internos do Supabase excluídos) toda **madrugada de domingo**, comprimido e guardado como **artifact privado do GitHub por 90 dias** — fora do Supabase, custo zero (repositório privado, dentro da franquia gratuita do Actions).

### Para ativar (proprietário)
1. Supabase → Database → Connect → **Session pooler** → copie a Connection string URI (troque `[YOUR-PASSWORD]` pela senha do banco; se esqueceu, Database → Settings → Reset database password).
2. GitHub → repositório → Settings → Secrets and variables → **Actions** → New repository secret → nome `SUPABASE_DB_URL`, valor = a URI.
3. GitHub → aba **Actions** → workflow `backup-banco` → **Run workflow** (teste manual). Ao terminar, o arquivo `erp-backup-AAAA-MM-DD.sql.gz` fica em "Artifacts" da execução.
4. A partir daí roda sozinho todo domingo. Baixar um backup: Actions → execução → Artifacts.

### Restaurar (se um dia precisar)
Num projeto Supabase novo: `gunzip erp-backup-….sql.gz` e aplicar pelo psql (`psql "URI-do-banco-novo" -f erp-backup-….sql`). Reportar antes de qualquer restauração em produção.

Sem migration nesta etapa (nada muda no banco).
