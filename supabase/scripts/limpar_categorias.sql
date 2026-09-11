-- =============================================================================
-- APAGAR AS CATEGORIAS do Financeiro para recadastrar do zero
-- (rodar no SQL Editor como proprietário).
--
-- ⚠️ ANTES DE RODAR: gere um backup (GitHub → Actions → backup-banco).
--
-- APAGA: todas as categorias (e subcategorias) que NÃO estão em uso.
-- FICA:  categoria usada por algum lançamento não é apagada (apagar quebraria
--        o histórico) — ela aparece no resultado como "em uso"; renomeie ou
--        desative pela tela se quiser.
-- ATENÇÃO: negócios que usavam uma categoria apagada como padrão de
--        receita/despesa ficam SEM padrão — reconfigure em Negócios antes do
--        próximo faturamento automático.
-- Tudo ou nada por categoria (as que não podem sair, ficam).
-- =============================================================================
begin;

do $$
declare r record; v_apagadas int := 0; v_ficaram int := 0;
begin
  alter table public.categorias disable trigger user;
  alter table public.negocios   disable trigger user;
  alter table public.carteira   disable trigger user;

  -- filhas primeiro, depois as raízes
  for r in
    select id, nome from public.categorias
    order by (categoria_pai_id is null), nome
  loop
    begin
      update public.negocios set categoria_receita_id = null where categoria_receita_id = r.id;
      update public.negocios set categoria_despesa_id = null where categoria_despesa_id = r.id;
      update public.carteira  set categoria_consumo_id = null where categoria_consumo_id = r.id;
      delete from public.categorias where id = r.id;
      v_apagadas := v_apagadas + 1;
    exception when foreign_key_violation then
      v_ficaram := v_ficaram + 1; -- em uso por lançamentos: fica
    end;
  end loop;

  alter table public.categorias enable trigger user;
  alter table public.negocios   enable trigger user;
  alter table public.carteira   enable trigger user;
  raise notice 'Concluído: % categorias apagadas · % ficaram (em uso por lançamentos).', v_apagadas, v_ficaram;
end $$;

commit;

-- Conferência: o que ficou (em uso) e negócios que precisam de novo padrão
select nome, tipo, natureza, 'em uso por lançamentos' as motivo
  from public.categorias order by tipo, nome;
select nome as negocio_sem_categoria_padrao
  from public.negocios
 where ativo and (categoria_receita_id is null or categoria_despesa_id is null)
 order by nome;
