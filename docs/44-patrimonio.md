# Etapa 41 — Patrimônio (bens individuais)

## Decisão de arquitetura
Em vez de um "tipo" dentro de `estoque_itens`, patrimônio ganhou **tabela
própria** (`patrimonios`): bem é individual (série, nº, local, estado) e não
combina com o modelo de saldo/custo médio do consumível. O estoque de
consumo continua intocado, e patrimônio **nunca entra em alerta de
reposição**.

## O que entrega (migration 0067)
- `patrimonios`: nº de patrimônio sequencial por organização (PAT-001…),
  nome, nº de série, valor de aquisição, data, nota fiscal, localização
  (POP, veículo, casa do técnico…), estado de conservação
  (novo/bom/regular/ruim) e situação (ativo/vendido/perdido/descartado).
- `patrimonio_historico` imutável (sem grant de update/delete): cadastro,
  transferência de local, mudança de estado e baixa entram sozinhos por
  trigger. Bem baixado vira somente leitura.
- RLS por organização, sem DELETE, nada para anon.

## Tela (Estoque → aba Patrimônio)
Inventário patrimonial por negócio: lista com nº, série, local, estado,
valor e situação; total do valor dos bens ativos; **Exportar CSV** (para
seguro/venda da operação); Novo bem; clique no bem para editar — mudar a
localização ou o estado gera histórico; mudar a situação para
vendido/perdido/descartado faz a **baixa definitiva** (com confirmação).

## Financeiro
A despesa da compra é lançada normalmente no Financeiro, em categoria de
natureza **"Investimento / ativo"** (etapa 39) — o bem guarda o valor de
aquisição para o inventário; o resultado operacional não é distorcido.

## Testes
`supabase/tests/patrimonio_test.sql` (numeração automática, históricos de
transferência/estado/baixa, bem baixado congelado, histórico imutável, RLS).
`verificar_tudo.sql`: 55.
