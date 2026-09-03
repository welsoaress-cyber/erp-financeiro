-- Testes da migration 0024 (portal estilo SERVNET: login CPF/CNPJ + nascimento, fidelidade, mês grátis, status da rede, chamados). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('33333333-3333-3333-3333-333333333333', 'cliente@teste.dev', '{"portal":"true"}');
insert into auth.users (id, email, raw_user_meta_data) values ('44444444-4444-4444-4444-444444444444', 'outro@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
grant select on ids to service_role, anon;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
insert into public.negocios (organizacao_id, nome, slug, conta_padrao_id, categoria_receita_id)
  select org, 'SERVNET', 'servnet', (select id from public.contas where nome='Banco'), (select id from public.categorias where nome='Salário') from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone, email, data_nascimento) select org, 'João da Silva', '52998224725', '11988887777', 'joao@x.com', date '1990-05-10' from ids;
insert into public.pessoas (organizacao_id, nome, tipo, documento, telefone, data_nascimento) select org, 'Igreja Central', 'juridica'::public.tipo_pessoa, '11222333000181', '11977776666', date '2001-03-15' from ids;
insert into public.pessoas (organizacao_id, nome, documento, telefone, data_nascimento) select org, 'Sem Contrato', '12345678909', '11966665555', date '1980-01-01' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, descricao) select org, (select id from public.negocios where slug='servnet'), 'Fibra 500', 99.90, '500 Mbps' from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet,
  (select id from public.pessoas where nome='João da Silva') joao, (select id from public.pessoas where nome='Igreja Central') igreja,
  (select id from public.pessoas where nome='Sem Contrato') semc, (select id from public.planos where nome='Fibra 500') fibra;
grant select on r to service_role, anon;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, servnet, joao, fibra, 99.90, 'mensal', date '2025-09-01', 10 from r;
insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento)
  select org, servnet, igreja, fibra, 150.00, 'mensal', date '2026-08-01', 15 from r;
insert into public.portal_config (organizacao_id, negocio_id, chave_pix, texto_promocional) select org, servnet, 'pix@servnet.com', 'Indique e ganhe 1 mês grátis' from r;
create temp table ct as select (select id from public.contratos where pessoa_id = (select joao from r)) joao, (select id from public.contratos where pessoa_id = (select igreja from r)) igreja;
grant select on ct to service_role, anon;

-- T0: defaults da config e data de nascimento
do $$ begin
  assert (select beneficio_tipo::text || '/' || tema || '/' || fidelidade_ativa::text from public.portal_config) = 'mes_gratis/escuro/true', 'T0 defaults';
  begin
    update public.pessoas set data_nascimento = date '2090-01-01' where nome = 'João da Silva';
    raise exception 'T0 nascimento futuro deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T1: fidelidade — 6 selos → 50% na 7ª competência; 12 selos → mês grátis na 13ª
