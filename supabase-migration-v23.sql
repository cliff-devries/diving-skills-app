-- ============================================================
-- Migration v23 — Rebuild level_completions RLS from scratch
-- Run once in Supabase SQL editor.
-- Safe to re-run: all DROPs use IF EXISTS.
--
-- WHY: v22 split the old FOR ALL policy into explicit INSERT/UPDATE/DELETE
-- policies using the same roster.coach_id = auth.uid() pattern that works
-- for skill_completions. If v22 was not yet applied, the old FOR ALL policy
-- from v19 remains — known to silently fail on INSERT in some PG versions.
-- This migration drops every known policy name variant and recreates all
-- five policies (coach SELECT/INSERT/UPDATE/DELETE, diver SELECT, parent
-- SELECT) cleanly so there is no ambiguity.
--
-- auth.uid() vs profiles.id:
--   For coaches who signed up via the Supabase auth trigger, profiles.id is
--   set equal to auth_user_id which equals auth.uid() (see migration v3,
--   line: "Sets both id and auth_user_id = NEW.id for triggered profiles").
--   roster.coach_id stores profiles.id, so roster.coach_id = auth.uid()
--   is the correct check — matching the working skill_completions policies.
-- ============================================================


-- =============================================
-- 1. DROP ALL KNOWN POLICY NAMES
--    Covers names from v19, v22, and any variants.
-- =============================================

DROP POLICY IF EXISTS "level_completions: coach manages roster"  ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach insert roster"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach update roster"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach delete roster"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach select roster"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: diver read own"        ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: diver select own"      ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: parent reads linked"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: parent read linked"    ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach insert"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach update"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach select"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: diver read own"        ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: parent reads linked"   ON public.level_completions;


-- =============================================
-- 2. RECREATE ALL POLICIES EXPLICITLY
-- =============================================

-- Coaches can SELECT level_completions for divers on their roster.
CREATE POLICY "level_completions: coach select"
  ON public.level_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

-- Coaches can INSERT level_completions for divers on their roster.
CREATE POLICY "level_completions: coach insert"
  ON public.level_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

-- Coaches can UPDATE level_completions for divers on their roster.
CREATE POLICY "level_completions: coach update"
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

-- Coaches can DELETE level_completions for divers on their roster.
CREATE POLICY "level_completions: coach delete"
  ON public.level_completions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

-- Divers can read their own level_completions.
CREATE POLICY "level_completions: diver read own"
  ON public.level_completions FOR SELECT
  USING (auth.uid() = diver_id);

-- Parents can read level_completions for their linked diver.
CREATE POLICY "level_completions: parent reads linked"
  ON public.level_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = level_completions.diver_id
    )
  );
