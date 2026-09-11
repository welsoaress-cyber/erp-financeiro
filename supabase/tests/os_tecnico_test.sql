-- Testes da migration 0056 (acesso restrito do técnico). Saída "OK".
\set ON_ERROR_STOP on
begin;
-- T0: usuário com metadata tecnico=true não ganha organização própria (como superusuário, antes do role)
do $$ declare n0 int; n1 int; begin
  select count(*) into n0 from public.organizacoes;
  insert into auth.users (id, email, raw_user_meta_data) values ('22222222-2222-2222-2222-222222222222', 'joao2@tecnico.local', '{"tecnico":"true","nome":"João"}');
  insert into auth.users (id, email, raw_user_meta_data) values ('32222222-2222-2222-2222-222222222223', 'maria2@tecnico.local', '{"tecnico":"true","nome":"Maria"}');
  select count(*) into n1 from public.organizacoes;
  assert n1 = n0, 'T0 técnico não cria organização';
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

-- setup como admin: negócio, itens, técnicos (João logado, Maria não), cliente, contrato, OS
do $$ declare v_org uuid; v_neg uuid; v_cat uuid; v_item uuid; v_p uuid; v_pt uuid; v_pt2 uuid; v_plano uuid; v_conta uuid; v_tec uuid; v_tec2 uuid; v_ct uuid; os public.ordens_servico; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'TEC TESTE', 'tec-teste', true) returning id into v_neg;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Cabos Tec') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'TEC-CABO', 'Cabo tec', 'metro') returning id into v_item;
  perform public.entrada_estoque(v_item, 500, 500, current_date, 'compra');
  insert into public.pessoas (organizacao_id, nome, telefone, endereco) values (v_org, 'Cliente Tec', '92988887777', 'Rua A, 10') returning id into v_p;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'João Técnico') returning id into v_pt;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Maria Técnica') returning id into v_pt2;
  insert into public.tecnicos (organizacao_id, negocio_id, pessoa_id, usuario_id, nome, login) values (v_org, v_neg, v_pt, '22222222-2222-2222-2222-222222222222', 'João Técnico', 'joao') returning id into v_tec;
  insert into public.tecnicos (organizacao_id, negocio_id, pessoa_id, nome) values (v_org, v_neg, v_pt2, 'Maria Técnica') returning id into v_tec2;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano Tec', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Tec', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id)
  values (v_org, v_neg, v_p, v_plano, 100, 'mensal', current_date, 10, v_conta) returning id into v_ct;
  perform public.abastecer_tecnico(v_tec, v_item, 100);
  os := public.abrir_os(v_neg, 'instalacao', 'Instalar cliente tec', v_p, v_ct, v_tec);
  os := public.abrir_os(v_neg, 'vistoria', 'Vistoria da maria', null, null, v_tec2);
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.tecnicos where login='joao') tec,
  (select id from public.tecnicos where nome='Maria Técnica') tec2,
  (select id from public.estoque_itens where codigo='TEC-CABO') item,
  (select id from public.ordens_servico where descricao='Instalar cliente tec') os_joao,
  (select id from public.ordens_servico where descricao='Vistoria da maria') os_maria;

-- T1: como técnico João — vê só o que é dele; ERP invisível
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  select count(*) into n from public.ordens_servico; assert n = 1, 'T1 vê só o próprio chamado: ' || n;
  select count(*) into n from public.tecnicos; assert n = 1, 'T1 vê só o próprio cadastro';
  select count(*) into n from public.tecnico_estoque; assert n = 1, 'T1 vê a própria bolsa';
  select count(*) into n from public.estoque_itens; assert n >= 1, 'T1 vê itens do negócio (nomes)';
  select count(*) into n from public.pessoas; assert n = 0, 'T1 pessoas invisíveis: ' || n;
  select count(*) into n from public.lancamentos; assert n = 0, 'T1 lançamentos invisíveis';
  select count(*) into n from public.contas; assert n = 0, 'T1 contas invisíveis';
  select count(*) into n from public.contratos; assert n = 0, 'T1 contratos invisíveis';
  select count(*) into n from public.estoque_movimentacoes; assert n = 0, 'T1 estoque central invisível';
