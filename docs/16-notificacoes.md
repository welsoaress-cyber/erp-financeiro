# Etapa 10 — Notificações WhatsApp (modo simulado)

Status: **implementada e testada localmente (03/09/2026); aguardando aplicação das migrations 0016–0019 em produção e validação do proprietário.** O envio real (Evolution API) existe, mas fica desligado até o proprietário trocar o provedor na tela.

## 1. Objetivo
Resgatar os avisos do sistema anterior: **próximo ao vencimento** (X dias antes), **no dia** e **bloqueio** (Y dias após, sem pagamento), por negócio, com número e mensagens próprias. Nesta etapa o "envio" é simulado e registrado; a integração real entra depois como outro provedor, sem mudar o esquema.

## 2. Como funciona
```
job diário 12:00 UTC (09:00 Brasília)  →  executar_notificacoes_todas()
  ├─ gerar_notificacoes: para cada cobrança PREVISTA de contrato ATIVO em negócio com config ATIVA,
  │    se hoje = vencimento − dias_antes / vencimento / vencimento + dias_apos → cria o aviso (pendente)
  │    mensagem renderizada do template; destino = telefone da pessoa em E.164; sem telefone → erro
  └─ processar_notificacoes: dentro do horário comercial do negócio (hora Brasília),
       cobrança ainda prevista → provedor "simulado" marca simulado (nada sai);
       cobrança já paga/cancelada → erro "paga antes do envio" (não avisa);
       fora do horário → continua pendente até a próxima execução
```
- **Sem duplicidade:** índice único (cobrança, tipo). Um aviso por evento por cobrança, e o mês seguinte tem outra cobrança.
- **Contrato encerrado ou negócio inativo:** nada é gerado. Cobrança paga antes do dia do bloqueio: o aviso de bloqueio não é gerado (só cobranças previstas entram) ou, se já estava pendente, vira erro.
- **Horário comercial** por negócio (padrão 08:00–18:00, Brasília). O job roda às 09:00; o botão "Executar verificação agora" respeita o mesmo horário.
- **Auditoria:** `notificacoes_log` só é gravado pelo motor, sem update de mensagem/tipo e sem delete; triggers de auditoria em config e log.

## 3. Banco (migrations `0016_notificacoes.sql` e `0017_notificacoes_agendado.sql`)
- `notificacoes_config` (1 por negócio): `numero_whatsapp` (E.164, ex.: +5511954490001), `ativo` (exige número), `dias_antes` (0–30), `dias_apos` (1–60), `hora_inicio`/`hora_fim`, três templates (10–1000 caracteres), `provedor` (enum, só `simulado` por enquanto).
- `notificacoes_log`: negócio, contrato, pessoa, cobrança (`lancamento_id`), `tipo` (proximo_vencimento, vencimento, bloqueio, teste), `data_referencia`, `numero_destino`, `mensagem`, `status` (pendente, simulado, enviado, erro), `erro`, `data_envio`.
- Funções: `gerar_notificacoes`, `processar_notificacoes`, `executar_notificacoes` (internas), `executar_notificacoes_agora(p_data)` (RPC, até 31 dias à frente), `executar_notificacoes_todas()` (pg_cron), `enviar_notificacao_teste(negócio, pessoa, tipo)`, helpers `renderizar_template`, `numero_e164`, `moeda_br`. View `vw_notificacoes`.
- Placeholders: `{nome} {negocio} {plano} {valor} {vencimento} {contrato} {dias}`.
- Desvio da proposta: `status` tem o valor **simulado** além de enviado/erro/pendente, para nunca registrar "enviado" sem envio real. `tipo`/`status` são enums, não texto.

## 4. Interface (menu Notificações)
- Seleção do negócio; resumo da configuração; **Configurar** (número, ativo, dias, horário, três mensagens com prévia ao vivo usando dados de exemplo).
- **Executar verificação agora**: roda a verificação de hoje e mostra gerados/processados/pendentes.
- **Histórico** com busca por cliente ou #contrato e filtros por evento e status; mostra destino, status, motivo do erro e a mensagem.
- **Enviar teste**: registra uma mensagem `[TESTE]` para um cliente com telefone (simulada).

