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
