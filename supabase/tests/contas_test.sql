-- Testes da migration 0002 (contas). Executar após 0001 e 0002. Saída final "OK".
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ana@teste.dev',   '{"nome":"Ana"}'),
  ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T1: criar conta com sucesso (defaults: saldo 0, data hoje, ativa)
insert into public.contas (organizacao_id, nome, tipo)
  select id, 'Nubank', 'corrente' from public.organizacoes;
do $$
declare c record;
begin
  select * into c from public.contas where nome = 'Nubank';
  assert c.saldo_inicial = 0 and c.data_inicio = current_date and c.ativo, 'T1 defaults';
end $$;

-- T2: validações no banco
do $$
declare v_org uuid;
begin
  select id into v_org from public.organizacoes;
  begin
    insert into public.contas (organizacao_id, nome, tipo) values (v_org, '   ', 'corrente');
    raise exception 'T2 nome vazio deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.contas (organizacao_id, nome, tipo) values (v_org, 'X', 'cartao');
    raise exception 'T2 tipo inválido deveria falhar';
  exception when invalid_text_representation then null; end;
  begin
    insert into public.contas (organizacao_id, nome, tipo, saldo_inicial) values (v_org, 'Y', 'dinheiro', -1);
    raise exception 'T2 saldo negativo deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.contas (organizacao_id, nome, tipo) values (v_org, ' nubank ', 'poupanca');
    raise exception 'T2 nome duplicado deveria falhar';
  exception when unique_violation then null; end;
end $$;

-- T3: editar nome e saldo inicial (sem movimentos) funciona; tipo não pode mudar
update public.contas set nome = 'Nubank Conta', saldo_inicial = 150.50 where nome = 'Nubank';
do $$
declare n int;
begin
  select count(*) into n from public.contas where nome = 'Nubank Conta' and saldo_inicial = 150.50; assert n = 1, 'T3 update';
  begin
    update public.contas set tipo = 'poupanca' where nome = 'Nubank Conta';
    raise exception 'T3 mudar tipo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: inativar sem movimentos funciona; reativar funciona
update public.contas set ativo = false where nome = 'Nubank Conta';
update public.contas set ativo = true  where nome = 'Nubank Conta';
do $$ declare n int; begin
  select count(*) into n from public.contas where nome = 'Nubank Conta' and ativo; assert n = 1, 'T4 reativar';
end $$;

-- T5: exclusão física negada
do $$ begin
  begin
    delete from public.contas;
    raise exception 'T5 delete deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T6: RLS — Bruno não vê nem consegue criar conta na organização da Ana
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$
declare n int; v_org_ana uuid;
begin
  select count(*) into n from public.contas; assert n = 0, 'T6 select alheio';
  reset role; -- pega o id da org da Ana como superusuário
  select organizacao_id into v_org_ana from public.organizacao_membros where usuario_id = '11111111-1111-1111-1111-111111111111';
  set local role authenticated;
  begin
    insert into public.contas (organizacao_id, nome, tipo) values (v_org_ana, 'Invasao', 'dinheiro');
    raise exception 'T6 insert alheio deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T7: com movimentos (simulação da tabela da Etapa 5), inativar e alterar saldo inicial são bloqueados
reset role;
create table public.movimentos (id uuid primary key default gen_random_uuid(), conta_id uuid not null references public.contas (id));
insert into public.movimentos (conta_id) select id from public.contas where nome = 'Nubank Conta';
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  begin
    update public.contas set ativo = false where nome = 'Nubank Conta';
    raise exception 'T7 inativar com movimentos deveria falhar';
  exception when check_violation then null; end;
  begin
    update public.contas set saldo_inicial = 1 where nome = 'Nubank Conta';
    raise exception 'T7 alterar saldo inicial com movimentos deveria falhar';
  exception when check_violation then null; end;
  update public.contas set nome = 'Nubank Renomeada' where nome = 'Nubank Conta'; -- renomear continua permitido
end $$;

-- T8: auditoria registrou INSERT e UPDATEs da conta com usuario_id
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'contas' and acao = 'INSERT' and usuario_id = '11111111-1111-1111-1111-111111111111'; assert n = 1, 'T8 insert';
  select count(*) into n from public.auditoria where tabela = 'contas' and acao = 'UPDATE'; assert n >= 4, 'T8 updates';
end $$;

reset role;
rollback;
\echo OK
