-- Autoatualização de cadastro para quem vai fazer o curso na Leveduca (clientes que não são
-- da Servnet — esses já têm CPF/e-mail/nascimento em dia). Hoje o proprietário faz isso na mão:
-- pede telefone, acha a pessoa, atualiza CPF/e-mail/nascimento e cria o contrato cortesia dele
-- mesmo. Aqui isso vira uma página pública (sem login — a pessoa não tem CPF/nascimento ainda
-- pra logar no portal, que usa exatamente esses dois campos como senha): ela informa o telefone,
-- confirma os 3 campos, e o ERP atualiza o cadastro e já cria o vínculo com a Servnet no plano
-- do curso, cortesia, começando em 01/10/2026 — sem passo manual.
--
-- Segurança: o único fator de verificação é o telefone bater com o cadastro (igual o link de
-- indicação pública, 0023) — não confere um segundo dado (ex.: não pede nada que só o dono saberia
-- pra confirmar identidade). Aceitável pra esse uso pontual (curso gratuito, sem dinheiro
-- envolvido), mas quem souber ou adivinhar o telefone de alguém pode preencher CPF/nascimento
-- dela. Se um dia isso virar fluxo permanente, vale considerar mais um fator de confirmação.

-- Localiza a pessoa pelo telefone (com ou sem +55/DDI) — devolve só os 3 campos a confirmar.
create function public.curso_buscar_pessoa(p_telefone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_tel text; p public.pessoas%rowtype;
begin
  v_tel := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  if char_length(v_tel) < 10 then raise exception 'Telefone inválido.' using errcode = 'check_violation'; end if;
  select * into p from public.pessoas
   where right(telefone, 11) = right(v_tel, 11) and ativo
   order by criado_em limit 1;
  if not found then return jsonb_build_object('encontrado', false); end if;
  return jsonb_build_object(
    'encontrado', true, 'pessoa_id', p.id, 'nome', p.nome,
    'cpf', p.documento, 'email', p.email, 'data_nascimento', p.data_nascimento
  );
end;
$$;
revoke all on function public.curso_buscar_pessoa(text) from public;
grant execute on function public.curso_buscar_pessoa(text) to anon, authenticated;

-- Atualiza CPF/e-mail/nascimento e garante o contrato cortesia do curso na Servnet (idempotente:
-- não duplica se a pessoa já tem um contrato ativo/suspenso nesse plano).
create function public.curso_atualizar_cadastro(p_pessoa_id uuid, p_cpf text, p_email text, p_data_nascimento date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare p public.pessoas%rowtype; v_neg public.negocios%rowtype; v_plano public.planos%rowtype; v_contrato_id uuid; v_criado boolean := false;
begin
  select * into p from public.pessoas where id = p_pessoa_id;
  if not found then raise exception 'Cadastro não encontrado.' using errcode = 'no_data_found'; end if;
  if p_cpf is null or char_length(regexp_replace(p_cpf, '[^0-9]', '', 'g')) <> 11 then
    raise exception 'CPF inválido.' using errcode = 'check_violation';
  end if;
  if p_email is null or p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'E-mail inválido.' using errcode = 'check_violation';
  end if;
  if p_data_nascimento is null or p_data_nascimento >= current_date then
    raise exception 'Data de nascimento inválida.' using errcode = 'check_violation';
  end if;

  update public.pessoas set documento = p_cpf, email = p_email, data_nascimento = p_data_nascimento where id = p_pessoa_id;

  select * into v_neg from public.negocios where lower(nome) like '%servnet%' and ativo order by criado_em limit 1;
  if not found then raise exception 'Negócio Servnet não encontrado ou inativo.' using errcode = 'no_data_found'; end if;
  select * into v_plano from public.planos where negocio_id = v_neg.id and lower(nome) like '%curso%' and ativo order by criado_em desc limit 1;
  if not found then raise exception 'Plano do curso não encontrado (cadastre um plano com "curso" no nome, no negócio Servnet).' using errcode = 'no_data_found'; end if;

  select id into v_contrato_id from public.contratos
   where pessoa_id = p_pessoa_id and plano_id = v_plano.id and status in ('ativo', 'suspenso') limit 1;
  if v_contrato_id is null then
    insert into public.contratos (
      organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade, data_inicio, dia_vencimento,
      status, faturamento_automatico, tipo_financeiro, cortesia
    ) values (
      v_neg.organizacao_id, v_neg.id, p_pessoa_id, v_plano.id, 0, v_plano.periodicidade, date '2026-10-01', 1,
      'ativo', true, 'receita', true
    ) returning id into v_contrato_id;
    v_criado := true;
  end if;

  return jsonb_build_object('ok', true, 'contrato_criado', v_criado);
end;
$$;
revoke all on function public.curso_atualizar_cadastro(uuid, text, text, date) from public;
grant execute on function public.curso_atualizar_cadastro(uuid, text, text, date) to anon, authenticated;
