-- Etapa 56 (ajuste): a Leveduca só usa cpf_cnpj + status_cliente pra liberar o
-- curso — "Suspenso" e "Inativo" davam no mesmo pro lado deles. Simplifica
-- status_cliente pra dois valores só: Ativo (contrato de receita ativo e
-- pessoa ativa) ou Inativo (qualquer outro caso, incluindo suspenso por
-- falta de pagamento). status_plano continua com os três valores — é
-- informativo, não decide liberar o curso.
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

  select ct.status, ct.plano_id, pl.nome as plano_nome into c
    from public.contratos ct
    join public.planos pl on pl.id = ct.plano_id
   where ct.negocio_id = tk.negocio_id and ct.pessoa_id = p.id and ct.tipo_financeiro = 'receita'
   order by (case ct.status when 'ativo' then 0 when 'suspenso' then 1 else 2 end), ct.criado_em desc
   limit 1;

  insert into public.api_consultas (organizacao_id, token_id, documento_consultado, encontrado)
  values (tk.organizacao_id, tk.id, p_documento, true);

  -- binário de propósito: só "Ativo" libera o curso; suspenso por atraso conta como Inativo
  v_status_cliente := case when p.ativo and c.status = 'ativo' then 'Ativo' else 'Inativo' end;

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