## 5. Envio real: provedor "Evolution API" (migration 0018, Edge Function, migration 0019)
O sistema anterior já envia pela **Evolution API auto-hospedada numa VM da Oracle Cloud** (gratuita), com uma instância por negócio (`servnet`, `servidor`). O ERP novo usa o mesmo caminho:
```
banco (fila: notificacoes_log pendente, provedor evolution)
  └─ pg_cron a cada 15 min (08–18h Brasília) → net.http_post → Edge Function notificacoes-enviar
        ├─ notificacoes_para_envio(): pendentes dentro do horário comercial (paga antes do envio → erro)
        ├─ Evolution: connectionState da instância; sendText com 3 tentativas; 1 s entre mensagens
        └─ registrar_resultado_notificacao(): enviado (com resposta) ou nova tentativa; 5 falhas → erro
```
- **Opt-in por negócio**: provedor `simulado` (padrão) ou `evolution` + nome da instância. Nada muda para quem fica em simulado.
- **Opt-out por pessoa**: "Recebe avisos de cobrança por WhatsApp" no cadastro (equivalente ao `receberLembretes` do sistema anterior).
- **Segredos só nos lugares certos**: `EVOLUTION_API_URL`, `EVOLUTION_API_KEY` e `NOTIFICACOES_CRON_SECRET` nos secrets da Edge Function; `project_url` e `notificacoes_cron_secret` no Vault do banco. Nada no repositório. No sistema anterior a chave e o IP da Evolution estão escritos dentro da função como valor padrão: **troque a chave na Evolution** e use a nova só nos secrets.
- A fila é acessível apenas ao `service_role` (a Edge Function). `anon`/`authenticated` não leem nem gravam.
- Ainda **sem** link Pix nas mensagens (o legado gera cobrança no Mercado Pago). Fica para uma etapa própria, com autorização.

## 5b. Custo e alternativas (não ativar sem autorização)
| Opção | Custo | Observação |
|---|---|---|
| WhatsApp Cloud API (Meta) | Conta Meta Business gratuita; conversas de utilidade cobradas por conversa após a franquia mensal gratuita | Exige número dedicado, verificação da empresa e templates aprovados. Integração via Edge Function do Supabase (gratuita no plano Free) com o token só em segredo do projeto. |
| Z-API / WPPConnect e similares | Pago (mensalidade) ou auto-hospedado | Usam WhatsApp não oficial; risco de bloqueio do número. |
Quando autorizado: novo valor no enum `provedor_notificacao`, uma Edge Function que lê os `pendente` e grava `enviado`/`erro`. O esquema, a tela e o job não mudam.

## 6. Testes
- `supabase/tests/notificacoes_test.sql`: helpers (E.164, template, moeda), validações da config (número, ativo sem número, template curto, log direto bloqueado), geração D-3/D0/D+3 com idempotência e sem telefone, horário comercial (pendente fora, simulado dentro), paga antes do envio → erro, contrato encerrado e config desativada não geram, teste manual, imutabilidade do log, `anon` negado.
- `supabase/tests/verificar_notificacoes.sql`: 6 verificações. `verificar_agendamento.sql` agora lista os dois jobs.
- e2e (Playwright + mock): configuração e validações, prévia de template, execução, D-3/D0 via RPC, histórico, filtros, teste manual, desativação.

## 7. Como aplicar em produção
1. SQL Editor → `0016_notificacoes.sql`, depois `0017_notificacoes_agendado.sql` (retorna o id do job), depois `0018_notificacoes_evolution.sql`.
2. `supabase/tests/verificar_notificacoes.sql` → 6 de 6; `verificar_notificacoes_envio.sql` → 5 de 5; `verificar_tudo.sql` → 16 de 16.
3. Deploy do app (push em `main`). Menu Notificações → Configurar (simulado) → Enviar teste → Executar verificação agora. Validar em simulado primeiro.
4. **Só depois, para ligar o envio real:** (a) na Evolution, gerar uma chave nova; (b) painel Supabase → Edge Functions → Deploy `supabase/functions/notificacoes-enviar` com "Verify JWT" desligado, e secrets `EVOLUTION_API_URL`, `EVOLUTION_API_KEY`, `NOTIFICACOES_CRON_SECRET`; (c) SQL Editor: `select vault.create_secret('https://SEU-REF.supabase.co','project_url'); select vault.create_secret('MESMO-SEGREDO','notificacoes_cron_secret');` (d) `0019_notificacoes_envio_agendado.sql`; (e) na tela, trocar o provedor do negócio para Evolution API com a instância; (f) Enviar teste para o seu próprio número e conferir o histórico como "Enviado".
