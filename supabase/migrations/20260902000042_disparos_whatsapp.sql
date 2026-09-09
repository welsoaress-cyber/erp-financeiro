-- =============================================================================
-- 0042 · Módulo Disparos WhatsApp (etapa 26)
-- =============================================================================
-- Disparo manual de mensagens (máx. 30 por vez) para clientes identificados
-- pelo LOGIN DO SERVIDOR extraído de um PDF de receitas. Modelos editáveis,
-- fila própria enviada pela Edge Function disparos-enviar (mesma Evolution API
-- das notificações, instância do negócio, intervalo de 15 s), histórico por
-- item e reenvio de falhas. Opcional: a tela lança a cobrança no contas a
-- receber pelo motor (criar_lancamento), fora desta migration.
-- =============================================================================

-- Login do servidor na pessoa: vínculo com o PDF (match exato, sem espaços)
alter table public.pessoas add column login_servidor text
  check (login_servidor is null or login_servidor ~ '^[A-Za-z0-9._@-]{2,60}$');
comment on column public.pessoas.login_servidor is 'Login do cliente no servidor (IPTV); usado para casar o PDF de receitas com o cadastro.';
create unique index pessoas_login_servidor_unico on public.pessoas (organizacao_id, lower(login_servidor)) where login_servidor is not null;

-- -----------------------------------------------------------------------------
-- Modelos de mensagem (CRUD do usuário)
-- -----------------------------------------------------------------------------
create table public.disparo_modelos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  nome text not null check (char_length(btrim(nome)) between 2 and 60),
  texto text not null check (char_length(texto) between 10 and 2000),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (organizacao_id, nome)
);
create trigger disparo_modelos_atualizado before update on public.disparo_modelos for each row execute function public.tg_atualizado_em();
alter table public.disparo_modelos enable row level security;
create policy disparo_modelos_org on public.disparo_modelos
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.disparo_modelos from public, anon, authenticated;
grant select, insert, update on public.disparo_modelos to authenticated;

-- Dois modelos padrão para as organizações existentes (novas criam pela tela)
insert into public.disparo_modelos (organizacao_id, nome, texto)
select o.id, m.nome, m.texto
  from public.organizacoes o
 cross join (values
   ('Lembrete de vencimento', e'⚠️ *Lembrete* ☝️\n\n_Olá {nome}, como você está?_\n_Espero que esteja aproveitando ao máximo nossa plataforma!_\n\n_Gostaria de lhe lembrar que o vencimento está se aproximando:_ ☝️\U0001f979\n\n_Estamos constantemente atualizando nosso catálogo com novos conteúdos exclusivos!_\n\n_Agradecemos sua confiança e estamos à disposição para qualquer dúvida ou assistência._\n\nTom'),
   ('Interrupção no serviço', e'⚠️ *Interrupção no serviço* ☝️\n\n_Olá {nome}._\n_Infelizmente não identificamos o pagamento da renovação, com isso, seu login foi temporariamente bloqueado_ \U0001f614\n\n_Agradecemos sua confiança e estamos à disposição para qualquer dúvida ou assistência._\n\nTom')
 ) as m (nome, texto)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Disparos e itens (gravados só pelo motor)
-- -----------------------------------------------------------------------------
create type public.status_disparo as enum ('pendente', 'enviado', 'erro');

create table public.disparos (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  modelo_nome text not null,
  criado_em timestamptz not null default now()
);
create table public.disparo_itens (
  id uuid primary key default gen_random_uuid(),
  disparo_id uuid not null references public.disparos (id),
  organizacao_id uuid not null references public.organizacoes (id),
  pessoa_id uuid not null references public.pessoas (id),
  numero_destino text not null,
  mensagem text not null check (char_length(mensagem) between 10 and 2000),
  status public.status_disparo not null default 'pendente',
  tentativas smallint not null default 0,
  erro text,
  resposta_provedor jsonb,
  data_envio timestamptz,
  criado_em timestamptz not null default now()
);
create index disparo_itens_disparo on public.disparo_itens (disparo_id);
create index disparo_itens_fila on public.disparo_itens (status) where status = 'pendente';

create or replace function public.tg_disparos_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Disparos são gravados só pelo motor (criar_disparo).' using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.tg_disparos_protecao() from public, anon, authenticated;
create trigger disparos_protecao before insert or update or delete on public.disparos for each row execute function public.tg_disparos_protecao();
create trigger disparo_itens_protecao before insert or update or delete on public.disparo_itens for each row execute function public.tg_disparos_protecao();

