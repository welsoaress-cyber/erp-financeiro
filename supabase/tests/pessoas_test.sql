-- Testes da migration 0007 (pessoas e vínculos). Saída final "OK".
\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, raw_user_meta_data) values ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{"nome":"Bruno"}');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- T1: validação de documentos
do $$ begin
  assert public.documento_valido('52998224725'), 'T1 cpf válido';
  assert not public.documento_valido('52998224726'), 'T1 cpf dígito errado';
  assert not public.documento_valido('11111111111'), 'T1 cpf repetido';
  assert public.documento_valido('11222333000181'), 'T1 cnpj válido';
  assert not public.documento_valido('11222333000182'), 'T1 cnpj dígito errado';
  assert not public.documento_valido('123'), 'T1 tamanho';
end $$;

create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.negocios (organizacao_id, nome, slug) select org, 'Servidor', 'servidor' from ids;

-- T2: criar pessoas; normalização (máscara removida, e-mail minúsculo); regras tipo × documento; duplicidade
insert into public.pessoas (organizacao_id, tipo, nome, documento, email, telefone) select org, 'fisica', '  João da Silva ', '529.982.247-25', 'Joao@Exemplo.com', '(11) 98888-7777' from ids;
insert into public.pessoas (organizacao_id, tipo, nome, documento) select org, 'juridica', 'Empresa X', '11.222.333/0001-81' from ids;
insert into public.pessoas (organizacao_id, nome) select org, 'Sem documento' from ids;
do $$
declare p public.pessoas%rowtype; v_org uuid;
begin
  select org into v_org from ids;
  select * into p from public.pessoas where nome = 'João da Silva';
  assert p.documento = '52998224725' and p.email = 'joao@exemplo.com' and p.telefone = '11988887777', 'T2 normalização';
  begin
    insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Dup', '529.982.247-25');
    raise exception 'T2 documento duplicado deveria falhar';
  exception when unique_violation then null; end;
  begin
    insert into public.pessoas (organizacao_id, tipo, nome, documento) values (v_org, 'fisica', 'Errada', '11222333000181');
    raise exception 'T2 física com cnpj deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.pessoas (organizacao_id, nome, documento) values (v_org, 'Inv', '52998224726');
    raise exception 'T2 cpf inválido deveria falhar';
  exception when check_violation then null; end;
  begin
    insert into public.pessoas (organizacao_id, nome, email) values (v_org, 'Email', 'sem-arroba');
    raise exception 'T2 e-mail inválido deveria falhar';
  exception when check_violation then null; end;
  insert into public.pessoas (organizacao_id, nome) values (v_org, 'Sem documento 2'); -- vários sem documento permitidos
end $$;

-- T3: vínculos — múltiplos negócios, papel único por negócio, negócio inativo/alheio
do $$
declare v_org uuid; v_joao uuid; v_servnet uuid; v_servidor uuid;
begin
  select org into v_org from ids;
  select id into v_joao from public.pessoas where nome = 'João da Silva';
  select id into v_servnet from public.negocios where slug = 'servnet';
  select id into v_servidor from public.negocios where slug = 'servidor';
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) values (v_org, v_joao, v_servnet, 'cliente');
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) values (v_org, v_joao, v_servidor, 'cliente');
  insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) values (v_org, v_joao, v_servnet, 'fornecedor');
  assert (select count(*) from public.pessoa_negocio_vinculos where pessoa_id = v_joao) = 3, 'T3 múltiplos vínculos';
  begin
    insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) values (v_org, v_joao, v_servnet, 'cliente');
    raise exception 'T3 vínculo duplicado deveria falhar';
  exception when unique_violation then null; end;
  update public.negocios set ativo = false where id = v_servidor; -- sem contas/previstos: permitido
  begin
    insert into public.pessoa_negocio_vinculos (organizacao_id, pessoa_id, negocio_id, papel) select v_org, id, v_servidor, 'cliente' from public.pessoas where nome = 'Empresa X';
    raise exception 'T3 vínculo com negócio inativo deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T4: inativar pessoa bloqueada com vínculo ativo; liberada após inativar vínculos
do $$
declare v_joao uuid;
begin
  select id into v_joao from public.pessoas where nome = 'João da Silva';
  begin
    update public.pessoas set ativo = false where id = v_joao;
    raise exception 'T4 inativar com vínculo ativo deveria falhar';
  exception when check_violation then null; end;
  update public.pessoa_negocio_vinculos set ativo = false where pessoa_id = v_joao;
  update public.pessoas set ativo = false where id = v_joao;
  begin
    update public.pessoa_negocio_vinculos set ativo = true where pessoa_id = v_joao and papel = 'cliente' and negocio_id = (select id from public.negocios where slug = 'servnet');
    raise exception 'T4 reativar vínculo de pessoa inativa deveria falhar';
  exception when check_violation then null; end;
  update public.pessoas set ativo = true where id = v_joao;
end $$;

-- T5: lançamento com pessoa; pessoa inativa rejeitada; previsto pendente bloqueia inativação
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco', 'corrente' from ids;
select public.criar_lancamento('receita', 'Mensalidade João', 100, '2026-09-10', null, '2026-09-10',
  (select id from public.contas where nome = 'Banco'), null, (select id from public.categorias where nome = 'Salário'), null,
  (select id from public.negocios where slug = 'servnet'), (select id from public.pessoas where nome = 'João da Silva'));
select public.criar_lancamento('receita', 'Mensalidade outubro', 100, '2026-10-10', '2026-10-10', null,
  (select id from public.contas where nome = 'Banco'), null, (select id from public.categorias where nome = 'Salário'), null,
  (select id from public.negocios where slug = 'servnet'), (select id from public.pessoas where nome = 'João da Silva'));
do $$
declare v_joao uuid; v_prev uuid;
begin
  select id into v_joao from public.pessoas where nome = 'João da Silva';
  assert (select count(*) from public.lancamentos where pessoa_id = v_joao) = 2, 'T5 lançamentos com pessoa';
  begin
    update public.pessoas set ativo = false where id = v_joao;
    raise exception 'T5 inativar com previsto deveria falhar';
  exception when check_violation then null; end;
  select id into v_prev from public.lancamentos where descricao = 'Mensalidade outubro';
  perform public.excluir_lancamento(v_prev);
  update public.pessoas set ativo = false where id = v_joao; -- histórico efetivado não impede
  begin
    perform public.criar_lancamento('receita', 'x', 1, '2026-09-10', null, '2026-09-10', (select id from public.contas where nome = 'Banco'), null, (select id from public.categorias where nome = 'Salário'), null, null, v_joao);
    raise exception 'T5 lançamento com pessoa inativa deveria falhar';
  exception when check_violation then null; end;
end $$;

-- T6: RLS e DELETE
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ declare n int; v_org uuid; begin
  select count(*) into n from public.pessoas; assert n = 0, 'T6 select alheio';
  select count(*) into n from public.pessoa_negocio_vinculos; assert n = 0, 'T6 vínculos alheios';
  reset role; select org into v_org from ids; set local role authenticated;
  begin
    insert into public.pessoas (organizacao_id, nome) values (v_org, 'Invasao');
    raise exception 'T6 insert alheio deveria falhar';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.pessoas;
    raise exception 'T6 delete deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;

-- T7: auditoria
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ declare n int; begin
  select count(*) into n from public.auditoria where tabela = 'pessoas' and acao = 'INSERT'; assert n = 4, 'T7 pessoas';
  select count(*) into n from public.auditoria where tabela = 'pessoa_negocio_vinculos'; assert n >= 3, 'T7 vínculos';
end $$;

reset role;
rollback;
\echo OK
