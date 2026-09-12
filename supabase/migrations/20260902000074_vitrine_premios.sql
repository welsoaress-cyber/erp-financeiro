-- =============================================================================
-- 0074 · Etapa 49 — Vitrine de prêmios no portal (Indique e Ganhe)
-- =============================================================================
-- A escolha do presente vira visual e do próprio cliente:
--   · Faixas da campanha viram CONFIGURAÇÃO por negócio (indicacao_faixas):
--     plano do indicado até R$ X → faixa N (teto de prêmio R$ Y). Sem faixas
--     cadastradas vale a régua antiga (≤60→30, ≤80→50, acima→80).
--   · Prêmios viram CADASTRO (indicacao_premios): foto (data URL comprimida no
--     navegador, sem Storage), nome, faixa e vínculo ao item do Estoque na
--     categoria Brindes. Prêmio sem saldo em estoque some da vitrine.
--   · Portal: vitrine em grade por faixa do plano que o INDICADO fechou;
--     escolha confirma e trava (regra de sempre: sem troca).
--   · Conversão dispara aviso WhatsApp ao indicante pela régua já existente
--     (tipo indicacao_convertida) com link do portal (portal_config.url_portal).
--   · Vitrine pública sem login (vitrine_publica) para divulgação — só nome,
--     foto e faixa dos prêmios; nenhum dado de cliente. Mesmo padrão anon da
--     página pública de indicação (0023).
-- =============================================================================

alter type public.tipo_notificacao add value if not exists 'indicacao_convertida';

-- o novo tipo é um aviso sem fatura vinculada (como teste/os_*)
alter table public.notificacoes_log drop constraint notificacoes_log_lancamento_chk;
alter table public.notificacoes_log add constraint notificacoes_log_lancamento_chk
  check ((lancamento_id is null) = (tipo::text in ('teste', 'os_agendada', 'os_encerrada', 'indicacao_convertida')));

alter table public.portal_config add column url_portal text check (url_portal is null or url_portal ~ '^https://');
comment on column public.portal_config.url_portal is 'Endereço do portal do cliente (para links em avisos WhatsApp).';

-- -----------------------------------------------------------------------------
-- Faixas configuráveis
-- -----------------------------------------------------------------------------
create table public.indicacao_faixas (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  faixa smallint not null check (faixa between 1 and 9),
  nome text not null check (char_length(btrim(nome)) between 2 and 60),
  plano_ate numeric(14,2) check (plano_ate is null or plano_ate > 0),
  teto numeric(14,2) not null check (teto > 0),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (negocio_id, faixa)
);
comment on table public.indicacao_faixas is 'Faixas da campanha: plano do indicado com mensalidade até plano_ate cai nesta faixa (teto = valor máximo do prêmio). plano_ate null = pega tudo acima das demais.';
create trigger indicacao_faixas_atualizado before update on public.indicacao_faixas for each row execute function public.tg_atualizado_em();
create trigger indicacao_faixas_auditoria after insert or update or delete on public.indicacao_faixas for each row execute function public.tg_auditoria();

create function public.tg_indicacao_faixas_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A faixa não muda de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  new.nome := btrim(new.nome);
  return new;
end; $$;
create trigger indicacao_faixas_protecao before insert or update on public.indicacao_faixas for each row execute function public.tg_indicacao_faixas_protecao();

alter table public.indicacao_faixas enable row level security;
create policy indicacao_faixas_select on public.indicacao_faixas for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacao_faixas_insert on public.indicacao_faixas for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacao_faixas_update on public.indicacao_faixas for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.indicacao_faixas from public, anon, authenticated;
grant select, insert, update on public.indicacao_faixas to authenticated;

-- -----------------------------------------------------------------------------
-- Prêmios da vitrine
-- -----------------------------------------------------------------------------
create table public.indicacao_premios (
  id uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id),
  negocio_id uuid not null references public.negocios (id),
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  foto text check (foto is null or (foto like 'data:image/%' and char_length(foto) <= 400000)),
  faixa smallint not null check (faixa between 1 and 9),
  item_id uuid not null references public.estoque_itens (id) on delete restrict,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
comment on table public.indicacao_premios is 'Vitrine do Indique e Ganhe: prêmio com foto (data URL ≤ 400 KB), faixa e item do Estoque (categoria Brindes). Sem saldo no item → some da vitrine.';
create index indicacao_premios_negocio on public.indicacao_premios (negocio_id, faixa);
create trigger indicacao_premios_atualizado before update on public.indicacao_premios for each row execute function public.tg_atualizado_em();
create trigger indicacao_premios_auditoria after insert or update or delete on public.indicacao_premios for each row execute function public.tg_auditoria();

