# Segurança

Status: **implementado; migration 0003 aplicada em produção (02/09/2026).** Pendência no painel do Supabase: política de senha (seção 5).

## 1. Visão geral
O sistema é um app estático (Cloudflare Workers) que fala diretamente com a API do Supabase (Auth + PostgREST). Não existe backend próprio. Consequência: **toda regra de segurança que importa vive no banco** (RLS, grants, triggers) e no Supabase Auth (hash de senha, rate limiting, sessões). O que roda no navegador (limite de tentativas, validação de senha, logout por inatividade) melhora a experiência e reduz abuso acidental, mas nunca é a única barreira.

Chaves: o app usa apenas a chave *publishable*, que é pública por natureza. A chave *service_role* não existe em nenhum lugar do projeto. Credenciais nunca vão para o repositório.

## 2. Medidas implementadas

| # | Medida | Camada | Estado |
|---|---|---|---|
| 1 | Senhas com hash **bcrypt** (Supabase Auth). O app nunca vê senha nem hash. | Auth | Verificado (padrão do serviço) |
| 2 | **RLS ativo** em `organizacoes`, `organizacao_membros`, `auditoria`, `contas`; policies por organização; `anon` sem grants; nenhum DELETE para clientes | Banco | Verificado por `verificar_rls.sql` |
| 3 | API protegida: sem JWT o papel é `anon` (sem acesso); com JWT, `auth.uid()` filtra tudo | Banco | Verificado |
| 4 | **Auditoria** INSERT/UPDATE/DELETE em todas as tabelas de negócio (antes/depois em JSON, `usuario_id`), tabela somente leitura. `CANCEL` de lançamentos entra na Etapa 5 como UPDATE de status auditado | Banco | Verificado (T1–T8) |
| 5 | **Auditoria de autenticação**: LOGIN bem-sucedido, troca de e-mail, troca de senha (sem hash) | Banco (migration 0003) | Testado (S1–S6) |
| 6 | **Limite de tentativas de login** por faixas, persistente | App | Testado (e2e) |
| 7 | **Senha forte** no cadastro | App + painel | Testado (e2e); painel pendente |
| 8 | **Logout por inatividade** (30 min) | App | Testado (e2e) |
| 9 | **Sanitização**: React escapa todo texto; zero uso de `dangerouslySetInnerHTML`, `innerHTML` ou `eval` (verificado por busca no código). SQL injection é impossível pelo caminho usado: PostgREST parametriza tudo, não há SQL montado no app | App | Verificado |
| 10 | URLs de Auth: Site URL e Redirect URL apontam para o site | Painel | Feito pelo proprietário |
| 11 | Regras de integridade no banco (tipo imutável, saldo derivado, sem exclusão física) | Banco | Verificado |

## 3. Políticas de RLS

Padrão adotado (usa função `security definer`, evita recursão quando a própria `organizacao_membros` é consultada):
```sql
create policy contas_select on public.contas
  for select to authenticated
  using (organizacao_id in (select public.minhas_organizacoes()));
```

Forma equivalente com `exists`, aceita quando a tabela não for `organizacao_membros`:
```sql
create policy usuario_visualiza_proprios_dados on public.nome_tabela
  for select to authenticated
  using (exists (
    select 1 from public.organizacao_membros m
    where m.organizacao_id = nome_tabela.organizacao_id and m.usuario_id = auth.uid()
  ));
```
Regras: policies separadas para `select`, `insert` (`with check`) e `update` (`using` + `with check`); **nunca** policy nem grant de `delete` sem decisão documentada; `anon` nunca recebe grant.

## 4. Limite de tentativas de login (rate limiting)
- Arquivo: `app/src/core/auth/useLimiteTentativas.ts`, usado em `LoginPage`.
- Faixas por falhas seguidas: 1ª e 2ª → pausa de 5 s; **3ª → 1 minuto; 5ª → 5 minutos; 10ª → 15 minutos**. Faixas intermediárias repetem a anterior (4ª = 1 min; 6ª a 9ª = 5 min).
- Mensagem: "Muitas tentativas. Aguarde X minutos." Botão desabilitado durante o bloqueio.
- Persistência em `localStorage` (`erp.login.tentativas`): vale entre abas e após recarregar. Contador zera com login correto ou após 1 h sem novas falhas.
- **Limite honesto:** é experiência do usuário. Quem ataca chama a API direto. A proteção real é o **rate limiting do Supabase Auth** (por IP nos endpoints de token/signup e limites de envio de e-mail), ativo por padrão. Conferir em *Authentication → Rate Limits*.

## 5. Política de senhas
- Arquivo: `app/src/core/auth/validarSenha.ts`, usado em `CadastroPage`, com checklist visual em tempo real.
- Requisitos: **mínimo 8 caracteres, 1 maiúscula, 1 minúscula, 1 número**. Caractere especial recomendado, não exigido.
- Mensagens: "A senha deve ter no mínimo 8 caracteres." / "...pelo menos 1 letra maiúscula." / "...1 letra minúscula." / "...1 número."
- **Pendente no painel (proprietário):** *Authentication → Providers → Email*: Minimum password length = **8**; Password requirements = **"Lowercase, uppercase letters and digits"**. Sem isso, a API aceitaria senha fraca vinda de fora do app.

