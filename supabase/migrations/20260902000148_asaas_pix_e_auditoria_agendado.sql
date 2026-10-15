-- =============================================================================
-- 0148 · asaas_reconciliar_agendado passa a cobrir Pix também + grava auditoria
-- =============================================================================
-- Pedido do proprietário: alguns clientes da Servnet pagam por Pix pela MESMA
-- conta Asaas (não é outro sistema) — a trava de forma_pagamento passa a
-- aceitar 'boleto' OU 'pix' (continua sem tocar quem usa Mercado Pago, que é
-- outro provedor). Toda baixa automática agora também grava uma linha em
-- asaas_baixas_automaticas (0147), base do relatório de conferência.
-- =============================================================================

create or replace function public.asaas_reconciliar_agendado()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_token text; r record; v_req bigint; j jsonb; cid text; pagamentos jsonb; match jsonb; divergente jsonb; v_data date; v_forma public.forma_pagamento_contrato;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'asaas_api_key' limit 1;
  if v_token is null then return; end if;
  perform set_config('erp.motor', 'on', true);

  -- divergência de lançamento que não está mais previsto (resolvido por outro caminho) não faz mais sentido
  delete from public.asaas_divergencias d
   where not exists (select 1 from public.lancamentos l where l.id = d.lancamento_id and l.status = 'previsto');

  -- 2) processa as respostas que já chegaram
  for r in
    select v.request_id, v.lancamento_id, v.tipo, h.status_code, h.content,
           l.organizacao_id, l.status as lanc_status, l.valor, l.data_vencimento, l.pessoa_id, l.negocio_id, c.forma_pagamento
      from public.asaas_verificacoes v
      join net._http_response h on h.id = v.request_id
      join public.lancamentos l on l.id = v.lancamento_id
      left join public.contratos c on c.id = l.contrato_id
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
            delete from public.asaas_divergencias where lancamento_id = r.lancamento_id;
            insert into public.asaas_baixas_automaticas (organizacao_id, lancamento_id, pessoa_id, negocio_id, valor, data_pagamento, forma_pagamento, pagamento)
            values (r.organizacao_id, r.lancamento_id, r.pessoa_id, r.negocio_id, r.valor, v_data, r.forma_pagamento, match);
          else
            select x into divergente from jsonb_array_elements(pagamentos) x
             where x->>'status' in ('RECEIVED', 'CONFIRMED', 'RECEIVED_IN_CASH')
             order by x->>'dueDate' desc limit 1;
            if divergente is not null then
              insert into public.asaas_divergencias (organizacao_id, lancamento_id, pessoa_id, valor_esperado, vencimento_esperado, pagamento)
              values (r.organizacao_id, r.lancamento_id, r.pessoa_id, r.valor, r.data_vencimento, divergente)
              on conflict (lancamento_id) do update set pagamento = excluded.pagamento, detectado_em = now();
            end if;
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
     where l.status = 'previsto' and l.tipo = 'receita' and cfg.asaas_ativo and c.forma_pagamento in ('boleto', 'pix')
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
