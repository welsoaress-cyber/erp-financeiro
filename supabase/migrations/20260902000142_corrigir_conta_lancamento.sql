-- =============================================================================
-- 0142 · Corrigir a conta de um lançamento já efetivado (ajustar baixa)
-- =============================================================================
-- Caso real: proprietário conferindo a Conciliação bancária (0138-0141)
-- percebeu que um recebimento marcado como pago no Mercado Pago na verdade
-- caiu na Caixa — baixa na conta errada. Até aqui, corrigir isso exigia abrir
-- o lançamento em Financeiro → Lançamentos e preencher editar_lancamento
-- inteiro de novo (descrição, valor, categoria...). Essa função só move a
-- conta de um lançamento já efetivado (recalcula movimentos via
-- gerar_movimentos — tira da conta errada, lança na certa), pra usar direto
-- na tela de Conciliação sem reabrir o resto do lançamento.
-- Transferência fica de fora (duas contas em jogo) — continua editando pelo
-- fluxo normal.
-- =============================================================================

create function public.corrigir_conta_lancamento(p_id uuid, p_conta_id uuid)
returns public.lancamentos
language plpgsql
security definer
set search_path = public
as $$
declare l public.lancamentos%rowtype; v_org_conta uuid;
begin
  select * into l from public.lancamentos where id = p_id;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'no_data_found'; end if;
  perform public.exigir_membro(l.organizacao_id);
  if l.status <> 'efetivado' then
    raise exception 'Só dá pra corrigir a conta de um lançamento já efetivado.' using errcode = 'check_violation';
  end if;
  if l.tipo = 'transferencia' then
    raise exception 'Transferência tem duas contas — corrija pela edição normal do lançamento.' using errcode = 'check_violation';
  end if;
  select organizacao_id into v_org_conta from public.contas where id = p_conta_id;
  if v_org_conta is distinct from l.organizacao_id then
    raise exception 'Conta inválida.' using errcode = 'check_violation';
  end if;
  if p_conta_id = l.conta_id then
    return l;
  end if;
  perform set_config('erp.motor', 'on', true);
  update public.lancamentos set conta_id = p_conta_id where id = p_id returning * into l;
  perform public.gerar_movimentos(l.id);
  return l;
end;
$$;
comment on function public.corrigir_conta_lancamento(uuid, uuid) is 'Move um lançamento já efetivado pra outra conta (ajusta a baixa). Recalcula movimentos. Não serve pra transferência.';

revoke all on function public.corrigir_conta_lancamento(uuid, uuid) from public, anon;
grant execute on function public.corrigir_conta_lancamento(uuid, uuid) to authenticated;
