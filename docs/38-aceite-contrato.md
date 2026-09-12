# 38 · Aceite digital do contrato — Etapa 36 (migration `20260902000063_aceite_contrato.sql`)

O cliente lê o **termo de adesão** no portal (Meu plano) e aceita digitalmente. Fica gravado, imutável e auditado: o **texto exato** aceito (snapshot + hash MD5), **data/hora**, **IP** e **user-agent** — capturados pela Edge Function `portal-aceite` (Verify JWT ligado; o navegador não fala com o banco direto). Um aceite por contrato; contrato encerrado não recebe aceite.

- **Modelo do termo** editável por negócio (`portal_config.contrato_modelo`, com `{cliente}`, `{documento}`, `{plano}`, `{valor}`, `{vencimento}`, `{codigo}`, `{negocio}`, `{data_inicio}`); vem com um texto padrão sensato.
- **Portal**: cartão "Termo de adesão" em Meu plano — pendentes com "Ler o termo e aceitar" (o texto abre na tela) e aceitos com a data.
- **Admin**: no detalhe do contrato aparece "Aceite digital em DD/MM/AAAA (IP …)" ou "Sem aceite digital ainda".
- Deploy necessário: Edge `portal-aceite` (Verify JWT ligado, sem secrets extras).

## Testes

`supabase/tests/aceite_test.sql`: termo renderizado com os dados do contrato, aceite via service com IP e hash, duplicado bloqueado, situação no portal, imutabilidade, visão do admin. `verificar_tudo.sql`: **51 de 51**.


> **Correção (12/09/2026):** o código da Edge `portal-aceite` não havia sido versionado nesta etapa — só existia deployado no projeto antigo. Agora está em `supabase/functions/portal-aceite/index.ts` (Verify JWT ligado, sem secrets próprios).
