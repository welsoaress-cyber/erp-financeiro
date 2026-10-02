# Etapa 57: bloqueio/desbloqueio automático (opt-in)

## Motivo

Até aqui, "Bloqueio assistido" (etapa 31) exigia um clique manual em "Bloqueei/Desbloqueei na rede" — porque, em geral, **o ERP não manda comando nenhum pra rede**: quem corta ou libera o acesso é o ReceitaNet/OLT, fora daqui. Com 4 mil clientes, revisar isso um por um todo dia não escala.

O proprietário confirmou que, no caso da Servnet, **o ReceitaNet já bloqueia e já libera o acesso sozinho**, pelas próprias regras dele (vencimento + N dias sem pagar → bloqueia; pagou → libera). Ou seja: o corte físico já é automático, fora do ERP — só faltava o ERP parar de esperar o clique manual pra registrar isso.

## O que foi feito

- **`notificacoes_config.bloqueio_automatico`** (opt-in, `false` por padrão): liga o robô diário pra esse negócio. Continua desligado por padrão porque nem todo negócio tem rede com bloqueio automático — quem não tem, segue no fluxo assistido normalmente.
- **Robô diário** (`executar_bloqueios_automaticos`, pg_cron às 00:00 Brasília, depois do faturamento): pros negócios com o toggle ligado, gera as sugestões (mesma lógica de `gerar_bloqueios`, incluindo voto de confiança) e **já confirma sozinho** — suspende quem venceu há mais que a régua "avisar depois", reativa quem quitou.
- **Auditoria**: `bloqueios.automatico` marca se foi o robô ou um clique manual; `usuario_id` fica nulo nos automáticos. Relatório **"Bloqueios e desbloqueios"** na Central de Relatórios mostra os dois tipos lado a lado.
- Cobrança avisa quando o negócio está no modo automático (a lista "Ações na rede" tende a ficar vazia, porque o robô já tratou de madrugada).

## Por que não automatizei o corte físico em si

O ERP continua **sem nenhuma integração de comando com o ReceitaNet/OLT** — não é ele quem corta ou libera a internet. Isso é outra etapa (a integração ReceitaNet que já está no radar do CLAUDE.md, aguardando o proprietário ativar o módulo de API). O que esta etapa faz é manter o **status interno do contrato** (e por tabela, a API da Leveduca) alinhado com o que a rede já faz por conta própria — sem isso, o contrato podia continuar "ativo" no ERP dias depois do cliente já estar bloqueado de verdade.

## Deploy (proprietário)

1. SQL Editor: aplicar `20260902000097_bloqueio_automatico.sql` e depois `20260902000098_bloqueio_automatico_agendado.sql` (nessa ordem — o segundo agenda o pg_cron).
2. No app: **Notificações → configurar o negócio → marcar "Bloqueio e desbloqueio automáticos" → Salvar** (só pra negócios onde a rede já bloqueia/libera sozinha).

## Ajuste (0114): curso cortesia acompanha inadimplência dos outros contratos

Bloqueio/desbloqueio (`gerar_bloqueios`, 0059/0072/0097) olha cada contrato isoladamente — só as cobranças vencidas daquele mesmo contrato. O contrato cortesia do curso Leveduca (etapa 60, valor R$ 0) nunca tem cobrança vencida, então nunca entra nessa varredura: ficava **Ativo pra sempre**, mesmo com a mesma pessoa suspensa em outro negócio (internet) por falta de pagamento — e é esse status que a Leveduca enxerga pela API (`api_consultar_cliente`, 0099) pra liberar o curso.

**Decisão do proprietário:** o curso é benefício condicionado a estar em dia nos outros negócios.

- `sincronizar_cortesia_curso(organizacao_id)`: pra cada contrato cortesia com plano "curso" no nome, suspende se a mesma pessoa tiver **qualquer outro** contrato de receita pago (não cortesia) suspenso em qualquer negócio da organização; libera de volta quando não tiver mais nenhum. Chamável pelo app (autenticado, exige ser membro da organização).
- `sincronizar_cortesia_curso_automatico()`: mesma coisa, para todas as organizações — encadeado no fim do robô diário (`executar_bloqueios_automaticos`, 00:00 Brasília), roda todo dia independente do negócio ter `bloqueio_automatico` ligado (é checagem cruzada entre negócios, não depende da rede de nenhum deles específico).
- Outros tipos de cortesia (indicação, prêmios da vitrine de pontos) **não** entram nessa regra — só o plano de curso, de propósito.
- Correção imediata de um cliente específico (sem esperar a virada do dia): SQL Editor, `select public.sincronizar_cortesia_curso('ID_DA_ORGANIZACAO');`.

### Deploy (proprietário)

1. SQL Editor: aplicar `20260902000114_curso_cortesia_segue_inadimplencia.sql`.
2. Opcional, pra corrigir agora quem já está nessa situação sem esperar 00:00: `select public.sincronizar_cortesia_curso('ID_DA_ORGANIZACAO');` (pega o ID em Configurações, ou `select id from organizacoes;`).

## Ajuste (0119): botão "Atualizar bloqueio/desbloqueio agora" também sincroniza o curso

A sincronização da 0114 só estava encadeada no robô diário (`executar_bloqueios_automaticos`, 00:00). O botão manual "Atualizar bloqueio/desbloqueio agora" chama `executar_bloqueios_agora` — uma função **por negócio**, separada — que nunca chamava `sincronizar_cortesia_curso_logica`. Resultado: clicar no botão suspendia o contrato pago na hora, mas o curso cortesia da mesma pessoa só acompanhava na virada do dia seguinte — a Leveduca via "Ativo" até lá.

`executar_bloqueios_agora` agora chama `sincronizar_cortesia_curso_logica(organizacao_id)` ao final, igual ao robô. O retorno ganhou `curso_suspensos`/`curso_liberados`, junto com `executados`.

### Deploy (proprietário)
SQL Editor: aplicar `20260902000119_atualizar_agora_sincroniza_curso.sql`.
