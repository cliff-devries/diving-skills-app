-- ============================================================
-- Migration v26 — Allow coaches to read other coach profiles
-- Run once in Supabase SQL editor.
-- Safe to re-run: uses DROP IF EXISTS / CREATE.
--
-- WHY: getTotalCoachCount() queries profiles WHERE role='coach'
-- AND status='active'. With RLS active, coaches could only see
-- their own profile row, so the count always returned 1 instead
-- of the true club-wide coach count.
--
-- FIX: Add a policy letting any active coach SELECT profiles
-- that also have role IN ('coach', 'super_user') and status='active'.
-- ============================================================

DROP POLICY IF EXISTS "profiles: coaches can read coach profiles" ON public.profiles;

CREATE POLICY "profiles: coaches can read coach profiles"
  ON public.profiles FOR SELECT
  USING (
    role IN ('coach', 'super_user')
    AND status = 'active'
    AND EXISTS (
      SELECT 1 FROM public.profiles self
      WHERE self.auth_user_id = auth.uid()
        AND self.role IN ('coach', 'super_user')
        AND self.status = 'active'
    )
  );
