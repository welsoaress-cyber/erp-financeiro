-- Testes da migration 0065 (natureza operacional × investimento). Saída "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T1: padrão operacional; marcar investimento; filha grava a natureza escolhida
do $$ declare v_org uuid; v_pai uuid; v_filha uuid; begin
  select organizacao_id into v_org from public.categorias limit 1;
  insert into public.categorias (organizacao_id, nome, tipo) values (v_org, 'Nat Padrão', 'despesa') returning id into v_pai;
  assert (select natureza from public.categorias where id = v_pai) = 'operacional', 'T1 padrão operacional';
  update public.categorias set natureza = 'investimento' where id = v_pai;
  assert (select natureza from public.categorias where id = v_pai) = 'investimento', 'T1 marcada investimento';
  insert into public.categorias (organizacao_id, nome, tipo, categoria_pai_id, natureza) values (v_org, 'Nat Filha', 'despesa', v_pai, 'investimento') returning id into v_filha;
  assert (select natureza from public.categorias where id = v_filha) = 'investimento', 'T1 filha investimento';
  insert into public.categorias (organizacao_id, nome, tipo, categoria_pai_id, natureza) values (v_org, 'Nat Filha Op', 'despesa', v_pai, 'operacional');
  assert (select natureza from public.categorias where nome = 'Nat Filha Op') = 'operacional', 'T1 filha pode divergir do pai';
end $$;

-- T2: valor inválido é barrado pelo enum
do $$ begin
  begin
    update public.categorias set natureza = 'outra' where nome = 'Nat Padrão';
    raise exception 'T2 deveria barrar natureza inválida';
  exception when invalid_text_representation then null; end;
end $$;

rollback;
\echo OK
