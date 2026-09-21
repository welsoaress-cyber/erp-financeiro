-- =============================================================================
-- 0103 · Etapa 59 — Parcerias (clube de benefícios) no Portal do cliente
-- =============================================================================
-- Catálogo de parceiros com desconto/benefício pro cliente. Duas origens:
--   · 'leveduca': lista grande (~500), importada de planilha (CSV/XLSX) pelo
--     admin sempre que a Leveduca manda uma atualização — substitui tudo que
--     era 'leveduca' daquele negócio de uma vez (importar_parcerias_leveduca).
--   · 'servnet': acordos locais próprios, cadastrados um a um pelo admin.
-- Portal: lista com busca (nome/benefício) e filtro por categoria, sem CRUD
-- do lado do cliente — só leitura.
-- =============================================================================

create type public.origem_parceria as enum ('leveduca', 'servnet');

create table public.parcerias (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id     uuid not null references public.negocios (id),
  origem         public.origem_parceria not null default 'servnet',
  nome           text not null check (char_length(btrim(nome)) between 2 and 120),
  tipo           text check (tipo is null or char_length(tipo) <= 40),
  beneficio      text not null check (char_length(btrim(beneficio)) between 2 and 300),
  categoria      text check (categoria is null or char_length(categoria) <= 60),
  cobertura      text check (cobertura is null or char_length(cobertura) <= 60),
  foto1          text check (foto1 is null or (foto1 like 'data:image/%' and char_length(foto1) <= 400000)),
  foto2          text check (foto2 is null or (foto2 like 'data:image/%' and char_length(foto2) <= 400000)),
  foto3          text check (foto3 is null or (foto3 like 'data:image/%' and char_length(foto3) <= 400000)),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
comment on table public.parcerias is 'Clube de benefícios do Portal (etapa 59). origem=leveduca vem de importação em massa; origem=servnet é cadastro manual do admin. foto1/2/3: artes que o proprietário guarda pra compartilhar no Instagram/WhatsApp — não aparecem no Portal, só no admin.';
create index parcerias_negocio on public.parcerias (negocio_id);
create index parcerias_negocio_ativo on public.parcerias (negocio_id, ativo);
create trigger parcerias_atualizado before update on public.parcerias for each row execute function public.tg_atualizado_em();
create trigger parcerias_auditoria after insert or update or delete on public.parcerias for each row execute function public.tg_auditoria();

-- criação direta (grant) só pra origem='servnet' — a lista da Leveduca só entra pela
-- função importar_parcerias_leveduca (flag erp.motor). Depois de criada (de qualquer
-- origem), o admin pode editar (fotos, ativo, etc.) livremente — só não muda de negócio/origem.
create function public.tg_parcerias_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id or new.origem <> old.origem) then
    raise exception 'A parceria não muda de negócio/origem.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  if tg_op = 'INSERT' and new.origem = 'leveduca' and coalesce(current_setting('erp.motor', true), 'off') <> 'on' then
    raise exception 'Parceiros da Leveduca só entram pela importação.' using errcode = 'check_violation';
  end if;
  new.nome := btrim(new.nome);
  new.beneficio := btrim(new.beneficio);
  return new;
end; $$;
create trigger parcerias_protecao before insert or update on public.parcerias for each row execute function public.tg_parcerias_protecao();

alter table public.parcerias enable row level security;
create policy parcerias_select on public.parcerias for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy parcerias_insert on public.parcerias for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy parcerias_update on public.parcerias for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.parcerias from public, anon, authenticated;
grant select, insert, update on public.parcerias to authenticated;

-- -----------------------------------------------------------------------------
-- Importação em massa (Leveduca): substitui tudo que já era 'leveduca' desse negócio
-- -----------------------------------------------------------------------------
create function public.importar_parcerias_leveduca(p_negocio_id uuid, p_parceiros jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid; v_total int;
begin
  select organizacao_id into v_org from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(v_org);
  if jsonb_typeof(p_parceiros) <> 'array' then raise exception 'Lista inválida.' using errcode = 'check_violation'; end if;
  perform set_config('erp.motor', 'on', true);
  delete from public.parcerias where negocio_id = p_negocio_id and origem = 'leveduca';
  insert into public.parcerias (organizacao_id, negocio_id, origem, nome, tipo, beneficio, categoria, cobertura, ativo)
  select v_org, p_negocio_id, 'leveduca',
         btrim(x.nome), nullif(btrim(x.tipo), ''), btrim(x.beneficio), nullif(btrim(x.categoria), ''), nullif(btrim(x.cobertura), ''),
         coalesce(lower(x.status) not in ('inativo', 'não ativo', 'nao ativo'), true)
    from jsonb_to_recordset(p_parceiros) as x(nome text, tipo text, beneficio text, categoria text, cobertura text, status text)
   where btrim(coalesce(x.nome, '')) <> '' and btrim(coalesce(x.beneficio, '')) <> '';
  get diagnostics v_total = row_count;
  return v_total;
end;
$$;
revoke all on function public.importar_parcerias_leveduca(uuid, jsonb) from public, anon;
grant execute on function public.importar_parcerias_leveduca(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Portal: lista de parceiros ativos (busca/filtro de categoria são no navegador)
-- -----------------------------------------------------------------------------
create function public.portal_parcerias(p_negocio_id uuid)
returns table (id uuid, nome text, tipo text, beneficio text, categoria text, cobertura text, origem public.origem_parceria)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.nome, p.tipo, p.beneficio, p.categoria, p.cobertura, p.origem
    from public.parcerias p
   where p.negocio_id = p_negocio_id and p.ativo
   order by p.categoria nulls last, p.nome;
$$;
revoke all on function public.portal_parcerias(uuid) from public, anon;
grant execute on function public.portal_parcerias(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Relatório: parceiros cadastrados (Central de Relatórios)
-- -----------------------------------------------------------------------------
create view public.vw_rel_parcerias with (security_invoker = true) as
select p.id, p.organizacao_id, p.negocio_id, n.nome as negocio, p.origem, p.nome, p.tipo, p.categoria, p.cobertura,
       (case when p.ativo then 'Ativo' else 'Inativo' end) as situacao, p.criado_em
  from public.parcerias p
  join public.negocios n on n.id = p.negocio_id;
grant select on public.vw_rel_parcerias to authenticated;
