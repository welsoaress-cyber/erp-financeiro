-- =============================================================================
-- 0129 · Importar nota fiscal (XML) — aceitar chave de NFS-e (serviço)
-- =============================================================================
-- A 0128 só previa NFe de produto (chave de acesso com exatos 44 dígitos).
-- NFS-e (nota de serviço, layout da prefeitura) não tem chave de 44 dígitos —
-- o app monta uma chave própria ("NFSE-<cnpj>-<numero>-<códigoVerificação>"),
-- mais longa e alfanumérica. Relaxa o tamanho aceito nos dois lugares que
-- validavam "= 44".
-- =============================================================================

alter table public.notas_fiscais_importadas
  drop constraint notas_fiscais_importadas_chave_check;
alter table public.notas_fiscais_importadas
  add constraint notas_fiscais_importadas_chave_check check (char_length(chave) between 10 and 150);

create or replace function public.registrar_nota_fiscal_importada(
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
  if p_chave is null or char_length(p_chave) not between 10 and 150 then
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
