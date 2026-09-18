# Etapa 58A: Pontos por pontualidade (motor + extrato)

## Motivo

Incentivar o cliente a pagar cedo, não só em dia: quanto antes a fatura é paga, mais pontos ele ganha. Depois (58B) ele troca por prêmio numa vitrine — aqui só o motor que concede os pontos e o extrato pra conferir, sem prêmio ainda.

## Regra (fechada com o proprietário)

```
pontos = min(30, dias_de_antecedência + 1)
```

- Pagar **no vencimento** já vale **1 ponto** (nunca é punido por pagar em dia).
- Pagar **depois** do vencimento = **0 pontos**. Isso já cobre sozinho o caso de promessa/voto de confiança — ela só existe pra fatura já vencida, então nunca dá ponto.
- Só conta **quitação total** de contrato de **receita principal** — baixa parcial nunca gera pontos (ela não passa pela função que concede pontos); contrato adicional/SVA fica de fora por padrão (`contratos.elegivel_pontos = false`, quem decide é o proprietário por contrato).
- **Opt-in por negócio** (`notificacoes_config.pontos_ativo`, desligado por padrão — mesmo padrão do bloqueio automático).
- Vale **a partir de 01/10/2026**, sem retroativo.
- **Ciclo 01/10 a 30/09.** Contrato encerrado no meio do ciclo perde o saldo daquele negócio.
- **Estorno** de um pagamento remove os pontos daquela fatura.
- Pessoa excluída (sem histórico) com saldo não resgatado: a exclusão é permitida, mas fica um registro de alerta em `pontos_perdidos_exclusao` (base pra relatório futuro).

## Vencimento original + auditoria de reagendamento

O cálculo usa sempre `lancamentos.data_vencimento_original` — a data como a fatura nasceu, fixada na criação e que nunca muda depois. Reagendar o vencimento da fatura do mês **não** deixa o cliente "fingir" antecedência: o reagendamento só vale pra fatura do **mês seguinte** (linha nova, com seu próprio vencimento original).

Toda alteração de `data_vencimento` fica auditada em `lancamentos_vencimento_historico` (quem, quando, de/pra qual data) — útil como controle geral, não só pros pontos.

## O que foi feito

- `lancamentos.data_vencimento_original` (fixo) + `lancamentos_vencimento_historico` (auditoria).
- `contratos.elegivel_pontos` (default `true`; desligar em contrato adicional/SVA).
- `notificacoes_config.pontos_ativo` (opt-in por negócio).
- `pontos_pontualidade`: um registro imutável por fatura paga adiantada.
- `vw_saldo_pontos`: saldo por pessoa/negócio/ciclo (soma pura — sem resgate ainda).
- `pontos_perdidos_exclusao`: alerta de saldo perdido quando a pessoa é excluída.
- Motor: `efetivar_lancamento` concede os pontos; `estornar_lancamento` remove os da fatura estornada; `excluir_pessoa` registra o alerta antes de liberar a exclusão; gatilho em `contratos` zera o saldo do negócio quando o contrato encerra.
- Relatório **"Pontos de pontualidade"** na Central de Relatórios (extrato fatura a fatura).
- Checkbox "Pontos por pontualidade" em Notificações → configuração do negócio.

## Pendente (58B, depois)

Vitrine de prêmios por negócio (níveis livres, brinde físico integrado ao estoque ou desconto % na próxima fatura), resgate com débito de pontos, exibição de saldo/extrato no portal ("Meus pontos") e relatório de ROI da campanha.

## Deploy (proprietário)

Aplicar a migration `20260902000100_pontos_pontualidade.sql` pelo SQL Editor. Depois, em Notificações, ligar "Pontos por pontualidade" no(s) negócio(s) desejado(s).
