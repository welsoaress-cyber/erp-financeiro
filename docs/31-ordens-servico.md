# 31 · Ordens de Serviço — Etapa 29A (admin)

Chamados técnicos do provedor, integrados a pessoas, contratos, negócios, estoque (28A/B), lançamentos e Contas a Pagar. Entrega em três partes: **29A** banco + telas do admin (esta doc), **29B** login e tela do técnico, **29C** portal do cliente + avisos WhatsApp.

## Decisões do proprietário

- Técnico: login próprio (29B, usuário/senha sem e-mail), vê só os chamados dele, sem níveis; cadastro cria também uma **pessoa** (fornecedor das comissões).
- Bolsa separada do estoque central, com mínimo por item; admin abastece; técnico poderá pedir reposição (29B).
- Perda/avaria: motivo obrigatório; **não** gera cobrança automática do técnico (item caro é negociado por fora); defeito de fábrica fica marcado sem responsabilidade. Devolução volta ao central.
- Abertura: admin, cliente (portal, 29C) ou sem cliente (rede). Atribuição automática: único técnico ativo do negócio; com vários, o com menos chamados abertos.
- Número: `OS{contrato 3 díg}{DDMMAAAA}{letra}` ou `MAN{DDMMAAAA}{letra}` (sem contrato). **Reabertura é chamado novo**: `{número original}-{letra}`.
- Tempo: conta do **horário agendado** ao encerramento, menos pausas (pausa por qualquer motivo, texto obrigatório); não iniciar conta como ocioso. Guarda também o tempo real de execução (início→fim). Técnico não vê tempos.
- Remarcação: pedida pelo técnico, aval de quem abriu; **não trava** o chamado.
- Encerramento: materiais saem da **bolsa** (pode ficar negativa — alerta para repor), diagnóstico padronizado (conector, cabo rompido, ONU, energia/roteador do cliente, sinal degradado, sem defeito, outro), sinal em dBm (histórico de potência do cliente).
- Custos: OS **com** contrato de instalação/mudança → vira registro em `estoque_instalacoes` (payback 28B, sem tocar o central). Reparo/manutenção com contrato → custo do cliente em view própria, fora do payback. OS **sem** cliente (rompimento/vistoria) → custo da rede, **sem rateio** entre clientes.
- Comissão: só instalação/mudança, decisão do admin, valor editável (padrão 50% da mensalidade normalizada), despesa **prevista** na categoria **Comissões** (criada sozinha), fornecedor = pessoa do técnico, descrição com o número do chamado. O lançamento não leva `contrato_id` (o motor exige pessoa = pessoa do contrato); a comissão entra no payback pela view.
- Retorno: chamado novo do mesmo cliente até 7 dias após um encerramento é marcado como reincidência (↺).
- Alertas (tela de OS): urgente sem atendimento > 4h, pausado > 24h, técnico com ≥ 5 abertos, bolsa negativa/abaixo do mínimo.
- CTO vinculada ao chamado ganha anel vermelho tracejado no mapa FTTH até encerrar.

## Banco (migration `20260902000054`… já existia; esta é a `20260902000055_ordens_servico.sql`)

- Enums: `tipo_os`, `prioridade_os`, `status_os` (aberto, em_atendimento, pausado, encerrado, cancelado — sem "reaberto": reabertura cria chamado novo), `evento_os`, `origem_abertura_os`, `diagnostico_os`, `tipo_mov_tecnico`; `origem_movimentacao_estoque` ganha `transferencia`.
- Tabelas: `tecnicos`, `tecnico_estoque` (quantidade só pelo motor; mínimo configurável direto), `tecnico_movimentacoes` (imutável), `ordens_servico`, `os_materiais` (imutável), `os_historico` (imutável). `estoque_instalacoes.os_id` e `estoque_movimentacoes.instalacao_id` já ligavam 28B; agora a instalação nasce da OS.
- Motor (security definer, flag `erp.motor`): `abastecer_tecnico`, `devolver_tecnico`, `perda_tecnico`, `abrir_os`, `atualizar_os` (reatribuir/prioridade/CTO), `ciencia_os`, `agendar_os`, `solicitar_remarcacao_os`, `responder_remarcacao_os`, `iniciar_os`, `pausar_os`, `retomar_os`, `encerrar_os`, `cancelar_os`, `avaliar_os`, `aprovar_comissao_os`.
- Views: `vw_payback_contrato` (recriada: custo = instalações + comissões), `vw_os_custo_contrato` (manutenção do cliente fora do payback), `vw_bolsa_tecnicos` (valor em campo e alertas).
- RLS por organização em tudo; escrita direta bloqueada por trigger (`tg_os_protecao`).

## App (`app/src/modules/os/`, rota `/os`, menu Ordens de Serviço)

- **Dashboard**: abertos / em atendimento / pausados / encerrados no mês (com retornos), valor nas bolsas, tempo médio por técnico, alertas no topo.
- **Chamados**: busca, filtros por status e técnico; detalhe com todas as ações por status, tempos (só admin), remarcação com aprovar/recusar, encerramento com materiais + diagnóstico + sinal, avaliação, reabertura, comissão (conta + vencimento + valor editável), reatribuição.
- **Agenda**: próximos 7 dias, chamados agendados por dia/hora e técnico.
- **Técnicos**: cadastro (cria a pessoa fornecedor), bolsa (abastecer, devolver, perda/avaria com motivo, definir mínimo, histórico).
- Contratos → detalhe: linha "Manutenção pós-instalação" (custo fora do payback).
- Mapa FTTH: anel de chamado aberto na CTO.

