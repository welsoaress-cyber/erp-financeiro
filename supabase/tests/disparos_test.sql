-- Testes da migration 0042 (disparos WhatsApp). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;

-- cenário: negócio com config evolution ativa + 2 pessoas com login/telefone e 1 sem telefone
do $$ declare v_org uuid; v_neg uuid; begin
  select org into v_org from ids;
  insert into public.negocios (organizacao_id, nome, slug) values (v_org, 'DISPARO TESTE', 'disparo-teste') returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo, provedor, instancia)
  values (v_org, v_neg, '+5514996560000', true, 'evolution', 'servidor');
  insert into public.pessoas (organizacao_id, nome, telefone, login_servidor) values
    (v_org, 'Cliente Disparo A', '(14) 99656-0001', 'clientea01'),
    (v_org, 'Cliente Disparo B', '(14) 99656-0002', 'clienteb02');
  insert into public.pessoas (organizacao_id, nome, login_servidor) values (v_org, 'Cliente Sem Fone', 'semfone03');
end $$;
create temp table r as select (select org from ids) org,
  (select id from public.negocios where slug='disparo-teste') neg,
  (select id from public.pessoas where login_servidor='clientea01') pa,
  (select id from public.pessoas where login_servidor='clienteb02') pb,
  (select id from public.pessoas where login_servidor='semfone03') psem;

-- T1: modelos padrão criados pela migration + login único por organização
do $$ declare v r%rowtype; begin
  select * into v from r;
  assert (select count(*) from public.disparo_modelos where organizacao_id = v.org and nome in ('Lembrete de vencimento','Interrupção no serviço')) = 2, 'T1 modelos padrão';
  begin
    insert into public.pessoas (organizacao_id, nome, login_servidor) values (v.org, 'Duplicado', 'CLIENTEA01');
    raise exception 'T1 login duplicado deveria falhar';
  exception when unique_violation then null; end;
end $$;

-- T2: criar_disparo gera itens pendentes com número E.164
do $$ declare v r%rowtype; d public.disparos; begin
  select * into v from r;
  d := public.criar_disparo(v.neg, 'Lembrete de vencimento', jsonb_build_array(
        jsonb_build_object('pessoa_id', v.pa, 'mensagem', 'Olá Cliente A, lembrete de vencimento.'),
        jsonb_build_object('pessoa_id', v.pb, 'mensagem', 'Olá Cliente B, lembrete de vencimento.')));
  assert (select count(*) from public.disparo_itens where disparo_id = d.id and status = 'pendente') = 2, 'T2 itens pendentes';
  assert (select numero_destino from public.disparo_itens where disparo_id = d.id and pessoa_id = v.pa) = '+5514996560001', 'T2 E.164';
end $$;

-- T3: validações — sem telefone, mais de 30, escrita direta bloqueada
do $$ declare v r%rowtype; v_itens jsonb; begin
  select * into v from r;
  begin
    perform public.criar_disparo(v.neg, 'x', jsonb_build_array(jsonb_build_object('pessoa_id', v.psem, 'mensagem', 'mensagem de teste valida')));
    raise exception 'T3 sem telefone deveria falhar';
  exception when check_violation then null; end;
  select jsonb_agg(jsonb_build_object('pessoa_id', v.pa, 'mensagem', 'mensagem de teste valida')) into v_itens from generate_series(1, 31);
  begin
    perform public.criar_disparo(v.neg, 'x', v_itens);
    raise exception 'T3 31 itens deveria falhar';
  exception when check_violation then null; end;
  perform set_config('erp.motor', '', true); -- a flag fica ligada na transação após criar_disparo
  begin
    insert into public.disparos (organizacao_id, negocio_id, modelo_nome) values (v.org, v.neg, 'direto');
    raise exception 'T3 escrita direta deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T4: fila para envio (service_role) e resultado; reenviar falhas
do $$ declare v r%rowtype; d public.disparos; v_id uuid; v_n int; begin
  select * into v from r;
  d := public.criar_disparo(v.neg, 'Lembrete de vencimento', jsonb_build_array(jsonb_build_object('pessoa_id', v.pa, 'mensagem', 'mensagem para fila de envio')));
  reset role;
  assert (select count(*) from public.disparos_para_envio(50)) >= 1, 'T4 fila com pendentes';
  select id into v_id from public.disparo_itens where disparo_id = d.id;
  perform public.registrar_resultado_disparo(v_id, false, 'falha 1', null, true);
  perform public.registrar_resultado_disparo(v_id, false, 'f2', null, true);
  perform public.registrar_resultado_disparo(v_id, false, 'f3', null, true);
  perform public.registrar_resultado_disparo(v_id, false, 'f4', null, true);
  perform public.registrar_resultado_disparo(v_id, false, 'f5', null, true);
  assert (select status from public.disparo_itens where id = v_id) = 'erro', 'T4 erro após 5 tentativas';
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
  select public.reenviar_falhas_disparo(d.id) into v_n;
  assert v_n = 1 and (select status from public.disparo_itens where id = v_id) = 'pendente', 'T4 reenvio de falha';
  reset role;
  perform public.registrar_resultado_disparo(v_id, true, null, '{"ok":true}'::jsonb, true);
  assert (select status from public.disparo_itens where id = v_id) = 'enviado', 'T4 enviado';
  set local role authenticated;
  set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
end $$;

rollback;
\echo OK
