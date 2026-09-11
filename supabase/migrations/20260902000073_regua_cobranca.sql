-- =============================================================================
-- 0073 · Etapa 48 — Régua de cobrança configurável (padrão enxuto)
-- =============================================================================
-- Antes a régua era fixa em 3 toques (1 aviso X dias antes, no dia, 1 aviso X
-- dias depois). Agora cada negócio escolhe OS PONTOS da régua: listas de dias
-- antes e depois do vencimento (até 5 pontos cada, sem repetição). Padrão
-- enxuto definido pelo proprietário: 2 dias antes · no dia · 3 dias depois.
-- Cada ponto dispara no máximo UMA mensagem por fatura (dedução por
-- lançamento + tipo + dias). As colunas dias_antes/dias_apos viram derivadas
-- (máximo de cada lista) para gerar_bloqueios e checks antigos continuarem
-- valendo sem mudança.
-- =============================================================================

alter table public.notificacoes_config add column regua_antes smallint[] not null default '{2}';
alter table public.notificacoes_config add column regua_apos smallint[] not null default '{3}';
comment on column public.notificacoes_config.regua_antes is 'Dias antes do vencimento em que o cliente recebe aviso (ex.: {5,2}). Vazio = nenhum aviso antes.';
comment on column public.notificacoes_config.regua_apos is 'Dias depois do vencimento em que o cliente recebe aviso de bloqueio (ex.: {3}). O maior valor é o prazo do bloqueio assistido.';

-- config existente migra a régua antiga (1 ponto antes, 1 depois)
update public.notificacoes_config
   set regua_antes = case when dias_antes > 0 then array[dias_antes] else '{}'::smallint[] end,
       regua_apos = array[dias_apos];

-- normaliza e valida a régua; dias_antes/dias_apos derivam do máximo de cada lista
create or replace function public.tg_notificacoes_config_protecao()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and (new.negocio_id <> old.negocio_id or new.organizacao_id <> old.organizacao_id) then
    raise exception 'A configuração não pode mudar de negócio.' using errcode = 'check_violation';
  end if;
  perform public.validar_negocio(new.negocio_id, new.organizacao_id, tg_op = 'INSERT');
  new.numero_whatsapp := nullif(regexp_replace(coalesce(new.numero_whatsapp, ''), '[^0-9+]', '', 'g'), '');
  new.instancia := nullif(lower(btrim(coalesce(new.instancia, ''))), '');
  if new.provedor::text = 'evolution' and new.instancia is null then
    raise exception 'Informe o nome da instância da Evolution API para este negócio.' using errcode = 'check_violation';
  end if;
  -- régua: sem repetição, em ordem, no máximo 5 pontos por lado
  new.regua_antes := coalesce((select array_agg(distinct d order by d) from unnest(coalesce(new.regua_antes, '{}')) d), '{}');
  new.regua_apos := coalesce((select array_agg(distinct d order by d) from unnest(coalesce(new.regua_apos, '{}')) d), '{}');
  if coalesce(array_length(new.regua_antes, 1), 0) > 5 or coalesce(array_length(new.regua_apos, 1), 0) > 5 then
    raise exception 'No máximo 5 pontos de aviso antes e 5 depois.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from unnest(new.regua_antes) d where d < 1 or d > 30) then
    raise exception 'Avisos antes do vencimento: de 1 a 30 dias.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from unnest(new.regua_apos) d where d < 1 or d > 60) then
    raise exception 'Avisos após o vencimento: de 1 a 60 dias.' using errcode = 'check_violation';
  end if;
  new.dias_antes := coalesce((select max(d) from unnest(new.regua_antes) d), 0);
  new.dias_apos := coalesce((select max(d) from unnest(new.regua_apos) d), 3);
  return new;
end;
$$;

-- de qual ponto da régua veio o aviso (para não repetir o mesmo ponto)
alter table public.notificacoes_log add column dias smallint;
-- o "um aviso por fatura+tipo" vira "um aviso por fatura+tipo+ponto"
drop index public.notificacoes_log_unico_idx;
create unique index notificacoes_log_unico_idx on public.notificacoes_log (lancamento_id, tipo, coalesce(dias, '-1'::smallint)) where lancamento_id is not null;

-- geração: um aviso por ponto da régua que cair na data
create or replace function public.gerar_notificacoes(p_organizacao uuid, p_data date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare r record; v_tpl text; v_msg text; n int := 0;
begin
  perform set_config('erp.motor', 'on', true);
  for r in
    select l.id as lancamento_id, l.valor, l.data_vencimento, c.id as contrato_id, c.codigo, c.pessoa_id,
           n2.id as negocio_id, n2.nome as negocio, pl.nome as plano, pe.nome as pessoa, pe.telefone,
           pt.tipo as ponto_tipo, pt.dias as ponto_dias,
           cfg.template_vencimento_proximo, cfg.template_vencimento_dia, cfg.template_bloqueio, cfg.provedor
      from public.lancamentos l
      join public.contratos c on c.id = l.contrato_id
      join public.negocios n2 on n2.id = c.negocio_id
      join public.planos pl on pl.id = c.plano_id
      join public.pessoas pe on pe.id = c.pessoa_id
      join public.notificacoes_config cfg on cfg.negocio_id = n2.id
      cross join lateral (
        select 'proximo_vencimento'::public.tipo_notificacao as tipo, d::smallint as dias, (l.data_vencimento - d)::date as dia from unnest(cfg.regua_antes) d
        union all
        select 'vencimento'::public.tipo_notificacao, 0::smallint, l.data_vencimento
        union all
        select 'bloqueio'::public.tipo_notificacao, d::smallint, (l.data_vencimento + d)::date from unnest(cfg.regua_apos) d
      ) pt
     where l.organizacao_id = p_organizacao and l.status = 'previsto' and l.tipo = 'receita' and l.contrato_id is not null
       and c.status = 'ativo' and n2.ativo and cfg.ativo and pe.receber_avisos
       and pt.dia = p_data
     order by l.data_vencimento, c.codigo
  loop
    -- um aviso por ponto; registros antigos (dias null) valem pelo tipo inteiro
    if exists (select 1 from public.notificacoes_log g where g.lancamento_id = r.lancamento_id and g.tipo = r.ponto_tipo and (g.dias is null or g.dias = r.ponto_dias)) then continue; end if;
    v_tpl := case r.ponto_tipo when 'proximo_vencimento' then r.template_vencimento_proximo when 'vencimento' then r.template_vencimento_dia else r.template_bloqueio end;
    v_msg := public.renderizar_template(v_tpl, jsonb_build_object(
      'nome', r.pessoa, 'negocio', r.negocio, 'plano', r.plano, 'valor', public.moeda_br(r.valor),
      'vencimento', to_char(r.data_vencimento, 'DD/MM/YYYY'), 'contrato', '#' || lpad(r.codigo::text, 3, '0'), 'dias', r.ponto_dias::text));
    insert into public.notificacoes_log (organizacao_id, negocio_id, contrato_id, pessoa_id, lancamento_id, tipo, dias, data_referencia, numero_destino, mensagem, status, provedor, erro)
    values (p_organizacao, r.negocio_id, r.contrato_id, r.pessoa_id, r.lancamento_id, r.ponto_tipo, r.ponto_dias, r.data_vencimento, public.numero_e164(r.telefone), v_msg,
            case when r.telefone is null then 'erro' else 'pendente' end::public.status_notificacao, r.provedor,
            case when r.telefone is null then 'Cliente sem telefone cadastrado.' end);
    n := n + 1;
  end loop;
  return n;
end;
$$;
