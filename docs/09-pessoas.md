# Etapa 6B — Pessoas e vínculos

Status: **CONCLUÍDA E VALIDADA EM PRODUÇÃO (02/09/2026).** Migration 0007 aplicada, verificação 7 de 7, cadastro/vínculo/lançamento confirmados pelo proprietário.

## 1. O que existe

### Banco (`supabase/migrations/20260902000007_pessoas.sql`)
| Objeto | Função |
|---|---|
| `tipo_pessoa` (física/jurídica), `papel_vinculo` (cliente/fornecedor/parceiro/outro) | Enums |
| `documento_valido(text)` | Valida CPF (11) e CNPJ (14) pelos dígitos verificadores; rejeita sequências repetidas. |
| `pessoas` | `tipo`, `nome` (2–120), `documento` (só dígitos, validado; física ⇒ 11, jurídica ⇒ 14; **único por organização quando informado**; opcional), `email` (minúsculo, formato), `telefone` (10–13 dígitos), `observacao`, `ativo`. O trigger normaliza: remove máscara do documento e telefone, baixa o e-mail. |
| `pessoa_negocio_vinculos` | `pessoa_id`, `negocio_id`, `papel`, `ativo`, `desde`; único por (pessoa, negócio, papel). Pessoa e negócio da mesma organização; negócio ativo e pessoa ativa ao criar/reativar. |
| `lancamentos.pessoa_id` | Opcional; pessoa da mesma organização, ativa ao vincular. |
| `tg_pessoas_protecao` | Organização imutável; **inativar bloqueado** com vínculos ativos ou lançamentos previstos pendentes. Histórico efetivado não impede. |
| Motor | `criar_lancamento`/`atualizar_lancamento` ganham `p_pessoa_id` (12º parâmetro). |
| RLS, grants, auditoria | Padrão; sem DELETE nas duas tabelas. |

### App (`app/src/modules/pessoas/`)
| Arquivo | Função |
|---|---|
| `tipos.ts` | Tipos, rótulos, máscara/formatação de CPF, CNPJ e telefone, validação de dígitos igual à do banco |
| `api.ts` | `usePessoas`, `useVinculos`, criar/atualizar pessoa, criar/ativar/inativar vínculo |
| `FormularioPessoa` | Física/jurídica, nome, CPF/CNPJ com máscara e validação, telefone, e-mail, observação, "Pessoa ativa" na edição |
| `VinculosPessoa` | Lista de vínculos (negócio · papel, status, inativar/reativar) e formulário de novo vínculo (negócio ativo + papel) |
| `PessoasPage` | Busca por nome, documento ou e-mail; filtro de inativas; tabela com documento formatado, contato, vínculos como etiquetas e status. Criar pessoa abre em seguida a seção de vínculos. Item **Pessoas** no menu. |
| Lançamentos | Campo "Pessoa (opcional)" em receita/despesa (não em transferência); pessoa aparece na linha. |

## 2. Decisões técnicas
1. **Documento validado no banco**, não só na tela. Documento é opcional (contatos sem CPF), mas único quando informado.
2. **Vínculo por papel**: a mesma pessoa pode ser cliente e fornecedora do mesmo negócio (dois vínculos). Único por pessoa+negócio+papel.
3. **Inativar pessoa** só sem vínculos ativos e sem previstos pendentes; histórico efetivado permitido (mesma lógica de Negócios). **Precisa da sua aprovação.**
4. **Vínculo não é obrigatório para lançar**: o lançamento aceita qualquer pessoa ativa da organização. A obrigatoriedade de vínculo entra nos contratos (6C), onde faz sentido.
5. Contatos em colunas simples (um e-mail, um telefone). Tabela de múltiplos contatos só se houver demanda.

## 3. Testes realizados
| Teste | Resultado |
|---|---|
| SQL T1 CPF/CNPJ válidos e inválidos | OK |
| T2 normalização (máscara, e-mail), física com CNPJ rejeitada, CPF inválido, e-mail inválido, documento duplicado, vários sem documento | OK |
| T3 vínculos múltiplos, duplicado, negócio inativo | OK |
| T4 inativar com vínculo ativo bloqueado; reativar vínculo de pessoa inativa bloqueado | OK |
| T5 lançamentos com pessoa; previsto pendente bloqueia inativação; pessoa inativa rejeitada | OK |
| T6 RLS e DELETE; T7 auditoria | OK |
| Suítes anteriores (7) e `verificar_rls` (10 tabelas); `verificar_pessoas.sql` 7 de 7 | OK |
| Lint, typecheck, build | OK |
| Interface: CPF inválido, máscara, criar → vínculos, dois vínculos, inativar bloqueada, lista formatada, jurídica, duplicidade, busca por nome e documento, lançamento com pessoa, transferência sem pessoa | 16 de 16 |
| Regressões Lançamentos 24/24, Negócios 20/20 | OK |

## 4. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000007_pessoas.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_pessoas.sql` → esperado `7 de 7 verificações OK`.
3. Site: Pessoas → nova pessoa com CPF → vincular à SERVNET como cliente → Lançamentos → receita com a pessoa.
