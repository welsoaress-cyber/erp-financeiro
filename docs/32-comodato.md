# 32 · Comodato — Etapa 30 (migration `20260902000058_comodato.sql`)

Equipamentos da empresa na casa do cliente (ONU, roteador), com número de série. Responde "onde está cada ONU".

## Regras (decisões do proprietário)

- **Instalação**: no encerramento da OS, o técnico (ou admin) informa o equipamento e a **série**. Sai 1 unidade da bolsa do técnico (custo médio), entra no custo do chamado (e no payback, em instalação/mudança) e nasce o registro de comodato vinculado a cliente, contrato e OS.
- **Série única**: uma série só pode estar `instalado` em um cliente por vez (única por organização, maiúscula, sem espaços nas pontas).
- **Contrato encerrado** com equipamento instalado → **OS de recolhimento automática** (novo tipo `recolhimento`), uma por contrato, com as séries na descrição. Encerrar essa OS recolhe os equipamentos e devolve ao estoque central pelo custo médio.
- **Recolhimento manual** (admin, aba Comodato): volta ao central ou **descarte** (danificado — motivo obrigatório, não volta; fica o histórico).
- **Troca** (equipamento queimou): o antigo vira `trocado` — com **defeito de fábrica** não volta ao estoque; sem defeito, volta ao central. O novo sai da **bolsa do técnico** e assume o lugar (mesmo cliente/contrato). Motivo obrigatório.
- **Perda** (cliente sumiu com o equipamento): justificativa obrigatória, status `perdido`. Sem cobrança automática.
- **Registro manual**: equipamento que já estava no cliente antes do sistema — não mexe no estoque.
- Tudo imutável no histórico (`comodato_historico`), escrita só pelo motor, auditoria ligada, RLS por organização (técnico não lê comodatos nesta etapa).

## App

- **Estoque → aba Comodato**: lista com busca por série/cliente e filtro por status; ações Trocar / Recolher (com descarte) / Perda; botão "Registrar equipamento antigo".
- **Encerramento de OS** (admin e técnico): seção "Equipamentos em comodato" com item + série (além dos materiais por quantidade).
- **Contratos → detalhe**: bloco "Equipamentos em comodato" do contrato.

## Testes

`supabase/tests/comodato_test.sql`: instalação via OS (bolsa −1, custo no chamado e no payback, série normalizada), série duplicada bloqueada, escrita direta bloqueada, troca com defeito (antigo não volta, novo da bolsa), registro manual sem estoque, contrato encerrado gera OS de recolhimento única e o encerramento dela devolve ao central, perda e descarte com justificativa. `verificar_tudo.sql`: **46 de 46**.
