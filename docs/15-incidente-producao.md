# Incidente 03/09/2026 — objetos criados fora das migrations (segunda ocorrência)

## O que aconteceu
Ao aplicar as migrations 0011–0013, outra ferramenta (DeepSeek) orientou a executar SQL avulso no banco de produção:
1. Recriou `criar_lancamento`/`atualizar_lancamento` com corpo errado (colunas `created_at`/`updated_at` inexistentes, sem o motor, sem verificação de membro). A 0012 as substituiu ao ser aplicada, mas as versões de 12 parâmetros continuaram no banco.
2. A 0013 falhou (`column c.valor does not exist` em `contratos`) e foi totalmente desfeita pelo SQL Editor. No lugar dela foram criadas tabelas `carteira`, `apps_catalogo`, `transacoes_carteira` com estrutura diferente (sem `organizacao_id`, sem `plano_id`, `tipo` em texto, `on delete cascade`), colunas `tipo_saldo` em texto com padrão `'dinheiro'` em **todos** os negócios, `taxa_conversao` com padrão, funções `recarregar_saldo` e `ativar_app` com assinaturas que o app não chama, `vw_dashboard_apps`, `atualizar_updated_at_carteira` e triggers para uma função `trigger_auditoria` que não existe no repositório.
3. O erro da 0013 revela que `contratos` em produção **não tem a coluna `valor`** do repositório. Ou seja, a migration 0008 não está aplicada como está no repositório.

Nada disso funciona com o app publicado, e o `ativar_app` externo falharia na primeira execução (insere em `planos` sem `organizacao_id` e usa `on conflict` em índice que não existe).

## Correção
- `supabase/migrations/20260902000014_limpeza_objetos_externos.sql`: remove com guardas tudo o que foi criado fora do repositório e as assinaturas antigas do motor; renomeia `valor_negociado → valor` e `faturamento_inicio → faturar_desde` se existirem. Idempotente: não faz nada onde não há resíduo. Testada localmente sobre uma simulação exata do estado deixado.
- `supabase/scripts/diagnostico_contratos.sql`: diagnóstico curto, somente leitura, que mostra o que falta/sobra em `contratos`/`planos` e as assinaturas do motor.
- `supabase/tests/verificar_tudo.sql`: 14 verificações consolidadas (0001–0014) para rodar em produção após a correção.
- Ordem em produção: **0014 → diagnóstico → 0013 → verificar_tudo**. Se o diagnóstico mostrar `FALTA` em `contratos`/`planos`, parar e enviar o resultado: a 0013 depende dessas colunas e será preciso uma migration 0015 específica.

## Regra reforçada
Nenhuma outra ferramenta cria, altera ou "ajusta" objetos no banco do ERP. Todo SQL executado em produção vem de um arquivo versionado neste repositório. Se uma migration falhar, o passo é enviar o erro aqui, não contornar.
