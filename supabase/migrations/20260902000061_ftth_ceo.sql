-- =============================================================================
-- 0061 · Etapa 33 — Rede FTTH: CEO e encadeamento (quem alimenta quem)
-- =============================================================================
-- Novo tipo de ponto: CEO (caixa de emenda óptica), ponto intermediário entre
-- o POP e as CTOs. O campo pop_id vira o "alimentado por": CEO aponta para POP
-- ou outra CEO; CTO aponta para POP ou CEO. POP é raiz (sem pai) e ganha os
-- dados da OLT (marca, modelo, IP, portas PON) — cadastro, não monitoramento.
-- Splitter primário da CEO usa o campo splitter que já existe.
-- ftth_abaixo_de(ponto) devolve tudo que é alimentado por um ponto (recursivo)
-- + clientes conectados: é o "quem cai junto" do rompimento, usado no mapa.
-- =============================================================================

alter type public.tipo_ponto_rede add value if not exists 'ceo';
alter table public.ctos add column olt_marca text check (olt_marca is null or char_length(olt_marca) <= 40);
alter table public.ctos add column olt_modelo text check (olt_modelo is null or char_length(olt_modelo) <= 60);
alter table public.ctos add column olt_ip text check (olt_ip is null or olt_ip ~ '^[0-9]{1,3}(\.[0-9]{1,3}){3}$');
alter table public.ctos add column olt_portas_pon smallint check (olt_portas_pon is null or olt_portas_pon between 1 and 128);
comment on column public.ctos.pop_id is 'Alimentado por: POP ou CEO de onde vem a fibra deste ponto (fio no mapa).';

-- encadeamento: CEO/CTO apontam para POP ou CEO do mesmo negócio, sem ciclo
create or replace function public.tg_ctos_pop()
returns trigger
language plpgsql
set search_path = public
as $$
declare p public.ctos%rowtype; v_atual uuid; v_passos int := 0;
begin
  if new.tipo::text = 'pop' then
    new.pop_id := null; -- POP é a raiz
  elsif new.pop_id is not null then
    if new.pop_id = new.id then raise exception 'O ponto não pode apontar para ele mesmo.' using errcode = 'check_violation'; end if;
    select * into p from public.ctos where id = new.pop_id;
    if not found or p.tipo::text not in ('pop', 'ceo') or p.negocio_id <> new.negocio_id then
      raise exception 'Alimentado por deve ser um POP ou uma CEO do mesmo negócio.' using errcode = 'check_violation';
    end if;
    if new.tipo::text = 'ceo' then
      -- sobe a cadeia para impedir ciclo (limite 10 níveis)
      v_atual := new.pop_id;
      while v_atual is not null and v_passos < 10 loop
        if v_atual = new.id then raise exception 'Encadeamento em círculo: a CEO não pode ser alimentada por quem ela alimenta.' using errcode = 'check_violation'; end if;
        select pop_id into v_atual from public.ctos where id = v_atual;
        v_passos := v_passos + 1;
      end loop;
    end if;
  end if;
  return new;
end;
$$;

-- tudo que está abaixo de um ponto (recursivo) — para o impacto do rompimento
create function public.ftth_abaixo_de(p_ponto_id uuid)
returns table (id uuid, codigo text, tipo public.tipo_ponto_rede, nivel int, clientes bigint)
language sql
stable
security definer
set search_path = public
as $$
  with recursive abaixo as (
    select c.id, c.codigo, c.tipo, 1 as nivel
      from public.ctos c
     where c.pop_id = p_ponto_id
       and c.organizacao_id in (select public.minhas_organizacoes())
    union all
    select c.id, c.codigo, c.tipo, a.nivel + 1
      from public.ctos c join abaixo a on c.pop_id = a.id
     where a.nivel < 10
  )
  select a.id, a.codigo, a.tipo, a.nivel,
         (select count(*) from public.cto_portas p where p.cto_id = a.id and p.status = 'ocupada')
    from abaixo a
   order by a.nivel, a.codigo;
$$;
revoke all on function public.ftth_abaixo_de(uuid) from public, anon;
grant execute on function public.ftth_abaixo_de(uuid) to authenticated;
