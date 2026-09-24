# Etapa 60: autoatualização de cadastro pro curso (Leveduca)

## Motivo

Clientes que vão fazer o curso na Leveduca (não são clientes de internet da Servnet — esses já
têm CPF/e-mail/nascimento em dia) precisam ter CPF, e-mail e data de nascimento cadastrados, e
precisam de um contrato cortesia com a Servnet no plano do curso, com início em 01/10/2026, pra
ter acesso liberado. O proprietário estava fazendo isso na mão, um por um.

## O que foi feito

- **Página pública, sem login** (`/curso/atualizar`, migration 0107): o cliente informa o telefone
  e clica **Pesquisar**. Se existe cadastro com esse telefone, abrem 3 campos — **CPF**, **e-mail**,
  **data de nascimento** — pré-preenchidos com o que já existir, pra confirmar ou corrigir. Ao
  clicar **Atualizar**:
  1. `pessoas.documento/email/data_nascimento` são atualizados.
  2. Se a pessoa ainda não tem contrato ativo/suspenso no plano do curso, um é criado — negócio
     Servnet, plano com "curso" no nome, **cortesia** (valor R$ 0), início **01/10/2026**,
     vencimento dia 1. Idempotente: clicar de novo não duplica o contrato.
- **Sem senha nem código de link** — o único fator de verificação é o telefone bater com o
  cadastro (mesmo padrão de risco do link de indicação pública, etapa 11B, mas sem o código
  secreto do link). Aceitável pra esse uso pontual (curso gratuito, sem dinheiro envolvido); quem
  souber/adivinhar o telefone de alguém pode preencher CPF/nascimento dela. **Sugestão pro
  proprietário, não implementada:** se esse fluxo virar permanente, vale considerar mais um fator
  (ex.: últimos 4 dígitos do CPF, se já tiver).
- Funções `curso_buscar_pessoa(telefone)` e `curso_atualizar_cadastro(pessoa_id, cpf, email,
  nascimento)`, `security definer`, concedidas a `anon` — mesmo padrão das funções públicas já
  existentes (`portal_indicacao_publica`, `vitrine_publica`).

## Como divulgar

Mande o link `https://SEU-DOMINIO/painel/curso/atualizar` pra quem vai fazer o curso.

## Deploy (proprietário)

1. SQL Editor: aplicar `20260902000107_curso_autoatualizacao.sql`.
2. Confirmar que o negócio **Servnet** tem um **plano com "curso" no nome** ativo (é por aí que a
   função encontra o plano a vincular) e conta/categoria de receita padrão configuradas (senão o
   contrato nasce sem lançamento — mas a cortesia com plano de valor R$ 0 não gera lançamento de
   qualquer forma, então isso não trava nada).
3. Deploy do app (push em `main`). Testar em `/curso/atualizar` com um telefone de teste.
