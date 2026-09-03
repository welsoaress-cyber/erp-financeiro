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

## Diagnóstico confirmado (03/09/2026, após a 0014)
- `planos`, `contratos`, `faturamentos` e `faturamento_execucoes` em produção foram criadas fora do repositório: colunas `created_at`/`updated_at`, sem `organizacao_id`, `conta_padrao_id`/`categoria_padrao_id` em contratos, nenhum trigger, nenhuma função de faturamento. Todas vazias.
- `negocios` sem `categoria_receita_id`; `lancamentos.contrato_id` sem o trigger de herança de contrato. Conclusão: **as migrations 0008, 0009 (e provavelmente 0010) nunca foram aplicadas**; as validações das Etapas 6C e 7 "em produção" aconteceram sobre esse esquema externo.
- 0011 e 0012 estão aplicadas corretamente (funções presentes, motor com 17 parâmetros).

## Correção final
- `20260902000015_refundacao_contratos.sql`: aborta se `contratos` já tiver `organizacao_id` ou se houver dados; remove o esquema externo (tabelas, funções, views, tipos, `trigger_auditoria`), descarta `lancamentos.contrato_id` e `negocios.conta_padrao_id`/`categoria_receita_id` (recriadas em seguida) e recria o conteúdo das 0008 e 0009 sem o motor (já na versão da 0012). Reaplicar é inofensivo: aborta sem alterar nada.
- Runner local ganhou o **cenário C**: 0001–0007 + `tests/simulacao_estado_externo.sql` (réplica do esquema encontrado) + 0011 + 0012, corrigido por 0014 → 0015 → 0013. Resultado: `verificar_tudo` 14 de 14 e todas as suítes OK.
- Ordem em produção: 0014 (feita) → **0015 → 0013 → 0010 → verificar_tudo**. Depois, em Negócios, definir de novo a conta de recebimento e a categoria de receita padrão de cada negócio (as colunas foram recriadas vazias).

## Encerramento (03/09/2026)
Produção após 0014 → 0015 → 0013 → 0010: `verificar_tudo.sql` **14 de 14**. Job `erp-faturamento-diario` agendado (executado duas vezes; o script desagenda antes de agendar, restando um job). Pendências: reconfigurar conta/categoria padrão dos negócios na tela e revalidar Etapas 6C, 7, 6D, 8 e 9 sobre o esquema correto.
