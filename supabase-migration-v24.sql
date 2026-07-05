-- ============================================================
-- Migration v24 — Allow any active coach to access any diver's data
-- Run once in Supabase SQL editor.
-- Safe to re-run: all operations use IF EXISTS / DROP+CREATE.
--
-- WHY: Previously coaches could only read/write skill_completions,
-- skill_test_attempts, and level_completions for divers on their
-- specific roster. The app now shows all club divers to all coaches,
-- so any coach must be able to run testing sessions and view progress
-- for any diver regardless of roster assignment.
--
-- WHAT CHANGES:
--   skill_completions:   roster-restricted coach policies → any-coach policies
--   skill_test_attempts: same
--   level_completions:   same (replaces v23 roster-restricted policies)
--
-- WHAT DOES NOT CHANGE:
--   profiles: already has "authenticated lookup by email" policy that
--     allows any authenticated user to SELECT any diver profile, so
--     getAllDivers() works without changes here.
--   getRoster(coachId): still used for the "My Divers" metric on the
--     coach dashboard — roster table and its RLS are unchanged.
--
-- Coach identity check used in all new policies:
--   EXISTS (SELECT 1 FROM public.profiles
--           WHERE id = auth.uid()
--             AND role IN ('coach', 'super_user')
--             AND status = 'active')
--   This works because coach profiles.id = auth.uid() (established in
--   migration v3: triggered profiles set id = auth_user_id = auth.uid()).
-- ============================================================


-- =============================================
-- 1. SKILL_COMPLETIONS
-- =============================================

DROP POLICY IF EXISTS "skill_completions: coach select roster"   ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach insert roster"   ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach update roster"   ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: any coach select"      ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: any coach insert"      ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: any coach update"      ON public.skill_completions;

CREATE POLICY "skill_completions: any coach select"
  ON public.skill_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "skill_completions: any coach insert"
  ON public.skill_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "skill_completions: any coach update"
  ON public.skill_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );


-- =============================================
-- 2. SKILL_TEST_ATTEMPTS
-- =============================================

DROP POLICY IF EXISTS "skill_test_attempts: coach select roster"  ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: coach insert roster"  ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: any coach select"     ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: any coach insert"     ON public.skill_test_attempts;

CREATE POLICY "skill_test_attempts: any coach select"
  ON public.skill_test_attempts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "skill_test_attempts: any coach insert"
  ON public.skill_test_attempts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );


-- =============================================
-- 3. LEVEL_COMPLETIONS
--    Replaces v23's roster-restricted policies with any-coach policies.
-- =============================================

DROP POLICY IF EXISTS "level_completions: coach select"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach insert"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach update"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach delete"          ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: any coach select"      ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: any coach insert"      ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: any coach update"      ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: any coach delete"      ON public.level_completions;

CREATE POLICY "level_completions: any coach select"
  ON public.level_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "level_completions: any coach insert"
  ON public.level_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "level_completions: any coach update"
  ON public.level_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "level_completions: any coach delete"
  ON public.level_completions FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );
