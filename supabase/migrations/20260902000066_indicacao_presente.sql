-- =============================================================================
-- 0066 · Etapa 40 — Indique e Ganhe com presente físico (campanha)
-- =============================================================================
-- Campanha "indique um amigo e escolha seu presente": o admin registra a
-- indicação recebida pelo WhatsApp; na conversão (indicado instalado) o
-- indicante ESCOLHE o presente (sem troca depois); a ENTREGA deve sair em
-- até 10 dias úteis — a baixa vai pelo motor de estoque (origem 'brinde')
-- e o custo fica gravado na indicação, para o ROI ser derivado.
-- Dedupe: telefone já indicado não repete; telefone que já é de cliente
-- (pessoa com contrato) não conta — regras da campanha.
-- =============================================================================

alter type public.origem_movimentacao_estoque add value if not exists 'brinde';

alter table public.indicacoes
  add column convertida_em timestamptz,
  add column presente_item_id uuid references public.estoque_itens (id) on delete restrict,
  add column presente_custo numeric check (presente_custo is null or presente_custo >= 0),
  add column presente_entregue_em date;
comment on column public.indicacoes.convertida_em is 'Quando o indicado virou cliente — o prazo de entrega do presente (10 dias úteis) conta daqui.';
comment on column public.indicacoes.presente_custo is 'Custo médio do item no dia da entrega — congela o custo da campanha.';

-- proteção: presente só muda pelo motor; escolha feita não troca; carimbo da conversão
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

-- a saída de estoque passa a aceitar a origem 'brinde'
create or replace function public.saida_estoque(p_item_id uuid, p_quantidade numeric, p_origem text, p_data date, p_pessoa_id uuid, p_contrato_id uuid, p_observacao text, p_instalacao_id uuid)
returns public.estoque_movimentacoes
language plpgsql
security definer
set search_path = public
as $$
declare it public.estoque_itens%rowtype; m public.estoque_movimentacoes%rowtype;
begin
  select * into it from public.estoque_itens where id = p_item_id;
  if not found then raise exception 'Item não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(it.organizacao_id);
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'Quantidade da saída deve ser maior que zero.' using errcode = 'check_violation'; end if;
  if p_origem not in ('instalacao', 'perda', 'brinde') then raise exception 'Origem de saída inválida.' using errcode = 'check_violation'; end if;
  if p_quantidade > it.quantidade_atual then
    raise exception 'Saída de % maior que o estoque disponível (% %).', it.nome, it.quantidade_atual, it.unidade_medida using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.estoque_itens set quantidade_atual = quantidade_atual - p_quantidade where id = p_item_id;
  insert into public.estoque_movimentacoes (organizacao_id, negocio_id, item_id, tipo, origem, quantidade, valor_unitario, valor_total, data, pessoa_id, contrato_id, instalacao_id, observacao, usuario_id)
  values (it.organizacao_id, it.negocio_id, p_item_id, 'saida', p_origem::public.origem_movimentacao_estoque, p_quantidade, it.valor_custo, round(p_quantidade * it.valor_custo, 2), coalesce(p_data, current_date), p_pessoa_id, p_contrato_id, p_instalacao_id, p_observacao, auth.uid())
  returning * into m;
  return m;
end;
$$;

-- admin registra indicação recebida fora do portal (WhatsApp, status)
create function public.criar_indicacao_admin(p_negocio_id uuid, p_indicador_pessoa_id uuid, p_nome text, p_telefone text)
returns public.indicacoes
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; i public.indicacoes%rowtype; v_tel text;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if not exists (select 1 from public.pessoas p where p.id = p_indicador_pessoa_id and p.organizacao_id = n.organizacao_id) then
    raise exception 'Indicante não encontrado.' using errcode = 'no_data_found';
  end if;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  if v_tel !~ '^[0-9]{10,13}$' then
    raise exception 'Telefone do indicado inválido (DDD + número).' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.indicacoes where negocio_id = p_negocio_id and telefone_indicado = v_tel and status <> 'cancelada') then
    raise exception 'Este telefone já foi indicado.' using errcode = 'check_violation';
  end if;
  -- regra da campanha: quem já é (ou já foi) cliente não conta
  if exists (
    select 1 from public.pessoas p
     where p.organizacao_id = n.organizacao_id and p.telefone = v_tel
       and exists (select 1 from public.contratos c where c.pessoa_id = p.id)
  ) then
    raise exception 'Este telefone já é de um cliente — a indicação não conta.' using errcode = 'check_violation';
  end if;
  insert into public.indicacoes (organizacao_id, negocio_id, indicador_pessoa_id, nome_indicado, telefone_indicado, observacao)
  values (n.organizacao_id, p_negocio_id, p_indicador_pessoa_id, p_nome, v_tel, 'Registrada pelo administrador (WhatsApp)')
  returning * into i;
  return i;
