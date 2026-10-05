-- =============================================================================
-- 0126 · Controle de Boletos (v1) + desconto em lançamento
-- =============================================================================
-- Dor do proprietário: Servidor (IPTV/streaming) é 100% Pix; Servnet (internet)
-- mistura Pix e boleto, e hoje não há como saber quem ainda precisa receber o
-- boleto por WhatsApp perto do vencimento. Resolvido com:
--   1) contratos.forma_pagamento (pix | boleto | outro) — por contrato, não por
--      pessoa (a mesma pessoa pode ter um contrato pix e outro boleto).
--   2) boletos_enviados — log imutável (cada envio é uma linha nova: histórico
--      e reenvio saem de graça, sem precisar de coluna de "status").
--   3) lancamentos.codigo_barras — opcional, editável antes de mandar o boleto.
--   4) vw_rel_boletos_pendentes — boleto + ativo + previsto + nunca registrado
--      como enviado (pago e suspenso somem sozinhos, sem lógica extra).
--
-- Desconto: mesmo padrão já usado no resgate de pontos (0102) — reduz
-- lancamentos.valor direto, pela função do motor, então saldo/relatórios/
-- dashboard continuam corretos sem saber que desconto existe. valor_desconto e
-- motivo_desconto ficam no lançamento como trilha de auditoria (nunca em
-- boletos_enviados, que já guarda a mensagem literal enviada — duplicar o
-- número lá só criaria chance de ele ficar desatualizado).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Forma de pagamento do contrato
-- -----------------------------------------------------------------------------
create type public.forma_pagamento_contrato as enum ('pix', 'boleto', 'outro');
alter table public.contratos add column forma_pagamento public.forma_pagamento_contrato not null default 'pix';

-- -----------------------------------------------------------------------------
-- 2) Desconto e código de barras no lançamento
-- -----------------------------------------------------------------------------
alter table public.lancamentos add column valor_desconto numeric(14,2) not null default 0 check (valor_desconto >= 0);
alter table public.lancamentos add column motivo_desconto text check (motivo_desconto is null or char_length(motivo_desconto) <= 200);
alter table public.lancamentos add column codigo_barras text check (codigo_barras is null or char_length(codigo_barras) <= 64);
alter table public.lancamentos add constraint lancamentos_desconto_motivo_check check ((valor_desconto > 0) = (motivo_desconto is not null));

comment on column public.lancamentos.valor_desconto is 'Desconto já aplicado (valor já saiu de "valor" — motor, via conceder_desconto_lancamento). Pra ver o valor cheio: valor + valor_desconto.';

-- Concede (ou remove, com p_valor_desconto = 0) desconto num lançamento ainda previsto.
-- p_valor_desconto é o desconto TOTAL desejado (substitui o anterior, não soma).
create function public.conceder_desconto_lancamento(p_id uuid, p_valor_desconto numeric, p_motivo text default null)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; v_valor_cheio numeric; v_motivo text;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'previsto' then
    raise exception 'Só dá pra aplicar desconto num lançamento previsto.' using errcode = 'check_violation';
  end if;
  if p_valor_desconto is null or p_valor_desconto < 0 then
    raise exception 'Desconto não pode ser negativo.' using errcode = 'check_violation';
  end if;
  v_valor_cheio := l.valor + l.valor_desconto;
  if p_valor_desconto >= v_valor_cheio then
    raise exception 'Desconto não pode zerar ou ultrapassar o valor do lançamento — pra isso, cancele.' using errcode = 'check_violation';
  end if;
  v_motivo := nullif(btrim(coalesce(p_motivo, '')), '');
  if p_valor_desconto > 0 and v_motivo is null then
    raise exception 'Informe o motivo do desconto.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos
     set valor = v_valor_cheio - p_valor_desconto,
         valor_desconto = p_valor_desconto,
         motivo_desconto = case when p_valor_desconto > 0 then v_motivo end
   where id = p_id
  returning * into l;
  return l;
end;
$$;
revoke all on function public.conceder_desconto_lancamento(uuid, numeric, text) from public, anon;
grant execute on function public.conceder_desconto_lancamento(uuid, numeric, text) to authenticated;

create function public.definir_codigo_barras_lancamento(p_id uuid, p_codigo text)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'previsto' then
    raise exception 'Só dá pra editar o código de barras de um lançamento previsto.' using errcode = 'check_violation';
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set codigo_barras = nullif(btrim(coalesce(p_codigo, '')), '') where id = p_id returning * into l;
  return l;
