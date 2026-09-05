-- Testes da migration 0036 (importação com documento e plano opcionais). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'IPTV TESTE', 'iptv-teste' from ids;
insert into public.contas (organizacao_id, nome, tipo) select org, 'Banco Iptv', 'corrente' from ids;
update public.negocios set conta_padrao_id = (select id from public.contas where nome='Banco Iptv'),
  categoria_receita_id = (select id from public.categorias where nome='Salário' limit 1)
  where slug='iptv-teste';

-- T1: linha sem documento e sem plano importa; plano vira o nome do negócio
do $$ declare v_rel jsonb; v_ct public.contratos%rowtype; begin
  v_rel := public.importar_clientes((select id from public.negocios where slug='iptv-teste'), jsonb_build_array(
    jsonb_build_object('nome', 'Login bororo', 'telefone', '14991230001', 'valor', '50',
                       'dia_vencimento', '10', 'data_inicio', '2026-09-10')
  ), false);
  assert (v_rel->>'importadas')::int = 1, 'T1 importada: ' || v_rel::text;
  select c.* into v_ct from public.contratos c join public.pessoas p on p.id = c.pessoa_id where p.nome = 'Login bororo';
  assert (select nome from public.planos where id = v_ct.plano_id) = 'IPTV TESTE', 'T1 plano = nome do negócio';
  assert (select documento from public.pessoas where id = v_ct.pessoa_id) is null, 'T1 pessoa sem documento';
end $$;

-- T2: reimportar a mesma pessoa (dedup por nome) é ignorada, não duplica
do $$ declare v_rel jsonb; n int; begin
  v_rel := public.importar_clientes((select id from public.negocios where slug='iptv-teste'), jsonb_build_array(
    jsonb_build_object('nome', 'Login bororo', 'telefone', '14991230001', 'valor', '50',
                       'dia_vencimento', '10', 'data_inicio', '2026-09-10')
  ), false);
  assert (v_rel->>'ignoradas')::int = 1, 'T2 ignorada: ' || v_rel::text;
  select count(*) into n from public.pessoas where nome = 'Login bororo';
  assert n = 1, 'T2 pessoa não duplicada';
end $$;

-- T3: nada obrigatório além do nome (0037): sem telefone/dia/início importa com padrões; o que vier errado ainda rejeita
do $$ declare v_rel jsonb; v_ct public.contratos%rowtype; begin
  v_rel := public.importar_clientes((select id from public.negocios where slug='iptv-teste'), jsonb_build_array(
    jsonb_build_object('nome', 'So Nome'),
    jsonb_build_object('nome', 'Doc Ruim', 'telefone', '14991230002', 'documento', '12345678900',
                       'valor', '30', 'dia_vencimento', '5', 'data_inicio', '2026-09-05'),
    jsonb_build_object('nome', 'Dia Ruim', 'telefone', '14991230003', 'dia_vencimento', '32')
  ), false);
  assert (v_rel->>'importadas')::int = 1 and (v_rel->>'rejeitadas')::int = 2, 'T3 padrões e validações: ' || v_rel::text;
  select c.* into v_ct from public.contratos c join public.pessoas p on p.id = c.pessoa_id where p.nome = 'So Nome';
  assert v_ct.dia_vencimento = 10 and v_ct.data_inicio = current_date, 'T3 padrões dia 10 e início hoje';
end $$;

rollback;
\echo OK
