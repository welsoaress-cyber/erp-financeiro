-- Testes da migration 0066 (Indique e Ganhe com presente). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('88888888-8888-8888-8888-888888888888', 'indicante@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- cenário: negócio, indicante, cliente antigo, plano 100 (faixa 50–80), brindes de 3 faixas
do $$ declare v_org uuid; v_neg uuid; v_ind uuid; v_cli uuid; v_plano uuid; v_conta uuid; v_cat uuid; a uuid; b uuid; c uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'INDICA T', 'indica-t', true) returning id into v_neg;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Indicante T', '11911110001') returning id into v_ind;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Cliente Antigo T', '11911110002') returning id into v_cli;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, 'Plano 300mb', 100, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Ind', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, faturamento_automatico)
  values (v_org, v_neg, v_cli, v_plano, 100, 'mensal', current_date, 10, v_conta, false);
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Brindes') returning id into v_cat;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'BR-JOGO', 'Jogo tabuleiro', 'unidade') returning id into a;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'BR-SUP', 'Mini game SUP', 'unidade') returning id into b;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'BR-X9', 'Console X9', 'unidade') returning id into c;
  perform public.ajuste_estoque(a, 5, 125, 'custo 25 — faixa até 30');
  perform public.ajuste_estoque(b, 5, 200, 'custo 40 — faixa 30–50');
  perform public.ajuste_estoque(c, 2, 150, 'custo 75 — faixa 50–80');
end $$;
create temp table r as select
  (select id from public.negocios where slug='indica-t') neg,
  (select id from public.pessoas where nome='Indicante T') ind,
  (select id from public.estoque_itens where codigo='BR-JOGO') jogo,
  (select id from public.estoque_itens where codigo='BR-SUP') sup,
  (select id from public.estoque_itens where codigo='BR-X9') x9;
grant select on r to service_role;

-- T1: admin registra indicação; telefone repetido e telefone de cliente são barrados
do $$ declare v r%rowtype; i public.indicacoes%rowtype; begin
  select * into v from r;
  i := public.criar_indicacao_admin(v.neg, v.ind, 'Vizinho Novo', '(11) 92222-0001');
  assert i.status = 'pendente' and i.telefone_indicado = '11922220001', 'T1 indicação criada';
  begin
    perform public.criar_indicacao_admin(v.neg, v.ind, 'Vizinho Novo', '11922220001');
    raise exception 'T1 telefone repetido deveria falhar';
  exception when check_violation then null; end;
  begin
    perform public.criar_indicacao_admin(v.neg, v.ind, 'Cliente Antigo', '11911110002');
    raise exception 'T1 telefone de cliente deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T2: converter carimba convertida_em; indicado fecha plano de 100 → faixa 50–80 (só o X9)
do $$ declare v r%rowtype; i public.indicacoes%rowtype; v_novo uuid; v_org uuid; v_plano uuid; v_conta uuid; begin
  select * into v from r;
  select organizacao_id into v_org from public.negocios where id = v.neg;
  select id into v_plano from public.planos where negocio_id = v.neg;
  select id into v_conta from public.contas where negocio_id = v.neg;
  select * into i from public.indicacoes where telefone_indicado = '11922220001';
  begin
    perform public.escolher_presente_indicacao(i.id, v.x9);
    raise exception 'T2 escolher antes de converter deveria falhar';
  exception when check_violation then null; end;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Vizinho Novo', '11922220001') returning id into v_novo;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, faturamento_automatico)
  values (v_org, v.neg, v_novo, v_plano, 100, 'mensal', current_date, 10, v_conta, false);
  perform public.converter_indicacao(i.id, v_novo);
  select * into i from public.indicacoes where id = i.id;
  assert i.convertida_em is not null, 'T2 convertida_em carimbado';
  assert (select teto from public.faixa_presente_indicacao(i.id)) = 80 and (select piso from public.faixa_presente_indicacao(i.id)) = 50, 'T2 faixa 50–80';
end $$;

-- T3: no portal, o indicante vê só o presente da faixa e escolhe uma única vez
reset role;
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.portal_vincular_servico(v.ind, '88888888-8888-8888-8888-888888888888');
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
do $$ declare v r%rowtype; i_id uuid; begin
  select * into v from r;
  select id into i_id from public.portal_indicacoes() where aguardando_escolha limit 1;
  assert i_id is not null, 'T3 indicação aguardando escolha no portal';
  assert (select count(*) from public.portal_presentes_indicacao(i_id)) = 1, 'T3 só o item da faixa aparece';
  assert (select item_id from public.portal_presentes_indicacao(i_id)) = v.x9, 'T3 item da faixa é o X9';
  begin
    perform public.portal_escolher_presente(i_id, v.jogo);
    raise exception 'T3 item fora da faixa deveria falhar';
  exception when check_violation then null; end;
  perform public.portal_escolher_presente(i_id, v.x9);
  begin
    perform public.portal_escolher_presente(i_id, v.x9);
    raise exception 'T3 trocar/escolher de novo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: admin entrega — baixa 1 do estoque como brinde e congela o custo; sem repetição
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v r%rowtype; i public.indicacoes%rowtype; q numeric; begin
  select * into v from r;
  select * into i from public.indicacoes where telefone_indicado = '11922220001';
  i := public.entregar_presente_indicacao(i.id, 'Entregue em mãos, foto no grupo');
  assert i.presente_entregue_em = current_date and i.presente_custo = 75.00, 'T4 entrega com custo congelado';
  select quantidade_atual into q from public.estoque_itens where id = v.x9;
  assert q = 1, 'T4 baixa de 1 unidade';
  assert exists (select 1 from public.estoque_movimentacoes where item_id = v.x9 and origem = 'brinde' and pessoa_id = v.ind), 'T4 movimentação brinde';
  begin
    perform public.entregar_presente_indicacao(i.id, null);
    raise exception 'T4 entregar duas vezes deveria falhar';
  exception when check_violation then null; end;
end $$;

rollback;
\echo OK
