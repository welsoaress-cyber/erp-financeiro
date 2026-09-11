# Etapa 37 — Excluir pessoa sem histórico + busca em Contratos

## O que entrega
- **Migration `20260902000064_excluir_pessoa.sql`**: função `excluir_pessoa(uuid)`
  (security definer, só membros da organização). Exclui a pessoa e, junto, os
  vínculos de cadastro: vínculo com negócio, acesso ao portal e o login do
  portal (`auth.users`). Qualquer histórico (contrato, lançamento, OS,
  comodato, técnico…) segura a exclusão pela chave estrangeira e a função
  devolve erro amigável — nesses casos o caminho continua sendo **desativar**.
  Sem grant de DELETE nas tabelas: a exclusão só passa pela função.
- **App**: botão **Excluir** (vermelho, com confirmação) no modal Editar
  pessoa; busca de Pessoas também acha por login do servidor.
- **Contratos**: campo de **busca** por nome do cliente, nº do contrato
  (#012), CPF/CNPJ, login do servidor ou telefone — combinado com os filtros
  de negócio e status.
- **UI geral** (entregue junto nesta leva): menu lateral reordenável por
  arraste e cartões do dashboard recolhíveis clicando na linha do título
  (escolhas salvas no navegador).

## Testes
- `supabase/tests/excluir_pessoa_test.sql`: exclui sem histórico (leva
  vínculo, portal e login junto), barra com contrato (check_violation),
  nega fora da organização (insufficient_privilege).
- `portal_test.sql` T2 deixou de depender do dia do mês (situação da fatura
  09/2026 calculada por `current_date`).
- `verificar_tudo.sql`: 52 verificações.

## Scripts de limpeza (SQL Editor, com backup antes)
- `supabase/scripts/limpar_movimento_contratos.sql`: zera só o movimento
  financeiro dos contratos da Servnet, mantendo contratos.
- `supabase/scripts/limpar_servnet_teste.sql`: recomeço total da Servnet
  (contratos, lançamentos, OS, comodatos, estoque movimentado, clientes sem
  outro vínculo), preservando cadastros estruturais e a rede física.
