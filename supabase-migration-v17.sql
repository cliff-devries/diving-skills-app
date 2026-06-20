-- =============================================
-- DIVING SKILLS — Migration v17: Coach self-signup flow
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Adds 'pending_coach' as an allowed value for the role column.
--   2. Creates RPC create_pending_coach_profile — called by coach-signup.html
--      immediately after auth.signUp() to create a pending profile row.
--   3. Creates RPC get_pending_coaches — coaches only, returns profiles
--      where role = 'pending_coach' and status = 'pending'.
--   4. Creates RPC approve_coach — sets role='coach', status='active'.
--   5. Creates RPC reject_coach — sets status='rejected'.
-- =============================================

-- =============================================
-- 1. EXTEND THE ROLE CONSTRAINT
-- =============================================

-- Drop the existing role CHECK constraint (created in supabase-setup.sql).
-- The constraint name varies by Postgres version; the DO block handles both
-- possible names safely.
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  SELECT constraint_name INTO v_constraint
  FROM information_schema.table_constraints
  WHERE table_schema = 'public'
    AND table_name   = 'profiles'
    AND constraint_type = 'CHECK'
    AND constraint_name LIKE '%role%'
  LIMIT 1;

  IF v_constraint IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.profiles DROP CONSTRAINT ' || quote_ident(v_constraint);
  END IF;
END;
$$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('coach', 'diver', 'parent', 'pending_coach'));

-- =============================================
-- 2. create_pending_coach_profile
--    Called right after auth.signUp() — the caller already has an active
--    session so auth.uid() is set. SECURITY DEFINER bypasses RLS.
-- =============================================
CREATE OR REPLACE FUNCTION public.create_pending_coach_profile(
  p_first_name TEXT,
  p_last_name  TEXT,
  p_email      TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  INSERT INTO public.profiles (
    auth_user_id,
    first_name,
    last_name,
    email,
    role,
    status
  ) VALUES (
    auth.uid(),
    TRIM(p_first_name),
    NULLIF(TRIM(COALESCE(p_last_name, '')), ''),
    LOWER(TRIM(p_email)),
    'pending_coach',
    'pending'
  )
  RETURNING id INTO v_profile_id;

  RETURN v_profile_id;
END;
$$;

-- =============================================
-- 3. get_pending_coaches
--    Coaches only — returns all pending coach requests.
-- =============================================
CREATE OR REPLACE FUNCTION public.get_pending_coaches()
RETURNS TABLE (
  id         UUID,
  first_name TEXT,
  last_name  TEXT,
  full_name  TEXT,
  email      TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid() AND role = 'coach'
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT p.id, p.first_name, p.last_name, p.full_name, p.email, p.created_at
  FROM public.profiles p
  WHERE p.role = 'pending_coach'
    AND p.status = 'pending'
  ORDER BY p.created_at ASC;
END;
$$;

-- =============================================
-- 4. approve_coach
--    Sets role='coach' and status='active' for a pending coach.
-- =============================================
CREATE OR REPLACE FUNCTION public.approve_coach(p_profile_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid() AND role = 'coach'
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.profiles
  SET role = 'coach', status = 'active'
  WHERE id = p_profile_id AND role = 'pending_coach';
END;
$$;

-- =============================================
-- 5. reject_coach
--    Sets status='rejected' for a pending coach (does not delete auth account).
-- =============================================
CREATE OR REPLACE FUNCTION public.reject_coach(p_profile_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid() AND role = 'coach'
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.profiles
  SET status = 'rejected'
  WHERE id = p_profile_id AND role = 'pending_coach';
END;
$$;
