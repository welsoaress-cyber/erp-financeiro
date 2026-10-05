-- =============================================================================
-- 0128 · Importar nota fiscal (XML) — controle de duplicidade
-- =============================================================================
-- Única peça de SQL nova do módulo de importação de NFe: todo o resto
-- (requisição, aprovação, recebimento, item de estoque, fornecedor, contrato,
-- baixa de lançamento) reaproveita funções do motor que já existem — a 0128
-- só impede importar a MESMA nota (chave de acesso) duas vezes, em qualquer
-- um dos dois caminhos (compra avulsa ou baixa de contrato recorrente).
-- =============================================================================

create table public.notas_fiscais_importadas (
  id             uuid primary key default gen_random_uuid(),
  organizacao_id uuid not null references public.organizacoes (id) on delete restrict,
  negocio_id     uuid not null references public.negocios (id) on delete restrict,
  fornecedor_id  uuid not null references public.pessoas (id) on delete restrict,
  chave          text not null unique check (char_length(chave) = 44),
  numero         text,
  valor          numeric(14,2) not null check (valor >= 0),
  emitida_em     date,
  destino        text not null check (destino in ('compra', 'contrato')),
  compra_id      uuid references public.compras (id) on delete restrict,
  contrato_id    uuid references public.contratos (id) on delete restrict,
  lancamento_id  uuid references public.lancamentos (id) on delete restrict,
  criado_em      timestamptz not null default now(),
  usuario_id     uuid,
  check ((destino = 'compra') = (compra_id is not null)),
  check ((destino = 'contrato') = (contrato_id is not null))
);
create index notas_fiscais_importadas_negocio_idx on public.notas_fiscais_importadas (negocio_id, criado_em desc);

alter table public.notas_fiscais_importadas enable row level security;
create policy notas_fiscais_importadas_select on public.notas_fiscais_importadas for select using (organizacao_id in (select public.minhas_organizacoes()));
revoke all on public.notas_fiscais_importadas from public, anon, authenticated;
grant select on public.notas_fiscais_importadas to authenticated;

-- Chamada só depois que o lado "de verdade" (compra ou baixa de lançamento) já
-- foi criado — trava a chave por último, pra nunca travar uma chave de uma
-- importação que falhou no meio do caminho.
create function public.registrar_nota_fiscal_importada(
  p_negocio_id uuid, p_fornecedor_id uuid, p_chave text, p_numero text, p_valor numeric, p_emitida_em date,
  p_destino text, p_compra_id uuid default null, p_contrato_id uuid default null, p_lancamento_id uuid default null
)
returns public.notas_fiscais_importadas
language plpgsql
security definer
set search_path = public
as $$
declare n public.negocios%rowtype; r public.notas_fiscais_importadas%rowtype;
begin
  select * into n from public.negocios where id = p_negocio_id;
  if not found then raise exception 'Negócio não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(n.organizacao_id);
  if p_chave is null or char_length(p_chave) <> 44 then
    raise exception 'Chave de acesso da nota inválida.' using errcode = 'check_violation';
  end if;
  if p_destino not in ('compra', 'contrato') then
    raise exception 'Destino inválido.' using errcode = 'check_violation';
  end if;
  begin
    insert into public.notas_fiscais_importadas
      (organizacao_id, negocio_id, fornecedor_id, chave, numero, valor, emitida_em, destino, compra_id, contrato_id, lancamento_id, usuario_id)
    values
      (n.organizacao_id, p_negocio_id, p_fornecedor_id, p_chave, p_numero, p_valor, p_emitida_em, p_destino, p_compra_id, p_contrato_id, p_lancamento_id, auth.uid())
    returning * into r;
  exception when unique_violation then
    raise exception 'Essa nota (chave %) já foi importada antes.', p_chave using errcode = 'unique_violation';
  end;
  return r;
end;
$$;
revoke all on function public.registrar_nota_fiscal_importada(uuid, uuid, text, text, numeric, date, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.registrar_nota_fiscal_importada(uuid, uuid, text, text, numeric, date, text, uuid, uuid, uuid) to authenticated;
