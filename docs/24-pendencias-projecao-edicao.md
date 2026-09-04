# 24 · Pendências de meses anteriores, projeção e edição em lote (Etapa 16)

Migration `20260902000029_projecao_e_edicao_recorrente.sql`.

## 1. Lançamentos pendentes de meses anteriores
Nada muda no banco: um lançamento previsto nunca "some" — ele fica exatamente no mês em que foi lançado, com status `previsto`, até ser efetivado ou cancelado. O que faltava era mostrar isso independente do mês que você está navegando.

Contas a Receber e Contas a Pagar agora têm um alerta fixo no topo, **"Pendências de meses anteriores"**, com tudo que está `previsto` e venceu antes do mês atual (não do mês que você está olhando na tela) — com "vencido há X dias" e um botão de pagar/receber direto ali. Some sozinho quando é quitado.

**Sobre o saldo inicial do mês**: ele continua sendo só o dinheiro que já entrou/saiu de verdade (Etapa 15) — uma pendência não paga não é dinheiro que saiu da conta, então não é somada ao saldo. Ela fica visível separadamente, sem distorcer o saldo real.

## 2. Projeção para os próximos meses
Nova ação **"Projetar meses futuros"** em qualquer lançamento recorrente (fixo ou parcelado): gera as próximas N ocorrências (você escolhe o horizonte, até 60 meses) já como previstas, sem precisar pagar a atual primeiro. Para automaticamente no fim do parcelamento ou na data-limite, se houver.

No banco: `gerar_proxima_parcela_projetada` (motor interno, cópia de `gerar_proxima_parcela` sem exigir que a atual esteja efetivada) + `projetar_lancamento(p_id, p_meses)` (RPC pública). O fluxo de pagar → gera o próximo automaticamente (já existente) continua igual e não duplica: cada nó da cadeia só gera um filho, não importa quem chamou.

## 3. Exclusão de lançamentos
Já existia — `excluir_lancamento` (migration 0005) apaga de verdade, mas só quando o status é `previsto` (efetivado ou com movimento vinculado, só cancelamento). Botão "Excluir" na tela de edição do lançamento.

## 4. Edição em lote de recorrentes
Editar um lançamento recorrente que já gerou a próxima parcela agora pergunta o alcance:
- **Apenas esta parcela** (como já era)
- **Esta e as futuras** — muda esta e as seguintes já geradas na cadeia; as anteriores (inclusive já pagas) não mudam
- **Todas as parcelas, inclusive já pagas** — reescreve a cadeia inteira; lançamentos já efetivados têm o movimento recalculado, então o saldo continua batendo

Só descrição, valor e observação (os únicos campos editáveis numa recorrência com parcela gerada). RPC `atualizar_lancamento_recorrente(p_id, p_descricao, p_valor, p_observacao, p_escopo)`.

## Testes
`supabase/tests/projecao_edicao_test.sql`; e2e `projecao.spec.mjs` (pendência aparece e some, projeção sem pagar, edição em lote "futuras").

## Adendo (migration 0032): data editável na edição em lote
Com a projeção automática (60 meses ao criar), toda recorrência nasce com parcelas geradas — a regra antiga travava a data na hora. Agora `atualizar_lancamento_recorrente` ganhou `p_data_vencimento` (6º parâmetro, default null):
- **apenas esta**: muda a data desta parcela (só previsto), preservando o intervalo vencimento−competência.
- **esta e as futuras**: esta recebe a nova data e as seguintes previstas deslocam mês a mês no novo dia âncora; parcelas pagas não movem, mas a régua avança por cima delas.
- **todas**: data recusada (reescrever data de parcela paga não faz sentido).
O trigger `tg_lancamentos_recorrencia` continua bloqueando data fora do motor; a flag de sessão `erp.editar_data` (ligada só dentro da função) libera exclusivamente as duas datas. Testes: `recorrencia_data_test.sql`. `verificar_tudo.sql`: 25 de 25.
