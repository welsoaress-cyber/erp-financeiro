-- Testes da migration 0023 (portal do cliente). Saída final "OK".
\set ON_ERROR_STOP on
begin;
-- usuário do portal (metadata portal=true → sem organização própria)
insert into auth.users (id, email, raw_user_meta_data) values ('33333333-3333-3333-3333-333333333333', 'cliente@teste.dev', '{"portal":"true","nome":"Cliente"}');
insert into auth.users (id, email, raw_user_meta_data) values ('44444444-4444-4444-4444-444444444444', 'outro@teste.dev', '{"portal":"true"}');
do $$ begin
  assert not exists (select 1 from public.organizacao_membros where usuario_id = '33333333-3333-3333-3333-333333333333'), 'T0 usuário do portal não ganha organização';
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
grant select on ids to service_role, anon;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.negocios (organizacao_id, nome, slug, conta_padrao_id, categoria_receita_id)
  select org, 'SERVNET', 'servnet', (select id from public.contas where nome='Banco'), (select id from public.categorias where nome='Salário') from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone, email) select org, 'João da Silva', '52998224725', '11988887777', 'joao@x.com' from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone) select org, 'Maria Indicada', '12345678909', '11977776666' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, descricao) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90, '500 Mbps' from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet,
  (select id from public.pessoas where nome='João da Silva') joao, (select id from public.pessoas where nome='Maria Indicada') maria, (select id from public.planos where nome='Fibra 500') fibra;
grant select on r to service_role, anon;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, servnet, joao, fibra, 99.90, 'mensal', date '2026-07-01', 10 from r;
select public.gerar_faturamento_agora(date '2026-09-30');  -- cobranças 07, 08, 09/2026
insert into public.portal_config (organizacao_id, negocio_id, chave_pix, beneficio_indicacao, texto_promocional, beneficio_tipo) select org, servnet, 'pix@servnet.com', 20, 'Indique e ganhe R$ 20', 'valor' from r;
insert into public.promocoes (organizacao_id, negocio_id, titulo, descricao) select org, servnet, 'Upgrade grátis', 'Dobro de velocidade por 3 meses' from r;
insert into public.promocoes (organizacao_id, negocio_id, titulo, descricao, ativa) select org, servnet, 'Encerrada', 'não aparece', false from r;
-- paga a primeira cobrança
select public.efetivar_lancamento((select id from public.lancamentos where contrato_id = (select id from public.contratos limit 1) order by data_vencimento limit 1), date '2026-07-09');

-- T1: vínculo do cliente — CPF + telefone conferem; administrador não pode; telefone errado não pode; segundo vínculo da mesma pessoa não pode
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ declare v r%rowtype; j jsonb; begin
  select * into v from r;
  assert public.portal_pessoa() is null, 'T1 sem vínculo';
  assert public.portal_resumo() is null, 'T1 resumo nulo sem vínculo';
  begin
    perform public.portal_vincular('52998224725', '11900000000');
    raise exception 'T1 telefone errado deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.portal_vincular('11111111111', '11988887777');
    raise exception 'T1 CPF inexistente deveria falhar';
  exception when check_violation then null; end;
  j := public.portal_vincular('529.982.247-25', '(11) 98888-7777');
  assert (j->>'pessoa_id')::uuid = v.joao and length(j->>'codigo_indicacao') = 8 and not (j->>'ja_vinculado')::boolean, 'T1 vinculado: ' || j::text;
  assert public.portal_pessoa() = v.joao, 'T1 portal_pessoa';
  j := public.portal_vincular('52998224725', '11988887777');
  assert (j->>'ja_vinculado')::boolean, 'T1 idempotente';
end $$;
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
do $$ begin
  begin
    perform public.portal_vincular('52998224725', '11988887777');
    raise exception 'T1 segunda conta para a mesma pessoa deveria falhar';
  exception when check_violation then null; end;
end $$;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  begin
    perform public.portal_vincular('52998224725', '11988887777');
    raise exception 'T1 administrador deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T2: dados do cliente — resumo, faturas (situação), próximas, pagamentos, contratos, promoções; nada do ERP visível diretamente
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ declare v r%rowtype; j jsonb; n int; begin
  select * into v from r;
  j := public.portal_resumo();
  assert j->'pessoa'->>'nome' = 'João da Silva' and (j->>'contratos_ativos')::int = 1 and (j->>'em_aberto')::numeric = 199.80, 'T2 resumo: ' || j::text;
  assert (j->'negocios'->0->'portal'->>'chave_pix') = 'pix@servnet.com', 'T2 config do portal no resumo';
  select count(*) into n from public.portal_faturas(); assert n = 3, 'T2 3 faturas';
  assert (select count(*) from public.portal_faturas() where situacao = 'paga') = 1, 'T2 1 paga';
  assert (select count(*) from public.portal_faturas() where situacao = 'vencida') = 1, 'T2 08/2026 vencida (hoje é 03/09)';
  assert (select count(*) from public.portal_faturas() where situacao = 'pendente') = 1, 'T2 09/2026 pendente';
  assert (select chave_pix from public.portal_faturas() limit 1) = 'pix@servnet.com', 'T2 chave pix na fatura';
  select count(*) into n from public.portal_proximas_faturas(); assert n between 5 and 7, 'T2 próximas ~6 meses (' || n || ')';
  assert (select min(data_vencimento) from public.portal_proximas_faturas()) = date '2026-10-10', 'T2 próxima 10/10';
  select count(*) into n from public.portal_pagamentos(); assert n = 1 and (select forma from public.portal_pagamentos()) = 'Banco', 'T2 pagamentos';
  assert (select plano from public.portal_contratos()) = 'Fibra 500' and (select proxima_renovacao from public.portal_contratos()) = date '2026-10-01', 'T2 contrato';
  assert (select count(*) from public.portal_promocoes()) = 1 and (select titulo from public.portal_promocoes()) = 'Upgrade grátis', 'T2 promoções vigentes';
  -- tabelas do ERP não são visíveis ao cliente (RLS por organização)
  select count(*) into n from public.lancamentos; assert n = 0, 'T2 cliente não lê lancamentos direto';
  select count(*) into n from public.pessoas; assert n = 0, 'T2 cliente não lê pessoas direto';
  select count(*) into n from public.contratos; assert n = 0, 'T2 cliente não lê contratos direto';
  select count(*) into n from public.portal_acessos; assert n = 1, 'T2 cliente vê só o próprio acesso';