## Etapa 29B — login e área do técnico (migration `20260902000056_os_tecnico.sql`)

- **Acesso**: o técnico entra no mesmo app em `/tecnico/entrar` com usuário e senha (o app converte para `login@tecnico.local` no Supabase Auth; metadata `tecnico=true` — não ganha organização própria, como o portal). O admin cria o login na aba Técnicos ("Criar login"), com cliente auxiliar para não derrubar a própria sessão. **Requisito**: confirmação de e-mail DESLIGADA no projeto (Auth → Providers → Email), como já é para o portal.
- **RLS**: técnico não é membro — não vê NADA do ERP. Políticas específicas abrem só: o próprio cadastro, os próprios chamados (com materiais/histórico), a própria bolsa/movimentações e os itens do negócio (nomes). Pessoas, contratos, contas, lançamentos e estoque central ficam invisíveis (testado). Dados do cliente do chamado só via RPC `os_info_cliente` (nome, telefone, endereço, contrato, CTO).
- **Ações do técnico** (motor com checagem membro-ou-técnico-do-chamado): ciência, agendar, pedir remarcação, iniciar, pausar, retomar, encerrar (materiais/diagnóstico/sinal/fotos) e perda/avaria da própria bolsa. Abrir, cancelar, reatribuir, avaliar, comissionar e abastecer continuam só do admin.
- **Reposição**: `solicitar_reposicao(item, qtd)` (técnico) → alerta na tela de OS do admin; `abastecer_tecnico` marca as pendências do item como atendidas (`reposicao_solicitacoes`).
- **Fotos**: bucket privado `os-fotos` (Storage) + tabela `os_fotos` (máx. 3 por chamado, caminho `os/{id}/…`, gravação via `registrar_foto_os`). Técnico fotografa no encerramento (comprimida a 1280px no aparelho); admin vê no detalhe com link assinado.
- **Tela do técnico** (mobile): Meus chamados (cartões, detalhe com dados do cliente e telefone clicável, ações por status, **sem tempos**) e Minha bolsa (saldo com alertas, pedir reposição, registrar perda).

## Etapa 29C — portal do cliente + avisos WhatsApp (migration `20260902000057_os_portal_whatsapp.sql`)

- **Portal → OS**: na tela Chamados do portal, o cliente pede uma **visita técnica** (Sem internet → reparo urgente; Internet lenta → reparo; Mudança de endereço; Outro → manutenção). Vira OS de verdade (`aberto_via = portal`, técnico automático, contrato ativo mais recente), com trava de 1 visita em andamento e 5 por dia. As solicitações antigas (fatura/dúvida/upgrade) continuam como eram.
- **Acompanhamento**: `portal_minhas_visitas` mostra número, status amigável, agendamento e técnico — nunca tempos internos; a tabela de OS continua invisível ao portal (testado).
- **Aval do cliente**: remarcação pedida pelo técnico em chamado aberto pelo portal aparece com "Aceitar nova data / Manter"; aprovar muda a agenda e dispara novo aviso. Encerrado → "Foi resolvido?" (sim → nota 1–5; não → reabre na hora como chamado novo `-A` urgente, mesmo técnico).
- **WhatsApp** (`os_notificar`, fila existente de `notificacoes_log` + Edge Function evolution): aviso ao **agendar** e ao **aprovar remarcação** ("visita agendada para DD/MM às HH:MM com o técnico X") e ao **encerrar** ("chamado concluído, avalie no portal" — uma vez só por chamado). Requer config de notificações ativa no negócio, telefone do cliente e receber_avisos ligado; provedor simulado registra na hora, evolution fica pendente para a fila. `notificacoes_log` ganhou `os_id` e os tipos `os_agendada`/`os_encerrada` (check de lançamento ajustado).
- `abrir_os` foi fatiada: núcleo `os_abrir_interna` (sem permissão, revogada) reutilizado pelo admin e pelo portal.

## Testes

`supabase/tests/os_test.sql`: número OS/MAN e sequência por dia, atribuição automática, bolsa (transferência central↔bolsa, perda com motivo, proteções), fluxo completo com tempo desde o agendado e pausa, instalação→payback sem tocar o central, bolsa negativa com alerta, custo de manutenção fora do payback, retorno ≤ 7 dias, comissão 50% (categoria, fornecedor, duplicada bloqueada, payback 80+50), avaliação e reabertura `-A`. `supabase/tests/os_tecnico_test.sql`: técnico não cria organização; vê só os próprios chamados/bolsa/cadastro; pessoas, lançamentos, contas, contratos e estoque central invisíveis; não abre chamado, não abastece, não age no chamado nem na bolsa de outro, não avalia; fluxo completo próprio funciona com dados mínimos do cliente; reposição pendente/atendida; fotos com caminho validado e limite de 3. `verificar_tudo.sql`: **44 de 44**. `supabase/tests/os_portal_test.sql` (29C): visita do portal vira OS urgente com contrato e técnico; segunda visita em andamento bloqueada; tabela de OS e fila de avisos invisíveis ao portal; aviso de agendamento na fila (simulado na hora), reenvio na remarcação aprovada pelo cliente, encerramento avisa uma vez; avaliação "não resolvido" reabre `-A` urgente; avaliar duas vezes ou visita alheia falha. Total: **45 de 45**.
