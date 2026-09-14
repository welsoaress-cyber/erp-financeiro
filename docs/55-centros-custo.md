# 55 · Centros de custo — 54A (Etapa 54)

Migration `20260902000081_centros_custo.sql`. Teste `supabase/tests/centro_custo_test.sql`. Módulo `app/src/modules/centros_custo`.

## Decisão (análise aprovada pelo proprietário)
- Centro de custo é o eixo que faltava **dentro** do negócio: departamento, projeto, ponto de rede (POP/CEO/CTO). Não substitui o negócio (1º nível) nem os vínculos que já existem: custo por cliente/contrato = `pessoa_id`/`contrato_id` (rentabilidade, payback), custo por técnico = bolsa/comissões. Sem tipos "cliente/técnico/veículo" (duplicariam verdades).
- **Uma tabela** `centros_custo` (organização, negócio, nome único por negócio, descrição, tipo, `referencia_id` → `ctos` quando ponto de rede, ativo). Auditoria pelo trigger genérico; sem DELETE (inativar); sem hierarquia (coluna futura se precisar).
- `lancamentos.centro_custo_id` e `contratos.centro_custo_id` (fornecedor), opcionais, FK restrict; trigger valida mesmo negócio e centro ativo ao definir. Nulo = **Geral**.
- Motor: `definir_centro_custo_lancamento(id, centro)` (definer, `exigir_membro`, flag `erp.motor`) — o app chama após `criar/atualizar_lancamento`. `faturar_contrato` copia o centro do contrato para a despesa mensal (inclusive cortesia).
- Views: `vw_rel_lancamentos` ganha `centro_custo_id`/`centro_custo` ("Geral"); nova `vw_rel_gastos_centro_custo` (despesas por org × negócio × centro × mês × status × natureza).

## App
- Menu **Centros de custo** (após Negócios): lista por negócio com gasto do mês (realizado · previsto), linha "Geral" por negócio, mostrar inativos; modal novo/editar (negócio fixo depois de criado; tipo ponto de rede exige o ponto da Rede FTTH).
- Lançamento (só despesa, com negócio escolhido): campo **Centro de custo (opcional)**, lista do negócio.
- Contrato de fornecedor: campo Centro de custo — a despesa mensal nasce classificada.
- Relatórios: novo **Gastos por centro de custo** (operacional/investimento, previsto × realizado, agrupável por negócio/tipo); filtro *Centro de custo* (com "Geral") em Lançamentos e Contas a pagar; coluna nos dois.

## Fora desta etapa (54B, sob pedido)
Centro no detalhe do contrato existente; compra de estoque herdando centro; custo acumulado do ponto na tela FTTH; "centros sem movimento"; top 10 e evolução mensal; veículo (não há frota).

## 0082 · Custo por cliente (complemento)
Regra do proprietário: **comprou algo para um cliente específico → vincule ao contrato**; esse vínculo é o "centro de custo" do cliente e tudo decorre dele:
- `vw_payback_contrato` passa a somar as **despesas lançadas para o contrato** (não canceladas, previstas ou pagas — o custo existe desde a compra) além de instalação pelo Estoque e comissão de OS; coluna `despesas_contrato`. Detalhe do contrato: "Payback do cliente".
- `vw_rel_custo_cliente` + relatório **Custo por cliente (contrato)** na Central (área Clientes e contratos): recebido, instalação+comissão, despesas do contrato, custo total, resultado, payback estimado/real.
- Rentabilidade (`vw_resultado_por_contrato`) continua só com efetivados.
