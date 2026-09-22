-- =============================================================================
-- 0104 · Correção da 0103 — coluna "Cobertura" da Leveduca é maior do que 60
-- =============================================================================
-- A planilha real tem cobertura tipo "AC, AL, AM, AP, BA, CE, DF, ES, GO, MA,
-- MG, MS, MT, PA, PB, PE, PI, RJ, RN, RO, RR, SE, PS, TO" (94 caracteres) —
-- o limite de 60 rejeitava a importação. Sobe pra 150 (folga confortável).
-- =============================================================================

alter table public.parcerias drop constraint parcerias_cobertura_check;
alter table public.parcerias add constraint parcerias_cobertura_check check (cobertura is null or char_length(cobertura) <= 150);
