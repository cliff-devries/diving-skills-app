-- ============================================================
-- Migration v26-fix — Emergency fix for infinite recursion in profiles RLS
-- Run IMMEDIATELY in Supabase SQL editor.
--
-- PROBLEM: v26 policy used EXISTS (SELECT 1 FROM public.profiles ...)
-- inside a policy ON public.profiles, causing infinite recursion.
--
-- FIX: Drop the broken policy. Create a SECURITY DEFINER helper function
-- that reads profiles bypassing RLS, then use it in a safe policy.
-- ============================================================

-- Step 1: Drop the broken policy immediately
DROP POLICY IF EXISTS "profiles: coaches can read coach profiles" ON public.profiles;

-- Step 2: Create a SECURITY DEFINER function — runs as DB owner, bypasses RLS,
-- so it can safely query profiles without triggering the policy recursion.
CREATE OR REPLACE FUNCTION public.is_active_coach()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  );
$$;

-- Step 3: Recreate the policy using the helper function (no self-reference)
DROP POLICY IF EXISTS "profiles: coaches can read coach profiles" ON public.profiles;

CREATE POLICY "profiles: coaches can read coach profiles"
  ON public.profiles FOR SELECT
  USING (
    role IN ('coach', 'super_user')
    AND status = 'active'
    AND public.is_active_coach()
  );
