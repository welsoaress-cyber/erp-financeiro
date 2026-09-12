-- Testes da migration 0074 (vitrine de prêmios no portal). Saída "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('77777777-7777-7777-7777-777777777777', 'vitrine@teste.dev', '{"portal":"true"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- cenário: negócio com portal e notificações; brindes com e sem saldo; item fora de Brindes
do $$ declare v_org uuid; v_neg uuid; v_ind uuid; v_plano uuid; v_conta uuid; v_cat uuid; v_out uuid; p1 uuid; p2 uuid; p3 uuid; nb uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'VITRINE T', 'vitrine-t', true) returning id into v_neg;
  insert into public.portal_config (organizacao_id, negocio_id, ativo, url_portal) values (v_org, v_neg, true, 'https://portal.exemplo.dev');
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v_org, v_neg, '+5511954490003', true);
  insert into public.pessoas (organizacao_id, nome, telefone) values (v_org, 'Indicante V', '11933330001') returning id into v_ind;
  insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade) values (v_org, v_neg, '200 Mb', 80, 'mensal') returning id into v_plano;
  insert into public.contas (organizacao_id, nome, tipo, negocio_id) values (v_org, 'Caixa Vit', 'dinheiro', v_neg) returning id into v_conta;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Brindes') returning id into v_cat;
  insert into public.estoque_categorias (organizacao_id, negocio_id, nome) values (v_org, v_neg, 'Materiais') returning id into v_out;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'VT-CX', 'Caixa de som', 'unidade') returning id into p1;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'VT-FONE', 'Fone bluetooth', 'unidade') returning id into p2;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_cat, 'VT-SMART', 'Smartwatch', 'unidade') returning id into p3;
  insert into public.estoque_itens (organizacao_id, negocio_id, categoria_id, codigo, nome, unidade_medida) values (v_org, v_neg, v_out, 'VT-ROT', 'Roteador', 'unidade') returning id into nb;
  perform public.ajuste_estoque(p1, 5, 100, 'custo 20');
  perform public.ajuste_estoque(p2, 3, 135, 'custo 45');
  -- VT-SMART fica com saldo zero de propósito
end $$;
create temp table r as select
  (select organizacao_id from public.negocios where slug='vitrine-t') org,
  (select id from public.negocios where slug='vitrine-t') neg,
  (select id from public.pessoas where nome='Indicante V') ind,
  (select id from public.estoque_itens where codigo='VT-CX') cx,
  (select id from public.estoque_itens where codigo='VT-FONE') fone,
  (select id from public.estoque_itens where codigo='VT-SMART') smart,
  (select id from public.estoque_itens where codigo='VT-ROT') rot;
grant select on r to service_role;

-- T1: faixas configuráveis — cadastro, unicidade por negócio e validações
do $$ declare v r%rowtype; begin
  select * into v from r;
  insert into public.indicacao_faixas (organizacao_id, negocio_id, faixa, nome, plano_ate, teto) values
    (v.org, v.neg, 1, 'Até 100 Mb', 60, 30),
    (v.org, v.neg, 2, '200 Mb', 80, 50),
    (v.org, v.neg, 3, '300 Mb', null, 80);
  begin
    insert into public.indicacao_faixas (organizacao_id, negocio_id, faixa, nome, plano_ate, teto) values (v.org, v.neg, 2, 'Repetida', 90, 60);
    raise exception 'T1 faixa repetida deveria falhar';
  exception when unique_violation then null; end;
  begin
    insert into public.indicacao_faixas (organizacao_id, negocio_id, faixa, nome, plano_ate, teto) values (v.org, v.neg, 4, 'Teto zero', null, 0);
    raise exception 'T1 teto zero deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T2: prêmios — item precisa ser da categoria Brindes; foto só data URL
