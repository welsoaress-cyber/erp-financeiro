-- Testes da migration 0001 (fundação). Executar após a migration.
-- Cada bloco lança exceção em caso de falha; saída final "OK" = todos passaram.
\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ana@teste.dev',   '{"nome":"Ana"}'),
  ('22222222-2222-2222-2222-222222222222', 'bruno@teste.dev', '{}');

-- T1: signup cria organizacao + membro proprietário + auditoria
do $$
declare n int;
begin
  select count(*) into n from public.organizacoes; assert n = 2, 'T1 organizacoes';
  select count(*) into n from public.organizacao_membros where papel = 'proprietario'; assert n = 2, 'T1 membros';
  select count(*) into n from public.organizacoes where nome = 'Ana'; assert n = 1, 'T1 nome via metadata';
  select count(*) into n from public.organizacoes where nome = 'bruno'; assert n = 1, 'T1 nome via email';
  select count(*) into n from public.auditoria where acao = 'INSERT'; assert n = 4, 'T1 auditoria insert';
end $$;

-- T2: usuária Ana enxerga apenas a própria organizacao
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$
declare n int;
begin
  select count(*) into n from public.organizacoes; assert n = 1, 'T2 organizacoes visíveis';
  select count(*) into n from public.organizacoes where nome = 'Ana'; assert n = 1, 'T2 organizacao correta';
  select count(*) into n from public.organizacao_membros; assert n = 1, 'T2 membros visíveis';
  select count(*) into n from public.auditoria; assert n = 2, 'T2 auditoria visível (1 organizacao + 1 membro)';
end $$;

-- T3: proprietária edita a própria organizacao; auditoria registra com usuario_id
-- atualizado_em enviado pelo cliente deve ser sobrescrito pelo trigger
update public.organizacoes set nome = 'Ana Editada', atualizado_em = '2000-01-01' where nome = 'Ana';
do $$
declare n int;
begin
  select count(*) into n from public.organizacoes where nome = 'Ana Editada'; assert n = 1, 'T3 update';
  select count(*) into n from public.auditoria
    where acao = 'UPDATE' and usuario_id = '11111111-1111-1111-1111-111111111111'
      and dados_antes ->> 'nome' = 'Ana' and dados_depois ->> 'nome' = 'Ana Editada';
  assert n = 1, 'T3 auditoria update';
  select count(*) into n from public.organizacoes where atualizado_em >= criado_em and atualizado_em > '2000-01-02'; assert n = 1, 'T3 atualizado_em';
end $$;

-- T4: update na organizacao alheia não afeta linha alguma (RLS filtra)
do $$
declare n int;
begin
  update public.organizacoes set nome = 'Invasao' where nome = 'bruno';
  get diagnostics n = row_count; assert n = 0, 'T4 update alheio';
end $$;

-- T5: escritas proibidas via cliente
do $$
begin
  begin
    insert into public.organizacoes (nome) values ('x');
    raise exception 'T5 insert organizacoes deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.organizacoes;
    raise exception 'T5 delete organizacoes deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.organizacao_membros (organizacao_id, usuario_id)
      select id, '22222222-2222-2222-2222-222222222222' from public.organizacoes;
    raise exception 'T5 insert membros deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.auditoria (tabela, registro_id, acao) values ('x', 'x', 'INSERT');
    raise exception 'T5 insert auditoria deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.auditoria;
    raise exception 'T5 delete auditoria deveria falhar';
  exception when insufficient_privilege then null;
  end;
end $$;

-- T6: anônimo não acessa nada
reset role;
set local role anon;
do $$
begin
  begin
    perform * from public.organizacoes;
    raise exception 'T6 anon select organizacoes deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.auditoria;
    raise exception 'T6 anon select auditoria deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.minhas_organizacoes();
    raise exception 'T6 anon minhas_organizacoes deveria falhar';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;
\echo OK
