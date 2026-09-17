-- Correção da etapa 56: a Edge Function estava lendo pessoas/contratos/planos
-- direto (.from()) com a service role, e o service_role não tem grant
-- automático nessas tabelas (só as funções definer, que rodam como dono da
-- tabela, têm — é assim em todo o resto do sistema). Move a consulta inteira
-- para uma função definer só; a Edge Function passa a chamar só ela.
create function public.api_consultar_cliente(p_token_hash text, p_documento text)
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

  v_status_cliente := case
    when not p.ativo then 'Inativo'
    when c.status = 'ativo' then 'Ativo'
    when c.status = 'suspenso' then 'Suspenso'
    else 'Inativo'
  end;

  situacao := 'ok';
  cliente := jsonb_build_object(
    'cpf_cnpj', p.documento, 'nome_completo', p.nome, 'status_cliente', v_status_cliente,
    'email', p.email, 'endereco', p.endereco, 'numero', null, 'cep', null,
    'plano', c.plano_nome, 'plano_id', c.plano_id,
    'status_plano', (case c.status when 'ativo' then 'Ativo' when 'suspenso' then 'Suspenso' when 'encerrado' then 'Encerrado' end)
  );
  return next;
end;
$$;
comment on function public.api_consultar_cliente(text, text) is 'Único ponto de acesso da Edge Function api-consulta-cliente: valida o token, busca a pessoa+contrato e registra a auditoria — tudo numa chamada, sem a Edge Function precisar de grant direto nas tabelas.';
revoke all on function public.api_consultar_cliente(text, text) from public, anon, authenticated;
grant execute on function public.api_consultar_cliente(text, text) to service_role;