alter table public.disparos enable row level security;
alter table public.disparo_itens enable row level security;
create policy disparos_org on public.disparos
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
create policy disparo_itens_org on public.disparo_itens
  using (organizacao_id in (select public.minhas_organizacoes()))
  with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.disparos, public.disparo_itens from public, anon, authenticated;
grant select, insert, update on public.disparos, public.disparo_itens to authenticated;

-- -----------------------------------------------------------------------------
-- Motor: criar disparo (máx. 30 itens, telefone obrigatório, E.164)
-- -----------------------------------------------------------------------------
create function public.criar_disparo(p_negocio_id uuid, p_modelo_nome text, p_itens jsonb)
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
    insert into public.disparo_itens (disparo_id, organizacao_id, pessoa_id, numero_destino, mensagem)
    values (d.id, n.organizacao_id, pe.id, public.numero_e164(pe.telefone), it->>'mensagem');
  end loop;
  return d;
end;
$$;
revoke all on function public.criar_disparo(uuid, text, jsonb) from public, anon;
grant execute on function public.criar_disparo(uuid, text, jsonb) to authenticated;

-- Reenviar só as falhas de um disparo
create function public.reenviar_falhas_disparo(p_disparo_id uuid)
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
  update public.disparo_itens set status = 'pendente', tentativas = 0, erro = null
   where disparo_id = p_disparo_id and status = 'erro';
  get diagnostics v = row_count;
  return v;
end;
$$;
revoke all on function public.reenviar_falhas_disparo(uuid) from public, anon;
grant execute on function public.reenviar_falhas_disparo(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Interface para a Edge Function disparos-enviar (só service_role)
-- -----------------------------------------------------------------------------
-- Poucos por chamada: a Edge espera 15 s entre mensagens; a tela re-dispara
-- enquanto houver pendentes.
create function public.disparos_para_envio(p_limite integer default 3)
returns table (id uuid, instancia text, numero_destino text, mensagem text, tentativas smallint)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  return query
    select i.id, cfg.instancia, i.numero_destino, i.mensagem, i.tentativas
      from public.disparo_itens i
      join public.disparos d on d.id = i.disparo_id
      join public.notificacoes_config cfg on cfg.negocio_id = d.negocio_id
     where i.status = 'pendente' and cfg.ativo
       and cfg.provedor::text = 'evolution' and cfg.instancia is not null
       and i.tentativas < 5
     order by i.criado_em
     limit p_limite;
end;
$$;

create function public.registrar_resultado_disparo(p_id uuid, p_ok boolean, p_erro text default null, p_resposta jsonb default null, p_contar boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('erp.motor', 'on', true);
  if p_ok then
    update public.disparo_itens set status = 'enviado', data_envio = now(), erro = null, resposta_provedor = p_resposta, tentativas = tentativas + 1
     where id = p_id and status = 'pendente';
  else
    update public.disparo_itens
       set tentativas = tentativas + (case when p_contar then 1 else 0 end), erro = left(p_erro, 500), resposta_provedor = p_resposta,
           status = case when p_contar and tentativas + 1 >= 5 then 'erro'::public.status_disparo else status end
     where id = p_id and status = 'pendente';
  end if;
end;
$$;
revoke all on function public.disparos_para_envio(integer), public.registrar_resultado_disparo(uuid, boolean, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.disparos_para_envio(integer), public.registrar_resultado_disparo(uuid, boolean, text, jsonb, boolean) to service_role;

-- RPC da tela: aciona a Edge Function sem expor segredos (mesmo padrão da 0020)
create function public.processar_disparos()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_url text; v_secret text; v_req bigint;
begin
  if not exists (select public.minhas_organizacoes()) then
    raise exception 'Sem organização.' using errcode = 'insufficient_privilege';
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'notificacoes_cron_secret';
  if v_url is null or v_secret is null then
    raise exception 'Envio real não configurado (segredos project_url / notificacoes_cron_secret ausentes no Vault).' using errcode = 'check_violation';
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/disparos-enviar',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  ) into v_req;
  return v_req;
end;
$$;
revoke all on function public.processar_disparos() from public, anon;
grant execute on function public.processar_disparos() to authenticated;
