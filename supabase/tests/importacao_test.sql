-- Testes da migration 0011 (importação de clientes por CSV). Saída final "OK".
\set ON_ERROR_STOP on
begin;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
create temp table ids as select (select organizacao_id from public.categorias limit 1) as org;
insert into public.negocios (organizacao_id, nome, slug) select org, 'SERVNET', 'servnet' from ids;
insert into public.negocios (organizacao_id, nome, slug, ativo) select org, 'Parado', 'parado', true from ids;
update public.negocios set ativo = false where slug = 'parado';
-- pessoa pré-existente com CPF de uma das linhas (não pode duplicar) e plano pré-existente
insert into public.pessoas (organizacao_id, nome, documento, telefone) select org, 'Maria Antiga', '52998224725', '11999990000' from ids;
insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela) select org, (select id from public.negocios where slug='servnet'), 'Plano 200 Mbps', 80 from ids;
create temp table r as select (select org from ids) org, (select id from public.negocios where slug='servnet') servnet, (select id from public.negocios where slug='parado') parado;

-- T0: helpers puros
do $$ begin
  assert public.nome_plano_importado('Velocidade_0100_MB') = 'Plano 100 Mbps', 'T0 velocidade 100';
  assert public.nome_plano_importado('velocidade_0300_mb') = 'Plano 300 Mbps', 'T0 minúsculas';
  assert public.nome_plano_importado('  Fibra   Premium ') = 'Fibra Premium', 'T0 nome comum limpo';
  assert public.nome_plano_importado('') is null, 'T0 vazio';
  assert public.data_importada('15/03/2024') = date '2024-03-15', 'T0 DD/MM/AAAA';
  assert public.data_importada('05/03/2024 10:30') = date '2024-03-05', 'T0 DD/MM nunca vira MM/DD';
  assert public.data_importada('2024-03-15T00:00:00') = date '2024-03-15', 'T0 ISO';
  assert public.data_importada('') is null, 'T0 data vazia';
end $$;

-- Arquivo de teste: 8 linhas cobrindo todos os casos
create temp table arq as select $j$[
 {"linha":2,"nome":"João da Silva","documento":"123.456.789-09","telefone":"(11) 98888-7777","email":"joao@x.com","plano":"Velocidade_0100_MB","valor":"R$ 60,00","dia_vencimento":"10","data_inicio":"15/01/2024","data_fim":""},
 {"linha":3,"nome":"Maria Nova","documento":"52998224725","telefone":"11999990000","email":"","plano":"Velocidade_0200_MB","valor":"80","dia_vencimento":"10","data_inicio":"2023-05-01","data_fim":null},
 {"linha":4,"nome":"Empresa X","documento":"11.222.333/0001-81","telefone":"1133334444","email":"fin@empresa.com","plano":"Velocidade_0300_MB","valor":"100","dia_vencimento":"5","data_inicio":"01/02/2022","data_fim":"31/12/2023"},
 {"linha":5,"nome":"Sem Documento","documento":"","telefone":"11999999999","email":"","plano":"Velocidade_0100_MB","valor":"60","dia_vencimento":"10","data_inicio":"01/01/2024","data_fim":""},
 {"linha":6,"nome":"CPF Errado","documento":"123.456.789-00","telefone":"11999999999","email":"","plano":"Velocidade_0100_MB","valor":"60","dia_vencimento":"10","data_inicio":"01/01/2024","data_fim":""},
 {"linha":7,"nome":"Dia Errado","documento":"39053344705","telefone":"11999999999","email":"","plano":"Velocidade_0100_MB","valor":"60","dia_vencimento":"32","data_inicio":"01/01/2024","data_fim":""},
 {"linha":8,"nome":"João da Silva","documento":"12345678909","telefone":"11988887777","email":"","plano":"Velocidade_0100_MB","valor":"60","dia_vencimento":"10","data_inicio":"15/01/2024","data_fim":""},
 {"linha":9,"nome":"Email Ruim","documento":"39053344705","telefone":"11999999999","email":"nao-e-email","plano":"Velocidade_0100_MB","valor":"60","dia_vencimento":"10","data_inicio":"01/01/2024","data_fim":""}
]$j$::jsonb as linhas;

-- T1: simulação executa tudo e desfaz; relatório completo
do $$ declare v r%rowtype; rel jsonb; n int; begin
  select * into v from r;
  rel := public.importar_clientes(v.servnet, (select linhas from arq), true, date '2026-09-01');
  assert (rel->>'simulado')::boolean, 'T1 simulado';
  assert (rel->>'total')::int = 8, 'T1 total';
  assert (rel->>'importadas')::int = 3, 'T1 importadas: ' || (rel->>'importadas');
  assert (rel->>'rejeitadas')::int = 5, 'T1 rejeitadas: ' || (rel->>'rejeitadas');
  assert (rel->>'pessoas_novas')::int = 2 and (rel->>'pessoas_existentes')::int = 1, 'T1 pessoas';
  assert (rel->>'planos_novos')::int = 2, 'T1 planos novos (100 e 300; 200 já existia)';
  assert (rel->>'contratos_ativos')::int = 2 and (rel->>'contratos_encerrados')::int = 1, 'T1 contratos';
  assert (select count(*) from jsonb_array_elements(rel->'linhas') l where l->>'status'='rejeitada' and (l->>'linha')::int = 5 and l->>'motivo' = 'CPF/CNPJ obrigatório.') = 1, 'T1 motivo doc obrigatório';
  assert (select count(*) from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 6 and l->>'motivo' = 'CPF/CNPJ inválido.') = 1, 'T1 motivo doc inválido';
  assert (select count(*) from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 7 and l->>'motivo' like 'Dia de vencimento%') = 1, 'T1 motivo dia';
  assert (select count(*) from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 8 and l->>'motivo' like 'Linha repetida%') = 1, 'T1 repetida no arquivo';
  assert (select count(*) from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 9 and l->>'motivo' = 'E-mail inválido.') = 1, 'T1 e-mail';
  assert (select l->>'pessoa' from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 3) = 'existente', 'T1 Maria reaproveitada';
  assert (select l->>'plano' from jsonb_array_elements(rel->'linhas') l where (l->>'linha')::int = 3) = 'existente', 'T1 plano 200 reaproveitado';
  -- nada gravado
  select count(*) into n from public.contratos where negocio_id = v.servnet; assert n = 0, 'T1 simulação não grava contratos';
  select count(*) into n from public.pessoas where documento in ('12345678909','11222333000181'); assert n = 0, 'T1 simulação não grava pessoas';
  select count(*) into n from public.planos where negocio_id = v.servnet; assert n = 1, 'T1 simulação não grava planos';