end;
$$;
revoke all on function public.criar_indicacao_admin(uuid, uuid, text, text) from public, anon;
grant execute on function public.criar_indicacao_admin(uuid, uuid, text, text) to authenticated;

-- passo 1: na conversão o indicante ESCOLHE o presente — sem troca depois
create function public.escolher_presente_indicacao(p_indicacao_id uuid, p_item_id uuid)
returns public.indicacoes
language plpgsql
security definer
set search_path = public
as $$
declare i public.indicacoes%rowtype; it public.estoque_itens%rowtype;
begin
  select * into i from public.indicacoes where id = p_indicacao_id for update;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(i.organizacao_id);
  if i.status <> 'convertida' then
    raise exception 'O presente só é escolhido depois que o indicado instala (indicação convertida).' using errcode = 'check_violation';
  end if;
  if i.presente_item_id is not null then
    raise exception 'Presente já escolhido — a regra da campanha não permite troca.' using errcode = 'check_violation';
  end if;
  select * into it from public.estoque_itens where id = p_item_id;
  if not found or it.organizacao_id <> i.organizacao_id or not it.ativo then
    raise exception 'Item do presente não encontrado.' using errcode = 'no_data_found';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.indicacoes set presente_item_id = p_item_id where id = p_indicacao_id returning * into i;
  return i;
end;
$$;
revoke all on function public.escolher_presente_indicacao(uuid, uuid) from public, anon;
grant execute on function public.escolher_presente_indicacao(uuid, uuid) to authenticated;

-- passo 2: ENTREGA (prazo: 10 dias úteis da conversão) — baixa o estoque e congela o custo
create function public.entregar_presente_indicacao(p_indicacao_id uuid, p_observacao text default null)
returns public.indicacoes
language plpgsql
security definer
set search_path = public
as $$
declare i public.indicacoes%rowtype; it public.estoque_itens%rowtype;
begin
  select * into i from public.indicacoes where id = p_indicacao_id for update;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(i.organizacao_id);
  if i.presente_item_id is null then
    raise exception 'Escolha o presente antes de registrar a entrega.' using errcode = 'check_violation';
  end if;
  if i.presente_entregue_em is not null then
    raise exception 'Presente desta indicação já foi entregue.' using errcode = 'check_violation';
  end if;
  select * into it from public.estoque_itens where id = i.presente_item_id;
  if it.quantidade_atual < 1 then
    raise exception 'Item "%" sem saldo em estoque — compre/ajuste antes de entregar.', it.nome using errcode = 'check_violation';
  end if;
  perform public.saida_estoque(i.presente_item_id, 1, 'brinde', current_date, i.indicador_pessoa_id, null,
    coalesce(p_observacao, 'Presente Indique e Ganhe — ' || i.nome_indicado));
  update public.indicacoes
     set presente_custo = round(coalesce(it.valor_custo, 0), 2),
         presente_entregue_em = current_date
   where id = p_indicacao_id
   returning * into i;
  return i;
end;
$$;
revoke all on function public.entregar_presente_indicacao(uuid, text) from public, anon;
grant execute on function public.entregar_presente_indicacao(uuid, text) to authenticated;

