# Etapa 48 — Régua de cobrança configurável (padrão enxuto)

## O problema
A régua era fixa em 3 toques (1 aviso X dias antes, no dia, 1 aviso X dias
depois) e sem escolha de quais dias. O proprietário definiu: menos WhatsApp —
padrão **2 dias antes · no dia · 3 dias depois** — e liberdade para ajustar
por negócio.

## A solução
Em Notificações → Configurar, dois campos de lista:

- **Avisar antes (dias)** — ex.: `2` ou `5, 2` (até 5 pontos, 1–30; vazio =
  nenhum aviso antes).
- **Avisar depois (dias)** — ex.: `3` ou `1, 3` (até 5 pontos, 1–60). O maior
  valor segue sendo o prazo do **bloqueio assistido** (Cobrança).
- O aviso **no dia** sempre sai. Cada ponto dispara **no máximo uma mensagem
  por fatura** (dedução por lançamento + tipo + ponto).

## Banco (migration `20260902000073_regua_cobranca.sql`)
- `notificacoes_config.regua_antes smallint[]` (default `{2}`) e
  `regua_apos smallint[]` (default `{3}`); config existente migrada da régua
  antiga (1 ponto de cada lado).
- Trigger de proteção normaliza (ordena, tira repetição), valida (≤5 pontos,
  faixas) e **deriva** `dias_antes`/`dias_apos` do máximo de cada lista —
  `gerar_bloqueios` (0059/0072) e checks antigos seguem intactos.
- `notificacoes_log.dias smallint` = ponto da régua; índice único vira
  `(lancamento_id, tipo, coalesce(dias,-1))`.
- `gerar_notificacoes` recriada: um aviso por ponto que cair na data
  (lateral sobre as listas); templates continuam os 3 mesmos
  (próximo / no dia / bloqueio) com `{dias}` do ponto.

## App
`FormularioConfig`: campos "Avisar antes/depois (dias)" como listas;
`NotificacoesPage` mostra a régua completa no resumo.

## Testes
`supabase/tests/regua_test.sql` (padrão enxuto, normalização, validações,
um disparo por ponto, régua vazia antes) + `notificacoes_test.sql` ajustado
ao novo padrão; check 0073 no `verificar_tudo.sql` (total 61).
