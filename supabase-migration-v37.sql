-- =============================================
-- DIVING SKILLS — Migration v37: Parent self-report (family account model)
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- Background: the app is moving to a single family account model — divers
-- never get their own Supabase auth account, parents log in on their
-- behalf. Parents therefore need write access to their linked diver's
-- skill_completions that they never needed before:
--   Stage 1 (skill_attained)  — parents already could do this for divers.
--   Stage 2 (ready_for_test)  — NEW: parents can now also mark this.
-- Stage 3 (tested_and_passed) remains coach-only; testing.html and
-- skill_test_attempts are unaffected by this migration.
--
-- What this does:
--   1. Adds parent INSERT/UPDATE RLS policies on skill_completions, scoped
--      to the diver they're linked to via parent_diver (mirrors the
--      existing "parent select linked diver" SELECT policy from v5).
--   2. Updates enforce_skill_stage_permissions() (from v4) so the
--      ready_for_test columns are also writable by role = 'parent', not
--      just 'coach'. tested_and_passed stays locked to coach-only for
--      every other role, parent included.
-- =============================================


-- =============================================
-- 1. PARENT WRITE ACCESS — skill_completions
-- =============================================

DROP POLICY IF EXISTS "skill_completions: parent insert linked diver" ON public.skill_completions;
CREATE POLICY "skill_completions: parent insert linked diver"
  ON public.skill_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_completions.diver_id
    )
  );

DROP POLICY IF EXISTS "skill_completions: parent update linked diver" ON public.skill_completions;
CREATE POLICY "skill_completions: parent update linked diver"
  ON public.skill_completions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_completions.diver_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_completions.diver_id
    )
  );


-- =============================================
-- 2. STAGE-COLUMN TRIGGER — allow parent to set ready_for_test
-- =============================================

CREATE OR REPLACE FUNCTION public.enforce_skill_stage_permissions()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE auth_user_id = auth.uid();

  -- Stage 3 (tested_and_passed) is coach-only, regardless of role.
  IF v_role IS DISTINCT FROM 'coach' THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.tested_and_passed := OLD.tested_and_passed;
    ELSE
      NEW.tested_and_passed := FALSE;
    END IF;
  END IF;

  -- Stage 2 (ready_for_test) is coach or parent (family account self-report).
  IF v_role NOT IN ('coach', 'parent') THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.ready_for_test    := OLD.ready_for_test;
      NEW.ready_for_test_at := OLD.ready_for_test_at;
      NEW.ready_for_test_by := OLD.ready_for_test_by;
    ELSE
      NEW.ready_for_test    := FALSE;
      NEW.ready_for_test_at := NULL;
      NEW.ready_for_test_by := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
-- Trigger already exists from v4 (BEFORE INSERT OR UPDATE ON skill_completions)
-- and points at this function by name, so no CREATE TRIGGER needed here.
