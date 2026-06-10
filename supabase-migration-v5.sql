-- =============================================
-- DIVING SKILLS — Migration v5: Fix skill_completions RLS for upserts
-- Run this ONCE in the Supabase SQL Editor on an existing database
-- (after supabase-setup.sql and supabase-migration-v4.sql).
-- Safe to re-run: all policies use DROP POLICY IF EXISTS.
--
-- PROBLEM: the old "coach manages roster" / "skill_test_attempts: coach
-- manages roster" policies are FOR ALL with only a USING clause and no
-- explicit WITH CHECK. When a coach upserts a skill_completions row that
-- doesn't exist yet (e.g. marking "Ready for Test" for the first time),
-- Postgres has to evaluate an INSERT-time WITH CHECK — relying on the
-- implicit USING fallback here was producing
-- "new row violates row-level security policy for table skill_completions".
--
-- FIX: replace the FOR ALL policies with explicit SELECT / INSERT / UPDATE
-- policies per role, each with its own WITH CHECK where needed.
-- =============================================


-- =============================================
-- 1. skill_completions
-- =============================================

DROP POLICY IF EXISTS "skill_completions: diver read own"        ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver insert"           ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver update own"       ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach manages roster"   ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: parent reads linked diver" ON public.skill_completions;

-- Also drop the new-style names in case this migration is re-run.
DROP POLICY IF EXISTS "skill_completions: diver select own"       ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver insert own"       ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver update own"       ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach select roster"    ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach insert roster"    ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach update roster"    ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: parent select linked diver" ON public.skill_completions;

-- ---- SELECT ----

-- Diver: read own rows.
CREATE POLICY "skill_completions: diver select own"
  ON public.skill_completions FOR SELECT
  USING (auth.uid() = diver_id);

-- Coach: read rows for any diver on their roster.
CREATE POLICY "skill_completions: coach select roster"
  ON public.skill_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_completions.diver_id
    )
  );

-- Parent: read rows for their linked diver only.
CREATE POLICY "skill_completions: parent select linked diver"
  ON public.skill_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_completions.diver_id
    )
  );

-- ---- INSERT ----

-- Diver: create their own row (Stage 1 only — Stage 2/3 fields are
-- forced back to false/NULL by enforce_skill_stage_permissions()).
CREATE POLICY "skill_completions: diver insert own"
  ON public.skill_completions FOR INSERT
  WITH CHECK (auth.uid() = diver_id);

-- Coach: create a row for any diver on their roster.
CREATE POLICY "skill_completions: coach insert roster"
  ON public.skill_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_completions.diver_id
    )
  );

-- ---- UPDATE ----

-- Diver: update their own row (Stage 1 only — Stage 2/3 fields are
-- protected by enforce_skill_stage_permissions()).
CREATE POLICY "skill_completions: diver update own"
  ON public.skill_completions FOR UPDATE
  USING (auth.uid() = diver_id)
  WITH CHECK (auth.uid() = diver_id);

-- Coach: update any row for a diver on their roster.
CREATE POLICY "skill_completions: coach update roster"
  ON public.skill_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_completions.diver_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_completions.diver_id
    )
  );


-- =============================================
-- 2. skill_test_attempts
-- Same FOR ALL / no-WITH-CHECK issue would hit "Tested and Passed"
-- (recordTestAttempt inserts here). Replace with explicit policies too.
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