do $$ declare v ct%rowtype; j jsonb; l public.lancamentos; n int; begin
  select * into v from ct;
  reset role;
  perform public.gerar_faturamento((select org from r), date '2026-02-28', 'manual');  -- 09/2025..02/2026 (6 competências)
  set local role authenticated;
  select count(*) into n from public.faturamentos where contrato_id = v.joao; assert n = 6, 'T1 6 faturas (' || n || ')';
  -- paga as 6 até o vencimento
  for l in select * from public.lancamentos where contrato_id = v.joao order by data_vencimento loop
    perform public.efetivar_lancamento(l.id, l.data_vencimento);
  end loop;
  j := public.fidelidade_cartao(v.joao, date '2026-02-28');
  assert (j->>'selos')::int = 6 and (j->>'ciclo')::int = 1 and j->>'inicio' = '2025-09-01' and jsonb_array_length(j->'slots') = 12, 'T1 6 selos: ' || j::text;
  assert j->'premios'->0->>'percentual' = '50' and j->'premios'->0->>'competencia' = '2026-03-01', 'T1 prêmio 50% em 03/2026: ' || (j->'premios')::text;
  assert j->'slots'->6->>'estado' = 'vazio', 'T1 7º slot vazio';
  -- fatura 03/2026 sai com 50%
  reset role;
  perform public.gerar_faturamento((select org from r), date '2026-03-31', 'manual');
  set local role authenticated;
  select * into l from public.lancamentos where contrato_id = v.joao and data_vencimento = date '2026-03-10';
  assert l.valor = 49.95 and l.observacao like 'Desconto aplicado: R$ 49,95 (Programa Fidelidade: 6 meses em dia (50%))%', 'T1 fatura 03/2026 com 50%: ' || l.valor || ' ' || coalesce(l.observacao,'');
  assert (select count(*) from public.descontos_contrato where contrato_id = v.joao and referencia = 'fidelidade:2025-09:50') = 1, 'T1 desconto registrado uma vez';
  -- paga 03..08/2026 em dia → 12 selos → 09/2026 grátis
  reset role;
  perform public.gerar_faturamento((select org from r), date '2026-08-31', 'manual');
  set local role authenticated;
  for l in select * from public.lancamentos where contrato_id = v.joao and status = 'previsto' order by data_vencimento loop
    perform public.efetivar_lancamento(l.id, l.data_vencimento);
  end loop;
  j := public.fidelidade_cartao(v.joao, date '2026-08-31');
  assert (j->>'selos')::int = 12 and jsonb_array_length(j->'premios') = 2 and j->'premios'->1->>'percentual' = '100' and j->'premios'->1->>'competencia' = '2026-09-01', 'T1 12 selos: ' || (j->'premios')::text;
  reset role;
  perform public.gerar_faturamento((select org from r), date '2026-09-30', 'manual');
  set local role authenticated;
  select * into l from public.lancamentos where contrato_id = v.joao and data_vencimento = date '2026-09-10';
  assert l.status = 'cancelado' and l.valor = 99.90 and l.motivo_cancelamento like 'Mês grátis: Programa Fidelidade: 12 meses em dia (100%)%', 'T1 09/2026 grátis: ' || l.status || ' ' || coalesce(l.motivo_cancelamento,'');
  assert not exists (select 1 from public.movimentos where lancamento_id = l.id), 'T1 mês grátis sem movimento';
  -- novo ciclo começa em 09/2026 e o mês grátis conta como selo
  j := public.fidelidade_cartao(v.joao, date '2026-09-30');
  assert (j->>'ciclo')::int = 2 and j->>'inicio' = '2026-09-01' and (j->>'selos')::int = 1 and j->'slots'->0->>'estado' = 'gratis', 'T1 ciclo 2: ' || j::text;
  -- prêmio de fidelidade desligado na config → não registra
  update public.portal_config set fidelidade_ativa = false;
  reset role;
  perform public.fidelidade_registrar_premio(v.joao, date '2026-03-01');
  set local role authenticated;
  assert (select count(*) from public.descontos_contrato where contrato_id = v.joao) = 2, 'T1 registrar_premio idempotente / desligado';
  update public.portal_config set fidelidade_ativa = true;
  begin
    perform public.fidelidade_registrar_premio(v.joao, date '2026-03-01');
    raise exception 'T1 cliente/admin não chama registrar_premio';
  exception when insufficient_privilege then null; end;
  -- contrato da igreja (08/2026): 1 fatura paga em atraso → sem selo
  reset role;
  perform public.gerar_faturamento((select org from r), date '2026-08-31', 'manual');
  set local role authenticated;
  select * into l from public.lancamentos where contrato_id = v.igreja and data_vencimento = date '2026-08-15';
  perform public.efetivar_lancamento(l.id, date '2026-08-20');
  j := public.fidelidade_cartao(v.igreja);
  assert (j->>'selos')::int = 0 and j->'slots'->0->>'estado' = 'atraso' and j->'slots'->1->>'estado' = 'aberto', 'T1 atraso não vale selo: ' || j::text;
