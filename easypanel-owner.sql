-- =============================================================================
-- DeskcommCRM en EasyPanel — crear la organización y promover al dueño.
--
-- ORDEN de instalación de la base (una sola vez, sobre tu proyecto Supabase):
--   1) Extensiones (este archivo, bloque de abajo) — ANTES del baseline.
--   2) Aplicar supabase/baseline.sql con psql (el schema completo).
--   3) Crear el usuario dueño en Supabase Dashboard:
--        Authentication › Users › Add user
--        - Email + Password
--        - "Auto Confirm User" = SÍ (marcado)
--   4) Ejecutar el bloque "OWNER" de abajo en el SQL Editor de Supabase,
--      cambiando el email por el del usuario que creaste.
--
-- Es idempotente: puedes correrlo de nuevo sin duplicar nada.
-- =============================================================================

-- ---- 1) EXTENSIONES (corre esto en el SQL Editor ANTES del baseline) --------
create extension if not exists vector  with schema public;
create extension if not exists citext  with schema public;
create extension if not exists pg_trgm with schema public;


-- ---- OWNER (corre esto DESPUÉS del baseline y de crear el usuario) ----------
-- Cambia el email por el del usuario dueño que creaste en Authentication.
do $$
declare
  v_owner_email text := 'dueno@tuempresa.com';   -- <<< CAMBIA ESTO
  v_org_name    text := 'Mi Empresa';            -- <<< nombre visible (opcional)
  v_locale      text := 'es';                    -- 'es' o 'pt-BR'
  v_uid uuid;
  v_org uuid;
begin
  select id into v_uid from auth.users where email = v_owner_email;
  if v_uid is null then
    raise exception 'No encontré % en auth.users. Créalo primero en Authentication › Users (Auto Confirm).', v_owner_email;
  end if;

  -- Organización (una sola, slug fijo 'minha-empresa' como en la instalación estándar).
  select id into v_org from public.organizations where slug = 'minha-empresa';
  if v_org is null then
    insert into public.organizations (slug, display_name, legal_name, locale, created_by)
    values ('minha-empresa', v_org_name, v_org_name, v_locale, v_uid)
    returning id into v_org;
  end if;

  -- El agente responde por OpenRouter: fija el proveedor (el trigger siembra
  -- 'anthropic' por defecto). El modelo se elige luego en Agente de IA › Provedores.
  update public.organizations
     set settings = jsonb_set(coalesce(settings, '{}'::jsonb), '{llm,provider}', to_jsonb('openrouter'::text), true)
   where id = v_org;

  -- Membresía como admin del tenant.
  insert into public.user_organizations (user_id, organization_id, role, accepted_at)
  values (v_uid, v_org, 'admin', now())
  on conflict (user_id, organization_id)
  do update set role = 'admin', revoked_at = null;

  -- Super-admin de plataforma (acceso a las pantallas /admin). MFA no forzado.
  insert into public.platform_admins (user_id, granted_by, scope, mfa_required, reason)
  values (v_uid, v_uid, 'full', false, 'Bootstrap self-host (dueño de la instancia)')
  on conflict (user_id) do nothing;

  raise notice 'Listo. Dueño % promovido. Org: %', v_owner_email, v_org;
end $$;
