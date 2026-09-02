# Etapa 2 — Fundação

Status: **CONCLUÍDA em código e testada localmente (02/09/2026).** Rename `entidades` → `organizacoes` / `entidade_membros` → `organizacao_membros` **aplicado** em migration, testes e app, com zero ocorrências antigas restantes. Pendências externas: criação do projeto Supabase (seção 6) e conexão do Cloudflare Pages (seção 5). Nenhum módulo de operação foi antecipado; eles pertencem ao roadmap (`01-arquitetura.md`, seção 11).

## 1. O que existe

### Banco (`supabase/migrations/20260902000001_fundacao.sql`)
| Objeto | Função |
|---|---|
| `organizacoes` | Escopo raiz (a holding). Toda tabela financeira futura terá `organizacao_id`. |
| `organizacao_membros` | Vínculo `auth.users` × organização, com papel `proprietario` / `membro`. |
| `auditoria` | Trilha imutável: tabela, registro, ação, antes/depois (JSON), usuário, quando. |
| `tg_auditoria()` | Trigger genérico. Basta anexar a qualquer tabela nova. Grava via `security definer` porque clientes não têm permissão de escrita na auditoria. |
| `tg_atualizado_em()` | Mantém `atualizado_em`, ignorando valor enviado pelo cliente. |
| `tg_novo_usuario()` | Ao criar usuário no Auth, cria a organização dele e o vincula como proprietário. |
| `minhas_organizacoes()` / `sou_proprietario()` | Helpers `security definer` usados nas policies (evitam recursão de RLS). |

Sem extensões adicionais: `gen_random_uuid()` é nativo do Postgres 13+.

### RLS e privilégios
- RLS habilitado nas 3 tabelas.
- `organizacoes`: membro lê; **só proprietário edita**; sem insert/delete pelo cliente.
- `organizacao_membros`: membro lê os membros da própria organização; sem escrita pelo cliente.
- `auditoria`: membro lê a trilha da própria organização; **nenhuma escrita pelo cliente**.
- `anon` não tem acesso a nada. Grants revogados explicitamente além do RLS (defesa em profundidade).
- Todas as funções têm `search_path` fixo.

### Aplicação (`app/`)
```
src/
├── app/            App.tsx (providers), router.tsx (rotas geradas do registro), modulos.ts (REGISTRO)
├── core/
│   ├── supabase/   cliente único; tela de erro se .env ausente
│   ├── auth/       AuthProvider, useAuth, RequireAuth / SomenteAnonimo
│   ├── organizacao/ OrganizacaoProvider, useOrganizacao (organização atual = escopo de todas as consultas futuras)
│   ├── modulos/    contrato DefinicaoModulo
│   ├── layout/     AppShell, BarraLateral, BarraSuperior (responsivo)
│   ├── ui/         Botao, Campo, Alerta, Carregando, Cartao, CabecalhoPagina, ModuloEmBreve, Icone
│   └── erros/      ErrorBoundary, mensagemDeErro (tradução de erros do Supabase)
├── modules/        dashboard, lancamentos, contas, categorias, configuracoes (placeholders, sem lógica financeira)
└── pages/auth/     LoginPage, CadastroPage
```
**Adicionar um módulo** = criar `src/modules/<nome>/index.ts` exportando `DefinicaoModulo` e incluir em `src/app/modulos.ts`. Menu e rotas são derivados do registro.

## 2. Decisões técnicas desta etapa
1. **Tailwind v4** via plugin do Vite; tokens de cor em `src/index.css`.
2. **TanStack Query** já na fundação: única forma de consultar dados nos módulos futuros (cache, loading, erro padronizados).
3. **Ícones inline** (SVG próprio) em vez de biblioteca: 6 ícones não justificam dependência.
4. **Nome da organização** no signup = nome informado no cadastro (metadata `nome`); fallback = parte local do e-mail.
5. **Chaves**: usar a chave *publishable* (`sb_publishable_...`) do projeto, nunca a `service_role`.
6. **Auditoria sem FK** para `organizacoes`: histórico sobrevive a qualquer remoção futura.
7. Hooks separados dos providers (`useAuth.ts`, `useOrganizacao.ts`) por exigência do Fast Refresh.
8. **Rename aprovado e aplicado** (02/09/2026): `entidades` → `organizacoes`, `entidade_membros` → `organizacao_membros`, `minhas_entidades()` → `minhas_organizacoes()`, `auditoria.entidade_id` → `organizacao_id`. Motivo: liberar o termo "entidade" e evitar colisão com "pessoa/cliente" da visão de plataforma.

