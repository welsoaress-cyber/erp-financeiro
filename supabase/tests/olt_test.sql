-- Testes da migration 0062 (monitoramento da OLT). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare v_org uuid; v_neg uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'OLT T', 'olt-t', true) returning id into v_neg;
  insert into public.notificacoes_config (organizacao_id, negocio_id, numero_whatsapp, ativo) values (v_org, v_neg, '+5592999990002', true);
  insert into public.ctos (organizacao_id, negocio_id, codigo, latitude, longitude, quantidade_portas, tipo, olt_ip) values (v_org, v_neg, 'POP-OLT', -3.0, -60.0, 1, 'pop', '10.0.0.9');
end $$;
set local role service_role;
do $$ declare r jsonb; begin
  r := public.olt_registrar_ping('pop-olt', true, 4);
  assert (r->>'ok') = 'true' and (r->>'mudou') = 'true' and (r->>'avisar') = 'false', 'T1 primeiro ping não avisa: ' || r::text;
  r := public.olt_registrar_ping('POP-OLT', true, 6);
  assert (r->>'mudou') = 'false', 'T1 sem mudança';
  r := public.olt_registrar_ping('POP-OLT', false, null);
  assert (r->>'mudou') = 'true', 'T1 queda detectada';
  r := public.olt_registrar_ping('POP-XX', true);
  assert (r->>'ok') = 'false', 'T1 pop desconhecido';
end $$;
set local role authenticated;
do $$ declare n int; begin
  select count(*) into n from public.olt_eventos; assert n = 2, 'T2 só mudanças no histórico: ' || n;
  assert (select online from public.olt_status limit 1) = false, 'T2 estado atual offline';
end $$;
rollback;
\echo OK
