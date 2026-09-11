-- =============================================================================
-- 0063 · Etapa 36 — Aceite digital do contrato no portal
-- =============================================================================
-- O cliente lê o termo do contrato no portal e aceita digitalmente. Para o
-- valor jurídico ficam gravados: o TEXTO exato aceito (snapshot + hash), data
-- e hora, IP e user-agent (capturados pela Edge portal-aceite — o banco não
-- enxerga o IP) e o vínculo pessoa/contrato. Um aceite por contrato, imutável.
-- O modelo do termo é editável por negócio (portal_config.contrato_modelo) com
-- os campos {cliente}, {documento}, {plano}, {valor}, {vencimento}, {codigo},
-- {negocio} e {data_inicio}.
-- =============================================================================

alter table public.portal_config add column contrato_modelo text not null default
'TERMO DE ADESÃO — {negocio}

Cliente: {cliente} ({documento})
Contrato: {codigo} · Plano: {plano}
Valor mensal: {valor} · Vencimento: todo dia {vencimento}
Início: {data_inicio}

O cliente declara aceitar a prestação do serviço nas condições acima, incluindo a política de pagamento até o vencimento e a suspensão por inadimplência. Equipamentos cedidos em comodato permanecem propriedade do provedor e devem ser devolvidos no encerramento.'
check (char_length(contrato_modelo) between 50 and 8000);

create table public.aceites_contrato (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  contrato_id uuid not null unique references public.contratos (id),
  pessoa_id uuid not null references public.pessoas (id),
  texto text not null,
  texto_hash text not null,
  ip text,
  user_agent text,
  data_aceite timestamptz not null default now()
);
create trigger aceites_auditoria after insert or update or delete on public.aceites_contrato for each row execute function public.tg_auditoria();

-- imutável, escrita só pelo motor (service_role via Edge)
create or replace function public.tg_aceite_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Aceite é imutável.' using errcode = 'check_violation';
  end if;
  if coalesce(current_setting('erp.motor', true), '') <> 'on' then
    raise exception 'Aceite é gravado pelo motor (registrar_aceite_contrato).' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;
revoke all on function public.tg_aceite_protecao() from public, anon, authenticated;
create trigger aceites_protecao before insert or update or delete on public.aceites_contrato for each row execute function public.tg_aceite_protecao();

alter table public.aceites_contrato enable row level security;
create policy aceites_org on public.aceites_contrato for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.aceites_contrato from public, anon, authenticated;
grant select on public.aceites_contrato to authenticated;

-- Texto do termo renderizado (membro OU o próprio cliente do portal)
create function public.contrato_texto_termo(p_contrato_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare c public.contratos%rowtype; pe public.pessoas%rowtype; n public.negocios%rowtype; pl public.planos%rowtype; modelo text;
begin
  select * into c from public.contratos where id = p_contrato_id;
  if not found then raise exception 'Contrato não encontrado.' using errcode = 'no_data_found'; end if;
  if c.organizacao_id not in (select public.minhas_organizacoes())
     and c.pessoa_id is distinct from public.portal_pessoa()
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') <> 'service_role' then
    raise exception 'Sem permissão.' using errcode = 'insufficient_privilege';
  end if;
  select * into pe from public.pessoas where id = c.pessoa_id;
  select * into n from public.negocios where id = c.negocio_id;
  select * into pl from public.planos where id = c.plano_id;
  select coalesce(max(contrato_modelo), '') into modelo from public.portal_config where negocio_id = c.negocio_id;
  if modelo = '' then raise exception 'Configure o portal do negócio (modelo do termo).' using errcode = 'check_violation'; end if;
  return replace(replace(replace(replace(replace(replace(replace(replace(modelo,
    '{cliente}', pe.nome), '{documento}', coalesce(pe.documento, 'sem documento')), '{plano}', pl.nome),
    '{valor}', 'R$ ' || replace(to_char(c.valor, 'FM999G999G990D00'), '.', ',')),
    '{vencimento}', c.dia_vencimento::text), '{codigo}', '#' || lpad(c.codigo::text, 3, '0')),
    '{negocio}', n.nome), '{data_inicio}', to_char(c.data_inicio, 'DD/MM/YYYY'));
end;
$$;
revoke all on function public.contrato_texto_termo(uuid) from public, anon;
grant execute on function public.contrato_texto_termo(uuid) to authenticated, service_role;

-- Registro do aceite (service_role — a Edge captura IP e user-agent)
create function public.registrar_aceite_contrato(p_contrato_id uuid, p_pessoa_id uuid, p_ip text, p_user_agent text)
returns public.aceites_contrato
language plpgsql
security definer
set search_path = public
as $$
declare c public.contratos%rowtype; a public.aceites_contrato%rowtype; v_texto text;
begin
  select * into c from public.contratos where id = p_contrato_id;
  if not found or c.pessoa_id is distinct from p_pessoa_id then
    raise exception 'Contrato inválido para este cliente.' using errcode = 'check_violation';
  end if;
  if c.status = 'encerrado' then raise exception 'Contrato encerrado não recebe aceite.' using errcode = 'check_violation'; end if;
  if exists (select 1 from public.aceites_contrato where contrato_id = p_contrato_id) then
    raise exception 'Contrato já aceito.' using errcode = 'check_violation';
  end if;
  v_texto := public.contrato_texto_termo(p_contrato_id);
  perform set_config('erp.motor', 'on', true);
  insert into public.aceites_contrato (organizacao_id, contrato_id, pessoa_id, texto, texto_hash, ip, user_agent)
  values (c.organizacao_id, p_contrato_id, p_pessoa_id, v_texto, md5(v_texto), nullif(btrim(coalesce(p_ip, '')), ''), left(coalesce(p_user_agent, ''), 300))
  returning * into a;
  return a;
end;
$$;
revoke all on function public.registrar_aceite_contrato(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.registrar_aceite_contrato(uuid, uuid, text, text) to service_role;

-- Portal: situação dos aceites do cliente
create function public.portal_meus_aceites()
returns table (contrato_id uuid, codigo integer, negocio text, plano text, aceito boolean, data_aceite timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.codigo, n.nome, pl.nome, a.id is not null, a.data_aceite
    from public.contratos c
    join public.negocios n on n.id = c.negocio_id
    join public.planos pl on pl.id = c.plano_id
    left join public.aceites_contrato a on a.contrato_id = c.id
   where c.pessoa_id = public.portal_pessoa() and c.status <> 'encerrado' and c.tipo_financeiro = 'receita'
   order by c.criado_em desc;
$$;
revoke all on function public.portal_meus_aceites() from public, anon;
grant execute on function public.portal_meus_aceites() to authenticated;