end $$;

-- T3: Indique e Ganhe — indicar (logado), link público (anon), conversão pelo administrador gera desconto na próxima fatura
do $$ declare v r%rowtype; i public.indicacoes; begin
  select * into v from r;
  i := public.portal_indicar(v.servnet, 'Maria Indicada', '(11) 97777-6666');
  assert i.status = 'pendente' and i.telefone_indicado = '11977776666', 'T3 indicação criada';
  begin
    perform public.portal_indicar(v.servnet, 'Maria de novo', '11977776666');
    raise exception 'T3 telefone repetido deveria falhar';
  exception when check_violation then null; end;
  assert (select count(*) from public.portal_indicacoes()) = 1, 'T3 lista do cliente';
end $$;
set local role anon;
do $$ declare cod text; begin
  begin
    select codigo_indicacao into cod from public.portal_acessos;
    raise exception 'T3 anon não deveria ler portal_acessos';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
create temp table cod as select codigo_indicacao from public.portal_acessos;
grant select on cod to anon;
set local role anon;
do $$ declare j jsonb; c text; begin
  select codigo_indicacao into c from cod;
  j := public.portal_info_indicacao(c);
  assert j->>'negocio' = 'SERVNET' and j->>'indicador' = 'João' and j->>'texto' = 'Indique e ganhe R$ 20', 'T3 info pública: ' || j::text;
  j := public.portal_indicacao_publica(lower(c), 'Pedro Novo', '11 96666-5555');
  assert (j->>'ok')::boolean and not (j->>'repetida')::boolean, 'T3 indicação pública';
  j := public.portal_indicacao_publica(c, 'Pedro Novo', '11966665555');
  assert (j->>'repetida')::boolean, 'T3 repetida não duplica';
  begin
    perform public.portal_indicacao_publica('XXXXXXXX', 'A', '11900000000');
    raise exception 'T3 código inválido deveria falhar';
  exception when check_violation then null; end;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; i public.indicacoes; n int; l public.lancamentos; begin
  select * into v from r;
  perform set_config('erp.motor', 'off', true);  -- flag do motor fica ligada na transação do teste
  select * into i from public.indicacoes where nome_indicado = 'Maria Indicada';
  begin
    update public.indicacoes set status = 'convertida', indicado_pessoa_id = v.maria where id = i.id;
    raise exception 'T3 converter direto deveria falhar';
  exception when check_violation then null; end;
  i := public.converter_indicacao(i.id, v.maria);
  assert i.status = 'convertida' and i.beneficio_valor = 20 and i.desconto_id is not null, 'T3 convertida com benefício';
  select count(*) into n from public.descontos_contrato where lancamento_id is null; assert n = 1, 'T3 desconto pendente';
  begin
    perform public.converter_indicacao(i.id, v.maria);
    raise exception 'T3 converter duas vezes deveria falhar';
  exception when check_violation then null; end;
  -- próxima cobrança (10/2026) sai com desconto
  perform public.gerar_faturamento_agora(date '2026-10-31');
  select * into l from public.lancamentos where contrato_id = (select id from public.contratos limit 1) and data_vencimento = date '2026-10-10';
  assert l.valor = 79.90 and l.observacao like 'Desconto aplicado: R$ 20,00%', 'T3 fatura com desconto: ' || l.valor || ' ' || coalesce(l.observacao, '');
  select count(*) into n from public.descontos_contrato where lancamento_id is null; assert n = 0, 'T3 desconto consumido';
  reset role;
  perform public.gerar_faturamento(v.org, date '2026-11-30', 'manual');
  set local role authenticated;
  assert (select valor from public.lancamentos where contrato_id = (select id from public.contratos limit 1) and data_vencimento = date '2026-11-10') = 99.90, 'T3 mês seguinte sem desconto';
end $$;
-- cliente vê o benefício nas indicações e nas próximas faturas
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ begin
  assert (select count(*) from public.portal_indicacoes() where status = 'convertida' and beneficio_valor = 20) = 1, 'T3 cliente vê conversão';
  assert (select (public.portal_resumo()->>'indicacoes_convertidas')::int) = 1, 'T3 resumo conta conversões';
  assert (select count(*) from public.portal_faturas() where valor = 79.90) = 1, 'T3 cliente vê fatura com desconto';
end $$;
rollback;
\echo OK
