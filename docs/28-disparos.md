# Etapa 26 — Disparos WhatsApp (migration 0042)

## Objetivo
Disparo manual de mensagens WhatsApp (máx. **30 por vez**, **15 s** entre mensagens) para clientes do servidor IPTV identificados pelo **login** extraído do PDF de receitas, com modelos editáveis, histórico por item, reenvio de falhas e lançamento opcional da cobrança no contas a receber.

## Como funciona
1. **Login do servidor**: novo campo em Pessoas (`pessoas.login_servidor`, único por organização). É o vínculo entre o PDF e o cadastro.
2. **Tela Disparos**: upload do PDF → o texto é lido no navegador (pdfjs) e todo login cadastrado que aparecer no PDF entra na lista. Cliente sem telefone: a tela pede o telefone e salva no cadastro. Quem desativou "receber avisos" aparece desmarcado. Também dá para adicionar clientes manualmente.
3. **Modelos** (`disparo_modelos`, CRUD do usuário): dois padrões criados pela migration — "Lembrete de vencimento" e "Interrupção no serviço". `{nome}` vira o primeiro nome do cliente.
4. **Fila própria** (`disparos` + `disparo_itens`, gravadas só pelo motor): `criar_disparo(negócio, modelo, itens)` valida 1–30 itens e telefone (E.164). `processar_disparos()` aciona a Edge Function **disparos-enviar** via `net.http_post` (segredos do Vault, mesmo padrão da 0020); a Edge envia **3 itens por chamada** com 15 s de pausa pela mesma Evolution API (instância da config de notificações do negócio); a tela re-aciona a cada ~50 s enquanto houver pendentes. 5 falhas → status erro; `reenviar_falhas_disparo` volta os erros para a fila.
5. **Cobrança opcional**: valor e vencimento digitados na tela; para cada marcado sem lançamento previsto naquele vencimento, cria receita **fixa mensal** pelo motor (`criar_lancamento`, projeção automática de 60 meses), sem marcar como paga; não duplica.

## Aplicar em produção
1. SQL Editor → `20260902000042_disparos_whatsapp.sql`.
2. Painel Supabase → Edge Functions → deploy `supabase/functions/disparos-enviar` com "Verify JWT" desligado (usa os mesmos secrets da `notificacoes-enviar`).
3. `verificar_tudo.sql` → 34 de 34. Deploy do app sai pelo push na `main`.

## Testes
`supabase/tests/disparos_test.sql`: modelos padrão, login único, criar_disparo (E.164, pendentes), validações (sem telefone, >30, escrita direta bloqueada), fila service_role, 5 tentativas → erro, reenvio de falhas, enviado.
