# 71 · Controle de Boletos (v1) + desconto em lançamento

Migrations `20260902000126_boletos_desconto.sql` e `20260902000127_forma_pagamento_default_outro.sql`. Módulo `app/src/modules/boletos` + tela em `Financeiro → Cobrança`.

**0127**: o default original (`forma_pagamento` nasce `pix`) marcava todo contrato existente como pix silenciosamente, sem o proprietário decidir — impossível saber quem ainda faltava classificar. Trocado para nascer **`outro`** (estado neutro, "ainda não decidi") — migration já zera pra `outro` todo contrato que estava em `pix` (ninguém tinha escolhido isso de propósito, era só o default antigo). Agora o proprietário vai revisando contrato a contrato e marcando pix/boleto conforme o caso real.

## Pedido do proprietário
Servidor (IPTV/streaming) é 100% Pix; Servnet (internet) mistura Pix e boleto, e não havia como saber quem ainda precisava receber o boleto por WhatsApp perto do vencimento.

## O que foi feito
1. **`contratos.forma_pagamento`**: `pix` (default) | `boleto` | `outro` — por **contrato**, não por pessoa (a mesma pessoa pode ter um contrato pix e outro boleto). Editável em Contratos → abrir → Editar, só para contrato de receita.
2. **`boletos_enviados`**: log imutável (organizacao_id, negocio_id, contrato_id, lancamento_id, pessoa_id, enviado_em, canal, mensagem, usuario_id). Cada envio é uma linha nova — histórico e reenvio saem de graça, sem campo de "status".
3. **`lancamentos.codigo_barras`**: opcional, editável por `definir_codigo_barras_lancamento` (motor, só em previsto).
4. **Tela Financeiro → Cobrança → "Boletos pendentes de envio"**: por negócio (reaproveita o seletor já existente na página), filtro de dia de vencimento (ex.: dia 10 a 15 — usa `contratos.dia_vencimento`, não a data do lançamento, porque é assim que o proprietário pensa o filtro). Lista só boleto + ativo + previsto + sem registro em `boletos_enviados` — pago e bloqueado/suspenso somem sozinhos, sem lógica extra (já está no `where` da view). Em cada linha: **+ Código** (código de barras/linha digitável), **+ Desconto** (valor e motivo), botão **WhatsApp** (mensagem pronta com valor, vencimento, código de barras e desconto se houver) e **Marcar como enviado**.
5. **Relatório na Central de Relatórios**: "Boletos pendentes de envio" (Clientes e contratos), reaproveitando a mesma view da tela.

## Desconto — mesmo padrão já usado no resgate de pontos (0102)
`conceder_desconto_lancamento(id, valor_desconto, motivo)`: reduz `lancamentos.valor` **direto**, pela função do motor (`set_config('erp.motor','on')`) — assim saldo, dashboard e relatórios de "a receber" continuam corretos sozinhos, sem precisar saber que desconto existe. `valor_desconto` e `motivo_desconto` ficam no lançamento como trilha de auditoria (nunca em `boletos_enviados`, que já guarda a mensagem literal enviada).
- `p_valor_desconto` é o desconto **total** desejado (substitui o anterior, não soma) — chamar de novo com `0` remove.
- Só em `status = 'previsto'`; não pode zerar nem ultrapassar o valor (`check`); motivo obrigatório quando desconto > 0 (`check` no banco, backstop da validação da função).
- `vw_rel_lancamentos` ganha `valor_desconto`/`motivo_desconto` no fim (CREATE OR REPLACE VIEW não deixa inserir no meio) — aparece no relatório "Lançamentos" existente, com total.

## Por que não ficou como no pedido original
O proprietário pediu `boletos_enviados.valor_desconto` e `lancamentos.valor_desconto` como campos **separados e intocáveis**. Ficou só no lançamento: um campo redundante em `boletos_enviados` poderia dessincronizar do valor real se o desconto mudasse depois do envio. `boletos_enviados.mensagem` já guarda o texto exato enviado (incluindo o desconto, se houver), que é o retrato daquele momento.

## Teste
`supabase/tests/boletos_test.sql`: forma_pagamento nasce pix; desconto aplica/remove/falha sem motivo/negativo/≥valor/em efetivado; código de barras seta e falha em efetivado; registrar envio tira da lista de pendentes e reenvio soma histórico; `vw_rel_boletos_pendentes` só mostra boleto+ativo+previsto+sem envio; `vw_rel_lancamentos` carrega o desconto.

## Fora da v1 (decisão registrada, não esquecida)
- Template de mensagem configurável por negócio — v1 usa uma mensagem padrão fixa.
- Ligar boleto vencido à régua/bloqueio automático — mexe no motor de bloqueio, etapa própria.
- Vencimento sempre em dia útil — mudaria o cálculo pra todo contrato de receita, não só boleto.
- CRM do cliente (`cliente_eventos`) — recomendado como **view** sobre dados já existentes (lançamentos, bloqueios, `lancamentos_vencimento_historico`), não uma tabela alimentada pela aplicação; decisão registrada na conversa, aguardando o proprietário definir a fórmula de score de risco antes de construir.
