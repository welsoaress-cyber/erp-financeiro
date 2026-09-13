-- =============================================================================
-- 0077 · RECONCILIAÇÃO PIX DENTRO DO BANCO, A CADA 1 MINUTO (pg_cron + pg_net + Vault)
-- =============================================================================
-- Por quê: a baixa automática dependia de três elos frágeis — webhook do MP
-- (entrega instável), Edge chamada pelo navegador (cache/deploy) e o próprio
-- pagamento criado no MP, que pode ficar "pending" enquanto o dinheiro entra
-- em OUTRO pagamento. Aqui o banco consulta o Mercado Pago sozinho, todo
-- minuto, para cada cobrança pendente (até 3 dias): GET pelo id criado E
-- busca por external_reference (a fatura). Grava o status real em
-- pix_cobrancas.resposta (diagnóstico sem cache) e dá a baixa (pix_confirmar)
-- assim que achar um "approved". Mesmo padrão da 0019.
-- PRÉ-REQUISITO (uma vez, no SQL Editor, com o token real — nunca no repositório):
--   select vault.create_secret('APP_USR-...', 'mp_access_token');
-- =============================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;
grant usage on schema cron to postgres;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'mp_access_token') then
    raise exception 'Crie o segredo mp_access_token no Vault antes desta migration: select vault.create_secret(''APP_USR-...'', ''mp_access_token'');';
  end if;
end $$;

-- requisições em voo (pg_net é assíncrono: dispara num minuto, lê a resposta no seguinte)
create table public.pix_verificacoes (
  request_id bigint primary key,
  txid text not null,
  tipo text not null check (tipo in ('get', 'busca')),
  criado_em timestamptz not null default now()
);
alter table public.pix_verificacoes enable row level security; -- interna: só a função (definer) e o postgres escrevem
revoke all on public.pix_verificacoes from public, anon, authenticated;

create or replace function public.pix_reconciliar_agendado()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_token text; r record; v_req bigint; j jsonb; s text; v_ok jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'mp_access_token' limit 1;
  if v_token is null then return; end if;

  -- 2) processa as respostas que já chegaram
  for r in
    select v.request_id, v.txid, v.tipo, h.status_code, h.content, h.timed_out, c.status as cob_status
      from public.pix_verificacoes v
      join net._http_response h on h.id = v.request_id
      left join public.pix_cobrancas c on c.txid = v.txid
  loop
    begin
      if r.cob_status is distinct from 'pendente' then
        null; -- já resolvida por outro caminho (webhook, portal, manual)
      elsif r.status_code = 200 then
        j := r.content::jsonb;
        if r.tipo = 'get' then
          s := j->>'status';
          update public.pix_cobrancas set resposta = coalesce(resposta, '{}'::jsonb) || jsonb_build_object('ultimo_mp_status', s, 'checado_em', now())
           where txid = r.txid and status = 'pendente';
          if s = 'approved' then
            perform public.pix_confirmar(r.txid, (j->>'transaction_amount')::numeric, jsonb_build_object('status', s, 'via', 'agendado'));
          elsif s in ('cancelled', 'expired', 'rejected') then
            perform public.pix_marcar_erro(r.txid, case s when 'rejected' then 'erro' when 'expired' then 'expirado' else 'cancelado' end, jsonb_build_object('status', s));
          end if;
        else
          -- busca por external_reference: o dinheiro pode ter entrado num pagamento separado
          select x into v_ok from jsonb_array_elements(coalesce(j->'results', '[]'::jsonb)) x where x->>'status' = 'approved' limit 1;
          if v_ok is not null then
            update public.pix_cobrancas set resposta = coalesce(resposta, '{}'::jsonb) || jsonb_build_object('ultimo_mp_status', 'approved(ref)', 'pagamento_mp', v_ok->>'id', 'checado_em', now())
             where txid = r.txid and status = 'pendente';
            perform public.pix_confirmar(r.txid, (v_ok->>'transaction_amount')::numeric, jsonb_build_object('status', 'approved', 'via', 'agendado_ref', 'pagamento_mp', v_ok->>'id'));
          else
            update public.pix_cobrancas set resposta = coalesce(resposta, '{}'::jsonb) || jsonb_build_object(
              'busca_ref', coalesce((select string_agg(x->>'status', ',') from jsonb_array_elements(coalesce(j->'results', '[]'::jsonb)) x), 'vazio'), 'checado_em', now())
             where txid = r.txid and status = 'pendente';
          end if;
        end if;
      else
        update public.pix_cobrancas set resposta = coalesce(resposta, '{}'::jsonb) || jsonb_build_object(
          'ultimo_mp_status', 'http_' || coalesce(r.status_code::text, case when r.timed_out then 'timeout' else 'erro' end),
          'erro', left(coalesce(r.content, ''), 200), 'checado_em', now())
         where txid = r.txid and status = 'pendente';
      end if;
    exception when others then
      update public.pix_cobrancas set resposta = coalesce(resposta, '{}'::jsonb) || jsonb_build_object('ultimo_mp_status', 'erro_processar', 'erro', left(sqlerrm, 200), 'checado_em', now())
       where txid = r.txid and status = 'pendente';
    end;
    delete from public.pix_verificacoes where request_id = r.request_id;
  end loop;

  -- requisição sem resposta em 5 min é descartada (libera nova tentativa)
  delete from public.pix_verificacoes where criado_em < now() - interval '5 minutes';

  -- 1) dispara as consultas para cada pendente recente sem requisição em voo
  for r in
    select c.txid, c.lancamento_id
      from public.pix_cobrancas c
     where c.status = 'pendente' and c.criado_em > now() - interval '3 days'
       and not exists (select 1 from public.pix_verificacoes v where v.txid = c.txid)
     order by c.criado_em desc
     limit 20
  loop
    select net.http_get(
      url := 'https://api.mercadopago.com/v1/payments/' || r.txid,
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_token),
      timeout_milliseconds := 8000
    ) into v_req;
    insert into public.pix_verificacoes (request_id, txid, tipo) values (v_req, r.txid, 'get');

    select net.http_get(
      url := 'https://api.mercadopago.com/v1/payments/search?external_reference=' || r.lancamento_id::text || '&sort=date_created&criteria=desc',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_token),
      timeout_milliseconds := 8000
    ) into v_req;
    insert into public.pix_verificacoes (request_id, txid, tipo) values (v_req, r.txid, 'busca');
  end loop;
end;
$$;
revoke all on function public.pix_reconciliar_agendado() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('erp-pix-reconciliar');
exception when others then null;  -- ainda não existia
end $$;

select cron.schedule('erp-pix-reconciliar', '* * * * *', $$select public.pix_reconciliar_agendado()$$);