end $$;

-- T2: ações permitidas e proibidas do técnico
do $$ declare v r%rowtype; os public.ordens_servico; info record; n int; begin
  select * into v from r;
  -- proibidas
  begin
    perform public.abrir_os((select negocio_id from public.tecnicos where id = v.tec), 'reparo', 'nao posso');
    raise exception 'T2 técnico abrindo chamado deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    perform public.abastecer_tecnico(v.tec, v.item, 10);
    raise exception 'T2 técnico abastecendo deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    perform public.ciencia_os(v.os_maria);
    raise exception 'T2 agir no chamado de outro deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    perform public.perda_tecnico(v.tec2, v.item, 1, false, 'nao é meu');
    raise exception 'T2 perda na bolsa de outro deveria falhar';
  exception when insufficient_privilege then null; end;
  -- permitidas: fluxo completo no próprio chamado
  perform public.ciencia_os(v.os_joao);
  perform public.agendar_os(v.os_joao, current_date, '08:00');
  perform public.iniciar_os(v.os_joao);
  info := public.os_info_cliente(v.os_joao);
  assert info.cliente = 'Cliente Tec' and info.telefone = '92988887777' and info.contrato is not null, 'T2 dados mínimos do cliente';
  perform public.registrar_foto_os(v.os_joao, 'os/' || v.os_joao || '/1.jpg');
  begin
    perform public.registrar_foto_os(v.os_joao, 'errado/1.jpg');
    raise exception 'T2 caminho de foto inválido deveria falhar';
  exception when check_violation then null; end;
  os := public.encerrar_os(v.os_joao, jsonb_build_array(jsonb_build_object('item_id', v.item, 'quantidade', 40)), 'outro', -19);
  assert os.status = 'encerrado', 'T2 técnico encerra o próprio chamado';
  assert (select quantidade from public.tecnico_estoque where tecnico_id = v.tec) = 60, 'T2 bolsa consumida';
  begin
    perform public.avaliar_os(v.os_joao, true, 5);
    raise exception 'T2 técnico avaliando deveria falhar';
  exception when insufficient_privilege then null; end;
  -- perda própria e reposição
  perform public.perda_tecnico(v.tec, v.item, 5, false, 'conector danificado');
  perform public.solicitar_reposicao(v.item, 50);
  select count(*) into n from public.reposicao_solicitacoes where tecnico_id = v.tec and not atendida;
  assert n = 1, 'T2 reposição pendente';
end $$;

-- T3: admin atende a reposição (abastecer marca atendida); fotos limitadas a 3
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  perform public.abastecer_tecnico(v.tec, v.item, 50);
  select count(*) into n from public.reposicao_solicitacoes where tecnico_id = v.tec and not atendida;
  assert n = 0, 'T3 reposição atendida no abastecimento';
  perform public.registrar_foto_os(v.os_joao, 'os/' || v.os_joao || '/2.jpg');
  perform public.registrar_foto_os(v.os_joao, 'os/' || v.os_joao || '/3.jpg');
  begin
    perform public.registrar_foto_os(v.os_joao, 'os/' || v.os_joao || '/4.jpg');
    raise exception 'T3 quarta foto deveria falhar';
  exception when check_violation then null; end;
  assert (select count(*) from public.os_fotos where os_id = v.os_joao) = 3, 'T3 fotos registradas';
end $$;

-- T4: admin segue vendo tudo (política do técnico não estreitou nada)
do $$ declare v r%rowtype; n int; begin
  select * into v from r;
  select count(*) into n from public.ordens_servico where organizacao_id = v.org; assert n >= 2, 'T4 admin vê todos os chamados';
  select count(*) into n from public.tecnicos where organizacao_id = v.org; assert n = 2, 'T4 admin vê os técnicos';
end $$;

rollback;
\echo OK