create function public.tg_indicacao_premios_protecao()
returns trigger language plpgsql set search_path = public as $$
declare it public.estoque_itens%rowtype;
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'O prêmio não muda de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  select * into it from public.estoque_itens where id = new.item_id;
  if not found or it.organizacao_id <> new.organizacao_id then
    raise exception 'Item de estoque inválido.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.estoque_categorias ec where ec.id = it.categoria_id and lower(ec.nome) like 'brinde%') then
    raise exception 'O prêmio precisa apontar para um item da categoria Brindes do Estoque.' using errcode = 'check_violation';
  end if;
  new.nome := btrim(new.nome);
  return new;
end; $$;
create trigger indicacao_premios_protecao before insert or update on public.indicacao_premios for each row execute function public.tg_indicacao_premios_protecao();

alter table public.indicacao_premios enable row level security;
create policy indicacao_premios_select on public.indicacao_premios for select to authenticated using (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacao_premios_insert on public.indicacao_premios for insert to authenticated with check (organizacao_id in (select public.minhas_organizacoes()));
create policy indicacao_premios_update on public.indicacao_premios for update to authenticated using (organizacao_id in (select public.minhas_organizacoes())) with check (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.indicacao_premios from public, anon, authenticated;
grant select, insert, update on public.indicacao_premios to authenticated;

-- escolha do portal grava também o prêmio (a foto/nome exibidos); só via motor
alter table public.indicacoes add column presente_premio_id uuid references public.indicacao_premios (id) on delete restrict;

create or replace function public.tg_indicacoes_protecao()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.indicador_pessoa_id <> old.indicador_pessoa_id or new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id then
      raise exception 'Indicador e negócio da indicação não mudam.' using errcode = 'check_violation';
    end if;
    if old.status = 'convertida' and new.status <> 'convertida' then
      raise exception 'Indicação convertida não volta atrás.' using errcode = 'check_violation';
    end if;
    if new.status = 'convertida' and old.status <> 'convertida' then
      if not public.motor_ativo() then
        raise exception 'Use converter_indicacao() para converter.' using errcode = 'check_violation';
      end if;
      new.convertida_em := coalesce(new.convertida_em, now());
    end if;
    if old.presente_item_id is not null and new.presente_item_id is distinct from old.presente_item_id then
      raise exception 'Presente escolhido não pode ser trocado.' using errcode = 'check_violation';
    end if;
    if (new.presente_item_id is distinct from old.presente_item_id
        or new.presente_premio_id is distinct from old.presente_premio_id
        or new.presente_custo is distinct from old.presente_custo
        or new.presente_entregue_em is distinct from old.presente_entregue_em)
       and not public.motor_ativo() then
      raise exception 'Use escolher_presente_indicacao() / entregar_presente_indicacao().' using errcode = 'check_violation';
    end if;
  end if;
  new.nome_indicado := btrim(new.nome_indicado);
  new.telefone_indicado := regexp_replace(new.telefone_indicado, '[^0-9]', '', 'g');
  return new;
end; $$;

-- -----------------------------------------------------------------------------
-- Faixa da indicação: pela config; sem config vale a régua antiga
-- -----------------------------------------------------------------------------
create function public.faixa_da_indicacao(p_indicacao_id uuid)
returns table (faixa smallint, nome text, teto numeric)
language sql
stable
security definer
set search_path = public
as $$
  with i as (
    select ind.negocio_id, c.valor
      from public.indicacoes ind
      join public.contratos c on c.pessoa_id = ind.indicado_pessoa_id and c.negocio_id = ind.negocio_id
     where ind.id = p_indicacao_id
     order by c.criado_em desc
     limit 1
  ), cfg as (
    select f.faixa, f.nome, f.teto
      from public.indicacao_faixas f, i
     where f.negocio_id = i.negocio_id and f.ativo
       and (f.plano_ate is null or i.valor <= f.plano_ate)
     order by f.plano_ate asc nulls last
     limit 1
  )
  select * from cfg
  union all
  select case when i.valor <= 60 then 1 when i.valor <= 80 then 2 else 3 end::smallint,
         case when i.valor <= 60 then '1ª faixa' when i.valor <= 80 then '2ª faixa' else '3ª faixa' end,
         case when i.valor <= 60 then 30 when i.valor <= 80 then 50 else 80 end::numeric
    from i
   where not exists (select 1 from cfg)
$$;
revoke all on function public.faixa_da_indicacao(uuid) from public, anon;
grant execute on function public.faixa_da_indicacao(uuid) to authenticated;

-- Vitrine da indicação: prêmios cadastrados da faixa, com saldo em estoque.
-- Sem prêmio cadastrado para a faixa, vale a lista antiga por custo do item.
drop function public.portal_presentes_indicacao(uuid);
create function public.portal_presentes_indicacao(p_indicacao_id uuid)
returns table (premio_id uuid, item_id uuid, nome text, foto text, ja_escolhido boolean)
language sql
stable
security definer
set search_path = public
as $$
  with i as (
    select * from public.indicacoes
     where id = p_indicacao_id and indicador_pessoa_id = public.portal_pessoa() and status = 'convertida'
  ), f as (select * from public.faixa_da_indicacao(p_indicacao_id)),
  premios as (
    select p.id as premio_id, p.item_id, p.nome, p.foto,
           coalesce((select i2.presente_premio_id from i i2) = p.id, (select i2.presente_item_id from i i2) = p.item_id, false) as ja_escolhido
      from public.indicacao_premios p, i, f
     where p.negocio_id = i.negocio_id and p.ativo and p.faixa = f.faixa
       and exists (select 1 from public.estoque_itens it where it.id = p.item_id and it.ativo and it.quantidade_atual >= 1)
  )
  select * from premios
  union all
  -- fallback sem prêmios cadastrados: régua antiga por custo do item (piso/teto)
  select null::uuid, it.id, it.nome, null::text, (select presente_item_id from i) = it.id
    from public.estoque_itens it, i, public.faixa_presente_indicacao(p_indicacao_id) fp
   where not exists (select 1 from premios)
     and it.negocio_id = i.negocio_id and it.ativo and it.quantidade_atual >= 1
     and it.categoria_id in (select ec.id from public.estoque_categorias ec where ec.negocio_id = i.negocio_id and lower(ec.nome) like 'brinde%')
     and coalesce(it.valor_custo, 0) > fp.piso and coalesce(it.valor_custo, 0) <= fp.teto
   order by nome
$$;
revoke all on function public.portal_presentes_indicacao(uuid) from public, anon;
grant execute on function public.portal_presentes_indicacao(uuid) to authenticated;

-- escolha pelo portal: valida contra a vitrine e grava item + prêmio (trava)
create or replace function public.portal_escolher_presente(p_indicacao_id uuid, p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare i public.indicacoes%rowtype; v_premio uuid;
begin
  select * into i from public.indicacoes where id = p_indicacao_id and indicador_pessoa_id = public.portal_pessoa() for update;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  if i.status <> 'convertida' then
    raise exception 'O presente é escolhido depois que o seu indicado é instalado.' using errcode = 'check_violation';
  end if;
  if i.presente_item_id is not null then
    raise exception 'Você já escolheu o presente desta indicação — a campanha não permite troca.' using errcode = 'check_violation';
  end if;
  select o.premio_id into v_premio from public.portal_presentes_indicacao(p_indicacao_id) o where o.item_id = p_item_id limit 1;
  if not found then
    raise exception 'Este presente não está disponível para a faixa do plano do seu indicado.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.indicacoes set presente_item_id = p_item_id, presente_premio_id = v_premio where id = p_indicacao_id;
end;
$$;

-- lista do portal ganha o nome/foto do prêmio (quando escolhido pela vitrine)
drop function public.portal_indicacoes();
create function public.portal_indicacoes()
returns table (id uuid, negocio text, nome_indicado text, status public.status_indicacao, beneficio_valor numeric, criado_em timestamptz,
               convertida_em timestamptz, presente_item_id uuid, presente text, presente_foto text, presente_entregue_em date, aguardando_escolha boolean)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, n.nome, i.nome_indicado, i.status, i.beneficio_valor, i.criado_em,
         i.convertida_em, i.presente_item_id, coalesce(pr.nome, it.nome), pr.foto, i.presente_entregue_em,
         (i.status = 'convertida' and i.presente_item_id is null)
    from public.indicacoes i
    join public.negocios n on n.id = i.negocio_id
    left join public.estoque_itens it on it.id = i.presente_item_id
    left join public.indicacao_premios pr on pr.id = i.presente_premio_id
   where i.indicador_pessoa_id = public.portal_pessoa()
   order by i.criado_em desc;
$$;
revoke all on function public.portal_indicacoes() from public, anon;
grant execute on function public.portal_indicacoes() to authenticated;

-- -----------------------------------------------------------------------------
-- Aviso WhatsApp na conversão (régua existente; tipo indicacao_convertida)
-- -----------------------------------------------------------------------------
create or replace function public.converter_indicacao(p_indicacao_id uuid, p_indicado_pessoa_id uuid)
returns public.indicacoes
language plpgsql security definer set search_path = public as $$
declare i public.indicacoes%rowtype; pc public.portal_config%rowtype; c public.contratos%rowtype; v_desc uuid; v_valor numeric(14,2) := 0; v_motivo text;
        cfg public.notificacoes_config%rowtype; pe public.pessoas%rowtype; v_msg text;
begin
  select * into i from public.indicacoes where id = p_indicacao_id;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(i.organizacao_id);
  if i.status <> 'pendente' then raise exception 'Só indicações pendentes podem ser convertidas.' using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.pessoas where id = p_indicado_pessoa_id and organizacao_id = i.organizacao_id) then
    raise exception 'Pessoa indicada inválida.' using errcode = 'check_violation';
  end if;
  if p_indicado_pessoa_id = i.indicador_pessoa_id then raise exception 'O indicado não pode ser o próprio indicador.' using errcode = 'check_violation'; end if;
  select * into pc from public.portal_config where negocio_id = i.negocio_id;
  select * into c from public.contratos where pessoa_id = i.indicador_pessoa_id and negocio_id = i.negocio_id and status = 'ativo' order by data_inicio desc limit 1;
  perform set_config('erp.motor', 'on', true);
  if found and pc.id is not null then
    if pc.beneficio_tipo = 'mes_gratis' then v_valor := c.valor; v_motivo := 'Indique e Ganhe: 1 mês grátis (indicação de ' || i.nome_indicado || ')';
    else v_valor := pc.beneficio_indicacao; v_motivo := 'Indique e Ganhe: indicação de ' || i.nome_indicado; end if;
    if v_valor > 0 then
      insert into public.descontos_contrato (organizacao_id, contrato_id, valor, motivo, indicacao_id, referencia)
      values (i.organizacao_id, c.id, v_valor, v_motivo, i.id, 'indicacao:' || i.id::text) returning id into v_desc;
    end if;
  end if;
  update public.indicacoes set status = 'convertida', indicado_pessoa_id = p_indicado_pessoa_id, beneficio_valor = case when v_desc is null then 0 else v_valor end, desconto_id = v_desc
   where id = i.id returning * into i;
  -- aviso ao indicante: presente liberado (sai pela fila/régua já configurada)
  select * into cfg from public.notificacoes_config where negocio_id = i.negocio_id;
  select * into pe from public.pessoas where id = i.indicador_pessoa_id;
  if cfg.id is not null and cfg.ativo and pe.receber_avisos and pe.telefone is not null then
    v_msg := '🎁 Boa notícia, ' || split_part(pe.nome, ' ', 1) || '! Sua indicação (' || i.nome_indicado || ') foi instalada e o seu presente está liberado. Entre no portal e escolha o seu:'
             || case when pc.url_portal is not null then e'\n' || pc.url_portal else '' end;
    insert into public.notificacoes_log (organizacao_id, negocio_id, contrato_id, pessoa_id, tipo, data_referencia, numero_destino, mensagem, status, provedor, data_envio)
    values (i.organizacao_id, i.negocio_id, c.id, i.indicador_pessoa_id, 'indicacao_convertida', current_date, public.numero_e164(pe.telefone), v_msg,
            case when cfg.provedor::text = 'simulado' then 'simulado' else 'pendente' end::public.status_notificacao, cfg.provedor,
            case when cfg.provedor::text = 'simulado' then now() end);
  end if;
  return i;
end; $$;

-- -----------------------------------------------------------------------------
-- Vitrine pública (sem login) — divulgação da campanha; nenhum dado de cliente.
-- Mesmo padrão anon da página pública de indicação (0023).
-- -----------------------------------------------------------------------------
create function public.vitrine_publica(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'negocio', n.nome,
    'cor', coalesce(pc.cor_primaria, '#1e3a8a'),
    'logo', pc.logo_url,
    'texto', pc.texto_promocional,
    'faixas', coalesce((
      select jsonb_agg(jsonb_build_object('faixa', f.faixa, 'nome', f.nome, 'teto', f.teto) order by f.faixa)
        from public.indicacao_faixas f where f.negocio_id = n.id and f.ativo), '[]'::jsonb),
    'premios', coalesce((
      select jsonb_agg(jsonb_build_object('nome', p.nome, 'foto', p.foto, 'faixa', p.faixa) order by p.faixa, p.nome)
        from public.indicacao_premios p
       where p.negocio_id = n.id and p.ativo
         and exists (select 1 from public.estoque_itens it where it.id = p.item_id and it.ativo and it.quantidade_atual >= 1)), '[]'::jsonb))
    from public.negocios n
    left join public.portal_config pc on pc.negocio_id = n.id
   where n.slug = lower(btrim(coalesce(p_slug, ''))) and n.ativo and coalesce(pc.ativo, false);
$$;
revoke all on function public.vitrine_publica(text) from public;
grant execute on function public.vitrine_publica(text) to anon, authenticated;
