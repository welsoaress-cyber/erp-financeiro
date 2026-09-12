-- =============================================================================
-- 0075 · Etapa 49C — Vitrine mostra prêmios sem saldo (compra sob demanda)
-- =============================================================================
-- Decisão do proprietário: os presentes são comprados DEPOIS da escolha,
-- dentro do prazo de 10 dias úteis da entrega. Então o saldo em estoque não
-- filtra mais a vitrine (pública nem a escolha do cliente). A trava de saldo
-- continua onde importa: entregar_presente_indicacao exige 1 unidade em
-- estoque para dar a baixa — compra antes de entregar.
-- =============================================================================

create or replace function public.portal_presentes_indicacao(p_indicacao_id uuid)
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
       and exists (select 1 from public.estoque_itens it where it.id = p.item_id and it.ativo)
  )
  select * from premios
  union all
  -- fallback sem prêmios cadastrados: régua antiga por custo do item (piso/teto)
  select null::uuid, it.id, it.nome, null::text, (select presente_item_id from i) = it.id
    from public.estoque_itens it, i, public.faixa_presente_indicacao(p_indicacao_id) fp
   where not exists (select 1 from premios)
     and it.negocio_id = i.negocio_id and it.ativo
     and it.categoria_id in (select ec.id from public.estoque_categorias ec where ec.negocio_id = i.negocio_id and lower(ec.nome) like 'brinde%')
     and coalesce(it.valor_custo, 0) > fp.piso and coalesce(it.valor_custo, 0) <= fp.teto
   order by nome
$$;

create or replace function public.vitrine_publica(p_slug text)
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
         and exists (select 1 from public.estoque_itens it where it.id = p.item_id and it.ativo)), '[]'::jsonb))
    from public.negocios n
    left join public.portal_config pc on pc.negocio_id = n.id
   where n.slug = lower(btrim(coalesce(p_slug, ''))) and n.ativo and coalesce(pc.ativo, false);
$$;
