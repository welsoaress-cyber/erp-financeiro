# 54 · Central de Relatórios — 53A (Etapa 53)

Migration `20260902000079_relatorios.sql`. Teste `supabase/tests/relatorios_test.sql`. Módulo `app/src/modules/relatorios`.

## Decisão de arquitetura (aprovada pelo proprietário)
- **Uma view versionada por relatório** (`security_invoker` → a RLS de `lancamentos` vale). Nada de SQL dinâmico, nada de query gravada em tabela, nada de dados duplicados.
- **Catálogo em código** (`catalogo.ts`): id, área, view, filtros aceitos, colunas, agrupamentos, agregação no navegador (`preparar`). Adicionar relatório = criar a view (migration) + uma entrada no catálogo.
- **Tela genérica** (`RelatorioPage`): filtros → `from(view)` com filtros conhecidos → ordenação por coluna, agrupamento com subtotais, totais, **Exportar CSV** (abre no Excel), **Imprimir / PDF** (impressão do navegador, sem menu) e **favoritos**.
- **Única tabela**: `relatorios_favoritos` (por usuário: relatório + nome + filtros jsonb). Sem grant de DELETE; remover via `remover_relatorio_favorito(id)` (definer, só o próprio).
- Adiado (só se sentir falta): agendamento por e-mail/WhatsApp, histórico de execuções, PDF no servidor, Excel real, comparativos entre meses.

## Views
- `vw_centro_custo_mensal`: lançamentos previstos/efetivados (receita/despesa) por organização × negócio × mês × categoria × natureza × status. Cancelados fora; estornos negativos.
- `vw_rel_lancamentos`: lançamento com nomes resolvidos (conta, categoria, natureza, negócio "Pessoal" quando nulo, pessoa, código do contrato).
- `vw_rel_inadimplencia`: receitas previstas vencidas com dias de atraso e telefone.

## Relatórios entregues (área Financeiro)
1. **Resultado por centro de custo** — negócio a negócio: receitas, despesas operacionais, resultado operacional, investimentos, resultado, líquido ainda previsto.
2. **DRE simplificado** — previsto × realizado × total.
3. **Despesas por categoria** — com natureza; agrupável por centro de custo/natureza.
4. **Lançamentos** — listagem por período com todos os filtros; agrupável.
5. **Contas a receber — previsto × realizado** por cliente.
6. **Contas a pagar — previsto × realizado** por fornecedor/categoria.
7. **Inadimplência** — vencidas em aberto hoje.

Limite de 5.000 linhas por consulta (aviso na tela) — refinar o período.

## Regra do projeto (nova)
Toda etapa que criar dados entrega, na mesma entrega, o(s) relatório(s) correspondente(s) no catálogo (view + entrada + teste). Áreas previstas: 53B Clientes e contratos, 53C Operação (OS, estoque, FTTH, comodato), 53D Comercial (Indique e Ganhe, portal).
