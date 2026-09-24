-- Vários clientes de servidor foram importados sem nome real (0043): o campo
-- pessoas.nome ficou com o LOGIN ("Jhone100526", "Viana0103A"…), porque na
-- época só isso existia. A API de consulta (0096/0099, já em produção com a
-- Leveduca) mandava esse valor direto em nome_completo — e a Leveduca gerava
-- certificado com o login em vez do nome da pessoa. O login do servidor deve
-- ficar só no ERP, nunca sair pra fora. Regra: nome sem espaço = provavelmente
-- é login, não nome completo → manda null em vez de vazar. Não resolve o nome
-- de verdade (só o proprietário sabe/tem essa informação para completar em
-- Pessoas); só evita mandar lixo pra fora enquanto isso não é feito.
-- Corpo copiado de 0099 (última versão em produção — status binário Ativo/Inativo),
-- só acrescentando a suspensão do nome-login.
create or replace function public.api_consultar_cliente(p_token_hash text, p_documento text)
returns table (situacao text, cliente jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  tk public.api_tokens%rowtype;
  p public.pessoas%rowtype;
  c record;
  v_status_cliente text;
  v_nome text;
begin
  select * into tk from public.api_tokens where token_hash = p_token_hash;
  if not found or not tk.ativo then
    situacao := 'token_invalido'; cliente := null; return next; return;
  end if;
  update public.api_tokens set ultimo_uso_em = now() where id = tk.id;

  select * into p from public.pessoas where organizacao_id = tk.organizacao_id and documento = p_documento;
  if not found then
    insert into public.api_consultas (organizacao_id, token_id, documento_consultado, encontrado)
    values (tk.organizacao_id, tk.id, p_documento, false);
    situacao := 'nao_encontrado'; cliente := null; return next; return;
  end if;

  -- contrato de receita mais relevante nesse negócio: ativo primeiro, depois suspenso, senão o mais recente
  select ct.status, ct.plano_id, pl.nome as plano_nome into c
    from public.contratos ct
    join public.planos pl on pl.id = ct.plano_id
   where ct.negocio_id = tk.negocio_id and ct.pessoa_id = p.id and ct.tipo_financeiro = 'receita'
   order by (case ct.status when 'ativo' then 0 when 'suspenso' then 1 else 2 end), ct.criado_em desc
   limit 1;

  insert into public.api_consultas (organizacao_id, token_id, documento_consultado, encontrado)
  values (tk.organizacao_id, tk.id, p_documento, true);

  -- binário de propósito (0099): só "Ativo" libera o curso; suspenso por atraso conta como Inativo
  v_status_cliente := case when p.ativo and c.status = 'ativo' then 'Ativo' else 'Inativo' end;

  -- nome sem nenhum espaço = provavelmente é o login do servidor, não um nome completo
  v_nome := case when btrim(coalesce(p.nome, '')) !~ '\s' then null else p.nome end;

  situacao := 'ok';
  cliente := jsonb_build_object(
    'cpf_cnpj', p.documento, 'nome_completo', v_nome, 'status_cliente', v_status_cliente,
    'email', p.email, 'endereco', p.endereco, 'numero', null, 'cep', null,
    'plano', c.plano_nome, 'plano_id', c.plano_id,
    'status_plano', (case c.status when 'ativo' then 'Ativo' when 'suspenso' then 'Suspenso' when 'encerrado' then 'Encerrado' end)
  );
  return next;
end;
$$;
comment on function public.api_consultar_cliente(text, text) is 'Único ponto de acesso da Edge Function api-consulta-cliente: valida o token, busca a pessoa+contrato e registra a auditoria — tudo numa chamada, sem a Edge Function precisar de grant direto nas tabelas. nome_completo vem null quando o cadastro só tem o login do servidor como nome (nunca vaza login pra fora).';
revoke all on function public.api_consultar_cliente(text, text) from public, anon, authenticated;
grant execute on function public.api_consultar_cliente(text, text) to service_role;
