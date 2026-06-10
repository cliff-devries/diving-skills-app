-- =============================================
-- DIVING SKILLS — Migration v4: Three-Stage Skill Progression
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- If starting fresh, run supabase-setup.sql first, then this file.
-- Safe to re-run: columns/tables use IF NOT EXISTS, policies use DROP IF EXISTS.
-- =============================================


-- =============================================
-- 1. EXTEND skill_completions WITH THE 3-STAGE FIELDS
-- =============================================

ALTER TABLE public.skill_completions
  ADD COLUMN IF NOT EXISTS skill_attained     BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS skill_attained_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS skill_attained_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ready_for_test     BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ready_for_test_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ready_for_test_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS tested_and_passed  BOOLEAN NOT NULL DEFAULT FALSE;

-- Enforce stage ordering at the data level:
--   ready_for_test   requires skill_attained
--   tested_and_passed requires skill_attained AND ready_for_test
ALTER TABLE public.skill_completions
  DROP CONSTRAINT IF EXISTS skill_completions_stage_order_chk;

ALTER TABLE public.skill_completions
  ADD CONSTRAINT skill_completions_stage_order_chk
  CHECK (
    (NOT ready_for_test    OR skill_attained)
    AND
    (NOT tested_and_passed OR (skill_attained AND ready_for_test))
  );


-- =============================================
-- 2. CREATE skill_test_attempts TABLE
-- Full history of every test attempt. Never overwritten —
-- a retest inserts a new row.
-- =============================================

CREATE TABLE IF NOT EXISTS public.skill_test_attempts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_completion_id UUID NOT NULL REFERENCES public.skill_completions(id) ON DELETE CASCADE,
  diver_id            UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_id            INTEGER NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
  coach_id            UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  score               NUMERIC(3,1) NOT NULL,
  test_date           DATE NOT NULL DEFAULT CURRENT_DATE,
  notes               TEXT NOT NULL DEFAULT '',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT skill_test_attempts_score_range_chk
    CHECK (score >= 0 AND score <= 10),
  CONSTRAINT skill_test_attempts_score_increment_chk
    CHECK (MOD(score * 10, 5) = 0)
);

CREATE INDEX IF NOT EXISTS idx_test_attempts_completion ON public.skill_test_attempts(skill_completion_id);
CREATE INDEX IF NOT EXISTS idx_test_attempts_diver      ON public.skill_test_attempts(diver_id);
CREATE INDEX IF NOT EXISTS idx_test_attempts_skill      ON public.skill_test_attempts(skill_id);


-- =============================================
-- 3. ENABLE RLS + POLICIES ON skill_test_attempts
-- Mirrors skill_completions: diver reads own, coach manages
-- roster divers, parent reads linked diver.
-- =============================================

ALTER TABLE public.skill_test_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "skill_test_attempts: diver read own"            ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: coach manages roster"      ON public.skill_test_attempts;
DROP POLICY IF EXISTS "skill_test_attempts: parent reads linked diver" ON public.skill_test_attempts;

CREATE POLICY "skill_test_attempts: diver read own"
  ON public.skill_test_attempts FOR SELECT
  USING (auth.uid() = diver_id);

CREATE POLICY "skill_test_attempts: coach manages roster"
  ON public.skill_test_attempts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_test_attempts.diver_id
    )
  );

CREATE POLICY "skill_test_attempts: parent reads linked diver"
  ON public.skill_test_attempts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_test_attempts.diver_id
    )
  );


-- =============================================
-- 4. ENFORCE COACH-ONLY STAGES 2 & 3 ON skill_completions
-- Divers can freely write skill_attained (Stage 1, their own row),
-- but ready_for_test / tested_and_passed must only ever be set
-- by a coach. RLS row-level policies can't see *which* columns
-- changed, so a trigger locks those columns down for non-coaches.
-- =============================================

CREATE OR REPLACE FUNCTION public.enforce_skill_stage_permissions()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE auth_user_id = auth.uid();

  IF v_role IS DISTINCT FROM 'coach' THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.ready_for_test    := OLD.ready_for_test;
      NEW.ready_for_test_at := OLD.ready_for_test_at;
      NEW.ready_for_test_by := OLD.ready_for_test_by;
      NEW.tested_and_passed := OLD.tested_and_passed;
    ELSE
      NEW.ready_for_test    := FALSE;
      NEW.ready_for_test_at := NULL;
      NEW.ready_for_test_by := NULL;
      NEW.tested_and_passed := FALSE;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS skill_completions_enforce_stage_permissions ON public.skill_completions;
CREATE TRIGGER skill_completions_enforce_stage_permissions
  BEFORE INSERT OR UPDATE ON public.skill_completions
  FOR EACH ROW EXECUTE PROCEDURE public.enforce_skill_stage_permissions();
