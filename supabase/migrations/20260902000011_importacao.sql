-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0011: IMPORTAÇÃO DE CLIENTES POR CSV (Etapa 6D)
-- Uma única RPC recebe as linhas já lidas do CSV (jsonb), valida, cria planos,
-- pessoas, vínculos e contratos do negócio informado e devolve um relatório.
-- Sem tabela nova: a importação usa os cadastros existentes e passa pelos mesmos
-- triggers/regras de sempre. Simulação = mesmo caminho, desfeito no final.
-- =============================================================================

-- Nome de plano vindo do sistema legado → nome de catálogo.
-- "Velocidade_0100_MB" → "Plano 100 Mbps"; qualquer outro nome é só limpo.
create or replace function public.nome_plano_importado(p_nome text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_nome ~* '^\s*velocidade[_ ]0*(\d+)[_ ]?mb\s*$'
      then 'Plano ' || (regexp_match(p_nome, '^\s*velocidade[_ ]0*(\d+)[_ ]?mb\s*$', 'i'))[1] || ' Mbps'
    else nullif(regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g'), '')
  end;
$$;
comment on function public.nome_plano_importado(text) is 'Normaliza o nome do plano do CSV legado (Velocidade_0100_MB → Plano 100 Mbps).';

-- Data do CSV: aceita AAAA-MM-DD e DD/MM/AAAA (com ou sem hora). Nunca interpreta como MM/DD.
create or replace function public.data_importada(p_texto text)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare t text := btrim(coalesce(p_texto, ''));
begin
  if t = '' then return null; end if;
  if t ~ '^\d{4}-\d{2}-\d{2}' then return left(t, 10)::date; end if;
  if t ~ '^\d{1,2}/\d{1,2}/\d{4}' then return to_date(split_part(t, ' ', 1), 'DD/MM/YYYY'); end if;
  raise exception 'Data inválida (use AAAA-MM-DD ou DD/MM/AAAA).' using errcode = 'invalid_datetime_format';
end;
$$;

-- -----------------------------------------------------------------------------
-- importar_clientes(negócio, linhas, simular, faturar_desde)
-- linhas: [{ "linha": 2, "nome": "...", "documento": "...", "telefone": "...",
--            "email": "...", "plano": "...", "valor": "99,90", "dia_vencimento": 10,
--            "data_inicio": "2024-01-15", "data_fim": null }, ...]
-- Retorna jsonb com totais e o resultado linha a linha.
-- p_simular = true: executa tudo e desfaz (relatório idêntico ao da importação real).
-- p_faturar_desde: data a partir da qual o faturamento automático gera cobranças
--   dos contratos ativos importados (nulo = início do contrato).
-- -----------------------------------------------------------------------------
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
  v_valor numeric(14,2); v_dia int; v_ini date; v_fim date;
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
        v_plano_nome := public.nome_plano_importado(v_linha->>'plano');
        v_valor := nullif(replace(regexp_replace(coalesce(v_linha->>'valor', ''), '[^0-9,.\-]', '', 'g'), ',', '.'), '')::numeric;
        v_dia   := nullif(regexp_replace(coalesce(v_linha->>'dia_vencimento', ''), '[^0-9]', '', 'g'), '')::int;
        v_ini   := public.data_importada(v_linha->>'data_inicio');
        v_fim   := public.data_importada(v_linha->>'data_fim');

        -- validações (mensagens curtas para o relatório)
        if v_nome is null or char_length(v_nome) < 2 then
          raise exception 'Nome obrigatório (mínimo 2 caracteres).';
        end if;
        if char_length(v_nome) > 120 then v_nome := left(v_nome, 120); end if;
        if v_doc is null then raise exception 'CPF/CNPJ obrigatório.'; end if;
        if not public.documento_valido(v_doc) then raise exception 'CPF/CNPJ inválido.'; end if;
        if v_tel is null then raise exception 'Telefone obrigatório.'; end if;
        if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Telefone inválido (use DDD + número).'; end if;
        if v_email is not null and (v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 120) then
          raise exception 'E-mail inválido.';
        end if;
        if v_plano_nome is null then raise exception 'Plano obrigatório.'; end if;
        if char_length(v_plano_nome) > 80 then raise exception 'Nome do plano muito longo (máximo 80).'; end if;
        if v_valor is not null and v_valor < 0 then raise exception 'Valor não pode ser negativo.'; end if;
        if v_dia is null then raise exception 'Dia de vencimento obrigatório.'; end if;
        if v_dia < 1 or v_dia > 31 then raise exception 'Dia de vencimento deve estar entre 1 e 31.'; end if;
        if v_ini is null then raise exception 'Data de início obrigatória.'; end if;
        if v_fim is not null and v_fim < v_ini then raise exception 'Data de cancelamento anterior ao início.'; end if;
        -- linha repetida dentro do próprio arquivo (mesmo documento, plano e início)
        if exists (
          select 1 from jsonb_array_elements(p_linhas) with ordinality as a(l, i)
          where i < v_n
            and regexp_replace(coalesce(a.l->>'documento', ''), '[^0-9]', '', 'g') = v_doc
            and public.nome_plano_importado(a.l->>'plano') = v_plano_nome
            and public.data_importada(a.l->>'data_inicio') = v_ini
        ) then
          raise exception 'Linha repetida no arquivo (mesmo CPF/CNPJ, plano e início).';
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
          values (v_org, p_negocio_id, v_plano_nome, coalesce(v_valor, 0), 'mensal')
          returning id into v_plano_id;
          v_plano_status := 'novo'; v_pl_novos := v_pl_novos + 1;
        end if;
        if v_valor is null then
          select valor_tabela into v_valor from public.planos where id = v_plano_id;
        end if;

        -- pessoa: reaproveita pelo documento (nunca duplica) ou cria
        select id into v_pessoa_id from public.pessoas where organizacao_id = v_org and documento = v_doc;
        if found then
          v_pessoa_status := 'existente'; v_pes_exist := v_pes_exist + 1;
          if not (select ativo from public.pessoas where id = v_pessoa_id) then
            raise exception 'Pessoa com este CPF/CNPJ está inativa.';
          end if;
        else
          insert into public.pessoas (organizacao_id, tipo, nome, documento, telefone, email)
          values (v_org, (case when char_length(v_doc) = 14 then 'juridica' else 'fisica' end)::public.tipo_pessoa, v_nome, v_doc, v_tel, v_email)
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
                                      data_inicio, dia_vencimento, faturamento_automatico, faturar_desde)
        values (v_org, p_negocio_id, v_pessoa_id, v_plano_id, v_valor, 'mensal',
                v_ini, v_dia, v_fim is null, case when v_fim is null then greatest(coalesce(p_faturar_desde, v_ini), v_ini) else v_ini end)
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
comment on function public.importar_clientes(uuid, jsonb, boolean, date) is
  'Importa clientes/planos/contratos de um CSV já lido (jsonb). Simulação executa e desfaz. Relatório linha a linha.';

revoke all on function public.data_importada(text) from public, anon;
grant execute on function public.data_importada(text) to authenticated;
revoke all on function public.nome_plano_importado(text) from public, anon;
grant execute on function public.nome_plano_importado(text) to authenticated;
revoke all on function public.importar_clientes(uuid, jsonb, boolean, date) from public, anon;
grant execute on function public.importar_clientes(uuid, jsonb, boolean, date) to authenticated;
