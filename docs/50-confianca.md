# Etapa 47 — Voto de confiança na Cobrança

## O problema
Cliente atrasado promete pagar ("segunda eu pago"). Sem registro, o admin ou
bloqueia quem prometeu (queima a relação) ou ignora a sugestão e perde o
controle — e da próxima vez nem lembra que já confiou naquele cliente.

## A solução
Na lista de bloqueio, o botão **🤝 Confiança** registra o voto com data:

- **Segurar até dia X** (máx. 90 dias) + o combinado (texto livre, opcional).
- O bloqueio pendente do contrato é **descartado na hora** e não volta
  enquanto a confiança estiver ativa.
- **Pagou tudo dentro do prazo** → confiança marcada como `cumprida`.
- **Passou o prazo devendo** → confiança `furada` e o contrato **volta à
  lista destacado** ("🤝 Confiança furada") — o admin decide com esse
  histórico na frente.
- Confianças ativas aparecem em cartão próprio na tela, com **Cancelar**
  (volta a valer a régua normal na próxima atualização da lista).
- Nova confiança para o mesmo contrato substitui a anterior (vira `cancelada`).

A resolução (cumprida/furada) acontece dentro de `gerar_bloqueios`, que já
roda ao abrir a tela — nenhum job novo.

## Banco (migration `20260902000072_confianca.sql`)
- Enum `status_confianca`: `ativa · cumprida · furada · cancelada`.
- Tabela `confiancas` (org, negócio, contrato, pessoa, `segurar_ate`,
  observação, status, usuário, `resolvido_em`) — única ativa por contrato,
  RLS de leitura, escrita só pelas funções, auditoria.
- `bloqueios.confianca_furada boolean` — o destaque da lista.
- `dar_confianca(contrato, data, observacao)` — valida membro, contrato de
  receita, data futura ≤ 90 dias; cancela a ativa anterior e descarta o
  bloqueio pendente.
- `cancelar_confianca(id)` — só ativa pode ser cancelada.
- `gerar_bloqueios` recriada: resolve as ativas (pagou → cumprida; venceu
  devendo → furada), pula contratos com confiança ativa (e descarta o
  pendente deles) e marca `confianca_furada` quando a última confiança do
  contrato furou sem uma cumprida mais recente.

## App
`CobrancaPage`: botão 🤝 Confiança por item de bloqueio (form inline com data
e combinado), selo "🤝 Confiança furada" no item destacado e cartão
"Confianças ativas" com Cancelar.

## Testes
`supabase/tests/confianca_test.sql` (T1 segurar/descartar, T2 validações e
substituição, T3 furada + destaque, T4 cumprida e volta sem destaque) e check
0072 em `verificar_tudo.sql` (total 60).