do $$ declare v r%rowtype; begin
  select * into v from r;
  insert into public.indicacao_premios (organizacao_id, negocio_id, nome, foto, faixa, item_id)
  values (v.org, v.neg, 'Fone Bluetooth Pro', 'data:image/jpeg;base64,QUJD', 2, v.fone);
  insert into public.indicacao_premios (organizacao_id, negocio_id, nome, faixa, item_id) values (v.org, v.neg, 'Smartwatch Fit', 2, v.smart);
  insert into public.indicacao_premios (organizacao_id, negocio_id, nome, faixa, item_id) values (v.org, v.neg, 'Caixa de Som', 1, v.cx);
  begin
    insert into public.indicacao_premios (organizacao_id, negocio_id, nome, faixa, item_id) values (v.org, v.neg, 'Roteador de brinde', 1, v.rot);
    raise exception 'T2 item fora de Brindes deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.indicacao_premios (organizacao_id, negocio_id, nome, foto, faixa, item_id) values (v.org, v.neg, 'Foto ruim', 'https://x/foto.jpg', 1, v.cx);
    raise exception 'T2 foto sem data URL deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T3: conversão resolve a faixa pela config e dispara o aviso WhatsApp com o link
do $$ declare v r%rowtype; i public.indicacoes%rowtype; v_novo uuid; v_plano uuid; v_conta uuid; g public.notificacoes_log%rowtype; begin
  select * into v from r;
  i := public.criar_indicacao_admin(v.neg, v.ind, 'Amigo Vitrine', '11933330002');
  select id into v_plano from public.planos where negocio_id = v.neg;
  select id into v_conta from public.contas where negocio_id = v.neg;
  insert into public.pessoas (organizacao_id, nome, telefone) values (v.org, 'Amigo Vitrine', '11933330002') returning id into v_novo;
  insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento, conta_id, faturamento_automatico)
  values (v.org, v.neg, v_novo, v_plano, 80, 'mensal', current_date, 10, v_conta, false);
  perform public.converter_indicacao(i.id, v_novo);
  assert (select faixa from public.faixa_da_indicacao(i.id)) = 2 and (select teto from public.faixa_da_indicacao(i.id)) = 50, 'T3 faixa 2 pela config';
  select * into g from public.notificacoes_log where pessoa_id = v.ind and tipo = 'indicacao_convertida';
  assert g.id is not null and g.numero_destino = '+5511933330001', 'T3 aviso ao indicante';
  assert position('https://portal.exemplo.dev' in g.mensagem) > 0, 'T3 link do portal na mensagem';
end $$;

-- T4: vitrine no portal — só prêmios da faixa com saldo; escolha grava prêmio e trava
reset role;
do $$ declare v r%rowtype; begin
  select * into v from r;
  perform public.portal_vincular_servico(v.ind, '77777777-7777-7777-7777-777777777777');
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
do $$ declare v r%rowtype; i_id uuid; begin
  select * into v from r;
  select id into i_id from public.portal_indicacoes() where aguardando_escolha limit 1;
  assert i_id is not null, 'T4 aguardando escolha';
  assert (select count(*) from public.portal_presentes_indicacao(i_id)) = 1, 'T4 só o prêmio da faixa com saldo';
  assert (select nome from public.portal_presentes_indicacao(i_id)) = 'Fone Bluetooth Pro'
     and (select foto from public.portal_presentes_indicacao(i_id)) like 'data:image/%', 'T4 prêmio com foto';
  begin
    perform public.portal_escolher_presente(i_id, v.cx);
    raise exception 'T4 prêmio de outra faixa deveria falhar';
  exception when check_violation then null; end;
  perform public.portal_escolher_presente(i_id, v.fone);
  assert (select presente from public.portal_indicacoes() where id = i_id) = 'Fone Bluetooth Pro'
     and (select presente_foto from public.portal_indicacoes() where id = i_id) is not null, 'T4 escolha gravada com prêmio';
  begin
    perform public.portal_escolher_presente(i_id, v.fone);
    raise exception 'T4 trocar deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T5: vitrine pública sem login (anon) — nome/foto/faixa; sem saldo não aparece
set local role anon;
do $$ declare j jsonb; begin
  j := public.vitrine_publica('vitrine-t');
  assert j->>'negocio' = 'VITRINE T', 'T5 negócio';
  assert jsonb_array_length(j->'faixas') = 3, 'T5 três faixas';
  assert jsonb_array_length(j->'premios') = 2, 'T5 smartwatch sem saldo fora: ' || (j->'premios')::text;
  assert public.vitrine_publica('nao-existe') is null, 'T5 slug inválido';
end $$;

rollback;
\echo OK
