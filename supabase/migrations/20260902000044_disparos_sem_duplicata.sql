-- =============================================================================
-- 0044 · Disparos sem duplicata: a fila reivindica o item
-- =============================================================================
-- Duas execuções simultâneas da Edge Function podiam pegar o MESMO item
-- pendente e o cliente recebia a mensagem 2x. Agora disparos_para_envio marca
-- o item como "em processamento" (processando_em) na própria leitura, de forma
-- atômica: quem chegar depois não o vê. Reivindicação expira em 3 minutos
-- (execução travada não prende o item para sempre).
-- =============================================================================

alter table public.disparo_itens add column processando_em timestamptz;

create or replace function public.disparos_para_envio(p_limite integer default 3)
returns table (id uuid, instancia text, numero_destino text, mensagem text, tentativas smallint)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  return query
    with reivindicados as (
      select i.id
        from public.disparo_itens i
        join public.disparos d on d.id = i.disparo_id
        join public.notificacoes_config cfg on cfg.negocio_id = d.negocio_id
       where i.status = 'pendente' and cfg.ativo
         and cfg.provedor::text = 'evolution' and cfg.instancia is not null
         and i.tentativas < 5
         and (i.processando_em is null or i.processando_em < now() - interval '3 minutes')
       order by i.criado_em
       limit p_limite
       for update of i skip locked
    ), marcados as (
      update public.disparo_itens i set processando_em = now()
        from reivindicados r where i.id = r.id
      returning i.id, i.disparo_id, i.numero_destino, i.mensagem, i.tentativas
    )
    select m.id, cfg.instancia, m.numero_destino, m.mensagem, m.tentativas
      from marcados m
      join public.disparos d on d.id = m.disparo_id
      join public.notificacoes_config cfg on cfg.negocio_id = d.negocio_id;
end;
$$;

-- resultado libera a reivindicação (sucesso ou falha)
create or replace function public.registrar_resultado_disparo(p_id uuid, p_ok boolean, p_erro text default null, p_resposta jsonb default null, p_contar boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  if p_ok then
    update public.disparo_itens set status = 'enviado', data_envio = now(), erro = null, resposta_provedor = p_resposta, tentativas = tentativas + 1, processando_em = null
     where id = p_id and status = 'pendente';
  else
    update public.disparo_itens
       set tentativas = tentativas + (case when p_contar then 1 else 0 end), erro = left(p_erro, 500), resposta_provedor = p_resposta, processando_em = null,
           status = case when p_contar and tentativas + 1 >= 5 then 'erro'::public.status_disparo else status end
     where id = p_id and status = 'pendente';
  end if;
end;
$$;

create or replace function public.reenviar_falhas_disparo(p_disparo_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare d public.disparos%rowtype; v int;
begin
  select * into d from public.disparos where id = p_disparo_id;
  if not found then raise exception 'Disparo não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(d.organizacao_id);
  perform set_config('erp.motor', 'on', true);
  update public.disparo_itens set status = 'pendente', tentativas = 0, erro = null, processando_em = null
   where disparo_id = p_disparo_id and status = 'erro';
  get diagnostics v = row_count;
  return v;
end;
$$;
