# 26 · Projeção de contratos nos meses futuros (Etapa 18)

Migration `20260902000031_projecao_contratos.sql`. Contratos com faturamento automático agora aparecem nos meses futuros da tela de Lançamentos — sem gravar nada.

## Por que projeção derivada (e não 60 lançamentos reais)
O motor de faturamento é mês a mês por desenho: fidelidade registra o prêmio na hora de faturar a competência (com base nos selos pagos), descontos de indicação são consumidos pela próxima competência pendente, encerramento/suspensão apenas param a geração futura e reajuste vale para competências ainda não faturadas. Pré-gerar 60 meses reais quebraria os quatro. A projeção resolve a visibilidade sem tocar no motor:

- `projecao_contratos(p_organizacao, p_de, p_ate)` — security definer, `exigir_membro`, grant só `authenticated`, teto de 60 meses à frente.
- Deriva de `competencias_pendentes` (mesma régua do faturamento): só contratos `ativo` + `faturamento_automatico` + valor > 0, só competências **estritamente futuras** (mês corrente e atrasados são do motor real), pulando o que já está em `faturamentos`.
- Sempre reflete o estado atual: reajuste de valor aparece na hora; suspender/encerrar some na hora. Periodicidade anual projeta só aniversários; `unico` não projeta.
- O lançamento real continua nascendo no mês certo (cron diário / trigger de criação), com desconto e fidelidade aplicados como sempre.

## Tela
- `/financeiro/lancamentos`: linhas "Contrato · projetado" (badge neutro, status Previsto) misturadas à lista do mês; sem clique/ações — a edição é no contrato. Filtros de tipo/status/negócio valem para elas.
- `useProjecaoContratos(mes)` tolera a migration ausente em produção (PGRST202 → lista vazia), então o deploy do app pode sair antes do SQL.

## Testes
`supabase/tests/projecao_contratos_test.sql` (T1 mês seguinte; T2 mês corrente fora; T3 60 meses + teto; T4 reajuste imediato; T5 suspender/reativar; T6 anual=5/único=0; T7 não-membro bloqueado). `verificar_tudo.sql` agora espera **24 de 24**. E2E: sem infraestrutura Playwright neste checkout (ver docs/25), pendência mantida.
