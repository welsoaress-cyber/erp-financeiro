# 20 · Recorrência: despesa fixa × parcelamento (Etapa 12)

Migration `20260902000025_recorrencia_fixa_parcelada.sql`. Corrige a confusão entre "repete todo mês" e "dividido em N vezes".

## Conceitos
| Tipo | `recorrente` | `tipo_recorrencia` | `numero_parcelas` | Comportamento |
|---|---|---|---|---|
| Avulso | false | null | null | Acontece uma vez. |
| Fixa | true | `fixa` | null | Ao efetivar, gera o mês seguinte como previsto. Só para com cancelamento (ou exclusão) da parcela prevista. |
| Parcelada | true | `parcelada` | 2..360 | Ao efetivar, gera a próxima; para na parcela N. |

- `tipo_recorrencia` é derivado pelo trigger `tg_lancamentos_recorrencia` (fixa ⇔ sem número de parcelas). Por isso `criar_lancamento`/`atualizar_lancamento` mantêm os 17 parâmetros: fixa = `p_recorrente = true, p_periodicidade = 'mensal', p_numero_parcelas = null, p_data_fim_recorrencia = null`.
- Dados existentes migrados: recorrentes com parcelas → `parcelada`; sem parcelas → `fixa` (data de término, se havia, continua valendo).
- Edição com parcelas já geradas: **descrição, valor e observação** podem mudar (antes valor era travado). Conta, categoria, datas, negócio, pessoa, contrato e a recorrência em si continuam imutáveis.
- `periodicidade` e `data_fim_recorrencia` seguem no banco (compatibilidade e flexibilidade); a tela usa mensal e sem fim.

## Tela
- Checkbox "Lançamento recorrente" → escolha "Despesa fixa (gera todo mês até cancelar)" ou "Parcelamento (N parcelas)"; parcelamento pede número de parcelas e início (1ª parcela).
- Lista: 🔄 Fixo / 🔄 Parcela X de Y; avulso sem indicador.

## Testes
`supabase/tests/recorrencia_fixa_test.sql`; `recorrencias_test.sql` ajustado (valor editável; fixa sem término válida); e2e `recorrencias.spec.mjs`.