-- =============================================================================
-- Portal: o indicante escolhe o presente — as opções dependem do plano que o
-- INDICADO fechou (faixas da campanha): mensalidade até R$ 60 → presente até
-- R$ 30; até R$ 80 → R$ 30–50; acima → R$ 50–80. Os itens elegíveis são os da
-- categoria de estoque "Brindes" do negócio.
-- =============================================================================
create function public.faixa_presente_indicacao(p_indicacao_id uuid)
returns table (piso numeric, teto numeric)
language sql
stable
security definer
set search_path = public
as $$
  select case when c.valor <= 60 then 0 when c.valor <= 80 then 30 else 50 end,
         case when c.valor <= 60 then 30 when c.valor <= 80 then 50 else 80 end
    from public.indicacoes i
    join public.contratos c on c.pessoa_id = i.indicado_pessoa_id and c.negocio_id = i.negocio_id
   where i.id = p_indicacao_id
   order by c.criado_em desc
   limit 1;
$$;
revoke all on function public.faixa_presente_indicacao(uuid) from public, anon;
grant execute on function public.faixa_presente_indicacao(uuid) to authenticated;

create function public.portal_presentes_indicacao(p_indicacao_id uuid)
returns table (item_id uuid, nome text, descricao text, ja_escolhido boolean)
language sql
stable
security definer
set search_path = public
as $$
  with i as (
    select * from public.indicacoes
     where id = p_indicacao_id and indicador_pessoa_id = public.portal_pessoa() and status = 'convertida'
  ), f as (select * from public.faixa_presente_indicacao(p_indicacao_id))
  select it.id, it.nome, it.descricao, (select presente_item_id from i) = it.id
    from public.estoque_itens it, i, f
   where it.negocio_id = i.negocio_id and it.ativo
     and it.categoria_id in (select ec.id from public.estoque_categorias ec where ec.negocio_id = i.negocio_id and lower(ec.nome) like 'brinde%')
     and coalesce(it.valor_custo, 0) > f.piso and coalesce(it.valor_custo, 0) <= f.teto
   order by it.nome;
$$;
revoke all on function public.portal_presentes_indicacao(uuid) from public, anon;
grant execute on function public.portal_presentes_indicacao(uuid) to authenticated;

create function public.portal_escolher_presente(p_indicacao_id uuid, p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare i public.indicacoes%rowtype;
begin
  select * into i from public.indicacoes where id = p_indicacao_id and indicador_pessoa_id = public.portal_pessoa() for update;
  if not found then raise exception 'Indicação não encontrada.' using errcode = 'no_data_found'; end if;
  if i.status <> 'convertida' then
    raise exception 'O presente é escolhido depois que o seu indicado é instalado.' using errcode = 'check_violation';
  end if;
  if i.presente_item_id is not null then
    raise exception 'Você já escolheu o presente desta indicação — a campanha não permite troca.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.portal_presentes_indicacao(p_indicacao_id) o where o.item_id = p_item_id) then
    raise exception 'Este presente não está disponível para a faixa do plano do seu indicado.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.indicacoes set presente_item_id = p_item_id where id = p_indicacao_id;
end;
$$;
revoke all on function public.portal_escolher_presente(uuid, uuid) from public, anon;
grant execute on function public.portal_escolher_presente(uuid, uuid) to authenticated;

-- lista do portal passa a mostrar a situação do presente e o prazo de entrega
drop function public.portal_indicacoes();
create function public.portal_indicacoes()
returns table (id uuid, negocio text, nome_indicado text, status public.status_indicacao, beneficio_valor numeric, criado_em timestamptz,
               convertida_em timestamptz, presente_item_id uuid, presente text, presente_entregue_em date, aguardando_escolha boolean)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, n.nome, i.nome_indicado, i.status, i.beneficio_valor, i.criado_em,
         i.convertida_em, i.presente_item_id, it.nome, i.presente_entregue_em,
         (i.status = 'convertida' and i.presente_item_id is null)
    from public.indicacoes i
    join public.negocios n on n.id = i.negocio_id
    left join public.estoque_itens it on it.id = i.presente_item_id
   where i.indicador_pessoa_id = public.portal_pessoa()
   order by i.criado_em desc;
$$;
revoke all on function public.portal_indicacoes() from public, anon;
grant execute on function public.portal_indicacoes() to authenticated;
