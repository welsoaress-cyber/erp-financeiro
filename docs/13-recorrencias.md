# Etapa 8 — Recorrências em lançamentos

Status: **implementada e testada localmente (03/09/2026); aguardando aplicação da migration 0012 em produção e validação do proprietário.**

## 1. Objetivo
Qualquer lançamento (receita, despesa ou transferência) pode ser **recorrente**: ao ser efetivado, o motor gera automaticamente a próxima parcela como **previsto**, copiando todos os dados. Independente do faturamento por contrato (Etapa 7), que continua gerando cobranças avulsas por competência.

## 2. Como funciona
```
Parcela 1 (previsto) ── efetivar ──► Parcela 2 (previsto, mesmos dados, próximo vencimento)
                                        └── efetivar ──► Parcela 3 … até o limite
Limite: número de parcelas OU data de término (vale o que ocorrer primeiro)
Parar antes: cancelar ou excluir uma parcela PREVISTA (nada mais é gerado)
Cancelar uma parcela EFETIVADA: só estorna aquela parcela; a próxima já gerada continua
```
- A próxima parcela é gerada **na efetivação** (`efetivar_lancamento`, ou `criar`/`atualizar_lancamento` quando o lançamento já nasce ou passa a efetivado). Nunca duas vezes: uma parcela gera no máximo uma próxima (índice único em `lancamento_origem_id`).
- **Vencimento** da próxima = vencimento da parcela atual + periodicidade, mantendo o **dia da primeira parcela** (31/01 → 28/02 → 31/03; não "escorrega" para o dia 28). Quinzenal = +15 dias. A data de efetivação não influencia.
- Competência acompanha o vencimento com a mesma distância da parcela atual.
- Cobrança gerada pelo faturamento de contrato (`origem = faturamento`) **não** pode ser recorrente: já é automática.

## 3. Banco (migration `20260902000012_recorrencias.sql`)
Colunas em `lancamentos`: `recorrente`, `periodicidade` (enum `periodicidade_recorrencia`: mensal, quinzenal, bimestral, trimestral, semestral, anual), `numero_parcelas` (2–360 ou nulo = indeterminado), `parcela_atual`, `data_fim_recorrencia`, `lancamento_origem_id` (parcela anterior; nulo = primeira).

Regras no banco (check + trigger `lancamentos_b_recorrencia`):
- Avulso ⇒ todas as colunas de recorrência nulas. Recorrente ⇒ periodicidade + (parcelas **ou** término) + parcela ≥ 1 e ≤ parcelas.
- Término ≥ vencimento. Parcela gerada tem número = anterior + 1 e mesma organização.
- **Com parcela gerada** (tem próxima, ou é a parcela 2+): periodicidade, parcelas, término e o próprio flag são imutáveis.
- **Com próxima parcela já gerada**: valor, datas, contas, categoria, negócio, pessoa e contrato são imutáveis; só descrição e observação mudam. A parcela seguinte (sem filha) pode ser ajustada e as próximas herdam o ajuste.
- Escrita continua **só pelo motor**: `gerar_proxima_parcela` é interna (sem execute para `authenticated`). `criar_lancamento` e `atualizar_lancamento` ganharam 4 parâmetros (`p_recorrente`, `p_periodicidade`, `p_numero_parcelas`, `p_data_fim_recorrencia`); as assinaturas de 13 parâmetros foram removidas.
- RLS e auditoria: mesma tabela, mesmas policies e trigger de auditoria; nada novo a proteger.

## 4. Interface
- **Formulário**: bloco "Lançamento recorrente" com periodicidade, número de parcelas (vazio = indeterminado) e data de término. Validação local espelha a do banco.
- **Edição**: parcela com próxima já gerada mostra aviso "Parcelas já geradas" e trava tudo exceto descrição e observação; parcela 2+ trava os campos de recorrência.
- **Lista**: distintivo 🔄 "Parcela X de Y" (ou "Parcela X" quando indeterminada).
- **Ações**: cancelar/excluir uma parcela prevista avisa que interrompe a recorrência; cancelar efetivada avisa que só estorna.

## 5. Testes
- `supabase/tests/recorrencias_test.sql`: próxima data (todas as periodicidades, fim de mês, dia 31), mensal 3 parcelas (gera 2 e 3, não gera 4), criado já efetivado gera na hora, data de término, cancelar previsto interrompe, cancelar efetivado não interrompe, edição bloqueada após parcelas geradas (descrição/observação liberadas), ajuste da parcela seguinte herdado, validações, avulso ignora dados de recorrência, transferência recorrente, exclusão de parcela prevista, função interna inacessível.
- `supabase/tests/verificar_recorrencias.sql`: 6 verificações somente leitura.
- e2e (Playwright + mock): fluxo completo de 3 parcelas, travas de edição, término, cancelamentos, indicador na lista.

## 6. Fora do escopo (de propósito)
- Gerar todas as parcelas de uma vez (a geração é uma a uma, na efetivação, como aprovado).
- "Cadeia" como entidade própria (tabela `recorrencias`): a rastreabilidade é por `lancamento_origem_id`.
- Recorrência em cobranças de contrato (já cobertas pelo faturamento automático).

## 7. Como aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000012_recorrencias.sql`.
2. `supabase/tests/verificar_recorrencias.sql` → esperado **6 de 6**.
3. Deploy do app (push em `main`). O app novo exige a migration aplicada (chama `criar_lancamento` com 17 parâmetros).
