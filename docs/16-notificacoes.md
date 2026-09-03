# Etapa 10 — Notificações WhatsApp (modo simulado)

Status: **implementada e testada localmente (03/09/2026); aguardando aplicação das migrations 0016/0017 em produção e validação do proprietário.** Nenhuma mensagem real é enviada nesta etapa.

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

## 5. Custo e integração futura (não ativar sem autorização)
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
1. SQL Editor → `supabase/migrations/20260902000016_notificacoes.sql`.
2. SQL Editor → `supabase/migrations/20260902000017_notificacoes_agendado.sql` (retorna o id do job).
3. `supabase/tests/verificar_notificacoes.sql` → **6 de 6**; `supabase/tests/verificar_agendamento.sql` → 2 jobs ativos.
4. Deploy do app (push em `main`). Menu Notificações → Configurar (número fictício é aceito; nada é enviado) → Enviar teste → Executar verificação agora.
