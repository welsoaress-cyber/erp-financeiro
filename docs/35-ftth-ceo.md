# 35 · FTTH: CEO e encadeamento — Etapa 33 (migration `20260902000061_ftth_ceo.sql`)

Expansão mínima da hierarquia da rede, sem tabelas novas (análise aprovada pelo proprietário):

- **CEO** (caixa de emenda óptica) é um novo tipo de ponto na tabela `ctos`, com splitter primário opcional (campo `splitter` existente). Botão "Nova CEO" no mapa; marcador âmbar.
- **Encadeamento**: `pop_id` virou "**alimentado por**" — CTO aponta para POP **ou** CEO; CEO aponta para POP ou outra CEO (cascata, ciclo bloqueado até 10 níveis); POP é a raiz. O fio tracejado do mapa segue a cadeia.
- **OLT como cadastro** no POP: marca, modelo, IP e portas PON (colunas novas; monitoramento fica para a etapa própria).
- **Impacto de rompimento**: `ftth_abaixo_de(ponto)` devolve tudo que o ponto alimenta (recursivo) com nível e clientes conectados. No detalhe do POP/CEO aparece "Alimenta X pontos · Y clientes — um rompimento aqui derruba: …".

## Testes

`supabase/tests/ftth_ceo_test.sql`: cadeia POP→CEO→CEO→CTO, ciclo bloqueado, pai CTO bloqueado, impacto (3 pontos e 1 cliente abaixo do POP, níveis corretos). `verificar_tudo.sql`: **49 de 49**.
