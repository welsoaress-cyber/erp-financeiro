-- Testes da migration 0067 (patrimônio). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

do $$ declare v_org uuid; v_neg uuid; v_p uuid; v_p2 uuid; begin
  select id into v_org from public.organizacoes limit 1;
  insert into public.negocios (organizacao_id, nome, slug, ativo) values (v_org, 'PATRI T', 'patri-t', true) returning id into v_neg;

  -- T1: cadastro numera sozinho (1, 2) e grava histórico
  insert into public.patrimonios (organizacao_id, negocio_id, nome, localizacao, valor_aquisicao, numero_serie, numero)
  values (v_org, v_neg, 'Fusionadora X1', 'POP Central', 8500, 'FUS-001', 0) returning id into v_p;
  insert into public.patrimonios (organizacao_id, negocio_id, nome, localizacao, valor_aquisicao, numero)
  values (v_org, v_neg, 'Estante gaveteiro', 'Escritório', 398.88, 0) returning id into v_p2;
  assert (select numero from public.patrimonios where id = v_p) = 1, 'T1 numero 1';
  assert (select numero from public.patrimonios where id = v_p2) = 2, 'T1 numero 2';
  assert (select count(*) from public.patrimonio_historico where patrimonio_id = v_p and evento = 'cadastro') = 1, 'T1 histórico de cadastro';

  -- T2: transferência e estado geram histórico automático
  update public.patrimonios set localizacao = 'Veículo Fiorino' where id = v_p;
  update public.patrimonios set estado = 'regular' where id = v_p;
  assert (select count(*) from public.patrimonio_historico where patrimonio_id = v_p and evento = 'transferencia') = 1, 'T2 transferência no histórico';
  assert (select detalhe from public.patrimonio_historico where patrimonio_id = v_p and evento = 'estado') = 'bom → regular', 'T2 estado no histórico';

  -- T3: baixa (venda) registra e congela o bem
  update public.patrimonios set status = 'vendido', observacao = 'Vendida usada' where id = v_p;
  assert (select count(*) from public.patrimonio_historico where patrimonio_id = v_p and evento = 'baixa') = 1, 'T3 baixa no histórico';
  begin
    update public.patrimonios set localizacao = 'Outro lugar' where id = v_p;
    raise exception 'T3 baixado não deveria editar';
  exception when check_violation then null; end;

  -- T4: histórico imutável (sem grant de update/delete para o cliente)
  begin
    delete from public.patrimonio_historico where patrimonio_id = v_p;
    raise exception 'T4 delete no histórico deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    update public.patrimonio_historico set detalhe = 'x' where patrimonio_id = v_p;
    raise exception 'T4 update no histórico deveria falhar';
  exception when insufficient_privilege then null; end;
  assert (select count(*) from public.patrimonio_historico where patrimonio_id = v_p) = 4, 'T4 histórico intacto';
end $$;

-- T5: fora da organização não vê
set local request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
do $$ begin
  assert (select count(*) from public.patrimonios) = 0, 'T5 RLS por organização';
end $$;

rollback;
\echo OK
