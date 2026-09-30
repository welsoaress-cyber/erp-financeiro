# 67 · Gestão de RH simplificada — Etapa 62 (migration `20260902000113_rh_funcionarios.sql`)

Cadastro de funcionários, ponto informal, férias (tracker de datas) e folha como lançamento de despesa mensal. Escopo aprovado pelo proprietário — **fora do escopo, permanentemente** (risco trabalhista/legal real, não é "depois"):

- Cálculo de INSS/IRRF/FGTS/13º/rescisão.
- eSocial (obrigação federal, fora do alcance de um ERP interno).
- Ponto com valor jurídico pleno — exige homologação REP-P (Portaria 671/MTE); o ponto daqui é só controle interno.
- Banco de horas automático.
- Documentos anexados (RG/CTPS/exames) — precisa de Storage, que o sistema ainda não usa em lugar nenhum; fica pra quando/se for autorizado.

## Modelo

- **`funcionarios`**: vínculo de emprego sobre uma pessoa já cadastrada (`pessoa_id`) — não duplica nome/CPF, mesmo padrão já usado em `tecnicos` (0055). `cargo`, `departamento`, `salario_base`, `data_admissao`/`data_demissao`, `ativo`. Único por `(organizacao_id, pessoa_id)`.
- **Histórico de cargo/salário**: não tem tabela própria — qualquer `update` em `funcionarios` já cai na auditoria genérica (`tg_auditoria`), mesmo truque usado pro histórico de status dos leads (etapa 61).
- **`funcionario_ponto`**: um registro por dia (`unique(funcionario_id, data)`), 4 horários (entrada/saída almoço/saída) editáveis — horas trabalhadas calculadas no front, sem gravar no banco.
- **`funcionario_ferias`**: período aquisitivo + período de gozo + status (`programada|em_gozo|concluida|cancelada`) — só datas, sem valores.
- **`funcionario_folha`**: um lançamento de despesa por funcionário por mês (`unique(funcionario_id, mes)`), imutável (só `select`+`insert`, sem `update`/`delete` — pra corrigir, estornar o lançamento e lançar de novo).

## Função

`lancar_folha_funcionario(funcionario_id, mes, valor, conta_id, vencimento, centro_custo_id?, observacao?)` — cria a categoria "Folha de pagamento" se não existir, chama `criar_lancamento` (o motor, mesmo padrão de `aprovar_comissao_os`, 0055) com `pessoa_id`/`negocio_id` do funcionário, define centro de custo se informado, e grava o vínculo em `funcionario_folha`. **O valor final (salário + comissões − descontos) é informado manualmente** — sem engine de cálculo trabalhista.

## App

`/rh` (menu Operação): lista de funcionários com busca/filtro por negócio, cadastro/edição reaproveitando `SelecaoBusca` sobre `pessoas`. Detalhe com 3 abas — Ponto, Férias, Folha — cada uma com seu formulário de lançamento e histórico. Comissão de técnico continua pelo fluxo que já existia (OS → `aprovar_comissao_os`), sem mudança.

## Testes

`supabase/tests/rh_funcionarios_test.sql`: funcionário não duplica pessoa (unique por organização), ponto não duplica dia e é editável, férias valida período aquisitivo, folha gera lançamento correto e bloqueia duplicidade no mês, folha é imutável (update sem grant falha), mudança de cargo/salário cai na auditoria. `verificar_tudo.sql`: 77 de 77 (sem verificação nova — etapa não mexe em dado financeiro pré-existente).
