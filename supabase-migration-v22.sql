-- ============================================================
-- Migration v22 — Fix level_completions upsert reliability
-- Run once in Supabase SQL editor.
-- Safe to re-run: all operations use IF EXISTS / IF NOT EXISTS.
--
-- What this does:
--   1. Ensures a NAMED unique constraint on (diver_id, level) so that
--      Supabase upsert onConflict targeting is unambiguous. If the
--      inline UNIQUE from v19 exists under its auto-generated name,
--      it is dropped and replaced with the explicit name.
--   2. Recreates the coach INSERT/UPDATE RLS policy, splitting FOR ALL
--      into explicit INSERT + UPDATE policies to avoid any edge-case
--      where PostgreSQL evaluates USING against a non-existent row on
--      INSERT (some PG versions do this for FOR ALL policies).
-- ============================================================

-- =============================================
-- 1. NAMED UNIQUE CONSTRAINT
-- =============================================

-- Drop the auto-generated name from v19's inline UNIQUE (safe no-op if absent).
ALTER TABLE public.level_completions
  DROP CONSTRAINT IF EXISTS "level_completions_diver_id_level_key";

-- Drop any prior attempt at a named version (makes re-runs safe).
ALTER TABLE public.level_completions
  DROP CONSTRAINT IF EXISTS "level_completions_diver_level_unique";

-- Add the explicitly named constraint.
ALTER TABLE public.level_completions
  ADD CONSTRAINT "level_completions_diver_level_unique" UNIQUE (diver_id, level);


-- =============================================
-- 2. EXPLICIT INSERT + UPDATE POLICIES
--    Replace the single FOR ALL policy with separate INSERT and UPDATE
--    policies so each operation is governed by exactly the right clause.
-- =============================================

DROP POLICY IF EXISTS "level_completions: coach manages roster"         ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach insert roster"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach update roster"          ON public.level_completions;

-- INSERT: WITH CHECK verifies coach-diver roster membership.
CREATE POLICY "level_completions: coach insert roster"
  ON public.level_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

-- UPDATE: USING gates which existing rows the coach can see/update;
-- WITH CHECK confirms the updated values still satisfy the roster check.
CREATE POLICY "level_completions: coach update roster"
  ON public.level_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

-- DELETE (coaches can clean up if needed, same roster check).
DROP POLICY IF EXISTS "level_completions: coach delete roster"          ON public.level_completions;
CREATE POLICY "level_completions: coach delete roster"
  ON public.level_completions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );
