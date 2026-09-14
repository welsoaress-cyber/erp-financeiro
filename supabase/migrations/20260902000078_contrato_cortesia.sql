-- =============================================================================
-- 0078 · CONTRATO CORTESIA (Etapa 52)
-- =============================================================================
-- Pedido do proprietário: alguns clientes (ele próprio, parceiros) não pagam.
-- Antes, contrato com valor 0 caía toda execução do faturamento como
-- pendência "Contrato com valor zero". Agora existe o flag explícito
-- contratos.cortesia: valor obrigatoriamente 0, o faturamento pula sem
-- pendência (não gera lançamento — o motor não aceita valor 0, e cortesia não é
-- receita), a importação por CSV aceita a coluna/caixa "cortesia".
-- Contratos que já estavam com valor 0 viram cortesia (único significado possível).
-- =============================================================================
alter table public.contratos add column cortesia boolean not null default false;
alter table public.contratos add constraint contratos_cortesia_valor_chk check (not cortesia or valor = 0);
comment on column public.contratos.cortesia is 'Sem cobrança: valor 0, faturamento pula sem pendência.';
update public.contratos set cortesia = true where valor = 0;

create or replace function public.faturar_contrato(p_contrato uuid, p_ate date, out gerados integer, out pendencia text)
language plpgsql
set search_path = public
as $$
declare
  c public.contratos%rowtype;
  n public.negocios%rowtype;
  pl public.planos%rowtype;
  v_conta uuid; v_cat uuid; v_comp date; v_venc date; l public.lancamentos%rowtype;
  v_desc numeric(14,2); v_valor numeric(14,2); v_motivos text;
begin
  gerados := 0; pendencia := null;
  select * into c from public.contratos where id = p_contrato;
  if not found or c.status <> 'ativo' or not c.faturamento_automatico then return; end if;
  if not exists (select 1 from public.competencias_pendentes(c.id, p_ate)) then return; end if;
  select * into n from public.negocios where id = c.negocio_id;
  select * into pl from public.planos where id = c.plano_id;
  v_conta := coalesce(c.conta_id, n.conta_padrao_id);
  v_cat := case when c.tipo_financeiro = 'despesa' then n.categoria_despesa_id else n.categoria_receita_id end;
  if v_conta is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Sem conta de pagamento (no contrato ou padrão do negócio).' else 'Sem conta de recebimento (no contrato ou padrão do negócio).' end; return; end if;
  if v_cat is null then pendencia := case when c.tipo_financeiro = 'despesa' then 'Negócio sem categoria de despesa padrão.' else 'Negócio sem categoria de receita padrão.' end; return; end if;
  if not exists (select 1 from public.contas where id = v_conta and ativo) then pendencia := case when c.tipo_financeiro = 'despesa' then 'Conta de pagamento inativa.' else 'Conta de recebimento inativa.' end; return; end if;
  if not exists (select 1 from public.categorias where id = v_cat and ativo) then pendencia := 'Categoria padrão inativa.'; return; end if;
  if c.cortesia then return; end if;  -- cortesia: sem cobrança, sem pendência
  if c.valor <= 0 then pendencia := 'Contrato com valor zero.'; return; end if;

  perform set_config('erp.motor', 'on', true);
  for v_comp in select * from public.competencias_pendentes(c.id, p_ate) order by 1 loop
    v_venc := public.data_vencimento_no_mes(v_comp, c.dia_vencimento);
    if c.tipo_financeiro = 'receita' then
      perform public.fidelidade_registrar_premio(c.id, v_comp);
      select coalesce(sum(d.valor), 0), string_agg(d.motivo, '; ' order by d.criado_em) into v_desc, v_motivos
        from public.descontos_contrato d where d.contrato_id = c.id and d.lancamento_id is null;
    else
      v_desc := 0; v_motivos := null;
    end if;
    v_valor := case when v_desc >= c.valor then c.valor else c.valor - v_desc end;
    insert into public.lancamentos (
      organizacao_id, tipo, descricao, valor, data_competencia, data_vencimento, data_efetivacao, status,
      conta_id, categoria_id, origem, negocio_id, pessoa_id, contrato_id, observacao, cancelado_em, motivo_cancelamento
    ) values (
      c.organizacao_id, c.tipo_financeiro::text::public.tipo_lancamento,
      left(pl.nome || ' · ' || to_char(v_comp, 'MM/YYYY') || ' · contrato #' || lpad(c.codigo::text, 3, '0'), 140),
      v_valor, v_venc, v_venc, null, (case when v_desc >= c.valor then 'cancelado' else 'previsto' end)::public.status_lancamento,
      v_conta, v_cat, 'faturamento', c.negocio_id, c.pessoa_id, c.id,
      case when v_desc >= c.valor then left('Mês grátis (' || v_motivos || ').', 500)
           when v_desc > 0 then left('Desconto aplicado: ' || public.moeda_br(v_desc) || ' (' || v_motivos || ').', 500) end,
      case when v_desc >= c.valor then now() end,
      case when v_desc >= c.valor then left('Mês grátis: ' || v_motivos, 200) end
    ) returning * into l;
    if v_desc > 0 then
      update public.descontos_contrato set lancamento_id = l.id where contrato_id = c.id and lancamento_id is null;
    end if;
    insert into public.faturamentos (organizacao_id, contrato_id, competencia, lancamento_id) values (c.organizacao_id, c.id, v_comp, l.id);
    gerados := gerados + 1;
  end loop;
