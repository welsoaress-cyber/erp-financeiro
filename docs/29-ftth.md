# Etapa 27A — Mapeamento FTTH (migration 0047)

## Objetivo
Gerenciar a rede FTTH da Servnet: CTOs com localização no mapa, portas ópticas, vínculo cliente↔porta amarrado a contrato ativo, histórico de movimentação e alertas de lotação ao vivo.

## Regras
- CTO pertence a um negócio; portas geradas automaticamente pelo cadastro (1–64, splitter informativo); código único por organização (sugerido CTO-NNN, editável); reduzir quantidade exige portas excedentes livres.
- **Uma porta por cliente** (índice único). Vincular exige contrato **ativo** do cliente **no negócio da CTO** (o contrato é escolhido manualmente na tela). Reserva sempre com cliente; "Efetivar instalação" converte em ocupada.
- Liberar e trocar deixam a porta antiga **livre com "drop disponível para utilização"**. Porta com defeito não pode ser ocupada; defeito em porta ocupada mantém o cliente. Todo movimento vai para `cto_historico` (com `auth.uid()`).
- Alertas ao vivo (sem job): ≥90% amarelo, 100% vermelho, no mapa, na lista e no topo da tela.

## Banco (0047)
`ctos`, `cto_portas` (motor: `vincular_porta_cto`, `liberar_porta_cto`, `trocar_porta_cto`, `defeito_porta_cto` sob `erp.motor`), `cto_historico` (insert-only pelo motor), view `vw_ctos_ocupacao` (security_invoker). RLS por organização; sem DELETE para authenticated (redução de portas via trigger security definer).

## App (menu "Rede FTTH")
Abas Mapa (Leaflet + OpenStreetMap, pinos coloridos pela ocupação, tooltip e clique abre a CTO), CTOs (lista com ocupação/drops/defeitos) e Histórico. Nova/editar CTO com localização marcada **clicando no mapa** (centro padrão: Jd. Moraes Prado, São Paulo/SP). Detalhe da CTO: grade de portas colorida (ocupada/reservada/drop livre/defeito), vincular (cliente com contrato ativo + escolha do contrato + reservar), liberar, trocar (para outra CTO do mesmo negócio), marcar defeito/reparo, histórico da CTO.

## Etapa 27B (próxima)
Busca por CEP + número (Nominatim) com sugestão de CTO mais próxima; CTO/porta no detalhe de pessoa e contrato.

## Testes
`supabase/tests/ftth_test.sql`: geração/aumento/redução de portas, contrato encerrado recusado, 1 porta por cliente, escrita direta bloqueada, defeito bloqueia, reserva→ocupada, troca com histórico dos dois lados, liberação com drop, view de ocupação.

## Etapa 27B (migration 0048) — POP, fios e clientes no mapa
- **Busca de endereço** no mapa (Nominatim): digite "rua, número, cidade" e o mapa dá zoom com um pino roxo no ponto.
- **POP**: cadastrado como ponto da rede (`ctos.tipo = 'pop'`, pino azul grande). Cada CTO pode apontar "Fibra vem do POP" (`pop_id`, validado: POP do mesmo negócio) — o mapa desenha o fio tracejado POP→CTO.
- **Clientes no mapa**: no detalhe da porta ocupada/reservada, "Marcar local do cliente no mapa" (busca + clique) grava `cliente_latitude/longitude` via `local_cliente_porta` (motor); o mapa geral desenha o fio CTO→cliente com o nome na dica.
- Premissa: fios em **linha reta** entre os pontos (sem vértices de poste nesta versão).

## Etapa 27C (migration 0049) — fios com vértices
Os fios deixam de ser linha reta: `ctos.rota_pop` (vértices POP→CTO) e `cto_portas.rota_cliente` (vértices CTO→cliente; o **último ponto é a casa do cliente**, que alimenta `cliente_latitude/longitude`). RPCs `rota_pop_cto` e `rota_cliente_porta` validam a rota (`validar_rota`, até 200 pontos [lat,lng]). Na tela: "Desenhar fio POP→CTO" no detalhe da CTO e "Desenhar fio até o cliente" no detalhe da porta — cada clique no mapa é um vértice, com Desfazer/Limpar/Salvar; o mapa geral renderiza os traçados completos.

## Etapa 27D (migration 0050) — endereço do cadastro e fio automático
`pessoas.endereco` (texto livre, campo no formulário de Pessoas). No FTTH: ao **vincular** um cliente com endereço cadastrado, o sistema geocodifica (Nominatim) e desenha o fio CTO→casa automaticamente (1 ponto — reta); o desenho manual abre já com a busca do endereço do cliente executada, para refinar os vértices.

## Etapa 27E (migration 0051) — lacre numerado por porta
`cto_portas.lacre` (3–20 caracteres alfanuméricos, único por organização, `lacre_porta_cto` via motor). Na tela: campo "Lacre (nº do drop na caixa)" no painel da porta; o número aparece na grade de portas e no diagrama do splitter. Vazio remove o lacre.

## Etapa 27F (migration 0052) — identificação da própria CTO
`ctos.lacre` (etiqueta/lacre físico da caixa, único por organização). Campo "Identificação física / lacre da caixa" no formulário; aparece no cabeçalho do detalhe e na lista de CTOs.
