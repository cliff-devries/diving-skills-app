-- =============================================
-- DIVING SKILLS — Migration v17: Coach self-signup flow
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- Safe to re-run: all statements are idempotent.
--
-- What this does:
--   1. Adds 'pending_coach' as an allowed value for the role column.
--   2. Adds an RLS INSERT policy so a newly signed-up user can insert
--      their own pending_coach profile row (direct table insert from JS,
--      no RPC required; works when email confirmation is disabled).
--   3. Creates RPC get_pending_coaches — coaches only, returns profiles
--      where role = 'pending_coach' and status = 'pending'.
--   4. Creates RPC approve_coach — sets role='coach', status='active'.
--   5. Creates RPC reject_coach — sets status='rejected'.
-- =============================================

-- =============================================
-- 1. EXTEND THE ROLE CONSTRAINT
-- =============================================

-- Drop the existing role CHECK constraint so we can replace it.
-- The name varies by Postgres version; this DO block finds it safely.
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
-- 2. RLS INSERT POLICY — pending coach self-signup
--    Allows a newly authenticated user (session established immediately
--    after auth.signUp() when email confirmation is disabled) to insert
--    exactly one profile row tied to their own auth UID, with role locked
--    to 'pending_coach' and status locked to 'pending'.
-- =============================================

DROP POLICY IF EXISTS "profiles: pending_coach self-insert" ON public.profiles;

CREATE POLICY "profiles: pending_coach self-insert"
  ON public.profiles
  FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND auth.uid() = auth_user_id
    AND role = 'pending_coach'
    AND status = 'pending'
  );

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