end;
$$;
revoke all on function public.definir_codigo_barras_lancamento(uuid, text) from public, anon;
grant execute on function public.definir_codigo_barras_lancamento(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3) Log de envio de boleto (imutável — cada linha é um envio; reenvio = nova linha)
-- -----------------------------------------------------------------------------
create table public.boletos_enviados (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  contrato_id    uuid not null references public.contratos (id) on delete restrict,
  lancamento_id  uuid not null references public.lancamentos (id) on delete restrict,
  pessoa_id      uuid not null references public.pessoas (id) on delete restrict,
  enviado_em     timestamptz not null default now(),
  canal          text not null default 'whatsapp' check (canal in ('whatsapp')),
  mensagem       text not null check (char_length(mensagem) between 1 and 1000),
  usuario_id     uuid
);
create index boletos_enviados_lancamento_idx on public.boletos_enviados (lancamento_id);
create index boletos_enviados_negocio_idx on public.boletos_enviados (negocio_id, enviado_em desc);
create trigger boletos_enviados_auditoria after insert or update or delete on public.boletos_enviados for each row execute function public.tg_auditoria();

alter table public.boletos_enviados enable row level security;
create policy boletos_enviados_select on public.boletos_enviados for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.boletos_enviados from public, anon, authenticated;
grant select on public.boletos_enviados to authenticated;

create function public.registrar_boleto_enviado(p_lancamento_id uuid, p_mensagem text)
returns public.boletos_enviados
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; c public.contratos%rowtype; r public.boletos_enviados%rowtype; v_mensagem text;
begin
  select * into l from public.lancamentos where id = p_lancamento_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  select * into c from public.contratos where id = l.contrato_id;
  if not found then raise exception 'Lançamento sem contrato — não é um boleto.' using errcode = 'check_violation'; end if;
  perform public.exigir_membro(l.organizacao_id);
  v_mensagem := nullif(btrim(coalesce(p_mensagem, '')), '');
  if v_mensagem is null then raise exception 'Informe a mensagem enviada.' using errcode = 'check_violation'; end if;
  insert into public.boletos_enviados (organizacao_id, negocio_id, contrato_id, lancamento_id, pessoa_id, mensagem, usuario_id)
  values (l.organizacao_id, c.negocio_id, c.id, l.id, c.pessoa_id, v_mensagem, auth.uid())
  returning * into r;
  return r;
end;
$$;
revoke all on function public.registrar_boleto_enviado(uuid, text) from public, anon;
grant execute on function public.registrar_boleto_enviado(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4) Relatório: boletos pendentes de envio
-- -----------------------------------------------------------------------------
create view public.vw_rel_boletos_pendentes
with (security_invoker = true) as
select l.id, l.organizacao_id, c.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       c.id as contrato_id, c.codigo as contrato_codigo, c.dia_vencimento,
       c.pessoa_id, p.nome as pessoa, p.telefone,
       l.descricao, l.valor, l.valor_desconto, l.motivo_desconto, l.codigo_barras,
       l.data_vencimento
  from public.lancamentos l
  join public.contratos c on c.id = l.contrato_id
  left join public.negocios n on n.id = c.negocio_id
  left join public.pessoas p on p.id = c.pessoa_id
 where l.tipo = 'receita' and l.status = 'previsto'
   and c.forma_pagamento = 'boleto' and c.tipo_financeiro = 'receita' and c.status = 'ativo'
   and not exists (select 1 from public.boletos_enviados be where be.lancamento_id = l.id);
grant select on public.vw_rel_boletos_pendentes to authenticated;

-- vw_rel_lancamentos (0079/0081) ganha o desconto — coluna nova sempre no fim
-- (CREATE OR REPLACE VIEW não deixa inserir/reordenar no meio da lista).
create or replace view public.vw_rel_lancamentos
with (security_invoker = true) as
select l.id, l.organizacao_id, l.tipo, l.status, l.descricao, l.valor,
       l.data_competencia, l.data_vencimento, l.data_efetivacao, l.origem,
       l.conta_id, ct.nome as conta,
       l.categoria_id, c.nome as categoria, coalesce(c.natureza, 'operacional'::public.natureza_categoria) as natureza,
       l.negocio_id, coalesce(n.nome, 'Pessoal') as negocio,
       l.pessoa_id, p.nome as pessoa,
       l.contrato_id, k.codigo as contrato_codigo,
       l.centro_custo_id, coalesce(cc.nome, 'Geral') as centro_custo,
       l.valor_desconto, l.motivo_desconto
  from public.lancamentos l
  left join public.contas ct on ct.id = l.conta_id
  left join public.categorias c on c.id = l.categoria_id
  left join public.negocios n on n.id = l.negocio_id
  left join public.pessoas p on p.id = l.pessoa_id
  left join public.contratos k on k.id = l.contrato_id
  left join public.centros_custo cc on cc.id = l.centro_custo_id
 where l.tipo in ('receita', 'despesa');
