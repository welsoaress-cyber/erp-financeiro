# 18 · Portal do cliente no padrão SERVNET (Etapa 11B)

Réplica da experiência do portal antigo (`servnet.net.br/portal`) sobre o ERP: login sem senha, status da rede, fidelidade, indique e ganhe com mês grátis, meus dados e chamados. Migration `20260902000024_portal_servnet.sql`.

## Login sem senha (CPF/CNPJ + data de nascimento)
- `pessoas.data_nascimento` (para empresas, a data de fundação). Preenchida no cadastro de Pessoas ou pela importação futura.
- Edge Function `portal-login` (Verify JWT desligado, sem secrets novos): chama `portal_login_verificar` (só `service_role`; 5 falhas → 15 min bloqueado por documento), cria o usuário técnico do Auth na primeira vez (`<pessoa_id>@portal.erp.local`, `user_metadata.portal = 'true'`), vincula com `portal_vincular_servico` e devolve o `token_hash` de um link mágico. O navegador troca por sessão com `supabase.auth.verifyOtp`.
- O login por e-mail e senha da Etapa 11 continua em `/portal/entrar-email` (acesso alternativo). Mesma pessoa = mesmo acesso, seja qual for a forma de entrar.

## Programa Fidelidade
- `fidelidade_cartao(contrato, referência)`: cartão de 12 competências a partir da 1ª competência do contrato (ciclos de 12 em 12). Selo = cobrança paga até o vencimento (ou mês grátis). Estados por slot: `ok`, `gratis`, `atraso`, `vencida`, `aberto`, `vazio`.
- Prêmios: 6º selo → 50% na competência seguinte; 12º selo → 100% (mês grátis) na competência seguinte. `fidelidade_registrar_premio` grava o desconto uma única vez (`descontos_contrato.referencia` = `fidelidade:AAAA-MM:50|100`) e `faturar_contrato` aplica ao gerar a cobrança. Liga/desliga em `portal_config.fidelidade_ativa`.
- Mês grátis (desconto ≥ valor): a cobrança nasce **cancelada** com `motivo_cancelamento = 'Mês grátis: …'`, sem movimento financeiro. Aparece no portal como "Mês grátis" e conta selo.

## Indique e Ganhe
- `portal_config.beneficio_tipo`: `mes_gratis` (padrão, 100% da próxima fatura) ou `valor` (R$ fixo). `converter_indicacao` gera o desconto conforme a config.
- Link de indicação usa `portal_config.site_url` quando informado (`https://www.servnet.net.br/?ref=CODIGO`); sem site, usa `/portal/indicacao/CODIGO` do próprio portal.

## Status da rede, chamados e meus dados
- `portal_status_rede` (1 por negócio): `ok | lentidao | queda | manutencao` + título/descrição. O cliente vê o aviso no início do portal enquanto não for `ok`.
- `portal_solicitacoes`: chamados com protocolo `PT-AAAAMMDD-XXXX`, tipos `suporte | fatura | duvida | upgrade`, status `aberta | em_andamento | concluida`, resposta do administrador. Limite de 10 por dia por cliente. Admin vê e responde em Portal do cliente → Chamados do portal (view `vw_portal_solicitacoes`).
- `portal_atualizar_contato`: cliente altera e-mail, telefone e "receber avisos".
- `portal_config` ganhou `tema` (escuro padrão SERVNET ou claro), `whatsapp_suporte` (E.164, banner de suporte) e `site_url`.

## App
- Cliente: `/portal/entrar` (CPF/CNPJ + nascimento), painel na ordem do portal antigo (status da rede, WhatsApp, meu plano, próxima fatura + Pix, fidelidade, promoções, indique e ganhe, meus dados, chamado), páginas `/portal/fidelidade`, `/portal/chamados`, `/portal/dados`. Tema escuro via classe `portal-escuro` (tokens CSS sobrescritos).
- Admin: configuração ampliada, status da rede e chamados em `/portal-admin`; data de nascimento no cadastro de Pessoas.
- Importação (ajuste): CPF e CNPJ podem vir em colunas separadas; o campo de vencimento aceita dia ou data completa.

## Produção (nesta ordem)
1. Aplicar `20260902000024_portal_servnet.sql` no SQL Editor; rodar `supabase/tests/verificar_portal_servnet.sql` (6 de 6) e `verificar_tudo.sql` (18 de 18).
2. Edge Function `portal-login`: criar no painel com o conteúdo de `supabase/functions/portal-login/index.ts`, **Verify JWT desligado**. Não precisa de secret.
3. Preencher a data de nascimento das pessoas que vão usar o login sem senha.
4. Domínio `servnet.net.br/portal`: rota do Worker no Cloudflare (gratuita), ver docs/19.

## Testes
- `supabase/tests/portal_servnet_test.sql` (fidelidade com 50% e mês grátis, login/bloqueio, vínculo, contato, chamados, status da rede, RLS).
- e2e Playwright `portal_servnet.spec.mjs` (mock): login CPF+nascimento, tema escuro, aviso da rede, fidelidade, chamado, meus dados, admin responde.
