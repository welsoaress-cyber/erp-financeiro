-- =============================================================================
-- 0045 · Histórico dos disparos: vencimento gravado por item
-- =============================================================================
-- O histórico precisa contar a história completa: quem recebeu, quando foi
-- enviado e qual o vencimento cobrado. data_envio já existe; este passo grava
-- o vencimento informado na tela em cada item do disparo.
-- =============================================================================

alter table public.disparo_itens add column vencimento date;

create or replace function public.criar_disparo(p_negocio_id uuid, p_modelo_nome text, p_itens jsonb)
returns public.disparos
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.negocios%rowtype;
  cfg public.notificacoes_config%rowtype;
  d public.disparos%rowtype;
  it jsonb;
  pe public.pessoas%rowtype;
  v_qtd int;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio inválido.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(n.organizacao_id);
  select * into cfg from public.notificacoes_config where negocio_id = p_negocio_id;
  if not found or not cfg.ativo then
    raise exception 'Configure e ative as notificações do negócio antes de disparar.' using errcode = 'check_violation';
  end if;
  v_qtd := coalesce(jsonb_array_length(p_itens), 0);
  if v_qtd < 1 or v_qtd > 30 then
    raise exception 'Um disparo tem de 1 a 30 destinatários (recebidos: %).', v_qtd using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  insert into public.disparos (organizacao_id, negocio_id, modelo_nome)
  values (n.organizacao_id, p_negocio_id, left(btrim(coalesce(p_modelo_nome, 'Sem modelo')), 60)) returning * into d;
  for it in select * from jsonb_array_elements(p_itens) loop
    select * into pe from public.pessoas where id = (it->>'pessoa_id')::uuid;
    if not found or pe.organizacao_id <> n.organizacao_id then
      raise exception 'Pessoa inválida no disparo.' using errcode = 'check_violation';
    end if;
    if pe.telefone is null then
      raise exception 'Pessoa % sem telefone cadastrado.', pe.nome using errcode = 'check_violation';
    end if;
    insert into public.disparo_itens (disparo_id, organizacao_id, pessoa_id, numero_destino, mensagem, vencimento)
    values (d.id, n.organizacao_id, pe.id, public.numero_e164(pe.telefone), it->>'mensagem', (it->>'vencimento')::date);
  end loop;
  return d;
end;
$$;