## 6. Logout por inatividade
- Arquivo: `app/src/core/auth/useInatividade.ts`, ativado em `AppShell` (só com sessão).
- 30 minutos sem `mousemove`, `keydown`, `click`, `scroll` ou `touchstart` → logout e redirecionamento ao login com o aviso "Sessão expirada por inatividade. Clique em OK para fazer login novamente."
- Última atividade gravada em `localStorage` (no máximo 1 vez por segundo): vale entre abas e ao reabrir o navegador depois do prazo.
- Complemento recomendado no painel: *Authentication → Sessions* → time-box / inactivity timeout, para o servidor também expirar o token.

## 7. CORS e domínios autorizados
- **Fato técnico:** a API do Supabase (PostgREST e Auth) **não restringe CORS por domínio**; ela responde a qualquer origem porque a chave publishable é pública por definição. Não existe campo "domínio autorizado" para a API. A barreira é o JWT do usuário + RLS. Um site de outro domínio com a chave publishable só consegue o que um usuário anônimo consegue: **nada**.
- O que existe e está configurado: *Authentication → URL Configuration* → **Site URL** `https://erp-financeiro.welsoaress.workers.dev` e **Redirect URLs** `https://erp-financeiro.welsoaress.workers.dev/**`. Isso impede que links de confirmação e recuperação redirecionem para domínios de terceiros.
- Teste manual válido: acessar o site pela URL → funciona. "Bloquear a API de outro domínio" não é testável porque não é uma restrição que o serviço ofereça; o teste equivalente é: com a chave publishable e sem login, `select` em qualquer tabela retorna vazio ou erro de permissão.

## 8. Procedimento obrigatório para novas tabelas
Na própria migration que cria a tabela:
1. Coluna `organizacao_id uuid not null references public.organizacoes(id)`.
2. `alter table public.X enable row level security;`
3. Policies `X_select`, `X_insert`, `X_update` com o padrão da seção 3. Sem `delete`.
4. `revoke all on public.X from anon, authenticated;` e depois `grant select, insert, update on public.X to authenticated;`
5. Triggers `X_atualizado_em` (`tg_atualizado_em`) e `X_auditoria` (`tg_auditoria`).
6. Funções novas: `set search_path = public`; `security definer` só quando necessário, com `revoke ... from public, anon`.
7. Rodar `supabase/tests/verificar_rls.sql` (todas as linhas `ok = true`) e cobrir a tabela no teste SQL da etapa (criar, RLS entre usuários, DELETE negado).

## 9. Recomendações futuras (não implementadas)
| Medida | Onde | Custo |
|---|---|---|
| 2FA (TOTP) | Supabase Auth MFA + telas no app | Free |
| CAPTCHA no login/cadastro | Cloudflare Turnstile (gratuito) integrado ao Supabase Auth | Free |
| Expiração de sessão no servidor | *Authentication → Sessions* | Free |
| Proteção contra senhas vazadas | *Authentication → Providers → Email → Leaked password protection* | Depende do plano |
| Bloqueio de IPs / WAF | Cloudflare WAF na frente do Worker | Free (regras básicas) |
| Alertas de auditoria | Consulta periódica em `auditoria` (LOGIN fora de horário, troca de senha) | Etapa futura |

## 10. Testes realizados
| Teste | Resultado |
|---|---|
| SQL S1–S6: login/e-mail/senha auditados, sem hash, metadata ignorada, trilha visível só ao próprio usuário | OK |
| `verificar_rls.sql`: 4 tabelas, RLS + policies + sem anon + sem DELETE | OK |
| Fundação T1–T6 e Contas T1–T8 reexecutados com a migration 0003 | OK |
| E2E login: pausa curta → 3ª falha 1 min → 4ª 1 min → 5ª 5 min → 10ª 15 min → persiste ao recarregar → login correto zera | 10 de 10 |
| E2E cadastro: "123", sem maiúscula, sem minúscula, sem número rejeitadas; "Abc12345" aceita | 5 de 5 |
| E2E inatividade: atividade gravada; 31 min → logout + aviso; OK fecha; sessão removida | 4 de 4 |
| Busca por `dangerouslySetInnerHTML`, `innerHTML`, `eval(` no código | 0 ocorrências |
| Lint, typecheck, build | OK |

Testes manuais restantes para o proprietário, em produção: errar a senha 3 vezes (1 min) e continuar até 5 (5 min); cadastrar com "123" (rejeita) e "Abc12345" (aceita); deixar 30 min parado (logout).

## 11. Aplicar em produção
1. SQL Editor → `supabase/migrations/20260902000003_seguranca_auth.sql` → Run.
2. SQL Editor → `supabase/tests/verificar_rls.sql` → todas as linhas `ok = true`.
3. Painel: *Authentication → Providers → Email* → senha mínima 8 + "Lowercase, uppercase letters and digits".
4. Opcional: *Authentication → Sessions* → inactivity timeout 30 min.