## 3. Testes realizados
| Teste | Como | Resultado |
|---|---|---|
| Migration + RLS + auditoria (`supabase/tests/fundacao_test.sql`, T1–T6) | Postgres 16 local com shim do `auth` (`00_shim_local.sql`) | OK |
| T1 signup cria organização, membro proprietário e auditoria | SQL | OK |
| T2 usuário vê somente a própria organização/membros/auditoria | `set role authenticated` + claim `sub` | OK |
| T3 proprietário edita; auditoria grava antes/depois e `usuario_id`; `atualizado_em` sobrescrito | SQL | OK |
| T4 update em organização alheia afeta 0 linhas | SQL | OK |
| T5 insert/delete em organizacoes, membros e auditoria negados ao cliente | SQL (`insufficient_privilege`) | OK |
| T6 `anon` sem acesso a tabelas e funções | SQL | OK |
| Typecheck + build (`tsc -b && vite build`) | npm | OK |
| Lint (`oxlint`) | npm | 0 avisos |
| Sem `.env`: tela "Supabase não configurado" | Chromium headless | OK |
| `/entrar`, `/cadastro` renderizam; `/` e `/contas` sem sessão redirecionam ao login | Chromium headless | OK |
| Shell autenticado: menu, nome da organização, e-mail, botão Sair, placeholders, Configurações | Chromium headless + mock local da API REST + sessão simulada | OK |
| Pós-rename: todos os itens acima reexecutados; busca por `entidade` em `supabase/` e `app/src` = 0 ocorrências | grep + rerun | OK |

**Não testado ainda** (depende do projeto Supabase real): signup/login/logout ponta a ponta contra o Auth.

Rodar os testes de banco localmente:
```
createdb erp_test
psql -d erp_test -f supabase/tests/00_shim_local.sql -f supabase/migrations/20260902000001_fundacao.sql
psql -d erp_test -f supabase/tests/fundacao_test.sql   # deve terminar com OK
```

## 4. Como rodar o app
```
cd erp-financeiro/app
cp .env.example .env.local   # preencher URL e chave publishable do projeto
npm install
npm run dev
```

## 5. Hospedagem / deploy — Cloudflare Pages (APROVADO, plano Free)
Aprovado em 02/09/2026. Regra permanente: nenhum recurso pago habilitado.

**Por que não gera cobrança:** Pages Free não exige cartão; inclui 500 builds/mês, banda e requisições ilimitadas para conteúdo estático. Só existe custo se você contratar manualmente o plano Workers Paid, que este projeto não usa. Não usar: Workers, D1, KV, R2, Access, domínios pagos.

**Estado:** ainda **não conectado**. Este ambiente não possui credencial Cloudflare e o conector disponível não expõe deploy de Pages, então a conexão é feita uma vez no painel (integração Git, sem CI extra):

1. Cloudflare Dashboard → *Workers & Pages* → *Create* → *Pages* → *Connect to Git* → repositório `welsoaress-cyber/holding-financeiro`.
2. Build settings:
   - Production branch: `main` (ou o branch de trabalho enquanto o PR não for mesclado)
   - Root directory: `erp-financeiro/app`
   - Build command: `npm run build`
   - Build output directory: `dist`
3. Environment variables (Production e Preview): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (chave *publishable*).
4. SPA: Pages serve `index.html` para rotas não encontradas quando não existe `404.html` — nada a configurar.

Sem o projeto Supabase, o deploy exibirá a tela "Supabase não configurado" (comportamento esperado).

## 6. Supabase — projeto novo criado (conta exclusiva, plano Free)
Projeto criado pelo proprietário em 02/09/2026 na nova conta (Opção A). URL: `https://slrdhspnovzubiyccnnk.supabase.co`. A chave *publishable* fica apenas em `app/.env.local` (ignorado pelo git) e nas variáveis do Cloudflare Pages; nunca no repositório.

**Limitação do ambiente de desenvolvimento assistido:** a rede do ambiente remoto bloqueia o host do novo projeto e o conector Supabase está vinculado à conta antiga. Portanto, aplicar a migration, verificar o banco e rodar o teste ponta a ponta são executados **pelo proprietário**, com os artefatos prontos abaixo.

| Passo | Como | Artefato |
|---|---|---|
| 1. Aplicar migration | SQL Editor → colar → Run | `supabase/migrations/20260902000001_fundacao.sql` |
| 2. Verificar tabelas, functions, triggers, policies e grants | SQL Editor → colar → Run; esperado `27 de 27 verificações OK` | `supabase/tests/verificar_fundacao.sql` (somente leitura; validado localmente) |
| 3. Variáveis do app | `app/.env.local` já criado com URL e chave publishable | — |
| 4. Teste ponta a ponta | `cd app && npm install && npm run dev` → cadastro → confirmar e-mail (se exigido) → login → navegar → sair | — |
| 5. Confirmar no banco | SQL Editor: `select nome from organizacoes;` e `select acao, tabela from auditoria order by id;` → 1 organização, 2 auditorias INSERT | — |

Auth: manter e-mail + senha (padrão). "Confirm email" pode ficar ligado; o remetente padrão do Supabase é gratuito e limitado a poucos envios por hora, suficiente para uso pessoal. Nenhum provedor de e-mail pago deve ser configurado.

Limitação do plano Free: projeto pausa após 7 dias sem uso (restauração manual, sem perda de dados).