end $$;

-- T2: login sem senha (só service_role) — CPF, CNPJ, erro, bloqueio após 5 falhas, sem contrato
reset role;
set local role service_role;
do $$ declare v r%rowtype; j jsonb; i int; begin
  select * into v from r;
  j := public.portal_login_verificar('529.982.247-25', date '1990-05-10');
  assert (j->>'ok')::boolean and (j->>'pessoa_id')::uuid = v.joao and j->>'nome' = 'João da Silva', 'T2 login CPF: ' || j::text;
  j := public.portal_login_verificar('11.222.333/0001-81', date '2001-03-15');
  assert (j->>'ok')::boolean and (j->>'pessoa_id')::uuid = v.igreja, 'T2 login CNPJ: ' || j::text;
  j := public.portal_login_verificar('', date '2001-03-15');
  assert not (j->>'ok')::boolean and j->>'msg' = 'Informe o CPF ou CNPJ.', 'T2 documento vazio';
  j := public.portal_login_verificar('12345678909', date '1980-01-01');
  assert not (j->>'ok')::boolean and j->>'msg' like 'Nenhum contrato ativo%', 'T2 sem contrato: ' || j::text;
  for i in 1..5 loop j := public.portal_login_verificar('52998224725', date '1991-01-01'); end loop;
  assert not (j->>'ok')::boolean and j->>'msg' like 'Muitas tentativas%', 'T2 bloqueio após 5 falhas: ' || j::text;
  j := public.portal_login_verificar('52998224725', date '1990-05-10');
  assert not (j->>'ok')::boolean and j->>'msg' like 'Muitas tentativas%', 'T2 bloqueado mesmo com dados certos';
  reset role; update public.portal_login_tentativas set bloqueado_ate = now() - interval '1 minute'; set local role service_role;
  j := public.portal_login_verificar('52998224725', date '1990-05-10');
  assert (j->>'ok')::boolean and not exists (select 1 from public.portal_login_tentativas where documento = '52998224725'), 'T2 desbloqueado limpa tentativas';
  -- vínculo do usuário técnico
  j := public.portal_vincular_servico(v.joao, '33333333-3333-3333-3333-333333333333');
  assert (j->>'pessoa_id')::uuid = v.joao and length(j->>'codigo_indicacao') = 8, 'T2 vínculo: ' || j::text;
  j := public.portal_vincular_servico(v.joao, '33333333-3333-3333-3333-333333333333');
  assert (j->>'pessoa_id')::uuid = v.joao, 'T2 vínculo idempotente';
  begin
    perform public.portal_vincular_servico(v.joao, '44444444-4444-4444-4444-444444444444');
    raise exception 'T2 outra conta para a mesma pessoa deveria falhar';
  exception when check_violation then null; end;
end $$;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ begin
  begin
    perform public.portal_login_verificar('52998224725', date '1990-05-10');
    raise exception 'T2 cliente não pode chamar portal_login_verificar';
  exception when insufficient_privilege then null; end;
end $$;

