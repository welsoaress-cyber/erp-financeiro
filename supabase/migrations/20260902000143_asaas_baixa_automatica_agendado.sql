-- =============================================================================
-- 0143 · Baixa automática via Asaas, dentro do banco (pg_cron + pg_net + Vault)
-- =============================================================================
-- Pedido do proprietário: "o receitanet baixou [o pagamento Asaas] sozinho,
-- quero que faça o mesmo". Mesmo padrão já usado pro Pix do Mercado Pago
-- (0077): o banco consulta o Asaas sozinho, a cada 5 minutos, sem depender de
-- webhook de fora nem do navegador aberto. Só roda pra lançamento elegível ao
-- boleto Asaas (negócio com asaas_ativo + contrato forma_pagamento='boleto' —
-- mesma trava da 0141).
--
-- O Asaas não tem "buscar cobrança pelo nosso id" (quem cria a cobrança é o
-- ReceitaNet, não a gente) — o casamento é em duas consultas: CPF → cliente
-- Asaas, cliente → cobranças. O id do cliente Asaas é cacheado em
-- pessoas.asaas_customer_id pra não repetir a primeira consulta toda vez.
--
-- PRÉ-REQUISITO (uma vez, no SQL Editor, com a chave real — nunca no repositório):
--   select vault.create_secret('a_chave_do_asaas', 'asaas_api_key');
-- =============================================================================

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'asaas_api_key') then
    raise exception 'Crie o segredo asaas_api_key no Vault antes desta migration: select vault.create_secret(''...'', ''asaas_api_key'');';
  end if;
end $$;

alter table public.pessoas add column asaas_customer_id text;
comment on column public.pessoas.asaas_customer_id is 'Id do cliente na conta Asaas (cache, achado por CPF) — evita repetir a consulta a cada rodada da baixa automática (0143).';

-- requisições em voo (pg_net é assíncrono: dispara num ciclo, lê a resposta no seguinte)
create table public.asaas_verificacoes (
  request_id bigint primary key,
  lancamento_id uuid not null references public.lancamentos (id) on delete cascade,
  tipo text not null check (tipo in ('cliente', 'pagamento')),
  criado_em timestamptz not null default now()
);
alter table public.asaas_verificacoes enable row level security; -- interna: só a função (definer) e o postgres escrevem
revoke all on public.asaas_verificacoes from public, anon, authenticated;

create or replace function public.asaas_reconciliar_agendado()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_token text; r record; v_req bigint; j jsonb; cid text; pagamentos jsonb; match jsonb; v_data date;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'asaas_api_key' limit 1;
  if v_token is null then return; end if;
  perform set_config('erp.motor', 'on', true);

  -- 2) processa as respostas que já chegaram
  for r in
    select v.request_id, v.lancamento_id, v.tipo, h.status_code, h.content,
           l.status as lanc_status, l.valor, l.data_vencimento, l.pessoa_id
      from public.asaas_verificacoes v
      join net._http_response h on h.id = v.request_id
      join public.lancamentos l on l.id = v.lancamento_id
  loop
    begin
      if r.lanc_status <> 'previsto' then
        null; -- já resolvida por outro caminho (manual, estorno etc.)
      elsif r.status_code = 200 then
        j := r.content::jsonb;
        if r.tipo = 'cliente' then
          cid := j->'data'->0->>'id';
          if cid is not null then
            update public.pessoas set asaas_customer_id = cid where id = r.pessoa_id;
            select net.http_get(
              url := 'https://api.asaas.com/v3/payments?customer=' || cid || '&limit=20',
              headers := jsonb_build_object('access_token', v_token), timeout_milliseconds := 15000
            ) into v_req;
            insert into public.asaas_verificacoes (request_id, lancamento_id, tipo) values (v_req, r.lancamento_id, 'pagamento');
          end if;
        else
          pagamentos := coalesce(j->'data', '[]'::jsonb);
          select x into match from jsonb_array_elements(pagamentos) x
           where x->>'status' in ('RECEIVED', 'CONFIRMED', 'RECEIVED_IN_CASH')
             and (x->>'value')::numeric = r.valor and (x->>'dueDate')::date = r.data_vencimento
           limit 1;
          if match is not null then
            v_data := coalesce(nullif(match->>'paymentDate', '')::date, nullif(match->>'clientPaymentDate', '')::date, current_date);
            perform public.pix_efetivar_interno(r.lancamento_id, v_data, 0, null);
          end if;
        end if;
      end if;
    exception when others then
      null; -- tenta de novo no próximo ciclo
    end;
    delete from public.asaas_verificacoes where request_id = r.request_id;
  end loop;

  -- requisição sem resposta em 5 min é descartada (libera nova tentativa)
  delete from public.asaas_verificacoes where criado_em < now() - interval '5 minutes';

  -- 1) dispara as consultas para cada lançamento elegível sem requisição em voo
  for r in
    select l.id as lancamento_id, pe.documento, pe.asaas_customer_id
      from public.lancamentos l
      join public.contratos c on c.id = l.contrato_id
      join public.negocios n on n.id = c.negocio_id
      join public.notificacoes_config cfg on cfg.negocio_id = n.id
      join public.pessoas pe on pe.id = l.pessoa_id
     where l.status = 'previsto' and l.tipo = 'receita' and cfg.asaas_ativo and c.forma_pagamento = 'boleto'
       and pe.documento is not null
       and not exists (select 1 from public.asaas_verificacoes v where v.lancamento_id = l.id)
     order by l.data_vencimento
     limit 20
  loop
    if r.asaas_customer_id is not null then
      select net.http_get(
        url := 'https://api.asaas.com/v3/payments?customer=' || r.asaas_customer_id || '&limit=20',
        headers := jsonb_build_object('access_token', v_token), timeout_milliseconds := 15000
      ) into v_req;
      insert into public.asaas_verificacoes (request_id, lancamento_id, tipo) values (v_req, r.lancamento_id, 'pagamento');
    else
      select net.http_get(
        url := 'https://api.asaas.com/v3/customers?cpfCnpj=' || r.documento,
        headers := jsonb_build_object('access_token', v_token), timeout_milliseconds := 15000
      ) into v_req;
      insert into public.asaas_verificacoes (request_id, lancamento_id, tipo) values (v_req, r.lancamento_id, 'cliente');
    end if;
  end loop;
end;
$$;
revoke all on function public.asaas_reconciliar_agendado() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('erp-asaas-reconciliar');
exception when others then null; -- ainda não existia
end $$;

select cron.schedule('erp-asaas-reconciliar', '*/5 * * * *', $$select public.asaas_reconciliar_agendado()$$);
