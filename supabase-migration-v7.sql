-- =============================================
-- DIVING SKILLS — Migration v7: Fix skill_test_attempts RLS for inserts
-- Run this ONCE in the Supabase SQL Editor.
-- Safe to re-run: all policies use DROP POLICY IF EXISTS.
--
-- The skill_test_attempts policy section of supabase-migration-v5.sql did
-- not get applied — pg_policies still shows the old v4 policy set:
--   "skill_test_attempts: coach manages roster"  FOR ALL, USING only, no WITH CHECK
--   "skill_test_attempts: diver read own"        SELECT
--   "skill_test_attempts: parent reads linked diver" SELECT
--
-- This is the same FOR ALL / no-WITH-CHECK pattern that caused
-- "new row violates row-level security policy for table skill_completions"
-- before v5 — here it blocks the INSERT into skill_test_attempts when a
-- coach records a test attempt ("Tested and Passed").
--
-- FIX: replace with explicit SELECT (diver/coach/parent) and INSERT
-- (coach only) policies, matching the v5 pattern.
-- =============================================

DROP POLICY IF EXISTS "skill_test_attempts: diver read own"            ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: coach manages roster"      ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: parent reads linked diver" ON public.skill_test_attempts;

DROP POLICY IF EXISTS "skill_test_attempts: diver select own"          ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: coach select roster"       ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: coach insert roster"       ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: parent select linked diver" ON public.skill_test_attempts;

-- ---- SELECT ----

CREATE POLICY "skill_test_attempts: diver select own"
  ON public.skill_test_attempts FOR SELECT
  USING (auth.uid() = diver_id);

CREATE POLICY "skill_test_attempts: coach select roster"
  ON public.skill_test_attempts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_test_attempts.diver_id
    )
  );

CREATE POLICY "skill_test_attempts: parent select linked diver"
  ON public.skill_test_attempts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_test_attempts.diver_id
    )
  );

-- ---- INSERT ----

-- Coach only: record a test attempt for a diver on their roster.
CREATE POLICY "skill_test_attempts: coach insert roster"
  ON public.skill_test_attempts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_test_attempts.diver_id
    )
  );
