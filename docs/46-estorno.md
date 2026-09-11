# Etapa 43 — Estorno formal de lançamento efetivado

## Regra
Efetivado errado não se reescreve: o estorno cria um **contra-lançamento
datado de hoje** (mesmo tipo e categoria, valor **negativo**, origem
`estorno`, apontando o original em `estorno_de`). O caixa volta hoje, o
resultado do mês atual absorve a correção e o original fica intocado —
funciona inclusive com o mês do original **fechado**. Motivo é obrigatório.
Um efetivado só tem um estorno vivo; estorno não se estorna (cancela-se);
estorno cancelado libera estornar de novo. `gerar_movimentos` inverte o
caixa sozinho pelo sinal do valor (transferência inverte as duas pontas).

## Entrega (migration 0069)
`origem_lancamento` ganha `estorno`; `lancamentos.valor` passa a aceitar
negativo SÓ para origem estorno; coluna `estorno_de` + índice único parcial;
função `estornar_lancamento(id, motivo)` (definer, membros).

## Tela
Lançamento efetivado → botão **Estornar** (motivo obrigatório), ao lado de
Cancelar, com a explicação de quando usar cada um.

## Testes
`supabase/tests/estorno_test.sql`: estorno em mês fechado devolve o caixa e
preserva o original; duplo estorno/estorno de estorno/previsto barrados;
transferência inverte as duas contas; cancelar o estorno permite estornar
de novo. `verificar_tudo.sql`: 57.
