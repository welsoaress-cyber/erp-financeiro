# Segurança

Status: **implementado e testado localmente (02/09/2026); migration 0003 aguardando aplicação em produção.**

## 1. O que já estava em vigor (verificado)

| Medida | Como funciona | Evidência |
|---|---|---|
| Senhas com hash | Supabase Auth (GoTrue) armazena `encrypted_password` com **bcrypt**. O app nunca vê nem grava senha. | Padrão do serviço; nenhuma tabela própria de senha |
| RLS em todas as tabelas | `organizacoes`, `organizacao_membros`, `auditoria`, `contas`: RLS ativo, policies por organização via `minhas_organizacoes()` (security definer, sem recursão). `anon` sem nenhum grant. Nenhuma tabela concede DELETE ao cliente. | `supabase/tests/verificar_rls.sql` → todas as linhas `ok = true` |
| API protegida | Só existe a API do Supabase (PostgREST/Auth). Toda requisição leva a chave *publishable* + JWT do usuário; sem JWT o papel é `anon`, que não tem acesso a nada. A chave *service_role* nunca é usada no app. | grants na migration 0001/0002 |
| Auditoria de dados | Trigger genérico `tg_auditoria` em todas as tabelas de negócio: INSERT/UPDATE/DELETE com antes/depois em JSON e `usuario_id`. Tabela somente leitura para clientes. | testes T1–T8 e S1–S6 |
| Regras no banco | Integridade (tipo imutável, saldo derivado, sem exclusão física) é imposta por constraints e triggers, não pela tela. | `01-arquitetura.md` seção 5 |

## 2. Implementado agora

### A. Limite de tentativas de login
- **Onde:** `app/src/core/auth/useLimiteTentativas.ts`, usado em `LoginPage`.
- **Regra:** 5 s de pausa após cada falha; após 5 falhas seguidas, bloqueio de 5 minutos com a mensagem "Muitas tentativas. Aguarde 5 minutos." O botão fica desabilitado e o bloqueio sobrevive a recarregar a página (sessionStorage). Login correto zera o contador.
- **Limite honesto:** isso é **experiência do usuário**, não segurança. Qualquer atacante ignora o navegador e chama a API direto. A proteção real é o **rate limiting nativo do Supabase Auth**, que já existe por padrão (limite por IP nos endpoints de token/signup e limite de envio de e-mails). Confira em *Authentication → Rate Limits* no painel; nada precisa ser ativado.

### B. RLS reforçado
- Já estava completo. A verificação passou a ser **genérica**: `verificar_rls.sql` lista todas as tabelas do `public` e acusa qualquer uma sem RLS, sem policy ou com acesso `anon`.
- O padrão sugerido na solicitação (`EXISTS` em `organizacao_membros`) é equivalente ao adotado (`organizacao_id in (select minhas_organizacoes())`). O adotado foi mantido porque a função `security definer` evita recursão de RLS quando a própria `organizacao_membros` é consultada.

### C. Auditoria estendida a autenticação (`supabase/migrations/20260902000003_seguranca_auth.sql`)
- Trigger `on_auth_user_updated` em `auth.users` grava em `public.auditoria`:
  - **LOGIN** bem-sucedido (mudança de `last_sign_in_at`);
  - **troca de e-mail** (antes/depois);
  - **troca de senha** (apenas `senha_alterada: true`; **nenhum hash é gravado**, testado).
- A linha recebe a `organizacao_id` do usuário, então ele enxerga a própria trilha e ninguém mais.
- **Tentativas falhas de login não chegam ao banco**: o Supabase Auth as rejeita antes. Elas ficam em *Authentication → Logs* no painel (retenção do plano Free: 1 dia) e na tabela interna `auth.audit_log_entries`. Registrá-las em `public.auditoria` exigiria um backend próprio, fora do escopo.

## 3. Regra obrigatória para toda nova tabela
Toda migration que criar tabela em `public` deve, na própria migration:
1. `alter table … enable row level security`;
2. policies de `select`/`insert`/`update` filtrando por `organizacao_id in (select public.minhas_organizacoes())`;
3. `revoke all … from anon, authenticated` seguido de grants explícitos, **sem DELETE** salvo decisão documentada;
4. trigger `…_auditoria` com `tg_auditoria()` e trigger `…_atualizado_em`;
5. rodar `verificar_rls.sql` e incluir a tabela no teste SQL da etapa.

## 4. Futuro (documentado, não implementado)
| Medida | Onde | Observação |
|---|---|---|
| 2FA (TOTP) | Supabase Auth MFA, plano Free inclui TOTP | Exige tela de enrolar/validar no app |
| CAPTCHA no login/cadastro | Supabase Auth + hCaptcha ou Turnstile (Cloudflare, gratuito) | Ativar no painel + widget no app |
| Política de senha forte | *Authentication → Providers → Email → Password requirements* | Configuração no painel; hoje mínimo 6 |
| Expiração de sessão | *Authentication → Sessions* (time-box, inatividade) | Configuração no painel |
| Bloqueio de IPs | Cloudflare WAF (Free) na frente do Worker | Só para o site; a API do Supabase tem o rate limit próprio |
| Leaked password protection | *Authentication → Providers → Email* | Ligar quando disponível no plano |

## 5. Testes
| Teste | Resultado |
|---|---|
| S1 login auditado com organização | OK |
| S2 troca de e-mail auditada com antes/depois | OK |
| S3 troca de senha auditada sem hash | OK |
| S4 nenhum hash em `auditoria` | OK |
| S5 alteração de metadata não gera auditoria | OK |
| S6 usuário vê só a própria trilha de autenticação | OK |
| `verificar_rls.sql`: 4 tabelas, todas ok | OK |
| Fundação (T1–T6) e Contas (T1–T8) reexecutados com a migration 0003 | OK |
| Login e2e: falha → pausa 5 s → 5 falhas → bloqueio 5 min → persiste ao recarregar → login correto entra | 7 de 7 |

## 6. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000003_seguranca_auth.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_rls.sql` → Run → todas as linhas com `ok = true`.
3. Teste manual: errar a senha 6 vezes no site; na 5ª aparece o bloqueio de 5 minutos.
