# Etapa 58A: Pontos por pontualidade (motor + extrato)

## Motivo

Incentivar o cliente a pagar cedo, não só em dia: quanto antes a fatura é paga, mais pontos ele ganha. Depois (58B) ele troca por prêmio numa vitrine — aqui só o motor que concede os pontos e o extrato pra conferir, sem prêmio ainda.

## Regra (fechada com o proprietário — ajustada na 0101)

```
pontos = dias_de_antecedência + 1     -- sem teto
```

- Pagar **no vencimento** já vale **1 ponto** (nunca é punido por pagar em dia). 1 dia antes = 2, 10 dias antes = 11, 30 dias antes = 31, e por aí vai — **sem limite máximo**.
- Pagar **depois** do vencimento = **0 pontos**. Isso já cobre sozinho o caso de promessa/voto de confiança — ela só existe pra fatura já vencida, então nunca dá ponto.
- Só conta **quitação total** de contrato de **receita principal** — baixa parcial nunca gera pontos (ela não passa pela função que concede pontos); contrato adicional/SVA fica de fora por padrão (`contratos.elegivel_pontos = false`, quem decide é o proprietário por contrato).
- **Opt-in por negócio** (`notificacoes_config.pontos_ativo`, desligado por padrão — mesmo padrão do bloqueio automático).
- **Campanha com prazo fixo: 01/10/2026 a 30/09/2027** (12 meses). Fora dessa janela, nenhum ponto é gerado. Não é um ciclo que se renova sozinho — é uma decisão do proprietário: "um ano pra ver se funciona, se der certo, prorroga" (extensão = nova migration mudando a data final, quando ele pedir).
- Contrato encerrado no meio da campanha perde o saldo daquele negócio.
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

Vitrine de prêmios por negócio (brinde físico integrado ao estoque, com custo em pontos derivado do preço em R$ pela taxa de conversão — o desenho detalhado do proprietário usa R$ 0,22/ponto pra prêmio e R$ 0,25/ponto pra desconto em fatura, desconto mínimo R$ 1,00/4 pontos, máximo 100% da fatura, entrega do prêmio físico em até 15 dias úteis), resgate com débito de pontos, exibição de saldo/extrato no portal ("Meus pontos"), relatório de ROI da campanha e expiração do saldo não resgatado no fim da campanha (30/09/2027).

## Deploy (proprietário)

1. Migration `20260902000100_pontos_pontualidade.sql` (já aplicada).
2. Migration `20260902000101_pontos_sem_teto_campanha.sql` — remove o teto de 30 pontos e troca a vigência aberta pela janela fixa da campanha (01/10/2026 a 30/09/2027).

Depois, em Notificações, ligar "Pontos por pontualidade" no(s) negócio(s) desejado(s).