end;
$$;

create or replace function public.importar_clientes(
  p_negocio_id    uuid,
  p_linhas        jsonb,
  p_simular       boolean default true,
  p_faturar_desde date default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_neg        public.negocios%rowtype;
  v_org        uuid;
  v_rel        jsonb;
  v_itens      jsonb := '[]'::jsonb;
  v_linha      jsonb;
  v_n          int := 0;
  v_ok         int := 0;
  v_rej        int := 0;
  v_ign        int := 0;
  v_pes_novas  int := 0;
  v_pes_exist  int := 0;
  v_pl_novos   int := 0;
  v_ct_ativos  int := 0;
  v_ct_enc     int := 0;
  -- por linha
  v_nome text; v_doc text; v_tel text; v_email text; v_plano_nome text;
  v_valor numeric(14,2); v_dia int; v_ini date; v_fim date; v_per public.periodicidade; v_per_txt text;
  v_cortesia boolean;
  v_pessoa_id uuid; v_plano_id uuid; v_contrato_id uuid;
  v_pessoa_status text; v_plano_status text; v_contrato_status text;
  v_motivo text;
begin
  if p_negocio_id is null then
    raise exception 'Informe o negócio de destino.' using errcode = 'check_violation';
  end if;
  select * into v_neg from public.negocios where id = p_negocio_id;
  if not found then
    raise exception 'Negócio inválido.' using errcode = 'check_violation';
  end if;
  if not v_neg.ativo then
    raise exception 'O negócio está inativo.' using errcode = 'check_violation';
  end if;
  v_org := v_neg.organizacao_id;  -- RLS em negocios já garante que o usuário é membro da organização
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then
    raise exception 'Linhas inválidas.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_linhas) > 2000 then
    raise exception 'Importe no máximo 2000 linhas por vez.' using errcode = 'check_violation';
  end if;

  begin  -- bloco desfeito inteiro quando p_simular
    for v_linha in select * from jsonb_array_elements(p_linhas) loop
      v_n := v_n + 1;
      v_motivo := null; v_pessoa_status := null; v_plano_status := null; v_contrato_status := null;
      begin  -- savepoint por linha: erro em uma linha não derruba as outras
        v_nome  := nullif(regexp_replace(btrim(coalesce(v_linha->>'nome', '')), '\s+', ' ', 'g'), '');
        v_doc   := nullif(regexp_replace(coalesce(v_linha->>'documento', ''), '[^0-9]', '', 'g'), '');
        v_tel   := nullif(regexp_replace(coalesce(v_linha->>'telefone', ''), '[^0-9]', '', 'g'), '');
        v_email := nullif(lower(btrim(coalesce(v_linha->>'email', ''))), '');
        v_plano_nome := coalesce(public.nome_plano_importado(v_linha->>'plano'), left(v_neg.nome, 80));
        v_valor := nullif(replace(regexp_replace(coalesce(v_linha->>'valor', ''), '[^0-9,.\-]', '', 'g'), ',', '.'), '')::numeric;
        v_dia   := coalesce(nullif(regexp_replace(coalesce(v_linha->>'dia_vencimento', ''), '[^0-9]', '', 'g'), '')::int, 10);
        v_per_txt := lower(btrim(coalesce(v_linha->>'periodicidade', 'mensal')));
        if v_per_txt not in ('mensal', 'bimestral', 'trimestral', 'semestral', 'anual') then
          raise exception 'Periodicidade inválida (mensal, bimestral, trimestral, semestral ou anual).';
        end if;
        v_per := v_per_txt::public.periodicidade;
        v_ini   := coalesce(public.data_importada(v_linha->>'data_inicio'), current_date);
        v_fim   := public.data_importada(v_linha->>'data_fim');
        v_cortesia := coalesce((v_linha->>'cortesia')::boolean, false);
        if v_cortesia then v_valor := 0; end if;

        -- validações (só sobre o que veio preenchido; mensagens curtas para o relatório)
        if v_nome is null or char_length(v_nome) < 2 then
          raise exception 'Nome obrigatório (mínimo 2 caracteres).';
        end if;
        if char_length(v_nome) > 120 then v_nome := left(v_nome, 120); end if;
        if v_doc is not null and not public.documento_valido(v_doc) then raise exception 'CPF/CNPJ inválido.'; end if;
        if v_tel is not null and v_tel !~ '^[0-9]{10,13}$' then raise exception 'Telefone inválido (use DDD + número).'; end if;
        if v_email is not null and (v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 120) then
          raise exception 'E-mail inválido.';
        end if;
        if char_length(v_plano_nome) > 80 then raise exception 'Nome do plano muito longo (máximo 80).'; end if;
        if v_valor is not null and v_valor < 0 then raise exception 'Valor não pode ser negativo.'; end if;
        if v_dia < 1 or v_dia > 31 then raise exception 'Dia de vencimento deve estar entre 1 e 31.'; end if;
        if v_fim is not null and v_fim < v_ini then raise exception 'Data de cancelamento anterior ao início.'; end if;
        -- linha repetida dentro do próprio arquivo (mesma identidade — documento ou nome —, plano e início)
        if exists (
          select 1 from jsonb_array_elements(p_linhas) with ordinality as a(l, i)
          where i < v_n
            and coalesce(nullif(regexp_replace(coalesce(a.l->>'documento', ''), '[^0-9]', '', 'g'), ''),
                         lower(regexp_replace(btrim(coalesce(a.l->>'nome', '')), '\s+', ' ', 'g')))
              = coalesce(v_doc, lower(v_nome))
            and coalesce(public.nome_plano_importado(a.l->>'plano'), left(v_neg.nome, 80)) = v_plano_nome
            and coalesce(public.data_importada(a.l->>'data_inicio'), current_date) = v_ini
        ) then
          raise exception 'Linha repetida no arquivo (mesma pessoa, plano e início).';
        end if;

        -- plano: reaproveita pelo nome (case-insensitive) ou cria no negócio
        select id into v_plano_id from public.planos
         where negocio_id = p_negocio_id and lower(btrim(nome)) = lower(v_plano_nome);
        if found then
          v_plano_status := 'existente';
          if not (select ativo from public.planos where id = v_plano_id) then
            raise exception 'Plano "%" está inativo no negócio.', v_plano_nome;
          end if;
        else
          insert into public.planos (organizacao_id, negocio_id, nome, valor_tabela, periodicidade)
          values (v_org, p_negocio_id, v_plano_nome, case when v_cortesia then 0 else coalesce(v_valor, 0) end, v_per)
          returning id into v_plano_id;
          v_plano_status := 'novo'; v_pl_novos := v_pl_novos + 1;
        end if;
        if v_valor is null then
          select valor_tabela into v_valor from public.planos where id = v_plano_id;
        end if;

        -- pessoa: reaproveita pelo documento (quando houver) ou pelo nome; nunca duplica
        if v_doc is not null then
          select id into v_pessoa_id from public.pessoas where organizacao_id = v_org and documento = v_doc;
        else
          select id into v_pessoa_id from public.pessoas
           where organizacao_id = v_org and documento is null and lower(btrim(nome)) = lower(v_nome)
           limit 1;
        end if;
        if v_pessoa_id is not null then
          v_pessoa_status := 'existente'; v_pes_exist := v_pes_exist + 1;
          if not (select ativo from public.pessoas where id = v_pessoa_id) then
            raise exception 'Pessoa com esta identificação está inativa.';
          end if;
        else
          insert into public.pessoas (organizacao_id, tipo, nome, documento, telefone, email)
          values (v_org, (case when v_doc is not null and char_length(v_doc) = 14 then 'juridica' else 'fisica' end)::public.tipo_pessoa, v_nome, v_doc, v_tel, v_email)
          returning id into v_pessoa_id;
          v_pessoa_status := 'nova'; v_pes_novas := v_pes_novas + 1;
        end if;

        -- contrato: não duplica (mesma pessoa, negócio, plano e início)
        if exists (
          select 1 from public.contratos
           where negocio_id = p_negocio_id and pessoa_id = v_pessoa_id and plano_id = v_plano_id and data_inicio = v_ini
        ) then
          v_contrato_status := 'existente'; v_ign := v_ign + 1;
          v_itens := v_itens || jsonb_build_object('linha', coalesce((v_linha->>'linha')::int, v_n), 'status', 'ignorada',
            'motivo', 'Contrato já existe (mesma pessoa, plano e início).', 'pessoa', v_pessoa_status, 'plano', v_plano_status, 'contrato', v_contrato_status);
          continue;
        end if;
        insert into public.contratos (organizacao_id, negocio_id, pessoa_id, plano_id, valor, periodicidade,
                                      data_inicio, dia_vencimento, faturamento_automatico, faturar_desde, cortesia)
        values (v_org, p_negocio_id, v_pessoa_id, v_plano_id, v_valor, v_per,
                v_ini, v_dia, v_fim is null, case when v_fim is null then greatest(coalesce(p_faturar_desde, v_ini), v_ini) else v_ini end, v_cortesia)
        returning id into v_contrato_id;
        if v_fim is not null then
          update public.contratos set status = 'encerrado', data_fim = v_fim,
            observacao = 'Importado do sistema anterior; cancelado em ' || to_char(v_fim, 'DD/MM/YYYY') || '.'
           where id = v_contrato_id;
          v_contrato_status := 'encerrado'; v_ct_enc := v_ct_enc + 1;
        else
          update public.contratos set observacao = 'Importado do sistema anterior.' where id = v_contrato_id;
          v_contrato_status := 'ativo'; v_ct_ativos := v_ct_ativos + 1;
        end if;
        v_ok := v_ok + 1;
        v_itens := v_itens || jsonb_build_object('linha', coalesce((v_linha->>'linha')::int, v_n), 'status', 'importada',
          'motivo', null, 'pessoa', v_pessoa_status, 'plano', v_plano_status, 'contrato', v_contrato_status);
      exception
        when others then
          v_rej := v_rej + 1;
          -- contadores da linha rejeitada voltam (a linha inteira foi desfeita)
          if v_pessoa_status = 'nova' then v_pes_novas := v_pes_novas - 1; end if;
          if v_pessoa_status = 'existente' then v_pes_exist := v_pes_exist - 1; end if;
          if v_plano_status = 'novo' then v_pl_novos := v_pl_novos - 1; end if;
          v_motivo := case sqlstate
            when '22007' then 'Data inválida (use AAAA-MM-DD ou DD/MM/AAAA).'
            when '22008' then 'Data inválida (use AAAA-MM-DD ou DD/MM/AAAA).'
            when '22P02' then 'Valor ou número inválido.'
            when '23505' then 'Registro duplicado (nome ou documento já existe).'
            else regexp_replace(sqlerrm, '^\s+', '') end;
          v_itens := v_itens || jsonb_build_object('linha', coalesce((v_linha->>'linha')::int, v_n), 'status', 'rejeitada',
            'motivo', v_motivo, 'pessoa', null, 'plano', null, 'contrato', null);
      end;
      v_pessoa_id := null; v_plano_id := null; v_contrato_id := null;
    end loop;

    v_rel := jsonb_build_object(
      'simulado', p_simular, 'negocio', v_neg.nome, 'total', v_n,
      'importadas', v_ok, 'rejeitadas', v_rej, 'ignoradas', v_ign,
      'pessoas_novas', v_pes_novas, 'pessoas_existentes', v_pes_exist, 'planos_novos', v_pl_novos,
      'contratos_ativos', v_ct_ativos, 'contratos_encerrados', v_ct_enc,
      'linhas', v_itens);
    if p_simular then
      raise exception 'SIMULACAO' using errcode = 'P0999';
    end if;
  exception
    when sqlstate 'P0999' then
      null;  -- tudo desfeito; v_rel (variável local) permanece com o relatório
  end;
  return v_rel;
end;
$$;
