-- =============================================
-- DIVING SKILLS — Migration v18: Fix handle_new_user trigger for coach signup
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- Safe to re-run: all statements are idempotent.
--
-- Root cause: the handle_new_user trigger (last updated in v3) reads
-- raw_user_meta_data->>'role' to set the profile role. The coach self-signup
-- flow (coach-signup.html) passes requested_role = 'coach', NOT role = 'coach',
-- so the trigger falls back to 'diver' and creates a diver/active profile
-- immediately on signUp() — before auth.js can intercept it.
--
-- What this does:
--   1. Updates handle_new_user to also check requested_role, and maps
--      requested_role = 'coach' → role = 'pending_coach', status = 'pending'.
--      Also populates first_name / last_name from signup metadata.
--   2. Fixes any existing profiles that were created as 'diver' for users
--      whose auth metadata has requested_role = 'coach'.
-- =============================================

-- =============================================
-- 1. UPDATE handle_new_user TRIGGER FUNCTION
-- =============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_requested_role TEXT;
  v_role           TEXT;
  v_status         TEXT;
  v_first_name     TEXT;
  v_last_name      TEXT;
  v_full_name      TEXT;
BEGIN
  -- Divers signing up to claim an existing profile skip auto-creation.
  -- The claim approval flow links their auth account to the existing profile.
  IF COALESCE(NEW.raw_user_meta_data->>'claiming', 'false') = 'true' THEN
    RETURN NEW;
  END IF;

  -- Coach self-signup passes requested_role = 'coach'.
  -- Legacy/invite flows may pass role directly. Fall back to 'diver'.
  v_requested_role := COALESCE(
    NULLIF(TRIM(NEW.raw_user_meta_data->>'requested_role'), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'role'), ''),
    'diver'
  );

  IF v_requested_role = 'coach' THEN
    v_role   := 'pending_coach';
    v_status := 'pending';
  ELSE
    v_role   := v_requested_role;
    v_status := 'active';
  END IF;

  -- Build name: prefer explicit first/last from coach signup metadata,
  -- fall back to full_name, then empty string.
  v_first_name := NULLIF(TRIM(COALESCE(NEW.raw_user_meta_data->>'first_name', '')), '');
  v_last_name  := NULLIF(TRIM(COALESCE(NEW.raw_user_meta_data->>'last_name',  '')), '');
  v_full_name  := TRIM(COALESCE(
    NULLIF(TRIM(CONCAT_WS(' ', v_first_name, v_last_name)), ''),
    NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
    ''
  ));

  INSERT INTO public.profiles (
    id, auth_user_id, email,
    full_name, first_name, last_name,
    role, status
  ) VALUES (
    NEW.id, NEW.id, NEW.email,
    v_full_name, v_first_name, v_last_name,
    v_role, v_status
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- =============================================
-- 2. FIX EXISTING PROFILES
--    Update any profile that was created as 'diver' for an auth user
--    whose signup metadata has requested_role = 'coach'.
--    Also backfills first_name / last_name from metadata if missing.
-- =============================================

UPDATE public.profiles p
SET
  role       = 'pending_coach',
  status     = 'pending',
  first_name = COALESCE(
    p.first_name,
    NULLIF(TRIM(COALESCE(u.raw_user_meta_data->>'first_name', '')), '')
  ),
  last_name  = COALESCE(
    p.last_name,
    NULLIF(TRIM(COALESCE(u.raw_user_meta_data->>'last_name', '')), '')
  ),
  full_name  = CASE
    WHEN p.full_name IS NOT NULL AND p.full_name <> '' THEN p.full_name
    ELSE TRIM(CONCAT_WS(' ',
      NULLIF(TRIM(COALESCE(u.raw_user_meta_data->>'first_name', '')), ''),
      NULLIF(TRIM(COALESCE(u.raw_user_meta_data->>'last_name',  '')), '')
    ))
  END
FROM auth.users u
WHERE p.auth_user_id = u.id
  AND u.raw_user_meta_data->>'requested_role' = 'coach'
  AND p.role = 'diver';
