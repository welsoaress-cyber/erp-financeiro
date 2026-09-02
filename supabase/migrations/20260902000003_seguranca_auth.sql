-- =============================================================================
-- ERP Financeiro Pessoal — Migration 0003: AUDITORIA DE AUTENTICAÇÃO
-- Registra em public.auditoria: login bem-sucedido, troca de e-mail e troca de
-- senha. Nunca grava hash de senha. Tentativas FALHAS de login não passam pelo
-- banco (são rejeitadas pelo Supabase Auth) e ficam nos Auth Logs do painel.
-- =============================================================================

alter table public.auditoria drop constraint if exists auditoria_acao_check;
alter table public.auditoria add constraint auditoria_acao_check
  check (acao in ('INSERT', 'UPDATE', 'DELETE', 'LOGIN'));

create or replace function public.tg_auditoria_auth_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org    uuid;
  v_antes  jsonb := '{}'::jsonb;
  v_depois jsonb := '{}'::jsonb;
  v_acao   text  := 'UPDATE';
begin
  if new.email is distinct from old.email then
    v_antes  := v_antes  || jsonb_build_object('email', old.email);
    v_depois := v_depois || jsonb_build_object('email', new.email);
  end if;
  if new.encrypted_password is distinct from old.encrypted_password then
    v_depois := v_depois || jsonb_build_object('senha_alterada', true);
  end if;
  if new.last_sign_in_at is distinct from old.last_sign_in_at and new.last_sign_in_at is not null then
    v_acao   := 'LOGIN';
    v_depois := v_depois || jsonb_build_object('em', new.last_sign_in_at);
  end if;
  if v_depois = '{}'::jsonb then
    return new;
  end if;

  select organizacao_id into v_org
  from public.organizacao_membros
  where usuario_id = new.id
  order by (papel = 'proprietario') desc, criado_em
  limit 1;

  insert into public.auditoria (organizacao_id, tabela, registro_id, acao, dados_antes, dados_depois, usuario_id)
  values (v_org, 'auth.users', new.id::text, v_acao, nullif(v_antes, '{}'::jsonb), v_depois, new.id);
  return new;
end;
$$;

revoke all on function public.tg_auditoria_auth_usuario() from public, anon, authenticated;

create trigger on_auth_user_updated
  after update of email, encrypted_password, last_sign_in_at on auth.users
  for each row execute function public.tg_auditoria_auth_usuario();
