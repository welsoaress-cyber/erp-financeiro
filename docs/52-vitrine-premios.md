# Etapa 49 — Vitrine de prêmios no portal (Indique e Ganhe)

## O problema
A escolha do presente dependia do admin registrar manualmente, as faixas
eram fixas no código e o cliente não via os prêmios — sem foto, sem apelo.

## A solução
**Admin (Portal do cliente → Vitrine de prêmios):**
- **Faixas configuráveis** (`indicacao_faixas`): plano do indicado com
  mensalidade até R$ X → faixa N (teto do prêmio R$ Y); a última faixa fica
  com "plano até" vazio e pega tudo acima. Editáveis sem mexer em código.
  Sem faixas cadastradas vale a régua antiga (≤60→30, ≤80→50, acima→80).
- **Prêmios** (`indicacao_premios`): foto (comprimida no navegador para
  data URL ≤ 400 KB — sem Storage, custo zero), nome, faixa e vínculo ao
  item da categoria **Brindes** do Estoque (validado por trigger). Prêmio
  com saldo zero **some da vitrine sozinho** (não prometer o que não tem).
- **Adicionar em lote**: escolhe a faixa, seleciona várias fotos de uma vez
  (cada foto vira um prêmio; nome inicial vem do arquivo, editável antes de
  criar; o item da categoria Brindes é criado junto com saldo 0 — o prêmio
  entra na vitrine quando houver entrada no estoque).
- **Copiar link público**: vitrine sem login em `/portal/premios/<slug>`
  (função `vitrine_publica`, anon, só nome/foto/faixa — nenhum dado de
  cliente; mesmo padrão da página pública de indicação da 0023).

**Portal do cliente:**
- **Aviso no início**: banner "🎁 Sua indicação foi instalada — escolha seu
  presente" quando houver escolha pendente (várias conversões = várias
  escolhas independentes, cada uma na faixa do plano do seu indicado).
- **Vitrine em grade** (feita para celular): foto grande, toque para
  selecionar, confirmação e trava (sem troca — regra de sempre).
- **Acompanhamento**: lista de indicações com status e prazo restante de
  entrega (10 dias úteis da conversão) e a foto do presente escolhido.

**WhatsApp:** `converter_indicacao` agora enfileira um aviso ao indicante
(tipo `indicacao_convertida`, sem fatura vinculada) pela régua/Evolution já
configurada, com o link do portal — novo campo `portal_config.url_portal`
(Configurar portal → "Endereço do portal").

## Banco (migration `20260902000074_vitrine_premios.sql`)
- Tabelas `indicacao_faixas` e `indicacao_premios` (RLS, sem delete,
  triggers de proteção e auditoria).
- `indicacoes.presente_premio_id` (só via motor; trigger de proteção
  recriada).
- `faixa_da_indicacao` (config → fallback legado), `portal_presentes_indicacao`
  recriada (prêmios com foto; fallback por custo), `portal_escolher_presente`
  grava item + prêmio, `portal_indicacoes` com `presente_foto`.
- `converter_indicacao` com o aviso; constraint do log ajustada para o novo
  tipo; `vitrine_publica` (anon).

## Testes
`supabase/tests/vitrine_test.sql` (faixas, validações de prêmio, aviso na
conversão com link, vitrine por faixa/saldo com trava, vitrine pública
anon); check 0074 no `verificar_tudo.sql` (total 62).
