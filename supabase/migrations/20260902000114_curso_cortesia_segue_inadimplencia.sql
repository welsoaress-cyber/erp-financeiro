-- =============================================================================
-- 0114 · Curso cortesia acompanha inadimplência dos outros contratos
-- =============================================================================
-- Até aqui, bloqueio/desbloqueio (gerar_bloqueios, 0059/0072/0097) olha cada
-- contrato isoladamente: só considera as próprias cobranças vencidas daquele
-- contrato. Um contrato cortesia (valor R$ 0, como o do curso Leveduca,
-- etapa 60) nunca tem cobrança vencida, então nunca é varrido — fica Ativo
-- pra sempre, mesmo que a mesma pessoa esteja suspensa em outro negócio por
-- falta de pagamento (internet, por exemplo). E esse status é o que a
-- Leveduca enxerga pela API (api_consultar_cliente, 0099): Ativo = libera o
-- curso.
--
-- Decisão do proprietário: o curso é benefício condicionado a estar em dia
-- nos outros negócios. Esta migration sincroniza, por pessoa, o status de
-- CONTRATOS CORTESIA DE CURSO (cortesia=true, tipo_financeiro=receita, plano
-- com "curso" no nome) com a existência de algum OUTRO contrato de receita
-- pago (cortesia=false) suspenso na mesma organização, em qualquer negócio:
--   tem pago suspenso em algum negócio → curso suspenso também
--   nenhum pago suspenso em lugar nenhum → curso ativo de volta
-- Outros tipos de cortesia (indicação, vitrine de pontos etc.) não entram
-- nessa regra — só o plano de curso, de propósito.
-- =============================================================================

-- Lógica compartilhada (sem permissão própria — só as duas funções abaixo chamam).
create function public.sincronizar_cortesia_curso_logica(p_organizacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_susp int := 0; v_lib int := 0; r record;
begin
  for r in
    select c.id
      from public.contratos c
      join public.planos pl on pl.id = c.plano_id
     where c.organizacao_id = p_organizacao_id
       and c.cortesia and c.tipo_financeiro = 'receita' and c.status = 'ativo'
       and lower(pl.nome) like '%curso%'
       and exists (
         select 1 from public.contratos c2
          where c2.organizacao_id = c.organizacao_id and c2.pessoa_id = c.pessoa_id
            and c2.id <> c.id and c2.tipo_financeiro = 'receita' and c2.status = 'suspenso' and not c2.cortesia
       )
  loop
    update public.contratos set status = 'suspenso' where id = r.id;
    v_susp := v_susp + 1;
  end loop;

  for r in
    select c.id
      from public.contratos c
      join public.planos pl on pl.id = c.plano_id
     where c.organizacao_id = p_organizacao_id
       and c.cortesia and c.tipo_financeiro = 'receita' and c.status = 'suspenso'
       and lower(pl.nome) like '%curso%'
       and not exists (
         select 1 from public.contratos c2
          where c2.organizacao_id = c.organizacao_id and c2.pessoa_id = c.pessoa_id
            and c2.id <> c.id and c2.tipo_financeiro = 'receita' and c2.status = 'suspenso' and not c2.cortesia
       )
  loop
    update public.contratos set status = 'ativo' where id = r.id;
    v_lib := v_lib + 1;
  end loop;

  return jsonb_build_object('suspensos', v_susp, 'liberados', v_lib);
end;
$$;
revoke all on function public.sincronizar_cortesia_curso_logica(uuid) from public, anon, authenticated;

-- Chamável pelo app (botão manual) — exige ser membro da organização.
create function public.sincronizar_cortesia_curso(p_organizacao_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.exigir_membro(p_organizacao_id);
  return public.sincronizar_cortesia_curso_logica(p_organizacao_id);
end;
$$;
revoke all on function public.sincronizar_cortesia_curso(uuid) from public, anon;
grant execute on function public.sincronizar_cortesia_curso(uuid) to authenticated;

-- Robô diário: todas as organizações, sem sessão de usuário.
create function public.sincronizar_cortesia_curso_automatico()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_org record; v_susp int := 0; v_lib int := 0; v_r jsonb;
begin
  for v_org in select id from public.organizacoes loop
    v_r := public.sincronizar_cortesia_curso_logica(v_org.id);
    v_susp := v_susp + coalesce((v_r->>'suspensos')::int, 0);
    v_lib := v_lib + coalesce((v_r->>'liberados')::int, 0);
  end loop;
  return jsonb_build_object('suspensos', v_susp, 'liberados', v_lib);
end;
$$;
revoke all on function public.sincronizar_cortesia_curso_automatico() from public, anon, authenticated;
grant execute on function public.sincronizar_cortesia_curso_automatico() to service_role;

-- Encadeia no robô diário já existente (0097), depois do bloqueio/desbloqueio normal.
create or replace function public.executar_bloqueios_automaticos()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_neg record; v_item record; v_total int := 0; v_curso jsonb;
begin
  for v_neg in select negocio_id from public.notificacoes_config where bloqueio_automatico loop
    perform public.gerar_bloqueios_interno(v_neg.negocio_id);
    for v_item in select id from public.bloqueios where negocio_id = v_neg.negocio_id and status = 'pendente' loop
      perform public.executar_bloqueio_interno(v_item.id);
      v_total := v_total + 1;
    end loop;
  end loop;
  v_curso := public.sincronizar_cortesia_curso_automatico();
  return jsonb_build_object('executados', v_total, 'curso_suspensos', v_curso->'suspensos', 'curso_liberados', v_curso->'liberados');
end;
$$;
revoke all on function public.executar_bloqueios_automaticos() from public, anon, authenticated;
grant execute on function public.executar_bloqueios_automaticos() to service_role;