end $$;

-- T2: importação real grava exatamente o simulado; contrato encerrado com data_fim; faturar_desde respeitado
do $$ declare v r%rowtype; rel jsonb; c public.contratos%rowtype; n int; begin
  select * into v from r;
  rel := public.importar_clientes(v.servnet, (select linhas from arq), false, date '2026-09-01');
  assert not (rel->>'simulado')::boolean and (rel->>'importadas')::int = 3 and (rel->>'rejeitadas')::int = 5, 'T2 totais';
  select count(*) into n from public.contratos where negocio_id = v.servnet; assert n = 3, 'T2 3 contratos';
  select count(*) into n from public.pessoas where documento in ('12345678909','11222333000181','52998224725'); assert n = 3, 'T2 pessoas sem duplicar';
  assert (select nome from public.pessoas where documento = '52998224725') = 'Maria Antiga', 'T2 pessoa existente não é sobrescrita';
  assert (select tipo from public.pessoas where documento = '11222333000181') = 'juridica', 'T2 CNPJ vira jurídica';
  assert (select array_agg(nome order by nome) from public.planos where negocio_id = v.servnet) = array['Plano 100 Mbps','Plano 200 Mbps','Plano 300 Mbps'], 'T2 planos';
  assert (select valor_tabela from public.planos where nome = 'Plano 100 Mbps') = 60, 'T2 valor do plano vindo do CSV';
  select * into c from public.contratos c2 join public.pessoas p on p.id = c2.pessoa_id where p.documento = '11222333000181';
  assert c.status = 'encerrado' and c.data_fim = date '2023-12-31' and c.data_inicio = date '2022-02-01' and not c.faturamento_automatico, 'T2 contrato cancelado → encerrado';
  select * into c from public.contratos c2 join public.pessoas p on p.id = c2.pessoa_id where p.documento = '12345678909';
  assert c.status = 'ativo' and c.faturamento_automatico and c.faturar_desde = date '2026-09-01' and c.data_inicio = date '2024-01-15' and c.dia_vencimento = 10 and c.valor = 60, 'T2 contrato ativo com faturar_desde da importação';
  assert c.codigo between 1 and 3, 'T2 código sequencial';
  select count(*) into n from public.pessoa_negocio_vinculos where negocio_id = v.servnet and papel = 'cliente' and ativo; assert n = 3, 'T2 vínculos cliente';
  -- reimportar o mesmo arquivo: nada duplica
  rel := public.importar_clientes(v.servnet, (select linhas from arq), false, null);
  assert (rel->>'importadas')::int = 0 and (rel->>'ignoradas')::int = 3 and (rel->>'rejeitadas')::int = 5, 'T2 reimportação idempotente: ' || rel::text;
  select count(*) into n from public.contratos where negocio_id = v.servnet; assert n = 3, 'T2 contratos não duplicados';
end $$;

-- T3: faturar_desde nulo = início do contrato; segundo contrato da mesma pessoa em outro plano é permitido
do $$ declare v r%rowtype; rel jsonb; c public.contratos%rowtype; begin
  select * into v from r;
  rel := public.importar_clientes(v.servnet, '[{"linha":2,"nome":"João da Silva","documento":"12345678909","telefone":"11988887777","plano":"Velocidade_0300_MB","valor":"","dia_vencimento":"15","data_inicio":"2026-08-01"}]'::jsonb, false, null);
  assert (rel->>'importadas')::int = 1 and (rel->>'pessoas_existentes')::int = 1 and (rel->>'planos_novos')::int = 0, 'T3 segundo contrato: ' || rel::text;
  select * into c from public.contratos where negocio_id = v.servnet and data_inicio = date '2026-08-01';
  assert c.faturar_desde = date '2026-08-01' and c.valor = 100, 'T3 faturar_desde = início e valor da tabela do plano';
end $$;

-- T4: negócio inativo / inválido / de outra organização; limite de linhas; papel anônimo
do $$ declare v r%rowtype; rel jsonb; begin
  select * into v from r;
  begin
    rel := public.importar_clientes(v.parado, '[]'::jsonb, true, null);
    raise exception 'T4 negócio inativo deveria falhar';
  exception when check_violation then null; end;
  begin
    rel := public.importar_clientes(gen_random_uuid(), '[]'::jsonb, true, null);
    raise exception 'T4 negócio inexistente deveria falhar';
  exception when check_violation then null; end;
  begin
    rel := public.importar_clientes(v.servnet, '{}'::jsonb, true, null);
    raise exception 'T4 linhas não-array deveria falhar';
  exception when check_violation then null; end;
end $$;
set local role anon;
do $$ begin
  begin
    perform public.importar_clientes(gen_random_uuid(), '[]'::jsonb, true, null);
    raise exception 'T4 anon deveria falhar';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
\echo OK
