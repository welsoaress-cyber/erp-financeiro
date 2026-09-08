# 21 · Módulo Financeiro (Etapa 13)

Menu "Financeiro" com três submódulos que compartilham o mês selecionado:
- **Lançamentos** (`/financeiro/lancamentos`, o antigo `/lancamentos` redireciona)
- **Contas a receber** (`/financeiro/receber`): lançamentos de receita do mês (faturas de contrato e receitas manuais)
- **Contas a pagar** (`/financeiro/pagar`): lançamentos de despesa do mês (fornecedor = pessoa do lançamento)

## Navegação por mês
`core/periodo/usePeriodo.ts` guarda o mês (sessionStorage da aba). O `SeletorMes` tem setas e o botão em destaque "Voltar ao mês atual" quando o mês não é o corrente. Trocar o mês em um submódulo vale para todos.

## Previsto × Realizado (por mês, pela data de competência)
| Campo | Cálculo |
|---|---|
| Previsto | soma dos lançamentos com status `previsto` |
| Realizado | soma dos lançamentos `efetivado` |
| Saldo | Realizado − Previsto (≥ 0 superávit, < 0 déficit) |
| Vencidos | previstos com vencimento antes de hoje |
Cancelados ficam fora. Filtros: cliente/fornecedor (pessoa) e situação (em aberto, vencido, pago/recebido).

## Ações
- Receber/Pagar → `efetivar_lancamento`.
- **Baixa parcial** → `baixar_parcial(id, valor, data)` (migration `20260902000026_baixa_parcial.sql`): o lançamento original fica efetivado com o valor pago; o restante vira um novo lançamento previsto (mesmos dados, sem recorrência, observação "Saldo restante após baixa parcial…"). Em lançamento recorrente a próxima parcela nasce com o valor cheio. Não vale para transferência.
- Cancelar → `cancelar_lancamento`.

## UI
- `Modal` agora tem `largura` (`lg` padrão ≈ 830px, `xl` ≈ 1100px, `md` para confirmações).
- Tabelas com `whitespace-nowrap` nas colunas de data, valor, tipo e situação; rolagem só horizontal dentro do cartão.
- Sidebar mostra os submódulos quando o módulo está ativo.

## Decisão pendente: previsão orçamentária
Escolha: **depois**. Metas por mês são um módulo à parte (tabela `orcamentos` por categoria/negócio + comparação). Entra quando previsto × realizado estiver validado em produção.

## Testes
`supabase/tests/financeiro_test.sql` (baixa parcial simples, dupla, em despesa fixa, inválidos); e2e `financeiro.spec.mjs` (menu, redirecionamento, previsto/realizado/saldo, baixa parcial, mês compartilhado, pop-up ≥ 800px).

## Encargos ao pagar com atraso (migration 0040)
Na baixa de um lançamento vencido (Contas a pagar/receber), o modal "Marcar como pago/recebido" mostra o campo opcional **Encargos por atraso (R$)** quando a data da baixa é posterior ao vencimento. O valor é somado só nesta parcela (`efetivar_lancamento(p_id, p_data_efetivacao, p_encargos)`), registrado na observação ("Encargos por atraso: R$ …") e refletido nos movimentos; as parcelas futuras da recorrência mantêm o valor normal. Encargos negativos são recusados. Testes: `supabase/tests/encargos_test.sql`.

## Baixa com valor pago e conta escolhida (migration 0041)
No modal de baixa em atraso o campo é **Valor pago com encargos (R$)**: os encargos são a diferença sobre o valor do lançamento (mostrada na hora); valor menor manda para "Baixa parcial". Também dá para escolher a **conta do pagamento/recebimento** (exceto transferências e cartões): `efetivar_lancamento(p_id, p_data_efetivacao, p_encargos, p_conta_id)` troca a conta só desta parcela sob a flag `erp.trocar_conta`; a próxima parcela mantém a conta original.