-- T3: cliente — fidelidade, faturas com mês grátis, status da rede, meus dados, chamados
do $$ declare v r%rowtype; j jsonb; s public.portal_solicitacoes; i int; begin
  select * into v from r;
  assert public.portal_pessoa() = v.joao, 'T3 vinculado';
  j := public.portal_fidelidade();
  assert jsonb_array_length(j) = 1 and (j->0->>'selos')::int = 1 and (j->0->>'ativa')::boolean and j->0->>'plano' = 'Fibra 500', 'T3 fidelidade: ' || j::text;
  assert (select count(*) from public.portal_faturas() where situacao = 'gratis') = 1, 'T3 fatura grátis visível';
  assert (select count(*) from public.portal_faturas() where situacao = 'paga') = 12, 'T3 12 pagas';
  assert (public.portal_resumo()->'pessoa'->>'tem_nascimento')::boolean, 'T3 resumo tem_nascimento';
  assert public.portal_status_rede() = '[]'::jsonb, 'T3 rede ok = vazio';
  -- meus dados
  j := public.portal_atualizar_contato('NOVO@x.com', '(11) 91111-2222', false);
  assert j->>'email' = 'novo@x.com' and j->>'telefone' = '11911112222', 'T3 contato: ' || j::text;
  j := public.portal_resumo()->'pessoa';
  assert j->>'email' = 'novo@x.com' and j->>'telefone' = '11911112222' and not (j->>'receber_avisos')::boolean, 'T3 pessoa atualizada: ' || j::text;
  begin
    perform public.portal_atualizar_contato('a@b.c', '123', true);
    raise exception 'T3 telefone inválido deveria falhar';
  exception when check_violation then null; end;
  -- chamados
  s := public.portal_solicitar(v.servnet, 'suporte', 'Internet caiu', null);
  assert s.protocolo ~ '^PT-[0-9]{8}-[A-Z0-9]{4}$' and s.status = 'aberta' and s.tipo = 'suporte', 'T3 protocolo: ' || s.protocolo;
  begin
    perform public.portal_solicitar(v.servnet, 'invalido', null, null);
    raise exception 'T3 tipo inválido deveria falhar';
  exception when invalid_text_representation then null; end;
  begin
    perform public.portal_solicitar(gen_random_uuid(), 'fatura', null, null);
    raise exception 'T3 negócio inválido deveria falhar';
  exception when check_violation then null; end;
  for i in 1..9 loop perform public.portal_solicitar(v.servnet, 'duvida', 'x' || i, null); end loop;
  begin
    perform public.portal_solicitar(v.servnet, 'duvida', 'x11', null);
    raise exception 'T3 limite diário deveria falhar';
  exception when check_violation then null; end;
  assert (select count(*) from public.portal_solicitacoes_cliente()) = 10, 'T3 cliente vê seus chamados';
  -- cliente não lê tabelas diretamente
  assert (select count(*) from public.portal_solicitacoes) = 0, 'T3 RLS: cliente não vê a tabela';
end $$;

-- T4: admin — status da rede, resposta ao chamado, view
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; begin
  select * into v from r;
  insert into public.portal_status_rede (organizacao_id, negocio_id, status, titulo, descricao) values (v.org, v.servnet, 'lentidao', 'Lentidão na região central', 'Equipe atuando');
  assert (select count(*) from public.vw_portal_solicitacoes where pessoa = 'João da Silva') = 10, 'T4 view de chamados';
  update public.portal_solicitacoes set status = 'concluida', resposta = 'Resolvido' where descricao = 'Internet caiu';
  begin
    insert into public.portal_status_rede (organizacao_id, negocio_id, status) values (v.org, v.servnet, 'ok');
    raise exception 'T4 um status por negócio';
  exception when unique_violation then null; end;
end $$;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ declare j jsonb; begin
  j := public.portal_status_rede();
  assert jsonb_array_length(j) = 1 and j->0->>'status' = 'lentidao' and j->0->>'negocio' = 'SERVNET', 'T4 cliente vê status: ' || j::text;
  assert (select count(*) from public.portal_solicitacoes_cliente() where status = 'concluida' and resposta = 'Resolvido') = 1, 'T4 cliente vê resposta';
end $$;
-- T5: usuário sem vínculo não vê nada
set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
do $$ begin
  assert public.portal_fidelidade() = '[]'::jsonb and public.portal_status_rede() = '[]'::jsonb and (select count(*) from public.portal_solicitacoes_cliente()) = 0, 'T5 sem vínculo';
  begin
    perform public.portal_atualizar_contato('a@b.c', '11911112222', true);
    raise exception 'T5 sem vínculo não atualiza';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo OK
